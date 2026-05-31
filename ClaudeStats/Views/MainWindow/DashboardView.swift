import SwiftUI

/// Overview Dashboard: 8 all-provider stat cards (4×2) scoped by an
/// "All / 30d / 7d" range, then a side-by-side row with the 3-month AI
/// heatmap on the left and the 3-month GitHub contributions heatmap on the
/// right, followed by the 3-month AI/GitHub overlap, and a humorous
/// comparison footer. The "Models" tab swaps the stat grid for a per-model
/// breakdown table.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env

    @SceneStorage("dashboard.section") private var sectionRaw: String = DashboardViewModel.Section.overview.rawValue
    @SceneStorage("dashboard.period") private var periodRaw: String = StatsPeriod.last30Days.rawValue
    @SceneStorage("dashboard.statusProvider") private var statusProviderRaw: String = ""

    /// GitHub cells filtered to the current heatmap window, cached so both
    /// `githubHeatmapSection` and `overlapCard` don't independently re-filter
    /// per body pass.
    @State private var githubCellsInRange: [HeatmapCell] = []
    /// Cached overlap stats. `nil` until inputs are available; recomputed via
    /// `refreshDerived()` when the inputs change. Saves two dict builds + two
    /// 90-day correlation walks per body pass.
    @State private var overlap: OverlapStats? = nil

    private var vm: DashboardViewModel { env.dashboard }

    private struct DashboardReloadKey: Equatable {
        let period: StatsPeriod
        let lastRefresh: Date?
        let token: UInt64
    }

    private struct GitHubReloadKey: Equatable {
        let githubEnabled: Bool
        let githubLogin: String
    }

    private enum StatusProvider: String, Equatable {
        case claude, codex

        var alternate: StatusProvider {
            switch self {
            case .claude: .codex
            case .codex: .claude
            }
        }

        var switchHelp: String {
            switch alternate {
            case .claude: L10n.string("status.claude.show", defaultValue: "Show Claude Status")
            case .codex: L10n.string("status.openai.show", defaultValue: "Show OpenAI Status")
            }
        }
    }

    var body: some View {
        let heatmapRange = vm.heatmapInterval()

        AppScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                controls
                Group {
                    switch vm.section {
                    case .overview: overviewBody(heatmapRange: heatmapRange)
                    case .models: modelsBody()
                    }
                }
                Spacer(minLength: 0)
            }
            // Horizontal padding trimmed (28 → 20) so the 4-column stat grid
            // fits inside the detail panel at the window's minimum width.
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 22)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            syncFromSceneStorage()
            syncStatusProviderFromSelection(env.preferences.selectedProvider)
            refreshDerived()
        }
        .onChange(of: vm.section) { _, new in sectionRaw = new.rawValue }
        .onChange(of: vm.period) { _, new in periodRaw = new.rawValue }
        .onChange(of: env.preferences.selectedProvider) { _, new in syncStatusProviderFromSelection(new) }
        .onChange(of: vm.heatmapCells) { _, _ in refreshDerived() }
        .onChange(of: env.github.cells) { _, _ in refreshDerived() }
        .task(id: dashboardReloadKey) {
            await vm.reload(sessions: env.store.sessions)
        }
        .task(id: githubReloadKey) {
            await env.github.reload(
                expectedLogin: env.preferences.githubLogin,
                enabled: env.preferences.githubEnabled
            )
            // If GitHub resolved a different login (rare — token now points
            // at a different user), keep prefs in sync.
            if case let .connected(login, _, _) = env.github.status,
               login != env.preferences.githubLogin {
                env.preferences.githubLogin = login
            }
        }
    }

    private func refreshDerived() {
        let range = vm.heatmapInterval()
        let github = env.github.cells.filter { range.contains($0.date) }
        githubCellsInRange = github
        overlap = OverlapStats.compute(
            local: vm.heatmapCells,
            github: github,
            range: range
        )
    }

    private var dashboardReloadKey: DashboardReloadKey {
        DashboardReloadKey(
            period: vm.period,
            lastRefresh: env.store.lastRefreshedAt,
            token: vm.reloadToken
        )
    }

    private var githubReloadKey: GitHubReloadKey {
        GitHubReloadKey(
            githubEnabled: env.preferences.githubEnabled,
            githubLogin: env.preferences.githubLogin
        )
    }

    private func syncFromSceneStorage() {
        if let s = DashboardViewModel.Section(rawValue: sectionRaw) { vm.section = s }
        if let p = StatsPeriod(rawValue: periodRaw),
           RangeChips.supported.contains(p) {
            vm.period = p
        }
    }

    private var statusProvider: StatusProvider {
        StatusProvider(rawValue: statusProviderRaw) ?? defaultStatusProvider
    }

    private var defaultStatusProvider: StatusProvider {
        env.preferences.selectedProvider == .codex ? .codex : .claude
    }

    private func syncStatusProviderFromSelection(_ provider: ProviderKind) {
        switch provider {
        case .claude:
            statusProviderRaw = StatusProvider.claude.rawValue
        case .codex:
            statusProviderRaw = StatusProvider.codex.rawValue
        case .gemini, .kimi, .minimax:
            if StatusProvider(rawValue: statusProviderRaw) == nil {
                statusProviderRaw = defaultStatusProvider.rawValue
            }
        }
    }

    // MARK: - Header & controls

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DASHBOARD")
                .font(.sora(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.stxMuted)
            Text("Coding activity")
                .font(.sora(24, weight: .semibold))
            Text("Your AI coding sessions, day by day.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
        }
    }

    private var controls: some View {
        @Bindable var bvm = vm
        return HStack(alignment: .center, spacing: 12) {
            OverviewTabs(section: $bvm.section)
            Spacer()
            RangeChips(period: $bvm.period)
        }
    }

    // MARK: - Overview body

    private func overviewBody(heatmapRange: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            statsGrid
            statusCard
            heatmapsRow(range: heatmapRange)
            overlapSection(range: heatmapRange)
            ComparisonFooter(totalTokens: vm.stats.totalTokens)
        }
    }

    /// Eight stat cards in a 4×2 manual `Grid`. Hard-coded to four columns so
    /// the value baselines line up across both rows — `LazyVGrid` would
    /// reflow them and lose that alignment.
    private var statsGrid: some View {
        let s = vm.stats
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatCard(label: L10n.string("dashboard.stat.sessions", defaultValue: "SESSIONS"), value: "\(s.sessions)")
                StatCard(label: L10n.string("dashboard.stat.messages", defaultValue: "MESSAGES"), value: Format.tokens(s.messages))
                StatCard(label: L10n.string("dashboard.stat.total_tokens", defaultValue: "TOTAL TOKENS"), value: Format.tokens(s.totalTokens))
                StatCard(label: L10n.string("dashboard.stat.active_days", defaultValue: "ACTIVE DAYS"), value: "\(s.activeDays)")
            }
            GridRow {
                StatCard(label: L10n.string("dashboard.stat.current_streak", defaultValue: "CURRENT STREAK"), value: "\(s.currentStreak)d")
                StatCard(label: L10n.string("dashboard.stat.longest_streak", defaultValue: "LONGEST STREAK"), value: "\(s.longestStreak)d")
                StatCard(label: L10n.string("dashboard.stat.peak_hour", defaultValue: "PEAK HOUR"), value: peakHourLabel(s.peakHour), animatesNumericValue: false)
                StatCard(label: L10n.string("dashboard.stat.favorite_model", defaultValue: "FAVORITE MODEL"), value: favoriteModelLabel(s.favoriteModel), animatesNumericValue: false)
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch statusProvider {
        case .claude:
            ClaudeStatusCard(
                status: env.claudeStatus,
                onSwitchStatusProvider: switchStatusProvider,
                switchStatusHelp: statusProvider.switchHelp
            )
        case .codex:
            OpenAIStatusCard(
                status: env.openAIStatus,
                onSwitchStatusProvider: switchStatusProvider,
                switchStatusHelp: statusProvider.switchHelp
            )
        }
    }

    private func switchStatusProvider() {
        statusProviderRaw = statusProvider.alternate.rawValue
    }

    // MARK: - Heatmap row (Claude + GitHub side-by-side, no card chrome)

    private func heatmapsRow(range: DateInterval) -> some View {
        HStack(alignment: .top, spacing: 32) {
            aiHeatmapSection(range: range)
            githubHeatmapSection(range: range)
        }
        .padding(.top, 4)
    }

    private func aiHeatmapSection(range: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heatmapHeader(
                title: L10n.string("dashboard.heatmap.ai_activity", defaultValue: "AI ACTIVITY"),
                subtitle: L10n.format("dashboard.heatmap.active_days_last_3_months",
                                      defaultValue: "%@ · last 3 months",
                                      L10n.activeDays(vm.heatmapActiveDays))
            )
            CompactHeatmap(
                cells: vm.heatmapCells,
                range: range,
                valueLabel: {
                    L10n.format("dashboard.heatmap.tokens_value",
                                defaultValue: "%@ tokens",
                                Format.tokens($0))
                }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func githubHeatmapSection(range: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heatmapHeader(title: "GITHUB", subtitle: githubSubtitle)
            switch githubDisplay {
            case .placeholder(let message, let isCTA):
                githubPlaceholder(message: message, isCTA: isCTA)
            case .heatmap(let cells, _):
                CompactHeatmap(
                    cells: cells,
                    range: range,
                    valueLabel: { L10n.contributionCount($0) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heatmapHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.sora(9, weight: .medium)).tracking(0.4)
                .foregroundStyle(Color.stxMuted)
            Spacer()
            Text(subtitle)
                .font(.sora(9))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
        }
    }

    // MARK: - Overlap section

    @ViewBuilder
    private func overlapSection(range: DateInterval) -> some View {
        if env.preferences.githubEnabled,
           case .connected = env.github.status,
           !env.github.cells.isEmpty,
           let overlap {
            overlapCard(overlap: overlap, range: range)
        }
    }

    private func overlapCard(overlap: OverlapStats, range: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("OVERLAP")
                    .font(.sora(9, weight: .medium)).tracking(0.4)
                    .foregroundStyle(Color.stxMuted)
                Text(L10n.format("dashboard.overlap.aligned",
                                 defaultValue: "%@ aligned",
                                 Format.percent(overlap.jaccard)))
                    .font(.sora(13, weight: .semibold))
                    .stxNumericValueTransition(value: Format.percent(overlap.jaccard))
                    .help(pearsonHelp(for: overlap))
                Spacer()
                Text(overlapBreakdown(overlap))
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            OverlapHeatmapView(
                stats: overlap,
                range: range,
                palette: env.preferences.overlapPalette,
                valueLabel: overlapStateLabel
            )
        }
        .appSurface(.mainWindowCard)
    }

    // MARK: - Models body

    private func modelsBody() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ModelsTrendChart(
                series: vm.modelTrend,
                seriesID: vm.modelTrend.dataRevisionID,
                includeCacheInTotals: env.preferences.includeCacheInTokens,
                displayName: modelDisplayName
            )
            DashboardModelTable(
                models: vm.modelBreakdown,
                includeCacheInTotals: env.preferences.includeCacheInTokens,
                displayName: dashboardModelDisplayName
            )
        }
    }

    /// Pretty label for a provider-qualified Dashboard model id.
    private func modelDisplayName(_ id: String) -> String {
        guard let key = DashboardModelKey(id: id) else { return id }
        return dashboardModelDisplayName(key)
    }

    private func dashboardModelDisplayName(_ key: DashboardModelKey) -> String {
        "\(key.provider.shortName) - \(env.store.displayName(forModel: key.model, provider: key.provider))"
    }

    // MARK: - GitHub display state

    private enum GitHubDisplay {
        case placeholder(message: String, isCTA: Bool)
        case heatmap(cells: [HeatmapCell], totalInRange: Int)
    }

    private var githubDisplay: GitHubDisplay {
        guard env.preferences.githubEnabled else {
            return .placeholder(
                message: L10n.string("dashboard.github.enable_prompt",
                                     defaultValue: "Enable GitHub in Features to compare your contributions."),
                isCTA: true
            )
        }
        switch env.github.status {
        case .disconnected:
            return .placeholder(
                message: L10n.string("dashboard.github.connect_prompt",
                                     defaultValue: "Connect a GitHub account in Features to see your contribution graph."),
                isCTA: true
            )
        case .connecting:
            return .placeholder(
                message: L10n.string("dashboard.github.fetching", defaultValue: "Fetching contribution graph…"),
                isCTA: false
            )
        case .connected, .failed:
            let total = githubCellsInRange.reduce(0) { $0 + $1.value }
            return .heatmap(cells: githubCellsInRange, totalInRange: total)
        }
    }

    private var githubSubtitle: String {
        guard env.preferences.githubEnabled else { return L10n.string("status.disabled", defaultValue: "Disabled") }
        switch env.github.status {
        case .disconnected: return L10n.string("status.not_connected", defaultValue: "Not connected")
        case .connecting: return L10n.string("status.connecting", defaultValue: "Connecting…")
        case .connected(let login, _, _):
            return "@\(login)"
        case .failed: return L10n.string("status.error", defaultValue: "Error")
        }
    }

    private func githubPlaceholder(message: String, isCTA: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
            if isCTA {
                Button { openFeaturesSettings() } label: {
                    BracketBox(spacing: 5) {
                        Label("OPEN FEATURES", systemImage: AppIcon.Settings.features)
                            .labelStyle(.titleAndIcon)
                            .font(.sora(10))
                            .tracking(0.8)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxAccent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Overlap formatting helpers

    private func overlapBreakdown(_ s: OverlapStats) -> String {
        L10n.format("dashboard.overlap.breakdown",
                    defaultValue: "%d both · %d AI · %d GitHub · %d neither",
                    s.bothCount,
                    s.localOnlyCount,
                    s.githubOnlyCount,
                    s.neitherCount)
    }

    private func pearsonHelp(for s: OverlapStats) -> String {
        guard let r = s.pearson else {
            return L10n.string("dashboard.overlap.pearson_undefined",
                               defaultValue: "Pearson correlation not defined (one series is constant)")
        }
        return String(format: "Pearson r = %.2f", r)
    }

    private func overlapStateLabel(_ state: OverlapStats.DayState) -> String {
        switch state {
        case .both: L10n.string("dashboard.overlap.state.both", defaultValue: "Both AI and GitHub activity")
        case .localOnly: L10n.string("dashboard.overlap.state.local_only", defaultValue: "AI activity only")
        case .githubOnly: L10n.string("dashboard.overlap.state.github_only", defaultValue: "GitHub activity only")
        case .neither: L10n.string("dashboard.overlap.state.neither", defaultValue: "No activity")
        }
    }

    private func openFeaturesSettings() {
        NotificationCenter.default.post(name: .openSettingsInMainWindow, object: SettingsSection.features)
    }

    // MARK: - Stat-card formatting helpers

    /// `"5 PM"` for hour 17 in the current locale. Returns "—" when no
    /// activity has been recorded yet.
    private func peakHourLabel(_ hour: Int?) -> String {
        guard let hour,
              let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)
        else { return "—" }
        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }

    /// Pretty display name for the favorite-model stat card.
    private func favoriteModelLabel(_ model: DashboardModelKey?) -> String {
        guard let model, !model.model.isEmpty else { return "—" }
        return dashboardModelDisplayName(model)
    }
}

#if DEBUG
#Preview("Dashboard") {
    DashboardView()
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
        .background(Color.stxBackground)
}
#endif
