import Foundation

protocol CodeMemoryBackend: Sendable {
    func health() async throws -> CodeMemoryHealth
    func projects() async throws -> [CodeMemoryProject]
    func modules(projectID: String?) async throws -> [CodeMemoryModule]
    func memories(filter: CodeMemoryQueryFilter) async throws -> [CodeMemoryMemory]
    func search(query: String, projectID: String?, limit: Int) async throws -> CodeMemorySearchResponse
    func unifiedSearch(query: String, filter: CodeMemoryQueryFilter) async throws -> CodeMemoryUnifiedSearchResponse
    func contextPack(query: String, projectID: String?, limit: Int) async throws -> CodeMemoryContextPack
    func graph(projectID: String) async throws -> CodeMemoryGraph
    func trace(runID: String) async throws -> CodeMemoryRunTrace
    func events(projectID: String?, afterSeq: Int?, limit: Int) async throws -> [CodeMemoryEvent]
    func memoryHistory(memoryID: String, limit: Int) async throws -> CodeMemoryMemoryHistory
    func proposals(projectID: String?, limit: Int) async throws -> [CodeMemoryMemory]
    func reviewItems(projectID: String?, limit: Int) async throws -> CodeMemoryReviewItemsResponse
    func accept(memoryID: String) async throws
    func reject(memoryID: String) async throws
    func deprecate(memoryID: String) async throws
    func update(memoryID: String, memory: CodeMemoryMemoryUpdate) async throws
    func promoteGraphFact(_ fact: CodeMemoryGraphFact) async throws -> CodeMemoryMemory
    func drainProjections() async throws -> CodeMemoryProjectionDrainResponse
    func drainProjections(includeFailed: Bool) async throws -> CodeMemoryProjectionDrainResponse
    func drainCaptures(limit: Int, includeFailed: Bool) async throws -> CodeMemoryProjectionDrainResponse
    func reindex(projectID: String?) async throws -> CodeMemoryProjectionDrainResponse
    func reinferSources(projectID: String?) async throws -> CodeMemoryReinferSourcesResponse
    func ingestSource(_ source: CodeMemorySourceInput) async throws -> CodeMemorySyncSourceResponse
    func recordEvent(_ event: CodeMemoryEventInput) async throws
    func configureDiagnostics(retentionDays: Int) async throws -> CodeMemoryDiagnosticsConfigurationResponse
}

extension CodeMemoryBackend {
    func modules(projectID: String?) async throws -> [CodeMemoryModule] { [] }
    func memories(filter: CodeMemoryQueryFilter) async throws -> [CodeMemoryMemory] { [] }
    func unifiedSearch(query: String, filter: CodeMemoryQueryFilter) async throws -> CodeMemoryUnifiedSearchResponse {
        let response = try await search(query: query, projectID: filter.projectID, limit: filter.limit)
        return CodeMemoryUnifiedSearchResponse(
            query: response.query,
            traceID: response.traceID,
            memoryResults: response.results,
            graphResults: [],
            sourceResults: []
        )
    }
    func contextPack(query: String, projectID: String?, limit: Int) async throws -> CodeMemoryContextPack {
        let response = try await search(query: query, projectID: projectID, limit: limit)
        return CodeMemoryContextPack(
            query: response.query,
            traceID: response.traceID,
            context: CodeMemoryContextGroups(rules: [], facts: response.results.map(\.memory), risks: [], commands: [], decisions: [])
        )
    }
    func events(projectID: String?, afterSeq: Int?, limit: Int) async throws -> [CodeMemoryEvent] { [] }
    func memoryHistory(memoryID: String, limit: Int) async throws -> CodeMemoryMemoryHistory {
        CodeMemoryMemoryHistory(memoryID: memoryID, versions: [], events: [])
    }
    func proposals(projectID: String?, limit: Int) async throws -> [CodeMemoryMemory] { [] }
    func reviewItems(projectID: String?, limit: Int) async throws -> CodeMemoryReviewItemsResponse {
        CodeMemoryReviewItemsResponse(proposals: try await proposals(projectID: projectID, limit: limit), conflicts: [], lowConfidence: [], graphFacts: [])
    }
    func accept(memoryID: String) async throws {}
    func reject(memoryID: String) async throws {}
    func deprecate(memoryID: String) async throws {}
    func update(memoryID: String, memory: CodeMemoryMemoryUpdate) async throws {}
    func promoteGraphFact(_ fact: CodeMemoryGraphFact) async throws -> CodeMemoryMemory {
        CodeMemoryMemory(
            id: fact.id,
            projectID: fact.projectID,
            type: "fact",
            status: "proposed",
            title: fact.title,
            body: fact.fact,
            normalizedClaim: fact.id,
            confidence: fact.score ?? 0.5,
            importance: 0.5,
            scopes: [],
            sourceRefs: fact.sourceRefs,
            metadata: fact.metadata,
            validAt: nil,
            invalidAt: nil,
            reviewReason: "graph_fact_promotion",
            extractedBy: "graphiti",
            createdAt: 0,
            updatedAt: 0
        )
    }
    func drainProjections() async throws -> CodeMemoryProjectionDrainResponse { CodeMemoryProjectionDrainResponse() }
    func drainProjections(includeFailed: Bool) async throws -> CodeMemoryProjectionDrainResponse { try await drainProjections() }
    func drainCaptures(limit: Int, includeFailed: Bool) async throws -> CodeMemoryProjectionDrainResponse {
        try await drainProjections(includeFailed: includeFailed)
    }
    func reindex(projectID: String?) async throws -> CodeMemoryProjectionDrainResponse { CodeMemoryProjectionDrainResponse() }
    func reinferSources(projectID: String?) async throws -> CodeMemoryReinferSourcesResponse { CodeMemoryReinferSourcesResponse() }
    func ingestSource(_ source: CodeMemorySourceInput) async throws -> CodeMemorySyncSourceResponse {
        CodeMemorySyncSourceResponse(status: "unsupported", created: nil, proposed: nil)
    }
    func configureDiagnostics(retentionDays: Int) async throws -> CodeMemoryDiagnosticsConfigurationResponse {
        CodeMemoryDiagnosticsConfigurationResponse(status: "unsupported")
    }
}

struct CodeMemoryHTTPClient: CodeMemoryBackend {
    var baseURL: URL
    var session: URLSession = .shared

    init(baseURL: URL = URL(string: "http://127.0.0.1:8765")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func health() async throws -> CodeMemoryHealth {
        try await get("/health")
    }

    func projects() async throws -> [CodeMemoryProject] {
        let response: CodeMemoryProjectsResponse = try await get("/v1/projects")
        return response.projects
    }

    func modules(projectID: String?) async throws -> [CodeMemoryModule] {
        var items: [URLQueryItem] = []
        if let projectID, !projectID.isEmpty {
            items.append(URLQueryItem(name: "project_id", value: projectID))
        }
        let response: CodeMemoryModulesResponse = try await get("/v1/modules", queryItems: items)
        return response.modules
    }

    func memories(filter: CodeMemoryQueryFilter) async throws -> [CodeMemoryMemory] {
        var items = [URLQueryItem(name: "limit", value: "\(filter.limit)")]
        if let projectID = filter.projectID, !projectID.isEmpty {
            items.append(URLQueryItem(name: "project_id", value: projectID))
        }
        if let moduleID = filter.moduleID, !moduleID.isEmpty {
            items.append(URLQueryItem(name: "module_id", value: moduleID))
        }
        if let status = filter.statuses.first, !status.isEmpty {
            items.append(URLQueryItem(name: "status", value: status))
        }
        if let type = filter.types.first, !type.isEmpty {
            items.append(URLQueryItem(name: "type", value: type))
        }
        let response: CodeMemoryMemoriesResponse = try await get("/v1/memories", queryItems: items)
        return response.memories
    }

    func search(query: String, projectID: String?, limit: Int = 20) async throws -> CodeMemorySearchResponse {
        var items = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        if let projectID, !projectID.isEmpty {
            items.append(URLQueryItem(name: "project_id", value: projectID))
        }
        return try await get("/v1/memories/search", queryItems: items)
    }

    func unifiedSearch(query: String, filter: CodeMemoryQueryFilter) async throws -> CodeMemoryUnifiedSearchResponse {
        try await post("/v1/search", body: CodeMemoryUnifiedSearchRequest(query: query, filters: filter, limit: filter.limit))
    }

    func contextPack(query: String, projectID: String?, limit: Int = 10) async throws -> CodeMemoryContextPack {
        try await post("/v1/context", body: CodeMemoryContextRequest(query: query, projectID: projectID, limit: limit))
    }

    func graph(projectID: String) async throws -> CodeMemoryGraph {
        try await get(
            "/v1/projects/\(Self.pathSegment(projectID))/graph",
            queryItems: [
                URLQueryItem(name: "node_limit", value: "700"),
                URLQueryItem(name: "edge_limit", value: "1200"),
                URLQueryItem(name: "include_events", value: "false"),
                URLQueryItem(name: "include_sources", value: "true"),
                URLQueryItem(name: "include_adapter", value: "true"),
            ]
        )
    }

    func trace(runID: String) async throws -> CodeMemoryRunTrace {
        try await get("/v1/runs/\(Self.pathSegment(runID))/trace")
    }

    func events(projectID: String?, afterSeq: Int?, limit: Int = 100) async throws -> [CodeMemoryEvent] {
        var items = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let projectID, !projectID.isEmpty {
            items.append(URLQueryItem(name: "project_id", value: projectID))
        }
        if let afterSeq {
            items.append(URLQueryItem(name: "after_seq", value: "\(afterSeq)"))
        }
        let response: CodeMemoryEventsResponse = try await get("/v1/events", queryItems: items)
        return response.events
    }

    func memoryHistory(memoryID: String, limit: Int = 200) async throws -> CodeMemoryMemoryHistory {
        try await get(
            "/v1/memories/\(Self.pathSegment(memoryID))/history",
            queryItems: [URLQueryItem(name: "limit", value: "\(limit)")]
        )
    }

    func proposals(projectID: String?, limit: Int = 100) async throws -> [CodeMemoryMemory] {
        var items = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let projectID, !projectID.isEmpty {
            items.append(URLQueryItem(name: "project_id", value: projectID))
        }
        let response: CodeMemoryMemoriesResponse = try await get("/v1/memories/proposals", queryItems: items)
        return response.memories
    }

    func reviewItems(projectID: String?, limit: Int = 100) async throws -> CodeMemoryReviewItemsResponse {
        var items = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let projectID, !projectID.isEmpty {
            items.append(URLQueryItem(name: "project_id", value: projectID))
        }
        return try await get("/v1/review/items", queryItems: items)
    }

    func accept(memoryID: String) async throws {
        let _: EmptyResponse = try await post("/v1/memories/\(Self.pathSegment(memoryID))/accept", body: CodeMemoryActorRequest(actor: ["kind": "human", "id": NSUserName()]))
    }

    func reject(memoryID: String) async throws {
        let _: EmptyResponse = try await post("/v1/memories/\(Self.pathSegment(memoryID))/reject", body: CodeMemoryActorRequest(actor: ["kind": "human", "id": NSUserName()]))
    }

    func deprecate(memoryID: String) async throws {
        let _: EmptyResponse = try await post("/v1/memories/\(Self.pathSegment(memoryID))/deprecate", body: CodeMemoryActorRequest(actor: ["kind": "human", "id": NSUserName()]))
    }

    func update(memoryID: String, memory: CodeMemoryMemoryUpdate) async throws {
        let _: EmptyResponse = try await post("/v1/memories/\(Self.pathSegment(memoryID))/update", body: memory)
    }

    func promoteGraphFact(_ fact: CodeMemoryGraphFact) async throws -> CodeMemoryMemory {
        struct PromoteResponse: Decodable {
            var memory: CodeMemoryMemory?
        }
        let response: PromoteResponse = try await post("/v1/graph-facts/promote", body: fact)
        if let memory = response.memory {
            return memory
        }
        throw CodeMemoryHTTPError.status(-1, "Graph fact promotion returned no memory")
    }

    func drainProjections() async throws -> CodeMemoryProjectionDrainResponse {
        try await drainProjections(includeFailed: false)
    }

    func drainProjections(includeFailed: Bool) async throws -> CodeMemoryProjectionDrainResponse {
        try await drainCaptures(limit: 10, includeFailed: includeFailed)
    }

    func drainCaptures(limit: Int, includeFailed: Bool) async throws -> CodeMemoryProjectionDrainResponse {
        try await post(
            "/v1/projections/drain",
            body: CodeMemoryProjectionDrainRequest(limit: limit, includeFailed: includeFailed),
            timeout: 300
        )
    }

    func reindex(projectID: String?) async throws -> CodeMemoryProjectionDrainResponse {
        try await post("/v1/reindex", body: CodeMemoryProjectRequest(projectID: projectID))
    }

    func reinferSources(projectID: String?) async throws -> CodeMemoryReinferSourcesResponse {
        try await post("/v1/sources/reinfer", body: CodeMemoryReinferSourcesRequest(projectID: projectID, sourceID: nil, limit: 50))
    }

    func ingestSource(_ source: CodeMemorySourceInput) async throws -> CodeMemorySyncSourceResponse {
        try await post("/v1/sync/source", body: source)
    }

    func recordEvent(_ event: CodeMemoryEventInput) async throws {
        let _: EmptyResponse = try await post("/v1/events", body: event)
    }

    func configureDiagnostics(retentionDays: Int) async throws -> CodeMemoryDiagnosticsConfigurationResponse {
        try await post("/v1/diagnostics/configure", body: CodeMemoryDiagnosticsConfigurationRequest(retentionDays: retentionDays))
    }

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let url = try makeURL(path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder.codeMemoryDecoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, Body: Encodable>(_ path: String, body: Body, timeout: TimeInterval = 20) async throws -> T {
        let url = try makeURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.codeMemoryEncoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        return try JSONDecoder.codeMemoryDecoder.decode(T.self, from: data)
    }

    private func makeURL(_ path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        let slashSet = CharacterSet(charactersIn: "/")
        let basePath = components.percentEncodedPath.trimmingCharacters(in: slashSet)
        let requestPath = path.trimmingCharacters(in: slashSet)
        let percentEncodedPath = [basePath, requestPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.percentEncodedPath = percentEncodedPath.isEmpty ? "/" : "/\(percentEncodedPath)"
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw CodeMemoryHTTPError.status(http.statusCode, text)
        }
    }

    private static func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "%/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct EmptyResponse: Decodable {}

private struct CodeMemoryContextRequest: Encodable {
    var query: String
    var projectID: String?
    var limit: Int

    enum CodingKeys: String, CodingKey {
        case query
        case projectID = "project_id"
        case limit
    }
}

private struct CodeMemoryActorRequest: Encodable {
    var actor: [String: String]
}

struct CodeMemoryMemoryUpdate: Codable, Sendable, Hashable {
    var title: String?
    var body: String?
    var type: String?
    var status: String?
    var confidence: Double?
    var importance: Double?
    var validAt: Double?
    var invalidAt: Double?
    var reviewReason: String?
    var extractedBy: String?

    enum CodingKeys: String, CodingKey {
        case title
        case body
        case type
        case status
        case confidence
        case importance
        case validAt = "valid_at"
        case invalidAt = "invalid_at"
        case reviewReason = "review_reason"
        case extractedBy = "extracted_by"
    }
}

private struct CodeMemoryProjectRequest: Encodable {
    var projectID: String?

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
    }
}

private struct CodeMemoryReinferSourcesRequest: Encodable {
    var projectID: String?
    var sourceID: String?
    var limit: Int

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case sourceID = "source_id"
        case limit
    }
}

private struct CodeMemoryProjectionDrainRequest: Encodable {
    var limit: Int
    var includeFailed: Bool

    enum CodingKeys: String, CodingKey {
        case limit
        case includeFailed = "include_failed"
    }
}

private struct CodeMemoryDiagnosticsConfigurationRequest: Encodable {
    var retentionDays: Int

    enum CodingKeys: String, CodingKey {
        case retentionDays = "retention_days"
    }
}

enum CodeMemoryHTTPError: Error, LocalizedError {
    case status(Int, String)

    var errorDescription: String? {
        switch self {
        case .status(let code, let body):
            "Code Memory sidecar returned HTTP \(code): \(body)"
        }
    }
}

extension JSONEncoder {
    static var codeMemoryEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var codeMemoryDecoder: JSONDecoder {
        JSONDecoder()
    }
}
