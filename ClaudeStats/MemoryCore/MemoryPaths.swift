import Foundation

enum MemoryPaths {
    static func rootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("Memory", isDirectory: true)
    }

    static func databaseURL(rootDirectory: URL = rootDirectory()) -> URL {
        rootDirectory.appendingPathComponent("memory.sqlite3", isDirectory: false)
    }

    static func sourcesURL(rootDirectory: URL = rootDirectory()) -> URL {
        rootDirectory.appendingPathComponent("sources.json", isDirectory: false)
    }

    static func terminalCapturesURL(rootDirectory: URL = rootDirectory()) -> URL {
        rootDirectory.appendingPathComponent("terminal-captures.jsonl", isDirectory: false)
    }
}

struct MemorySourceFileStore: Sendable {
    let url: URL

    init(url: URL = MemoryPaths.sourcesURL()) {
        self.url = url
    }

    func load() async throws -> [MemorySource] {
        let url = url
        return try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let data = try Data(contentsOf: url)
            return try JSONDecoder.memoryDecoder.decode([MemorySource].self, from: data)
        }.value
    }

    func save(_ sources: [MemorySource]) async throws {
        let url = url
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.memoryEncoder.encode(sources)
            try data.write(to: url, options: .atomic)
        }.value
    }
}

extension JSONEncoder {
    static var memoryEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode("referenceBitPattern:\(date.timeIntervalSinceReferenceDate.bitPattern)")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var memoryDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            let value = try container.decode(String.self)
            if
                value.hasPrefix("referenceBitPattern:"),
                let bits = UInt64(value.dropFirst("referenceBitPattern:".count))
            {
                return Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits))
            }
            if
                value.hasPrefix("epochBitPattern:"),
                let bits = UInt64(value.dropFirst("epochBitPattern:".count))
            {
                return Date(timeIntervalSince1970: Double(bitPattern: bits))
            }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
        }
        return decoder
    }
}
