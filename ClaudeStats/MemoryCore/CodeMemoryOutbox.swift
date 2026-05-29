import Foundation

struct CodeMemoryOutboxDrainResult: Sendable, Hashable {
    var delivered: Int
    var remaining: Int
}

struct CodeMemoryEventOutbox: Sendable {
    let url: URL

    init(url: URL = MemoryPaths.codeMemoryOutboxURL()) {
        self.url = url
    }

    func enqueue(_ event: CodeMemoryEventInput) async throws {
        let url = url
        let envelope = Envelope(id: UUID().uuidString, createdAt: Date().timeIntervalSince1970, event: event)
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = try JSONEncoder.codeMemoryEncoder.encode(envelope)
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

    func drain(client: CodeMemoryHTTPClient = CodeMemoryHTTPClient()) async -> CodeMemoryOutboxDrainResult {
        let url = url
        let envelopes: [Envelope]
        do {
            envelopes = try await Task.detached(priority: .utility) {
                guard FileManager.default.fileExists(atPath: url.path) else { return [] }
                let text = try String(contentsOf: url, encoding: .utf8)
                return text.split(separator: "\n").compactMap { line in
                    try? JSONDecoder.codeMemoryDecoder.decode(Envelope.self, from: Data(line.utf8))
                }
            }.value
        } catch {
            return CodeMemoryOutboxDrainResult(delivered: 0, remaining: 0)
        }
        guard !envelopes.isEmpty else {
            return CodeMemoryOutboxDrainResult(delivered: 0, remaining: 0)
        }

        var delivered = 0
        var remaining: [Envelope] = []
        for envelope in envelopes {
            do {
                try await client.recordEvent(envelope.event)
                delivered += 1
            } catch {
                remaining.append(envelope)
            }
        }
        do {
            try await rewrite(remaining)
        } catch {
            return CodeMemoryOutboxDrainResult(delivered: delivered, remaining: remaining.count)
        }
        return CodeMemoryOutboxDrainResult(delivered: delivered, remaining: remaining.count)
    }

    private func rewrite(_ envelopes: [Envelope]) async throws {
        let url = url
        try await Task.detached(priority: .utility) {
            if envelopes.isEmpty {
                try? FileManager.default.removeItem(at: url)
                return
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = Data()
            for envelope in envelopes {
                data.append(try JSONEncoder.codeMemoryEncoder.encode(envelope))
                data.append(Data("\n".utf8))
            }
            try data.write(to: url, options: .atomic)
        }.value
    }

    private struct Envelope: Codable, Sendable, Hashable {
        var id: String
        var createdAt: Double
        var event: CodeMemoryEventInput

        enum CodingKeys: String, CodingKey {
            case id
            case createdAt = "created_at"
            case event
        }
    }
}

