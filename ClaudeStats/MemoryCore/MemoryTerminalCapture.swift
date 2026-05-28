import Foundation

struct MemoryTerminalCaptureWriter: Sendable {
    static let maxCapturedBytes = 2 * 1024 * 1024

    let storage: MemorySQLiteStore
    let jsonlURL: URL

    init(
        storage: MemorySQLiteStore = MemorySQLiteStore(),
        jsonlURL: URL = MemoryPaths.terminalCapturesURL()
    ) {
        self.storage = storage
        self.jsonlURL = jsonlURL
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
            sourceID: MemoryDefaults.terminalSourceID,
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
        try await ensureTerminalSource()
        try await storage.upsertRecord(record, blocks: blocks)
        try await appendJSONL(record: record, blocks: blocks)
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
            sourceID: MemoryDefaults.terminalSourceID,
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
            textHash: MemorySQLiteStore.textHash(text)
        )
        try await ensureTerminalSource()
        try await storage.upsertRecord(record, blocks: [block])
        try await appendJSONL(record: record, blocks: [block])
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
            sourceID: MemoryDefaults.terminalSourceID,
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
            textHash: MemorySQLiteStore.textHash(text)
        )
        try await ensureTerminalSource()
        try await storage.upsertRecord(record, blocks: [block])
        try await appendJSONL(record: record, blocks: [block])
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
                    textHash: MemorySQLiteStore.textHash(stdout)
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
                    textHash: MemorySQLiteStore.textHash(stderr)
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
                    textHash: MemorySQLiteStore.textHash(text)
                )
            )
        }
        return blocks
    }

    private func ensureTerminalSource() async throws {
        let source = MemorySource(
            id: MemoryDefaults.terminalSourceID,
            kind: .terminal,
            providerRaw: nil,
            title: "Terminal captures",
            path: MemoryPaths.terminalCapturesURL().path,
            isDefault: true
        )
        try await storage.upsertSources([source])
    }

    private func appendJSONL(record: MemoryRecord, blocks: [MemoryBlock]) async throws {
        let url = jsonlURL
        let envelope = MemoryTerminalCaptureEnvelope(record: record, blocks: blocks)
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = try JSONEncoder.memoryEncoder.encode(envelope)
            data.append(Data("\n".utf8))
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: .atomic)
            }
        }.value
    }

    private func metadataJSON(_ values: [String: String]) -> String? {
        guard let data = try? JSONEncoder.memoryEncoder.encode(values) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct MemoryTerminalCaptureEnvelope: Codable, Sendable, Hashable {
    let record: MemoryRecord
    let blocks: [MemoryBlock]
}
