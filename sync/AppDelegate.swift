import Cocoa
import UserNotifications

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var isBackupRunning = false
    var backupTimer: Timer?
    var backupHour = ""
    var backupMinute = ""
    var rangeStart = ""
    var rangeEnd = ""
    var frequency: TimeInterval = 30
    var maxDayAttemptNotification = 0 // Default value, will be overwritten by loadConfig()
    var logFilePath = "\(NSHomeDirectory())/delorean.log" // Default value, will be overwritten by loadConfig()


    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidStart), name: .backupDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidFinish), name: .backupDidFinish, object: nil)

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in }
        loadConfig()
        checkProlongedFailures() // Check for prolonged failures
    }

    @objc func backupDidStart(notification: Notification) {
        isBackupRunning = true
    }

    @objc func backupDidFinish(notification: Notification) {
        isBackupRunning = false
        checkProlongedFailures()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        backupTimer?.invalidate()

        if let task = StatusMenuController.shared.backupTask {
            task.terminate()
        }
    }

    // MARK: - Backup Configuration and Schedule
    private func loadConfig() {
        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
            print("Failed to locate sync_files.sh")
            return
        }

        let command = "grep '=' \(scriptPath) | grep -v '^#' | tr -d '\"' | tr -d ' '"
        executeShellCommand(command) { output in
            output.forEach { line in
                let components = line.split(separator: "=").map { String($0) }
                if components.count == 2 {
                    switch components[0] {
                        case "scheduledBackupTime":
                            let timeComponents = components[1].split(separator: ":").map { String($0) }
                            if timeComponents.count == 2 {
                                self.backupHour = timeComponents[0]
                                self.backupMinute = timeComponents[1]
                            }
                        case "rangeStart":
                            self.rangeStart = components[1]
                        case "rangeEnd":
                            self.rangeEnd = components[1]
                        case "frequencyCheck":
                            self.frequency = TimeInterval(components[1]) ?? 3600
                        case "maxDayAttemptNotification":
                            self.maxDayAttemptNotification = Int(components[1]) ?? 6
                        case "LOG_FILE":
                            self.logFilePath = components[1].replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
                            print("DEBUG: logFilePath set to \(self.logFilePath)")
                        default: break
                    }
                }
            }
            self.startBackupTimer()
        }
        checkProlongedFailures()
    }

    private func startBackupTimer() {
        backupTimer?.invalidate()
        backupTimer = Timer.scheduledTimer(timeInterval: frequency, target: self, selector: #selector(performScheduledChecks), userInfo: nil, repeats: true)
        performScheduledChecks()
    }

    @objc private func performScheduledChecks() {
        checkBackupSchedule()
        checkProlongedFailures()
    }

    
    
    
    
    
    
    
    
    
    
    @objc private func checkBackupSchedule() {
        guard !isBackupRunning else {
            print("DEBUG: Backup is already in progress.")
            return
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = TimeZone.current

        let logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        logDateFormatter.timeZone = TimeZone.current

        let currentTimeString = timeFormatter.string(from: Date())
        let currentDateString = logDateFormatter.string(from: Date()).prefix(10) // Get the current date in yyyy-MM-dd format
        let currentDateTime = logDateFormatter.string(from: Date())

        guard let currentTime = timeFormatter.date(from: currentTimeString),
              let rangeEnd = timeFormatter.date(from: self.rangeEnd),
              let backupTime = timeFormatter.date(from: "\(self.backupHour):\(self.backupMinute)") else {
            print("DEBUG: There was an error parsing the date or time.")
            return
        }

        // If current time is not within the scheduled backup window, exit
        if currentTime < backupTime || currentTime > rangeEnd {
            print("DEBUG: Current time is outside the backup window.")
            return
        }

        var didRunBackupToday = false
        var logContent = ""

        if FileManager.default.fileExists(atPath: logFilePath) {
            do {
                logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
                print("DEBUG: Successfully read log file.")
            } catch {
                print("DEBUG: Failed to read log file: \(error)")
                logContent = ""  // Ensure logContent is initialized even if reading fails
            }
        } else {
            print("DEBUG: Log file does not exist yet.")
        }

        if logContent.isEmpty {
            print("DEBUG: Backup log is empty, initiating backup.")
            isBackupRunning = true
            NotificationCenter.default.post(name: Notification.Name("StartBackup"), object: nil, userInfo: ["scriptPath": Bundle.main.path(forResource: "sync_files", ofType: "sh")!])
            return
        }

        let logEntries = logContent.components(separatedBy: "\n").filter { !$0.isEmpty }
        let successfulBackupsToday = logEntries.filter { $0.contains("Backup completed successfully") && $0.contains(currentDateString) }
        didRunBackupToday = !successfulBackupsToday.isEmpty
        print("DEBUG: Backup log found. Did run backup today? \(didRunBackupToday)")

        // Ensure the network drive is accessible before scheduling a backup
        let destPath = "/Volumes/SFA-All/User Data/\(NSUserName())"
        let fileManager = FileManager.default

        print("DEBUG: Checking if network drive is accessible.")
        if fileManager.fileExists(atPath: destPath) {
            print("DEBUG: Network drive is accessible.")
            if !didRunBackupToday && currentTime >= backupTime && currentTime <= rangeEnd {
                if currentTime >= backupTime {
                    print("DEBUG: Conditions met for starting backup.")
                    isBackupRunning = true
                    NotificationCenter.default.post(name: Notification.Name("StartBackup"), object: nil, userInfo: ["scriptPath": Bundle.main.path(forResource: "sync_files", ofType: "sh")!])
                } else {
                    print("DEBUG: Not yet time for scheduled backup.")
                }
            } else if didRunBackupToday {
                print("DEBUG: Backup already completed for today.")
            } else {
                print("DEBUG: Current time is outside the backup window.")
            }
        } else {
            print("DEBUG: Network drive is not accessible.")
            if !didRunBackupToday && currentTime >= backupTime && currentTime <= rangeEnd {
                // Trigger the script to log a new failure entry
                let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh")!
                let process = Process()
                process.launchPath = "/bin/bash"
                process.arguments = [scriptPath]
                process.launch()
                process.waitUntilExit()

                // Recalculate recent failures
                do {
                    logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
                    print("DEBUG: Successfully read log file after failure entry.")
                } catch {
                    print("DEBUG: Failed to read log file: \(error)")
                    logContent = ""  // Ensure logContent is initialized even if reading fails
                }

                let updatedLogEntries = logContent.components(separatedBy: "\n").filter { !$0.isEmpty }
                let updatedFailureCount = updatedLogEntries.reversed().prefix(while: { !$0.contains("Backup completed successfully") }).filter { entry in
                    let entryDateString = entry.prefix(19)
                    if let entryDateTime = logDateFormatter.date(from: String(entryDateString)) {
                        return entry.contains("Backup Failed: Network drive inaccessible") && String(entryDateString.prefix(10)) == currentDateString && entryDateTime.timeIntervalSince1970 >= backupTime.timeIntervalSince1970
                    }
                    return false
                }.count

                print("DEBUG: Updated failure count: \(updatedFailureCount)")

                if updatedFailureCount >= maxDayAttemptNotification {
                    print("DEBUG: Failure count threshold met, sending notification.")
                    DispatchQueue.main.async {
                        self.notifyUser(title: "Backup Error", informativeText: "The network drive is not accessible. Ensure you are connected to the network and try again.")
                    }
                }
            }
        }
    }

    
    
    
    
    
    
    
    
    
    
    private func checkProlongedFailures() {
        let logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        logDateFormatter.timeZone = TimeZone.current

        var lastSuccessfulBackupDate: Date?

        if FileManager.default.fileExists(atPath: logFilePath) {
            do {
                let logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
                let logEntries = logContent.components(separatedBy: "\n").filter { !$0.isEmpty }
                for entry in logEntries.reversed() { // Iterate in reverse to find the most recent success
                    if entry.contains("Backup completed successfully") {
                        let dateString = entry.prefix(19) // Extract the date and time portion
                        lastSuccessfulBackupDate = logDateFormatter.date(from: String(dateString))
                        break
                    }
                }
            } catch {
                print("DEBUG: Failed to read log file: \(error)")
            }
        } else {
            print("DEBUG: Log file does not exist yet.")
        }

        guard let lastBackupDate = lastSuccessfulBackupDate else {
            print("DEBUG: No valid last successful backup date found.")
            return
        }

        let currentDate = Date()
        let calendar = Calendar.current
        if let daysBetween = calendar.dateComponents([.day], from: lastBackupDate, to: currentDate).day {
            if daysBetween >= maxDayAttemptNotification {  // Notify if no successful backup for maxDayAttemptNotification days
                notifyUser(title: "Backup Warning", informativeText: "No successful backup for \(daysBetween) days. Please check your network drive.")
            }
        }
    }

    @objc private func performBackup() {
        guard !isBackupRunning else {
            print("Backup is already in progress.")
            return
        }
        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
            DispatchQueue.main.async {
                self.notifyUser(title: "Backup Error", informativeText: "Failed to locate backup script.")
            }
            return
        }
        if StatusMenuController.shared.isRunning {
            print("Backup process attempted to start, but one is already in progress.")
            return
        }

        isBackupRunning = true
        NotificationCenter.default.post(name: Notification.Name("StartBackup"), object: nil, userInfo: ["scriptPath": scriptPath])
    }

    // MARK: - Helper Methods
    private func executeShellCommand(_ command: String, completion: @escaping ([String]) -> Void) {
        let process = Process()
        let pipe = Pipe()

        process.launchPath = "/bin/bash"
        process.arguments = ["-c", command]
        process.standardOutput = pipe

        process.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.components(separatedBy: "\n").filter { !$0.isEmpty } ?? []

        completion(output)
    }

    // MARK: - User Notification Center Delegate Methods
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        print("User interacted with notification: \(response.notification.request.identifier)")
        completionHandler()
    }

    func notifyUser(title: String, informativeText: String) {
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = title
        notificationContent.body = informativeText
        notificationContent.sound = UNNotificationSound.default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: nil)
        notificationCenter.add(request) { (error) in
            if let error = error {
                print("Error posting user notification: \(error.localizedDescription)")
            }
        }
    }
}
