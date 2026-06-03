import Foundation
import Observation

/// What the menu-bar status item shows.
enum MenuBarMetric: String, CaseIterable, Sendable, Identifiable {
    case tokens
    case cost
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .tokens: L10n.string("menu_bar.metric.tokens", defaultValue: "Tokens")
        case .cost: L10n.string("menu_bar.metric.cost", defaultValue: "Cost")
        }
    }
}

enum APIProviderKeyStorageMode: String, CaseIterable, Sendable, Identifiable {
    case json
    case keychain

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .json: "JSON"
        case .keychain: L10n.string("api_key_storage.keychain", defaultValue: "Keychain")
        }
    }
}

/// Thin, observable wrapper over the handful of `UserDefaults` keys the app
/// uses. Writing a property persists it immediately.
@MainActor
@Observable
final class Preferences {
    var appLanguagePreference: AppLanguagePreference {
        didSet {
            defaults.set(appLanguagePreference.rawValue, forKey: Keys.appLanguagePreference)
            appLanguagePreference.applyToAppleLanguages(defaults: defaults)
        }
    }
    var autoRefreshMinutes: Int {
        didSet { defaults.set(autoRefreshMinutes, forKey: Keys.autoRefreshMinutes) }
    }
    var menuBarMetric: MenuBarMetric {
        didSet { defaults.set(menuBarMetric.rawValue, forKey: Keys.menuBarMetric) }
    }
    var menuBarPeriod: StatsPeriod {
        didSet { defaults.set(menuBarPeriod.rawValue, forKey: Keys.menuBarPeriod) }
    }
    /// Whether token totals shown in the app (Usage stats, BY MODEL, sessions
    /// list) include `cache_read` tokens. On by default — `cache_read` is what
    /// Anthropic's API reports per turn, so excluding it disagrees with the
    /// Console. Off gives a "real flow-through" figure closer to billed
    /// (non-cached) traffic. ``cache_creation`` is always counted regardless;
    /// only the per-turn cache-read re-reporting is what this gates.
    var includeCacheInTokens: Bool {
        didSet { defaults.set(includeCacheInTokens, forKey: Keys.includeCacheInTokens) }
    }
    /// Which cost estimate the UI displays. The standard API mode is the
    /// stable baseline; detailed billing applies only billable details that
    /// transcripts expose explicitly.
    var costEstimationMode: CostEstimationMode {
        didSet { defaults.set(costEstimationMode.rawValue, forKey: Keys.costEstimationMode) }
    }
    /// Same setting, but specifically for the menu-bar status item. Independent
    /// so users can keep the app totals canonical while the menu bar shows a
    /// less inflated figure (or vice versa).
    var menuBarIncludesCache: Bool {
        didSet { defaults.set(menuBarIncludesCache, forKey: Keys.menuBarIncludesCache) }
    }
    /// Whether launching Claude Stats should present the main window. On by
    /// default so double-clicking the app behaves like a normal windowed app.
    var openMainWindowOnLaunch: Bool {
        didSet { defaults.set(openMainWindowOnLaunch, forKey: Keys.openMainWindowOnLaunch) }
    }
    /// Optional floating edge tab used as a backup entry point when the macOS
    /// menu bar is crowded.
    var floatingTabEnabled: Bool {
        didSet { defaults.set(floatingTabEnabled, forKey: Keys.floatingTabEnabled) }
    }
    /// Cursor-adjacent command palette for recent AI sessions. It is quiet until
    /// Accessibility permission is granted.
    var cursorCommandOverlayEnabled: Bool {
        didSet { defaults.set(cursorCommandOverlayEnabled, forKey: Keys.cursorCommandOverlayEnabled) }
    }
    /// Last snapped edge for the floating tab. Kept out of Settings to keep the
    /// UI simple; dragging the tab updates it silently.
    var floatingTabEdge: FloatingPanelEdge {
        didSet { defaults.set(floatingTabEdge.rawValue, forKey: Keys.floatingTabEdge) }
    }
    /// Normalized position along ``floatingTabEdge``. 0 is minX/minY, 1 is
    /// maxX/maxY; geometry helpers clamp it so the tab remains visible.
    var floatingTabAnchor: Double {
        didSet { defaults.set(floatingTabAnchor, forKey: Keys.floatingTabAnchor) }
    }
    /// Camera-notch Dynamic Island surface adapted from Atoll. Off by default
    /// so the existing menu-bar and floating-tab entry points remain unchanged.
    var notchIslandEnabled: Bool {
        didSet { defaults.set(notchIslandEnabled, forKey: Keys.notchIslandEnabled) }
    }
    var notchIslandDisplayMode: NotchIslandDisplayMode {
        didSet { defaults.set(notchIslandDisplayMode.rawValue, forKey: Keys.notchIslandDisplayMode) }
    }
    var notchIslandSelectedScreenIDs: Set<String> {
        didSet {
            if notchIslandSelectedScreenIDs.isEmpty {
                notchIslandSelectedScreenIDs = NotchIslandScreenCatalog.defaultSelectedScreenIDs()
                return
            }
            defaults.set(
                notchIslandSelectedScreenIDs.sorted().joined(separator: ","),
                forKey: Keys.notchIslandSelectedScreenIDs
            )
        }
    }
    var notchIslandScreenStyles: [String: NotchIslandScreenStyle] {
        didSet {
            persistNotchIslandScreenStyles()
        }
    }
    var notchIslandSizePreset: NotchIslandSizePreset {
        didSet { defaults.set(notchIslandSizePreset.rawValue, forKey: Keys.notchIslandSizePreset) }
    }
    var notchIslandHoverExpansionEnabled: Bool {
        didSet { defaults.set(notchIslandHoverExpansionEnabled, forKey: Keys.notchIslandHoverExpansionEnabled) }
    }
    var notchIslandShortcutEnabled: Bool {
        didSet { defaults.set(notchIslandShortcutEnabled, forKey: Keys.notchIslandShortcutEnabled) }
    }
    var notchIslandEnabledModules: Set<NotchIslandModule> {
        didSet {
            if notchIslandEnabledModules.isEmpty {
                notchIslandEnabledModules = NotchIslandModule.defaultEnabled
            }
            defaults.set(
                notchIslandEnabledModules.map(\.rawValue).sorted().joined(separator: ","),
                forKey: Keys.notchIslandEnabledModules
            )
        }
    }
    var detailPanelBoundaryFalloffEnabled: Bool {
        didSet { defaults.set(detailPanelBoundaryFalloffEnabled, forKey: Keys.detailPanelBoundaryFalloffEnabled) }
    }
    var networkTrafficLayoutMode: NetworkTrafficLayoutMode {
        didSet { defaults.set(networkTrafficLayoutMode.rawValue, forKey: Keys.networkTrafficLayoutMode) }
    }
    var networkTrafficAutoBreakpoint: Double {
        didSet {
            let clamped = NetworkTrafficLayoutConstants.clampedAutoBreakpoint(networkTrafficAutoBreakpoint)
            guard clamped == networkTrafficAutoBreakpoint else {
                networkTrafficAutoBreakpoint = clamped
                return
            }
            defaults.set(networkTrafficAutoBreakpoint, forKey: Keys.networkTrafficAutoBreakpoint)
        }
    }
    var networkAutoEnableSystemProxyOnStart: Bool {
        didSet { defaults.set(networkAutoEnableSystemProxyOnStart, forKey: Keys.networkAutoEnableSystemProxyOnStart) }
    }
    var networkUpstreamProxyMode: NetworkUpstreamProxyMode {
        didSet { defaults.set(networkUpstreamProxyMode.rawValue, forKey: Keys.networkUpstreamProxyMode) }
    }
    var networkAskBeforeChainingExistingSystemProxy: Bool {
        didSet { defaults.set(networkAskBeforeChainingExistingSystemProxy, forKey: Keys.networkAskBeforeChainingExistingSystemProxy) }
    }
    var networkManualUpstreamProxyProtocol: NetworkUpstreamProxyProtocol {
        didSet { defaults.set(networkManualUpstreamProxyProtocol.rawValue, forKey: Keys.networkManualUpstreamProxyProtocol) }
    }
    var networkManualUpstreamProxyHost: String {
        didSet { defaults.set(networkManualUpstreamProxyHost, forKey: Keys.networkManualUpstreamProxyHost) }
    }
    var networkManualUpstreamProxyPort: Int {
        didSet { defaults.set(networkManualUpstreamProxyPort, forKey: Keys.networkManualUpstreamProxyPort) }
    }
    var networkManualUpstreamProxyPACURL: String {
        didSet { defaults.set(networkManualUpstreamProxyPACURL, forKey: Keys.networkManualUpstreamProxyPACURL) }
    }
    var networkManualUpstreamProxyUsername: String {
        didSet { defaults.set(networkManualUpstreamProxyUsername, forKey: Keys.networkManualUpstreamProxyUsername) }
    }
    var networkManualUpstreamProxyIncludeHosts: String {
        didSet { defaults.set(networkManualUpstreamProxyIncludeHosts, forKey: Keys.networkManualUpstreamProxyIncludeHosts) }
    }
    var networkManualUpstreamProxyExcludeHosts: String {
        didSet { defaults.set(networkManualUpstreamProxyExcludeHosts, forKey: Keys.networkManualUpstreamProxyExcludeHosts) }
    }
    var networkManualUpstreamBypassLocalhost: Bool {
        didSet { defaults.set(networkManualUpstreamBypassLocalhost, forKey: Keys.networkManualUpstreamBypassLocalhost) }
    }
    var networkManualUpstreamDNSOverSOCKS: Bool {
        didSet { defaults.set(networkManualUpstreamDNSOverSOCKS, forKey: Keys.networkManualUpstreamDNSOverSOCKS) }
    }
    var sessionsExpandedOnAppOpen: Bool {
        didSet { defaults.set(sessionsExpandedOnAppOpen, forKey: Keys.sessionsExpandedOnAppOpen) }
    }
    var terminalChromeMode: TerminalChromeMode {
        didSet { defaults.set(terminalChromeMode.rawValue, forKey: Keys.terminalChromeMode) }
    }
    var terminalBackgroundStyle: TerminalBackgroundStyle {
        didSet { defaults.set(terminalBackgroundStyle.rawValue, forKey: Keys.terminalBackgroundStyle) }
    }
    var terminalRuntimeKind: TerminalRuntimeKind {
        didSet { defaults.set(terminalRuntimeKind.rawValue, forKey: Keys.terminalRuntimeKind) }
    }
    var apiProviderKeyStorageMode: APIProviderKeyStorageMode {
        didSet { defaults.set(apiProviderKeyStorageMode.rawValue, forKey: Keys.apiProviderKeyStorageMode) }
    }
    var systemMonitorEnabled: Bool {
        didSet { defaults.set(systemMonitorEnabled, forKey: Keys.systemMonitorEnabled) }
    }
    var systemMonitorRefreshRate: SystemMonitorRefreshRate {
        didSet { defaults.set(systemMonitorRefreshRate.rawValue, forKey: Keys.systemMonitorRefreshRate) }
    }
    var systemMonitorVisibleModules: Set<SystemMonitorModule> {
        didSet {
            if systemMonitorVisibleModules.isEmpty {
                systemMonitorVisibleModules = SystemMonitorModule.defaultVisible
            }
            defaults.set(
                systemMonitorVisibleModules.map(\.rawValue).sorted().joined(separator: ","),
                forKey: Keys.systemMonitorVisibleModules
            )
        }
    }

    /// Which platforms the user has turned on. The switcher bar only appears
    /// when this has more than one entry; otherwise the panel shows the single
    /// enabled platform (and the original scanline strip). Always non-empty.
    var enabledProviders: Set<ProviderKind> {
        didSet {
            if enabledProviders.isEmpty { enabledProviders = [.claude] }   // re-fires didSet, persists below
            defaults.set(enabledProviders.map(\.rawValue).joined(separator: ","), forKey: Keys.enabledProviders)
            if !enabledProviders.contains(selectedProvider) {
                selectedProvider = orderedEnabledProviders.first ?? .claude
            }
        }
    }
    /// The platform currently being viewed. Always a member of ``enabledProviders``.
    var selectedProvider: ProviderKind {
        didSet { defaults.set(selectedProvider.rawValue, forKey: Keys.selectedProvider) }
    }
    /// When off, the app forgets ``selectedProvider`` on launch and starts on
    /// the first enabled platform.
    var rememberSelectedProvider: Bool {
        didSet { defaults.set(rememberSelectedProvider, forKey: Keys.rememberSelectedProvider) }
    }

    /// ``enabledProviders`` in canonical (``ProviderKind/allCases``) order.
    var orderedEnabledProviders: [ProviderKind] {
        ProviderKind.allCases.filter(enabledProviders.contains)
    }

    /// Opt-in to the AI activity analysis (reads macOS Screen Time; needs Full
    /// Disk Access). Off by default — the Activity tab only appears when on.
    var aiActivityAnalysisEnabled: Bool {
        didSet { defaults.set(aiActivityAnalysisEnabled, forKey: Keys.aiActivityAnalysisEnabled) }
    }
    /// Opt-in to git tracking — adds a view that correlates Claude usage with the
    /// commit activity of the repos you've used Claude in. Off by default.
    var gitTrackingEnabled: Bool {
        didSet { defaults.set(gitTrackingEnabled, forKey: Keys.gitTrackingEnabled) }
    }
    /// When git tracking is on: `true` opens the git view in its own window
    /// (button next to the panel title); `false` shows it as a pane in the panel.
    var gitOpensInWindow: Bool {
        didSet { defaults.set(gitOpensInWindow, forKey: Keys.gitOpensInWindow) }
    }
    /// Sources whose remembered workspaces feed the Git view. Defaults to
    /// Claude Code + Codex sessions, with AI editor workspace histories opt-in.
    var gitWorkspaceSourceIDs: Set<GitWorkspaceSourceID> {
        didSet {
            let normalized = GitWorkspaceSourceCatalog.normalized(gitWorkspaceSourceIDs)
            guard normalized == gitWorkspaceSourceIDs else {
                gitWorkspaceSourceIDs = normalized
                return
            }
            defaults.set(
                GitWorkspaceSourceCatalog.storageString(for: normalized),
                forKey: Keys.gitWorkspaceSourceIDs
            )
        }
    }
    /// Which tree the repo language/SLOC inspector uses.
    var gitStatsScope: GitStatsScope {
        didSet { defaults.set(gitStatsScope.rawValue, forKey: Keys.gitStatsScope) }
    }
    /// How split diff panes group changed lines into colored blocks.
    var gitDiffBlockGranularity: GitDiffBlockGranularity {
        didSet { defaults.set(gitDiffBlockGranularity.rawValue, forKey: Keys.gitDiffBlockGranularity) }
    }
    /// Opt-in to comparing local activity against the GitHub contribution
    /// graph on the Dashboard. Off by default — the dashboard's GitHub panel
    /// only appears when this is on and a PAT is configured.
    var githubEnabled: Bool {
        didSet { defaults.set(githubEnabled, forKey: Keys.githubEnabled) }
    }
    /// Last known GitHub login, for the Dashboard / Settings status row.
    /// Empty when not connected. The PAT itself lives in the Keychain.
    var githubLogin: String {
        didSet { defaults.set(githubLogin, forKey: Keys.githubLogin) }
    }
    var linuxDoNotificationsEnabled: Bool {
        didSet { defaults.set(linuxDoNotificationsEnabled, forKey: Keys.linuxDoNotificationsEnabled) }
    }
    var linuxDoLastSeenNotificationID: Int {
        didSet { defaults.set(linuxDoLastSeenNotificationID, forKey: Keys.linuxDoLastSeenNotificationID) }
    }
    var linuxDoNotificationDeliveredIDs: [Int] {
        didSet {
            defaults.set(
                linuxDoNotificationDeliveredIDs.map(String.init).joined(separator: ","),
                forKey: Keys.linuxDoNotificationDeliveredIDs
            )
        }
    }
    var linuxDoLastLoginUsername: String {
        didSet { defaults.set(linuxDoLastLoginUsername, forKey: Keys.linuxDoLastLoginUsername) }
    }
    var linuxDoSelectedFeed: String {
        didSet { defaults.set(linuxDoSelectedFeed, forKey: Keys.linuxDoSelectedFeed) }
    }
    var linuxDoReadingPositions: [Int: LinuxDoReadingPosition] {
        didSet {
            let trimmed = Self.trimLinuxDoReadingPositions(linuxDoReadingPositions)
            guard trimmed == linuxDoReadingPositions else {
                linuxDoReadingPositions = trimmed
                return
            }
            persistLinuxDoReadingPositions()
        }
    }
    /// Claude Status components shown on the Dashboard and monitored for
    /// optional notifications. Defaults to `claude.ai` and `Claude Code`.
    var claudeStatusVisibleComponentIDs: Set<String> {
        didSet {
            if claudeStatusVisibleComponentIDs.isEmpty {
                claudeStatusVisibleComponentIDs = ClaudeStatusComponentCatalog.defaultVisibleComponentIDs
            }
            defaults.set(claudeStatusVisibleComponentIDs.sorted().joined(separator: ","), forKey: Keys.claudeStatusVisibleComponentIDs)
        }
    }
    /// Opt-in to macOS notifications when one of the visible Claude Status
    /// components is not operational.
    var claudeStatusNotificationsEnabled: Bool {
        didSet { defaults.set(claudeStatusNotificationsEnabled, forKey: Keys.claudeStatusNotificationsEnabled) }
    }
    /// Last abnormal visible-component status notification sent. Stored so the
    /// app does not repeat the same alert across polling cycles or relaunches.
    var claudeStatusLastNotificationFingerprint: String {
        didSet { defaults.set(claudeStatusLastNotificationFingerprint, forKey: Keys.claudeStatusLastNotificationFingerprint) }
    }
    /// Claude Desktop UI usage capture. The default only tries when Claude is
    /// already frontmost, so it never steals focus.
    var claudeDesktopUsageAutoMode: ClaudeDesktopUsageAutoMode {
        didSet { defaults.set(claudeDesktopUsageAutoMode.rawValue, forKey: Keys.claudeDesktopUsageAutoMode) }
    }
    /// Optional timed Claude Desktop usage capture. Disabled by default.
    var claudeDesktopUsageTimedCaptureEnabled: Bool {
        didSet { defaults.set(claudeDesktopUsageTimedCaptureEnabled, forKey: Keys.claudeDesktopUsageTimedCaptureEnabled) }
    }
    var claudeDesktopUsageTimedIntervalMinutes: Int {
        didSet {
            let clamped = min(240, max(5, claudeDesktopUsageTimedIntervalMinutes))
            guard clamped == claudeDesktopUsageTimedIntervalMinutes else {
                claudeDesktopUsageTimedIntervalMinutes = clamped
                return
            }
            defaults.set(claudeDesktopUsageTimedIntervalMinutes, forKey: Keys.claudeDesktopUsageTimedIntervalMinutes)
        }
    }
    /// Claude usage-limit windows shown in the Usage Limits panel. The 5h and
    /// 7d windows are always visible; this set controls optional GUI-only rows.
    var claudeUsageLimitVisibleWindowIDs: Set<String> {
        didSet {
            let normalized = UsageLimitWindowCatalog.normalizedClaudeVisibleWindowIDs(claudeUsageLimitVisibleWindowIDs)
            guard normalized == claudeUsageLimitVisibleWindowIDs else {
                claudeUsageLimitVisibleWindowIDs = normalized
                return
            }
            defaults.set(normalized.sorted().joined(separator: ","), forKey: Keys.claudeUsageLimitVisibleWindowIDs)
        }
    }
    /// OpenAI Status product groups shown on the Dashboard and monitored for
    /// optional notifications. Defaults to ChatGPT and Codex.
    var openAIStatusVisibleGroupIDs: Set<String> {
        didSet {
            if openAIStatusVisibleGroupIDs.isEmpty {
                openAIStatusVisibleGroupIDs = OpenAIStatusGroupCatalog.defaultVisibleGroupIDs
            }
            defaults.set(openAIStatusVisibleGroupIDs.sorted().joined(separator: ","), forKey: Keys.openAIStatusVisibleGroupIDs)
        }
    }
    /// Opt-in to macOS notifications when one of the visible OpenAI Status
    /// product groups is not operational.
    var openAIStatusNotificationsEnabled: Bool {
        didSet { defaults.set(openAIStatusNotificationsEnabled, forKey: Keys.openAIStatusNotificationsEnabled) }
    }
    /// Last abnormal visible OpenAI Status notification sent. Stored so the app
    /// does not repeat the same alert across polling cycles or relaunches.
    var openAIStatusLastNotificationFingerprint: String {
        didSet { defaults.set(openAIStatusLastNotificationFingerprint, forKey: Keys.openAIStatusLastNotificationFingerprint) }
    }
    /// Which colour scheme the Overlap heatmap should use.
    var overlapPalette: OverlapPalette {
        didSet { defaults.set(overlapPalette.rawValue, forKey: Keys.overlapPalette) }
    }
    /// Opt-in to publishing aggregate, privacy-preserving leaderboard scores to
    /// CloudKit's public database. Off by default.
    var leaderboardsEnabled: Bool {
        didSet {
            defaults.set(leaderboardsEnabled, forKey: Keys.leaderboardsEnabled)
            persistSharedLeaderboardPreferences()
        }
    }
    /// Public display name shown next to submitted leaderboard scores. Stored
    /// locally in defaults; CloudKit receives only this nickname and aggregate
    /// scores.
    var leaderboardNickname: String {
        didSet {
            defaults.set(leaderboardNickname, forKey: Keys.leaderboardNickname)
            persistSharedLeaderboardPreferences()
        }
    }
    /// Random seed used to render the user's public Beam avatar. It is scoped
    /// to the current iCloud user hash by ``leaderboardProfileUserHash``.
    var leaderboardAvatarSeed: String {
        didSet {
            defaults.set(leaderboardAvatarSeed, forKey: Keys.leaderboardAvatarSeed)
            persistSharedLeaderboardPreferences()
        }
    }
    /// Last iCloud user hash this local leaderboard profile was reconciled
    /// against. If it changes, the app reloads or regenerates the avatar seed.
    var leaderboardProfileUserHash: String {
        didSet {
            defaults.set(leaderboardProfileUserHash, forKey: Keys.leaderboardProfileUserHash)
            persistSharedLeaderboardPreferences()
        }
    }
    var leaderboardLastSyncedAt: Date? {
        didSet {
            defaults.set(leaderboardLastSyncedAt, forKey: Keys.leaderboardLastSyncedAt)
            persistSharedLeaderboardPreferences()
        }
    }
    var leaderboardLastSyncError: String {
        didSet {
            defaults.set(leaderboardLastSyncError, forKey: Keys.leaderboardLastSyncError)
            persistSharedLeaderboardPreferences()
        }
    }
    var leaderboardLastSubmittedPeriodKeys: [String] {
        didSet {
            defaults.set(leaderboardLastSubmittedPeriodKeys, forKey: Keys.leaderboardLastSubmittedPeriodKeys)
            persistSharedLeaderboardPreferences()
        }
    }
    /// Extra GUI coding-surface bundle ids the user added on top of
    /// ``ActivitySurfaceCatalog/codingSurfaceDefaults``.
    var codingSurfaceBundleIDsAdded: [String] {
        didSet { defaults.set(codingSurfaceBundleIDsAdded, forKey: Keys.codingSurfaceBundleIDsAdded) }
    }
    /// Default GUI coding-surface bundle ids the user turned off.
    var codingSurfaceBundleIDsRemoved: [String] {
        didSet { defaults.set(codingSurfaceBundleIDsRemoved, forKey: Keys.codingSurfaceBundleIDsRemoved) }
    }
    /// Extra terminal/CLI-host bundle ids the user added on top of
    /// ``ActivitySurfaceCatalog/cliHostDefaults``.
    var cliHostBundleIDsAdded: [String] {
        didSet { defaults.set(cliHostBundleIDsAdded, forKey: Keys.cliHostBundleIDsAdded) }
    }
    /// Default terminal/CLI-host bundle ids the user turned off.
    var cliHostBundleIDsRemoved: [String] {
        didSet { defaults.set(cliHostBundleIDsRemoved, forKey: Keys.cliHostBundleIDsRemoved) }
    }

    /// The GUI coding-surface bundle ids actually in effect for the analysis.
    var effectiveCodingSurfaceBundleIDs: Set<String> {
        ActivitySurfaceCatalog.effectiveCodingSurfaceBundleIDs(
            added: codingSurfaceBundleIDsAdded,
            removed: codingSurfaceBundleIDsRemoved
        )
    }

    /// The CLI-host bundle ids actually in effect for the analysis.
    var effectiveCLIHostBundleIDs: Set<String> {
        ActivitySurfaceCatalog.effectiveCLIHostBundleIDs(
            added: cliHostBundleIDsAdded,
            removed: cliHostBundleIDsRemoved
        )
    }

    /// All app-focus bundle ids needed for one Screen Time query.
    var effectiveActivityBundleIDs: Set<String> {
        effectiveCodingSurfaceBundleIDs.union(effectiveCLIHostBundleIDs)
    }

    private let defaults: UserDefaults
    private let leaderboardSharedStore: LeaderboardSharedPreferencesStore?

    init(defaults: UserDefaults = .standard,
         leaderboardSharedStore: LeaderboardSharedPreferencesStore? = nil) {
        self.defaults = defaults
        self.leaderboardSharedStore = leaderboardSharedStore ?? Self.defaultLeaderboardSharedStore(for: defaults)
        appLanguagePreference = AppLanguagePreference(rawValue: defaults.string(forKey: Keys.appLanguagePreference) ?? "") ?? .system
        autoRefreshMinutes = (defaults.object(forKey: Keys.autoRefreshMinutes) as? Int) ?? 5
        menuBarMetric = MenuBarMetric(rawValue: defaults.string(forKey: Keys.menuBarMetric) ?? "") ?? .tokens
        menuBarPeriod = StatsPeriod(rawValue: defaults.string(forKey: Keys.menuBarPeriod) ?? "") ?? .allTime
        includeCacheInTokens = (defaults.object(forKey: Keys.includeCacheInTokens) as? Bool) ?? true
        costEstimationMode = CostEstimationMode(rawValue: defaults.string(forKey: Keys.costEstimationMode) ?? "") ?? .standardAPI
        menuBarIncludesCache = (defaults.object(forKey: Keys.menuBarIncludesCache) as? Bool) ?? true
        openMainWindowOnLaunch = (defaults.object(forKey: Keys.openMainWindowOnLaunch) as? Bool) ?? true
        floatingTabEnabled = (defaults.object(forKey: Keys.floatingTabEnabled) as? Bool) ?? true
        cursorCommandOverlayEnabled = (defaults.object(forKey: Keys.cursorCommandOverlayEnabled) as? Bool) ?? true
        floatingTabEdge = FloatingPanelEdge(rawValue: defaults.string(forKey: Keys.floatingTabEdge) ?? "") ?? .right
        floatingTabAnchor = (defaults.object(forKey: Keys.floatingTabAnchor) as? Double) ?? 0.5
        notchIslandEnabled = defaults.bool(forKey: Keys.notchIslandEnabled)
        let legacyNotchDisplayMode = NotchIslandDisplayMode(rawValue: defaults.string(forKey: Keys.notchIslandDisplayMode) ?? "") ?? .primaryDisplay
        notchIslandDisplayMode = legacyNotchDisplayMode
        let storedNotchScreenIDsRaw = defaults.string(forKey: Keys.notchIslandSelectedScreenIDs) ?? ""
        let storedNotchScreenIDs = storedNotchScreenIDsRaw
            .split(separator: ",")
            .map { String($0) }
        if storedNotchScreenIDs.isEmpty {
            let migratedScreenIDs = NotchIslandScreenCatalog.defaultSelectedScreenIDs(for: legacyNotchDisplayMode)
            notchIslandSelectedScreenIDs = migratedScreenIDs
            defaults.set(migratedScreenIDs.sorted().joined(separator: ","), forKey: Keys.notchIslandSelectedScreenIDs)
        } else {
            notchIslandSelectedScreenIDs = Set(storedNotchScreenIDs)
        }
        notchIslandScreenStyles = Self.decodeNotchIslandScreenStyles(defaults.string(forKey: Keys.notchIslandScreenStyles))
        notchIslandSizePreset = NotchIslandSizePreset(rawValue: defaults.string(forKey: Keys.notchIslandSizePreset) ?? "") ?? .regular
        notchIslandHoverExpansionEnabled = (defaults.object(forKey: Keys.notchIslandHoverExpansionEnabled) as? Bool) ?? true
        notchIslandShortcutEnabled = (defaults.object(forKey: Keys.notchIslandShortcutEnabled) as? Bool) ?? true
        let storedNotchModules = (defaults.string(forKey: Keys.notchIslandEnabledModules) ?? "")
            .split(separator: ",")
            .compactMap { NotchIslandModule(rawValue: String($0)) }
        notchIslandEnabledModules = storedNotchModules.isEmpty
            ? NotchIslandModule.defaultEnabled
            : Set(storedNotchModules)
        detailPanelBoundaryFalloffEnabled = (defaults.object(forKey: Keys.detailPanelBoundaryFalloffEnabled) as? Bool) ?? true
        networkTrafficLayoutMode = NetworkTrafficLayoutMode(rawValue: defaults.string(forKey: Keys.networkTrafficLayoutMode) ?? "") ?? .automatic
        let storedNetworkTrafficAutoBreakpoint = (defaults.object(forKey: Keys.networkTrafficAutoBreakpoint) as? Double)
            ?? NetworkTrafficLayoutConstants.defaultAutoBreakpoint
        networkTrafficAutoBreakpoint = NetworkTrafficLayoutConstants.clampedAutoBreakpoint(storedNetworkTrafficAutoBreakpoint)
        networkAutoEnableSystemProxyOnStart = (defaults.object(forKey: Keys.networkAutoEnableSystemProxyOnStart) as? Bool) ?? false
        networkUpstreamProxyMode = NetworkUpstreamProxyMode(rawValue: defaults.string(forKey: Keys.networkUpstreamProxyMode) ?? "") ?? .automatic
        networkAskBeforeChainingExistingSystemProxy = (defaults.object(forKey: Keys.networkAskBeforeChainingExistingSystemProxy) as? Bool) ?? false
        networkManualUpstreamProxyProtocol = NetworkUpstreamProxyProtocol(rawValue: defaults.string(forKey: Keys.networkManualUpstreamProxyProtocol) ?? "") ?? .http
        networkManualUpstreamProxyHost = defaults.string(forKey: Keys.networkManualUpstreamProxyHost) ?? ""
        networkManualUpstreamProxyPort = (defaults.object(forKey: Keys.networkManualUpstreamProxyPort) as? Int) ?? 6_152
        networkManualUpstreamProxyPACURL = defaults.string(forKey: Keys.networkManualUpstreamProxyPACURL) ?? ""
        networkManualUpstreamProxyUsername = defaults.string(forKey: Keys.networkManualUpstreamProxyUsername) ?? ""
        networkManualUpstreamProxyIncludeHosts = defaults.string(forKey: Keys.networkManualUpstreamProxyIncludeHosts) ?? ""
        networkManualUpstreamProxyExcludeHosts = defaults.string(forKey: Keys.networkManualUpstreamProxyExcludeHosts) ?? ""
        networkManualUpstreamBypassLocalhost = (defaults.object(forKey: Keys.networkManualUpstreamBypassLocalhost) as? Bool) ?? true
        networkManualUpstreamDNSOverSOCKS = (defaults.object(forKey: Keys.networkManualUpstreamDNSOverSOCKS) as? Bool) ?? true
        sessionsExpandedOnAppOpen = (defaults.object(forKey: Keys.sessionsExpandedOnAppOpen) as? Bool) ?? false
        terminalChromeMode = TerminalChromeMode(rawValue: defaults.string(forKey: Keys.terminalChromeMode) ?? "") ?? .tabsAndStatus
        terminalBackgroundStyle = TerminalBackgroundStyle(rawValue: defaults.string(forKey: Keys.terminalBackgroundStyle) ?? "") ?? .fluidGradient
        terminalRuntimeKind = TerminalRuntimeKind(rawValue: defaults.string(forKey: Keys.terminalRuntimeKind) ?? "") ?? .warp
        apiProviderKeyStorageMode = APIProviderKeyStorageMode(rawValue: defaults.string(forKey: Keys.apiProviderKeyStorageMode) ?? "") ?? .json
        systemMonitorEnabled = defaults.bool(forKey: Keys.systemMonitorEnabled)
        systemMonitorRefreshRate = SystemMonitorRefreshRate(rawValue: defaults.string(forKey: Keys.systemMonitorRefreshRate) ?? "") ?? .threeSeconds
        let storedSystemMonitorModules = (defaults.string(forKey: Keys.systemMonitorVisibleModules) ?? "")
            .split(separator: ",")
            .compactMap { SystemMonitorModule(rawValue: String($0)) }
        systemMonitorVisibleModules = storedSystemMonitorModules.isEmpty
            ? SystemMonitorModule.defaultVisible
            : Set(storedSystemMonitorModules)
        aiActivityAnalysisEnabled = defaults.bool(forKey: Keys.aiActivityAnalysisEnabled)
        gitTrackingEnabled = (defaults.object(forKey: Keys.gitTrackingEnabled) as? Bool) ?? AppVariant.isLite
        gitOpensInWindow = defaults.bool(forKey: Keys.gitOpensInWindow)
        gitWorkspaceSourceIDs = GitWorkspaceSourceCatalog.decodeStoredSourceIDs(
            defaults.string(forKey: Keys.gitWorkspaceSourceIDs)
        )
        gitStatsScope = GitStatsScope(rawValue: defaults.string(forKey: Keys.gitStatsScope) ?? "") ?? .head
        gitDiffBlockGranularity = GitDiffBlockGranularity(
            rawValue: defaults.string(forKey: Keys.gitDiffBlockGranularity) ?? ""
        ) ?? .fine
        githubEnabled = defaults.bool(forKey: Keys.githubEnabled)
        githubLogin = defaults.string(forKey: Keys.githubLogin) ?? ""
        linuxDoNotificationsEnabled = defaults.bool(forKey: Keys.linuxDoNotificationsEnabled)
        linuxDoLastSeenNotificationID = (defaults.object(forKey: Keys.linuxDoLastSeenNotificationID) as? Int) ?? 0
        linuxDoNotificationDeliveredIDs = (defaults.string(forKey: Keys.linuxDoNotificationDeliveredIDs) ?? "")
            .split(separator: ",")
            .compactMap { Int($0) }
        linuxDoLastLoginUsername = defaults.string(forKey: Keys.linuxDoLastLoginUsername) ?? ""
        linuxDoSelectedFeed = defaults.string(forKey: Keys.linuxDoSelectedFeed) ?? LinuxDoFeed.latest.storedValue
        if let data = defaults.data(forKey: Keys.linuxDoReadingPositions),
           let positions = try? JSONDecoder().decode([Int: LinuxDoReadingPosition].self, from: data) {
            linuxDoReadingPositions = Self.trimLinuxDoReadingPositions(positions)
        } else {
            linuxDoReadingPositions = [:]
        }
        let storedClaudeStatusComponentIDs = (defaults.string(forKey: Keys.claudeStatusVisibleComponentIDs) ?? "")
            .split(separator: ",")
            .map { String($0) }
        claudeStatusVisibleComponentIDs = storedClaudeStatusComponentIDs.isEmpty
            ? ClaudeStatusComponentCatalog.defaultVisibleComponentIDs
            : Set(storedClaudeStatusComponentIDs)
        claudeStatusNotificationsEnabled = defaults.bool(forKey: Keys.claudeStatusNotificationsEnabled)
        claudeStatusLastNotificationFingerprint = defaults.string(forKey: Keys.claudeStatusLastNotificationFingerprint) ?? ""
        claudeDesktopUsageAutoMode = ClaudeDesktopUsageAutoMode(rawValue: defaults.string(forKey: Keys.claudeDesktopUsageAutoMode) ?? "") ?? .visibleOnly
        claudeDesktopUsageTimedCaptureEnabled = (defaults.object(forKey: Keys.claudeDesktopUsageTimedCaptureEnabled) as? Bool) ?? false
        let storedClaudeDesktopUsageTimedInterval = (defaults.object(forKey: Keys.claudeDesktopUsageTimedIntervalMinutes) as? Int) ?? 30
        claudeDesktopUsageTimedIntervalMinutes = min(240, max(5, storedClaudeDesktopUsageTimedInterval))
        let storedClaudeUsageLimitWindowIDs = (defaults.string(forKey: Keys.claudeUsageLimitVisibleWindowIDs) ?? "")
            .split(separator: ",")
            .map { String($0) }
        claudeUsageLimitVisibleWindowIDs = UsageLimitWindowCatalog.normalizedClaudeVisibleWindowIDs(
            Set(storedClaudeUsageLimitWindowIDs)
        )
        let storedOpenAIStatusGroupIDs = (defaults.string(forKey: Keys.openAIStatusVisibleGroupIDs) ?? "")
            .split(separator: ",")
            .map { String($0) }
        openAIStatusVisibleGroupIDs = storedOpenAIStatusGroupIDs.isEmpty
            ? OpenAIStatusGroupCatalog.defaultVisibleGroupIDs
            : Set(storedOpenAIStatusGroupIDs)
        openAIStatusNotificationsEnabled = defaults.bool(forKey: Keys.openAIStatusNotificationsEnabled)
        openAIStatusLastNotificationFingerprint = defaults.string(forKey: Keys.openAIStatusLastNotificationFingerprint) ?? ""
        overlapPalette = OverlapPalette(rawValue: defaults.string(forKey: Keys.overlapPalette) ?? "") ?? .appCohesive
        let sharedLeaderboardPreferences = self.leaderboardSharedStore?.read()
        leaderboardsEnabled = sharedLeaderboardPreferences?.leaderboardsEnabled
            ?? defaults.bool(forKey: Keys.leaderboardsEnabled)
        leaderboardNickname = sharedLeaderboardPreferences?.nickname
            ?? defaults.string(forKey: Keys.leaderboardNickname)
            ?? ""
        leaderboardAvatarSeed = sharedLeaderboardPreferences?.avatarSeed
            ?? defaults.string(forKey: Keys.leaderboardAvatarSeed)
            ?? ""
        leaderboardProfileUserHash = sharedLeaderboardPreferences?.profileUserHash
            ?? defaults.string(forKey: Keys.leaderboardProfileUserHash)
            ?? ""
        leaderboardLastSyncedAt = sharedLeaderboardPreferences?.lastSyncedAt
            ?? defaults.object(forKey: Keys.leaderboardLastSyncedAt) as? Date
        leaderboardLastSyncError = sharedLeaderboardPreferences?.lastSyncError
            ?? defaults.string(forKey: Keys.leaderboardLastSyncError)
            ?? ""
        leaderboardLastSubmittedPeriodKeys = sharedLeaderboardPreferences?.lastSubmittedPeriodKeys
            ?? defaults.stringArray(forKey: Keys.leaderboardLastSubmittedPeriodKeys)
            ?? []
        let hasNewCodingSurfaceAdditions = defaults.object(forKey: Keys.codingSurfaceBundleIDsAdded) != nil
        let hasNewCodingSurfaceRemovals = defaults.object(forKey: Keys.codingSurfaceBundleIDsRemoved) != nil
        let storedCodingSurfaceBundleIDsAdded = defaults.stringArray(forKey: Keys.codingSurfaceBundleIDsAdded)
            ?? defaults.stringArray(forKey: Keys.ideBundleIDsAdded)
            ?? []
        let storedCodingSurfaceBundleIDsRemoved = defaults.stringArray(forKey: Keys.codingSurfaceBundleIDsRemoved)
            ?? defaults.stringArray(forKey: Keys.ideBundleIDsRemoved)
            ?? []
        codingSurfaceBundleIDsAdded = storedCodingSurfaceBundleIDsAdded
        codingSurfaceBundleIDsRemoved = storedCodingSurfaceBundleIDsRemoved
        cliHostBundleIDsAdded = defaults.stringArray(forKey: Keys.cliHostBundleIDsAdded) ?? []
        cliHostBundleIDsRemoved = defaults.stringArray(forKey: Keys.cliHostBundleIDsRemoved) ?? []

        if !hasNewCodingSurfaceAdditions, defaults.object(forKey: Keys.ideBundleIDsAdded) != nil {
            defaults.set(storedCodingSurfaceBundleIDsAdded, forKey: Keys.codingSurfaceBundleIDsAdded)
        }
        if !hasNewCodingSurfaceRemovals, defaults.object(forKey: Keys.ideBundleIDsRemoved) != nil {
            defaults.set(storedCodingSurfaceBundleIDsRemoved, forKey: Keys.codingSurfaceBundleIDsRemoved)
        }

        let storedEnabled = (defaults.string(forKey: Keys.enabledProviders) ?? "")
            .split(separator: ",")
            .compactMap { ProviderKind(rawValue: String($0)) }
        let enabled = storedEnabled.isEmpty ? Set([ProviderKind.claude]) : Set(storedEnabled)
        let remember = (defaults.object(forKey: Keys.rememberSelectedProvider) as? Bool) ?? true
        let storedSelected = ProviderKind(rawValue: defaults.string(forKey: Keys.selectedProvider) ?? "")
        let firstEnabled = ProviderKind.allCases.first(where: enabled.contains) ?? .claude

        enabledProviders = enabled
        rememberSelectedProvider = remember
        if remember, let s = storedSelected, enabled.contains(s) {
            selectedProvider = s
        } else {
            selectedProvider = firstEnabled
        }
        appLanguagePreference.applyToAppleLanguages(defaults: defaults)
        if sharedLeaderboardPreferences == nil {
            persistSharedLeaderboardPreferences()
        }
    }

    func resetNetworkTrafficAutoBreakpoint() {
        networkTrafficAutoBreakpoint = NetworkTrafficLayoutConstants.defaultAutoBreakpoint
    }

    private func persistNotchIslandScreenStyles() {
        let raw = notchIslandScreenStyles.mapValues(\.rawValue)
        guard let data = try? JSONEncoder().encode(raw),
              let json = String(data: data, encoding: .utf8) else {
            defaults.removeObject(forKey: Keys.notchIslandScreenStyles)
            return
        }
        defaults.set(json, forKey: Keys.notchIslandScreenStyles)
    }

    private func persistLinuxDoReadingPositions() {
        guard let data = try? JSONEncoder().encode(linuxDoReadingPositions) else {
            defaults.removeObject(forKey: Keys.linuxDoReadingPositions)
            return
        }
        defaults.set(data, forKey: Keys.linuxDoReadingPositions)
    }

    private func persistSharedLeaderboardPreferences() {
        leaderboardSharedStore?.write(LeaderboardSharedPreferencesSnapshot(
            leaderboardsEnabled: leaderboardsEnabled,
            nickname: leaderboardNickname,
            avatarSeed: leaderboardAvatarSeed,
            profileUserHash: leaderboardProfileUserHash,
            lastSyncedAt: leaderboardLastSyncedAt,
            lastSyncError: leaderboardLastSyncError,
            lastSubmittedPeriodKeys: leaderboardLastSubmittedPeriodKeys
        ))
    }

    private static func defaultLeaderboardSharedStore(for defaults: UserDefaults) -> LeaderboardSharedPreferencesStore? {
        ObjectIdentifier(defaults) == ObjectIdentifier(UserDefaults.standard)
            ? LeaderboardSharedPreferencesStore()
            : nil
    }

    private static func trimLinuxDoReadingPositions(
        _ positions: [Int: LinuxDoReadingPosition],
        limit: Int = 200
    ) -> [Int: LinuxDoReadingPosition] {
        guard positions.count > limit else { return positions }
        return Dictionary(
            uniqueKeysWithValues: positions
                .sorted { lhs, rhs in lhs.value.updatedAt > rhs.value.updatedAt }
                .prefix(limit)
                .map { ($0.key, $0.value) }
        )
    }

    private static func decodeNotchIslandScreenStyles(_ raw: String?) -> [String: NotchIslandScreenStyle] {
        guard let raw,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded.reduce(into: [:]) { result, pair in
            if let style = NotchIslandScreenStyle(rawValue: pair.value) {
                result[pair.key] = style
            }
        }
    }

    private enum Keys {
        static let appLanguagePreference = "appLanguagePreference"
        static let autoRefreshMinutes = "autoRefreshMinutes"
        static let menuBarMetric = "menuBarMetric"
        static let menuBarPeriod = "menuBarPeriod"
        static let includeCacheInTokens = "includeCacheInTokens"
        static let costEstimationMode = "costEstimationMode"
        static let menuBarIncludesCache = "menuBarIncludesCache"
        static let openMainWindowOnLaunch = "openMainWindowOnLaunch"
        static let floatingTabEnabled = "floatingTabEnabled"
        static let cursorCommandOverlayEnabled = "cursorCommandOverlayEnabled"
        static let floatingTabEdge = "floatingTabEdge"
        static let floatingTabAnchor = "floatingTabAnchor"
        static let notchIslandEnabled = "notchIslandEnabled"
        static let notchIslandDisplayMode = "notchIslandDisplayMode"
        static let notchIslandSelectedScreenIDs = "notchIslandSelectedScreenIDs"
        static let notchIslandScreenStyles = "notchIslandScreenStyles"
        static let notchIslandSizePreset = "notchIslandSizePreset"
        static let notchIslandHoverExpansionEnabled = "notchIslandHoverExpansionEnabled"
        static let notchIslandShortcutEnabled = "notchIslandShortcutEnabled"
        static let notchIslandEnabledModules = "notchIslandEnabledModules"
        static let detailPanelBoundaryFalloffEnabled = "detailPanelBoundaryFalloffEnabled"
        static let networkTrafficLayoutMode = "networkTrafficLayoutMode"
        static let networkTrafficAutoBreakpoint = "networkTrafficAutoBreakpoint"
        static let networkAutoEnableSystemProxyOnStart = "networkAutoEnableSystemProxyOnStart"
        static let networkUpstreamProxyMode = "networkUpstreamProxyMode"
        static let networkAskBeforeChainingExistingSystemProxy = "networkAskBeforeChainingExistingSystemProxy"
        static let networkManualUpstreamProxyProtocol = "networkManualUpstreamProxyProtocol"
        static let networkManualUpstreamProxyHost = "networkManualUpstreamProxyHost"
        static let networkManualUpstreamProxyPort = "networkManualUpstreamProxyPort"
        static let networkManualUpstreamProxyPACURL = "networkManualUpstreamProxyPACURL"
        static let networkManualUpstreamProxyUsername = "networkManualUpstreamProxyUsername"
        static let networkManualUpstreamProxyIncludeHosts = "networkManualUpstreamProxyIncludeHosts"
        static let networkManualUpstreamProxyExcludeHosts = "networkManualUpstreamProxyExcludeHosts"
        static let networkManualUpstreamBypassLocalhost = "networkManualUpstreamBypassLocalhost"
        static let networkManualUpstreamDNSOverSOCKS = "networkManualUpstreamDNSOverSOCKS"
        static let sessionsExpandedOnAppOpen = "sessionsExpandedOnAppOpen"
        static let terminalChromeMode = "terminalChromeMode"
        static let terminalBackgroundStyle = "terminalBackgroundStyle"
        static let terminalRuntimeKind = "terminalRuntimeKind"
        static let apiProviderKeyStorageMode = "apiProviderKeyStorageMode"
        static let systemMonitorEnabled = "systemMonitorEnabled"
        static let systemMonitorRefreshRate = "systemMonitorRefreshRate"
        static let systemMonitorVisibleModules = "systemMonitorVisibleModules"
        static let aiActivityAnalysisEnabled = "aiActivityAnalysisEnabled"
        static let gitTrackingEnabled = "gitTrackingEnabled"
        static let gitOpensInWindow = "gitOpensInWindow"
        static let gitWorkspaceSourceIDs = "gitWorkspaceSourceIDs"
        static let gitStatsScope = "gitStatsScope"
        static let gitDiffBlockGranularity = "gitDiffBlockGranularity"
        static let codingSurfaceBundleIDsAdded = "codingSurfaceBundleIDsAdded"
        static let codingSurfaceBundleIDsRemoved = "codingSurfaceBundleIDsRemoved"
        static let cliHostBundleIDsAdded = "cliHostBundleIDsAdded"
        static let cliHostBundleIDsRemoved = "cliHostBundleIDsRemoved"
        static let ideBundleIDsAdded = "ideBundleIDsAdded"
        static let ideBundleIDsRemoved = "ideBundleIDsRemoved"
        static let enabledProviders = "enabledProviders"
        static let selectedProvider = "selectedProvider"
        static let rememberSelectedProvider = "rememberSelectedProvider"
        static let githubEnabled = "githubEnabled"
        static let githubLogin = "githubLogin"
        static let linuxDoNotificationsEnabled = "linuxDoNotificationsEnabled"
        static let linuxDoLastSeenNotificationID = "linuxDoLastSeenNotificationID"
        static let linuxDoNotificationDeliveredIDs = "linuxDoNotificationDeliveredIDs"
        static let linuxDoLastLoginUsername = "linuxDoLastLoginUsername"
        static let linuxDoSelectedFeed = "linuxDoSelectedFeed"
        static let linuxDoReadingPositions = "linuxDoReadingPositions"
        static let claudeStatusVisibleComponentIDs = "claudeStatusVisibleComponentIDs"
        static let claudeStatusNotificationsEnabled = "claudeStatusNotificationsEnabled"
        static let claudeStatusLastNotificationFingerprint = "claudeStatusLastNotificationFingerprint"
        static let claudeDesktopUsageAutoMode = "claudeDesktopUsageAutoMode"
        static let claudeDesktopUsageTimedCaptureEnabled = "claudeDesktopUsageTimedCaptureEnabled"
        static let claudeDesktopUsageTimedIntervalMinutes = "claudeDesktopUsageTimedIntervalMinutes"
        static let claudeUsageLimitVisibleWindowIDs = "claudeUsageLimitVisibleWindowIDs"
        static let openAIStatusVisibleGroupIDs = "openAIStatusVisibleGroupIDs"
        static let openAIStatusNotificationsEnabled = "openAIStatusNotificationsEnabled"
        static let openAIStatusLastNotificationFingerprint = "openAIStatusLastNotificationFingerprint"
        static let overlapPalette = "overlapPalette"
        static let leaderboardsEnabled = "leaderboardsEnabled"
        static let leaderboardNickname = "leaderboardNickname"
        static let leaderboardAvatarSeed = "leaderboardAvatarSeed"
        static let leaderboardProfileUserHash = "leaderboardProfileUserHash"
        static let leaderboardLastSyncedAt = "leaderboardLastSyncedAt"
        static let leaderboardLastSyncError = "leaderboardLastSyncError"
        static let leaderboardLastSubmittedPeriodKeys = "leaderboardLastSubmittedPeriodKeys"
    }
}
