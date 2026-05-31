import Foundation
import Observation

/// The app's source of truth for sessions and aggregate usage. Owns the
/// scan/parse pipeline and a parse cache keyed by transcript metadata
/// so a refresh only re-parses transcripts that actually changed.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var isLoading = false
    private(set) var lastRefreshedAt: Date?
    /// Whether any provider's on-disk data directory exists — drives the
    /// "no Claude Code data found" empty state.
    private(set) var dataDirectoryExists: Bool
    @ObservationIgnored var onRefresh: (() -> Void)?

    private let registry: ProviderRegistry
    private let pricing: ModelPricing
    private var cache: [String: CacheEntry] = [:]
    private var autoRefreshTask: Task<Void, Never>?

    private struct CacheEntry {
        let fileSize: Int64
        let lastModified: Date
        let stats: SessionStats
    }

    private struct CommandCacheEntry {
        let fileSize: Int64
        let lastModified: Date
        let events: [SessionCommandEvent]
    }

    private var commandCache: [String: CommandCacheEntry] = [:]

    /// Max transcripts parsed concurrently.
    private static let parseBatchSize = 16

    init(registry: ProviderRegistry, pricing: ModelPricing) {
        self.registry = registry
        self.pricing = pricing
        self.dataDirectoryExists = registry.providers.contains { $0.dataDirectoryExists }
    }

    // MARK: Queries

    /// All discovered sessions belonging to `provider`.
    func sessions(for provider: ProviderKind) -> [Session] {
        sessions.filter { $0.provider == provider }
    }

    private func sessions(matching provider: ProviderKind?) -> [Session] {
        guard let provider else { return sessions }
        return sessions.filter { $0.provider == provider }
    }

    /// Whether `provider`'s on-disk data directory exists.
    func dataDirectoryExists(for provider: ProviderKind) -> Bool {
        registry.provider(for: provider)?.dataDirectoryExists ?? false
    }

    /// `provider`'s data directory path, for the empty-state message.
    func dataDirectoryPath(for provider: ProviderKind) -> String? {
        registry.provider(for: provider)?.dataDirectoryPath
    }

    /// Pretty label for a model id under `provider`. Falls back to the raw id
    /// when the provider is unknown — never returns a placeholder so callers
    /// can drop it straight into a label.
    func displayName(forModel id: String, provider: ProviderKind) -> String {
        registry.provider(for: provider)?.displayName(forModel: id) ?? id
    }

    func cacheHitRate(for usage: TokenUsage, provider: ProviderKind) -> Double? {
        registry.provider(for: provider)?.cacheHitRate(for: usage) ?? usage.cacheHitRate
    }

    func transcriptMessages(for session: Session) async -> [SessionTranscriptMessage] {
        guard let provider = registry.provider(for: session.provider) else { return [] }
        return await provider.transcriptMessages(for: session)
    }

    func transcriptMessageLoader(for provider: ProviderKind) -> TranscriptMessageLoader? {
        guard let provider = registry.provider(for: provider) else { return nil }
        return { session in
            await provider.transcriptMessages(for: session)
        }
    }

    func executedCommands(for session: Session) async -> [SessionCommandEvent] {
        let cacheKey = commandCacheKey(for: session)
        if let cached = commandCache[cacheKey],
           cached.fileSize == session.fileSize,
           cached.lastModified == session.lastModified {
            return cached.events
        }

        guard let provider = registry.provider(for: session.provider) else { return [] }
        let events = await provider.executedCommands(for: session)
        commandCache[cacheKey] = CommandCacheEntry(
            fileSize: session.fileSize,
            lastModified: session.lastModified,
            events: events
        )
        return events
    }

    func recentSessionCommandSummaries(
        sessionLimit: Int = 5,
        commandLimit: Int = 3
    ) async -> [SessionCommandSummary] {
        let recent = SessionCommandSummaryBuilder.recentSessions(sessions, limit: sessionLimit)
        var summaries: [SessionCommandSummary] = []
        summaries.reserveCapacity(recent.count)
        for session in recent {
            let events = await executedCommands(for: session)
            summaries.append(SessionCommandSummaryBuilder.summary(
                for: session,
                events: events,
                commandLimit: commandLimit
            ))
        }
        return summaries
    }

    func summary(for period: StatsPeriod, provider: ProviderKind? = nil, now: Date = .now) -> UsageSummary {
        UsageSummary.make(period: period, sessions: sessions(matching: provider), pricing: pricing, now: now)
    }

    func summary(for selection: PeriodSelection, provider: ProviderKind? = nil, now: Date = .now) -> UsageSummary {
        switch selection {
        case .preset(let period):
            return summary(for: period, provider: provider, now: now)
        case .custom(let start, let end):
            return UsageSummary.makeCustom(start: start, end: end, sessions: sessions(matching: provider), pricing: pricing)
        }
    }

    func sessions(in period: StatsPeriod, provider: ProviderKind? = nil, now: Date = .now) -> [Session] {
        sessions(matching: provider).filter { period.contains($0.stats?.lastActivity ?? $0.lastModified, now: now) }
    }

    // MARK: Refresh

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var discovered: [Session] = []
        for provider in registry.providers {
            discovered += await provider.discoverSessions()
        }
        discovered.sort { $0.lastModified > $1.lastModified }
        dataDirectoryExists = registry.providers.contains { $0.dataDirectoryExists }

        let providerByKind = Dictionary(uniqueKeysWithValues: registry.providers.map { ($0.kind, $0) })
        let stale = discovered.filter { session in
            guard let entry = cache[session.id] else { return true }
            return entry.fileSize != session.fileSize || entry.lastModified != session.lastModified
        }

        var index = 0
        while index < stale.count {
            let batch = stale[index ..< min(index + Self.parseBatchSize, stale.count)]
            index += Self.parseBatchSize
            await withTaskGroup(of: (String, Int64, Date, SessionStats?).self) { group in
                for session in batch {
                    guard let provider = providerByKind[session.provider] else { continue }
                    group.addTask { (session.id, session.fileSize, session.lastModified, await provider.parse(session)) }
                }
                for await (id, size, lastModified, stats) in group {
                    if let stats { cache[id] = CacheEntry(fileSize: size, lastModified: lastModified, stats: stats) }
                }
            }
        }

        let liveIDs = Set(discovered.map(\.id))
        let liveCommandKeys = Set(discovered.map { commandCacheKey(for: $0) })
        cache = cache.filter { liveIDs.contains($0.key) }
        commandCache = commandCache.filter { liveCommandKeys.contains($0.key) }

        var withStats = discovered
        for i in withStats.indices { withStats[i].stats = cache[withStats[i].id]?.stats }
        // Drop transcripts that parsed to nothing (only queue-ops / snapshots).
        sessions = withStats.filter { $0.stats != nil }
        lastRefreshedAt = .now
        Log.store.notice("Refreshed: \(self.sessions.count) sessions visible, \(stale.count) re-parsed")
        onRefresh?()
    }

    // MARK: Auto-refresh

    func startAutoRefresh(every interval: TimeInterval) {
        autoRefreshTask?.cancel()
        guard interval > 0 else { autoRefreshTask = nil; return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { break }
                await self.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    private func commandCacheKey(for session: Session) -> String {
        "\(session.provider.rawValue):\(session.id)"
    }
}

#if DEBUG
extension SessionStore {
    /// Inject canned sessions without touching disk — for SwiftUI previews.
    func loadPreviewSessions(_ sessions: [Session]) {
        self.sessions = sessions
        self.lastRefreshedAt = .now
        self.dataDirectoryExists = !sessions.isEmpty
    }
}
#endif
