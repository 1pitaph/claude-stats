import Foundation
import Testing
@testable import WarpEmbed

@Suite("WarpRuntime")
struct WarpRuntimeTests {
    @Test("Runtime reports missing source checkout")
    func missingSourceCheckout() {
        let runtime = WarpRuntime(sourceRoot: URL(fileURLWithPath: "/tmp/claude-stats-missing-warp-checkout"))

        #expect(runtime.availability().isReady == false)
    }

    @Test("Runtime reports pending bridge when source exists without library")
    func pendingBridge() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("Cargo.toml"))

        let runtime = WarpRuntime(sourceRoot: root)

        #expect(runtime.availability() == .bridgeUnavailable)
    }
}
