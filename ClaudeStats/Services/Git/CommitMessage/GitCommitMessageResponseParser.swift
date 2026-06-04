import Foundation

struct GitCommitMessageObservation: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var path: String
    var summary: String
    var keyChanges: [String]
    var risks: [String]
    var publicInterfaces: [String]
    var questions: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case summary
        case keyChanges = "key_changes"
        case risks
        case publicInterfaces = "public_interfaces"
        case questions
    }
}

struct GitCommitMessageFinalLLMResponse: Decodable, Sendable {
    var commitTitle: String
    var commitBody: String

    private enum CodingKeys: String, CodingKey {
        case commitTitle = "commit_title"
        case commitBody = "commit_body"
    }
}

struct GitCommitMessageObservationParseResult: Sendable {
    var observation: GitCommitMessageObservation
    var jsonParseOK: Bool
}

struct GitCommitMessageFinalParseResult: Sendable {
    var response: GitCommitMessageFinalLLMResponse?
    var jsonParseOK: Bool
}

enum GitCommitMessageResponseParser {
    static func parseObservation(_ raw: String, fallbackPath: String, fallbackID: String) -> GitCommitMessageObservationParseResult {
        if let data = extractJSONObject(from: raw)?.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(GitCommitMessageObservation.self, from: data) {
            return GitCommitMessageObservationParseResult(observation: decoded, jsonParseOK: true)
        }
        return GitCommitMessageObservationParseResult(
            observation: GitCommitMessageObservation(
                id: fallbackID,
                path: fallbackPath,
                summary: raw.trimmingCharacters(in: .whitespacesAndNewlines),
                keyChanges: [],
                risks: [],
                publicInterfaces: [],
                questions: []
            ),
            jsonParseOK: false
        )
    }

    static func parseFinalCommitMessage(_ raw: String) -> GitCommitMessageFinalParseResult {
        guard let json = extractJSONObject(from: raw), let data = json.data(using: .utf8) else {
            return GitCommitMessageFinalParseResult(response: nil, jsonParseOK: false)
        }
        guard let decoded = try? JSONDecoder().decode(GitCommitMessageFinalLLMResponse.self, from: data) else {
            return GitCommitMessageFinalParseResult(response: nil, jsonParseOK: false)
        }
        return GitCommitMessageFinalParseResult(response: decoded, jsonParseOK: true)
    }

    static func extractJSONObject(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(trimmed[start...end])
    }
}
