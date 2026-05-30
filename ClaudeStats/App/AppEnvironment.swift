import Foundation
import GhosttyEmbed
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
    let localAI: LocalAIStore
    let transcriptAnalysis: TranscriptAnalysisStore
    let updater = UpdaterController()
    let floatingStatsPanel = FloatingStatsPanelController()
    let notchIsland = NotchIslandController()
    let terminalStore: EmbeddedTerminalStore
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
    let memory: MemoryStore
    let memoryModelSettings: MemoryModelSettingsStore
    let chat: ChatStore
    let systemMonitor: SystemMonitorViewModel
    let networkDebugger: NetworkDebuggerStore
    let ops: OpsStore

    init(
        pricing: ModelPricing,
        preferences: Preferences,
        providerRegistry: ProviderRegistry,
        store: SessionStore,
        terminalStore: EmbeddedTerminalStore = EmbeddedTerminalStore(),
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
        self.terminalStore = terminalStore
        self.warpSessionStore = warpSessionStore
        self.cliEnvironment = cliEnvironment
        self.systemMonitor = systemMonitor
        self.networkDebugger = networkDebugger ?? NetworkDebuggerStore(preferences: preferences)
        self.ops = ops
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
        self.memoryModelSettings = MemoryModelSettingsStore()
        self.chat = ChatStore()
    }

    convenience init() {
        self.init(terminalStore: EmbeddedTerminalStore())
    }

    convenience init(terminalStore: EmbeddedTerminalStore) {
        let pricing = ModelPricing.loadDefault()
        let registry = ProviderRegistry(pricing: pricing)
        self.init(
            pricing: pricing,
            preferences: Preferences(),
            providerRegistry: registry,
            store: SessionStore(registry: registry, pricing: pricing),
            terminalStore: terminalStore
        )
    }

    /// Kick off the first scan and the periodic refresh. Call once at launch.
    func start() {
        LegacyFeatureDataCleaner().cleanRemovedFeatureData()
        LaunchAtLogin.enableByDefaultIfNeeded()
        store.onRefresh = { [weak self] in
            guard let self else { return }
            self.leaderboards.scheduleSilentSyncAfterDataRefresh()
            Task { [weak self] in
                await self?.syncMemorySourcesFromCurrentState()
            }
        }
        leaderboards.start()
        Task {
            await apiProviders.loadIfNeeded(keyStorageMode: preferences.apiProviderKeyStorageMode)
            await configurationProfiles.loadIfNeeded()
            await store.refresh()
            await aiConfigs.reload(sessions: store.sessions)
            await memoryModelSettings.loadIfNeeded()
            await startCodeMemorySidecarFromCurrentModelSettings()
            await memory.syncAvailableSources(sessions: store.sessions, configProjects: aiConfigs.snapshot.projects)
            await drainMemoryCaptureQueueIfAllowed()
        }
        claudeStatus.start()
        openAIStatus.start()
        linuxDo.start()
        applyAutoRefreshSetting()
        updater.start()
        floatingStatsPanel.start(environment: self)
        if !Self.isRunningUnitTests {
            notchIsland.start(environment: self)
        }
    }

    func applyAutoRefreshSetting() {
        store.startAutoRefresh(every: TimeInterval(preferences.autoRefreshMinutes) * 60)
    }

    private func syncMemorySourcesFromCurrentState() async {
        await aiConfigs.reload(sessions: store.sessions)
        await memory.syncAvailableSources(sessions: store.sessions, configProjects: aiConfigs.snapshot.projects)
        await drainMemoryCaptureQueueIfAllowed()
    }

    func startCodeMemorySidecarFromCurrentModelSettings() async {
        await memoryModelSettings.loadIfNeeded()
        let launch = memoryModelSettings.sidecarLaunchConfiguration(localAI: localAI)
        await memory.startCodeMemorySidecar(
            localAIEnvironment: launch.legacyLocalAIEnvironment,
            modelRuntimeConfig: launch.runtimeConfig
        )
    }

    private func drainMemoryCaptureQueueIfAllowed() async {
        let mode = memory.captureMode
        guard mode.allowsAutomaticDrain else { return }
        guard memoryModelSettings.hasRunnableAdapters(localAI: localAI) else { return }
        await memory.drainQueuedMemoryCaptures(limit: mode.backgroundDrainLimit)
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
