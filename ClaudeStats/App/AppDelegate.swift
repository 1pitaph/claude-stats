import AppKit
import Darwin
import UserNotifications

/// Owns the ``AppEnvironment`` and kicks off the first scan once AppKit has
/// finished launching. `MenuBarExtra`'s label/window views don't run a normal
/// `onAppear`/`task` lifecycle at launch, so the kickoff lives here instead.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let automaticTerminationReason = "Claude Stats is a resident menu bar app."

    let env: AppEnvironment
    private let linuxDoNotificationDelegate = LinuxDoUserNotificationDelegate()
    private var residentStatusItem: NSStatusItem?
    private var terminationSignalSource: DispatchSourceSignal?
    private var automaticTerminationDisabled = false
    private var suddenTerminationDisabled = false
    private var userRequestedTermination = false

    override init() {
        self.env = MainActor.assumeIsolated {
            AppEnvironment()
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(Self.automaticTerminationReason)
        automaticTerminationDisabled = true
        ProcessInfo.processInfo.disableSuddenTermination()
        suddenTerminationDisabled = true
        UNUserNotificationCenter.current().delegate = linuxDoNotificationDelegate
        MainActor.assumeIsolated {
            installTerminationSignalHandler()
            installResidentStatusItem()
            Theme.registerFonts()
            env.start()
            requestMainWindowOnLaunchIfNeeded()
        }
    }

    @MainActor
    func requestUserTermination() {
        authorizeUserTermination(reason: "explicit menu request")
        NSApplication.shared.terminate(nil)
    }

    @MainActor
    private func authorizeUserTermination(reason: String) {
        guard !userRequestedTermination else { return }
        userRequestedTermination = true
        AppLivenessRescue.disarm()
        if automaticTerminationDisabled {
            ProcessInfo.processInfo.enableAutomaticTermination(Self.automaticTerminationReason)
            automaticTerminationDisabled = false
        }
        if suddenTerminationDisabled {
            ProcessInfo.processInfo.enableSuddenTermination()
            suddenTerminationDisabled = false
        }
        Log.app.info("Application termination approved: \(reason, privacy: .public)")
    }

    @MainActor
    private func installTerminationSignalHandler() {
        guard terminationSignalSource == nil else { return }
        Darwin.signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.authorizeUserTermination(reason: "SIGTERM")
                NSApplication.shared.terminate(nil)
            }
        }
        source.resume()
        terminationSignalSource = source
    }

    @MainActor
    private func installResidentStatusItem() {
        guard residentStatusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: 0)
        item.button?.isHidden = true
        residentStatusItem = item
    }

    @MainActor
    private func requestMainWindowOnLaunchIfNeeded() {
        guard env.preferences.openMainWindowOnLaunch else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openMainWindowOnAppLaunch, object: nil)
        }
    }

    @MainActor
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        let bridgedUserInfo = Dictionary(uniqueKeysWithValues: userInfo.map { (AnyHashable($0.key), $0.value) })
        guard let notification = LeaderboardRemoteNotificationParser.notification(from: bridgedUserInfo) else { return }
        env.leaderboards.handleRealtimeNotification(notification)
    }

    @MainActor
    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        env.leaderboards.handleRemoteNotificationRegistrationFailure(error)
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        if let firstURL = urls.first {
            Log.app.notice("Unhandled application URL: \(firstURL.absoluteString, privacy: .public)")
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        authorizeUserTermination(reason: "AppKit termination request")
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        if userRequestedTermination {
            Log.app.info("Application will terminate after explicit user request")
            return
        }

        guard let reason = AppLivenessRescue.activeReason() else {
            Log.app.error("Application is terminating without an explicit user request outside the liveness rescue window")
            return
        }

        Log.app.error("Application is terminating during liveness rescue window for \(reason, privacy: .public); launching a replacement instance")
        launchReplacementInstance()
    }

    private func launchReplacementInstance() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundleURL.path]
        do {
            try process.run()
        } catch {
            Log.app.error("Failed to launch replacement app instance: \(error.localizedDescription, privacy: .public)")
        }
    }
}

enum AppLivenessRescue {
    private static let deadlineKey = "ClaudeStats.AppLivenessRescue.deadline"
    private static let reasonKey = "ClaudeStats.AppLivenessRescue.reason"

    static func arm(reason: String, duration: TimeInterval = 45) {
        UserDefaults.standard.set(Date().addingTimeInterval(duration).timeIntervalSince1970, forKey: deadlineKey)
        UserDefaults.standard.set(reason, forKey: reasonKey)
    }

    static func disarm() {
        UserDefaults.standard.removeObject(forKey: deadlineKey)
        UserDefaults.standard.removeObject(forKey: reasonKey)
    }

    static func activeReason(now: Date = Date()) -> String? {
        let deadline = UserDefaults.standard.double(forKey: deadlineKey)
        guard deadline > now.timeIntervalSince1970 else {
            disarm()
            return nil
        }
        return UserDefaults.standard.string(forKey: reasonKey) ?? "memory action"
    }
}

private final class LinuxDoUserNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if Self.topicRoute(from: notification.request.content.userInfo) != nil {
            completionHandler([.banner, .sound])
            return
        }
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let route = Self.topicRoute(from: response.notification.request.content.userInfo) else {
            completionHandler()
            return
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .openMainWindowDestinationFromFloatingStats,
                object: FloatingStatsMainWindowDestination.linuxDoTopic(route)
            )
        }
        completionHandler()
    }

    private static func topicRoute(from userInfo: [AnyHashable: Any]) -> LinuxDoTopicRoute? {
        guard let rawURL = userInfo["url"] as? String,
              let url = URL(string: rawURL) else {
            return nil
        }
        return LinuxDoTopicRoute(url: url)
    }
}
