import AppKit
import SwiftUI

struct MainGanttView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm = GanttViewModel()

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
                    GanttChartPanel(snapshot: vm.snapshot)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 22)
            .frame(minWidth: 760, maxWidth: .infinity, alignment: .leading)
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
                GanttPeriodStepper(
                    selectedPeriod: selectedPeriod,
                    canStepForward: canStepForward,
                    onStepPeriod: onStepPeriod
                )
                Spacer(minLength: 0)
                loadingIndicator(isLoading)
                GanttRangeChips(range: range)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    GanttModeChips(mode: mode)
                    GanttPeriodStepper(
                        selectedPeriod: selectedPeriod,
                        canStepForward: canStepForward,
                        onStepPeriod: onStepPeriod
                    )
                    Spacer(minLength: 0)
                    loadingIndicator(isLoading)
                }
                HStack {
                    Spacer(minLength: 0)
                    GanttRangeChips(range: range)
                }
            }
        }
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
                    vm.refreshPermissionState()
                    vm.bumpReload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .font(.sora(11))
        }
        .mainWindowPanel(padding: 16)
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

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct GanttRangeChips: View {
    @Binding var range: GanttRange

    var body: some View {
        PillSegmentedBar(
            GanttRange.allCases,
            selection: $range,
            help: { $0.help },
            accessibilityLabel: { $0.label }
        ) { value, _ in
            Text(value.label)
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
    let selectedPeriod: String
    let canStepForward: Bool
    let onStepPeriod: (Int) -> Void

    var body: some View {
        PillTimeStepperBar(
            canStepForward: canStepForward,
            isCenterSelected: true,
            previousHelp: String(localized: "Previous range"),
            nextHelp: String(localized: "Next range"),
            centerAccessibilityLabel: String(localized: "Selected range"),
            accessibilityLabel: String(localized: "Gantt range navigation"),
            onPrevious: { onStepPeriod(-1) },
            onNext: { onStepPeriod(1) }
        ) { _ in
            Text(selectedPeriod)
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

private struct GanttChartPanel: View {
    let snapshot: GanttTimelineSnapshot

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
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PROJECT TIMELINE")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Text(caption)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(rangeLabel)
                .font(.sora(10).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
        }
    }

    private var caption: String {
        switch snapshot.activityMode {
        case .aiActive:
            String(localized: "Each row merges project activity blocks from sessions across all providers.")
        case .assistedFocus:
            String(localized: "Assisted Focus = AI was active while an editor or terminal was in front. It is not precise Screen Time project attribution.")
        }
    }

    private var rangeLabel: String {
        "\(Format.day(snapshot.domain.start)) - \(Format.day(snapshot.domain.end.addingTimeInterval(-1)))"
    }

    private var emptyState: some View {
        Text(snapshot.sourceSessionCount == 0 ? String(localized: "No tracked project sessions yet.") : String(localized: "No project activity in this range."))
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
                GanttProjectRow(project: project)
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
                    providerBadges
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
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format(
            "gantt.project.accessibility.active",
            defaultValue: "%@, %@ active",
            project.displayName,
            Format.duration(project.totalDuration)
        ))
    }

    private var providerBadges: some View {
        HStack(spacing: 3) {
            ForEach(project.providerList) { provider in
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
