import AppKit
import SwiftUI

struct MainGanttView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm = GanttViewModel()
    @State private var selectedProject: GanttProjectReference?

    private struct ReloadKey: Equatable {
        let range: GanttRange
        let selectedDate: Date
        let mode: GanttActivityMode
        let token: UInt64
        let lastRefreshedAt: Date?
        let codingSurfaceBundleIDs: Set<String>
        let cliHostBundleIDs: Set<String>
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
                    onStepPeriod: vm.stepPeriod
                )

                if vm.activityMode == .assistedFocus && vm.permissionState == .needsFullDiskAccess {
                    permissionGate
                } else {
                    GanttOverviewPanel(snapshot: vm.snapshot)
                    GanttChartPanel(snapshot: vm.snapshot, emptyMessage: chartEmptyMessage) { project in
                        selectedProject = project
                    }
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
                cliHostBundleIDs: cliHostBundleIDs
            )
        }
        .sheet(item: $selectedProject) { project in
            GanttProjectDetailSheet(
                project: project,
                initialMode: vm.activityMode,
                sessions: env.store.sessions,
                sourceRefreshedAt: env.store.lastRefreshedAt,
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
        onStepPeriod: @escaping (Int) -> Void
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                GanttModeChips(mode: mode)
                Spacer(minLength: 12)
                loadingIndicator(isLoading)
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
        ReloadKey(
            range: vm.range,
            selectedDate: vm.selectedDate,
            mode: vm.activityMode,
            token: vm.reloadToken,
            lastRefreshedAt: env.store.lastRefreshedAt,
            codingSurfaceBundleIDs: codingSurfaceBundleIDs,
            cliHostBundleIDs: cliHostBundleIDs
        )
    }

}

private struct GanttRangeChips: View {
    @Binding var range: GanttRange

    private static let values: [GanttRange] = [.week, .month]

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

    private var isSelected: Bool {
        range == .day
    }

    var body: some View {
        PillTimeStepperBar(
            canStepForward: canStepForward,
            isCenterSelected: isSelected,
            previousHelp: String(localized: "Previous day"),
            nextHelp: String(localized: "Next day"),
            centerHelp: String(localized: "Show selected day"),
            centerAccessibilityLabel: String(localized: "Selected day"),
            accessibilityLabel: String(localized: "Gantt day navigation"),
            onPrevious: { stepDay(-1) },
            onNext: { stepDay(1) },
            onCenter: {
                withAnimation(.easeOut(duration: 0.18)) {
                    range = .day
                }
            }
        ) { _ in
            Text(selectedPeriod)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func stepDay(_ offset: Int) {
        withAnimation(.easeOut(duration: 0.18)) {
            range = .day
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

private struct GanttProjectDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let project: GanttProjectReference
    let sessions: [Session]
    let sourceRefreshedAt: Date?
    let codingSurfaceBundleIDs: Set<String>
    let cliHostBundleIDs: Set<String>

    @State private var vm: GanttProjectDetailViewModel

    private struct ReloadKey: Equatable {
        let projectID: String
        let mode: GanttActivityMode
        let token: UInt64
        let sourceRefreshedAt: Date?
        let codingSurfaceBundleIDs: Set<String>
        let cliHostBundleIDs: Set<String>
    }

    init(
        project: GanttProjectReference,
        initialMode: GanttActivityMode,
        sessions: [Session],
        sourceRefreshedAt: Date?,
        codingSurfaceBundleIDs: Set<String>,
        cliHostBundleIDs: Set<String>
    ) {
        self.project = project
        self.sessions = sessions
        self.sourceRefreshedAt = sourceRefreshedAt
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
                codingSurfaceBundleIDs: codingSurfaceBundleIDs,
                cliHostBundleIDs: cliHostBundleIDs
            )
        }
    }

    private var reloadKey: ReloadKey {
        ReloadKey(
            projectID: project.id,
            mode: vm.activityMode,
            token: vm.reloadToken,
            sourceRefreshedAt: sourceRefreshedAt,
            codingSurfaceBundleIDs: codingSurfaceBundleIDs,
            cliHostBundleIDs: cliHostBundleIDs
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
                    GanttProjectSevenDayChartPanel(
                        snapshot: vm.snapshot,
                        project: project,
                        emptyMessage: detailEmptyMessage
                    )
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
        Canvas { context, size in
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

        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: day.start, to: date)
        let seconds = Double(components.hour ?? 0) * 3_600
            + Double(components.minute ?? 0) * 60
            + Double(components.second ?? 0)
            + Double(components.nanosecond ?? 0) / 1_000_000_000
        return min(width, max(0, width * CGFloat(seconds / 86_400)))
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
    var onSelectProject: ((GanttProjectReference) -> Void)?

    private let leftColumnWidth: CGFloat = 260
    private let headerHeight: CGFloat = 42
    private let rowHeight: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader

            if snapshot.isEmpty {
                emptyState
            } else {
                chart
            }
        }
        .mainWindowPanel(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Gantt"))
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

    private var chart: some View {
        let rowsHeight = CGFloat(snapshot.projects.count) * rowHeight
        let totalHeight = headerHeight + rowsHeight

        return GeometryReader { proxy in
            let timelineWidth = max(proxy.size.width - leftColumnWidth - 1, preferredTimelineWidth)

            HStack(alignment: .top, spacing: 0) {
                projectColumn
                    .frame(width: leftColumnWidth)

                AppScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        GanttTimelineHeader(snapshot: snapshot)
                            .frame(width: timelineWidth, height: headerHeight)
                        GanttTimelineCanvas(snapshot: snapshot, rowHeight: rowHeight)
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

    private var preferredTimelineWidth: CGFloat {
        switch snapshot.range {
        case .day:
            980
        case .week:
            1_120
        case .month:
            max(1_420, CGFloat(calendarDaySpan(snapshot.domain)) * 48)
        }
    }

    private var projectColumn: some View {
        VStack(spacing: 0) {
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

            ForEach(snapshot.projects) { project in
                Group {
                    if let onSelectProject {
                        GanttProjectSelectableRow(project: project, onSelect: onSelectProject)
                    } else {
                        GanttProjectRow(project: project)
                    }
                }
                .frame(height: rowHeight)

                if project.id != snapshot.projects.last?.id {
                    StxRule()
                }
            }
        }
        .background(Color.primary.opacity(0.02))
    }

    private func calendarDaySpan(_ interval: DateInterval) -> Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1
        return max(1, days)
    }
}

private struct GanttProjectRow: View {
    let project: GanttProjectTimeline

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(project.displayName)
                        .font(.sora(12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    GanttProviderBadges(providers: project.providerList)
                }

                Text(project.path ?? String(localized: "No project path"))
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(Format.duration(project.totalDuration))
                .font(.sora(11, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .frame(width: 58, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format(
            "gantt.project.accessibility.active",
            defaultValue: "%@, %@ active",
            project.displayName,
            Format.duration(project.totalDuration)
        ))
    }
}

private struct GanttProjectSelectableRow: View {
    let project: GanttProjectTimeline
    let onSelect: (GanttProjectReference) -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            onSelect(project.reference)
        } label: {
            GanttProjectRow(project: project)
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
    let snapshot: GanttTimelineSnapshot

    var body: some View {
        Canvas { context, size in
            let ticks = GanttTimelineScale.ticks(for: snapshot.range, domain: snapshot.domain)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.primary.opacity(0.035)))

            for tick in ticks where tick.isMajor {
                let x = GanttTimelineScale.x(for: tick.date, domain: snapshot.domain, width: size.width)
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

private struct GanttTimelineCanvas: View {
    let snapshot: GanttTimelineSnapshot
    let rowHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            let ticks = GanttTimelineScale.ticks(for: snapshot.range, domain: snapshot.domain)
            drawGrid(context: &context, size: size, ticks: ticks)
            drawBars(context: &context, size: size)
            drawNowLine(context: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize, ticks: [GanttTick]) {
        for index in 0...snapshot.projects.count {
            let y = CGFloat(index) * rowHeight
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(Color.stxStroke.opacity(0.55)), lineWidth: 1)
        }

        for tick in ticks {
            let x = GanttTimelineScale.x(for: tick.date, domain: snapshot.domain, width: size.width)
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
        for (index, project) in snapshot.projects.enumerated() {
            let color = colorForProject(project, index: index)
            let y = CGFloat(index) * rowHeight + (rowHeight - 13) / 2

            for segment in project.segments {
                let startX = GanttTimelineScale.x(for: segment.interval.start, domain: snapshot.domain, width: size.width)
                let endX = GanttTimelineScale.x(for: segment.interval.end, domain: snapshot.domain, width: size.width)
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
        guard snapshot.domain.contains(now) else { return }
        let x = GanttTimelineScale.x(for: now, domain: snapshot.domain, width: size.width)
        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(line, with: .color(Color.stxAccent.opacity(0.72)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
    }

    private func colorForProject(_ project: GanttProjectTimeline, index: Int) -> Color {
        if let provider = project.providerList.first {
            return provider == .codex ? Color.stxAccent : provider.accentColor
        }
        let palette: [Color] = [.stxAccent, .blue, .green, .orange, .pink, .purple]
        return palette[index % palette.count]
    }
}

private struct GanttTick: Sendable {
    let date: Date
    let label: String
    let isMajor: Bool
}

private enum GanttTimelineScale {
    static func x(for date: Date, domain: DateInterval, width: CGFloat) -> CGFloat {
        guard domain.duration > 0 else { return 0 }
        let ratio = date.timeIntervalSince(domain.start) / domain.duration
        return min(width, max(0, width * CGFloat(ratio)))
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
                component: .day,
                calendar: calendar
            ) { date in
                GanttTick(date: date, label: Format.day(date), isMajor: true)
            }
        case .month:
            return strideTicks(
                domain: domain,
                component: .day,
                calendar: calendar
            ) { date in
                let weekday = calendar.component(.weekday, from: date)
                let day = calendar.component(.day, from: date)
                return GanttTick(date: date, label: Format.day(date), isMajor: day == 1 || weekday == calendar.firstWeekday)
            }
        }
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
