import Foundation
import Testing
@testable import ClaudeStats

@MainActor
@Suite("ChatStore")
struct ChatStoreTests {
    @Test("Streaming deltas accumulate into the assistant message")
    func streamingDeltasAccumulate() async throws {
        let persistence = FakeChatPersistence()
        let store = ChatStore(
            persistence: persistence,
            chatClient: FakeChatClient(events: [.delta("Hel"), .delta("lo"), .completed(finishReason: "stop")])
        )
        let endpoint = FakeChatEndpointProvider()

        await store.loadIfNeeded(defaultModelID: "test-model")
        store.draft = "Say hello"
        store.send(endpointProvider: endpoint, sessions: [], sourceIDs: [])
        try await waitUntilIdle(store)

        let messages = try #require(store.selectedConversation?.messages)
        #expect(messages.map(\.role) == [.user, .assistant])
        #expect(messages.last?.content == "Hello")
        #expect(!store.isGenerating)
        #expect(store.lastError == nil)
    }

    @Test("Stop preserves partial assistant output")
    func stopPreservesPartialOutput() async throws {
        let store = ChatStore(
            persistence: FakeChatPersistence(),
            chatClient: FakeChatClient(events: [.delta("partial"), .delta(" later")], delayNanoseconds: 50_000_000)
        )
        let endpoint = FakeChatEndpointProvider()

        await store.loadIfNeeded(defaultModelID: "test-model")
        store.draft = "Start"
        store.send(endpointProvider: endpoint, sessions: [], sourceIDs: [])
        try await Task.sleep(nanoseconds: 10_000_000)
        store.stopGenerating()
        try await waitUntilIdle(store)

        let messages = try #require(store.selectedConversation?.messages)
        #expect(messages.last?.role == .assistant)
        #expect(messages.last?.content == "partial")
    }

    private func waitUntilIdle(_ store: ChatStore) async throws {
        for _ in 0..<80 {
            if !store.isGenerating { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("ChatStore did not become idle.")
    }
}

private actor FakeChatPersistence: ChatPersisting {
    var snapshot: ChatLibrarySnapshot = .empty

    func load() async -> ChatLibrarySnapshot {
        snapshot
    }

    func save(_ snapshot: ChatLibrarySnapshot) async {
        self.snapshot = snapshot
    }
}

private struct FakeChatClient: LocalAIChatStreaming {
    let events: [LocalAIChatStreamEvent]
    var delayNanoseconds: UInt64 = 0

    func streamChat(
        endpoint: LocalAIOpenAIEndpoint,
        request: LocalAIChatCompletionsRequest
    ) -> AsyncThrowingStream<LocalAIChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for event in events {
                    guard !Task.isCancelled else {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    continuation.yield(event)
                    if delayNanoseconds > 0 {
                        do {
                            try await Task.sleep(nanoseconds: delayNanoseconds)
                        } catch {
                            continuation.finish(throwing: CancellationError())
                            return
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

@MainActor
private final class FakeChatEndpointProvider: LocalAIChatEndpointProviding {
    var selectedChatModelID = "test-model"
    var localLLMAvailable = true
    var localAPIStatusText = "ready"

    func ensureChatEndpoint() -> LocalAIOpenAIEndpoint? {
        LocalAIOpenAIEndpoint(baseURL: URL(string: "http://127.0.0.1:1/v1")!, token: "token")
    }
}
