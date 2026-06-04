import SwiftUI

@main
struct ClaudeStatsiOSApp: App {
    @State private var store = CloudStatsSnapshotStore()

    var body: some Scene {
        WindowGroup {
            CloudStatsRootView(store: store)
        }
    }
}
