import Foundation
import ClaudeStatsSync
import Observation
#if !CLAUDE_STATS_LITE
import WarpEmbed
#endif

/// Composition root. Constructs the pricing table, preferences, provider
/// registry, and the shared ``SessionStore``, then hands itself to the view
/// tree via `.environment(_:)`. Views read it with
/// `@Environment(AppEnvironment.self)`.
@MainActor
@Observable
final class AppEnvironment {
    let pricing: ModelPricing
    let preferences: Preferences
    let providerRegistry: ProviderRegistry
    let store: SessionStore
    let technicalTerms: TechnicalTermDictionaryStore
    #if !CLAUDE_STATS_LITE
    let localAI: LocalAIStore
    #endif
    let transcriptAnalysis: TranscriptAnalysisStore
    let updater = UpdaterController()
    let floatingStatsPanel = FloatingStatsPanelController()
    let cursorCommandOverlay = CursorCommandOverlayController()
    var cloudStatsSyncState = CloudStatsSnapshotSyncState()
    @ObservationIgnored private let cloudStatsSync: CloudStatsSyncService
    @ObservationIgnored private let cloudStatsEntitlementChecker: @Sendable (String) -> Bool
    @ObservationIgnored private var cloudStatsPublishTask: Task<Void, Never>?
    #if !CLAUDE_STATS_LITE
    let notchIsland = NotchIslandController()
    let warpSessionStore: WarpSessionStore
    #endif
    /// View models live in the environment so the Settings window and the
    /// individual pages can share state — and so the VMs persist across
    /// main-window open/close cycles (reopening doesn't refire a fetch).
    let dashboard: DashboardViewModel
    let gitActivity: GitActivityViewModel
    let github = GitHubViewModel()
    #if !CLAUDE_STATS_LITE
    let linuxDo: LinuxDoStore
    #endif
    let claudeStatus: ClaudeStatusViewModel
    let openAIStatus: OpenAIStatusViewModel
    let leaderboards: LeaderboardSyncViewModel
    let usageLimits: UsageLimitStore
    #if !CLAUDE_STATS_LITE
    let configurationProfiles: ConfigurationProfilesViewModel
    let apiProviders: APIProviderSwitcherViewModel
    let cliEnvironment: CLIEnvironmentViewModel
    let aiConfigs: AIConfigsViewModel
    let skills: SkillsStore
    let configWorkspace: ConfigWorkspaceStore
    #endif
    #if !CLAUDE_STATS_LITE
    let memory: MemoryStore
    #endif
    let appLLMSettings: AppLLMSettingsStore
    #if !CLAUDE_STATS_LITE
    let memoryModelSettings: MemoryModelSettingsStore
    let chat: ChatStore
    #endif
    let systemMonitor: SystemMonitorViewModel
    #if !CLAUDE_STATS_LITE
    let networkDebugger: NetworkDebuggerStore
    let ops: OpsStore
    let track: TrackStore
    #endif
    let dailyReport: DailyReportViewModel

    #if CLAUDE_STATS_LITE
    init(
        pricing: ModelPricing,
        preferences: Preferences,
        providerRegistry: ProviderRegistry,
        store: SessionStore,
        usageLimits: UsageLimitStore? = nil,
        systemMonitor: SystemMonitorViewModel = SystemMonitorViewModel(),
        cloudStatsSync: CloudStatsSyncService = CloudStatsSyncService(),
        cloudStatsEntitlementChecker: @escaping @Sendable (String) -> Bool = CloudKitRuntimeEntitlements.hasCloudKitAccess
    ) {
        self.pricing = pricing
        self.preferences = preferences
        self.providerRegistry = providerRegistry
        self.store = store
        self.cloudStatsSync = cloudStatsSync
        self.cloudStatsEntitlementChecker = cloudStatsEntitlementChecker
        let technicalTermRepository = TechnicalTermDictionaryRepository()
        self.technicalTerms = TechnicalTermDictionaryStore(repository: technicalTermRepository)
        self.transcriptAnalysis = TranscriptAnalysisStore(
            service: TranscriptAnalysisService(
                dictionaryResolver: { session in
                    await technicalTermRepository.snapshot(for: session)
                },
                embeddingStatusResolver: {
                    .notConfigured
                }
            )
        )
        self.systemMonitor = systemMonitor
        self.dailyReport = DailyReportViewModel()
        self.dashboard = DashboardViewModel(pricing: pricing)
        self.gitActivity = GitActivityViewModel()
        self.claudeStatus = ClaudeStatusViewModel(preferences: preferences)
        self.openAIStatus = OpenAIStatusViewModel(preferences: preferences)
        self.leaderboards = LeaderboardSyncViewModel(
            preferences: preferences,
            store: store,
            remoteNotificationRegistrar: Self.isRunningUnitTests ? nil : AppKitLeaderboardRemoteNotificationRegistrar()
        )
        self.usageLimits = usageLimits ?? UsageLimitStore(registry: providerRegistry)
        self.appLLMSettings = AppLLMSettingsStore()
    }
    #else
    init(
        pricing: ModelPricing,
        preferences: Preferences,
        providerRegistry: ProviderRegistry,
        store: SessionStore,
        warpSessionStore: WarpSessionStore = WarpSessionStore(),
        usageLimits: UsageLimitStore? = nil,
        cliEnvironment: CLIEnvironmentViewModel = CLIEnvironmentViewModel(),
        systemMonitor: SystemMonitorViewModel = SystemMonitorViewModel(),
        networkDebugger: NetworkDebuggerStore? = nil,
        ops: OpsStore = OpsStore(),
        linuxDo: LinuxDoStore? = nil,
        cloudStatsSync: CloudStatsSyncService = CloudStatsSyncService(),
        cloudStatsEntitlementChecker: @escaping @Sendable (String) -> Bool = CloudKitRuntimeEntitlements.hasCloudKitAccess
    ) {
        self.pricing = pricing
        self.preferences = preferences
        self.providerRegistry = providerRegistry
        self.store = store
        self.cloudStatsSync = cloudStatsSync
        self.cloudStatsEntitlementChecker = cloudStatsEntitlementChecker
        let technicalTermRepository = TechnicalTermDictionaryRepository()
        self.technicalTerms = TechnicalTermDictionaryStore(repository: technicalTermRepository)
        let localAI = LocalAIStore()
        self.localAI = localAI
        self.transcriptAnalysis = TranscriptAnalysisStore(
            service: TranscriptAnalysisService(
                dictionaryResolver: { session in
                    await technicalTermRepository.snapshot(for: session)
                },
                embeddingStatusResolver: {
                    await MainActor.run {
                        localAI.selectedEmbeddingStatus
                    }
                }
            )
        )
        self.warpSessionStore = warpSessionStore
        self.cliEnvironment = cliEnvironment
        self.systemMonitor = systemMonitor
        self.networkDebugger = networkDebugger ?? NetworkDebuggerStore(preferences: preferences)
        self.ops = ops
        self.track = TrackStore()
        self.dailyReport = DailyReportViewModel()
        let linuxDoCredentials: any LinuxDoCredentialStoring = Self.isRunningUnitTests
            ? InMemoryLinuxDoCredentialStore()
            : LinuxDoKeychainStore.shared
        self.linuxDo = linuxDo ?? LinuxDoStore(preferences: preferences, credentials: linuxDoCredentials)
        self.dashboard = DashboardViewModel(pricing: pricing)
        self.gitActivity = GitActivityViewModel()
        self.claudeStatus = ClaudeStatusViewModel(preferences: preferences)
        self.openAIStatus = OpenAIStatusViewModel(preferences: preferences)
        self.leaderboards = LeaderboardSyncViewModel(
            preferences: preferences,
            store: store,
            remoteNotificationRegistrar: Self.isRunningUnitTests ? nil : AppKitLeaderboardRemoteNotificationRegistrar()
        )
        self.usageLimits = usageLimits ?? UsageLimitStore(registry: providerRegistry)
        self.configurationProfiles = ConfigurationProfilesViewModel(registry: providerRegistry)
        let apiProviders = APIProviderSwitcherViewModel()
        let aiConfigs = AIConfigsViewModel(scanner: AIConfigScanner(registry: providerRegistry))
        let skills = SkillsStore()
        self.apiProviders = apiProviders
        self.aiConfigs = aiConfigs
        self.skills = skills
        self.configWorkspace = ConfigWorkspaceStore(
            apiProviders: apiProviders,
            cliEnvironment: cliEnvironment,
            aiConfigs: aiConfigs,
            skills: skills,
            configurationProfiles: self.configurationProfiles
        )
        self.memory = MemoryStore()
        self.appLLMSettings = AppLLMSettingsStore()
        self.memoryModelSettings = MemoryModelSettingsStore()
        self.chat = ChatStore()
    }
    #endif

    convenience init() {
        let pricing = ModelPricing.loadDefault()
        let registry = ProviderRegistry(pricing: pricing)
        self.init(
            pricing: pricing,
            preferences: Preferences(),
            providerRegistry: registry,
            store: SessionStore(registry: registry, pricing: pricing)
        )
    }

    /// Kick off the first scan and the periodic refresh. Call once at launch.
    func start() {
        LegacyFeatureDataCleaner().cleanRemovedFeatureData()
        LaunchAtLogin.enableByDefaultIfNeeded()
        store.onRefresh = { [weak self] in
            guard let self else { return }
            self.leaderboards.scheduleSilentSyncAfterDataRefresh()
            self.scheduleCloudStatsSnapshotPublish(reason: "data refresh")
            #if !CLAUDE_STATS_LITE
            Task { [weak self] in
                await self?.syncMemorySourcesFromCurrentState()
                await self?.refreshTrack()
            }
            #endif
        }
        claudeStatus.onRefresh = { [weak self] in
            self?.scheduleCloudStatsSnapshotPublish(reason: "Claude status refresh")
        }
        openAIStatus.onRefresh = { [weak self] in
            self?.scheduleCloudStatsSnapshotPublish(reason: "OpenAI status refresh")
        }
        leaderboards.start()
        Task {
            #if !CLAUDE_STATS_LITE
            await apiProviders.loadIfNeeded(keyStorageMode: preferences.apiProviderKeyStorageMode)
            await configurationProfiles.loadIfNeeded()
            #endif
            await store.refresh()
            await usageLimits.refreshSupportedProviders()
            await usageLimits.refreshForecasts(sessions: store.sessions)
            #if !CLAUDE_STATS_LITE
            await aiConfigs.reload(sessions: store.sessions)
            #endif
            await appLLMSettings.loadIfNeeded()
            #if !CLAUDE_STATS_LITE
            await memoryModelSettings.loadIfNeeded()
            await startCodeMemorySidecarFromCurrentModelSettings()
            await memory.syncAvailableSources(sessions: store.sessions, configProjects: aiConfigs.snapshot.projects)
            await refreshTrack()
            await drainMemoryCaptureQueueIfAllowed()
            #endif
        }
        claudeStatus.start()
        openAIStatus.start()
        #if !CLAUDE_STATS_LITE
        linuxDo.start()
        #endif
        applyAutoRefreshSetting()
        updater.start()
        floatingStatsPanel.start(environment: self)
        cursorCommandOverlay.start(environment: self)
        #if !CLAUDE_STATS_LITE
        if !Self.isRunningUnitTests {
            notchIsland.start(environment: self)
        }
        #endif
    }

    func applyAutoRefreshSetting() {
        store.startAutoRefresh(every: TimeInterval(preferences.autoRefreshMinutes) * 60)
    }

    #if !CLAUDE_STATS_LITE
    func refreshTrack() async {
        await track.refresh(sessions: store.sessions) { [weak self] session in
            guard let self else { return [] }
            return await self.store.executedCommands(for: session)
        } trackEventLoader: { [weak self] session in
            guard let self else { return [] }
            return await self.store.trackEvents(for: session)
        }
    }
    #endif

    func generationEndpoint() throws -> AppLLMGenerationEndpoint {
        #if CLAUDE_STATS_LITE
        try appLLMSettings.generationEndpoint()
        #else
        try appLLMSettings.generationEndpoint(localAI: localAI)
        #endif
    }

    func refreshCloudStatsSnapshotSyncStatus() async {
        let hasEntitlement = updateCloudStatsEntitlementState(checkedAt: .now)
        guard hasEntitlement else { return }

        cloudStatsSyncState.phase = .checkingAccount
        let status = await cloudStatsSync.accountStatus()
        cloudStatsSyncState.accountStatus = status
        cloudStatsSyncState.lastCheckedAt = .now
        switch status {
        case .available:
            cloudStatsSyncState.phase = cloudStatsSyncState.lastPublishedAt == nil ? .ready : .published
        case .unknown:
            cloudStatsSyncState.phase = .ready
        case .noAccount, .restricted, .unavailable:
            cloudStatsSyncState.phase = .unavailable
        }
    }

    func publishCloudStatsSnapshotNow() async {
        await publishCloudStatsSnapshot(reason: "manual publish", refreshAccount: true)
    }

    private func scheduleCloudStatsSnapshotPublish(reason: String) {
        guard hasCloudStatsCloudKitAccess else {
            updateCloudStatsEntitlementState(checkedAt: .now)
            Log.app.debug("Skipping iCloud stats snapshot publish for \(reason, privacy: .public): CloudKit entitlement is unavailable")
            return
        }
        cloudStatsPublishTask?.cancel()
        cloudStatsPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await self?.publishCloudStatsSnapshot(reason: reason)
        }
    }

    private func publishCloudStatsSnapshot(reason: String, refreshAccount: Bool = false) async {
        guard updateCloudStatsEntitlementState(checkedAt: .now) else {
            Log.app.debug("Skipping iCloud stats snapshot publish for \(reason, privacy: .public): CloudKit entitlement is unavailable")
            return
        }

        if refreshAccount || cloudStatsSyncState.accountStatus == .unknown {
            cloudStatsSyncState.phase = .checkingAccount
            let status = await cloudStatsSync.accountStatus()
            cloudStatsSyncState.accountStatus = status
            cloudStatsSyncState.lastCheckedAt = .now
            guard status == .available || status == .unknown else {
                cloudStatsSyncState.phase = .unavailable
                cloudStatsSyncState.lastError = nil
                Log.app.debug("Skipping iCloud stats snapshot publish for \(reason, privacy: .public): \(status.displayText, privacy: .public)")
                return
            }
        }

        await refreshStatusesForCloudStatsPublish()
        let snapshot = StatsSnapshotBuilder.make(environment: self)
        cloudStatsSyncState.phase = .publishing
        cloudStatsSyncState.lastPublishReason = reason
        cloudStatsSyncState.lastSnapshotGeneratedAt = snapshot.generatedAt
        cloudStatsSyncState.lastError = nil
        do {
            try await cloudStatsSync.publish(snapshot: snapshot)
            cloudStatsSyncState.phase = .published
            cloudStatsSyncState.lastPublishedAt = .now
            Log.app.info("Published iCloud stats snapshot for \(reason, privacy: .public)")
        } catch {
            cloudStatsSyncState.phase = .failed
            cloudStatsSyncState.lastError = error.localizedDescription
            Log.app.error("iCloud stats snapshot publish failed for \(reason, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshStatusesForCloudStatsPublish() async {
        await claudeStatus.refreshIfNeeded()
        await openAIStatus.refreshIfNeeded()
    }

    private var hasCloudStatsCloudKitAccess: Bool {
        cloudStatsEntitlementChecker(CloudStatsCloudKitClient.defaultContainerIdentifier)
    }

    @discardableResult
    private func updateCloudStatsEntitlementState(checkedAt: Date) -> Bool {
        let hasAccess = hasCloudStatsCloudKitAccess
        cloudStatsSyncState.entitlementAvailable = hasAccess
        cloudStatsSyncState.lastCheckedAt = checkedAt
        if !hasAccess {
            cloudStatsSyncState.phase = .missingEntitlement
            cloudStatsSyncState.accountStatus = .unknown
        }
        return hasAccess
    }

    #if !CLAUDE_STATS_LITE
    private func syncMemorySourcesFromCurrentState() async {
        await aiConfigs.reload(sessions: store.sessions)
        await memory.syncAvailableSources(sessions: store.sessions, configProjects: aiConfigs.snapshot.projects)
        await drainMemoryCaptureQueueIfAllowed()
    }

    func startCodeMemorySidecarFromCurrentModelSettings() async {
        await appLLMSettings.loadIfNeeded()
        await memoryModelSettings.loadIfNeeded()
        let launch = memoryModelSettings.sidecarLaunchConfiguration(
            appLLMSettings: appLLMSettings,
            localAI: localAI,
            diagnosticsRetentionDays: memory.diagnosticsRetentionDays
        )
        await memory.startCodeMemorySidecar(
            localAIEnvironment: launch.legacyLocalAIEnvironment,
            modelRuntimeConfig: launch.runtimeConfig,
            sessions: store.sessions
        )
    }

    private func drainMemoryCaptureQueueIfAllowed() async {
        let mode = memory.captureMode
        guard mode.allowsAutomaticDrain else { return }
        guard memoryModelSettings.hasRunnableAdapters(appLLMSettings: appLLMSettings, localAI: localAI) else { return }
        await memory.drainQueuedMemoryCaptures(limit: mode.backgroundDrainLimit)
    }
    #endif

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
