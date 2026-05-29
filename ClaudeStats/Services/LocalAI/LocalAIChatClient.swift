import Foundation

enum LocalAIChatClientError: Error, LocalizedError, Sendable {
    case invalidEndpoint
    case httpStatus(Int, String)
    case api(String)
    case malformedStream(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "The local chat endpoint is invalid."
        case .httpStatus(let status, let body):
            body.isEmpty ? "Local chat request failed with HTTP \(status)." : body
        case .api(let message):
            message
        case .malformedStream(let payload):
            "Local chat stream returned malformed data: \(payload)"
        }
    }
}

protocol LocalAIChatStreaming: Sendable {
    func streamChat(
        endpoint: LocalAIOpenAIEndpoint,
        request: LocalAIChatCompletionsRequest
    ) -> AsyncThrowingStream<LocalAIChatStreamEvent, Error>
}

struct LocalAIChatClient: LocalAIChatStreaming {
    func streamChat(
        endpoint: LocalAIOpenAIEndpoint,
        request: LocalAIChatCompletionsRequest
    ) -> AsyncThrowingStream<LocalAIChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await stream(endpoint: endpoint, request: request, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func stream(
        endpoint: LocalAIOpenAIEndpoint,
        request: LocalAIChatCompletionsRequest,
        continuation: AsyncThrowingStream<LocalAIChatStreamEvent, Error>.Continuation
    ) async throws {
        let url = Self.chatCompletionsURL(for: endpoint)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw LocalAIChatClientError.httpStatus(-1, "")
        }
        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines {
                body += line
            }
            if let data = body.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(LocalAIAPIErrorResponse.self, from: data) {
                throw LocalAIChatClientError.httpStatus(http.statusCode, decoded.error.message)
            }
            throw LocalAIChatClientError.httpStatus(http.statusCode, body)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let events = try Self.events(fromSSELine: line) else {
                return
            }
            for event in events {
                continuation.yield(event)
            }
        }
    }

    static func chatCompletionsURL(for endpoint: LocalAIOpenAIEndpoint) -> URL {
        endpoint.baseURL
            .appendingPathComponent("chat", isDirectory: true)
            .appendingPathComponent("completions", isDirectory: false)
    }

    static func events(fromSSELine line: String) throws -> [LocalAIChatStreamEvent]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return [] }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return nil
        }
        guard let data = payload.data(using: .utf8) else {
            throw LocalAIChatClientError.malformedStream(String(payload))
        }
        if let apiError = try? JSONDecoder().decode(LocalAIAPIErrorResponse.self, from: data) {
            throw LocalAIChatClientError.api(apiError.error.message)
        }
        guard let chunk = try? JSONDecoder().decode(LocalAIChatCompletionsStreamResponse.self, from: data) else {
            throw LocalAIChatClientError.malformedStream(String(payload))
        }
        return chunk.choices.flatMap { choice -> [LocalAIChatStreamEvent] in
            var events: [LocalAIChatStreamEvent] = []
            if let content = choice.delta.content, !content.isEmpty {
                events.append(.delta(content))
            }
            if let finishReason = choice.finishReason {
                events.append(.completed(finishReason: finishReason))
            }
            return events
        }
    }
}
