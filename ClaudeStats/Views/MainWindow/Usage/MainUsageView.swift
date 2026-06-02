import AppKit
import SwiftUI

/// Wide Usage page for the main window. The menu-bar panel still uses
/// `UsageView`; this view owns the larger-window layout and scene persistence.
struct MainUsageView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    @SceneStorage("mainWindow.usage.period") private var periodRaw: String = StatsPeriod.allTime.rawValue
    @SceneStorage("mainWindow.usage.chartStyle") private var chartStyleRaw: String = MainUsageView.ChartStyleStorage.line.rawValue
    @SceneStorage("mainWindow.usage.scaleMode") private var scaleModeRaw: String = MainUsageView.ScaleModeStorage.linear.rawValue
    @SceneStorage("mainWindow.usage.stackByType") private var stackByTypeRaw: Bool = false
    @SceneStorage("mainWindow.usage.dailyPeriodKey") private var dailyPeriodKeyRaw: String = ""

    @State private var vm = UsageViewModel()

    var body: some View {
        @Bindable var bvm = vm
        let provider = env.preferences.selectedProvider
        let data = vm.displayedDerivedData(provider: provider, lastRefreshedAt: env.store.lastRefreshedAt)
        let summary = data.summary
        let series = data.series
        let includeCache = env.preferences.includeCacheInTokens
        let costMode = env.preferences.costEstimationMode
        let cacheHitRate = data.cacheHitRate

        AppScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(provider: provider)
                controls(period: $bvm.period, selectedDay: $bvm.selectedDay)
                UsageSummaryCards(
                    summary: summary,
                    includeCacheInTokens: includeCache,
                    costEstimationMode: costMode,
                    cacheHitRate: cacheHitRate
                )
                if provider.supportsUsageLimits {
                    usageLimitPanel(provider: provider)
                }
                UsageTrendPanel(
                    series: series,
                    seriesID: data.key.chartSeriesID,
                    rangeID: vm.period.rawValue,
                    chartStyle: $bvm.chartStyle,
                    scaleMode: $bvm.scaleMode,
                    stackByType: $bvm.stackByType,
                    displayName: modelDisplayName
                )
                lowerPanels(
                    summary: summary,
                    series: series,
                    seriesID: data.key.chartSeriesID,
                    includeCache: includeCache,
                    costMode: costMode,
                    cacheHitRate: cacheHitRate
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 22)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            syncFromSceneStorage()
            refreshDerivedData()
        }
        .onChange(of: vm.period) { _, new in periodRaw = new.rawValue }
        .onChange(of: vm.selectedDay) { _, new in
            let normalized = UsageDailyDateNavigator.normalized(new)
            if normalized != new {
                vm.selectedDay = normalized
                return
            }
            dailyPeriodKeyRaw = UsageDailyDateNavigator.periodKey(for: normalized)
        }
        .onChange(of: vm.chartStyle) { _, new in chartStyleRaw = ChartStyleStorage(new).rawValue }
        .onChange(of: vm.scaleMode) { _, new in scaleModeRaw = ScaleModeStorage(new).rawValue }
        .onChange(of: vm.stackByType) { _, new in stackByTypeRaw = new }
        .onChange(of: usageDataKey) { _, _ in refreshDerivedData() }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in
            guard env.preferences.selectedProvider.supportsUsageLimits else { return }
            Task {
                await env.usageLimits.refresh(provider: env.preferences.selectedProvider, force: true)
            }
        }
        .task(id: claudeDesktopTimedCaptureKey) {
            await runClaudeDesktopTimedCaptureLoop()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await env.usageLimits.runPendingClaudeDesktopPermissionRechecks() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await env.usageLimits.runPendingClaudeDesktopPermissionRechecks() }
        }
    }

    private func header(provider: ProviderKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("USAGE")
                .font(.sora(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.stxMuted)
            Text("Token usage")
                .font(.sora(24, weight: .semibold))
                .lineLimit(1)
            Text(L10n.format("usage.subtitle.provider_mix",
                             defaultValue: "Cost, cache, and model mix for %@.",
                             provider.displayName))
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
        }
    }

    private func controls(period: Binding<StatsPeriod>, selectedDay: Binding<Date>) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                Spacer(minLength: 0)
                UsageDailyPeriodControl(period: period, selectedDay: selectedDay)
                UsagePeriodChips(period: period)
            }
            VStack(alignment: .trailing, spacing: 8) {
                UsageDailyPeriodControl(period: period, selectedDay: selectedDay)
                UsagePeriodChips(period: period)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func usageLimitPanel(provider: ProviderKind) -> some View {
        UsageLimitPanel(
            provider: provider,
            report: env.usageLimits.report(for: provider),
            isLoading: env.usageLimits.isLoading(provider),
            actionMessage: env.usageLimits.actionMessage(for: provider),
            visibleWindowIDs: provider == .claude ? env.preferences.claudeUsageLimitVisibleWindowIDs : nil,
            onRefresh: {
                Task { await env.usageLimits.refresh(provider: provider, force: true) }
            },
            onInstallClaudeBridge: provider == .claude ? {
                env.usageLimits.installClaudeBridge()
            } : nil,
            onCopyClaudeSettingsSnippet: provider == .claude ? {
                copyClaudeSettingsSnippet()
            } : nil,
            onOpenClaudeSettings: provider == .claude ? {
                openClaudeSettings()
            } : nil,
            claudeDesktopPermissionIssue: provider == .claude ? env.usageLimits.claudeDesktopPermissionIssue : nil,
            onReadClaudeDesktop: provider == .claude ? {
                Task { await env.usageLimits.captureClaudeDesktopUsage(trigger: .manual) }
            } : nil,
            onOpenAccessibilitySettings: provider == .claude ? {
                openClaudeAccessibilitySettings()
            } : nil,
            onOpenScreenRecordingSettings: provider == .claude ? {
                openClaudeScreenRecordingSettings()
            } : nil
        )
        .task(id: provider) {
            await env.usageLimits.refresh(provider: provider)
            await runVisibleClaudeDesktopCaptureIfNeeded(provider: provider)
        }
    }

    @ViewBuilder
    private func lowerPanels(
        summary: UsageSummary,
        series: TrendSeries,
        seriesID: String,
        includeCache: Bool,
        costMode: CostEstimationMode,
        cacheHitRate: Double?
    ) -> some View {
        UsageLowerPanelsLayout(
            modelMinimumWidth: 560,
            compositionWidth: 300,
            spacing: 12
        ) {
            UsageModelBreakdown(
                models: summary.models,
                series: series,
                seriesID: seriesID,
                includeCacheInTokens: includeCache,
                costEstimationMode: costMode,
                displayName: modelDisplayName
            )
            UsageTokenCompositionPanel(
                usage: summary.totalUsage,
                includeCacheInTokens: includeCache,
                cacheHitRate: cacheHitRate
            )
        }
    }

    private var usageDataKey: UsageDerivedData.Key {
        UsageDerivedData.Key(
            period: vm.period,
            selectedDay: UsageDailyDateNavigator.normalized(vm.selectedDay),
            provider: env.preferences.selectedProvider,
            lastRefreshedAt: env.store.lastRefreshedAt
        )
    }

    private var claudeDesktopTimedCaptureKey: String {
        let preferences = env.preferences
        return [
            preferences.selectedProvider.rawValue,
            String(preferences.claudeDesktopUsageTimedCaptureEnabled),
            String(preferences.claudeDesktopUsageTimedIntervalMinutes),
        ].joined(separator: ":")
    }

    private func syncFromSceneStorage() {
        vm.period = StatsPeriod(rawValue: periodRaw) ?? .allTime
        vm.selectedDay = UsageDailyDateNavigator.date(fromPeriodKey: dailyPeriodKeyRaw)
            ?? UsageDailyDateNavigator.todayStart()
        dailyPeriodKeyRaw = UsageDailyDateNavigator.periodKey(for: vm.selectedDay)
        vm.chartStyle = ChartStyleStorage(rawValue: chartStyleRaw)?.chartStyle ?? .line
        vm.scaleMode = ScaleModeStorage(rawValue: scaleModeRaw)?.scaleMode ?? .linear
        vm.stackByType = stackByTypeRaw
    }

    private func refreshDerivedData() {
        vm.refreshDerivedData(
            from: env.store,
            provider: env.preferences.selectedProvider,
            lastRefreshedAt: env.store.lastRefreshedAt
        )
    }

    private func modelDisplayName(_ id: String) -> String {
        env.store.displayName(forModel: id, provider: env.preferences.selectedProvider)
    }

    private func copyClaudeSettingsSnippet() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(env.usageLimits.claudeSettingsSnippet(), forType: .string)
        env.usageLimits.recordActionMessage(
            L10n.string("usage.limit.action.copied_settings_snippet",
                        defaultValue: "Claude settings snippet copied."),
            for: .claude
        )
    }

    private func openClaudeSettings() {
        NSWorkspace.shared.open(env.usageLimits.claudeSettingsURL())
    }

    private func openClaudeAccessibilitySettings() {
        env.usageLimits.beginClaudeDesktopAccessibilityPermissionRecheck()
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    private func openClaudeScreenRecordingSettings() {
        env.usageLimits.beginClaudeDesktopScreenRecordingPermissionRecheck()
        openPrivacySettings(anchor: "Privacy_ScreenCapture")
    }

    private func runVisibleClaudeDesktopCaptureIfNeeded(provider: ProviderKind) async {
        guard provider == .claude,
              env.preferences.claudeDesktopUsageAutoMode == .visibleOnly else {
            return
        }
        await env.usageLimits.captureClaudeDesktopUsage(trigger: .visibleAutomatic)
    }

    private func runClaudeDesktopTimedCaptureLoop() async {
        guard env.preferences.selectedProvider == .claude,
              env.preferences.claudeDesktopUsageTimedCaptureEnabled else {
            return
        }
        while !Task.isCancelled {
            let minutes = max(5, env.preferences.claudeDesktopUsageTimedIntervalMinutes)
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled,
                  env.preferences.selectedProvider == .claude,
                  env.preferences.claudeDesktopUsageTimedCaptureEnabled else {
                return
            }
            await env.usageLimits.captureClaudeDesktopUsage(trigger: .timedAutomatic)
        }
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct UsagePeriodChips: View {
    @Binding var period: StatsPeriod

    private static let values: [StatsPeriod] = [.last7Days, .last30Days, .allTime]

    var body: some View {
        PillSegmentedBar(
            Self.values,
            selection: $period,
            help: { $0.displayName }
        ) { value, _ in
            Text(label(for: value))
        }
    }

    private func label(for period: StatsPeriod) -> String {
        switch period {
        case .today: L10n.string("usage.period_chip.today", defaultValue: "Today")
        case .last7Days: L10n.string("usage.period_chip.weekly", defaultValue: "Weekly")
        case .last30Days: L10n.string("usage.period_chip.monthly", defaultValue: "Monthly")
        case .allTime: L10n.string("usage.period_chip.all", defaultValue: "All")
        }
    }
}

private struct UsageLowerPanelsLayout: Layout {
    let modelMinimumWidth: CGFloat
    let compositionWidth: CGFloat
    let spacing: CGFloat

    private var horizontalMinimumWidth: CGFloat {
        modelMinimumWidth + compositionWidth + spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }

        let availableWidth = proposal.width ?? horizontalMinimumWidth
        if availableWidth >= horizontalMinimumWidth {
            let modelWidth = max(modelMinimumWidth, availableWidth - compositionWidth - spacing)
            let modelSize = subviews[0].sizeThatFits(ProposedViewSize(width: modelWidth, height: nil))
            let compositionSize = subviews[1].sizeThatFits(ProposedViewSize(width: compositionWidth, height: nil))
            return CGSize(width: availableWidth, height: max(modelSize.height, compositionSize.height))
        }

        let stackedWidth = max(0, availableWidth)
        let modelSize = subviews[0].sizeThatFits(ProposedViewSize(width: stackedWidth, height: nil))
        let compositionSize = subviews[1].sizeThatFits(ProposedViewSize(width: stackedWidth, height: nil))
        return CGSize(
            width: stackedWidth,
            height: modelSize.height + spacing + compositionSize.height
        )
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard subviews.count == 2 else { return }

        if bounds.width >= horizontalMinimumWidth {
            let modelWidth = max(modelMinimumWidth, bounds.width - compositionWidth - spacing)
            subviews[0].place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: modelWidth, height: nil)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX + modelWidth + spacing, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: compositionWidth, height: nil)
            )
        } else {
            let modelSize = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subviews[0].place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + modelSize.height + spacing),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
        }
    }
}

private extension MainUsageView {
    enum ChartStyleStorage: String {
        case line, bar

        init(_ chartStyle: TrendChartStyle) {
            self = chartStyle == .line ? .line : .bar
        }

        var chartStyle: TrendChartStyle {
            switch self {
            case .line: .line
            case .bar: .bar
            }
        }
    }

    enum ScaleModeStorage: String {
        case linear, log

        init(_ scaleMode: TrendScaleMode) {
            self = scaleMode == .linear ? .linear : .log
        }

        var scaleMode: TrendScaleMode {
            switch self {
            case .linear: .linear
            case .log: .log
            }
        }
    }
}

extension View {
    func mainUsagePanel(padding: CGFloat = 14) -> some View {
        mainWindowPanel(padding: padding)
    }
}

#if DEBUG
#Preview("Main Usage") {
    MainUsageView()
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
        .background(Color.stxBackground)
}
#endif
