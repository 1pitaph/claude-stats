import Foundation

/// Provider conformer for the ZCode CLI.
///
/// ZCode publishes its own structured usage data into a SQLite database, so
/// almost everything we need (per-turn token counts, cache splits, durations,
/// cost-relevant model ids) is read directly out of that database. JSONL
/// rollouts are still on disk and used as a fallback by ``ZCodeRolloutParser``.
struct ZCodeProvider: Provider {
    let paths: ZCodePaths
    let pricing: ModelPricing

    var kind: ProviderKind { .zcode }

    var dataDirectoryExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: paths.homeDirectory.path, isDirectory: &isDir) && isDir.boolValue
    }

    var dataDirectoryPath: String? { paths.homeDirectory.path }

    func discoverSessions() async -> [Session] {
        ZCodeSessionScanner(paths: paths).scan()
    }

    func parse(_ session: Session) async -> SessionStats? {
        ZCodeTranscriptParser(paths: paths, pricing: pricing).parse(session)
    }

    func transcriptMessages(for session: Session) async -> [SessionTranscriptMessage] {
        ZCodeTranscriptParser(paths: paths, pricing: pricing).messages(for: session)
    }

    func executedCommands(for session: Session) async -> [SessionCommandEvent] {
        ZCodeTranscriptParser(paths: paths, pricing: pricing).executedCommands(for: session)
    }

    func displayName(forModel id: String) -> String {
        Self.modelDisplayName(forModelID: id)
    }

    /// Pretty model name. ZCode talks to many providers, so we normalise a
    /// handful of well-known families and otherwise return the raw id.
    static func modelDisplayName(forModelID id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return id }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("glm-") {
            return "GLM \(trimmed.dropFirst("glm-".count))"
        }
        if lower.hasPrefix("doubao-") {
            return "Doubao \(trimmed.dropFirst("doubao-".count))"
        }
        if lower.hasPrefix("deepseek-") {
            return "DeepSeek \(trimmed.dropFirst("deepseek-".count))"
        }
        return trimmed
    }
}
