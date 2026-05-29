import Foundation
import Testing
@testable import ClaudeStats

@Suite("Memory capture")
struct MemoryCaptureTests {
    @Test("Terminal writer queues run captures in outbox when sidecar is offline")
    func terminalWriterQueuesRunCaptures() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let outboxURL = root.appendingPathComponent("code-memory-outbox.jsonl")
        let writer = MemoryTerminalCaptureWriter(
            outbox: CodeMemoryEventOutbox(url: outboxURL),
            recorder: CodeMemoryTerminalRecorder(recordHandler: { _ in false })
        )

        let record = try await writer.saveRunCapture(
            command: "/bin/echo",
            arguments: ["ok"],
            cwd: root.path,
            stdout: "ok\n",
            stderr: "",
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 11),
            truncated: false
        )

        #expect(record.title == "/bin/echo ok")
        let outbox = try String(contentsOf: outboxURL, encoding: .utf8)
        let line = try #require(outbox.split(separator: "\n").first)
        let envelope = try JSONDecoder.codeMemoryDecoder.decode(
            OutboxEnvelope.self,
            from: Data(line.utf8)
        )
        #expect(envelope.event.after?.title == "/bin/echo ok")
        #expect(envelope.event.after?.body == "ok\n")
    }

    @Test("Text hash is stable")
    func textHashStable() {
        #expect(MemoryHash.textHash("Needle context for parser refactor") == MemoryHash.textHash("Needle context for parser refactor"))
        #expect(MemoryHash.textHash("a") != MemoryHash.textHash("b"))
    }

    private struct OutboxEnvelope: Decodable {
        var event: CodeMemoryEventInput
    }
}

@Suite("Memory shell integration")
struct MemoryShellIntegrationTests {
    @Test("Renderer contains markers and metadata command")
    func rendererContainsMarkers() {
        let text = MemoryShellIntegrationManager().render(shell: .zsh, helperPath: "/tmp/claude-stats-memory")
        #expect(text.contains("Claude Stats Memory"))
        #expect(text.contains("record-shell"))
        #expect(text.contains("--command"))
    }
}
