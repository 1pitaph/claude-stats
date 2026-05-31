import Foundation

struct LLMGenerationRequest: Sendable, Hashable {
    var systemPrompt: String
    var userPrompt: String
    var maxTokens: Int
    var temperature: Double

    init(systemPrompt: String, userPrompt: String, maxTokens: Int = 1_200, temperature: Double = 0.2) {
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

struct LLMGenerationResult: Sendable, Hashable {
    var text: String
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
}

protocol LLMGenerating: Sendable {
    func generate(endpoint: AppLLMGenerationEndpoint, request: LLMGenerationRequest) async throws -> LLMGenerationResult
}

enum LLMClientError: Error, LocalizedError, Sendable {
    case invalidResponse
    case httpStatus(Int, String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "LLM service returned an invalid response."
        case .httpStatus(let status, let body):
            let message = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "LLM service returned HTTP \(status)." : "LLM service returned HTTP \(status): \(message)"
        case .emptyOutput:
            return "LLM service returned an empty response."
        }
    }
}

struct AppLLMClient: LLMGenerating {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let transport: Transport

    init(transport: @escaping Transport = { request in
        try await URLSession.shared.data(for: request)
    }) {
        self.transport = transport
    }

    func generate(endpoint: AppLLMGenerationEndpoint, request: LLMGenerationRequest) async throws -> LLMGenerationResult {
        switch endpoint.protocol {
        case .openAIChatCompletions:
            return try await openAIChat(endpoint: endpoint, generationRequest: request)
        case .openAIResponses:
            return try await openAIResponses(endpoint: endpoint, generationRequest: request)
        case .anthropicMessages:
            return try await anthropicMessages(endpoint: endpoint, generationRequest: request)
        }
    }

    private func openAIChat(endpoint: AppLLMGenerationEndpoint, generationRequest: LLMGenerationRequest) async throws -> LLMGenerationResult {
        struct Message: Encodable {
            var role: String
            var content: String
        }
        struct Body: Encodable {
            var model: String
            var messages: [Message]
            var temperature: Double
            var max_tokens: Int
        }
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { var content: String? }
                var message: Message
            }
            struct Usage: Decodable {
                var prompt_tokens: Int?
                var completion_tokens: Int?
                var total_tokens: Int?
            }
            var model: String?
            var choices: [Choice]
            var usage: Usage?
        }

        var urlRequest = try jsonRequest(
            url: endpoint.baseURL.appendingLLMPath(["chat", "completions"]),
            apiKey: endpoint.apiKey,
            headerName: "Authorization",
            headerValuePrefix: "Bearer ",
            body: Body(
                model: endpoint.model,
                messages: [
                    Message(role: "system", content: generationRequest.systemPrompt),
                    Message(role: "user", content: generationRequest.userPrompt),
                ],
                temperature: generationRequest.temperature,
                max_tokens: generationRequest.maxTokens
            )
        )
        urlRequest.timeoutInterval = 120
        let data = try await perform(urlRequest)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw LLMClientError.emptyOutput }
        return result(
            text: text,
            model: decoded.model ?? endpoint.model,
            inputTokens: decoded.usage?.prompt_tokens,
            outputTokens: decoded.usage?.completion_tokens,
            totalTokens: decoded.usage?.total_tokens,
            request: generationRequest
        )
    }

    private func openAIResponses(endpoint: AppLLMGenerationEndpoint, generationRequest: LLMGenerationRequest) async throws -> LLMGenerationResult {
        struct Input: Encodable {
            var role: String
            var content: String
        }
        struct Body: Encodable {
            var model: String
            var input: [Input]
            var temperature: Double
            var max_output_tokens: Int
        }
        struct Response: Decodable {
            struct Output: Decodable {
                struct Content: Decodable {
                    var type: String?
                    var text: String?
                }
                var content: [Content]?
            }
            struct Usage: Decodable {
                var input_tokens: Int?
                var output_tokens: Int?
                var total_tokens: Int?
            }
            var model: String?
            var output_text: String?
            var output: [Output]?
            var usage: Usage?
        }

        var urlRequest = try jsonRequest(
            url: endpoint.baseURL.appendingLLMPath(["responses"]),
            apiKey: endpoint.apiKey,
            headerName: "Authorization",
            headerValuePrefix: "Bearer ",
            body: Body(
                model: endpoint.model,
                input: [
                    Input(role: "system", content: generationRequest.systemPrompt),
                    Input(role: "user", content: generationRequest.userPrompt),
                ],
                temperature: generationRequest.temperature,
                max_output_tokens: generationRequest.maxTokens
            )
        )
        urlRequest.timeoutInterval = 120
        let data = try await perform(urlRequest)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let contentText = decoded.output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
        let text = (decoded.output_text ?? contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LLMClientError.emptyOutput }
        return result(
            text: text,
            model: decoded.model ?? endpoint.model,
            inputTokens: decoded.usage?.input_tokens,
            outputTokens: decoded.usage?.output_tokens,
            totalTokens: decoded.usage?.total_tokens,
            request: generationRequest
        )
    }

    private func anthropicMessages(endpoint: AppLLMGenerationEndpoint, generationRequest: LLMGenerationRequest) async throws -> LLMGenerationResult {
        struct Message: Encodable {
            var role: String
            var content: String
        }
        struct Body: Encodable {
            var model: String
            var system: String
            var messages: [Message]
            var max_tokens: Int
            var temperature: Double
        }
        struct Response: Decodable {
            struct Content: Decodable {
                var type: String?
                var text: String?
            }
            struct Usage: Decodable {
                var input_tokens: Int?
                var output_tokens: Int?
            }
            var model: String?
            var content: [Content]
            var usage: Usage?
        }

        var urlRequest = try jsonRequest(
            url: endpoint.baseURL.appendingAnthropicMessagesPath(),
            apiKey: endpoint.apiKey,
            headerName: "x-api-key",
            headerValuePrefix: "",
            body: Body(
                model: endpoint.model,
                system: generationRequest.systemPrompt,
                messages: [Message(role: "user", content: generationRequest.userPrompt)],
                max_tokens: generationRequest.maxTokens,
                temperature: generationRequest.temperature
            )
        )
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.timeoutInterval = 120
        let data = try await perform(urlRequest)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let text = decoded.content.compactMap(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LLMClientError.emptyOutput }
        return result(
            text: text,
            model: decoded.model ?? endpoint.model,
            inputTokens: decoded.usage?.input_tokens,
            outputTokens: decoded.usage?.output_tokens,
            totalTokens: nil,
            request: generationRequest
        )
    }

    private func jsonRequest<Body: Encodable>(
        url: URL,
        apiKey: String,
        headerName: String,
        headerValuePrefix: String,
        body: Body
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("\(headerValuePrefix)\(apiKey)", forHTTPHeaderField: headerName)
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMClientError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func result(
        text: String,
        model: String,
        inputTokens: Int?,
        outputTokens: Int?,
        totalTokens: Int?,
        request: LLMGenerationRequest
    ) -> LLMGenerationResult {
        let estimatedInput = inputTokens ?? estimateTokens(request.systemPrompt + "\n" + request.userPrompt)
        let estimatedOutput = outputTokens ?? estimateTokens(text)
        return LLMGenerationResult(
            text: text,
            model: model,
            inputTokens: estimatedInput,
            outputTokens: estimatedOutput,
            totalTokens: totalTokens ?? (estimatedInput + estimatedOutput)
        )
    }

    private func estimateTokens(_ text: String) -> Int {
        max(1, Int((Double(text.count) / 4.0).rounded(.up)))
    }
}

private extension URL {
    func appendingLLMPath(_ components: [String]) -> URL {
        var url = self
        for component in components {
            if url.pathComponents.last != component {
                url.appendPathComponent(component)
            }
        }
        return url
    }

    func appendingAnthropicMessagesPath() -> URL {
        if pathComponents.last == "messages" {
            return self
        }
        if pathComponents.last == "v1" {
            return appendingPathComponent("messages")
        }
        return appendingPathComponent("v1").appendingPathComponent("messages")
    }
}
