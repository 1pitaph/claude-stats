import Foundation

struct CodeMemoryHealth: Codable, Sendable, Hashable {
    var status: String
    var store: String?
    var apiVersion: Int? = nil
    var eventCount: Int
    var memoryCount: Int
    var totalMemoryCount: Int? = nil
    var proposalCount: Int? = nil
    var moduleCount: Int? = nil
    var projectionPending: Int? = nil
    var projectionFailed: Int? = nil
    var capturePending: Int? = nil
    var captureFailed: Int? = nil
    var migrationPending: Int? = nil
    var adapters: [String: String]

    enum CodingKeys: String, CodingKey {
        case status
        case store
        case apiVersion = "api_version"
        case eventCount = "event_count"
        case memoryCount = "memory_count"
        case totalMemoryCount = "total_memory_count"
        case proposalCount = "proposal_count"
        case moduleCount = "module_count"
        case projectionPending = "projection_pending"
        case projectionFailed = "projection_failed"
        case capturePending = "capture_pending"
        case captureFailed = "capture_failed"
        case migrationPending = "migration_pending"
        case adapters
    }
}

struct CodeMemoryScope: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var kind: String
    var key: String
    var title: String
    var metadata: [String: String]?
    var primary: Bool?
}

struct CodeMemorySourceRef: Codable, Identifiable, Sendable, Hashable, ExpressibleByDictionaryLiteral {
    var kind: String
    var uri: String?
    var path: String?
    var contentHash: String?
    var sourceID: String?
    var episodeID: String?
    var lineStart: Int?
    var lineEnd: Int?
    var quote: String?
    var metadata: [String: String]

    var id: String {
        [kind, uri, path, sourceID, episodeID, lineStart.map(String.init), lineEnd.map(String.init)]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    init(
        kind: String,
        uri: String? = nil,
        path: String? = nil,
        contentHash: String? = nil,
        sourceID: String? = nil,
        episodeID: String? = nil,
        lineStart: Int? = nil,
        lineEnd: Int? = nil,
        quote: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.kind = kind
        self.uri = uri
        self.path = path
        self.contentHash = contentHash
        self.sourceID = sourceID
        self.episodeID = episodeID
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.quote = quote
        self.metadata = metadata
    }

    init(dictionaryLiteral elements: (String, String)...) {
        var values = Dictionary(uniqueKeysWithValues: elements)
        self.init(
            kind: values.removeValue(forKey: "kind") ?? "source",
            uri: values.removeValue(forKey: "uri"),
            path: values.removeValue(forKey: "path"),
            contentHash: values.removeValue(forKey: "content_hash"),
            sourceID: values.removeValue(forKey: "source_id"),
            episodeID: values.removeValue(forKey: "episode_id"),
            lineStart: values.removeValue(forKey: "line_start").flatMap(Int.init),
            lineEnd: values.removeValue(forKey: "line_end").flatMap(Int.init),
            quote: values.removeValue(forKey: "quote"),
            metadata: values
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodeMemoryDynamicCodingKey.self)
        func string(_ key: String) -> String? {
            guard let codingKey = CodeMemoryDynamicCodingKey(stringValue: key) else { return nil }
            if let value = try? container.decodeIfPresent(String.self, forKey: codingKey) { return value }
            if let value = try? container.decodeIfPresent(Int.self, forKey: codingKey) { return "\(value)" }
            if let value = try? container.decodeIfPresent(Double.self, forKey: codingKey) { return "\(value)" }
            return nil
        }
        func int(_ key: String) -> Int? {
            guard let codingKey = CodeMemoryDynamicCodingKey(stringValue: key) else { return nil }
            if let value = try? container.decodeIfPresent(Int.self, forKey: codingKey) { return value }
            if let value = try? container.decodeIfPresent(String.self, forKey: codingKey) { return Int(value) }
            return nil
        }
        kind = string("kind") ?? "source"
        uri = string("uri")
        path = string("path")
        contentHash = string("content_hash")
        sourceID = string("source_id")
        episodeID = string("episode_id")
        lineStart = int("line_start")
        lineEnd = int("line_end")
        quote = string("quote")

        let known = Set(["kind", "uri", "path", "content_hash", "source_id", "episode_id", "line_start", "line_end", "quote"])
        var extras: [String: String] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                extras[key.stringValue] = value
            } else if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                extras[key.stringValue] = "\(value)"
            } else if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                extras[key.stringValue] = "\(value)"
            }
        }
        metadata = extras
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodeMemoryDynamicCodingKey.self)
        try container.encode(kind, forKey: CodeMemoryDynamicCodingKey("kind"))
        try container.encodeIfPresent(uri, forKey: CodeMemoryDynamicCodingKey("uri"))
        try container.encodeIfPresent(path, forKey: CodeMemoryDynamicCodingKey("path"))
        try container.encodeIfPresent(contentHash, forKey: CodeMemoryDynamicCodingKey("content_hash"))
        try container.encodeIfPresent(sourceID, forKey: CodeMemoryDynamicCodingKey("source_id"))
        try container.encodeIfPresent(episodeID, forKey: CodeMemoryDynamicCodingKey("episode_id"))
        try container.encodeIfPresent(lineStart, forKey: CodeMemoryDynamicCodingKey("line_start"))
        try container.encodeIfPresent(lineEnd, forKey: CodeMemoryDynamicCodingKey("line_end"))
        try container.encodeIfPresent(quote, forKey: CodeMemoryDynamicCodingKey("quote"))
        for (key, value) in metadata {
            try container.encode(value, forKey: CodeMemoryDynamicCodingKey(key))
        }
    }
}

private struct CodeMemoryDynamicCodingKey: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }
}

struct CodeMemoryMemory: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var projectID: String
    var type: String
    var status: String
    var title: String
    var body: String
    var normalizedClaim: String
    var confidence: Double
    var importance: Double
    var scopes: [CodeMemoryScope]
    var sourceRefs: [CodeMemorySourceRef]
    var metadata: [String: String]?
    var validAt: Double? = nil
    var invalidAt: Double? = nil
    var reviewReason: String? = nil
    var extractedBy: String? = nil
    var createdAt: Double
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case type
        case status
        case title
        case body
        case normalizedClaim = "normalized_claim"
        case confidence
        case importance
        case scopes
        case sourceRefs = "source_refs"
        case metadata
        case validAt = "valid_at"
        case invalidAt = "invalid_at"
        case reviewReason = "review_reason"
        case extractedBy = "extracted_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CodeMemorySearchResult: Codable, Identifiable, Sendable, Hashable {
    var rank: Int
    var score: Double
    var memory: CodeMemoryMemory
    var matchKind: String
    var evidence: [CodeMemoryEvidence]? = nil

    var id: String { memory.id }

    enum CodingKeys: String, CodingKey {
        case rank
        case score
        case memory
        case matchKind = "match_kind"
        case evidence
    }
}

struct CodeMemoryEvidence: Codable, Identifiable, Sendable, Hashable {
    var adapter: String
    var score: Double
    var detail: String

    var id: String { "\(adapter)-\(detail)-\(score)" }
}

struct CodeMemorySearchResponse: Codable, Sendable, Hashable {
    var query: String
    var traceID: String
    var results: [CodeMemorySearchResult]

    enum CodingKeys: String, CodingKey {
        case query
        case traceID = "trace_id"
        case results
    }
}

struct CodeMemoryQueryFilter: Codable, Sendable, Hashable {
    var projectID: String?
    var moduleID: String?
    var statuses: [String]
    var types: [String]
    var sourceKinds: [String]
    var asOf: Double?
    var includeGraphFacts: Bool
    var limit: Int

    init(
        projectID: String? = nil,
        moduleID: String? = nil,
        statuses: [String] = ["active"],
        types: [String] = [],
        sourceKinds: [String] = [],
        asOf: Double? = nil,
        includeGraphFacts: Bool = true,
        limit: Int = 30
    ) {
        self.projectID = projectID
        self.moduleID = moduleID
        self.statuses = statuses
        self.types = types
        self.sourceKinds = sourceKinds
        self.asOf = asOf
        self.includeGraphFacts = includeGraphFacts
        self.limit = limit
    }

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case moduleID = "module_id"
        case statuses
        case types
        case sourceKinds = "source_kinds"
        case asOf = "as_of"
        case includeGraphFacts = "include_graph_facts"
        case limit
    }
}

struct CodeMemoryUnifiedSearchRequest: Codable, Sendable, Hashable {
    var query: String
    var filters: CodeMemoryQueryFilter
    var limit: Int
}

struct CodeMemoryUnifiedSearchResponse: Codable, Sendable, Hashable {
    var query: String
    var traceID: String
    var memoryResults: [CodeMemorySearchResult]
    var graphResults: [CodeMemoryGraphFact]
    var sourceResults: [CodeMemoryEpisode]

    enum CodingKeys: String, CodingKey {
        case query
        case traceID = "trace_id"
        case memoryResults = "memory_results"
        case graphResults = "graph_results"
        case sourceResults = "source_results"
    }
}

struct CodeMemoryProject: Codable, Identifiable, Sendable, Hashable {
    var projectID: String
    var memoryCount: Int
    var totalMemoryCount: Int? = nil
    var proposalCount: Int? = nil
    var updatedAt: Double?

    var id: String { projectID }
    var folderDisplayName: String {
        let trimmedProjectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProjectID.isEmpty else { return "Untitled" }

        let expandedPath = (trimmedProjectID as NSString).expandingTildeInPath
        let lastPathComponent = (expandedPath as NSString).lastPathComponent
        if !lastPathComponent.isEmpty {
            return lastPathComponent
        }

        return trimmedProjectID.memoryAbbreviatingHomeDirectory
    }

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case memoryCount = "memory_count"
        case totalMemoryCount = "total_memory_count"
        case proposalCount = "proposal_count"
        case updatedAt = "updated_at"
    }
}

struct CodeMemoryProjectsResponse: Codable, Sendable, Hashable {
    var projects: [CodeMemoryProject]
}

struct CodeMemoryGraphNode: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var kind: String
    var title: String
    var type: String?
    var status: String?
    var seq: Int?
    var body: String?
    var sourceRefs: [CodeMemorySourceRef]?
    var metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case type
        case status
        case seq
        case body
        case sourceRefs = "source_refs"
        case metadata
    }
}

struct CodeMemoryGraphEdge: Codable, Identifiable, Sendable, Hashable {
    var source: String
    var target: String
    var kind: String
    var primary: Bool?
    var fact: String? = nil
    var validAt: String? = nil
    var invalidAt: String? = nil
    var metadata: [String: String]?

    var id: String {
        let base = "\(source)-\(kind)-\(target)"
        var details: [String] = []
        if let fact, !fact.isEmpty {
            details.append("fact=\(fact)")
        }
        if let validAt, !validAt.isEmpty {
            details.append("valid=\(validAt)")
        }
        if let invalidAt, !invalidAt.isEmpty {
            details.append("invalid=\(invalidAt)")
        }
        if let metadata, !metadata.isEmpty {
            details.append(contentsOf: metadata.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" })
        }
        guard !details.isEmpty else { return base }
        return "\(base)-\(Self.stableSuffix(for: details.joined(separator: "|")))"
    }

    var factText: String? { fact ?? metadata?["fact"] }
    var validAtLabel: String? { validAt ?? metadata?["valid_at"] }
    var invalidAtLabel: String? { invalidAt ?? metadata?["invalid_at"] }

    enum CodingKeys: String, CodingKey {
        case source
        case target
        case kind
        case primary
        case fact
        case validAt = "valid_at"
        case invalidAt = "invalid_at"
        case metadata
    }

    private static func stableSuffix(for text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

struct CodeMemoryGraph: Codable, Sendable, Hashable {
    var projectID: String
    var nodes: [CodeMemoryGraphNode]
    var edges: [CodeMemoryGraphEdge]
    var truncated: Bool? = nil
    var totalNodes: Int? = nil
    var totalEdges: Int? = nil
    var visibleNodes: Int? = nil
    var visibleEdges: Int? = nil
    var nodeLimit: Int? = nil
    var edgeLimit: Int? = nil

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case nodes
        case edges
        case truncated
        case totalNodes = "total_nodes"
        case totalEdges = "total_edges"
        case visibleNodes = "visible_nodes"
        case visibleEdges = "visible_edges"
        case nodeLimit = "node_limit"
        case edgeLimit = "edge_limit"
    }
}

struct CodeMemoryRunTrace: Codable, Sendable, Hashable {
    var runID: String
    var projectID: String?
    var timestamp: Double?
    var request: [String: String]?
    var repoState: [String: String]
    var memoryUsage: [CodeMemoryTraceUsage]

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case projectID = "project_id"
        case timestamp
        case request
        case repoState = "repo_state"
        case memoryUsage = "memory_usage"
    }
}

struct CodeMemoryTraceUsage: Codable, Identifiable, Sendable, Hashable {
    var runID: String
    var memoryID: String
    var usageKind: String
    var rank: Int
    var score: Double
    var featuresJSON: String? = nil

    var id: String { "\(runID)-\(memoryID)-\(usageKind)-\(rank)" }

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case memoryID = "memory_id"
        case usageKind = "usage_kind"
        case rank
        case score
        case featuresJSON = "features_json"
    }
}

struct CodeMemoryContextPack: Codable, Sendable, Hashable {
    var query: String
    var traceID: String
    var context: CodeMemoryContextGroups
    var graphFacts: [CodeMemoryGraphFact] = []
    var sources: [CodeMemoryEpisode] = []

    init(
        query: String,
        traceID: String,
        context: CodeMemoryContextGroups,
        graphFacts: [CodeMemoryGraphFact] = [],
        sources: [CodeMemoryEpisode] = []
    ) {
        self.query = query
        self.traceID = traceID
        self.context = context
        self.graphFacts = graphFacts
        self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
        case query
        case traceID = "trace_id"
        case context
        case graphFacts = "graph_facts"
        case sources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try container.decode(String.self, forKey: .query)
        traceID = try container.decode(String.self, forKey: .traceID)
        context = try container.decode(CodeMemoryContextGroups.self, forKey: .context)
        graphFacts = try container.decodeIfPresent([CodeMemoryGraphFact].self, forKey: .graphFacts) ?? []
        sources = try container.decodeIfPresent([CodeMemoryEpisode].self, forKey: .sources) ?? []
    }
}

struct CodeMemoryContextGroups: Codable, Sendable, Hashable {
    var rules: [CodeMemoryMemory]
    var facts: [CodeMemoryMemory]
    var risks: [CodeMemoryMemory]
    var commands: [CodeMemoryMemory]
    var decisions: [CodeMemoryMemory]
}

struct CodeMemoryMemoriesResponse: Codable, Sendable, Hashable {
    var memories: [CodeMemoryMemory]
}

struct CodeMemoryGraphFact: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var projectID: String
    var title: String
    var fact: String
    var relation: String?
    var source: String?
    var target: String?
    var validAt: String?
    var invalidAt: String?
    var score: Double?
    var sourceRefs: [CodeMemorySourceRef]
    var metadata: [String: String]?
    var evidence: [CodeMemoryEvidence]?

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case title
        case fact
        case relation
        case source
        case target
        case validAt = "valid_at"
        case invalidAt = "invalid_at"
        case score
        case sourceRefs = "source_refs"
        case metadata
        case evidence
    }
}

struct CodeMemoryEpisode: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var projectID: String
    var kind: String
    var title: String
    var uri: String?
    var path: String?
    var contentHash: String?
    var excerpt: String?
    var metadata: [String: String]?
    var updatedAt: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case kind
        case title
        case uri
        case path
        case contentHash = "content_hash"
        case excerpt
        case metadata
        case updatedAt = "updated_at"
    }
}

struct CodeMemoryReviewItemsResponse: Codable, Sendable, Hashable {
    var proposals: [CodeMemoryMemory]
    var conflicts: [CodeMemoryMemory]
    var lowConfidence: [CodeMemoryMemory]
    var graphFacts: [CodeMemoryGraphFact]

    enum CodingKeys: String, CodingKey {
        case proposals
        case conflicts
        case lowConfidence = "low_confidence"
        case graphFacts = "graph_facts"
    }
}

struct CodeMemoryRuntimeContext: Codable, Sendable, Hashable {
    var pack: CodeMemoryContextPack
    var enabledForPromptInjection: Bool = false
}

struct CodeMemoryModule: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var projectID: String
    var scopeID: String
    var title: String
    var classifier: String
    var memoryCount: Int
    var totalMemoryCount: Int? = nil
    var updatedAt: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case scopeID = "scope_id"
        case title
        case classifier
        case memoryCount = "memory_count"
        case totalMemoryCount = "total_memory_count"
        case updatedAt = "updated_at"
    }
}

struct CodeMemoryModulesResponse: Codable, Sendable, Hashable {
    var modules: [CodeMemoryModule]
}

enum CodeMemoryEventPayloadValue: Codable, Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: CodeMemoryEventPayloadValue])
    case array([CodeMemoryEventPayloadValue])
    case null

    var displayString: String {
        switch self {
        case .string(let value):
            value
        case .int(let value):
            "\(value)"
        case .double(let value):
            "\(value)"
        case .bool(let value):
            value ? "true" : "false"
        case .object(let value):
            value
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.displayString)" }
                .joined(separator: ", ")
        case .array(let value):
            value.map(\.displayString).joined(separator: ", ")
        case .null:
            "null"
        }
    }

    var objectValue: [String: CodeMemoryEventPayloadValue]? {
        if case .object(let value) = self {
            value
        } else {
            nil
        }
    }

    var arrayValue: [CodeMemoryEventPayloadValue]? {
        if case .array(let value) = self {
            value
        } else {
            nil
        }
    }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(Int.self) {
            self = .int(value)
        } else if let value = try? single.decode(Double.self) {
            self = .double(value)
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else if let value = try? single.decode([CodeMemoryEventPayloadValue].self) {
            self = .array(value)
        } else {
            let keyed = try decoder.container(keyedBy: CodeMemoryDynamicCodingKey.self)
            var value: [String: CodeMemoryEventPayloadValue] = [:]
            for key in keyed.allKeys {
                value[key.stringValue] = try keyed.decode(CodeMemoryEventPayloadValue.self, forKey: key)
            }
            self = .object(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .double(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .object(let value):
            var container = encoder.container(keyedBy: CodeMemoryDynamicCodingKey.self)
            for (key, item) in value {
                try container.encode(item, forKey: CodeMemoryDynamicCodingKey(key))
            }
        case .array(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

typealias CodeMemoryEventPayload = [String: CodeMemoryEventPayloadValue]

extension Dictionary where Key == String, Value == CodeMemoryEventPayloadValue {
    func displayValue(_ key: String) -> String? {
        self[key]?.displayString
    }
}

struct CodeMemoryEvent: Codable, Identifiable, Sendable, Hashable {
    var eventID: String
    var seq: Int
    var timestamp: Double
    var projectID: String
    var actor: [String: String]
    var eventType: String
    var memoryID: String?
    var before: CodeMemoryEventPayload?
    var after: CodeMemoryEventPayload?
    var delta: CodeMemoryEventPayload?
    var sourceRefs: [CodeMemorySourceRef]
    var hash: String
    var prevHash: String?

    var id: String { eventID }
    var titleCandidate: String {
        after?.displayValue("title")
            ?? before?.displayValue("title")
            ?? delta?.displayValue("title")
            ?? memoryID
            ?? eventID
    }

    var statusTransition: String? {
        let beforeStatus = before?.displayValue("status")
        let afterStatus = after?.displayValue("status")
        if let beforeStatus, let afterStatus, beforeStatus != afterStatus {
            return "\(beforeStatus) -> \(afterStatus)"
        }
        return afterStatus ?? beforeStatus
    }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case seq
        case timestamp
        case projectID = "project_id"
        case actor
        case eventType = "event_type"
        case memoryID = "memory_id"
        case before
        case after
        case delta
        case sourceRefs = "source_refs"
        case hash
        case prevHash = "prev_hash"
    }
}

struct CodeMemoryEventsResponse: Codable, Sendable, Hashable {
    var events: [CodeMemoryEvent]
}

struct CodeMemoryMemoryVersion: Codable, Identifiable, Sendable, Hashable {
    var memoryID: String
    var version: Int
    var eventID: String
    var eventType: String
    var projectID: String
    var timestamp: Double
    var title: String
    var body: String
    var type: String
    var status: String
    var normalizedClaim: String
    var confidence: Double
    var importance: Double
    var sourceRefs: [CodeMemorySourceRef]
    var metadata: [String: String]?
    var validAt: Double?
    var invalidAt: Double?
    var reviewReason: String?
    var extractedBy: String?
    var createdAt: Double
    var updatedAt: Double

    var id: String { "\(memoryID):v\(version)" }

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case version
        case eventID = "event_id"
        case eventType = "event_type"
        case projectID = "project_id"
        case timestamp
        case title
        case body
        case type
        case status
        case normalizedClaim = "normalized_claim"
        case confidence
        case importance
        case sourceRefs = "source_refs"
        case metadata
        case validAt = "valid_at"
        case invalidAt = "invalid_at"
        case reviewReason = "review_reason"
        case extractedBy = "extracted_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CodeMemoryMemoryHistory: Codable, Sendable, Hashable {
    var memoryID: String
    var versions: [CodeMemoryMemoryVersion]
    var events: [CodeMemoryEvent]

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case versions
        case events
    }
}

struct CodeMemoryProjectionDrainResponse: Codable, Sendable, Hashable {
    var delivered: Int? = nil
    var failed: Int? = nil
    var remaining: Int? = nil
    var pending: Int? = nil
    var failedTotal: Int? = nil
    var enqueued: Int? = nil
    var drained: CodeMemoryProjectionDrainStats? = nil
    var capture: CodeMemoryProjectionDrainStage? = nil
    var projection: CodeMemoryProjectionDrainStage? = nil
    var skipped: Bool? = nil
    var message: String? = nil
    var blockers: [String: String]? = nil

    enum CodingKeys: String, CodingKey {
        case delivered
        case failed
        case remaining
        case pending
        case failedTotal = "failed_total"
        case enqueued
        case drained
        case capture
        case projection
        case skipped
        case message
        case blockers
    }
}

struct CodeMemoryProjectionDrainStats: Codable, Sendable, Hashable {
    var delivered: Int? = nil
    var failed: Int? = nil
    var remaining: Int? = nil
}

struct CodeMemoryProjectionDrainStage: Codable, Sendable, Hashable {
    var delivered: Int? = nil
    var failed: Int? = nil
    var remaining: Int? = nil
    var pending: Int? = nil
    var failedTotal: Int? = nil
    var enqueued: Int? = nil
    var skipped: Bool? = nil
    var message: String? = nil
    var blockers: [String: String]? = nil

    enum CodingKeys: String, CodingKey {
        case delivered
        case failed
        case remaining
        case pending
        case failedTotal = "failed_total"
        case enqueued
        case skipped
        case message
        case blockers
    }
}

struct CodeMemoryInferenceError: Codable, Identifiable, Sendable, Hashable {
    var sourceID: String?
    var adapter: String
    var error: String

    var id: String {
        [sourceID, adapter, error]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case adapter
        case error
    }
}

struct CodeMemorySourceInput: Codable, Sendable, Hashable {
    var id: String?
    var projectID: String
    var title: String
    var body: String
    var kind: String
    var uri: String
    var path: String?
    var contentHash: String
    var infer: Bool
    var metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case title
        case body
        case kind
        case uri
        case path
        case contentHash = "content_hash"
        case infer
        case metadata
    }
}

struct CodeMemorySyncSourceResponse: Codable, Sendable, Hashable {
    var status: String
    var created: [CodeMemoryMemory]?
    var proposed: [CodeMemoryMemory]?
    var queued: Int? = nil
    var inferenceErrors: [CodeMemoryInferenceError]? = nil

    enum CodingKeys: String, CodingKey {
        case status
        case created
        case proposed
        case queued
        case inferenceErrors = "inference_errors"
    }
}

struct CodeMemoryReinferSourcesResponse: Codable, Sendable, Hashable {
    var status: String = "ok"
    var scanned: Int = 0
    var attempted: Int = 0
    var created: Int = 0
    var proposed: Int = 0
    var skipped: Int = 0
    var errors: [CodeMemoryInferenceError] = []
}

struct CodeMemoryEventInput: Codable, Sendable, Hashable {
    var projectID: String
    var eventType: String
    var actor: [String: String]
    var after: CodeMemoryNewMemory?
    var sourceRefs: [CodeMemorySourceRef]

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case eventType = "event_type"
        case actor
        case after
        case sourceRefs = "source_refs"
    }
}

struct CodeMemoryNewMemory: Codable, Sendable, Hashable {
    var projectID: String
    var title: String
    var body: String
    var type: String
    var status: String? = nil
    var scope: CodeMemoryNewScope
    var scopes: [CodeMemoryNewScope]? = nil
    var sourceRefs: [CodeMemorySourceRef]
    var metadata: [String: String]? = nil

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case title
        case body
        case type
        case status
        case scope
        case scopes
        case sourceRefs = "source_refs"
        case metadata
    }
}

struct CodeMemoryNewScope: Codable, Sendable, Hashable {
    var kind: String
    var key: String
    var title: String?
}
