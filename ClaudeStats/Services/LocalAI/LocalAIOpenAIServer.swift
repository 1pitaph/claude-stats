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
    private let idleTimeout: TimeInterval?
    private let onIdleTimeout: (@MainActor @Sendable () -> Void)?
    private let queue = DispatchQueue(label: "com.claudestats.local-ai-openai-server")
    private var listener: NWListener?
    private var activeRequestCount = 0
    private var lastActivityDate = Date()
    private var idleCheckGeneration = 0

    init(
        service: LocalAIOpenAIService,
        token: String,
        port: UInt16 = 18_765,
        idleTimeout: TimeInterval? = nil,
        onIdleTimeout: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.service = service
        self.token = token
        self.port = port
        self.idleTimeout = idleTimeout
        self.onIdleTimeout = onIdleTimeout
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
        scheduleIdleCheckIfNeeded()
        return endpoint
    }

    func stop() {
        idleCheckGeneration += 1
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
                    await self.handle(request, connection: connection)
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

    private func handle(_ request: LocalAIHTTPRequest, connection: NWConnection) async {
        beginRequest()
        defer { endRequest() }

        guard request.path == "/health" || authorized(request) else {
            send(Self.errorResponse("Missing or invalid local API token.", status: 401, code: "unauthorized"), to: connection)
            return
        }

        if request.method == "POST", request.path == "/v1/chat/completions" {
            do {
                let decoded = try JSONDecoder().decode(LocalAIChatCompletionsRequest.self, from: request.body)
                if decoded.stream == true {
                    await sendStreamingChat(decoded, to: connection)
                    return
                }
            } catch {
                send(Self.errorResponse(error.localizedDescription, status: 400), to: connection)
                return
            }
        }

        let response = await route(authorizedRequest: request)
        send(response, to: connection)
    }

    private func beginRequest() {
        activeRequestCount += 1
        lastActivityDate = Date()
        idleCheckGeneration += 1
    }

    private func endRequest() {
        activeRequestCount = max(0, activeRequestCount - 1)
        lastActivityDate = Date()
        scheduleIdleCheckIfNeeded()
    }

    private func scheduleIdleCheckIfNeeded() {
        guard activeRequestCount == 0, listener != nil, let idleTimeout else { return }
        idleCheckGeneration += 1
        let generation = idleCheckGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(idleTimeout * 1_000_000_000))
            guard let self else { return }
            guard self.listener != nil, self.activeRequestCount == 0, self.idleCheckGeneration == generation else { return }
            guard Date().timeIntervalSince(self.lastActivityDate) >= idleTimeout else {
                self.scheduleIdleCheckIfNeeded()
                return
            }
            self.onIdleTimeout?()
        }
    }

    private func route(_ request: LocalAIHTTPRequest) async -> LocalAIHTTPResponse {
        guard request.path == "/health" || authorized(request) else {
            return Self.errorResponse("Missing or invalid local API token.", status: 401, code: "unauthorized")
        }
        return await route(authorizedRequest: request)
    }

    private func route(authorizedRequest request: LocalAIHTTPRequest) async -> LocalAIHTTPResponse {
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

    private func sendStreamingChat(_ request: LocalAIChatCompletionsRequest, to connection: NWConnection) async {
        do {
            let session = try await service.chatStream(request)
            try await sendStreamHeader(to: connection)
            do {
                try await sendStreamObject(
                    LocalAIChatCompletionsStreamResponse(
                        id: session.id,
                        created: session.created,
                        model: session.model,
                        choices: [
                            LocalAIChatCompletionsStreamResponse.Choice(
                                index: 0,
                                delta: LocalAIChatCompletionsStreamResponse.Delta(role: "assistant", content: nil),
                                finishReason: nil
                            ),
                        ]
                    ),
                    to: connection
                )
                for try await event in session.events {
                    switch event {
                    case .delta(let text):
                        try await sendStreamObject(
                            LocalAIChatCompletionsStreamResponse(
                                id: session.id,
                                created: session.created,
                                model: session.model,
                                choices: [
                                    LocalAIChatCompletionsStreamResponse.Choice(
                                        index: 0,
                                        delta: LocalAIChatCompletionsStreamResponse.Delta(role: nil, content: text),
                                        finishReason: nil
                                    ),
                                ]
                            ),
                            to: connection
                        )
                    case .completed(let finishReason):
                        try await sendStreamObject(
                            LocalAIChatCompletionsStreamResponse(
                                id: session.id,
                                created: session.created,
                                model: session.model,
                                choices: [
                                    LocalAIChatCompletionsStreamResponse.Choice(
                                        index: 0,
                                        delta: LocalAIChatCompletionsStreamResponse.Delta(role: nil, content: nil),
                                        finishReason: finishReason ?? "stop"
                                    ),
                                ]
                            ),
                            to: connection
                        )
                    }
                }
                try await sendStreamDone(to: connection)
            } catch {
                try? await sendStreamObject(
                    LocalAIAPIErrorResponse(
                        error: LocalAIAPIErrorResponse.ErrorBody(
                            message: error.localizedDescription,
                            type: "local_ai_error",
                            code: nil
                        )
                    ),
                    to: connection
                )
                try? await sendStreamDone(to: connection)
            }
            connection.cancel()
        } catch {
            let response = Self.errorResponse(error.localizedDescription, status: statusCode(for: error))
            send(response, to: connection)
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

    private func sendStreamHeader(to connection: NWConnection) async throws {
        var head = "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: text/event-stream; charset=utf-8\r\n"
        head += "Cache-Control: no-cache\r\n"
        head += "Connection: close\r\n\r\n"
        try await sendRaw(Data(head.utf8), to: connection)
    }

    private func sendStreamObject<T: Encodable>(_ value: T, to connection: NWConnection) async throws {
        let data = try JSONEncoder.localAIHTTPEncoder.encode(value)
        let payload = String(data: data, encoding: .utf8) ?? "{}"
        try await sendRaw(Data("data: \(payload)\n\n".utf8), to: connection)
    }

    private func sendStreamDone(to connection: NWConnection) async throws {
        try await sendRaw(Data("data: [DONE]\n\n".utf8), to: connection)
    }

    private func sendRaw(_ data: Data, to connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
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
