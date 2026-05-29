import Foundation

protocol CodeMemoryBackend: Sendable {
    func health() async throws -> CodeMemoryHealth
    func projects() async throws -> [CodeMemoryProject]
    func modules(projectID: String?) async throws -> [CodeMemoryModule]
    func search(query: String, projectID: String?, limit: Int) async throws -> CodeMemorySearchResponse
    func contextPack(query: String, projectID: String?, limit: Int) async throws -> CodeMemoryContextPack
    func graph(projectID: String) async throws -> CodeMemoryGraph
    func trace(runID: String) async throws -> CodeMemoryRunTrace
    func events(projectID: String?, afterSeq: Int?, limit: Int) async throws -> [CodeMemoryEvent]
    func proposals(projectID: String?, limit: Int) async throws -> [CodeMemoryMemory]
    func accept(memoryID: String) async throws
    func reject(memoryID: String) async throws
    func deprecate(memoryID: String) async throws
    func drainProjections() async throws -> CodeMemoryProjectionDrainResponse
    func reindex(projectID: String?) async throws -> CodeMemoryProjectionDrainResponse
    func ingestSource(_ source: CodeMemorySourceInput) async throws -> CodeMemorySyncSourceResponse
    func recordEvent(_ event: CodeMemoryEventInput) async throws
}

extension CodeMemoryBackend {
    func modules(projectID: String?) async throws -> [CodeMemoryModule] { [] }
    func contextPack(query: String, projectID: String?, limit: Int) async throws -> CodeMemoryContextPack {
        let response = try await search(query: query, projectID: projectID, limit: limit)
        return CodeMemoryContextPack(
            query: response.query,
            traceID: response.traceID,
            context: CodeMemoryContextGroups(rules: [], facts: response.results.map(\.memory), risks: [], commands: [], decisions: [])
        )
    }
    func events(projectID: String?, afterSeq: Int?, limit: Int) async throws -> [CodeMemoryEvent] { [] }
    func proposals(projectID: String?, limit: Int) async throws -> [CodeMemoryMemory] { [] }
    func accept(memoryID: String) async throws {}
    func reject(memoryID: String) async throws {}
    func deprecate(memoryID: String) async throws {}
    func drainProjections() async throws -> CodeMemoryProjectionDrainResponse { CodeMemoryProjectionDrainResponse() }
    func reindex(projectID: String?) async throws -> CodeMemoryProjectionDrainResponse { CodeMemoryProjectionDrainResponse() }
    func ingestSource(_ source: CodeMemorySourceInput) async throws -> CodeMemorySyncSourceResponse {
        CodeMemorySyncSourceResponse(status: "unsupported", created: nil, proposed: nil)
    }
}

struct CodeMemoryHTTPClient: CodeMemoryBackend {
    var baseURL: URL
    var session: URLSession = .shared

    init(baseURL: URL = URL(string: "http://127.0.0.1:8765")!) {
        self.baseURL = baseURL
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

    func contextPack(query: String, projectID: String?, limit: Int = 10) async throws -> CodeMemoryContextPack {
        try await post("/v1/context", body: CodeMemoryContextRequest(query: query, projectID: projectID, limit: limit))
    }

    func graph(projectID: String) async throws -> CodeMemoryGraph {
        try await get("/v1/projects/\(Self.pathSegment(projectID))/graph")
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

    func proposals(projectID: String?, limit: Int = 100) async throws -> [CodeMemoryMemory] {
        var items = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let projectID, !projectID.isEmpty {
            items.append(URLQueryItem(name: "project_id", value: projectID))
        }
        let response: CodeMemoryMemoriesResponse = try await get("/v1/memories/proposals", queryItems: items)
        return response.memories
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

    func drainProjections() async throws -> CodeMemoryProjectionDrainResponse {
        try await post("/v1/projections/drain", body: CodeMemoryProjectionDrainRequest(limit: 10, includeFailed: false))
    }

    func reindex(projectID: String?) async throws -> CodeMemoryProjectionDrainResponse {
        try await post("/v1/reindex", body: CodeMemoryProjectRequest(projectID: projectID))
    }

    func ingestSource(_ source: CodeMemorySourceInput) async throws -> CodeMemorySyncSourceResponse {
        try await post("/v1/sync/source", body: source)
    }

    func recordEvent(_ event: CodeMemoryEventInput) async throws {
        let _: EmptyResponse = try await post("/v1/events", body: event)
    }

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)
        return try JSONDecoder.codeMemoryDecoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.codeMemoryEncoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        return try JSONDecoder.codeMemoryDecoder.decode(T.self, from: data)
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
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
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

private struct CodeMemoryProjectRequest: Encodable {
    var projectID: String?

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
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
