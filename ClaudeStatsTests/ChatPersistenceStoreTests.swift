import Foundation
import Testing
@testable import ClaudeStats

@Suite("Chat persistence store")
struct ChatPersistenceStoreTests {
    @Test("Conversations round-trip through the v1 library")
    func conversationRoundTrip() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("conversations.json")
        let store = ChatPersistenceStore(fileURL: url)
        let conversation = ChatConversation(
            title: "Streaming test",
            selectedModelID: "qwen",
            messages: [
                ChatMessage(role: .user, content: "hello"),
                ChatMessage(role: .assistant, content: "hi"),
            ]
        )
        let snapshot = ChatLibrarySnapshot(conversations: [conversation], selectedConversationID: conversation.id)

        await store.save(snapshot)
        let loaded = await store.load()

        #expect(loaded == snapshot)
    }

    @Test("Missing and incompatible libraries recover as empty")
    func missingAndIncompatibleLibrariesRecoverAsEmpty() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let missingURL = root.appendingPathComponent("missing.json")
        let missingStore = ChatPersistenceStore(fileURL: missingURL)

        #expect(await missingStore.load() == .empty)

        let incompatibleURL = root.appendingPathComponent("bad-schema.json")
        try #"{"schemaVersion":999,"snapshot":{"conversations":[],"selectedConversationID":null}}"#
            .write(to: incompatibleURL, atomically: true, encoding: .utf8)
        let incompatibleStore = ChatPersistenceStore(fileURL: incompatibleURL)

        #expect(await incompatibleStore.load() == .empty)
    }
}
