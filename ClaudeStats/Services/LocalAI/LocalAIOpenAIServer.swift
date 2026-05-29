import Foundation
@preconcurrency import Network

struct LocalAIOpenAIEndpoint: Sendable, Hashable {
    var baseURL: URL
    var token: String
}

private struct LocalAIHTTPRequest: Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}

private struct LocalAIHTTPResponse: Sendable {
    var status: Int
    var body: Data
    var contentType: String

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> LocalAIHTTPResponse {
        let data = (try? JSONEncoder.localAIHTTPEncoder.encode(value)) ?? Data("{}".utf8)
        return LocalAIHTTPResponse(status: status, body: data, contentType: "application/json; charset=utf-8")
    }
}

@MainActor
final class LocalAIOpenAIServer {
    private let service: LocalAIOpenAIService
    private let token: String
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.claudestats.local-ai-openai-server")
    private var listener: NWListener?

    init(service: LocalAIOpenAIService, token: String, port: UInt16 = 18_765) {
        self.service = service
        self.token = token
        self.port = port
    }

    var endpoint: LocalAIOpenAIEndpoint {
        LocalAIOpenAIEndpoint(baseURL: URL(string: "http://127.0.0.1:\(port)/v1")!, token: token)
    }

    var isRunning: Bool {
        listener != nil
    }

    func start() throws -> LocalAIOpenAIEndpoint {
        guard listener == nil else { return endpoint }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw URLError(.badURL)
        }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.accept(connection)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
        return endpoint
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection: connection, buffer: Data())
    }

    private func receive(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }
            var next = buffer
            if let data {
                next.append(data)
            }
            if let request = Self.parseRequest(next) {
                Task { @MainActor in
                    let response = await self.route(request)
                    self.send(response, to: connection)
                }
            } else if isComplete {
                Task { @MainActor in
                    self.send(Self.errorResponse("Malformed HTTP request.", status: 400), to: connection)
                }
            } else {
                Task { @MainActor in
                    self.receive(connection: connection, buffer: next)
                }
            }
        }
    }

    private func route(_ request: LocalAIHTTPRequest) async -> LocalAIHTTPResponse {
        guard request.path == "/health" || authorized(request) else {
            return Self.errorResponse("Missing or invalid local API token.", status: 401, code: "unauthorized")
        }

        do {
            switch (request.method, request.path) {
            case ("GET", "/health"):
                return .json(service.health())
            case ("GET", "/v1/models"):
                return .json(service.modelsResponse())
            case ("POST", "/v1/embeddings"):
                let decoded = try JSONDecoder().decode(LocalAIEmbeddingsRequest.self, from: request.body)
                return .json(try await service.embeddingsResponse(decoded))
            case ("POST", "/v1/chat/completions"):
                let decoded = try JSONDecoder().decode(LocalAIChatCompletionsRequest.self, from: request.body)
                return .json(try await service.chatResponse(decoded))
            default:
                return Self.errorResponse("Route not found.", status: 404, code: "not_found")
            }
        } catch {
            return Self.errorResponse(error.localizedDescription, status: statusCode(for: error))
        }
    }

    private func authorized(_ request: LocalAIHTTPRequest) -> Bool {
        let raw = request.headers["authorization"] ?? request.headers["Authorization"] ?? ""
        return raw == "Bearer \(token)"
    }

    private func send(_ response: LocalAIHTTPResponse, to connection: NWConnection) {
        let reason = HTTPURLResponse.localizedString(forStatusCode: response.status).capitalized
        var head = "HTTP/1.1 \(response.status) \(reason)\r\n"
        head += "Content-Type: \(response.contentType)\r\n"
        head += "Content-Length: \(response.body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    nonisolated private static func parseRequest(_ data: Data) -> LocalAIHTTPRequest? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
            headers[key.lowercased()] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = Data(data[bodyStart..<(bodyStart + contentLength)])
        let rawPath = parts[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? parts[1]
        return LocalAIHTTPRequest(method: parts[0], path: rawPath, headers: headers, body: body)
    }

    nonisolated private static func errorResponse(_ message: String, status: Int, code: String? = nil) -> LocalAIHTTPResponse {
        .json(
            LocalAIAPIErrorResponse(
                error: LocalAIAPIErrorResponse.ErrorBody(message: message, type: "local_ai_error", code: code)
            ),
            status: status
        )
    }

    private func statusCode(for error: Error) -> Int {
        switch error {
        case LocalAIOpenAIServiceError.unsupportedStreaming:
            400
        case LocalAIOpenAIServiceError.modelNotFound(_):
            404
        case LocalAIOpenAIServiceError.modelNotInstalled(_):
            409
        case LocalAIOpenAIServiceError.invalidRequest(_):
            400
        default:
            500
        }
    }
}

private extension JSONEncoder {
    static var localAIHTTPEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
