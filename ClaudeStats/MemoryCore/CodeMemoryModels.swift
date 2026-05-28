import Foundation

struct CodeMemoryHealth: Codable, Sendable, Hashable {
    var status: String
    var store: String?
    var eventCount: Int
    var memoryCount: Int
    var adapters: [String: String]

    enum CodingKeys: String, CodingKey {
        case status
        case store
        case eventCount = "event_count"
        case memoryCount = "memory_count"
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

    var id: String { memory.id }

    enum CodingKeys: String, CodingKey {
        case rank
        case score
        case memory
        case matchKind = "match_kind"
    }
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

    var id: String { "\(runID)-\(memoryID)-\(usageKind)-\(rank)" }

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case memoryID = "memory_id"
        case usageKind = "usage_kind"
        case rank
        case score
    }
}

struct CodeMemoryEventInput: Encodable, Sendable {
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

struct CodeMemoryNewMemory: Encodable, Sendable {
    var projectID: String
    var title: String
    var body: String
    var type: String
    var scope: CodeMemoryNewScope
    var sourceRefs: [[String: String]]

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case title
        case body
        case type
        case scope
        case sourceRefs = "source_refs"
    }
}

struct CodeMemoryNewScope: Encodable, Sendable {
    var kind: String
    var key: String
    var title: String?
}

struct CodeMemoryLegacyImportRequest: Encodable, Sendable {
    var projectID: String
    var records: [CodeMemoryLegacyRecord]

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case records
    }
}

struct CodeMemoryLegacyRecord: Encodable, Sendable {
    var id: String
    var ref: String
    var title: String
    var body: String
    var type: String
    var scope: CodeMemoryNewScope
}

struct CodeMemoryLegacyImportResponse: Codable, Sendable, Hashable {
    var imported: Int
    var skipped: Int
}
