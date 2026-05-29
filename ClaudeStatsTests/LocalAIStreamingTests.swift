import Foundation
import Testing
@testable import ClaudeStats

@Suite("Local AI streaming")
struct LocalAIStreamingTests {
    @Test("Chat completions URL preserves the OpenAI v1 base path")
    func chatCompletionsURLUsesV1BasePath() throws {
        let endpoint = LocalAIOpenAIEndpoint(
            baseURL: try #require(URL(string: "http://127.0.0.1:18765/v1")),
            token: "token"
        )

        #expect(LocalAIChatClient.chatCompletionsURL(for: endpoint).absoluteString == "http://127.0.0.1:18765/v1/chat/completions")
    }

    @Test("SSE lines parse delta, completion, done, and API errors")
    func sseLineParsing() throws {
        let delta = LocalAIChatCompletionsStreamResponse(
            id: "chatcmpl",
            created: 1,
            model: "model",
            choices: [
                LocalAIChatCompletionsStreamResponse.Choice(
                    index: 0,
                    delta: LocalAIChatCompletionsStreamResponse.Delta(role: nil, content: "hel"),
                    finishReason: nil
                ),
            ]
        )
        let deltaPayload = try #require(String(data: JSONEncoder().encode(delta), encoding: .utf8))
        #expect(try LocalAIChatClient.events(fromSSELine: "data: \(deltaPayload)") == [.delta("hel")])

        let completed = LocalAIChatCompletionsStreamResponse(
            id: "chatcmpl",
            created: 1,
            model: "model",
            choices: [
                LocalAIChatCompletionsStreamResponse.Choice(
                    index: 0,
                    delta: LocalAIChatCompletionsStreamResponse.Delta(role: nil, content: nil),
                    finishReason: "stop"
                ),
            ]
        )
        let completedPayload = try #require(String(data: JSONEncoder().encode(completed), encoding: .utf8))
        #expect(try LocalAIChatClient.events(fromSSELine: "data: \(completedPayload)") == [.completed(finishReason: "stop")])
        #expect(try LocalAIChatClient.events(fromSSELine: "data: [DONE]") == nil)

        let error = LocalAIAPIErrorResponse(
            error: LocalAIAPIErrorResponse.ErrorBody(message: "boom", type: "local_ai_error", code: nil)
        )
        let errorPayload = try #require(String(data: JSONEncoder().encode(error), encoding: .utf8))
        #expect(throws: LocalAIChatClientError.self) {
            _ = try LocalAIChatClient.events(fromSSELine: "data: \(errorPayload)")
        }
    }
}

@MainActor
@Suite("Local AI streaming service")
struct LocalAIStreamingServiceTests {
    @Test("Streaming requests reach model validation instead of unsupported-streaming")
    func streamRequestIsAcceptedByServiceLayer() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "LocalAIStreamingServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let modelStore = LocalAIModelStore(
            defaults: defaults,
            stateURL: root.appendingPathComponent("models-state.json")
        )
        let service = LocalAIOpenAIService(modelStore: modelStore)
        let request = LocalAIChatCompletionsRequest(
            model: modelStore.selectedLLMModel.id,
            messages: [LocalAIChatMessage(role: "user", content: "hello")],
            temperature: 0.2,
            maxTokens: 8,
            stream: true
        )

        do {
            _ = try await service.chatStream(request)
            Issue.record("Expected missing model error for an uninstalled LLM.")
        } catch LocalAIOpenAIServiceError.unsupportedStreaming {
            Issue.record("Streaming should no longer fail as unsupported.")
        } catch LocalAIOpenAIServiceError.modelNotInstalled(_) {
            // Expected: the request reached model installation validation.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
