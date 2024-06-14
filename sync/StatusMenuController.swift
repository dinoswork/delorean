import Cocoa
import UserNotifications

extension Notification.Name {
    static let backupDidStart = Notification.Name("backupDidStart")
    static let backupDidFinish = Notification.Name("backupDidFinish")
}

class StatusMenuController: NSObject {
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()
    
    // MARK: - Outlets
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var startBackupItem: NSMenuItem!
    @IBOutlet weak var abortBackupItem: NSMenuItem!
    @IBOutlet weak var backupInProgressItem: NSMenuItem!
    @IBOutlet weak var lastBackupItem: NSMenuItem!
    
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var isRunning: Bool = false
    var backupTask: Process?
    static let shared = StatusMenuController()
    
    // MARK: - Awake and Menu Setup
    override func awakeFromNib() {
        super.awakeFromNib()
        setupMenuIcon()
        setupInitialMenuState()
        
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidStart), name: .backupDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidFinish), name: .backupDidFinish, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(startBackupFromNotification(_:)), name: Notification.Name("StartBackup"), object: nil)
    }
    
    @objc func startBackupFromNotification(_ notification: Notification) {
        guard !isRunning else {
            print("DEBUG: Backup is already in progress.")
            notifyUser(title: "Process is still running", informativeText: "A backup process is already in progress.")
            return
        }
        
        if let task = backupTask, task.isRunning {
            print("DEBUG: Backup is already in progress (task.isRunning).")
            notifyUser(title: "Backup in Progress", informativeText: "A backup is already in progress. Please wait for it to complete.")
            return
        }
        
        if let scriptPath = notification.userInfo?["scriptPath"] as? String {
            isRunning = true
            NotificationCenter.default.post(name: .backupDidStart, object: nil)  // Notify that backup started
            backupTask = Process()
            backupTask?.launchPath = "/bin/bash"
            backupTask?.arguments = [scriptPath]
            
            backupTask?.terminationHandler = { [weak self] process in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    let success = process.terminationStatus == 0
                    print("DEBUG: Backup task terminated with success: \(success)")
                    
                    if success {
                        self.notifyUser(title: "Sync Completed", informativeText: "Your files have been successfully backed up.")
                    } else {
                        self.notifyUser(title: "Sync Failed", informativeText: "There was an issue with the backup process.")
                    }
                    
                    self.isRunning = false
                    NotificationCenter.default.post(name: .backupDidFinish, object: nil)  // Notify that backup finished
                }
            }
            
            do {
                print("DEBUG: Starting backup task.")
                try backupTask?.run()
            } catch {
                print("DEBUG: Failed to start the backup task.")
                notifyUser(title: "Error", informativeText: "Failed to start the backup process.")
                self.isRunning = false
                NotificationCenter.default.post(name: .backupDidFinish, object: nil)  // Notify that backup finished
            }
        }
    }
    
    @objc func backupDidStart() {
        print("DEBUG: Backup did start.")
        updateUIForBackupStart()
    }
    
    @objc func backupDidFinish() {
        print("DEBUG: Backup did finish.")
        updateUIForBackupEnd()
        updateLastBackupTime()  // Ensure the last backup time is updated
    }

    func setupMenuIcon() {
        let icon = NSImage(named: NSImage.refreshFreestandingTemplateName)
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.menu = statusMenu
    }
    
    func setupInitialMenuState() {
        startBackupItem.isHidden = false
        abortBackupItem.isHidden = true
        backupInProgressItem.isHidden = true
        backupInProgressItem.isEnabled = false
        updateLastBackupTime()
        lastBackupItem.isEnabled = false  // Make last backup item non-interactive
        lastBackupItem.isHidden = isRunning  // Hide last backup item if backup is in progress
    }
    
    // MARK: - Actions
    @IBAction func startBackupClicked(_ sender: NSMenuItem) {
        guard !isRunning else {
            print("DEBUG: Start backup clicked but process is still running.")
            notifyUser(title: "Process is still running", informativeText: "A backup process is already in progress.")
            return
        }
        
        NotificationCenter.default.post(name: Notification.Name("StartBackup"), object: nil, userInfo: ["scriptPath": Bundle.main.path(forResource: "sync_files", ofType: "sh")!])
    }
    
    @IBAction func abortBackupClicked(_ sender: NSMenuItem) {
        guard let task = backupTask, isRunning else {
            print("DEBUG: Abort backup clicked but no backup is currently in progress.")
            notifyUser(title: "Abort Ignored", informativeText: "No backup is currently in progress.")
            return
        }
        
        task.terminate()
        isRunning = false
        NotificationCenter.default.post(name: .backupDidFinish, object: nil)  // Notify that backup finished
        notifyUser(title: "Backup Aborted", informativeText: "The backup process has been cancelled.")
    }
    
    func notifyUser(title: String, informativeText: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = informativeText
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("DEBUG: Error posting notification: \(error.localizedDescription)")
            }
        }
    }
    
    @IBAction func quitClicked(sender: NSMenuItem) {
        if isRunning && !closeDialog() {
            return
        }
        NSApplication.shared.terminate(self)
    }
    
    func closeDialog() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Sync is running"
        alert.informativeText = "It appears a process is still running."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close anyway")
        alert.addButton(withTitle: "Cancel")
        
        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            if let task = backupTask {
                task.terminate()
            }
            return true
        }
        return false
    }

    func updateUIForBackupStart() {
        DispatchQueue.main.async {
            print("DEBUG: Updating UI for backup start.")
            self.isRunning = true
            self.startBackupItem.isHidden = true
            self.abortBackupItem.isHidden = false
            self.abortBackupItem.isEnabled = true
            self.backupInProgressItem.isHidden = false
            self.lastBackupItem.isHidden = true  // Hide last backup item during backup
        }
    }

    func updateUIForBackupEnd() {
        DispatchQueue.main.async {
            print("DEBUG: Updating UI for backup end.")
            self.isRunning = false
            self.setupInitialMenuState()
        }
    }

//    func updateBackupLog(success: Bool) {
//        print("DEBUG: Updating backup log with success: \(success)")
//        let logPath = "\(NSHomeDirectory())/delorean.log"
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
//        let logEntry = "\(dateFormatter.string(from: Date())) - \(success ? "Backup completed successfully" : "Backup Failed: User aborted backup")\n"
//        
//        do {
//            if FileManager.default.fileExists(atPath: logPath) {
//                let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
//                fileHandle.seekToEndOfFile()
//                fileHandle.write(logEntry.data(using: .utf8)!)
//                fileHandle.closeFile()
//            } else {
//                try logEntry.write(toFile: logPath, atomically: true, encoding: .utf8)
//            }
//        } catch {
//            print("DEBUG: Failed to write to log file: \(error)")
//        }
//    }
    
    func updateLastBackupTime() {
        guard let lastBackupItem = lastBackupItem else {
            print("DEBUG: lastBackupItem is not connected")
            return
        }
        
        let logPath = "\(NSHomeDirectory())/delorean.log"

        if !FileManager.default.fileExists(atPath: logPath) {
            // Create the log file if it doesn't exist
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
        }
        
        do {
            let logContent = try String(contentsOfFile: logPath, encoding: .utf8)
            if let lastEntry = logContent.components(separatedBy: "\n").filter({ !$0.isEmpty }).last {
                lastBackupItem.title = "Last Backup: \(lastEntry)"
            } else {
                lastBackupItem.title = "Last Backup: N/A"
            }
        } catch {
            lastBackupItem.title = "Last Backup: N/A"
            print("DEBUG: Failed to read log file: \(error)")
        }
        lastBackupItem.isEnabled = false  // Make last backup item non-interactive
    }
}
