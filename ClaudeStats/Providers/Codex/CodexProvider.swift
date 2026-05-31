import Foundation

/// Reads OpenAI Codex CLI sessions from `~/.codex/sessions/`.
struct CodexProvider: Provider {
    let paths: CodexPaths
    let pricing: ModelPricing

    var kind: ProviderKind { .codex }

    var dataDirectoryExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: paths.sessionsDirectory.path, isDirectory: &isDir) && isDir.boolValue
    }

    var dataDirectoryPath: String? { paths.sessionsDirectory.path }

    func discoverSessions() async -> [Session] {
        await CodexSessionScanner(paths: paths).scan()
    }

    func parse(_ session: Session) async -> SessionStats? {
        await CodexTranscriptParser(pricing: pricing)
            .parse(transcriptAt: URL(fileURLWithPath: session.filePath),
                   fallbackTitle: session.projectDisplayName)
    }

    func transcriptMessages(for session: Session) async -> [SessionTranscriptMessage] {
        await CodexTranscriptParser(pricing: pricing)
            .messages(transcriptAt: URL(fileURLWithPath: session.filePath))
    }

    func executedCommands(for session: Session) async -> [SessionCommandEvent] {
        await CodexTranscriptParser(pricing: pricing)
            .executedCommands(transcriptAt: URL(fileURLWithPath: session.filePath))
    }

    func cacheHitRate(for usage: TokenUsage) -> Double? {
        usage.cachedInputRate
    }

    func usageLimitReport(now: Date) async -> UsageLimitReport {
        CodexUsageLimitLoader(paths: paths).report(now: now)
    }

    func globalConfigurationLocations() -> [ProviderConfigLocation] {
        [
            ProviderConfigLocation(
                provider: kind,
                title: "config.toml",
                url: paths.homeDirectory.appendingPathComponent("config.toml", isDirectory: false),
                fileKind: .toml
            ),
            ProviderConfigLocation(
                provider: kind,
                title: "AGENTS.md",
                url: paths.homeDirectory.appendingPathComponent("AGENTS.md", isDirectory: false),
                fileKind: .markdown
            ),
        ]
    }

    func projectConfigurationLocations(for projectURL: URL) -> [ProviderConfigLocation] {
        [
            ProviderConfigLocation(
                provider: kind,
                title: "Project AGENTS.md",
                url: projectURL.appendingPathComponent("AGENTS.md", isDirectory: false),
                fileKind: .markdown
            ),
        ]
    }

    func globalAIConfigSources() -> [AIConfigSource] {
        [
            AIConfigSource(
                provider: kind,
                title: "config.toml",
                url: paths.homeDirectory.appendingPathComponent("config.toml", isDirectory: false),
                kind: .providerConfig,
                fileKind: .toml,
                location: .global,
                isExpected: true
            ),
            AIConfigSource(
                provider: kind,
                title: "AGENTS.md",
                url: paths.homeDirectory.appendingPathComponent("AGENTS.md", isDirectory: false),
                kind: .instruction,
                fileKind: .markdown,
                location: .global,
                isExpected: true
            ),
            AIConfigSource(
                provider: kind,
                title: "Plugins",
                url: paths.homeDirectory.appendingPathComponent("plugins", isDirectory: true),
                kind: .pluginConfig,
                fileKind: .json,
                location: .pluginStore,
                target: .directory(extensions: ["json"], maxDepth: 4)
            ),
        ]
    }

    func projectAIConfigSources(for projectURL: URL) -> [AIConfigSource] {
        [
            AIConfigSource(
                provider: kind,
                title: "Project AGENTS.md",
                url: projectURL.appendingPathComponent("AGENTS.md", isDirectory: false),
                kind: .instruction,
                fileKind: .markdown,
                location: .project(path: projectURL.path),
                isExpected: true
            ),
            AIConfigSource(
                provider: kind,
                title: "Project config.toml",
                url: projectURL
                    .appendingPathComponent(".codex", isDirectory: true)
                    .appendingPathComponent("config.toml", isDirectory: false),
                kind: .providerConfig,
                fileKind: .toml,
                location: .project(path: projectURL.path)
            ),
        ]
    }
}
