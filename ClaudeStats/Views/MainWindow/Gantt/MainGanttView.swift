import AppKit
import SwiftUI

struct MainGanttView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm = GanttViewModel()
    @State private var selectedProject: GanttProjectReference?
    @State private var timelineViewport = GanttTimelineViewport()
    @State private var timelineResetID: UInt64 = 0

    private struct ReloadKey: Equatable {
        let range: GanttRange
        let periodStart: Date
        let periodEnd: Date
        let mode: GanttActivityMode
        let token: UInt64
        let sessions: SessionsFingerprint
        let codingSurfaceBundleIDs: Set<String>
        let cliHostBundleIDs: Set<String>
    }

    private struct SessionsFingerprint: Equatable {
        let count: Int
        let newestModified: Date?
        let totalFileSize: Int64
        let contentHash: Int
    }

    var body: some View {
        @Bindable var bvm = vm
        let codingSurfaceBundleIDs = env.preferences.effectiveCodingSurfaceBundleIDs
        let cliHostBundleIDs = env.preferences.effectiveCLIHostBundleIDs

        AppScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                controls(
                    range: $bvm.range,
                    mode: $bvm.activityMode,
                    selectedPeriod: vm.periodLabel,
                    canStepForward: vm.canStepForward,
                    isLoading: vm.isLoading,
                    onStepPeriod: vm.stepPeriod,
                    onJumpToToday: vm.jumpToToday
                )

                if vm.activityMode == .assistedFocus && vm.permissionState == .needsFullDiskAccess {
                    permissionGate
                } else {
                    GanttOverviewPanel(snapshot: vm.snapshot)
                    GanttTimelineOverviewPanel(snapshot: vm.snapshot, viewport: $timelineViewport)
                    GanttChartPanel(
                        snapshot: vm.snapshot,
                        emptyMessage: chartEmptyMessage,
                        viewport: $timelineViewport,
                        resetID: timelineResetID
                    ) { project in
                        selectedProject = project
                    }
                    GanttBaselinePanel(comparison: vm.snapshot.baselineComparison)
                    GanttLoadPanel(load: vm.snapshot.load, domain: vm.snapshot.domain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            vm.refreshPermissionState()
        }
        .onChange(of: vm.activityMode) { _, _ in
            vm.refreshPermissionState()
        }
        .task(id: reloadKey(codingSurfaceBundleIDs: codingSurfaceBundleIDs, cliHostBundleIDs: cliHostBundleIDs)) {
            await env.usageLimits.refreshForecasts(sessions: env.store.sessions)
            await vm.reload(
                sessions: env.store.sessions,
                codingSurfaceBundleIDs: codingSurfaceBundleIDs,
                cliHostBundleIDs: cliHostBundleIDs,
                usageLimitReports: Array(env.usageLimits.reports.values),
                usageLimitForecasts: Array(env.usageLimits.forecasts.values)
            )
        }
        .onChange(of: env.usageLimits.reports) { _, reports in
            vm.refreshUsageLimitReports(Array(reports.values))
            Task {
                await env.usageLimits.refreshForecasts(sessions: env.store.sessions)
            }
        }
        .onChange(of: env.usageLimits.forecasts) { _, forecasts in
            vm.refreshUsageLimitForecasts(Array(forecasts.values))
        }
        .onChange(of: vm.range) { _, _ in
            resetTimelineViewport()
        }
        .onChange(of: vm.selectedDate) { _, _ in
            resetTimelineViewport()
        }
        .onChange(of: vm.snapshot.renderRevisionID) { _, _ in
            resetTimelineViewport()
        }
        .task {
            await env.usageLimits.refreshSupportedProviders()
            await env.usageLimits.refreshForecasts(sessions: env.store.sessions)
        }
        .sheet(item: $selectedProject) { project in
            GanttProjectDetailSheet(
                project: project,
                initialMode: vm.activityMode,
                sessions: env.store.sessions,
                usageLimitReports: Array(env.usageLimits.reports.values),
                usageLimitForecasts: Array(env.usageLimits.forecasts.values),
                codingSurfaceBundleIDs: codingSurfaceBundleIDs,
                cliHostBundleIDs: cliHostBundleIDs
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GANTT")
                .font(.sora(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.stxMuted)
            Text("Gantt")
                .font(.sora(24, weight: .semibold))
                .lineLimit(1)
            Text("Tracked project activity across all AI coding tools.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
        }
    }

    private func controls(
        range: Binding<GanttRange>,
        mode: Binding<GanttActivityMode>,
        selectedPeriod: String,
        canStepForward: Bool,
        isLoading: Bool,
        onStepPeriod: @escaping (Int) -> Void,
        onJumpToToday: @escaping () -> Void
    ) -> some View {
        GanttAdaptiveSwitch(compactThreshold: 860) {
            HStack(alignment: .center, spacing: 12) {
                GanttModeChips(mode: mode)
                Spacer(minLength: 12)
                loadingIndicator(isLoading)
                GanttTodayButton(onJumpToToday: onJumpToToday)
                GanttPeriodStepper(
                    range: range,
                    selectedPeriod: selectedPeriod,
                    canStepForward: canStepForward,
                    onStepPeriod: onStepPeriod
                )
                GanttRangeChips(range: range)
            }
        } compact: {
            VStack(alignment: .leading, spacing: 10) {
                GanttModeChips(mode: mode)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    loadingIndicator(isLoading)
                    GanttTodayButton(onJumpToToday: onJumpToToday)
                    GanttPeriodStepper(
                        range: range,
                        selectedPeriod: selectedPeriod,
                        canStepForward: canStepForward,
                        onStepPeriod: onStepPeriod
                    )
                    GanttRangeChips(range: range)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func loadingIndicator(_ isLoading: Bool) -> some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .help(String(localized: "Loading gantt data"))
        }
    }

    private var permissionGate: some View {
        GanttPermissionGate {
            vm.refreshPermissionState()
            vm.bumpReload()
        }
    }

    private var chartEmptyMessage: String? {
        assistedFocusEmptyMessage(
            mode: vm.activityMode,
            focusDataState: vm.focusDataState,
            sourceSessionCount: vm.snapshot.sourceSessionCount,
            scope: .range
        )
    }

    private func reloadKey(
        codingSurfaceBundleIDs: Set<String>,
        cliHostBundleIDs: Set<String>
    ) -> ReloadKey {
        let period = vm.period
        return ReloadKey(
            range: vm.range,
            periodStart: period.domain.start,
            periodEnd: period.domain.end,
            mode: vm.activityMode,
            token: vm.reloadToken,
            sessions: sessionsFingerprint(env.store.sessions),
            codingSurfaceBundleIDs: codingSurfaceBundleIDs,
            cliHostBundleIDs: cliHostBundleIDs
        )
    }

    private func sessionsFingerprint(_ sessions: [Session]) -> SessionsFingerprint {
        var newestModified: Date?
        var totalFileSize: Int64 = 0
        var hasher = Hasher()
        for session in sessions {
            totalFileSize += session.fileSize
            if newestModified == nil || session.lastModified > newestModified! {
                newestModified = session.lastModified
            }
            hasher.combine(session.provider)
            hasher.combine(session.id)
            hasher.combine(session.filePath)
            hasher.combine(session.fileSize)
            hasher.combine(Int((session.lastModified.timeIntervalSinceReferenceDate * 1_000).rounded()))
            hasher.combine(session.stats?.messageCount ?? 0)
            hasher.combine(Int(((session.stats?.lastActivity ?? session.lastModified).timeIntervalSinceReferenceDate * 1_000).rounded()))
        }
        return SessionsFingerprint(
            count: sessions.count,
            newestModified: newestModified,
            totalFileSize: totalFileSize,
            contentHash: hasher.finalize()
        )
    }

    private func resetTimelineViewport() {
        timelineViewport = GanttTimelineViewport()
        timelineResetID &+= 1
    }

}

private struct GanttAdaptiveSwitch<Regular: View, Compact: View>: View {
    let compactThreshold: CGFloat
    @ViewBuilder var regular: () -> Regular
    @ViewBuilder var compact: () -> Compact
    @State private var isCompact = false
    @State private var hasMeasuredWidth = false

    var body: some View {
        Group {
            if isCompact {
                compact()
            } else {
                regular()
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: GanttAdaptiveWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        }
        .onPreferenceChange(GanttAdaptiveWidthPreferenceKey.self) { width in
            guard width.isFinite, width > 0 else { return }

            let nextIsCompact: Bool
            if hasMeasuredWidth {
                guard GanttAdaptiveLayoutMetrics.shouldUpdateCompactState(
                    current: isCompact,
                    width: width,
                    threshold: compactThreshold,
                    hysteresis: GanttAdaptiveLayoutMetrics.compactSwitchHysteresis
                ) else {
                    return
                }
                nextIsCompact = GanttAdaptiveLayoutMetrics.isCompact(width: width, threshold: compactThreshold)
            } else {
                hasMeasuredWidth = true
                nextIsCompact = GanttAdaptiveLayoutMetrics.isCompact(width: width, threshold: compactThreshold)
                guard isCompact != nextIsCompact else { return }
            }

            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isCompact = nextIsCompact
            }
        }
    }
}

private struct GanttAdaptiveWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private struct GanttTodayButton: View {
    let onJumpToToday: () -> Void

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                onJumpToToday()
            }
        } label: {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Go to today"))
        .accessibilityLabel(String(localized: "Go to today"))
    }
}

private struct GanttRangeChips: View {
    @Binding var range: GanttRange

    private static let values: [GanttRange] = [.day, .week, .month]

    var body: some View {
        PillSegmentedBar(
            Self.values,
            selection: $range,
            help: { $0.help },
            accessibilityLabel: { $0.label }
        ) { value, _ in
            Text(value.label)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Gantt range"))
    }
}

private struct GanttModeChips: View {
    @Binding var mode: GanttActivityMode

    var body: some View {
        PillSegmentedBar(
            GanttActivityMode.allCases,
            selection: $mode,
            help: { $0.help },
            accessibilityLabel: { $0.label }
        ) { value, _ in
            Text(value.label)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Gantt activity mode"))
    }
}

private struct GanttPeriodStepper: View {
    @Binding var range: GanttRange
    let selectedPeriod: String
    let canStepForward: Bool
    let onStepPeriod: (Int) -> Void

    var body: some View {
        PillTimeStepperBar(
            canStepForward: canStepForward,
            previousHelp: previousHelp,
            nextHelp: nextHelp,
            centerHelp: centerHelp,
            centerAccessibilityLabel: centerAccessibilityLabel,
            accessibilityLabel: accessibilityLabel,
            onPrevious: { stepSelectedPeriod(-1) },
            onNext: { stepSelectedPeriod(1) }
        ) { _ in
            Text(selectedPeriod)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var previousHelp: String {
        switch range {
        case .day: String(localized: "Previous day")
        case .week: String(localized: "Previous week")
        case .month: String(localized: "Previous month")
        }
    }

    private var nextHelp: String {
        switch range {
        case .day: String(localized: "Next day")
        case .week: String(localized: "Next week")
        case .month: String(localized: "Next month")
        }
    }

    private var centerHelp: String {
        switch range {
        case .day: String(localized: "Selected day")
        case .week: String(localized: "Selected week")
        case .month: String(localized: "Selected month")
        }
    }

    private var centerAccessibilityLabel: String {
        centerHelp
    }

    private var accessibilityLabel: String {
        switch range {
        case .day: String(localized: "Gantt day navigation")
        case .week: String(localized: "Gantt week navigation")
        case .month: String(localized: "Gantt month navigation")
        }
    }

    private func stepSelectedPeriod(_ offset: Int) {
        withAnimation(.easeOut(duration: 0.18)) {
            onStepPeriod(offset)
        }
    }
}

private struct GanttOverviewPanel: View {
    let snapshot: GanttTimelineSnapshot

    var body: some View {
        GanttAdaptiveSwitch(compactThreshold: 760) {
            HStack(spacing: 0) {
                cards
            }
            .mainWindowPanel(padding: 0)
        } compact: {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    projectCard
                    durationCard
                }
                GridRow {
                    segmentCard
                    topProjectCard
                }
            }
            .mainWindowPanel(padding: 0)
        }
    }

    @ViewBuilder
    private var cards: some View {
        projectCard
        Divider().opacity(0.5)
        durationCard
        Divider().opacity(0.5)
        segmentCard
        Divider().opacity(0.5)
        topProjectCard
    }

    private var projectCard: some View {
        StatCard(label: String(localized: "PROJECTS"), value: "\(snapshot.projects.count)")
    }

    private var durationCard: some View {
        StatCard(label: String(localized: "ACTIVE TIME"), value: Format.duration(snapshot.totalDuration))
    }

    private var segmentCard: some View {
        StatCard(label: String(localized: "SEGMENTS"), value: "\(snapshot.segmentCount)")
    }

    private var topProjectCard: some View {
        StatCard(
            label: String(localized: "TOP PROJECT"),
            value: snapshot.mostActiveProject?.displayName ?? "--",
            animatesNumericValue: false
        )
    }
}

private struct GanttBaselinePanel: View {
    let comparison: GanttBaselineComparison?

    var body: some View {
        if let comparison {
            VStack(alignment: .leading, spacing: 12) {
                GanttAdaptiveSwitch(compactThreshold: 540) {
                    HStack(alignment: .firstTextBaseline) {
                        title
                        Spacer(minLength: 12)
                        Text("\(Format.day(comparison.baselineDomain.start)) - \(Format.day(comparison.baselineDomain.end.addingTimeInterval(-1)))")
                            .font(.sora(10).monospacedDigit())
                            .foregroundStyle(Color.stxMuted)
                    }
                } compact: {
                    VStack(alignment: .leading, spacing: 6) {
                        title
                        Text("\(Format.day(comparison.baselineDomain.start)) - \(Format.day(comparison.baselineDomain.end.addingTimeInterval(-1)))")
                            .font(.sora(10).monospacedDigit())
                            .foregroundStyle(Color.stxMuted)
                    }
                }

                HStack(spacing: 0) { deltaCards(comparison) }
            }
            .mainWindowPanel(padding: 16)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BASELINE")
                .font(.sora(13, weight: .semibold))
                .tracking(1.0)
            Text("Compared with the previous 14-day daily average.")
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
        }
    }

    @ViewBuilder
    private func deltaCards(_ comparison: GanttBaselineComparison) -> some View {
        baselineCard("ACTIVE", Format.signedDuration(comparison.activeDurationDelta))
        Divider().opacity(0.5)
        baselineCard("TOKENS", Format.signedTokens(comparison.tokensDelta))
        Divider().opacity(0.5)
        baselineCard("COST", Format.signedCurrency(comparison.costDelta))
        Divider().opacity(0.5)
        baselineCard("COMMITS", Format.signedCount(comparison.commitDelta))
    }

    private func baselineCard(_ label: String, _ value: String) -> some View {
        StatCard(label: label, value: value, animatesNumericValue: false)
    }
}

private struct GanttLoadPanel: View {
    let load: GanttLoadSnapshot
    let domain: DateInterval
    @State private var selectedKind: GanttLoadGroupKind = .provider

    private var selectedGroup: GanttLoadGroup? {
        load.groups.first { $0.kind == selectedKind } ?? load.groups.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summary
            if load.groups.isEmpty {
                Text("No tool or attention load data in this range.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
            } else {
                GanttLoadKindChips(groups: load.groups, selection: $selectedKind)
                if let selectedGroup {
                    GanttLoadLaneList(group: selectedGroup, domain: domain)
                }
            }
        }
        .mainWindowPanel(padding: 16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TOOL / ATTENTION LOAD")
                .font(.sora(13, weight: .semibold))
                .tracking(1.0)
            Text("Provider, model, project, focus, and usage-limit pressure translated into load lanes.")
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summary: some View {
        GanttAdaptiveSwitch(compactThreshold: 940) {
            HStack(spacing: 0) { summaryCards }
        } compact: {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    loadCard("FOCUS BLOCKS", "\(load.summary.focusBlocks)")
                    loadCard("SWITCHES", "\(load.summary.contextSwitches)")
                }
                GridRow {
                    loadCard("TOP LOAD", load.summary.topLoadTitle ?? "--")
                    loadCard("FOCUS SCORE", "\(Int(load.summary.focusScore.rounded()))")
                }
            }
        }
        .background(Color.primary.opacity(0.015), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private var summaryCards: some View {
        loadCard("FOCUS BLOCKS", "\(load.summary.focusBlocks)")
        Divider().opacity(0.5)
        loadCard("SWITCHES", "\(load.summary.contextSwitches)")
        Divider().opacity(0.5)
        loadCard("TOP LOAD", load.summary.topLoadTitle ?? "--")
        Divider().opacity(0.5)
        loadCard("TOKEN PEAK", load.summary.highestTokenWindow.map { "\(Format.shortTime($0.start))" } ?? "--")
        Divider().opacity(0.5)
        loadCard("FOCUS SCORE", "\(Int(load.summary.focusScore.rounded()))")
    }

    private func loadCard(_ label: String, _ value: String) -> some View {
        StatCard(label: label, value: value, animatesNumericValue: false)
    }
}

private struct GanttLoadKindChips: View {
    let groups: [GanttLoadGroup]
    @Binding var selection: GanttLoadGroupKind

    var body: some View {
        PillSegmentedBar(
            groups.map(\.kind),
            selection: $selection,
            help: { $0.label },
            accessibilityLabel: { $0.label }
        ) { value, _ in
            Text(value.label)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct GanttLoadLaneList: View {
    let group: GanttLoadGroup
    let domain: DateInterval

    var body: some View {
        VStack(spacing: 0) {
            ForEach(group.lanes.prefix(8)) { lane in
                GanttLoadLaneRow(lane: lane, domain: domain)
                if lane.id != group.lanes.prefix(8).last?.id {
                    StxRule()
                }
            }
        }
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.stxStroke.opacity(0.55), lineWidth: 1)
        }
    }
}

private struct GanttLoadLaneRow: View {
    let lane: GanttLoadLane
    let domain: DateInterval

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(lane.title)
                    .font(.sora(11, weight: .medium))
                    .lineLimit(1)
                Text(lane.subtitle ?? "\(Format.duration(lane.totalDuration)) · \(lane.tokens) tokens")
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 210, alignment: .leading)

            GanttLoadLaneCanvas(lane: lane, domain: domain)
                .frame(height: 28)

            Text(Format.duration(lane.totalDuration))
                .font(.sora(10).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color.primary.opacity(0.018))
    }
}

private struct GanttLoadLaneCanvas: View {
    let lane: GanttLoadLane
    let domain: DateInterval

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.primary.opacity(0.025)))
            for segment in lane.segments {
                let startX = GanttTimelineScale.ratio(for: segment.interval.start, domain: domain) * size.width
                let endX = GanttTimelineScale.ratio(for: segment.interval.end, domain: domain) * size.width
                let rect = CGRect(x: startX, y: 8, width: max(2, endX - startX), height: 12)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 3),
                    with: .color(Color.stxAccent.opacity(max(0.18, min(0.92, segment.intensity))))
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct GanttProjectDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let project: GanttProjectReference
    let sessions: [Session]
    let usageLimitReports: [UsageLimitReport]
    let usageLimitForecasts: [UsageLimitForecast]
    let codingSurfaceBundleIDs: Set<String>
    let cliHostBundleIDs: Set<String>

    @State private var vm: GanttProjectDetailViewModel

    private struct ReloadKey: Equatable {
        let projectID: String
        let mode: GanttActivityMode
        let token: UInt64
        let sessions: SessionsFingerprint
        let codingSurfaceBundleIDs: Set<String>
        let cliHostBundleIDs: Set<String>
    }

    private struct SessionsFingerprint: Equatable {
        let count: Int
        let newestModified: Date?
        let totalFileSize: Int64
        let contentHash: Int
    }

    init(
        project: GanttProjectReference,
        initialMode: GanttActivityMode,
        sessions: [Session],
        usageLimitReports: [UsageLimitReport],
        usageLimitForecasts: [UsageLimitForecast],
        codingSurfaceBundleIDs: Set<String>,
        cliHostBundleIDs: Set<String>
    ) {
        self.project = project
        self.sessions = sessions
        self.usageLimitReports = usageLimitReports
        self.usageLimitForecasts = usageLimitForecasts
        self.codingSurfaceBundleIDs = codingSurfaceBundleIDs
        self.cliHostBundleIDs = cliHostBundleIDs
        _vm = State(initialValue: GanttProjectDetailViewModel(initialMode: initialMode))
    }

    var body: some View {
        @Bindable var bvm = vm

        VStack(spacing: 0) {
            header(mode: $bvm.activityMode)
            StxRule()
            content
        }
        .frame(minWidth: 1_040, idealWidth: 1_220, minHeight: 600, idealHeight: 740)
        .background(AppSurface.panelFill)
        .onAppear {
            vm.refreshPermissionState()
        }
        .onChange(of: vm.activityMode) { _, _ in
            vm.refreshPermissionState()
        }
        .task(id: reloadKey) {
            await vm.reload(
                projectID: project.id,
                sessions: sessions,
                usageLimitReports: usageLimitReports,
                usageLimitForecasts: usageLimitForecasts,
                codingSurfaceBundleIDs: codingSurfaceBundleIDs,
                cliHostBundleIDs: cliHostBundleIDs
            )
        }
        .onChange(of: usageLimitReports) { _, reports in
            vm.refreshUsageLimitReports(reports)
        }
        .onChange(of: usageLimitForecasts) { _, forecasts in
            vm.refreshUsageLimitForecasts(forecasts)
        }
    }

    private var reloadKey: ReloadKey {
        ReloadKey(
            projectID: project.id,
            mode: vm.activityMode,
            token: vm.reloadToken,
            sessions: sessionsFingerprint(sessions),
            codingSurfaceBundleIDs: codingSurfaceBundleIDs,
            cliHostBundleIDs: cliHostBundleIDs
        )
    }

    private func sessionsFingerprint(_ sessions: [Session]) -> SessionsFingerprint {
        var newestModified: Date?
        var totalFileSize: Int64 = 0
        var hasher = Hasher()
        for session in sessions {
            totalFileSize += session.fileSize
            if newestModified == nil || session.lastModified > newestModified! {
                newestModified = session.lastModified
            }
            hasher.combine(session.provider)
            hasher.combine(session.id)
            hasher.combine(session.filePath)
            hasher.combine(session.fileSize)
            hasher.combine(Int((session.lastModified.timeIntervalSinceReferenceDate * 1_000).rounded()))
            hasher.combine(session.stats?.messageCount ?? 0)
            hasher.combine(Int(((session.stats?.lastActivity ?? session.lastModified).timeIntervalSinceReferenceDate * 1_000).rounded()))
        }
        return SessionsFingerprint(
            count: sessions.count,
            newestModified: newestModified,
            totalFileSize: totalFileSize,
            contentHash: hasher.finalize()
        )
    }

    private func header(mode: Binding<GanttActivityMode>) -> some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: AppIcon.Action.close)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Close project detail"))

            Image(systemName: AppIcon.Workspace.gantt)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.stxAccent)
                .frame(width: 26, height: 26)
                .background(Color.stxAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(project.displayName)
                    .font(.sora(14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(project.displayName)

                HStack(spacing: 6) {
                    GanttProviderBadges(providers: project.providerList)
                    Text(project.path ?? String(localized: "No project path"))
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(project.path ?? "")
                }
            }

            Spacer(minLength: 12)

            GanttModeChips(mode: mode)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 14) {
                detailIntro

                if vm.activityMode == .assistedFocus && vm.permissionState == .needsFullDiskAccess {
                    GanttPermissionGate {
                        vm.refreshPermissionState()
                        vm.bumpReload()
                    }
                } else {
                    GanttProjectDetailSummaryPanel(snapshot: vm.snapshot)
                    GanttBaselinePanel(comparison: vm.snapshot.baselineComparison)
                    GanttProjectSevenDayChartPanel(
                        snapshot: vm.snapshot,
                        project: project,
                        emptyMessage: detailEmptyMessage
                    )
                    GanttLoadPanel(load: vm.snapshot.load, domain: vm.snapshot.domain)
                }
            }
            .padding(16)
        }
    }

    private var detailIntro: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("PROJECT DETAIL")
                .font(.sora(11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.stxMuted)
            Text(rangeLabel)
                .font(.sora(11).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
            Spacer(minLength: 0)
            if vm.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .help(String(localized: "Loading gantt data"))
            }
        }
    }

    private var rangeLabel: String {
        "\(Format.day(vm.period.domain.start)) - \(Format.day(vm.period.domain.end.addingTimeInterval(-1)))"
    }

    private var detailEmptyMessage: String {
        assistedFocusEmptyMessage(
            mode: vm.activityMode,
            focusDataState: vm.focusDataState,
            sourceSessionCount: vm.snapshot.sourceSessionCount,
            scope: .project
        ) ?? String(localized: "No activity for this project in the last seven days.")
    }
}

private enum GanttEmptyScope {
    case range
    case project
}

private func assistedFocusEmptyMessage(
    mode: GanttActivityMode,
    focusDataState: GanttFocusDataState,
    sourceSessionCount: Int,
    scope: GanttEmptyScope
) -> String? {
    guard mode == .assistedFocus else { return nil }
    guard sourceSessionCount > 0 else { return nil }

    switch focusDataState {
    case .noMatchingFocusData:
        return String(localized: "No Screen Time focus data matched the configured coding surfaces or terminal hosts in this range. Add your editor or terminal in Tracking settings, or verify Screen Time is recording app usage.")
    case .queryFailed:
        return String(localized: "Could not read Screen Time focus data for this range.")
    case .available:
        switch scope {
        case .range:
            return String(localized: "No AI activity overlapped the configured coding surfaces or terminal hosts in this range.")
        case .project:
            return String(localized: "No AI activity for this project overlapped the configured coding surfaces or terminal hosts in the last seven days.")
        }
    }
}

private struct GanttProjectDetailSummaryPanel: View {
    let snapshot: GanttTimelineSnapshot

    var body: some View {
        GanttAdaptiveSwitch(compactThreshold: 760) {
            HStack(spacing: 0) {
                cards
            }
            .mainWindowPanel(padding: 0)
        } compact: {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    durationCard
                    segmentCard
                }
                GridRow {
                    latestCard
                    modeCard
                }
            }
            .mainWindowPanel(padding: 0)
        }
    }

    @ViewBuilder
    private var cards: some View {
        durationCard
        Divider().opacity(0.5)
        segmentCard
        Divider().opacity(0.5)
        latestCard
        Divider().opacity(0.5)
        modeCard
    }

    private var durationCard: some View {
        StatCard(label: String(localized: "ACTIVE TIME"), value: Format.duration(snapshot.totalDuration))
    }

    private var segmentCard: some View {
        StatCard(label: String(localized: "SEGMENTS"), value: "\(snapshot.segmentCount)")
    }

    private var latestCard: some View {
        StatCard(
            label: String(localized: "LATEST ACTIVITY"),
            value: snapshot.mostActiveProject.map { Format.shortDate($0.latestActivity) } ?? "--",
            animatesNumericValue: false
        )
    }

    private var modeCard: some View {
        StatCard(
            label: String(localized: "MODE"),
            value: snapshot.activityMode.label,
            animatesNumericValue: false
        )
    }
}

private struct GanttProjectSevenDayChartPanel: View {
    let snapshot: GanttTimelineSnapshot
    let project: GanttProjectReference
    let emptyMessage: String

    private let leftColumnWidth: CGFloat = 210
    private let headerHeight: CGFloat = 42
    private let rowHeight: CGFloat = 54
    private let preferredTimelineWidth: CGFloat = 940

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader

            if timeline == nil {
                emptyState
            } else {
                chart
            }
        }
        .mainWindowPanel(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Recent 7 days"))
    }

    private var timeline: GanttProjectTimeline? {
        snapshot.projects.first(where: { $0.id == project.id }) ?? snapshot.projects.first
    }

    private var rows: [GanttProjectDayTimelineRow] {
        GanttProjectDayTimelineRow.makeRows(
            domain: snapshot.domain,
            segments: timeline?.segments.map(\.interval) ?? []
        )
    }

    private var panelHeader: some View {
        GanttAdaptiveSwitch(compactThreshold: 560) {
            HStack(alignment: .firstTextBaseline) {
                recentSevenDayTitle
                Spacer(minLength: 12)
                Text(rangeLabel)
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
        } compact: {
            VStack(alignment: .leading, spacing: 6) {
                recentSevenDayTitle
                Text(rangeLabel)
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
        }
    }

    private var recentSevenDayTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RECENT 7 DAYS")
                .font(.sora(13, weight: .semibold))
                .tracking(1.0)
            Text("Single project activity for the last seven local days.")
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rangeLabel: String {
        "\(Format.day(snapshot.domain.start)) - \(Format.day(snapshot.domain.end.addingTimeInterval(-1)))"
    }

    private var emptyState: some View {
        Text(emptyMessage)
            .font(.sora(12))
            .foregroundStyle(Color.stxMuted)
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
    }

    private var chart: some View {
        let rows = rows
        let rowsHeight = CGFloat(rows.count) * rowHeight
        let totalHeight = headerHeight + rowsHeight

        return GeometryReader { proxy in
            let timelineWidth = max(proxy.size.width - leftColumnWidth - 1, preferredTimelineWidth)

            HStack(alignment: .top, spacing: 0) {
                dayColumn(rows: rows)
                    .frame(width: leftColumnWidth)

                AppScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        GanttDayTimelineHeader()
                            .frame(width: timelineWidth, height: headerHeight)
                        GanttDayTimelineCanvas(rows: rows, rowHeight: rowHeight)
                            .frame(width: timelineWidth, height: rowsHeight)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
        .frame(height: totalHeight)
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1)
        }
    }

    private func dayColumn(rows: [GanttProjectDayTimelineRow]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Day")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.stxMuted)
                Spacer()
                Text("Active")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(.horizontal, 12)
            .frame(height: headerHeight)
            .background(Color.primary.opacity(0.035))

            ForEach(rows) { row in
                GanttProjectDayRow(row: row)
                    .frame(height: rowHeight)

                if row.id != rows.last?.id {
                    StxRule()
                }
            }
        }
        .background(Color.primary.opacity(0.02))
    }
}

private struct GanttProjectDayTimelineRow: Equatable, Identifiable, Sendable {
    let id: String
    let interval: DateInterval
    let segments: [DateInterval]

    var totalDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }

    static func makeRows(
        domain: DateInterval,
        segments: [DateInterval],
        calendar: Calendar = .current
    ) -> [GanttProjectDayTimelineRow] {
        var cursor = calendar.startOfDay(for: domain.start)
        var rows: [GanttProjectDayTimelineRow] = []

        while cursor < domain.end {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: cursor)
                ?? cursor.addingTimeInterval(86_400)
            let intervalEnd = min(dayEnd, domain.end)
            guard intervalEnd > cursor else { break }

            let dayInterval = DateInterval(start: cursor, end: intervalEnd)
            let visibleSegments = segments.compactMap {
                ActivityAnalyzer.clip($0, to: dayInterval)
            }
            rows.append(GanttProjectDayTimelineRow(
                id: "\(cursor.timeIntervalSinceReferenceDate)",
                interval: dayInterval,
                segments: visibleSegments
            ))
            cursor = dayEnd
        }

        return rows
    }
}

private struct GanttProjectDayRow: View {
    let row: GanttProjectDayTimelineRow

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Format.day(row.interval.start))
                    .font(.sora(12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(row.interval.start.formatted(.dateTime.weekday(.wide)))
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(Format.duration(row.totalDuration))
                .font(.sora(11, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format(
            "gantt.day.accessibility.active",
            defaultValue: "%@, %@ active",
            Format.day(row.interval.start),
            Format.duration(row.totalDuration)
        ))
    }
}

private struct GanttDayTimelineHeader: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.primary.opacity(0.035)))

            for tick in GanttDayTimelineScale.ticks {
                let x = GanttDayTimelineScale.x(forHour: tick.hour, width: size.width)
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height - 12))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(Color.stxStroke), lineWidth: 1)

                let anchor: UnitPoint = tick.hour >= 24 ? .trailing : .leading
                let labelX = tick.hour >= 24 ? size.width - 4 : min(max(x + 4, 4), size.width - 24)
                context.draw(
                    Text(tick.label)
                        .font(.sora(9))
                        .foregroundStyle(Color.stxMuted),
                    at: CGPoint(x: labelX, y: 11),
                    anchor: anchor
                )
            }

            var bottom = Path()
            bottom.move(to: CGPoint(x: 0, y: size.height - 0.5))
            bottom.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(bottom, with: .color(Color.stxStroke.opacity(0.8)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct GanttDayTimelineCanvas: View {
    let rows: [GanttProjectDayTimelineRow]
    let rowHeight: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            drawGrid(context: &context, size: size)
            drawBars(context: &context, size: size)
            drawTodayLine(context: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        for index in 0...rows.count {
            let y = CGFloat(index) * rowHeight
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(Color.stxStroke.opacity(0.55)), lineWidth: 1)
        }

        for hour in stride(from: 0, through: 24, by: 1) {
            let x = GanttDayTimelineScale.x(forHour: hour, width: size.width)
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            let isMajor = hour % 6 == 0
            context.stroke(
                line,
                with: .color(Color.stxStroke.opacity(isMajor ? 0.72 : 0.26)),
                lineWidth: isMajor ? 1 : 0.5
            )
        }
    }

    private func drawBars(context: inout GraphicsContext, size: CGSize) {
        for (index, row) in rows.enumerated() {
            let y = CGFloat(index) * rowHeight + (rowHeight - 13) / 2

            for segment in row.segments {
                let startX = GanttDayTimelineScale.x(for: segment.start, in: row.interval, width: size.width)
                let endX = GanttDayTimelineScale.x(for: segment.end, in: row.interval, width: size.width)
                let width = min(size.width - startX, max(3, endX - startX))
                guard width > 0 else { continue }

                let rect = CGRect(x: startX, y: y, width: width, height: 13)
                context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(Color.stxAccent.opacity(0.86)))
                context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3.5), with: .color(Color.stxAccent), lineWidth: 1)
            }
        }
    }

    private func drawTodayLine(context: inout GraphicsContext, size: CGSize) {
        let now = Date.now
        guard let index = rows.firstIndex(where: { Calendar.current.isDate(now, inSameDayAs: $0.interval.start) }) else {
            return
        }
        let row = rows[index]
        let x = GanttDayTimelineScale.x(for: now, in: row.interval, width: size.width)
        let startY = CGFloat(index) * rowHeight
        let endY = startY + rowHeight
        var line = Path()
        line.move(to: CGPoint(x: x, y: startY))
        line.addLine(to: CGPoint(x: x, y: endY))
        context.stroke(line, with: .color(Color.stxAccent.opacity(0.72)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
    }
}

private struct GanttDayTick: Sendable {
    let hour: Int
    let label: String
}

private enum GanttDayTimelineScale {
    static let ticks: [GanttDayTick] = [
        GanttDayTick(hour: 0, label: "00"),
        GanttDayTick(hour: 6, label: "06"),
        GanttDayTick(hour: 12, label: "12"),
        GanttDayTick(hour: 18, label: "18"),
        GanttDayTick(hour: 24, label: "24"),
    ]

    static func x(forHour hour: Int, width: CGFloat) -> CGFloat {
        min(width, max(0, width * CGFloat(hour) / 24))
    }

    static func x(for date: Date, in day: DateInterval, width: CGFloat, calendar: Calendar = .current) -> CGFloat {
        if date <= day.start {
            return 0
        }
        if date >= day.end {
            return width
        }

        guard day.duration > 0 else { return 0 }
        let seconds = date.timeIntervalSince(day.start)
        return min(width, max(0, width * CGFloat(seconds / day.duration)))
    }
}

private struct GanttPermissionGate: View {
    let onRecheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("FULL DISK ACCESS REQUIRED")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer()
                Image(systemName: AppIcon.Status.lockShield)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                    .accessibilityHidden(true)
            }

            Text("Assisted Focus mode needs macOS Screen Time access to tell whether an editor or terminal was in front.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Open Full Disk Access settings") {
                    openFullDiskAccessSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Re-check") {
                    onRecheck()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .font(.sora(11))
        }
        .mainWindowPanel(padding: 16)
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct GanttChartPanel: View {
    let snapshot: GanttTimelineSnapshot
    var title: LocalizedStringKey = "PROJECT TIMELINE"
    var captionOverride: String?
    var emptyMessage: String?
    @Binding var viewport: GanttTimelineViewport
    var resetID: UInt64 = 0
    var onSelectProject: ((GanttProjectReference) -> Void)?
    @State private var cachedRenderPlanKey: GanttTimelineRenderPlan.Key?
    @State private var cachedRenderPlan: GanttTimelineRenderPlan?
    @State private var selectedSegment: GanttTimelinePopoverSelection?

    private let leftColumnWidth: CGFloat = 260
    private let headerHeight: CGFloat = 42
    private let rowHeight: CGFloat = 46

    var body: some View {
        let renderPlanKey = GanttTimelineRenderPlan.Key(snapshot: snapshot)
        let renderPlan = cachedRenderPlanKey == renderPlanKey
            ? (cachedRenderPlan ?? makeRenderPlan(key: renderPlanKey))
            : makeRenderPlan(key: renderPlanKey)

        return VStack(alignment: .leading, spacing: 12) {
            panelHeader

            if snapshot.isEmpty {
                emptyState
            } else {
                chart(renderPlan)
                GanttTimelineLegend(renderPlan: renderPlan)
            }
        }
        .mainWindowPanel(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Gantt"))
        .onAppear { cacheRenderPlanIfNeeded(renderPlanKey) }
        .onChange(of: renderPlanKey) { _, newKey in
            selectedSegment = nil
            cacheRenderPlanIfNeeded(newKey)
        }
        .onChange(of: resetID) { _, _ in
            selectedSegment = nil
        }
    }

    private var panelHeader: some View {
        GanttAdaptiveSwitch(compactThreshold: 560) {
            HStack(alignment: .firstTextBaseline) {
                chartTitle
                Spacer(minLength: 12)
                Text(rangeLabel)
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
        } compact: {
            VStack(alignment: .leading, spacing: 6) {
                chartTitle
                Text(rangeLabel)
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
        }
    }

    private var chartTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.sora(13, weight: .semibold))
                .tracking(1.0)
            Text(caption)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var caption: String {
        if let captionOverride {
            return captionOverride
        }
        switch snapshot.activityMode {
        case .aiActive:
            return String(localized: "Each row merges project activity blocks from sessions across all providers.")
        case .assistedFocus:
            return String(localized: "Assisted Focus = AI was active while an editor or terminal was in front. It is not precise Screen Time project attribution.")
        }
    }

    private var rangeLabel: String {
        "\(Format.day(snapshot.domain.start)) - \(Format.day(snapshot.domain.end.addingTimeInterval(-1)))"
    }

    private var emptyState: some View {
        Text(emptyMessage ?? (snapshot.sourceSessionCount == 0 ? String(localized: "No tracked project sessions yet.") : String(localized: "No project activity in this range.")))
            .font(.sora(12))
            .foregroundStyle(Color.stxMuted)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
    }

    private func chart(_ renderPlan: GanttTimelineRenderPlan) -> some View {
        let rowsHeight = CGFloat(renderPlan.rows.count) * rowHeight
        let totalHeight = headerHeight + rowsHeight

        return GeometryReader { proxy in
            let rawTimelineWidth = max(0, proxy.size.width - leftColumnWidth - 1)
            let timelineWidth = GanttTimelineViewportMetrics.contentWidth(
                range: renderPlan.range,
                domain: renderPlan.domain,
                viewportWidth: rawTimelineWidth
            )

            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 0) {
                    projectColumn(renderPlan)
                        .frame(width: leftColumnWidth)

                    GanttHorizontalTimelineScrollView(
                        contentWidth: timelineWidth,
                        contentHeight: totalHeight,
                        contentRevisionID: renderPlan.contentRevisionID,
                        viewport: $viewport
                    ) {
                        GanttTimelineDocument(
                            renderPlan: renderPlan,
                            headerHeight: headerHeight,
                            rowHeight: rowHeight,
                            rowsHeight: rowsHeight,
                            selectedSegment: $selectedSegment
                        )
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: totalHeight, maxHeight: totalHeight)
                }
            }
        }
        .frame(height: totalHeight)
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1)
        }
    }

    private func projectColumn(_ renderPlan: GanttTimelineRenderPlan) -> some View {
        LazyVStack(spacing: 0) {
            HStack {
                Text("Project")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.stxMuted)
                Spacer()
                Text("Active")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(.horizontal, 12)
            .frame(height: headerHeight)
            .background(Color.primary.opacity(0.035))

            ForEach(renderPlan.rows) { row in
                Group {
                    if let onSelectProject {
                        GanttProjectSelectableRow(row: row, onSelect: onSelectProject)
                    } else {
                        GanttProjectRow(row: row)
                    }
                }
                .frame(height: rowHeight)

                if row.id != renderPlan.rows.last?.id {
                    StxRule()
                }
            }
        }
        .background(Color.primary.opacity(0.02))
    }

    private func makeRenderPlan(key: GanttTimelineRenderPlan.Key) -> GanttTimelineRenderPlan {
        GanttTimelineRenderPlan(key: key, snapshot: snapshot)
    }

    private func cacheRenderPlanIfNeeded(_ key: GanttTimelineRenderPlan.Key) {
        guard cachedRenderPlanKey != key else { return }
        cachedRenderPlan = makeRenderPlan(key: key)
        cachedRenderPlanKey = key
    }
}

private struct GanttTimelineRenderPlan {
    struct Key: Equatable {
        let revisionID: String
        let annotationID: String

        init(snapshot: GanttTimelineSnapshot) {
            self.revisionID = snapshot.renderRevisionID
            self.annotationID = Self.annotationID(for: snapshot)
        }

        private static func annotationID(for snapshot: GanttTimelineSnapshot) -> String {
            let peak = snapshot.load.summary.highestTokenWindow.map {
                "peak:\(timeID($0.start))-\(timeID($0.end)):\(snapshot.load.summary.highestTokenWindowTokens)"
            } ?? "peak:none"
            let usage = snapshot.load.groups
                .first { $0.kind == .usageLimit }?
                .lanes
                .flatMap { lane in
                    lane.segments.map {
                        "\(lane.id):\(timeID($0.interval.start))-\(timeID($0.interval.end)):\(Int(($0.intensity * 100).rounded()))"
                    }
                }
                .joined(separator: ",") ?? "usage:none"
            let forecasts = snapshot.usageLimitForecasts
                .map { forecast in
                    let interval = forecast.reachInterval.map {
                        "\(timeID($0.start))-\(timeID($0.end))"
                    } ?? "none"
                    return "\(forecast.id):\(forecast.horizon.rawValue):\(forecast.status.rawValue):\(interval)"
                }
                .joined(separator: ",")
            let commits = snapshot.commitMarkers
                .map { "\($0.projectID):\($0.id):\(timeID($0.date))" }
                .joined(separator: ",")
            return [peak, usage, forecasts, commits].joined(separator: "|")
        }

        private static func timeID(_ date: Date) -> String {
            String(Int((date.timeIntervalSinceReferenceDate * 1_000).rounded()))
        }
    }

    struct Tick {
        let ratio: CGFloat
        let label: String
        let isMajor: Bool
    }

    struct Segment {
        let id: String
        let startRatio: CGFloat
        let endRatio: CGFloat
        let tokenIntensity: Double
        let focusRatio: Double
        let detail: SegmentDetail
    }

    struct SegmentDetail: Equatable, Identifiable {
        let id: String
        let projectName: String
        let projectPath: String
        let interval: DateInterval
        let providers: [ProviderKind]
        let sessionCount: Int
        let sessionTitles: [String]
        let models: [GanttModelMetric]
        let tokens: Int
        let cost: Double
        let messageCount: Int
        let focusOverlapDuration: TimeInterval

        var duration: TimeInterval { interval.duration }
    }

    struct TokenPeak {
        let startRatio: CGFloat
        let endRatio: CGFloat
        let tokens: Int
    }

    struct UsageLimitBand: Identifiable {
        let id: String
        let title: String
        let startRatio: CGFloat
        let endRatio: CGFloat
        let intensity: Double
    }

    struct LimitReachForecastBand: Identifiable {
        let id: String
        let title: String
        let startRatio: CGFloat
        let endRatio: CGFloat
        let confidence: UsageLimitForecastConfidence
        let horizon: UsageLimitForecastHorizon
    }

    struct HitTarget: Identifiable {
        let id: String
        let rowIndex: Int
        let startRatio: CGFloat
        let endRatio: CGFloat
        let detail: SegmentDetail
    }

    struct CommitMarker: Identifiable {
        let id: String
        let ratio: CGFloat
        let label: String
    }

    struct Row: Identifiable {
        let id: String
        let index: Int
        let displayName: String
        let pathText: String
        let providers: [ProviderKind]
        let durationText: String
        let accessibilityLabel: String
        let reference: GanttProjectReference
        let colorProvider: ProviderKind?
        let fallbackColorIndex: Int
        let segments: [Segment]
        let commitMarkers: [CommitMarker]
    }

    let key: Key
    let range: GanttRange
    let domain: DateInterval
    let ticks: [Tick]
    let rows: [Row]
    let hitTargets: [HitTarget]
    let providers: [ProviderKind]
    let tokenPeak: TokenPeak?
    let usageLimitBands: [UsageLimitBand]
    let limitReachForecastBands: [LimitReachForecastBand]

    init(key: Key, snapshot: GanttTimelineSnapshot) {
        self.key = key
        self.range = snapshot.range
        self.domain = snapshot.domain
        self.ticks = GanttTimelineScale.ticks(for: snapshot.range, domain: snapshot.domain).map { tick in
            Tick(
                ratio: GanttTimelineScale.ratio(for: tick.date, domain: snapshot.domain),
                label: tick.label,
                isMajor: tick.isMajor
            )
        }
        self.providers = ProviderKind.allCases.filter { provider in
            snapshot.projects.contains { $0.providers.contains(provider) }
        }
        let maxSegmentTokens = max(
            1,
            snapshot.projects.flatMap(\.segments).map { $0.usage.total }.max() ?? 0
        )
        self.tokenPeak = snapshot.load.summary.highestTokenWindow.map {
            TokenPeak(
                startRatio: GanttTimelineScale.ratio(for: $0.start, domain: snapshot.domain),
                endRatio: GanttTimelineScale.ratio(for: $0.end, domain: snapshot.domain),
                tokens: snapshot.load.summary.highestTokenWindowTokens
            )
        }
        self.usageLimitBands = snapshot.load.groups
            .first { $0.kind == .usageLimit }?
            .lanes
            .filter { !Self.isCoreForecastUsageLimitLane($0) }
            .flatMap { lane in
                lane.segments.map { segment in
                    UsageLimitBand(
                        id: "\(lane.id)|\(segment.id)",
                        title: lane.title,
                        startRatio: GanttTimelineScale.ratio(for: segment.interval.start, domain: snapshot.domain),
                        endRatio: GanttTimelineScale.ratio(for: segment.interval.end, domain: snapshot.domain),
                        intensity: segment.intensity
                    )
                }
            } ?? []
        self.limitReachForecastBands = snapshot.usageLimitForecasts.compactMap { forecast in
            guard forecast.status == .forecast,
                  let reachInterval = forecast.reachInterval,
                  let clipped = ActivityAnalyzer.clip(reachInterval, to: snapshot.domain) else {
                return nil
            }
            return LimitReachForecastBand(
                id: forecast.id,
                title: "\(forecast.provider.shortName) \(forecast.label)",
                startRatio: GanttTimelineScale.ratio(for: clipped.start, domain: snapshot.domain),
                endRatio: GanttTimelineScale.ratio(for: clipped.end, domain: snapshot.domain),
                confidence: forecast.confidence,
                horizon: forecast.horizon
            )
        }
        let commitMarkersByProjectID = Dictionary(grouping: snapshot.commitMarkers, by: \.projectID)
        var hitTargets: [HitTarget] = []
        self.rows = snapshot.projects.enumerated().map { index, project in
            let providerList = project.providerList
            let durationText = Format.duration(project.totalDuration)
            let commitMarkers = (commitMarkersByProjectID[project.id] ?? [])
                .sorted { lhs, rhs in
                    if lhs.date != rhs.date { return lhs.date > rhs.date }
                    return lhs.id < rhs.id
                }
                .map {
                    CommitMarker(
                        id: $0.id,
                        ratio: GanttTimelineScale.ratio(for: $0.date, domain: snapshot.domain),
                        label: "\($0.shortHash) \($0.subject)"
                    )
                }
            let segments = project.segments.map { segment in
                let focusRatio = segment.duration > 0
                    ? min(1, max(0, segment.focusOverlapDuration / segment.duration))
                    : 0
                let detail = SegmentDetail(
                    id: segment.id,
                    projectName: project.displayName,
                    projectPath: project.path ?? String(localized: "No project path"),
                    interval: segment.interval,
                    providers: segment.providerList,
                    sessionCount: segment.sessionIDs.count,
                    sessionTitles: segment.sessionTitles,
                    models: segment.models,
                    tokens: segment.usage.total,
                    cost: segment.cost,
                    messageCount: segment.messageCount,
                    focusOverlapDuration: segment.focusOverlapDuration
                )
                let startRatio = GanttTimelineScale.ratio(for: segment.interval.start, domain: snapshot.domain)
                let endRatio = GanttTimelineScale.ratio(for: segment.interval.end, domain: snapshot.domain)
                hitTargets.append(
                    HitTarget(
                        id: "\(project.id)|\(segment.id)",
                        rowIndex: index,
                        startRatio: startRatio,
                        endRatio: endRatio,
                        detail: detail
                    )
                )
                return Segment(
                    id: segment.id,
                    startRatio: startRatio,
                    endRatio: endRatio,
                    tokenIntensity: min(1, max(0.12, Double(segment.usage.total) / Double(maxSegmentTokens))),
                    focusRatio: focusRatio,
                    detail: detail
                )
            }
            return Row(
                id: project.id,
                index: index,
                displayName: project.displayName,
                pathText: project.path ?? String(localized: "No project path"),
                providers: providerList,
                durationText: durationText,
                accessibilityLabel: L10n.format(
                    "gantt.project.accessibility.active",
                    defaultValue: "%@, %@ active",
                    project.displayName,
                    durationText
                ),
                reference: project.reference,
                colorProvider: providerList.first,
                fallbackColorIndex: index,
                segments: segments,
                commitMarkers: commitMarkers
            )
        }
        self.hitTargets = hitTargets
    }

    private static func isCoreForecastUsageLimitLane(_ lane: GanttLoadLane) -> Bool {
        lane.id == "codex|primary"
            || lane.id == "claude|five_hour"
            || lane.id == "codex|secondary"
            || lane.id == "claude|seven_day"
    }

    var contentRevisionID: String {
        "\(key.revisionID)|\(key.annotationID)"
    }

    func ratio(for date: Date) -> CGFloat {
        GanttTimelineScale.ratio(for: date, domain: domain)
    }
}

private struct GanttTimelinePopoverSelection: Equatable {
    let segmentID: String
    let detail: GanttTimelineRenderPlan.SegmentDetail
}

private struct GanttSegmentPopoverSource: NSViewRepresentable {
    @Binding var selectedSegment: GanttTimelinePopoverSelection?
    let anchorPoint: CGPoint?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> FlippedPopoverSourceView {
        let view = FlippedPopoverSourceView()
        view.postsFrameChangedNotifications = true
        return view
    }

    func updateNSView(_ nsView: FlippedPopoverSourceView, context: Context) {
        context.coordinator.selectedSegment = $selectedSegment
        context.coordinator.update(
            selection: selectedSegment,
            anchorPoint: anchorPoint,
            in: nsView
        )
    }

    static func dismantleNSView(_ nsView: FlippedPopoverSourceView, coordinator: Coordinator) {
        coordinator.closeFromViewRemoval()
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        private struct PendingPresentation {
            let selection: GanttTimelinePopoverSelection
            let sourceRect: CGRect
        }

        var selectedSegment: Binding<GanttTimelinePopoverSelection?>?
        private var popover: NSPopover?
        private var hostingController: NSHostingController<GanttSegmentInspector>?
        private var presentedSelectionID: String?
        private var pendingPresentation: PendingPresentation?
        private weak var pendingSourceView: FlippedPopoverSourceView?
        private var pendingPresentationTask: Task<Void, Never>?
        private var programmaticCloseIDs: Set<ObjectIdentifier> = []

        deinit {
            pendingPresentationTask?.cancel()
        }

        func update(
            selection: GanttTimelinePopoverSelection?,
            anchorPoint: CGPoint?,
            in sourceView: FlippedPopoverSourceView
        ) {
            guard let selection,
                  let anchorPoint,
                  anchorPoint.x.isFinite,
                  anchorPoint.y.isFinite
            else {
                closeFromSelectionChange()
                return
            }

            guard sourceView.window != nil else { return }
            let sourceRect = Self.sourceRect(for: anchorPoint)
            guard sourceRect.width > 0, sourceRect.height > 0 else { return }

            if let popover, popover.isShown, presentedSelectionID != selection.segmentID {
                pendingPresentation = PendingPresentation(selection: selection, sourceRect: sourceRect)
                pendingSourceView = sourceView
                pendingPresentationTask?.cancel()
                closePopoverForPendingPresentation(popover)
                return
            }

            let popover = ensurePopover(for: selection.detail)
            updateContentSize(popover)
            presentedSelectionID = selection.segmentID
            if popover.isShown {
                popover.positioningRect = sourceRect
                return
            }
            let popoverToShow = self.popover ?? ensurePopover(for: selection.detail)
            popoverToShow.show(relativeTo: sourceRect, of: sourceView, preferredEdge: .minY)
            if popoverToShow.delegate == nil {
                popoverToShow.delegate = self
            }
            self.popover = popoverToShow
        }

        func closeFromSelectionChange() {
            cancelPendingPresentation()
            closeActivePopover()
        }

        func closeFromViewRemoval() {
            cancelPendingPresentation()
            closeActivePopover()
        }

        func popoverDidClose(_ notification: Notification) {
            guard let closedPopover = notification.object as? NSPopover else { return }

            let closeID = ObjectIdentifier(closedPopover)
            if programmaticCloseIDs.remove(closeID) != nil {
                if closedPopover === popover {
                    popover = nil
                    hostingController = nil
                    presentedSelectionID = nil
                }
                if pendingPresentation != nil {
                    schedulePendingPresentation()
                }
                return
            }

            guard closedPopover === popover else { return }
            let closedSelectionID = presentedSelectionID
            popover = nil
            hostingController = nil
            presentedSelectionID = nil
            if selectedSegment?.wrappedValue?.segmentID == closedSelectionID {
                selectedSegment?.wrappedValue = nil
            }
        }

        private func cancelPendingPresentation() {
            pendingPresentationTask?.cancel()
            pendingPresentationTask = nil
            pendingPresentation = nil
            pendingSourceView = nil
        }

        private func closeActivePopover() {
            presentedSelectionID = nil
            guard let popover else { return }
            self.popover = nil
            hostingController = nil
            closePopover(popover)
        }

        private func closePopoverForPendingPresentation(_ popover: NSPopover) {
            if popover === self.popover {
                self.popover = nil
                hostingController = nil
                presentedSelectionID = nil
            }
            closePopover(popover)
            if !popover.isShown {
                schedulePendingPresentation()
            }
        }

        private func closePopover(_ popover: NSPopover) {
            let closeID = ObjectIdentifier(popover)
            programmaticCloseIDs.insert(closeID)
            popover.close()
            if !popover.isShown {
                programmaticCloseIDs.remove(closeID)
            }
        }

        private func schedulePendingPresentation() {
            pendingPresentationTask?.cancel()
            pendingPresentationTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled else { return }
                self?.presentPendingSelection()
            }
        }

        private func presentPendingSelection() {
            pendingPresentationTask = nil
            guard let pendingPresentation else { return }
            guard selectedSegment?.wrappedValue?.segmentID == pendingPresentation.selection.segmentID,
                  let sourceView = pendingSourceView,
                  sourceView.window != nil
            else {
                cancelPendingPresentation()
                return
            }

            let popover = ensurePopover(for: pendingPresentation.selection.detail)
            updateContentSize(popover)
            presentedSelectionID = pendingPresentation.selection.segmentID
            let sourceRect = pendingPresentation.sourceRect
            self.pendingPresentation = nil
            pendingSourceView = nil

            if popover.isShown {
                popover.positioningRect = sourceRect
            } else {
                popover.show(relativeTo: sourceRect, of: sourceView, preferredEdge: .minY)
            }
            if popover.delegate == nil {
                popover.delegate = self
            }
            self.popover = popover
        }

        private func ensurePopover(for detail: GanttTimelineRenderPlan.SegmentDetail) -> NSPopover {
            if let popover, popover.isShown, let hostingController {
                hostingController.rootView = GanttSegmentInspector(detail: detail)
                popover.contentViewController = hostingController
                return popover
            }

            let hostingController = NSHostingController(rootView: GanttSegmentInspector(detail: detail))
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.delegate = self
            popover.contentViewController = hostingController
            self.hostingController = hostingController
            self.popover = popover
            return popover
        }

        private func updateContentSize(_ popover: NSPopover) {
            guard let view = hostingController?.view else { return }
            view.layoutSubtreeIfNeeded()
            let fittingSize = view.fittingSize
            guard fittingSize.width.isFinite,
                  fittingSize.height.isFinite,
                  fittingSize.width > 0,
                  fittingSize.height > 0
            else {
                return
            }
            popover.contentSize = fittingSize
        }

        private static func sourceRect(for anchorPoint: CGPoint) -> CGRect {
            CGRect(x: anchorPoint.x - 0.5, y: anchorPoint.y - 0.5, width: 1, height: 1)
        }
    }
}

private final class FlippedPopoverSourceView: NSView {
    override var isFlipped: Bool { true }
}

private struct GanttProjectRow: View {
    let row: GanttTimelineRenderPlan.Row

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                        .font(.sora(12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    GanttProviderBadges(providers: row.providers)
                }

                Text(row.pathText)
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(row.durationText)
                .font(.sora(11, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .frame(width: 58, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

private struct GanttProjectSelectableRow: View {
    let row: GanttTimelineRenderPlan.Row
    let onSelect: (GanttProjectReference) -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            onSelect(row.reference)
        } label: {
            GanttProjectRow(row: row)
                .background {
                    if hovering {
                        Color.primary.opacity(0.045)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(String(localized: "Open project detail"))
        .accessibilityHint(String(localized: "Open project detail"))
    }
}

private struct GanttProviderBadges: View {
    let providers: [ProviderKind]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(providers) { provider in
                Text(provider.shortName)
                    .font(.sora(8, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(provider.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .lineLimit(1)
            }
        }
    }
}

private struct GanttTimelineLegend: View {
    let renderPlan: GanttTimelineRenderPlan

    var body: some View {
        GanttLegendFlowLayout(spacing: 10, rowSpacing: 8, horizontalAlignment: .trailing) {
            ForEach(renderPlan.providers) { provider in
                GanttLegendChip(
                    title: provider.displayName,
                    sample: .provider(provider == .codex ? Color.stxAccent : provider.accentColor)
                )
            }
            GanttLegendChip(title: String(localized: "Active time"), sample: .activeBar)
            GanttLegendChip(title: String(localized: "Token intensity"), sample: .tokenIntensity)
            GanttLegendChip(title: String(localized: "Focus overlap"), sample: .focusOverlap)
            GanttLegendChip(title: String(localized: "Token peak"), sample: .tokenPeak)
            GanttLegendChip(title: String(localized: "Usage limit"), sample: .usageLimit)
            if renderPlan.limitReachForecastBands.contains(where: { $0.horizon == .fiveHour }) {
                GanttLegendChip(title: String(localized: "5h forecast"), sample: .limitForecast(.fiveHour))
            }
            if renderPlan.limitReachForecastBands.contains(where: { $0.horizon == .sevenDay }) {
                GanttLegendChip(title: String(localized: "7d forecast"), sample: .limitForecast(.sevenDay))
            }
            GanttLegendChip(title: String(localized: "Commit"), sample: .commit)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Gantt visual encoding legend"))
    }
}

private struct GanttLegendFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat
    var horizontalAlignment: GanttLegendHorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(proposal: proposal, subviews: subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * rowSpacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = xOffset(for: row, in: bounds)
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func xOffset(for row: Row, in bounds: CGRect) -> CGFloat {
        switch horizontalAlignment {
        case .center:
            return bounds.minX + max(0, (bounds.width - row.width) / 2)
        case .trailing:
            return max(bounds.minX, bounds.maxX - row.width)
        default:
            return bounds.minX
        }
    }

    private func rows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if nextWidth > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.items.append(Item(index: index, size: size))
            current.width = current.items.count == 1 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }
}

private enum GanttLegendHorizontalAlignment {
    case leading
    case center
    case trailing
}

private struct GanttLegendChip: View {
    let title: String
    let sample: GanttLegendSample

    var body: some View {
        HStack(spacing: 6) {
            GanttLegendSampleView(sample: sample)
                .frame(width: 24, height: 14)
            Text(title)
                .font(.sora(9, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private enum GanttLegendSample {
    case provider(Color)
    case activeBar
    case tokenIntensity
    case focusOverlap
    case tokenPeak
    case usageLimit
    case limitForecast(UsageLimitForecastHorizon)
    case commit
}

private struct GanttLegendSampleView: View {
    let sample: GanttLegendSample

    var body: some View {
        Canvas { context, size in
            switch sample {
            case .provider(let color):
                let rect = CGRect(x: 1, y: 3, width: size.width - 2, height: size.height - 6)
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color.opacity(0.86)))
                context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2.5), with: .color(color), lineWidth: 1)
            case .activeBar:
                let rect = CGRect(x: 1, y: 4, width: size.width - 2, height: size.height - 8)
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Color.stxAccent.opacity(0.78)))
            case .tokenIntensity:
                let low = CGRect(x: 1, y: 5, width: 8, height: size.height - 10)
                let high = CGRect(x: 11, y: 2, width: size.width - 12, height: size.height - 4)
                context.fill(Path(roundedRect: low, cornerRadius: 2), with: .color(Color.stxAccent.opacity(0.34)))
                context.fill(Path(roundedRect: high, cornerRadius: 3), with: .color(Color.stxAccent.opacity(0.92)))
            case .focusOverlap:
                let rect = CGRect(x: 1, y: 3, width: size.width - 2, height: size.height - 6)
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Color.stxAccent.opacity(0.30)))
                drawFocusHatch(context: &context, rect: rect, color: Color.primary.opacity(0.44))
            case .tokenPeak:
                let rect = CGRect(x: 5, y: 1, width: size.width - 10, height: size.height - 2)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.yellow.opacity(0.28)))
                context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.yellow.opacity(0.90)), lineWidth: 1)
            case .usageLimit:
                let rect = CGRect(x: 4, y: 1, width: size.width - 8, height: size.height - 2)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.red.opacity(0.22)))
                context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.red.opacity(0.74)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            case .limitForecast(let horizon):
                let rect = CGRect(x: 3, y: 4, width: size.width - 6, height: size.height - 8)
                let fill = horizon == .fiveHour ? Color.red.opacity(0.28) : Color.orange.opacity(0.32)
                let stroke = horizon == .fiveHour ? Color.orange.opacity(0.88) : Color.red.opacity(0.82)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(fill))
                context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(stroke), lineWidth: 1.1)
            case .commit:
                var path = Path()
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                path.move(to: CGPoint(x: center.x, y: 1))
                path.addLine(to: CGPoint(x: size.width - 6, y: center.y))
                path.addLine(to: CGPoint(x: center.x, y: size.height - 1))
                path.addLine(to: CGPoint(x: 6, y: center.y))
                path.closeSubpath()
                context.fill(path, with: .color(Color.green.opacity(0.82)))
            }
        }
        .accessibilityHidden(true)
    }

    private func drawFocusHatch(context: inout GraphicsContext, rect: CGRect, color: Color) {
        var x = rect.minX - rect.height
        while x < rect.maxX {
            var line = Path()
            line.move(to: CGPoint(x: x, y: rect.maxY))
            line.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            context.stroke(line, with: .color(color), lineWidth: 1)
            x += 5
        }
    }
}

private struct GanttTimelineHeader: View {
    let renderPlan: GanttTimelineRenderPlan

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.primary.opacity(0.035)))

            for tick in renderPlan.ticks where tick.isMajor {
                let x = tick.ratio * size.width
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height - 12))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(Color.stxStroke), lineWidth: 1)

                context.draw(
                    Text(tick.label)
                        .font(.sora(9))
                        .foregroundStyle(Color.stxMuted),
                    at: CGPoint(x: min(max(x + 4, 4), size.width - 34), y: 11),
                    anchor: .leading
                )
            }

            if let tokenPeak = renderPlan.tokenPeak {
                let midX = ((tokenPeak.startRatio + tokenPeak.endRatio) / 2) * size.width
                drawMarkerLabel(
                    text: String(localized: "Peak"),
                    x: midX,
                    y: 29,
                    color: Color.yellow,
                    context: &context,
                    size: size
                )
            }

            let now = Date.now
            if renderPlan.domain.contains(now) {
                let x = renderPlan.ratio(for: now) * size.width
                drawMarkerLabel(
                    text: String(localized: "Now"),
                    x: x,
                    y: 29,
                    color: Color.stxAccent,
                    context: &context,
                    size: size
                )
            }

            var bottom = Path()
            bottom.move(to: CGPoint(x: 0, y: size.height - 0.5))
            bottom.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(bottom, with: .color(Color.stxStroke.opacity(0.8)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func drawMarkerLabel(
        text: String,
        x: CGFloat,
        y: CGFloat,
        color: Color,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let width: CGFloat = text == String(localized: "Peak") ? 34 : 30
        let rect = CGRect(
            x: min(max(x - width / 2, 4), max(4, size.width - width - 4)),
            y: y - 8,
            width: width,
            height: 16
        )
        context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(color.opacity(0.14)))
        context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3.5), with: .color(color.opacity(0.72)), lineWidth: 1)
        context.draw(
            Text(text)
                .font(.sora(8, weight: .semibold))
                .foregroundStyle(color),
            at: CGPoint(x: rect.midX, y: rect.midY),
            anchor: .center
        )
    }
}

private struct GanttSegmentInspector: View {
    let detail: GanttTimelineRenderPlan.SegmentDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACTIVITY SEGMENT")
                        .font(.sora(12, weight: .semibold))
                        .tracking(0.8)
                    Text("\(detail.projectName) · \(Format.shortDate(detail.interval.start)) - \(Format.shortTime(detail.interval.end))")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 12)
                GanttProviderBadges(providers: detail.providers)
            }

            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    inspectorCard("DURATION", Format.duration(detail.duration))
                    inspectorCard("SESSIONS", "\(detail.sessionCount)")
                }
                GridRow {
                    inspectorCard("MESSAGES", "\(detail.messageCount)")
                    inspectorCard("TOKENS", Format.tokens(detail.tokens))
                }
                GridRow {
                    inspectorCard("COST", Format.cost(detail.cost))
                    inspectorCard("FOCUS", Format.duration(detail.focusOverlapDuration))
                }
            }
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            if !detail.models.isEmpty {
                HStack(spacing: 8) {
                    ForEach(detail.models.prefix(4)) { model in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.model)
                                .font(.sora(9, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(Format.tokens(model.tokens)) · \(Format.cost(model.cost))")
                                .font(.sora(8))
                                .foregroundStyle(Color.stxMuted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func inspectorCard(_ label: String, _ value: String) -> some View {
        StatCard(label: label, value: value, animatesNumericValue: false)
    }
}

private struct GanttTimelineDocument: View {
    let renderPlan: GanttTimelineRenderPlan
    let headerHeight: CGFloat
    let rowHeight: CGFloat
    let rowsHeight: CGFloat
    @Binding var selectedSegment: GanttTimelinePopoverSelection?

    var body: some View {
        VStack(spacing: 0) {
            GanttTimelineHeader(renderPlan: renderPlan)
                .frame(height: headerHeight)
            ZStack(alignment: .topLeading) {
                GanttTimelineCanvas(
                    renderPlan: renderPlan,
                    rowHeight: rowHeight,
                    selectedSegmentID: selectedSegment?.segmentID
                )
                GanttTimelineHitLayer(
                    renderPlan: renderPlan,
                    rowHeight: rowHeight,
                    selectedSegment: $selectedSegment
                )
            }
            .frame(height: rowsHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct GanttTimelineHitLayer: View {
    let renderPlan: GanttTimelineRenderPlan
    let rowHeight: CGFloat
    @Binding var selectedSegment: GanttTimelinePopoverSelection?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                guard isTap(value) else { return }
                                selectTarget(at: value.location, timelineWidth: proxy.size.width)
                            }
                    )
                    .accessibilityLabel(String(localized: "Gantt timeline segments"))

                GanttSegmentPopoverSource(
                    selectedSegment: $selectedSegment,
                    anchorPoint: selectedSegment.flatMap {
                        anchorPoint(for: $0.segmentID, timelineWidth: proxy.size.width)
                    }
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private func isTap(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) <= 2 && abs(value.translation.height) <= 2
    }

    private func selectTarget(at location: CGPoint, timelineWidth: CGFloat) {
        for target in renderPlan.hitTargets.reversed() {
            guard let rect = hitRect(for: target, timelineWidth: timelineWidth),
                  rect.contains(location)
            else {
                continue
            }
            selectedSegment = GanttTimelinePopoverSelection(
                segmentID: target.id,
                detail: target.detail
            )
            return
        }
        selectedSegment = nil
    }

    private func anchorPoint(for selectionID: String, timelineWidth: CGFloat) -> CGPoint? {
        guard let target = renderPlan.hitTargets.first(where: { $0.id == selectionID }),
              let rect = hitRect(for: target, timelineWidth: timelineWidth)
        else {
            return nil
        }
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private func hitRect(
        for target: GanttTimelineRenderPlan.HitTarget,
        timelineWidth: CGFloat
    ) -> CGRect? {
        GanttTimelineHitTargetGeometry.rect(
            startRatio: target.startRatio,
            endRatio: target.endRatio,
            rowIndex: target.rowIndex,
            rowHeight: rowHeight,
            timelineWidth: timelineWidth
        )
    }
}

private struct GanttTimelineCanvas: View {
    let renderPlan: GanttTimelineRenderPlan
    let rowHeight: CGFloat
    let selectedSegmentID: String?

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            drawAnnotationBands(context: &context, size: size)
            drawGrid(context: &context, size: size)
            drawBars(context: &context, size: size)
            drawCommitMarkers(context: &context, size: size)
            drawNowLine(context: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    private func drawAnnotationBands(context: inout GraphicsContext, size: CGSize) {
        for band in renderPlan.usageLimitBands {
            let startX = band.startRatio * size.width
            let endX = band.endRatio * size.width
            let width = min(size.width - startX, max(2, endX - startX))
            guard width > 0 else { continue }

            let rect = CGRect(x: startX, y: 0, width: width, height: size.height)
            let opacity = 0.045 + min(0.18, max(0, band.intensity) * 0.16)
            context.fill(Path(rect), with: .color(Color.red.opacity(opacity)))
            context.stroke(
                Path(rect),
                with: .color(Color.red.opacity(0.20 + min(0.36, band.intensity * 0.28))),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
        }

        if let tokenPeak = renderPlan.tokenPeak {
            let startX = tokenPeak.startRatio * size.width
            let endX = tokenPeak.endRatio * size.width
            let width = min(size.width - startX, max(2, endX - startX))
            guard width > 0 else { return }

            let rect = CGRect(x: startX, y: 0, width: width, height: size.height)
            context.fill(Path(rect), with: .color(Color.yellow.opacity(0.085)))
            context.stroke(Path(rect), with: .color(Color.yellow.opacity(0.34)), lineWidth: 1)
        }

        for band in renderPlan.limitReachForecastBands {
            let startX = band.startRatio * size.width
            let endX = band.endRatio * size.width
            let width = min(size.width - startX, max(3, endX - startX))
            guard width > 0 else { continue }

            let y: CGFloat = band.horizon == .fiveHour ? 3 : 13
            let rect = CGRect(x: startX, y: y, width: width, height: 7)
            let opacity: Double = switch band.confidence {
            case .high: 0.34
            case .medium: 0.28
            case .low: 0.22
            }
            let fill = band.horizon == .fiveHour
                ? Color.red.opacity(opacity)
                : Color.orange.opacity(opacity)
            let stroke = band.horizon == .fiveHour
                ? Color.orange.opacity(0.78)
                : Color.red.opacity(0.70)
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(fill))
            context.stroke(
                Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2.5),
                with: .color(stroke),
                lineWidth: 1
            )
        }
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        for index in 0...renderPlan.rows.count {
            let y = CGFloat(index) * rowHeight
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(Color.stxStroke.opacity(0.55)), lineWidth: 1)
        }

        for tick in renderPlan.ticks {
            let x = tick.ratio * size.width
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(
                line,
                with: .color(Color.stxStroke.opacity(tick.isMajor ? 0.72 : 0.32)),
                lineWidth: tick.isMajor ? 1 : 0.5
            )
        }
    }

    private func drawBars(context: inout GraphicsContext, size: CGSize) {
        for row in renderPlan.rows {
            for segment in row.segments {
                let color = color(for: segment, row: row)
                let startX = segment.startRatio * size.width
                let endX = segment.endRatio * size.width
                let width = min(size.width - startX, max(3, endX - startX))
                guard width > 0 else { continue }

                let height = 10 + CGFloat(segment.tokenIntensity) * 6
                let y = CGFloat(row.index) * rowHeight + (rowHeight - height) / 2
                let rect = CGRect(x: startX, y: y, width: width, height: height)
                let fillOpacity = 0.48 + min(0.44, segment.tokenIntensity * 0.44)
                context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(color.opacity(fillOpacity)))
                context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3.5), with: .color(color), lineWidth: 1)

                if segment.focusRatio > 0 {
                    drawFocusHatch(context: &context, rect: rect.insetBy(dx: 1.5, dy: 1.5))
                }

                let selectionID = "\(row.id)|\(segment.id)"
                if selectedSegmentID == selectionID {
                    let selectedRect = rect.insetBy(dx: -2, dy: -2)
                    context.stroke(
                        Path(roundedRect: selectedRect, cornerRadius: 5),
                        with: .color(Color.primary.opacity(0.88)),
                        lineWidth: 2
                    )
                    context.stroke(
                        Path(roundedRect: selectedRect.insetBy(dx: -2, dy: -2), cornerRadius: 7),
                        with: .color(color.opacity(0.30)),
                        lineWidth: 3
                    )
                }
            }
        }
    }

    private func drawFocusHatch(context: inout GraphicsContext, rect: CGRect) {
        let color = Color.primary.opacity(0.38)
        var x = rect.minX - rect.height
        while x < rect.maxX {
            var line = Path()
            line.move(to: CGPoint(x: x, y: rect.maxY))
            line.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            context.stroke(line, with: .color(color), lineWidth: 1)
            x += 7
        }
    }

    private func drawCommitMarkers(context: inout GraphicsContext, size: CGSize) {
        for row in renderPlan.rows where !row.commitMarkers.isEmpty {
            let rowTop = CGFloat(row.index) * rowHeight
            let rowMidY = rowTop + rowHeight / 2
            let lineStartY = rowTop + 6
            let lineEndY = rowTop + rowHeight - 6

            for marker in row.commitMarkers {
                let x = marker.ratio * size.width
                var line = Path()
                line.move(to: CGPoint(x: x, y: lineStartY))
                line.addLine(to: CGPoint(x: x, y: lineEndY))
                context.stroke(line, with: .color(Color.green.opacity(0.26)), lineWidth: 1)

                let diamond = diamondPath(center: CGPoint(x: x, y: rowMidY), radius: 5)
                context.fill(diamond, with: .color(Color.green.opacity(0.86)))
                context.stroke(diamond, with: .color(Color.green), lineWidth: 1)
            }
        }
    }

    private func diamondPath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.closeSubpath()
        return path
    }

    private func drawNowLine(context: inout GraphicsContext, size: CGSize) {
        let now = Date.now
        guard renderPlan.domain.contains(now) else { return }
        let x = renderPlan.ratio(for: now) * size.width
        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(line, with: .color(Color.stxAccent.opacity(0.72)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
    }

    private func color(for segment: GanttTimelineRenderPlan.Segment, row: GanttTimelineRenderPlan.Row) -> Color {
        if let provider = segment.detail.providers.first ?? row.colorProvider {
            return provider == .codex ? Color.stxAccent : provider.accentColor
        }
        let palette: [Color] = [.stxAccent, .blue, .green, .orange, .pink, .purple]
        return palette[row.fallbackColorIndex % palette.count]
    }
}

private struct GanttTick: Sendable {
    let date: Date
    let label: String
    let isMajor: Bool
}

enum GanttTimelineScale {
    static func ratio(for date: Date, domain: DateInterval) -> CGFloat {
        guard domain.duration > 0 else { return 0 }
        let ratio = date.timeIntervalSince(domain.start) / domain.duration
        return min(1, max(0, CGFloat(ratio)))
    }

    static func x(for date: Date, domain: DateInterval, width: CGFloat) -> CGFloat {
        ratio(for: date, domain: domain) * width
    }

    fileprivate static func ticks(for range: GanttRange, domain: DateInterval, calendar: Calendar = .current) -> [GanttTick] {
        switch range {
        case .day:
            return strideTicks(
                domain: domain,
                component: .hour,
                calendar: calendar
            ) { date in
                let hour = calendar.component(.hour, from: date)
                return GanttTick(
                    date: date,
                    label: date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))),
                    isMajor: hour % 3 == 0
                )
            }
        case .week:
            return strideTicks(
                domain: domain,
                component: .hour,
                calendar: calendar
            ) { date in
                multiDayTick(for: date, calendar: calendar)
            }
        case .month:
            return strideTicks(
                domain: domain,
                component: .hour,
                calendar: calendar
            ) { date in
                multiDayTick(for: date, calendar: calendar)
            }
        }
    }

    private static func multiDayTick(for date: Date, calendar: Calendar) -> GanttTick {
        let hour = calendar.component(.hour, from: date)
        if hour == 0 {
            return GanttTick(date: date, label: Format.day(date), isMajor: true)
        }

        return GanttTick(
            date: date,
            label: date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))),
            isMajor: hour % 3 == 0
        )
    }

    private static func strideTicks(
        domain: DateInterval,
        component: Calendar.Component,
        calendar: Calendar,
        make: (Date) -> GanttTick
    ) -> [GanttTick] {
        var cursor = calendar.dateInterval(of: component, for: domain.start)?.start ?? domain.start
        var out: [GanttTick] = []
        while cursor <= domain.end {
            out.append(make(cursor))
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return out
    }
}

#if DEBUG
#Preview("Gantt") {
    MainGanttView()
        .environment(AppEnvironment.preview())
        .frame(width: 1_080, height: 720)
        .background(Color.stxBackground)
}
#endif
