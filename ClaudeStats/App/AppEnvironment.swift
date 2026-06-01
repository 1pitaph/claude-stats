import Foundation
import Observation
import WarpEmbed

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
    let notchIsland = NotchIslandController()
    let warpSessionStore: WarpSessionStore
    /// View models live in the environment so the Settings window and the
    /// individual pages can share state — and so the VMs persist across
    /// main-window open/close cycles (reopening doesn't refire a fetch).
    let dashboard: DashboardViewModel
    let gitActivity: GitActivityViewModel
    let github = GitHubViewModel()
    let linuxDo: LinuxDoStore
    let claudeStatus: ClaudeStatusViewModel
    let openAIStatus: OpenAIStatusViewModel
    let leaderboards: LeaderboardSyncViewModel
    let usageLimits: UsageLimitStore
    let configurationProfiles: ConfigurationProfilesViewModel
    let apiProviders: APIProviderSwitcherViewModel
    let cliEnvironment: CLIEnvironmentViewModel
    let aiConfigs: AIConfigsViewModel
    let skills: SkillsStore
    let configWorkspace: ConfigWorkspaceStore
    #if !CLAUDE_STATS_LITE
    let memory: MemoryStore
    #endif
    let appLLMSettings: AppLLMSettingsStore
    #if !CLAUDE_STATS_LITE
    let memoryModelSettings: MemoryModelSettingsStore
    let chat: ChatStore
    #endif
    let systemMonitor: SystemMonitorViewModel
    let networkDebugger: NetworkDebuggerStore
    let ops: OpsStore
    let dailyReport: DailyReportViewModel

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
        linuxDo: LinuxDoStore? = nil
    ) {
        self.pricing = pricing
        self.preferences = preferences
        self.providerRegistry = providerRegistry
        self.store = store
        let technicalTermRepository = TechnicalTermDictionaryRepository()
        self.technicalTerms = TechnicalTermDictionaryStore(repository: technicalTermRepository)
        #if !CLAUDE_STATS_LITE
        let localAI = LocalAIStore()
        self.localAI = localAI
        #endif
        self.transcriptAnalysis = TranscriptAnalysisStore(
            service: TranscriptAnalysisService(
                dictionaryResolver: { session in
                    await technicalTermRepository.snapshot(for: session)
                },
                embeddingStatusResolver: {
                    #if CLAUDE_STATS_LITE
                    .notConfigured
                    #else
                    await MainActor.run {
                        localAI.selectedEmbeddingStatus
                    }
                    #endif
                }
            )
        )
        self.warpSessionStore = warpSessionStore
        self.cliEnvironment = cliEnvironment
        self.systemMonitor = systemMonitor
        self.networkDebugger = networkDebugger ?? NetworkDebuggerStore(preferences: preferences)
        self.ops = ops
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
        #if !CLAUDE_STATS_LITE
        self.memory = MemoryStore()
        #endif
        self.appLLMSettings = AppLLMSettingsStore()
        #if !CLAUDE_STATS_LITE
        self.memoryModelSettings = MemoryModelSettingsStore()
        self.chat = ChatStore()
        #endif
    }

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
            #if !CLAUDE_STATS_LITE
            Task { [weak self] in
                await self?.syncMemorySourcesFromCurrentState()
            }
            #endif
        }
        leaderboards.start()
        Task {
            await apiProviders.loadIfNeeded(keyStorageMode: preferences.apiProviderKeyStorageMode)
            await configurationProfiles.loadIfNeeded()
            await store.refresh()
            await aiConfigs.reload(sessions: store.sessions)
            await appLLMSettings.loadIfNeeded()
            #if !CLAUDE_STATS_LITE
            await memoryModelSettings.loadIfNeeded()
            await startCodeMemorySidecarFromCurrentModelSettings()
            await memory.syncAvailableSources(sessions: store.sessions, configProjects: aiConfigs.snapshot.projects)
            await drainMemoryCaptureQueueIfAllowed()
            #endif
        }
        claudeStatus.start()
        openAIStatus.start()
        linuxDo.start()
        applyAutoRefreshSetting()
        updater.start()
        floatingStatsPanel.start(environment: self)
        cursorCommandOverlay.start(environment: self)
        if !Self.isRunningUnitTests {
            notchIsland.start(environment: self)
        }
    }

    func applyAutoRefreshSetting() {
        store.startAutoRefresh(every: TimeInterval(preferences.autoRefreshMinutes) * 60)
    }

    func generationEndpoint() throws -> AppLLMGenerationEndpoint {
        #if CLAUDE_STATS_LITE
        try appLLMSettings.generationEndpoint()
        #else
        try appLLMSettings.generationEndpoint(localAI: localAI)
        #endif
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
