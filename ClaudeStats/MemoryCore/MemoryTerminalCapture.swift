import Foundation

struct MemoryTerminalCaptureWriter: Sendable {
    static let maxCapturedBytes = 2 * 1024 * 1024
    private static let terminalSourceID = "terminal:sidecar"

    let outbox: CodeMemoryEventOutbox
    let recorder: CodeMemoryTerminalRecorder

    init(
        outbox: CodeMemoryEventOutbox = CodeMemoryEventOutbox(),
        recorder: CodeMemoryTerminalRecorder = CodeMemoryTerminalRecorder()
    ) {
        self.outbox = outbox
        self.recorder = recorder
    }

    func saveRunCapture(
        command: String,
        arguments: [String],
        cwd: String,
        stdout: String,
        stderr: String,
        exitCode: Int,
        startedAt: Date,
        endedAt: Date,
        truncated: Bool
    ) async throws -> MemoryRecord {
        let title = ([command] + arguments).joined(separator: " ")
        let record = MemoryRecord(
            id: "terminal:\(UUID().uuidString)",
            sourceID: Self.terminalSourceID,
            kind: .terminalRun,
            title: title.isEmpty ? "Command" : title,
            subtitle: cwd,
            command: title,
            cwd: cwd,
            exitCode: exitCode,
            startedAt: startedAt,
            endedAt: endedAt,
            metadataJSON: metadataJSON([
                "command": command,
                "arguments": arguments.joined(separator: "\u{1f}"),
                "truncated": truncated ? "true" : "false",
            ])
        )
        let blocks = terminalBlocks(record: record, stdout: stdout, stderr: stderr)
        let event = recorder.event(
            title: record.title,
            body: blocks.map(\.text).joined(separator: "\n\n"),
            kind: record.kind,
            cwd: cwd,
            ref: blocks.first?.ref ?? record.id
        )
        if await recorder.record(event) {
            return record
        }
        try await outbox.enqueue(event)
        return record
    }

    func savePipeCapture(
        text: String,
        cwd: String,
        startedAt: Date = .now,
        truncated: Bool
    ) async throws -> MemoryRecord {
        let record = MemoryRecord(
            id: "terminal:\(UUID().uuidString)",
            sourceID: Self.terminalSourceID,
            kind: .terminalPipe,
            title: "Pipe capture",
            subtitle: cwd,
            cwd: cwd,
            startedAt: startedAt,
            endedAt: .now,
            metadataJSON: metadataJSON(["truncated": truncated ? "true" : "false"])
        )
        let blockID = "\(record.id):pipe"
        let block = MemoryBlock(
            id: blockID,
            recordID: record.id,
            sourceID: record.sourceID,
            ordinal: 0,
            role: .text,
            text: text,
            ref: MemoryRef.terminal(recordID: record.id, blockID: blockID),
            textHash: MemoryHash.textHash(text)
        )
        let event = recorder.event(
            title: record.title,
            body: text,
            kind: record.kind,
            cwd: cwd,
            ref: block.ref
        )
        if await recorder.record(event) {
            return record
        }
        try await outbox.enqueue(event)
        return record
    }

    func saveShellMetadata(
        shell: String,
        command: String,
        cwd: String,
        exitCode: Int,
        startedAt: Date?,
        endedAt: Date = .now
    ) async throws -> MemoryRecord {
        let title = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = MemoryRecord(
            id: "terminal:\(UUID().uuidString)",
            sourceID: Self.terminalSourceID,
            kind: .shellMetadata,
            title: title.isEmpty ? "Shell command" : title,
            subtitle: cwd,
            command: command,
            cwd: cwd,
            exitCode: exitCode,
            startedAt: startedAt,
            endedAt: endedAt,
            metadataJSON: metadataJSON(["shell": shell])
        )
        let text = "shell=\(shell)\nexit=\(exitCode)\ncwd=\(cwd)\ncommand=\(command)"
        let blockID = "\(record.id):metadata"
        let block = MemoryBlock(
            id: blockID,
            recordID: record.id,
            sourceID: record.sourceID,
            ordinal: 0,
            role: .metadata,
            text: text,
            ref: MemoryRef.terminal(recordID: record.id, blockID: blockID),
            textHash: MemoryHash.textHash(text)
        )
        let event = recorder.event(
            title: record.title,
            body: text,
            kind: record.kind,
            cwd: cwd,
            ref: block.ref
        )
        if await recorder.record(event) {
            return record
        }
        try await outbox.enqueue(event)
        return record
    }

    private func terminalBlocks(record: MemoryRecord, stdout: String, stderr: String) -> [MemoryBlock] {
        var blocks: [MemoryBlock] = []
        if !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let blockID = "\(record.id):stdout"
            blocks.append(
                MemoryBlock(
                    id: blockID,
                    recordID: record.id,
                    sourceID: record.sourceID,
                    ordinal: blocks.count,
                    role: .stdout,
                    text: stdout,
                    ref: MemoryRef.terminal(recordID: record.id, blockID: blockID),
                    textHash: MemoryHash.textHash(stdout)
                )
            )
        }
        if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let blockID = "\(record.id):stderr"
            blocks.append(
                MemoryBlock(
                    id: blockID,
                    recordID: record.id,
                    sourceID: record.sourceID,
                    ordinal: blocks.count,
                    role: .stderr,
                    text: stderr,
                    ref: MemoryRef.terminal(recordID: record.id, blockID: blockID),
                    textHash: MemoryHash.textHash(stderr)
                )
            )
        }
        if blocks.isEmpty {
            let text = "exit=\(record.exitCode ?? 0)\ncommand=\(record.command ?? "")"
            let blockID = "\(record.id):metadata"
            blocks.append(
                MemoryBlock(
                    id: blockID,
                    recordID: record.id,
                    sourceID: record.sourceID,
                    ordinal: 0,
                    role: .metadata,
                    text: text,
                    ref: MemoryRef.terminal(recordID: record.id, blockID: blockID),
                    textHash: MemoryHash.textHash(text)
                )
            )
        }
        return blocks
    }

    private func metadataJSON(_ values: [String: String]) -> String? {
        guard let data = try? JSONEncoder.memoryEncoder.encode(values) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
