import AppKit
import GhosttyEmbed
import UserNotifications

/// Owns the ``AppEnvironment`` and kicks off the first scan once AppKit has
/// finished launching. `MenuBarExtra`'s label/window views don't run a normal
/// `onAppear`/`task` lifecycle at launch, so the kickoff lives here instead.
final class AppDelegate: GhosttyEmbed.AppDelegate {
    let env: AppEnvironment
    private let linuxDoNotificationDelegate = LinuxDoUserNotificationDelegate()

    override init() {
        let terminalStore = MainActor.assumeIsolated {
            EmbeddedTerminalStore()
        }
        self.env = MainActor.assumeIsolated {
            AppEnvironment(terminalStore: terminalStore)
        }
        super.init(terminalStore: terminalStore)
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        super.applicationDidFinishLaunching(notification)
        linuxDoNotificationDelegate.fallback = self
        UNUserNotificationCenter.current().delegate = linuxDoNotificationDelegate
        MainActor.assumeIsolated {
            Theme.registerFonts()
            env.start()
            requestMainWindowOnLaunchIfNeeded()
        }
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
}

private final class LinuxDoUserNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var fallback: GhosttyEmbed.AppDelegate?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if Self.topicRoute(from: notification.request.content.userInfo) != nil {
            completionHandler([.banner, .sound])
            return
        }
        fallback?.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
            ?? completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let route = Self.topicRoute(from: response.notification.request.content.userInfo) else {
            fallback?.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
                ?? completionHandler()
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
