import AppKit
import SwiftUI

/// Top-level page shown in the main window's detail column. Settings live in
/// their own main-window mode, not as a `MainPage`.
enum MainPage: String, CaseIterable, Identifiable, Sendable {
    case dashboard, linuxDo, usage, leaderboards, activity, git, system, terminal
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: L10n.string("main_page.dashboard", defaultValue: "Dashboard")
        case .linuxDo: "LinuxDo"
        case .usage: L10n.string("main_page.usage", defaultValue: "Usage")
        case .leaderboards: L10n.string("main_page.leaderboards", defaultValue: "Leaderboards")
        case .activity: L10n.string("main_page.activity", defaultValue: "Activity")
        case .git: L10n.string("main_page.git", defaultValue: "Git")
        case .system: L10n.string("main_page.system", defaultValue: "System")
        case .terminal: L10n.string("main_page.terminal", defaultValue: "Terminal")
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .linuxDo: "globe.asia.australia"
        case .usage: "chart.bar.xaxis"
        case .leaderboards: "trophy"
        case .activity: "waveform"
        case .git: "arrow.triangle.branch"
        case .system: "cpu"
        case .terminal: "terminal"
        }
    }

    var assetName: String? {
        switch self {
        case .linuxDo: "LinuxDoLogo"
        default: nil
        }
    }
}

extension Notification.Name {
    /// Posted by the menu-bar Settings button to ask the main window to enter
    /// settings mode (opening the window first if needed).
    static let openSettingsInMainWindow = Notification.Name("ClaudeStats.openSettingsInMainWindow")
}

/// The main app window: a vibrancy-backed sidebar with a floating rounded
/// detail "card" sitting visually above it (Codex-style shell). The window
/// holds an activation-policy reference for its lifetime so the app shows a
/// Dock icon while it's open (see ``DockVisibilityCoordinator``).
struct MainWindowView: View {
    static let windowID = "main-window"

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("mainWindow.selectedPage") private var pageRaw: String = MainPage.dashboard.rawValue
    @SceneStorage("mainWindow.sidebarVisible") private var sidebarVisible: Bool = true
    @SceneStorage("mainWindow.mode") private var modeRaw: String = MainWindowMode.app.rawValue
    @SceneStorage("mainWindow.settingsSection") private var settingsSectionRaw: String = SettingsSection.general.rawValue
    @SceneStorage("mainWindow.configSection") private var configSectionRaw: String = ""
    @SceneStorage("mainWindow.configsSection") private var configFilesSectionRaw: String = AIConfigsSection.overview.rawValue
    @SceneStorage("mainWindow.configsSearch") private var configsSearchText: String = ""
    @SceneStorage("mainWindow.configsProjectID") private var configsProjectIDRaw: String = ""
    @SceneStorage("mainWindow.configsDocumentID") private var configsDocumentIDRaw: String = ""
    @SceneStorage("mainWindow.memorySection") private var memorySectionRaw: String = MemoryWorkspaceSection.search.rawValue
    @SceneStorage("mainWindow.memoryAIDestination") private var memoryAIDestinationRaw: String = MemoryAIDestination.overviewRawValue
    @SceneStorage("mainWindow.networkSection") private var networkSectionRaw: String = NetworkSection.traffic.rawValue
    @SceneStorage("mainWindow.opsSection") private var opsSectionRaw: String = OpsSection.ports.rawValue
    @SceneStorage("mainWindow.sessionsDestination") private var legacySessionsDestinationRaw: String = ""
    @State private var page: MainPage = .dashboard
    @State private var toggleHovering = false
    @State private var trafficLights = TrafficLightPositioner()
    @State private var linuxDoWebLoginPresented = false
    @State private var linuxDoSignInEnabled = true

    private var availablePages: [MainPage] {
        var pages: [MainPage] = [.dashboard, .usage, .leaderboards]
        if env.preferences.aiActivityAnalysisEnabled { pages.append(.activity) }
        if env.preferences.gitTrackingEnabled { pages.append(.git) }
        if env.preferences.systemMonitorEnabled { pages.append(.system) }
        pages.append(.terminal)
        return pages
    }

    private var memoryAIDestination: MemoryAIDestination {
        MemoryAIDestination(rawValue: memoryAIDestinationRaw)
    }

    private var mode: MainWindowMode {
        MainWindowMode(rawValue: modeRaw) ?? .app
    }

    private var settingsSection: SettingsSection {
        SettingsSection(rawValue: settingsSectionRaw) ?? .general
    }

    private var networkSection: NetworkSection {
        NetworkSection(storedRawValue: networkSectionRaw)
    }

    private var opsSection: OpsSection {
        OpsSection(storedRawValue: opsSectionRaw)
    }

    private var settingsSectionBinding: Binding<SettingsSection> {
        Binding(
            get: { settingsSection },
            set: { settingsSectionRaw = $0.rawValue }
        )
    }

    private var configsProjectIDBinding: Binding<String> {
        Binding(
            get: { configsProjectIDRaw },
            set: { configsProjectIDRaw = $0 }
        )
    }

    private var configsDocumentIDBinding: Binding<String> {
        Binding(
            get: { configsDocumentIDRaw },
            set: { configsDocumentIDRaw = $0 }
        )
    }

    private var networkSectionBinding: Binding<NetworkSection> {
        Binding(
            get: { networkSection },
            set: { networkSectionRaw = $0.rawValue }
        )
    }

    private var opsSectionBinding: Binding<OpsSection> {
        Binding(
            get: { opsSection },
            set: { opsSectionRaw = $0.rawValue }
        )
    }

    private var memoryAIDestinationBinding: Binding<MemoryAIDestination> {
        Binding(
            get: { memoryAIDestination },
            set: { memoryAIDestinationRaw = $0.rawValue }
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)

            MainWindowModeShell(
                mode: mode,
                sidebarVisible: sidebarVisible,
                boundaryFalloffEnabled: env.preferences.detailPanelBoundaryFalloffEnabled
            ) {
                SidebarColumn(
                    page: $page,
                    availablePages: availablePages,
                    isLinuxDoActive: mode == .linuxDo,
                    isConfigsActive: mode == .configs,
                    isMemoryActive: mode == .memory,
                    onOpenSettings: openSettings,
                    onOpenLinuxDo: openLinuxDo,
                    onOpenConfigs: openConfigs,
                    onOpenMemory: openMemory,
                    onOpenNetwork: openNetwork,
                    onOpenOps: openOps
                )
            } linuxDoSidebar: {
                LinuxDoSidebarColumn(
                    store: env.linuxDo,
                    signInEnabled: linuxDoSignInEnabled,
                    onExit: closeLinuxDo,
                    onSignIn: openLinuxDoSignIn
                )
            } configsSidebar: {
                ConfigWorkspaceSidebar(store: env.configWorkspace, onExit: closeConfigs)
            } memorySidebar: {
                MemoryWorkspaceSidebar(store: env.memory, onExit: closeMemory)
            } settingsSidebar: {
                SettingsSidebarColumn(section: settingsSectionBinding, onExit: closeSettings)
            } networkSidebar: {
                NetworkSidebarColumn(store: env.networkDebugger, section: networkSectionBinding, onExit: closeNetwork)
            } opsSidebar: {
                OpsSidebarColumn(section: opsSectionBinding, onExit: closeOps)
            } appDetail: {
                detail
            } linuxDoDetail: {
                LinuxDoWorkspaceView(store: env.linuxDo)
            } configsDetail: {
                ConfigWorkspaceView(
                    store: env.configWorkspace,
                    selectedProjectID: configsProjectIDBinding,
                    selectedDocumentID: configsDocumentIDBinding
                )
            } memoryDetail: {
                MemoryWorkspaceView(store: env.memory, aiDestination: memoryAIDestinationBinding)
            } settingsDetail: {
                SettingsDetailView(section: settingsSection, onSelectSection: selectSettingsSection)
            } networkDetail: {
                NetworkDetailView(section: networkSection)
            } opsDetail: {
                OpsDetailView(store: env.ops, section: opsSection)
            }
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { clearTextFocus() }
            }

            if mode == .app || mode == .linuxDo || mode == .configs || mode == .memory || mode == .network || mode == .ops {
                sidebarToggle
                    .padding(.leading, 81)
                    .padding(.top, 11)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .background(WindowAccessor { window in
            trafficLights.attach(to: window)
        })
        .onAppear {
            restoreConfigWorkspaceState()
            restoreMemoryWorkspaceState()
            normalizeNavigationState()
            if mode == .memory { clearInvalidMemoryAIDestination() }
            DockVisibilityCoordinator.shared.acquire()
            Log.app.info("Main window opened on page \(page.rawValue, privacy: .public)")
        }
        .onDisappear {
            DockVisibilityCoordinator.shared.release()
            Log.app.info("Main window closed")
        }
        .sheet(isPresented: $linuxDoWebLoginPresented) {
            LinuxDoWebLoginSheet(store: env.linuxDo, isPresented: $linuxDoWebLoginPresented)
        }
        .onChange(of: page) { _, new in
            guard availablePages.contains(new) else {
                page = .dashboard
                pageRaw = MainPage.dashboard.rawValue
                return
            }
            pageRaw = new.rawValue
        }
        .onChange(of: env.configWorkspace.section) { _, new in
            configSectionRaw = new.rawValue
        }
        .onChange(of: env.configWorkspace.filesSection) { _, new in
            configFilesSectionRaw = new.rawValue
        }
        .onChange(of: env.configWorkspace.filesSearchText) { _, new in
            configsSearchText = new
        }
        .onChange(of: env.memory.section) { _, new in
            memorySectionRaw = new.rawValue
        }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in
            if mode == .memory { clearInvalidMemoryAIDestination() }
        }
        .onChange(of: env.preferences.selectedProvider) { _, _ in
            if mode == .memory { clearInvalidMemoryAIDestination() }
        }
        .onChange(of: env.preferences.aiActivityAnalysisEnabled) { _, on in
            if !on && page == .activity { page = .dashboard }
        }
        .onChange(of: env.preferences.gitTrackingEnabled) { _, on in
            if !on && page == .git { page = .dashboard }
        }
        .onChange(of: env.preferences.systemMonitorEnabled) { _, on in
            if !on && page == .system { page = .dashboard }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsInMainWindow)) { notification in
            openSettings(section: notification.object as? SettingsSection)
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectMainWindowDestinationFromFloatingStats)) { notification in
            guard let destination = notification.object as? FloatingStatsMainWindowDestination else { return }
            openFloatingStatsDestination(destination)
        }
    }

    // MARK: - Sidebar toggle

    private var sidebarToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { sidebarVisible.toggle() }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(toggleHovering ? .primary : Color.stxMuted)
                .frame(width: 24, height: 22)
                .background {
                    if toggleHovering {
                        RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { toggleHovering = $0 }
        .help(sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
        .keyboardShortcut("s", modifiers: [.command, .control])
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch page {
        case .dashboard:
            DashboardView()
        case .linuxDo:
            DashboardView()
        case .usage:
            MainUsageView()
        case .leaderboards:
            LeaderboardsView()
        case .activity:
            MainActivityView()
        case .git:
            MainGitActivityView()
        case .system:
            MainSystemMonitorView()
        case .terminal:
            TerminalWorkspaceView(store: env.terminalStore)
        }
    }

    private func clearTextFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func openSettings() {
        openSettings(section: nil)
    }

    private func openSettings(section: SettingsSection?) {
        if let section {
            settingsSectionRaw = section.rawValue
        }
        transition(to: .settings)
    }

    private func selectSettingsSection(_ section: SettingsSection) {
        settingsSectionRaw = section.rawValue
    }

    private func openLinuxDo() {
        linuxDoSignInEnabled = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            page = availablePages.contains(page) ? page : .dashboard
            pageRaw = page.rawValue
            sidebarVisible = true
            Log.app.info("Opening LinuxDo mode")
            transition(to: .linuxDo)
            try? await Task.sleep(for: .seconds(2))
            guard mode == .linuxDo else { return }
            linuxDoSignInEnabled = true
        }
    }

    private func openLinuxDoSignIn() {
        guard linuxDoSignInEnabled else {
            Log.app.info("Ignoring LinuxDo sign-in trigger during mode transition")
            return
        }
        Log.app.info("Opening LinuxDo web sign-in sheet")
        linuxDoWebLoginPresented = true
    }

    private func openConfigs() {
        transition(to: .configs)
    }

    private func openMemory() {
        transition(to: .memory)
    }

    private func openNetwork() {
        transition(to: .network)
    }

    private func openOps() {
        transition(to: .ops)
    }

    private func closeSettings() {
        transition(to: .app)
    }

    private func closeLinuxDo() {
        Log.app.info("Closing LinuxDo mode")
        transition(to: .app)
    }

    private func closeConfigs() {
        transition(to: .app)
    }

    private func closeMemory() {
        transition(to: .app)
    }

    private func closeNetwork() {
        transition(to: .app)
    }

    private func closeOps() {
        transition(to: .app)
    }

    private func openFloatingStatsDestination(_ destination: FloatingStatsMainWindowDestination) {
        switch destination {
        case .page(let nextPage):
            page = availablePages.contains(nextPage) ? nextPage : .dashboard
            transition(to: .app)
        case .network:
            transition(to: .network)
        case .linuxDoTopic(let route):
            env.linuxDo.openTopic(route)
            openLinuxDo()
        }
    }

    private func clearInvalidMemoryAIDestination() {
        switch memoryAIDestination {
        case .session(let id):
            let sessions = env.store.sessions(for: env.preferences.selectedProvider)
            if !sessions.contains(where: { $0.id == id }) {
                memoryAIDestinationRaw = MemoryAIDestination.overviewRawValue
            }
        case .indexedRecord(let id):
            if !env.memory.aiRecords.contains(where: { $0.id == id }) {
                memoryAIDestinationRaw = MemoryAIDestination.overviewRawValue
            }
        case .overview, .analysis:
            break
        }
    }

    private func transition(to nextMode: MainWindowMode) {
        clearTextFocus()
        guard mode != nextMode else { return }

        if reduceMotion {
            modeRaw = nextMode.rawValue
        } else {
            withAnimation(MainWindowMotion.modeSwitchAnimation) {
                modeRaw = nextMode.rawValue
            }
        }
    }

    private func normalizeNavigationState() {
        if modeRaw == "sessions" {
            modeRaw = MainWindowMode.memory.rawValue
            memorySectionRaw = MemoryWorkspaceSection.aiSessions.rawValue
            if memoryAIDestinationRaw == MemoryAIDestination.overviewRawValue,
               !legacySessionsDestinationRaw.isEmpty {
                memoryAIDestinationRaw = legacySessionsDestinationRaw
            }
            sidebarVisible = true
        }

        if MainWindowMode(rawValue: modeRaw) == nil {
            modeRaw = MainWindowMode.app.rawValue
        }

        if env.configWorkspace.migrateLegacyMainPage(rawValue: pageRaw) {
            configSectionRaw = env.configWorkspace.section.rawValue
            configFilesSectionRaw = env.configWorkspace.filesSection.rawValue
            page = .dashboard
            pageRaw = MainPage.dashboard.rawValue
            modeRaw = MainWindowMode.configs.rawValue
            sidebarVisible = true
            return
        }

        let storedPage = MainPage(rawValue: pageRaw) ?? .dashboard
        if availablePages.contains(storedPage) {
            page = storedPage
            pageRaw = storedPage.rawValue
        } else {
            page = .dashboard
            pageRaw = MainPage.dashboard.rawValue
        }

        if mode == .linuxDo {
            sidebarVisible = true
        }
    }

    private func restoreConfigWorkspaceState() {
        if let section = ConfigWorkspaceSection(rawValue: configSectionRaw), !configSectionRaw.isEmpty {
            env.configWorkspace.section = section
        } else {
            let legacySection = AIConfigsSection(rawValue: configFilesSectionRaw) ?? .overview
            switch legacySection {
            case .overview:
                env.configWorkspace.section = .overview
            case .diagnostics:
                env.configWorkspace.section = .diagnostics
            case .instructions, .provider, .plans, .plugins:
                env.configWorkspace.section = .files
            }
        }

        env.configWorkspace.filesSection = ConfigFilesSection(storedRawValue: configFilesSectionRaw)
        env.configWorkspace.filesSearchText = configsSearchText
        configSectionRaw = env.configWorkspace.section.rawValue
        configFilesSectionRaw = env.configWorkspace.filesSection.rawValue
    }

    private func restoreMemoryWorkspaceState() {
        env.memory.section = MemoryWorkspaceSection(rawValue: memorySectionRaw) ?? .search
        memorySectionRaw = env.memory.section.rawValue
    }
}

#if DEBUG
#Preview("Main window") {
    MainWindowView()
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
}
#endif
