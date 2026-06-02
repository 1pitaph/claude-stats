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
            await vm.reload(
                sessions: env.store.sessions,
                codingSurfaceBundleIDs: codingSurfaceBundleIDs,
                cliHostBundleIDs: cliHostBundleIDs,
                usageLimitReports: Array(env.usageLimits.reports.values)
            )
        }
        .onChange(of: env.usageLimits.reports) { _, reports in
            vm.refreshUsageLimitReports(Array(reports.values))
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
        }
        .sheet(item: $selectedProject) { project in
            GanttProjectDetailSheet(
                project: project,
                initialMode: vm.activityMode,
                sessions: env.store.sessions,
                usageLimitReports: Array(env.usageLimits.reports.values),
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
        ViewThatFits(in: .horizontal) {
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

    private func resetTimelineViewport() {
        timelineViewport = GanttTimelineViewport()
        timelineResetID &+= 1
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                cards
            }
            .mainWindowPanel(padding: 0)

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
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        title
                        Spacer(minLength: 12)
                        Text("\(Format.day(comparison.baselineDomain.start)) - \(Format.day(comparison.baselineDomain.end.addingTimeInterval(-1)))")
                            .font(.sora(10).monospacedDigit())
                            .foregroundStyle(Color.stxMuted)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        title
                        Text("\(Format.day(comparison.baselineDomain.start)) - \(Format.day(comparison.baselineDomain.end.addingTimeInterval(-1)))")
                            .font(.sora(10).monospacedDigit())
                            .foregroundStyle(Color.stxMuted)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) { deltaCards(comparison) }
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            baselineCard("ACTIVE", Format.signedDuration(comparison.activeDurationDelta))
                            baselineCard("TOKENS", Format.signedTokens(comparison.tokensDelta))
                        }
                        GridRow {
                            baselineCard("COST", Format.signedCurrency(comparison.costDelta))
                            baselineCard("COMMITS", Format.signedCount(comparison.commitDelta))
                        }
                        GridRow {
                            baselineCard("FAILURES", Format.signedCount(comparison.failureSignalDelta))
                            baselineCard("RETRIES", Format.signedCount(comparison.retrySignalDelta))
                        }
                        GridRow {
                            baselineCard("SWITCHES", Format.signedCount(comparison.contextSwitchDelta))
                        }
                    }
                }
            }
            .mainWindowPanel(padding: 16)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BASELINE")
                .font(.sora(13, weight: .semibold))
                .tracking(1.0)
            Text("Compared with the previous matching range.")
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
        Divider().opacity(0.5)
        baselineCard("FAILURES", Format.signedCount(comparison.failureSignalDelta))
        Divider().opacity(0.5)
        baselineCard("RETRIES", Format.signedCount(comparison.retrySignalDelta))
        Divider().opacity(0.5)
        baselineCard("SWITCHES", Format.signedCount(comparison.contextSwitchDelta))
    }

    private func baselineCard(_ label: String, _ value: String) -> some View {
        StatCard(label: label, value: value, animatesNumericValue: false)
    }
}

private struct GanttTimelineOverviewPanel: View {
    let snapshot: GanttTimelineSnapshot
    @Binding var viewport: GanttTimelineViewport
    @State private var dragSession: GanttOverviewViewportDragSession?

    private var isInteractive: Bool {
        GanttTimelineViewportMetrics.overviewIsInteractive(range: snapshot.range, viewport: viewport)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("OVERVIEW")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer(minLength: 12)
                if isInteractive {
                    Text("Drag to move the visible period.")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    GanttOverviewCanvas(snapshot: snapshot)

                    if isInteractive {
                        GanttOverviewViewportOverlay(
                            viewport: viewport,
                            overviewSize: proxy.size
                        )
                        .allowsHitTesting(false)

                        GanttOverviewViewportDragLayer(
                            viewport: $viewport,
                            overviewSize: proxy.size,
                            dragSession: $dragSession
                        )
                    }
                }
            }
            .frame(height: 58)
            .clipShape(.rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1)
            }
        }
        .mainWindowPanel(padding: 16)
        .onChange(of: isInteractive) { _, _ in
            dragSession = nil
        }
        .onChange(of: snapshot.renderRevisionID) { _, _ in
            dragSession = nil
        }
    }
}

private enum GanttOverviewViewportDragSession: Equatable {
    case active(startOffsetX: CGFloat)
    case ignored
}

private struct GanttOverviewViewportOverlay: View {
    let viewport: GanttTimelineViewport
    let overviewSize: CGSize

    private var rect: CGRect {
        GanttTimelineViewportMetrics.overviewThumbRect(viewport: viewport, overviewSize: overviewSize)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.stxAccent.opacity(0.14))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.stxAccent.opacity(0.72), lineWidth: 1)
            }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .contentShape(Rectangle())
            .accessibilityLabel(String(localized: "Visible timeline period"))
    }
}

private struct GanttOverviewViewportDragLayer: View {
    @Binding var viewport: GanttTimelineViewport
    let overviewSize: CGSize
    @Binding var dragSession: GanttOverviewViewportDragSession?

    var body: some View {
        Color.clear
            .frame(width: max(0, overviewSize.width), height: max(0, overviewSize.height))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragSession == nil {
                            let thumbRect = GanttTimelineViewportMetrics
                                .overviewThumbRect(viewport: viewport, overviewSize: overviewSize)
                                .insetBy(dx: -6, dy: 0)
                            dragSession = thumbRect.contains(value.startLocation)
                                ? .active(startOffsetX: viewport.offsetX)
                                : .ignored
                        }

                        guard case .active(let startOffsetX) = dragSession else { return }
                        let delta = GanttTimelineViewportMetrics.offsetDeltaForOverviewDrag(
                            translationX: value.translation.width,
                            overviewWidth: overviewSize.width,
                            viewport: viewport
                        )
                        viewport = viewport.withOffset(startOffsetX + delta)
                    }
                    .onEnded { _ in
                        dragSession = nil
                    }
            )
            .accessibilityHidden(true)
    }
}

private struct GanttOverviewCanvas: View {
    let snapshot: GanttTimelineSnapshot

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.primary.opacity(0.025)))
            let rowCount = max(1, min(snapshot.projects.count, 8))
            let rowHeight = size.height / CGFloat(rowCount)
            for (index, project) in snapshot.projects.prefix(rowCount).enumerated() {
                let color = project.providerList.first == .codex ? Color.stxAccent : (project.providerList.first?.accentColor ?? Color.stxAccent)
                for segment in project.segments {
                    let startX = GanttTimelineScale.ratio(for: segment.interval.start, domain: snapshot.domain) * size.width
                    let endX = GanttTimelineScale.ratio(for: segment.interval.end, domain: snapshot.domain) * size.width
                    let rect = CGRect(
                        x: startX,
                        y: CGFloat(index) * rowHeight + 8,
                        width: max(2, endX - startX),
                        height: max(3, rowHeight - 14)
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(0.78)))
                }
            }
            if snapshot.domain.contains(Date.now) {
                let x = GanttTimelineScale.ratio(for: .now, domain: snapshot.domain) * size.width
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(Color.stxAccent.opacity(0.75)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .accessibilityLabel(String(localized: "Gantt overview"))
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { summaryCards }
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
        codingSurfaceBundleIDs: Set<String>,
        cliHostBundleIDs: Set<String>
    ) {
        self.project = project
        self.sessions = sessions
        self.usageLimitReports = usageLimitReports
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
                codingSurfaceBundleIDs: codingSurfaceBundleIDs,
                cliHostBundleIDs: cliHostBundleIDs
            )
        }
        .onChange(of: usageLimitReports) { _, reports in
            vm.refreshUsageLimitReports(reports)
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                cards
            }
            .mainWindowPanel(padding: 0)

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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                recentSevenDayTitle
                Spacer(minLength: 12)
                Text(rangeLabel)
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }

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
        let renderPlanKey = GanttTimelineRenderPlan.Key(revisionID: snapshot.renderRevisionID)
        let renderPlan = cachedRenderPlanKey == renderPlanKey
            ? (cachedRenderPlan ?? makeRenderPlan(key: renderPlanKey))
            : makeRenderPlan(key: renderPlanKey)

        return VStack(alignment: .leading, spacing: 12) {
            panelHeader

            if snapshot.isEmpty {
                emptyState
            } else {
                chart(renderPlan)
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                chartTitle
                Spacer(minLength: 12)
                Text(rangeLabel)
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }

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
                        viewport: $viewport
                    ) {
                        VStack(spacing: 0) {
                            GanttTimelineHeader(ticks: renderPlan.ticks)
                                .frame(width: timelineWidth, height: headerHeight)
                            ZStack(alignment: .topLeading) {
                                GanttTimelineCanvas(renderPlan: renderPlan, rowHeight: rowHeight)
                                GanttTimelineHitLayer(
                                    renderPlan: renderPlan,
                                    rowHeight: rowHeight,
                                    selectedSegment: $selectedSegment
                                )
                            }
                            .frame(width: timelineWidth, height: rowsHeight)
                        }
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

    struct Row: Identifiable {
        let id: String
        let displayName: String
        let pathText: String
        let providers: [ProviderKind]
        let durationText: String
        let accessibilityLabel: String
        let reference: GanttProjectReference
        let colorProvider: ProviderKind?
        let fallbackColorIndex: Int
        let segments: [Segment]
    }

    let key: Key
    let range: GanttRange
    let domain: DateInterval
    let ticks: [Tick]
    let rows: [Row]

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
        self.rows = snapshot.projects.enumerated().map { index, project in
            let providerList = project.providerList
            let durationText = Format.duration(project.totalDuration)
            let segments = project.segments.map { segment in
                Segment(
                    id: segment.id,
                    startRatio: GanttTimelineScale.ratio(for: segment.interval.start, domain: snapshot.domain),
                    endRatio: GanttTimelineScale.ratio(for: segment.interval.end, domain: snapshot.domain),
                    detail: SegmentDetail(
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
                )
            }
            return Row(
                id: project.id,
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
                segments: segments
            )
        }
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
    let segmentID: String
    let detail: GanttTimelineRenderPlan.SegmentDetail
    @Binding var selectedSegment: GanttTimelinePopoverSelection?

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
            isSelected: selectedSegment?.segmentID == segmentID,
            detail: selectedSegment?.detail ?? detail,
            in: nsView
        )
    }

    static func dismantleNSView(_ nsView: FlippedPopoverSourceView, coordinator: Coordinator) {
        coordinator.closeFromViewRemoval()
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        var selectedSegment: Binding<GanttTimelinePopoverSelection?>?
        private var popover: NSPopover?
        private var hostingController: NSHostingController<GanttSegmentInspector>?
        private var isClosingFromUpdate = false

        func update(
            isSelected: Bool,
            detail: GanttTimelineRenderPlan.SegmentDetail,
            in sourceView: FlippedPopoverSourceView
        ) {
            guard isSelected else {
                closeFromSelectionChange()
                return
            }

            guard sourceView.window != nil else { return }

            let sourceRect = sourceView.bounds
            guard sourceRect.width > 0, sourceRect.height > 0 else { return }

            let popover = ensurePopover(for: detail)
            updateContentSize(popover)

            if popover.isShown {
                popover.positioningRect = sourceRect
                return
            }

            let popoverToShow = self.popover ?? ensurePopover(for: detail)
            // The source view is flipped, so minY is the visual top edge.
            popoverToShow.show(relativeTo: sourceRect, of: sourceView, preferredEdge: .minY)
            if popoverToShow.delegate == nil {
                popoverToShow.delegate = self
            }
            self.popover = popoverToShow
        }

        func closeFromSelectionChange() {
            guard let popover else { return }
            isClosingFromUpdate = true
            popover.close()
        }

        func closeFromViewRemoval() {
            popover?.close()
            popover = nil
            hostingController = nil
        }

        func popoverDidClose(_ notification: Notification) {
            defer { isClosingFromUpdate = false }
            guard !isClosingFromUpdate else { return }
            selectedSegment?.wrappedValue = nil
        }

        private func ensurePopover(for detail: GanttTimelineRenderPlan.SegmentDetail) -> NSPopover {
            if let hostingController {
                hostingController.rootView = GanttSegmentInspector(detail: detail)
            } else {
                hostingController = NSHostingController(rootView: GanttSegmentInspector(detail: detail))
            }

            if let popover {
                popover.contentViewController = hostingController
                return popover
            }

            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.delegate = self
            popover.contentViewController = hostingController
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
    }
}

private final class FlippedPopoverSourceView: NSView {
    override var isFlipped: Bool {
        true
    }
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

private struct GanttTimelineHeader: View {
    let ticks: [GanttTimelineRenderPlan.Tick]

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.primary.opacity(0.035)))

            for tick in ticks where tick.isMajor {
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

            var bottom = Path()
            bottom.move(to: CGPoint(x: 0, y: size.height - 0.5))
            bottom.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(bottom, with: .color(Color.stxStroke.opacity(0.8)), lineWidth: 1)
        }
        .accessibilityHidden(true)
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

private struct GanttTimelineHitLayer: View {
    let renderPlan: GanttTimelineRenderPlan
    let rowHeight: CGFloat
    @Binding var selectedSegment: GanttTimelinePopoverSelection?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(Array(renderPlan.rows.enumerated()), id: \.element.id) { index, row in
                    ForEach(row.segments, id: \.id) { segment in
                        let selectionID = "\(row.id)|\(segment.id)"
                        let startX = segment.startRatio * proxy.size.width
                        let endX = segment.endRatio * proxy.size.width
                        let barWidth = min(proxy.size.width - startX, max(3, endX - startX))
                        let visibleStartX = min(max(startX, 0), proxy.size.width)
                        let visibleEndX = min(max(startX + barWidth, 0), proxy.size.width)
                        let visibleWidth = max(0, visibleEndX - visibleStartX)
                        let hitWidth = max(8, visibleWidth)
                        let rowY = CGFloat(index) * rowHeight
                        if visibleWidth > 0 {
                            Button {
                                selectedSegment = GanttTimelinePopoverSelection(
                                    segmentID: selectionID,
                                    detail: segment.detail
                                )
                            } label: {
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: hitWidth, height: rowHeight)
                            .overlay {
                                GanttSegmentPopoverSource(
                                    segmentID: selectionID,
                                    detail: segment.detail,
                                    selectedSegment: $selectedSegment
                                )
                                .frame(width: 1, height: 1)
                                .allowsHitTesting(false)
                            }
                            .position(x: visibleStartX + visibleWidth / 2, y: rowY + rowHeight / 2)
                            .help("\(segment.detail.projectName): \(Format.duration(segment.detail.duration)), \(Format.tokens(segment.detail.tokens))")
                            .accessibilityLabel("\(segment.detail.projectName), \(Format.duration(segment.detail.duration)), \(Format.tokens(segment.detail.tokens))")
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

private struct GanttTimelineCanvas: View {
    let renderPlan: GanttTimelineRenderPlan
    let rowHeight: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            drawGrid(context: &context, size: size)
            drawBars(context: &context, size: size)
            drawNowLine(context: &context, size: size)
        }
        .accessibilityHidden(true)
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
        for (index, row) in renderPlan.rows.enumerated() {
            let color = color(for: row)
            let y = CGFloat(index) * rowHeight + (rowHeight - 13) / 2

            for segment in row.segments {
                let startX = segment.startRatio * size.width
                let endX = segment.endRatio * size.width
                let width = min(size.width - startX, max(3, endX - startX))
                guard width > 0 else { continue }

                let rect = CGRect(x: startX, y: y, width: width, height: 13)
                context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(color.opacity(0.86)))
                context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3.5), with: .color(color), lineWidth: 1)
            }
        }
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

    private func color(for row: GanttTimelineRenderPlan.Row) -> Color {
        if let provider = row.colorProvider {
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

private enum GanttTimelineScale {
    static func ratio(for date: Date, domain: DateInterval) -> CGFloat {
        guard domain.duration > 0 else { return 0 }
        let ratio = date.timeIntervalSince(domain.start) / domain.duration
        return min(1, max(0, CGFloat(ratio)))
    }

    static func x(for date: Date, domain: DateInterval, width: CGFloat) -> CGFloat {
        ratio(for: date, domain: domain) * width
    }

    static func ticks(for range: GanttRange, domain: DateInterval, calendar: Calendar = .current) -> [GanttTick] {
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
