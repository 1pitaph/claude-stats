import Foundation

/// Reads Claude Code sessions from `~/.claude/projects/`.
struct ClaudeProvider: Provider {
    let paths: ClaudePaths
    let pricing: ModelPricing
    let cliInstallDetector: any ClaudeCLIInstallDetecting
    let usageLimitCacheURLs: [URL]?

    init(
        paths: ClaudePaths,
        pricing: ModelPricing,
        cliInstallDetector: any ClaudeCLIInstallDetecting = ClaudeCLIInstallDetector(),
        usageLimitCacheURLs: [URL]? = nil
    ) {
        self.paths = paths
        self.pricing = pricing
        self.cliInstallDetector = cliInstallDetector
        self.usageLimitCacheURLs = usageLimitCacheURLs
    }

    var kind: ProviderKind { .claude }

    var dataDirectoryExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: paths.projectsDirectory.path, isDirectory: &isDir) && isDir.boolValue
    }

    var dataDirectoryPath: String? { paths.projectsDirectory.path }

    func discoverSessions() async -> [Session] {
        await SessionScanner(paths: paths).scan()
    }

    func parse(_ session: Session) async -> SessionStats? {
        await TranscriptParser(pricing: pricing)
            .parse(transcriptAt: URL(fileURLWithPath: session.filePath), fallbackTitle: session.projectDisplayName)
    }

    func transcriptMessages(for session: Session) async -> [SessionTranscriptMessage] {
        await TranscriptParser(pricing: pricing)
            .messages(transcriptAt: URL(fileURLWithPath: session.filePath))
    }

    func executedCommands(for session: Session) async -> [SessionCommandEvent] {
        await TranscriptParser(pricing: pricing)
            .executedCommands(transcriptAt: URL(fileURLWithPath: session.filePath))
    }

    /// Pretty label for Anthropic's canonical model ids:
    /// `claude-opus-4-7` → `Opus 4.7`, `claude-haiku-4-5` → `Haiku 4.5`,
    /// `claude-3.5-sonnet` → `Sonnet 3.5`. Unknown shapes fall back to a
    /// hyphen-cleaned, capitalised form so a previously-unseen id is still
    /// readable.
    func displayName(forModel id: String) -> String {
        Self.prettyName(for: id)
    }

    func globalConfigurationLocations() -> [ProviderConfigLocation] {
        [
            ProviderConfigLocation(
                provider: kind,
                title: "settings.json",
                url: paths.configDirectory.appendingPathComponent("settings.json", isDirectory: false),
                fileKind: .json
            ),
            ProviderConfigLocation(
                provider: kind,
                title: "CLAUDE.md",
                url: paths.configDirectory.appendingPathComponent("CLAUDE.md", isDirectory: false),
                fileKind: .markdown
            ),
        ]
    }

    func usageLimitReport(now: Date) async -> UsageLimitReport {
        let report = ClaudeUsageLimitLoader(paths: paths, cacheURLs: usageLimitCacheURLs).report(now: now)
        guard report.status == .setupRequired || report.status == .waitingForNextResponse else {
            return report
        }
        let isClaudeCLIInstalled = await cliInstallDetector.isClaudeCLIInstalled()
        guard !isClaudeCLIInstalled else {
            return report
        }
        return .setupRequired(
            provider: .claude,
            message: "Install Claude Code and sign in, then connect the status line bridge to capture 5h and weekly limits. You can also read visible Claude Desktop usage from this panel."
        )
    }

    func projectConfigurationLocations(for projectURL: URL) -> [ProviderConfigLocation] {
        [
            ProviderConfigLocation(
                provider: kind,
                title: "Project CLAUDE.md",
                url: projectURL.appendingPathComponent("CLAUDE.md", isDirectory: false),
                fileKind: .markdown
            ),
        ]
    }

    func globalAIConfigSources() -> [AIConfigSource] {
        [
            AIConfigSource(
                provider: kind,
                title: "settings.json",
                url: paths.configDirectory.appendingPathComponent("settings.json", isDirectory: false),
                kind: .providerConfig,
                fileKind: .json,
                location: .global,
                isExpected: true
            ),
            AIConfigSource(
                provider: kind,
                title: "settings.local.json",
                url: paths.configDirectory.appendingPathComponent("settings.local.json", isDirectory: false),
                kind: .providerConfig,
                fileKind: .json,
                location: .global
            ),
            AIConfigSource(
                provider: kind,
                title: "CLAUDE.md",
                url: paths.configDirectory.appendingPathComponent("CLAUDE.md", isDirectory: false),
                kind: .instruction,
                fileKind: .markdown,
                location: .global,
                isExpected: true
            ),
            AIConfigSource(
                provider: kind,
                title: "Plans",
                url: paths.configDirectory.appendingPathComponent("plans", isDirectory: true),
                kind: .plan,
                fileKind: .markdown,
                location: .planStore,
                target: .directory(extensions: ["md", "markdown"], maxDepth: 1)
            ),
            AIConfigSource(
                provider: kind,
                title: "Plugins",
                url: paths.configDirectory.appendingPathComponent("plugins", isDirectory: true),
                kind: .pluginConfig,
                fileKind: .json,
                location: .pluginStore,
                target: .directory(extensions: ["json"], maxDepth: 1)
            ),
        ]
    }

    func projectAIConfigSources(for projectURL: URL) -> [AIConfigSource] {
        [
            AIConfigSource(
                provider: kind,
                title: "Project CLAUDE.md",
                url: projectURL.appendingPathComponent("CLAUDE.md", isDirectory: false),
                kind: .instruction,
                fileKind: .markdown,
                location: .project(path: projectURL.path),
                isExpected: true
            ),
            AIConfigSource(
                provider: kind,
                title: "Project settings.local.json",
                url: projectURL
                    .appendingPathComponent(".claude", isDirectory: true)
                    .appendingPathComponent("settings.local.json", isDirectory: false),
                kind: .providerConfig,
                fileKind: .json,
                location: .project(path: projectURL.path)
            ),
        ]
    }

    static func prettyName(for id: String) -> String {
        if id == "<synthetic>" { return "Claude internal" }

        var stripped = id
        if stripped.hasPrefix("claude-") { stripped.removeFirst("claude-".count) }
        let parts = stripped.split(separator: "-", omittingEmptySubsequences: true).map(String.init)

        // `family-major-minor` (modern): opus-4-7, sonnet-4-6, haiku-4-5
        if parts.count == 3,
           let major = Int(parts[1]), let minor = Int(parts[2]) {
            return "\(parts[0].capitalized) \(major).\(minor)"
        }
        // `family-major` (no minor): opus-4
        if parts.count == 2, Int(parts[1]) != nil {
            return "\(parts[0].capitalized) \(parts[1])"
        }
        // `major.minor-family` (legacy): 3.5-sonnet, 3-opus
        if parts.count == 2,
           Double(parts[0]) != nil {
            return "\(parts[1].capitalized) \(parts[0])"
        }
        // Fallback: hyphen-cleaned, capitalised. Preserves any embedded dots.
        return parts.map { part in
            guard let head = part.first else { return "" }
            return String(head).uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }
}
