import AppKit
import Testing
@testable import ClaudeStats

@MainActor
@Suite("App delegate termination")
struct AppDelegateTerminationTests {
    @Test("AppKit terminate requests are treated as explicit user exits")
    func appKitTerminateRequestIsApproved() {
        let delegate = AppDelegate()

        let reply = delegate.applicationShouldTerminate(.shared)

        #expect(reply == .terminateNow)
    }

    @Test("AppKit terminate request disarms liveness rescue")
    func appKitTerminateRequestDisarmsLivenessRescue() {
        AppLivenessRescue.arm(reason: "test rescue")
        defer { AppLivenessRescue.disarm() }
        #expect(AppLivenessRescue.activeReason() == "test rescue")
        let delegate = AppDelegate()

        let reply = delegate.applicationShouldTerminate(.shared)

        #expect(reply == .terminateNow)
        #expect(AppLivenessRescue.activeReason() == nil)
    }
}
