import Foundation

struct LocalAIChatMessage: Codable, Sendable, Hashable {
    var role: String
    var content: String
}

struct LocalAIChatCompletionsRequest: Codable, Sendable {
    var model: String?
    var messages: [LocalAIChatMessage]
    var temperature: Double?
    var maxTokens: Int?
    var stream: Bool?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

enum LocalAIChatStreamEvent: Sendable, Equatable {
    case delta(String)
    case completed(finishReason: String?)
}

struct LocalAIChatCompletionsResponse: Encodable, Sendable {
    var id: String
    var object: String = "chat.completion"
    var created: Int
    var model: String
    var choices: [Choice]
    var usage: Usage

    struct Choice: Encodable, Sendable {
        var index: Int
        var message: LocalAIChatMessage
        var finishReason: String

        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Encodable, Sendable {
        var promptTokens: Int
        var completionTokens: Int
        var totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

struct LocalAIChatCompletionsStreamResponse: Codable, Sendable {
    var id: String
    var object: String = "chat.completion.chunk"
    var created: Int
    var model: String
    var choices: [Choice]

    struct Choice: Codable, Sendable {
        var index: Int
        var delta: Delta
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Codable, Sendable {
        var role: String?
        var content: String?
    }
}

struct LocalAIEmbeddingsRequest: Decodable, Sendable {
    var model: String?
    var input: [String]

    enum CodingKeys: String, CodingKey {
        case model
        case input
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        if let single = try? container.decode(String.self, forKey: .input) {
            input = [single]
        } else {
            input = try container.decode([String].self, forKey: .input)
        }
    }
}

struct LocalAIEmbeddingsResponse: Encodable, Sendable {
    var object: String = "list"
    var data: [Embedding]
    var model: String
    var usage: Usage

    struct Embedding: Encodable, Sendable {
        var object: String = "embedding"
        var embedding: [Float]
        var index: Int
    }

    struct Usage: Encodable, Sendable {
        var promptTokens: Int
        var totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

struct LocalAIModelsResponse: Encodable, Sendable {
    var object: String = "list"
    var data: [Model]

    struct Model: Encodable, Sendable {
        var id: String
        var object: String = "model"
        var created: Int
        var ownedBy: String = "claude-stats-local"

        enum CodingKeys: String, CodingKey {
            case id
            case object
            case created
            case ownedBy = "owned_by"
        }
    }
}

struct LocalAIAPIErrorResponse: Codable, Sendable {
    var error: ErrorBody

    struct ErrorBody: Codable, Sendable {
        var message: String
        var type: String
        var code: String?
    }
}
