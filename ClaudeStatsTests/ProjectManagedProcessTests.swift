import Foundation
import Testing
@testable import ClaudeStats

@Suite("Project managed process")
struct ProjectManagedProcessTests {
    @Test("One-shot process streams output and reports a successful exit")
    func oneShotProcessStreamsOutput() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let collector = ProjectProcessEventCollector()
        let action = makeAction(
            root: root,
            command: ProjectLaunchCommand(
                executablePath: "/bin/sh",
                arguments: ["-c", "printf 'hello from launcher\\n'"]
            ),
            lifecycle: .oneShot
        )
        let process = ProjectManagedProcess(action: action) { event in
            Task { await collector.record(event) }
        }

        let pid = try process.start()
        let snapshot = try await waitForTermination(collector)

        #expect(pid > 0)
        #expect(snapshot.output.contains("hello from launcher"))
        #expect(snapshot.exitCode == 0)
        #expect(snapshot.requestedStop == false)
    }

    @Test("Stopping a managed process runs its explicit cleanup command")
    func stopRunsCleanupCommand() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("stopped.marker", isDirectory: false)
        let collector = ProjectProcessEventCollector()
        let action = makeAction(
            root: root,
            command: ProjectLaunchCommand(executablePath: "/bin/sleep", arguments: ["30"]),
            stopCommand: ProjectLaunchCommand(executablePath: "/usr/bin/touch", arguments: [marker.path]),
            lifecycle: .longRunning
        )
        let process = ProjectManagedProcess(action: action) { event in
            Task { await collector.record(event) }
        }

        _ = try process.start()
        process.stop()
        let snapshot = try await waitForTermination(collector)

        #expect(snapshot.requestedStop == true)
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    private func makeAction(
        root: URL,
        command: ProjectLaunchCommand,
        stopCommand: ProjectLaunchCommand? = nil,
        lifecycle: ProjectLaunchLifecycle
    ) -> ProjectLaunchAction {
        ProjectLaunchAction(
            id: "test-action-\(UUID().uuidString)",
            title: "Test",
            detail: "Test process",
            kind: .script,
            workingDirectory: root.path,
            command: command,
            stopCommand: stopCommand,
            lifecycle: lifecycle,
            confidence: .certain,
            sourcePath: "test",
            priority: 1
        )
    }

    private func waitForTermination(
        _ collector: ProjectProcessEventCollector
    ) async throws -> ProjectProcessEventSnapshot {
        for _ in 0..<140 {
            let snapshot = await collector.snapshot()
            if snapshot.exitCode != nil { return snapshot }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Timed out waiting for the managed process to terminate")
        return await collector.snapshot()
    }
}

private struct ProjectProcessEventSnapshot: Sendable {
    var output = ""
    var exitCode: Int32?
    var requestedStop: Bool?
}

private actor ProjectProcessEventCollector {
    private var value = ProjectProcessEventSnapshot()

    func record(_ event: ProjectManagedProcessEvent) {
        switch event {
        case .output(_, _, _, let text):
            value.output += text
        case .terminated(_, _, _, let exitCode, let requestedStop):
            value.exitCode = exitCode
            value.requestedStop = requestedStop
        }
    }

    func snapshot() -> ProjectProcessEventSnapshot { value }
}
