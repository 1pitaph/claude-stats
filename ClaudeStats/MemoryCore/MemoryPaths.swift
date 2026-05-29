import Foundation

enum MemoryPaths {
    static func rootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("Memory", isDirectory: true)
    }

    static func codeMemoryOutboxURL(rootDirectory: URL = rootDirectory()) -> URL {
        rootDirectory.appendingPathComponent("code-memory-outbox.jsonl", isDirectory: false)
    }

    static func sidecarPIDURL(rootDirectory: URL = rootDirectory()) -> URL {
        rootDirectory.appendingPathComponent("memoryd.pid", isDirectory: false)
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
