import Foundation

struct DailyReportGitSummaryLLMResponse: Decodable, Sendable {
    var summary: String?
    var keyChanges: [String]?
    var risksOrNotes: [String]?

    private enum CodingKeys: String, CodingKey {
        case summary
        case keyChanges = "key_changes"
        case risksOrNotes = "risks_or_notes"
    }
}

struct DailyReportGitSummaryParseResult: Sendable {
    var summary: String
    var keyChanges: [String]
    var risksOrNotes: [String]
    var jsonParseOK: Bool
}

enum DailyReportGitSummaryResponseParser {
    static func parse(_ raw: String) -> DailyReportGitSummaryParseResult {
        let fallback = normalizedFallback(raw)
        guard let json = extractJSONObject(from: raw),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DailyReportGitSummaryLLMResponse.self, from: data)
        else {
            return DailyReportGitSummaryParseResult(
                summary: fallback.isEmpty ? raw : fallback,
                keyChanges: [],
                risksOrNotes: [],
                jsonParseOK: false
            )
        }

        return DailyReportGitSummaryParseResult(
            summary: trimmed(decoded.summary ?? "").dailyReportGitSummaryParserNilIfEmpty ?? fallback,
            keyChanges: (decoded.keyChanges ?? []).map(trimmed).filter { !$0.isEmpty },
            risksOrNotes: (decoded.risksOrNotes ?? []).map(trimmed).filter { !$0.isEmpty },
            jsonParseOK: true
        )
    }

    static func extractJSONObject(from raw: String) -> String? {
        let trimmed = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start < end
        else {
            return nil
        }
        return String(trimmed[start...end])
    }

    private static func normalizedFallback(_ raw: String) -> String {
        stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripCodeFence(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: "\n")
        if !lines.isEmpty { lines.removeFirst() }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var dailyReportGitSummaryParserNilIfEmpty: String? { isEmpty ? nil : self }
}
