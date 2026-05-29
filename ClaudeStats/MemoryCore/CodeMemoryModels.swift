import Foundation

struct CodeMemoryHealth: Codable, Sendable, Hashable {
    var status: String
    var store: String?
    var eventCount: Int
    var memoryCount: Int
    var proposalCount: Int? = nil
    var moduleCount: Int? = nil
    var projectionPending: Int? = nil
    var projectionFailed: Int? = nil
    var adapters: [String: String]

    enum CodingKeys: String, CodingKey {
        case status
        case store
        case eventCount = "event_count"
        case memoryCount = "memory_count"
        case proposalCount = "proposal_count"
        case moduleCount = "module_count"
        case projectionPending = "projection_pending"
        case projectionFailed = "projection_failed"
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
    var sourceRefs: [[String: String]]
    var metadata: [String: String]?
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

struct CodeMemoryProject: Codable, Identifiable, Sendable, Hashable {
    var projectID: String
    var memoryCount: Int
    var updatedAt: Double?

    var id: String { projectID }

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case memoryCount = "memory_count"
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
    var sourceRefs: [[String: String]]?
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

    var id: String { "\(source)-\(kind)-\(target)" }
}

struct CodeMemoryGraph: Codable, Sendable, Hashable {
    var projectID: String
    var nodes: [CodeMemoryGraphNode]
    var edges: [CodeMemoryGraphEdge]

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case nodes
        case edges
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

    enum CodingKeys: String, CodingKey {
        case query
        case traceID = "trace_id"
        case context
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

struct CodeMemoryModule: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var projectID: String
    var scopeID: String
    var title: String
    var classifier: String
    var memoryCount: Int
    var updatedAt: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case scopeID = "scope_id"
        case title
        case classifier
        case memoryCount = "memory_count"
        case updatedAt = "updated_at"
    }
}

struct CodeMemoryModulesResponse: Codable, Sendable, Hashable {
    var modules: [CodeMemoryModule]
}

struct CodeMemoryEvent: Codable, Identifiable, Sendable, Hashable {
    var eventID: String
    var seq: Int
    var timestamp: Double
    var projectID: String
    var actor: [String: String]
    var eventType: String
    var memoryID: String?
    var sourceRefs: [[String: String]]
    var hash: String
    var prevHash: String?

    var id: String { eventID }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case seq
        case timestamp
        case projectID = "project_id"
        case actor
        case eventType = "event_type"
        case memoryID = "memory_id"
        case sourceRefs = "source_refs"
        case hash
        case prevHash = "prev_hash"
    }
}

struct CodeMemoryEventsResponse: Codable, Sendable, Hashable {
    var events: [CodeMemoryEvent]
}

struct CodeMemoryProjectionDrainResponse: Codable, Sendable, Hashable {
    var delivered: Int? = nil
    var failed: Int? = nil
    var remaining: Int? = nil
    var enqueued: Int? = nil
    var drained: CodeMemoryProjectionDrainStats? = nil
}

struct CodeMemoryProjectionDrainStats: Codable, Sendable, Hashable {
    var delivered: Int? = nil
    var failed: Int? = nil
    var remaining: Int? = nil
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
}

struct CodeMemoryEventInput: Codable, Sendable, Hashable {
    var projectID: String
    var eventType: String
    var actor: [String: String]
    var after: CodeMemoryNewMemory?
    var sourceRefs: [[String: String]]

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
    var sourceRefs: [[String: String]]
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
