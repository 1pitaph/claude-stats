import AppKit
import SwiftUI

enum FloatingStatsMainWindowDestination: Sendable {
    case page(MainPage)
    case git
    #if !CLAUDE_STATS_LITE
    case network
    case warp
    case linuxDoTopic(LinuxDoTopicRoute)
    #endif
}

extension Notification.Name {
    static let openMainWindowFromFloatingStats = Notification.Name("ClaudeStats.openMainWindowFromFloatingStats")
    static let openMainWindowDestinationFromFloatingStats = Notification.Name("ClaudeStats.openMainWindowDestinationFromFloatingStats")
    static let selectMainWindowDestinationFromFloatingStats = Notification.Name("ClaudeStats.selectMainWindowDestinationFromFloatingStats")
    static let openSettingsFromFloatingStats = Notification.Name("ClaudeStats.openSettingsFromFloatingStats")
}

/// Bridges AppKit-owned floating-panel commands back into SwiftUI's scene
/// system, where `openWindow` is available.
struct FloatingStatsCommandBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindowFromFloatingStats)) { _ in
                openMainWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindowDestinationFromFloatingStats)) { notification in
                openMainWindow()
                guard let destination = notification.object as? FloatingStatsMainWindowDestination else { return }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .selectMainWindowDestinationFromFloatingStats,
                        object: destination
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsFromFloatingStats)) { _ in
                openMainWindow()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .openSettingsInMainWindow, object: nil)
                }
            }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: MainWindowView.windowID)
    }
}
