import Foundation
import Testing
@testable import ClaudeStats

@Suite("App LLM client")
struct LLMClientTests {
    @Test("OpenAI chat request body and usage parse")
    func openAIChatRequestAndUsage() async throws {
        let capture = LLMRequestCapture()
        let client = AppLLMClient { request in
            await capture.record(request)
            let body = """
            {"model":"gpt-test","choices":[{"message":{"content":"hello"}}],"usage":{"prompt_tokens":11,"completion_tokens":7,"total_tokens":18}}
            """
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let endpoint = endpoint(protocol: .openAIChatCompletions)

        let result = try await client.generate(
            endpoint: endpoint,
            request: LLMGenerationRequest(systemPrompt: "sys", userPrompt: "user", maxTokens: 99, temperature: 0.1)
        )
        let request = try #require(await capture.last())

        #expect(request.url == "https://api.example.com/v1/chat/completions")
        #expect(request.authorization == "Bearer test-key")
        #expect(request.body.contains(#""max_tokens":99"#))
        #expect(request.body.contains(#""role":"system""#))
        #expect(result.text == "hello")
        #expect(result.inputTokens == 11)
        #expect(result.outputTokens == 7)
        #expect(result.totalTokens == 18)
    }

    @Test("Responses and Anthropic request formats parse text and usage")
    func responsesAndAnthropicFormats() async throws {
        let responsesCapture = LLMRequestCapture()
        let responsesClient = AppLLMClient { request in
            await responsesCapture.record(request)
            let body = """
            {"model":"gpt-response","output_text":"response text","usage":{"input_tokens":13,"output_tokens":5,"total_tokens":18}}
            """
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let responses = try await responsesClient.generate(
            endpoint: endpoint(protocol: .openAIResponses),
            request: LLMGenerationRequest(systemPrompt: "sys", userPrompt: "user", maxTokens: 42)
        )
        let responsesRequest = try #require(await responsesCapture.last())

        let anthropicCapture = LLMRequestCapture()
        let anthropicClient = AppLLMClient { request in
            await anthropicCapture.record(request)
            let body = """
            {"model":"claude-test","content":[{"type":"text","text":"anthropic text"}],"usage":{"input_tokens":17,"output_tokens":6}}
            """
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let anthropic = try await anthropicClient.generate(
            endpoint: endpoint(protocol: .anthropicMessages, baseURL: "https://api.anthropic.com"),
            request: LLMGenerationRequest(systemPrompt: "sys", userPrompt: "user", maxTokens: 42)
        )
        let anthropicRequest = try #require(await anthropicCapture.last())

        #expect(responsesRequest.url == "https://api.example.com/v1/responses")
        #expect(responsesRequest.body.contains(#""max_output_tokens":42"#))
        #expect(responses.text == "response text")
        #expect(responses.totalTokens == 18)
        #expect(anthropicRequest.url == "https://api.anthropic.com/v1/messages")
        #expect(anthropicRequest.apiKey == "test-key")
        #expect(anthropicRequest.anthropicVersion == "2023-06-01")
        #expect(anthropic.text == "anthropic text")
        #expect(anthropic.totalTokens == 23)
    }

    private func endpoint(protocol protocolName: AppLLMProtocol, baseURL: String = "https://api.example.com/v1") -> AppLLMGenerationEndpoint {
        AppLLMGenerationEndpoint(
            mode: .online,
            protocol: protocolName,
            baseURL: URL(string: baseURL)!,
            apiKey: "test-key",
            model: "test-model",
            displayName: "Test"
        )
    }
}

private struct CapturedLLMRequest: Sendable {
    var url: String
    var authorization: String?
    var apiKey: String?
    var anthropicVersion: String?
    var body: String
}

private actor LLMRequestCapture {
    private var value: CapturedLLMRequest?

    func record(_ request: URLRequest) {
        value = CapturedLLMRequest(
            url: request.url?.absoluteString ?? "",
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            apiKey: request.value(forHTTPHeaderField: "x-api-key"),
            anthropicVersion: request.value(forHTTPHeaderField: "anthropic-version"),
            body: request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        )
    }

    func last() -> CapturedLLMRequest? {
        value
    }
}
