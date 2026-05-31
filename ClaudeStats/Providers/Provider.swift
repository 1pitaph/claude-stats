import Foundation

/// A source of AI-CLI usage data. One conformer per CLI.
///
/// Conformers are stateless value types so their `async` methods run off the
/// main actor (a `nonisolated async` function does not inherit the caller's
/// executor). Provider-specific quirks — path conventions, transcript format,
/// model-name aliases — live inside the conformer's folder; shared code
/// (`Models/`, `Services/`, views) only ever sees `Session` / `SessionStats`.
protocol Provider: Sendable {
    var kind: ProviderKind { get }

    /// Whether the on-disk location this provider reads from exists. Drives
    /// the "no data found" empty state without an expensive scan.
    var dataDirectoryExists: Bool { get }

    /// Human-readable path of the directory this provider reads from, shown in
    /// the empty state. `nil` if the provider has no fixed location yet.
    var dataDirectoryPath: String? { get }

    /// Cheap pass: enumerate transcripts and return their metadata. Does not
    /// open/parse the files. Newest first.
    func discoverSessions() async -> [Session]

    /// Parse one transcript into ``SessionStats``. `nil` if the file is gone
    /// or unreadable.
    func parse(_ session: Session) async -> SessionStats?

    /// Parse one transcript into displayable conversation entries. Providers
    /// decide which provider-specific events are useful enough to show.
    func transcriptMessages(for session: Session) async -> [SessionTranscriptMessage]

    /// Parse true executed shell/terminal commands from a provider transcript.
    /// Mentions in natural-language messages are intentionally ignored.
    func executedCommands(for session: Session) async -> [SessionCommandEvent]

    /// Pretty label for a canonical model id. Used wherever a model surfaces
    /// to the user (Dashboard breakdown, "Favorite model" stat, …). Default
    /// returns the id unchanged — providers override when their ids carry a
    /// readable structure (e.g. Claude's `claude-opus-4-7` → `Opus 4.7`).
    func displayName(forModel id: String) -> String

    /// Cache percentage shown in the Usage panel. Providers can override when
    /// their transcript format reports cache fields with different semantics.
    func cacheHitRate(for usage: TokenUsage) -> Double?

    /// Global configuration files owned by this CLI. Providers decide their own
    /// path conventions so shared UI never switches on provider names.
    func globalConfigurationLocations() -> [ProviderConfigLocation]

    /// Project-local configuration files owned by this CLI for a given working
    /// directory.
    func projectConfigurationLocations(for projectURL: URL) -> [ProviderConfigLocation]

    /// Read-only AI configuration sources surfaced by the Configs page.
    /// Providers own path conventions; the shared scanner owns parsing,
    /// statistics, and diagnostics.
    func globalAIConfigSources() -> [AIConfigSource]

    /// Project-local AI configuration sources surfaced by the Configs page.
    func projectAIConfigSources(for projectURL: URL) -> [AIConfigSource]

    /// Optional provider-owned usage-limit snapshot. Providers that expose
    /// rate-limit windows keep file formats and source-specific fallback logic
    /// behind this boundary so shared UI can remain provider-agnostic.
    func usageLimitReport(now: Date) async -> UsageLimitReport
}

extension Provider {
    var dataDirectoryPath: String? { nil }
    func transcriptMessages(for session: Session) async -> [SessionTranscriptMessage] { [] }
    func executedCommands(for session: Session) async -> [SessionCommandEvent] { [] }
    func displayName(forModel id: String) -> String { id }
    func cacheHitRate(for usage: TokenUsage) -> Double? { usage.cacheHitRate }
    func globalConfigurationLocations() -> [ProviderConfigLocation] { [] }
    func projectConfigurationLocations(for projectURL: URL) -> [ProviderConfigLocation] { [] }
    func globalAIConfigSources() -> [AIConfigSource] { [] }
    func projectAIConfigSources(for projectURL: URL) -> [AIConfigSource] { [] }
    func usageLimitReport(now: Date) async -> UsageLimitReport { .unsupported(provider: kind) }
}
