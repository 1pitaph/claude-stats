import AppKit
import SwiftUI

/// Top-level page shown in the main window's detail column. Settings live in
/// their own main-window mode, not as a `MainPage`.
enum MainPage: String, CaseIterable, Identifiable, Sendable {
    case dashboard, linuxDo, usage, leaderboards, activity, dailyReport, gantt, git, system, terminal
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: L10n.string("main_page.dashboard", defaultValue: "Dashboard")
        case .linuxDo: "LinuxDo"
        case .usage: L10n.string("main_page.usage", defaultValue: "Usage")
        case .leaderboards: L10n.string("main_page.leaderboards", defaultValue: "Leaderboards")
        case .activity: L10n.string("main_page.activity", defaultValue: "Activity")
        case .dailyReport: L10n.string("main_page.daily_report", defaultValue: "Daily Report")
        case .gantt: L10n.string("main_page.gantt", defaultValue: "Gantt")
        case .git: L10n.string("main_page.git", defaultValue: "Git")
        case .system: L10n.string("main_page.system", defaultValue: "System")
        case .terminal: L10n.string("main_page.terminal", defaultValue: "Terminal")
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: AppIcon.Workspace.dashboard
        case .linuxDo: AppIcon.Workspace.linuxDo
        case .usage: AppIcon.Workspace.usage
        case .leaderboards: AppIcon.Workspace.leaderboards
        case .activity: AppIcon.Workspace.activity
        case .dailyReport: AppIcon.Workspace.dailyReport
        case .gantt: AppIcon.Workspace.gantt
        case .git: AppIcon.Workspace.git
        case .system: AppIcon.Workspace.system
        case .terminal: AppIcon.Workspace.terminal
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
    @SceneStorage("mainWindow.gitSelection") private var gitSelectionRaw: String = GitWorkspaceSelection.all.rawValue
    #if !CLAUDE_STATS_LITE
    @SceneStorage("mainWindow.configSection") private var configSectionRaw: String = ""
    @SceneStorage("mainWindow.configsSection") private var configFilesSectionRaw: String = AIConfigsSection.overview.rawValue
    @SceneStorage("mainWindow.configsSearch") private var configsSearchText: String = ""
    @SceneStorage("mainWindow.configsProjectID") private var configsProjectIDRaw: String = ""
    @SceneStorage("mainWindow.configsDocumentID") private var configsDocumentIDRaw: String = ""
    @SceneStorage("mainWindow.sessionsDestination") private var sessionsDestinationRaw: String = SessionsDestination.overviewRawValue
    @SceneStorage("mainWindow.memorySection") private var memorySectionRaw: String = MemoryWorkspaceSection.search.rawValue
    @SceneStorage("mainWindow.networkSection") private var networkSectionRaw: String = NetworkSection.traffic.rawValue
    @SceneStorage("mainWindow.warpSection") private var warpSectionRaw: String = WarpWorkspaceSection.sessions.rawValue
    @SceneStorage("mainWindow.opsSection") private var opsSectionRaw: String = OpsSection.ports.rawValue
    @SceneStorage("mainWindow.trackSection") private var trackSectionRaw: String = TrackSection.flow.rawValue
    #endif
    @State private var page: MainPage = .dashboard
    @State private var gitRepoSelectionToken: UInt64 = 0
    @State private var toggleHovering = false
    @State private var trafficLights = TrafficLightPositioner()
    #if !CLAUDE_STATS_LITE
    @State private var linuxDoWebLoginPresented = false
    @State private var linuxDoSignInEnabled = true
    #endif

    private var availablePages: [MainPage] {
        var pages: [MainPage] = [.dashboard, .usage, .leaderboards, .dailyReport, .gantt]
        if env.preferences.aiActivityAnalysisEnabled { pages.append(.activity) }
        if env.preferences.systemMonitorEnabled { pages.append(.system) }
        return pages
    }

    private var mode: MainWindowMode {
        MainWindowMode(rawValue: modeRaw) ?? .app
    }

    private var settingsSection: SettingsSection {
        let storedSection = SettingsSection(rawValue: settingsSectionRaw) ?? .general
        return SettingsSection.availableCases.contains(storedSection) ? storedSection : .general
    }

    private var gitSelection: GitWorkspaceSelection {
        GitWorkspaceSelection(rawValue: gitSelectionRaw)
    }

    #if !CLAUDE_STATS_LITE
    private var sessionsDestination: SessionsDestination {
        SessionsDestination(rawValue: sessionsDestinationRaw)
    }

    private var selectedSession: Session? {
        guard case .session(let id) = sessionsDestination else { return nil }
        return env.store.sessions(for: env.preferences.selectedProvider).first { $0.id == id }
    }

    private var networkSection: NetworkSection {
        NetworkSection(storedRawValue: networkSectionRaw)
    }

    private var warpSection: WarpWorkspaceSection {
        WarpWorkspaceSection(storedRawValue: warpSectionRaw)
    }

    private var opsSection: OpsSection {
        OpsSection(storedRawValue: opsSectionRaw)
    }

    private var trackSection: TrackSection {
        TrackSection(rawValue: trackSectionRaw) ?? .flow
    }
    #endif

    private var settingsSectionBinding: Binding<SettingsSection> {
        Binding(
            get: { settingsSection },
            set: { settingsSectionRaw = $0.rawValue }
        )
    }

    private var gitSelectionBinding: Binding<GitWorkspaceSelection> {
        Binding(
            get: { gitSelection },
            set: { gitSelectionRaw = $0.rawValue }
        )
    }

    #if !CLAUDE_STATS_LITE
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

    private var sessionsDestinationBinding: Binding<SessionsDestination> {
        Binding(
            get: { sessionsDestination },
            set: { sessionsDestinationRaw = $0.rawValue }
        )
    }

    private var networkSectionBinding: Binding<NetworkSection> {
        Binding(
            get: { networkSection },
            set: { networkSectionRaw = $0.rawValue }
        )
    }

    private var warpSectionBinding: Binding<WarpWorkspaceSection> {
        Binding(
            get: { warpSection },
            set: { warpSectionRaw = $0.rawValue }
        )
    }

    private var opsSectionBinding: Binding<OpsSection> {
        Binding(
            get: { opsSection },
            set: { opsSectionRaw = $0.rawValue }
        )
    }

    private var trackSectionBinding: Binding<TrackSection> {
        Binding(
            get: { trackSection },
            set: { trackSectionRaw = $0.rawValue }
        )
    }
    #endif

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
                    isSessionsActive: AppVariant.isEnabled(.sessions) && mode == .sessions,
                    isConfigsActive: mode == .configs,
                    isMemoryActive: AppVariant.isEnabled(.memory) && mode == .memory,
                    isGitActive: mode == .git,
                    isWarpActive: mode == .warp,
                    isTrackActive: AppVariant.isEnabled(.track) && mode == .track,
                    onOpenSettings: openSettings,
                    onOpenLinuxDo: openLinuxDo,
                    onOpenSessions: openSessions,
                    onOpenConfigs: openConfigs,
                    onOpenMemory: openMemory,
                    onOpenGit: openGit,
                    onOpenNetwork: openNetwork,
                    onOpenWarp: { openWarp() },
                    onOpenOps: openOps,
                    onOpenTrack: openTrack
                )
            } linuxDoSidebar: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                LinuxDoSidebarColumn(
                    store: env.linuxDo,
                    signInEnabled: linuxDoSignInEnabled,
                    onExit: closeLinuxDo,
                    onSignIn: openLinuxDoSignIn
                )
                #endif
            } sessionsSidebar: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                SessionSidebarColumn(
                    destination: sessionsDestinationBinding,
                    onExit: closeSessions
                )
                #endif
            } configsSidebar: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                ConfigWorkspaceSidebar(store: env.configWorkspace, onExit: closeConfigs)
                #endif
            } memorySidebar: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                MemoryWorkspaceSidebar(store: env.memory, onExit: closeMemory)
                #endif
            } gitSidebar: {
                GitWorkspaceSidebar(
                    model: env.gitActivity,
                    selection: gitSelectionBinding,
                    onSelect: selectGitWorkspace,
                    onExit: closeGit
                )
            } settingsSidebar: {
                SettingsSidebarColumn(section: settingsSectionBinding, onExit: closeSettings)
            } networkSidebar: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                NetworkSidebarColumn(store: env.networkDebugger, section: networkSectionBinding, onExit: closeNetwork)
                #endif
            } warpSidebar: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                WarpSidebarColumn(store: env.warpSessionStore, section: warpSectionBinding, onExit: closeWarp)
                #endif
            } opsSidebar: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                OpsSidebarColumn(section: opsSectionBinding, onExit: closeOps)
                #endif
            } trackSidebar: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                TrackSidebarColumn(store: env.track, section: trackSectionBinding, onExit: closeTrack)
                #endif
            } appDetail: {
                detail
            } linuxDoDetail: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                LinuxDoWorkspaceView(store: env.linuxDo)
                #endif
            } sessionsDetail: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                sessionsDetail
                #endif
            } configsDetail: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                ConfigWorkspaceView(
                    store: env.configWorkspace,
                    selectedProjectID: configsProjectIDBinding,
                    selectedDocumentID: configsDocumentIDBinding
                )
                #endif
            } memoryDetail: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                MemoryWorkspaceView(store: env.memory)
                #endif
            } gitDetail: {
                GitWorkspaceDetailView(
                    selection: gitSelectionBinding,
                    repoSelectionToken: gitRepoSelectionToken
                )
            } settingsDetail: {
                SettingsDetailView(section: settingsSection, onSelectSection: selectSettingsSection)
            } networkDetail: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                NetworkDetailView(section: networkSection)
                #endif
            } warpDetail: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                WarpWorkspaceView(
                    section: warpSection,
                    store: env.warpSessionStore,
                    chromeMode: env.preferences.terminalChromeMode,
                    backgroundStyle: env.preferences.terminalBackgroundStyle
                )
                #endif
            } opsDetail: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                OpsDetailView(store: env.ops, section: opsSection)
                #endif
            } trackDetail: {
                #if CLAUDE_STATS_LITE
                EmptyView()
                #else
                TrackDetailView(store: env.track, section: trackSection)
                #endif
            }
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { clearTextFocus() }
            }

            if mode == .app || mode == .linuxDo || mode == .sessions || mode == .configs || mode == .memory || mode == .git || mode == .network || mode == .warp || mode == .ops || mode == .track {
                sidebarToggle
                    .padding(.leading, 81)
                    .padding(.top, 11)
                    .transition(.opacity)
            }

            if let notice = env.notices.current {
                AppNoticeToast(notice: notice) {
                    handleNoticeTap(notice)
                }
                .padding(.top, 18)
                .padding(.trailing, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(30)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86), value: env.notices.current?.id)
        .ignoresSafeArea()
        .background(WindowAccessor { window in
            trafficLights.attach(to: window)
        })
        .onAppear {
            #if !CLAUDE_STATS_LITE
            restoreConfigWorkspaceState()
            restoreMemoryWorkspaceState()
            #endif
            normalizeNavigationState()
            #if !CLAUDE_STATS_LITE
            if mode == .sessions { clearInvalidSessionSelection() }
            #endif
            DockVisibilityCoordinator.shared.acquire()
            Log.app.info("Main window opened on page \(page.rawValue, privacy: .public)")
        }
        .onDisappear {
            DockVisibilityCoordinator.shared.release()
            Log.app.info("Main window closed")
        }
        #if !CLAUDE_STATS_LITE
        .sheet(isPresented: $linuxDoWebLoginPresented) {
            LinuxDoWebLoginSheet(store: env.linuxDo, isPresented: $linuxDoWebLoginPresented)
        }
        #endif
        .onChange(of: page) { _, new in
            guard availablePages.contains(new) else {
                page = .dashboard
                pageRaw = MainPage.dashboard.rawValue
                return
            }
            pageRaw = new.rawValue
        }
        #if !CLAUDE_STATS_LITE
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
            if mode == .sessions { clearInvalidSessionSelection() }
        }
        .onChange(of: env.preferences.selectedProvider) { _, _ in
            if mode == .sessions, case .session = sessionsDestination {
                sessionsDestinationRaw = SessionsDestination.overviewRawValue
            }
        }
        #endif
        .onChange(of: env.preferences.aiActivityAnalysisEnabled) { _, on in
            if !on && page == .activity { page = .dashboard }
        }
        .onChange(of: env.preferences.gitTrackingEnabled) { _, on in
            if !on && (page == .git || mode == .git) {
                page = .dashboard
                pageRaw = MainPage.dashboard.rawValue
                transition(to: .app)
            }
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
            Image(systemName: AppIcon.Navigation.sidebarLeft)
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
        case .dailyReport:
            DailyReportWorkspaceView(store: env.dailyReport)
        case .gantt:
            MainGanttView()
        case .git:
            GitWorkspaceDetailView(
                selection: gitSelectionBinding,
                repoSelectionToken: gitRepoSelectionToken
            )
        case .system:
            MainSystemMonitorView()
        case .terminal:
            #if CLAUDE_STATS_LITE
            DashboardView()
            #else
            TerminalWorkspaceView(warpStore: env.warpSessionStore)
            #endif
        }
    }

    #if !CLAUDE_STATS_LITE
    @ViewBuilder
    private var sessionsDetail: some View {
        switch sessionsDestination {
        case .overview:
            SessionsOverviewDetailView()
        case .analysis:
            SessionsAnalysisDetailView()
        case .session:
            if let selectedSession {
                CenteredPaneContainer {
                    SessionDetailView(session: selectedSession)
                }
            } else {
                SessionsOverviewDetailView()
            }
        }
    }
    #endif

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

    private func handleNoticeTap(_ notice: AppNotice) {
        env.notices.dismiss(id: notice.id)
        switch notice.action {
        case .openSettings(let section):
            openSettings(section: section)
        case .none:
            break
        }
    }

    #if CLAUDE_STATS_LITE
    private func openLinuxDo() {}
    #else
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
    #endif

    #if CLAUDE_STATS_LITE
    private func openConfigs() {}
    #else
    private func openConfigs() {
        transition(to: .configs)
    }
    #endif

    #if CLAUDE_STATS_LITE
    private func openSessions() {}
    #else
    private func openSessions() {
        sidebarVisible = true
        sessionsDestinationRaw = SessionsDestination.overviewRawValue
        transition(to: .sessions)
    }
    #endif

    #if CLAUDE_STATS_LITE
    private func openMemory() {}
    #else
    private func openMemory() {
        transition(to: .memory)
    }
    #endif

    private func openGit() {
        guard env.preferences.gitTrackingEnabled else {
            page = .dashboard
            pageRaw = MainPage.dashboard.rawValue
            transition(to: .app)
            return
        }
        transition(to: .git)
    }

    #if CLAUDE_STATS_LITE
    private func openNetwork() {}
    #else
    private func openNetwork() {
        transition(to: .network)
    }
    #endif

    #if CLAUDE_STATS_LITE
    private func openWarp(resetToSessions: Bool = false) {}
    #else
    private func openWarp(resetToSessions: Bool = false) {
        if resetToSessions {
            warpSectionRaw = WarpWorkspaceSection.sessions.rawValue
        }
        transition(to: .warp)
    }
    #endif

    #if CLAUDE_STATS_LITE
    private func openOps() {}
    #else
    private func openOps() {
        transition(to: .ops)
    }
    #endif

    #if CLAUDE_STATS_LITE
    private func openTrack() {}
    #else
    private func openTrack() {
        transition(to: .track)
    }
    #endif

    private func closeSettings() {
        transition(to: .app)
    }

    #if CLAUDE_STATS_LITE
    private func closeLinuxDo() {}
    #else
    private func closeLinuxDo() {
        Log.app.info("Closing LinuxDo mode")
        transition(to: .app)
    }
    #endif

    #if CLAUDE_STATS_LITE
    private func closeSessions() {}
    #else
    private func closeSessions() {
        transition(to: .app)
    }
    #endif

    #if CLAUDE_STATS_LITE
    private func closeConfigs() {}
    #else
    private func closeConfigs() {
        transition(to: .app)
    }
    #endif

    #if CLAUDE_STATS_LITE
    private func closeMemory() {}
    #else
    private func closeMemory() {
        transition(to: .app)
    }
    #endif

    private func closeGit() {
        transition(to: .app)
    }

    private func selectGitWorkspace(_ nextSelection: GitWorkspaceSelection) {
        if nextSelection.repoID != nil {
            gitRepoSelectionToken &+= 1
        }
        gitSelectionRaw = nextSelection.rawValue
    }

    #if CLAUDE_STATS_LITE
    private func closeNetwork() {}
    #else
    private func closeNetwork() {
        transition(to: .app)
    }
    #endif

    #if CLAUDE_STATS_LITE
    private func closeWarp() {}
    #else
    private func closeWarp() {
        transition(to: .app)
    }
    #endif

    #if CLAUDE_STATS_LITE
    private func closeOps() {}
    #else
    private func closeOps() {
        transition(to: .app)
    }
    #endif

    #if CLAUDE_STATS_LITE
    private func closeTrack() {}
    #else
    private func closeTrack() {
        transition(to: .app)
    }
    #endif

    private func openFloatingStatsDestination(_ destination: FloatingStatsMainWindowDestination) {
        switch destination {
        case .page(let nextPage):
            if nextPage == .git {
                openGit()
                return
            }
            #if CLAUDE_STATS_LITE
            let resolvedPage: MainPage = nextPage == .terminal ? .dashboard : nextPage
            page = availablePages.contains(resolvedPage) ? resolvedPage : .dashboard
            transition(to: .app)
            #else
            if nextPage == .terminal {
                openWarp(resetToSessions: true)
                return
            }
            page = availablePages.contains(nextPage) ? nextPage : .dashboard
            transition(to: .app)
            #endif
        case .git:
            openGit()
        #if !CLAUDE_STATS_LITE
        case .network:
            transition(to: .network)
        case .warp:
            openWarp(resetToSessions: true)
        case .linuxDoTopic(let route):
            env.linuxDo.openTopic(route)
            openLinuxDo()
        #endif
        }
    }

    #if !CLAUDE_STATS_LITE
    private func clearInvalidSessionSelection() {
        guard case .session(let id) = sessionsDestination else { return }
        let sessions = env.store.sessions(for: env.preferences.selectedProvider)
        if !sessions.contains(where: { $0.id == id }) {
            sessionsDestinationRaw = SessionsDestination.overviewRawValue
        }
    }
    #endif

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
        if modeRaw == "dailyReport" {
            modeRaw = MainWindowMode.app.rawValue
            page = .dailyReport
            pageRaw = MainPage.dailyReport.rawValue
        }

        #if CLAUDE_STATS_LITE
        if modeRaw == "sessions"
            || modeRaw == "memory"
            || modeRaw == "linuxDo"
            || modeRaw == "configs"
            || modeRaw == "network"
            || modeRaw == "warp"
            || modeRaw == "ops"
            || modeRaw == "track"
            || modeRaw == "chat" {
            modeRaw = MainWindowMode.app.rawValue
            sidebarVisible = true
        }
        #else
        if modeRaw == "sessions" {
            modeRaw = MainWindowMode.sessions.rawValue
            sidebarVisible = true
        }

        if modeRaw == "chat" {
            modeRaw = MainWindowMode.warp.rawValue
            warpSectionRaw = WarpWorkspaceSection.sessions.rawValue
            sidebarVisible = true
        }
        #endif

        if MainWindowMode(rawValue: modeRaw) == nil {
            modeRaw = MainWindowMode.app.rawValue
        }

        if mode == .git && !env.preferences.gitTrackingEnabled {
            modeRaw = MainWindowMode.app.rawValue
            sidebarVisible = true
        }

        #if !CLAUDE_STATS_LITE
        if env.configWorkspace.migrateLegacyMainPage(rawValue: pageRaw) {
            configSectionRaw = env.configWorkspace.section.rawValue
            configFilesSectionRaw = env.configWorkspace.filesSection.rawValue
            page = .dashboard
            pageRaw = MainPage.dashboard.rawValue
            modeRaw = MainWindowMode.configs.rawValue
            sidebarVisible = true
            return
        }
        #endif

        let storedPage = MainPage(rawValue: pageRaw) ?? .dashboard
        if storedPage == .git {
            page = .dashboard
            pageRaw = MainPage.dashboard.rawValue
            if env.preferences.gitTrackingEnabled {
                modeRaw = MainWindowMode.git.rawValue
                sidebarVisible = true
            } else {
                modeRaw = MainWindowMode.app.rawValue
            }
            return
        }

        if storedPage == .terminal {
            #if CLAUDE_STATS_LITE
            page = .dashboard
            pageRaw = MainPage.dashboard.rawValue
            modeRaw = MainWindowMode.app.rawValue
            sidebarVisible = true
            #else
            page = .dashboard
            pageRaw = MainPage.dashboard.rawValue
            warpSectionRaw = WarpWorkspaceSection.sessions.rawValue
            modeRaw = MainWindowMode.warp.rawValue
            sidebarVisible = true
            #endif
            return
        }

        if availablePages.contains(storedPage) {
            page = storedPage
            pageRaw = storedPage.rawValue
        } else {
            page = .dashboard
            pageRaw = MainPage.dashboard.rawValue
        }

        if mode == .linuxDo || mode == .git {
            sidebarVisible = true
        }
    }

    #if !CLAUDE_STATS_LITE
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
    #endif

    #if !CLAUDE_STATS_LITE
    private func restoreMemoryWorkspaceState() {
        env.memory.section = MemoryWorkspaceSection(rawValue: memorySectionRaw) ?? .search
        memorySectionRaw = env.memory.section.rawValue
    }
    #endif
}

private struct AppNoticeToast: View {
    let notice: AppNotice
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.title)
                        .font(.sora(12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(notice.message)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let actionTitle = notice.actionTitle {
                        Text(actionTitle)
                            .font(.sora(10, weight: .semibold))
                            .foregroundStyle(tint)
                            .padding(.top, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 320, alignment: .leading)
            .background(AppSurface.panelFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.stxStroke.opacity(0.85), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(notice.actionTitle ?? notice.title)
        .accessibilityLabel("\(notice.title). \(notice.message)")
    }

    private var icon: String {
        switch notice.severity {
        case .info: AppIcon.Status.info
        case .success: AppIcon.Status.success
        case .warning: AppIcon.Status.warning
        case .error: AppIcon.Status.error
        }
    }

    private var tint: Color {
        switch notice.severity {
        case .info: Color.stxMuted
        case .success: Color.stxAccent
        case .warning: Color.orange
        case .error: Color.red
        }
    }
}

#if DEBUG
#Preview("Main window") {
    MainWindowView()
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
}
#endif
