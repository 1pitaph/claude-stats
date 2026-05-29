import Foundation

protocol ChatPersisting: Sendable {
    func load() async -> ChatLibrarySnapshot
    func save(_ snapshot: ChatLibrarySnapshot) async
}

actor ChatPersistenceStore: ChatPersisting {
    static let currentSchemaVersion = 1

    private struct Envelope: Codable, Sendable {
        var schemaVersion: Int
        var snapshot: ChatLibrarySnapshot
    }

    private let fileURL: URL
    private let schemaVersion: Int

    init(fileURL: URL = ChatPersistenceStore.defaultFileURL(), schemaVersion: Int = ChatPersistenceStore.currentSchemaVersion) {
        self.fileURL = fileURL
        self.schemaVersion = schemaVersion
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("Chat", isDirectory: true)
            .appendingPathComponent("v\(currentSchemaVersion)", isDirectory: true)
            .appendingPathComponent("conversations.json", isDirectory: false)
    }

    func load() async -> ChatLibrarySnapshot {
        let url = fileURL
        let schemaVersion = schemaVersion
        return await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else {
                return .empty
            }
            do {
                let envelope = try JSONDecoder.chatDecoder.decode(Envelope.self, from: data)
                guard envelope.schemaVersion == schemaVersion else { return .empty }
                return envelope.snapshot
            } catch {
                Log.store.error("Chat library decode failed: \(error.localizedDescription, privacy: .public)")
                return .empty
            }
        }.value
    }

    func save(_ snapshot: ChatLibrarySnapshot) async {
        let url = fileURL
        let schemaVersion = schemaVersion
        await Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let envelope = Envelope(schemaVersion: schemaVersion, snapshot: snapshot)
                let data = try JSONEncoder.chatEncoder.encode(envelope)
                try data.write(to: url, options: .atomic)
            } catch {
                Log.store.error("Chat library save failed: \(error.localizedDescription, privacy: .public)")
            }
        }.value
    }
}

private extension JSONEncoder {
    static var chatEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate.bitPattern)
        }
        return encoder
    }
}

private extension JSONDecoder {
    static var chatDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let bitPattern = try? container.decode(UInt64.self) {
                return Date(timeIntervalSinceReferenceDate: Double(bitPattern: bitPattern))
            }

            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }

            let value = try container.decode(String.self)
            if let date = ChatPersistenceDateFormat.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid chat date")
        }
        return decoder
    }
}

private enum ChatPersistenceDateFormat {
    static func date(from value: String) -> Date? {
        let fractionalISO8601 = ISO8601DateFormatter()
        fractionalISO8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalISO8601.date(from: value) {
            return date
        }

        let standardISO8601 = ISO8601DateFormatter()
        return standardISO8601.date(from: value)
    }
}
