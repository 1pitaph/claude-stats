import Foundation

enum ChatRole: String, Codable, Sendable, Hashable {
    case system
    case user
    case assistant

    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .user: String(localized: "You")
        case .assistant: String(localized: "Local LLM")
        }
    }
}

struct ChatMessage: Identifiable, Codable, Sendable, Hashable {
    var id: UUID
    var role: ChatRole
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), role: ChatRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct ChatGenerationSettings: Codable, Sendable, Hashable {
    var temperature: Double
    var maxTokens: Int

    static let `default` = ChatGenerationSettings(temperature: 0.4, maxTokens: 768)
}

struct ChatContextCommit: Identifiable, Codable, Sendable, Hashable {
    var hash: String
    var subject: String
    var author: String
    var date: Date

    var id: String { hash }
    var shortHash: String { String(hash.prefix(7)) }
}

struct ChatContextSnapshot: Codable, Sendable, Hashable {
    var capturedAt: Date
    var repoName: String
    var repoRootPath: String
    var branchName: String?
    var isDirty: Bool
    var dirtyFileCount: Int
    var stagedFileCount: Int
    var unstagedFileCount: Int
    var changedPaths: [String]
    var recentCommits: [ChatContextCommit]

    var branchLabel: String {
        branchName?.isEmpty == false ? branchName! : String(localized: "detached")
    }

    var dirtyLabel: String {
        isDirty ? "\(dirtyFileCount) changed" : "clean"
    }
}

struct ChatProjectOption: Identifiable, Codable, Sendable, Hashable {
    var rootPath: String
    var displayName: String
    var branchName: String?

    var id: String { rootPath }

    var branchLabel: String {
        branchName?.isEmpty == false ? branchName! : String(localized: "detached")
    }
}

struct ChatConversation: Identifiable, Codable, Sendable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var selectedModelID: String
    var settings: ChatGenerationSettings
    var contextSnapshot: ChatContextSnapshot?
    var messages: [ChatMessage]

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        selectedModelID: String,
        settings: ChatGenerationSettings = .default,
        contextSnapshot: ChatContextSnapshot? = nil,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.selectedModelID = selectedModelID
        self.settings = settings
        self.contextSnapshot = contextSnapshot
        self.messages = messages
    }
}

struct ChatLibrarySnapshot: Codable, Sendable, Hashable {
    var conversations: [ChatConversation]
    var selectedConversationID: UUID?

    static let empty = ChatLibrarySnapshot(conversations: [], selectedConversationID: nil)
}
