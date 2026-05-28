import Foundation

enum MemorySourceKind: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case aiSessions
    case terminal

    var id: String { rawValue }
}

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

enum MemorySearchMode: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case text
    case semantic
    case hybrid

    var id: String { rawValue }
}

enum MemoryWorkspaceSection: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case search
    case aiSessions
    case terminalHistory
    case sources
    case setup

    var id: String { rawValue }
}

enum MemoryAIDestination: Hashable, Sendable {
    case overview
    case analysis
    case session(String)
    case indexedRecord(String)

    static let overviewRawValue = "overview"
    static let analysisRawValue = "analysis"
    private static let sessionPrefix = "session:"
    private static let indexedRecordPrefix = "indexed-record:"

    init(rawValue: String) {
        if rawValue == Self.analysisRawValue {
            self = .analysis
        } else if rawValue.hasPrefix(Self.sessionPrefix) {
            let id = String(rawValue.dropFirst(Self.sessionPrefix.count))
            self = id.isEmpty ? .overview : .session(id)
        } else if rawValue.hasPrefix(Self.indexedRecordPrefix) {
            let id = String(rawValue.dropFirst(Self.indexedRecordPrefix.count))
            self = id.isEmpty ? .overview : .indexedRecord(id)
        } else {
            self = .overview
        }
    }

    var rawValue: String {
        switch self {
        case .overview:
            Self.overviewRawValue
        case .analysis:
            Self.analysisRawValue
        case .session(let id):
            Self.sessionPrefix + id
        case .indexedRecord(let id):
            Self.indexedRecordPrefix + id
        }
    }
}

struct MemorySource: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var kind: MemorySourceKind
    var providerRaw: String?
    var title: String
    var path: String?
    var isEnabled: Bool
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastIndexedAt: Date?
    var lastError: String?

    init(
        id: String,
        kind: MemorySourceKind,
        providerRaw: String?,
        title: String,
        path: String?,
        isEnabled: Bool = true,
        isDefault: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastIndexedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.providerRaw = providerRaw
        self.title = title
        self.path = path
        self.isEnabled = isEnabled
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastIndexedAt = lastIndexedAt
        self.lastError = lastError
    }
}

struct MemorySourceStatus: Identifiable, Sendable, Hashable {
    var sourceID: String
    var readable: Bool
    var readOnly: Bool
    var indexed: Bool
    var unsupported: Bool
    var error: String?

    var id: String { sourceID }
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

struct MemorySearchResult: Identifiable, Sendable, Hashable {
    var id: String { block.id }
    var block: MemoryBlock
    var record: MemoryRecord
    var source: MemorySource?
    var score: Double?
    var snippet: String?
    var matchKind: MemorySearchMatchKind
}

enum MemorySearchMatchKind: String, Codable, Sendable, Hashable {
    case text
    case semantic
}

enum MemoryRef {
    static func ai(provider: String, sessionID: String, blockID: String) -> String {
        "memory://ai/\(escape(provider))/\(escape(sessionID))/\(escape(blockID))"
    }

    static func terminal(recordID: String, blockID: String) -> String {
        "memory://terminal/\(escape(recordID))/\(escape(blockID))"
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

enum MemoryDefaults {
    static let terminalSourceID = "terminal:default"

    static func defaultAISourceID(providerRaw: String) -> String {
        "ai:\(providerRaw):default"
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
