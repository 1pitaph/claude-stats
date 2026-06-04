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
        #expect(!anthropicRequest.body.contains(#""thinking""#))
        #expect(anthropic.text == "anthropic text")
        #expect(anthropic.totalTokens == 23)
    }

    @Test("Responses protocol accepts chat-shaped compatible responses")
    func responsesProtocolAcceptsChatShapedCompatibleResponses() async throws {
        let capture = LLMRequestCapture()
        let client = AppLLMClient { request in
            await capture.record(request)
            let body = """
            {"model":"compat-model","choices":[{"message":{"content":"compat text"}}],"usage":{"prompt_tokens":19,"completion_tokens":4,"total_tokens":23}}
            """
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let result = try await client.generate(
            endpoint: endpoint(protocol: .openAIResponses),
            request: LLMGenerationRequest(systemPrompt: "sys", userPrompt: "user", maxTokens: 42)
        )
        let request = try #require(await capture.last())

        #expect(request.url == "https://api.example.com/v1/responses")
        #expect(result.text == "compat text")
        #expect(result.model == "compat-model")
        #expect(result.inputTokens == 19)
        #expect(result.outputTokens == 4)
        #expect(result.totalTokens == 23)
    }

    @Test("DeepSeek Anthropic JSON requests disable thinking")
    func deepSeekAnthropicJSONRequestsDisableThinking() async throws {
        let capture = LLMRequestCapture()
        let client = AppLLMClient { request in
            await capture.record(request)
            let body = """
            {"model":"deepseek-v4-flash","content":[{"type":"text","text":"{\\"summary\\":\\"ok\\"}"}],"usage":{"input_tokens":21,"output_tokens":5}}
            """
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        _ = try await client.generate(
            endpoint: endpoint(protocol: .anthropicMessages, baseURL: "https://api.deepseek.com/anthropic", model: "deepseek-v4-flash"),
            request: LLMGenerationRequest(systemPrompt: "sys", userPrompt: "user", maxTokens: 42, outputShape: .jsonObject)
        )
        let request = try #require(await capture.last())

        #expect(request.url == "https://api.deepseek.com/anthropic/v1/messages")
        #expect(request.body.contains(#""thinking":{"type":"disabled"}"#))
    }

    @Test("DeepSeek Anthropic text requests disable thinking")
    func deepSeekAnthropicTextRequestsDisableThinking() async throws {
        let capture = LLMRequestCapture()
        let client = AppLLMClient { request in
            await capture.record(request)
            let body = """
            {"model":"deepseek-v4-flash","content":[{"type":"text","text":"No material issues found."}],"usage":{"input_tokens":21,"output_tokens":5}}
            """
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        _ = try await client.generate(
            endpoint: endpoint(protocol: .anthropicMessages, baseURL: "https://api.deepseek.com/anthropic", model: "deepseek-v4-flash"),
            request: LLMGenerationRequest(systemPrompt: "sys", userPrompt: "user", maxTokens: 42, outputShape: .text)
        )
        let request = try #require(await capture.last())

        #expect(request.body.contains(#""thinking":{"type":"disabled"}"#))
    }

    @Test("JSON object requests retry once after empty content")
    func jsonObjectRequestsRetryOnceAfterEmptyContent() async throws {
        let capture = LLMRequestCapture()
        let client = AppLLMClient { request in
            await capture.record(request)
            let count = await capture.count()
            let body = if count == 1 {
                #"{"model":"deepseek-v4-flash","content":[],"usage":{"input_tokens":21,"output_tokens":0}}"#
            } else {
                #"{"model":"deepseek-v4-flash","content":[{"type":"text","text":"{\"summary\":\"ok\"}"}],"usage":{"input_tokens":22,"output_tokens":5}}"#
            }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let result = try await client.generate(
            endpoint: endpoint(protocol: .anthropicMessages, baseURL: "https://api.deepseek.com/anthropic", model: "deepseek-v4-flash"),
            request: LLMGenerationRequest(systemPrompt: "sys", userPrompt: "user", maxTokens: 42, outputShape: .jsonObject)
        )
        let requests = await capture.all()

        #expect(result.text == #"{"summary":"ok"}"#)
        #expect(requests.count == 2)
        #expect(requests[1].body.contains("previous response was empty"))
        #expect(requests[1].body.contains("compact JSON object"))
    }

    @Test("Text requests retry once after empty content")
    func textRequestsRetryOnceAfterEmptyContent() async throws {
        let capture = LLMRequestCapture()
        let client = AppLLMClient { request in
            await capture.record(request)
            let count = await capture.count()
            let body = if count == 1 {
                #"{"model":"deepseek-v4-flash","content":[],"usage":{"input_tokens":21,"output_tokens":0}}"#
            } else {
                #"{"model":"deepseek-v4-flash","content":[{"type":"text","text":"No material issues found."}],"usage":{"input_tokens":22,"output_tokens":5}}"#
            }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let result = try await client.generate(
            endpoint: endpoint(protocol: .anthropicMessages, baseURL: "https://api.deepseek.com/anthropic", model: "deepseek-v4-flash"),
            request: LLMGenerationRequest(systemPrompt: "sys", userPrompt: "user", maxTokens: 42, outputShape: .text)
        )
        let requests = await capture.all()

        #expect(result.text == "No material issues found.")
        #expect(requests.count == 2)
        #expect(requests[1].body.contains("previous response was empty"))
        #expect(requests[1].body.contains("Return concise plain text now"))
    }

    private func endpoint(
        protocol protocolName: AppLLMProtocol,
        baseURL: String = "https://api.example.com/v1",
        model: String = "test-model"
    ) -> AppLLMGenerationEndpoint {
        AppLLMGenerationEndpoint(
            mode: .online,
            protocol: protocolName,
            baseURL: URL(string: baseURL)!,
            apiKey: "test-key",
            model: model,
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
    private var values: [CapturedLLMRequest] = []

    func record(_ request: URLRequest) {
        values.append(CapturedLLMRequest(
            url: request.url?.absoluteString ?? "",
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            apiKey: request.value(forHTTPHeaderField: "x-api-key"),
            anthropicVersion: request.value(forHTTPHeaderField: "anthropic-version"),
            body: request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        ))
    }

    func last() -> CapturedLLMRequest? {
        values.last
    }

    func all() -> [CapturedLLMRequest] {
        values
    }

    func count() -> Int {
        values.count
    }
}
