import Foundation

protocol CodeMemoryBackend: Sendable {
    func health() async throws -> CodeMemoryHealth
    func projects() async throws -> [CodeMemoryProject]
    func search(query: String, projectID: String?, limit: Int) async throws -> CodeMemorySearchResponse
    func graph(projectID: String) async throws -> CodeMemoryGraph
    func trace(runID: String) async throws -> CodeMemoryRunTrace
    func recordEvent(_ event: CodeMemoryEventInput) async throws
    func importLegacy(_ request: CodeMemoryLegacyImportRequest) async throws -> CodeMemoryLegacyImportResponse
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

    func graph(projectID: String) async throws -> CodeMemoryGraph {
        try await get("/v1/projects/\(projectID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectID)/graph")
    }

    func trace(runID: String) async throws -> CodeMemoryRunTrace {
        try await get("/v1/runs/\(runID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? runID)/trace")
    }

    func recordEvent(_ event: CodeMemoryEventInput) async throws {
        let _: EmptyResponse = try await post("/v1/events", body: event)
    }

    func importLegacy(_ request: CodeMemoryLegacyImportRequest) async throws -> CodeMemoryLegacyImportResponse {
        try await post("/v1/legacy/import", body: request)
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
}

private struct EmptyResponse: Decodable {}

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
