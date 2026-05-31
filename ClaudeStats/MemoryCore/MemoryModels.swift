import CryptoKit
import Foundation

enum MemoryRecordKind: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case aiSession
    case terminalRun
    case terminalPipe
    case shellMetadata

    var id: String { rawValue }
}

enum MemoryBlockRole: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case user
    case assistant
    case tool
    case system
    case stdout
    case stderr
    case metadata
    case text

    var id: String { rawValue }
}

enum MemoryWorkspaceSection: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case search
    case memories
    case gantt
    case graph
    case review
    case settings

    var id: String { rawValue }

    static var allCases: [MemoryWorkspaceSection] {
        [.search, .memories, .gantt, .graph, .review, .settings]
    }
}

struct MemoryRecord: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var sourceID: String
    var kind: MemoryRecordKind
    var providerRaw: String?
    var externalID: String?
    var title: String
    var subtitle: String?
    var projectPath: String?
    var filePath: String?
    var command: String?
    var cwd: String?
    var exitCode: Int?
    var startedAt: Date?
    var endedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var metadataJSON: String?

    init(
        id: String,
        sourceID: String,
        kind: MemoryRecordKind,
        providerRaw: String? = nil,
        externalID: String? = nil,
        title: String,
        subtitle: String? = nil,
        projectPath: String? = nil,
        filePath: String? = nil,
        command: String? = nil,
        cwd: String? = nil,
        exitCode: Int? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        metadataJSON: String? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.kind = kind
        self.providerRaw = providerRaw
        self.externalID = externalID
        self.title = title
        self.subtitle = subtitle
        self.projectPath = projectPath
        self.filePath = filePath
        self.command = command
        self.cwd = cwd
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadataJSON = metadataJSON
    }
}

struct MemoryBlock: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var recordID: String
    var sourceID: String
    var ordinal: Int
    var role: MemoryBlockRole
    var text: String
    var excerpt: String
    var timestamp: Date?
    var model: String?
    var ref: String
    var textHash: String
    var createdAt: Date

    init(
        id: String,
        recordID: String,
        sourceID: String,
        ordinal: Int,
        role: MemoryBlockRole,
        text: String,
        excerpt: String? = nil,
        timestamp: Date? = nil,
        model: String? = nil,
        ref: String,
        textHash: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.recordID = recordID
        self.sourceID = sourceID
        self.ordinal = ordinal
        self.role = role
        self.text = text
        self.excerpt = excerpt ?? Self.makeExcerpt(text)
        self.timestamp = timestamp
        self.model = model
        self.ref = ref
        self.textHash = textHash
        self.createdAt = createdAt
    }

    static func makeExcerpt(_ text: String, limit: Int = 280) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

enum MemoryRef {
    static func terminal(recordID: String, blockID: String) -> String {
        "memory://terminal/\(escape(recordID))/\(escape(blockID))"
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

enum MemoryHash {
    static func textHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension String {
    var memoryAbbreviatingHomeDirectory: String {
        replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}
