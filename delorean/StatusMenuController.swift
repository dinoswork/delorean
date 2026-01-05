import Cocoa
import UserNotifications
import QuartzCore

extension Notification.Name {
    static let backupDidStart = Notification.Name("backupDidStart")
    static let backupDidFinish = Notification.Name("backupDidFinish")
    static let StartBackup = Notification.Name("StartBackup")
    static let requestManualBackup = Notification.Name("requestManualBackup")
    static let updateLastBackupDisplay = Notification.Name("updateLastBackupDisplay")
    static let logAbort = Notification.Name("logAbort")
}
 
class StatusMenuController: NSObject {
    
    // MARK: - Outlets
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var startBackupItem: NSMenuItem!
    @IBOutlet weak var abortBackupItem: NSMenuItem!
    @IBOutlet weak var backupInProgressItem: NSMenuItem!
    @IBOutlet weak var lastBackupItem: NSMenuItem!
    private var originalIcon: NSImage?
    
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var isRunning: Bool = false
    var backupTask: Process?
    var isUserInitiatedAbort: Bool = false
    
    static let shared = StatusMenuController()
    
    // MARK: - Awake and Menu Setup
    override func awakeFromNib() {
        super.awakeFromNib()
        setupMenuIcon()
        updateUIForStateChange()
        
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidStart), name: .backupDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidFinish), name: .backupDidFinish, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(startBackupFromNotification(_:)), name: .StartBackup, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleUpdateLastBackupDisplay(_:)), name: .updateLastBackupDisplay, object: nil)
    }
    
    func setupMenuIcon() {
        let icon = NSImage(named: NSImage.refreshFreestandingTemplateName)
        icon?.isTemplate = true
        originalIcon = icon?.copy() as? NSImage // Store original
        statusItem.button?.image = icon
        statusItem.menu = statusMenu
    }
    
    func updateUIForStateChange() {
        DispatchQueue.main.async {
            self.startBackupItem.isHidden = self.isRunning
            self.abortBackupItem.isHidden = !self.isRunning
            self.backupInProgressItem.isHidden = !self.isRunning
            self.lastBackupItem.isHidden = self.isRunning
            
            self.backupInProgressItem.isEnabled = false
            self.lastBackupItem.isEnabled = false
        }
    }
    
    // MARK: - Notification Handlers
    @objc func startBackupFromNotification(_ notification: Notification) {
        guard !isRunning, let scriptPath = notification.userInfo?["scriptPath"] as? String else {
            return
        }
        
        NotificationCenter.default.post(name: .backupDidStart, object: nil)
        
        backupTask = Process()
        backupTask?.launchPath = "/bin/bash"
        backupTask?.arguments = [scriptPath]
        
        // Pass backup type to script via environment variable
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            let backupType = appDelegate.isManualBackup ? "manual" : "scheduled"
            
            // Get the current environment and ADD our variable to it
            var environment = ProcessInfo.processInfo.environment
            environment["BACKUP_TYPE"] = backupType
            backupTask?.environment = environment
        }
        
        backupTask?.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.isUserInitiatedAbort {
                    self.isUserInitiatedAbort = false
                } else {
                    let exitCode = process.terminationStatus
                    let isManual = (NSApplication.shared.delegate as? AppDelegate)?.isManualBackup ?? false
                    if exitCode == 0 {
                        // Perfect success
                        if isManual {
                            self.notifyUser(title: "Backup Completed",
                                            informativeText: "Your files have been successfully backed up.")
                        }
                    } else if exitCode == 2 {
                        // Success with warnings (only manual backups use this code)
                        self.notifyUser(title: "Backup Completed",
                                        informativeText: "Your files have been backed up, but some files could not be copied due to unsupported characters or length. Check delorean.log for details.")
                    } else {
                        // Real failure
                        self.notifyUser(title: "Backup Failed",
                                        informativeText: "There was an issue with the backup process.")
                    }
                    // Treat exit 2 as success for AppDelegate tracking
                    let success = (exitCode == 0 || exitCode == 2)
                    NotificationCenter.default.post(name: .backupDidFinish, object: nil, userInfo: ["success": success])
                    return
                }
                NotificationCenter.default.post(name: .backupDidFinish, object: nil)
            }
        }
        
        do {
            try backupTask?.run()
        } catch {
            notifyUser(title: "Error", informativeText: "Failed to start the backup process.")
            NotificationCenter.default.post(name: .backupDidFinish, object: nil)
        }
    }
    
    private func startSpinningIcon() {
        guard let button = statusItem.button,
              let layer = button.layer else { return }
        
        // Stop any existing animation first
        stopSpinningIcon()
        
        // Get the current bounds
        let bounds = layer.bounds
        
        // CRITICAL: Set anchor point to center so it rotates in place
        // When changing anchor point, we must adjust position to keep visual location same
        let oldAnchorPoint = layer.anchorPoint
        let newAnchorPoint = CGPoint(x: 0.5, y: 0.5)
        
        // Calculate position adjustment needed
        let oldPosition = layer.position
        let anchorPointDelta = CGPoint(
            x: (newAnchorPoint.x - oldAnchorPoint.x) * bounds.width,
            y: (newAnchorPoint.y - oldAnchorPoint.y) * bounds.height
        )
        
        layer.anchorPoint = newAnchorPoint
        layer.position = CGPoint(
            x: oldPosition.x + anchorPointDelta.x,
            y: oldPosition.y + anchorPointDelta.y
        )
        
        // Create smooth rotation animation using Core Animation
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = -Double.pi * 2  // Negative for counter-clockwise
        rotation.duration = 3.0  // 2 seconds per full rotation (beach ball speed)
        rotation.repeatCount = .infinity  // Spin forever until stopped
        rotation.isRemovedOnCompletion = false
        
        // Add the animation to the button's layer
        layer.add(rotation, forKey: "rotationAnimation")
    }

    private func stopSpinningIcon() {
        guard let button = statusItem.button else { return }
        
        // Remove the animation
        button.layer?.removeAnimation(forKey: "rotationAnimation")
        
        // Reset to original non-rotated state
        button.layer?.transform = CATransform3DIdentity
    }
    
    @objc func backupDidStart() {
        print("DEBUG: backupDidStart called")
        isRunning = true
        startSpinningIcon()
        updateUIForStateChange()
    }
    
    @objc func backupDidFinish() {
        isRunning = false
        stopSpinningIcon()
        updateUIForStateChange()
    }
    
    @objc func handleUpdateLastBackupDisplay(_ notification: Notification) {
        if let title = notification.userInfo?["title"] as? String {
            lastBackupItem.title = title
        }
    }
    
    // MARK: - Actions
    @IBAction func startBackupClicked(_ sender: NSMenuItem) {
        guard !isRunning else {
            notifyUser(title: "Process is still running", informativeText: "A backup process is already in progress.")
            return
        }
        NotificationCenter.default.post(name: .requestManualBackup, object: nil)
    }
    
    @IBAction func abortBackupClicked(_ sender: NSMenuItem) {
        guard let task = backupTask, isRunning else {
            return
        }
        isUserInitiatedAbort = true
        
        // Terminate the bash script (which will kill the rsync process)
        task.terminate()
        
        // Log the abort in Swift
        logUserAbort()
        
        notifyUser(title: "Backup Aborted", informativeText: "The backup process has been cancelled.")
    }

    private func logUserAbort() {
        // Post notification to AppDelegate to handle logging in a thread-safe way
        NotificationCenter.default.post(name: .logAbort, object: nil)
    }
    
    @IBAction func quitClicked(sender: NSMenuItem) {
        if isRunning && !showQuitWarning() {
            return
        }
        NSApplication.shared.terminate(self)
    }
    
    // MARK: - Dialogs and User Notifications
    func showQuitWarning() -> Bool {
        let alert = NSAlert()
        alert.messageText = "DeLorean is running"
        alert.informativeText = "A backup is currently in progress. Are you sure you want to quit?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        
        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            backupTask?.terminate()
            return true
        }
        return false
    }
    
    func notifyUser(title: String, informativeText: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = informativeText
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
