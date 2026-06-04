import SwiftUI

struct DailyReportWorkspaceView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var store: DailyReportViewModel
    @State private var projectGitSelection: DailyReportProjectGitSheetSelection?

    private struct ReloadKey: Equatable {
        let month: Date
        let token: UInt64
        let lastRefreshedAt: Date?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: reloadKey) {
            await store.reload(sessions: env.store.sessions)
        }
        .sheet(item: $projectGitSelection) { selection in
            DailyReportProjectGitDetailSheet(selection: selection)
        }
    }

    private var reloadKey: ReloadKey {
        ReloadKey(
            month: store.displayedMonthStart,
            token: store.reloadToken,
            lastRefreshedAt: env.store.lastRefreshedAt
        )
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DAILY REPORT")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Text("Calendar")
                    .font(.sora(24, weight: .semibold))
                    .lineLimit(1)
                Text("AI-active projects by day.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var content: some View {
        DailyReportCalendarSection(store: store, rightColumn: .selectedDay) { project in
            projectGitSelection = DailyReportProjectGitSheetSelection(project: project, day: store.selectedDate)
        }
    }
}

private enum DailyReportRightColumn {
    case selectedDay
    case monthProjects
}

private enum DailyReportLayoutMetrics {
    static let columnSpacing: CGFloat = 12
    static let calendarPreferredWidth: CGFloat = 520
    static let calendarMinimumWidth: CGFloat = 300
    static let calendarDotModeThreshold: CGFloat = 480
    static let projectReadableWidth: CGFloat = 340
    static let projectEmergencyWidth: CGFloat = 260

    static func columns(for availableWidth: CGFloat) -> DailyReportResolvedColumns {
        let width = max(0, availableWidth)
        let spacing = columnSpacing
        let projectReadableLimit = calendarPreferredWidth + spacing + projectReadableWidth

        if width >= projectReadableLimit {
            let calendarWidth = calendarPreferredWidth
            return DailyReportResolvedColumns(
                calendarWidth: calendarWidth,
                projectWidth: width - calendarWidth - spacing,
                usesProjectDots: false
            )
        }

        let projectWidth = min(
            projectReadableWidth,
            max(projectEmergencyWidth, width - spacing - calendarMinimumWidth)
        )
        let calendarWidth = max(calendarMinimumWidth, width - spacing - projectWidth)

        return DailyReportResolvedColumns(
            calendarWidth: calendarWidth,
            projectWidth: projectWidth,
            usesProjectDots: calendarWidth < calendarDotModeThreshold
        )
    }
}

private struct DailyReportResolvedColumns: Equatable {
    let calendarWidth: CGFloat
    let projectWidth: CGFloat
    let usesProjectDots: Bool
}

private struct DailyReportCalendarSection: View {
    @Bindable var store: DailyReportViewModel
    let rightColumn: DailyReportRightColumn
    let onProjectSelected: (DailyReportProjectDaySummary) -> Void

    var body: some View {
        horizontalLayout
    }

    private var horizontalLayout: some View {
        GeometryReader { proxy in
            let layout = DailyReportLayoutMetrics.columns(for: proxy.size.width)

            HStack(alignment: .top, spacing: DailyReportLayoutMetrics.columnSpacing) {
                AppScrollView {
                    calendarColumn(usesProjectDots: layout.usesProjectDots)
                        .padding(.leading, 16)
                        .padding(.vertical, 16)
                }
                .frame(width: layout.calendarWidth, height: proxy.size.height, alignment: .top)

                AppScrollView {
                    projectsColumn
                        .padding(.trailing, 16)
                        .padding(.vertical, 16)
                }
                .frame(width: layout.projectWidth, height: proxy.size.height, alignment: .top)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func calendarColumn(usesProjectDots: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            controls
            DailyReportMonthGrid(store: store, usesProjectDots: usesProjectDots)
                .mainWindowPanel(padding: 10)
        }
    }

    @ViewBuilder
    private var projectsColumn: some View {
        switch rightColumn {
        case .selectedDay:
            DailyReportDayDetailPanel(summary: store.selectedDaySummary, onProjectSelected: onProjectSelected)
        case .monthProjects:
            DailyReportMonthProjectsPanel(snapshot: store.snapshot)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            monthStepper
            Spacer(minLength: 0)
            todayButton
        }
    }

    private var monthStepper: some View {
        PillTimeStepperBar(
            canStepForward: store.canStepForward,
            isCenterSelected: true,
            previousHelp: "Previous month",
            nextHelp: "Next month",
            centerAccessibilityLabel: "Displayed month",
            accessibilityLabel: "Daily report month navigation",
            onPrevious: { stepMonth(-1) },
            onNext: { stepMonth(1) }
        ) { _ in
            Text(store.monthTitle)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.18), value: store.monthTitle)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var todayButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                store.showToday()
            }
        } label: {
            Text("Today")
                .font(.sora(12, weight: .medium))
                .lineLimit(1)
                .frame(minWidth: 58)
                .frame(height: PillTimeStepperBarStyle.standard.totalHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .help("Jump to today")
    }

    private func stepMonth(_ delta: Int) {
        withAnimation(.easeOut(duration: 0.18)) {
            store.stepMonth(delta)
        }
    }
}

private struct DailyReportMonthGrid: View {
    @Bindable var store: DailyReportViewModel
    let usesProjectDots: Bool

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: usesProjectDots ? 34 : 56), spacing: 6, alignment: .top),
            count: 7
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.sora(9, weight: .semibold))
                        .foregroundStyle(Color.stxMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(store.snapshot.visibleDays) { day in
                    DailyReportDayCell(
                        day: day,
                        isSelected: Calendar.current.isDate(day.date, inSameDayAs: store.selectedDate),
                        isToday: Calendar.current.isDateInToday(day.date),
                        usesProjectDots: usesProjectDots
                    ) {
                        store.selectDate(day.date)
                    }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % symbols.count] }
    }
}

private struct DailyReportDayCell: View {
    let day: DailyReportCalendarDay
    let isSelected: Bool
    let isToday: Bool
    let usesProjectDots: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Calendar.current.component(.day, from: day.date))")
                        .font(.sora(11, weight: isToday ? .semibold : .regular))
                        .foregroundStyle(day.isInDisplayedMonth ? Color.primary : Color.stxMuted.opacity(0.65))
                    Spacer(minLength: 4)
                    if day.summary.projectCount > 0 {
                        Text("\(day.summary.projectCount)")
                            .font(.sora(8, weight: .semibold).monospacedDigit())
                            .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    if usesProjectDots {
                        DailyReportProjectDots(count: day.summary.projectCount, isSelected: isSelected)
                    } else {
                        ForEach(day.summary.projects.prefix(1)) { project in
                            DailyReportProjectMiniRow(project: project)
                        }
                        let overflow = day.summary.projects.count - 1
                        if overflow > 0 {
                            Text("+\(overflow) more")
                                .font(.sora(9))
                                .foregroundStyle(Color.stxMuted)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(5)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1.2 : 1)
            }
            .opacity(day.isInDisplayedMonth ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var backgroundColor: Color {
        if isSelected { return Color.stxAccent.opacity(0.10) }
        if day.summary.projectCount > 0 { return Color.primary.opacity(0.045) }
        return Color.primary.opacity(0.025)
    }

    private var borderColor: Color {
        if isSelected { return Color.stxAccent.opacity(0.75) }
        if isToday { return Color.stxAccent.opacity(0.35) }
        return Color.primary.opacity(0.08)
    }

    private var helpText: String {
        if day.summary.isEmpty {
            return day.date.formatted(date: .abbreviated, time: .omitted)
        }
        return "\(day.summary.projectCount) projects · \(Format.duration(day.summary.totalActiveDuration)) · \(Format.tokens(day.summary.totalTokens)) tokens"
    }
}

private struct DailyReportProjectDots: View {
    let count: Int
    let isSelected: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 4, maximum: 4), spacing: 3, alignment: .leading)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 3) {
            ForEach(0..<count, id: \.self) { _ in
                Circle()
                    .fill(dotColor)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 1)
    }

    private var dotColor: Color {
        isSelected ? Color.stxAccent : Color.stxMuted.opacity(0.85)
    }
}

private struct DailyReportProjectMiniRow: View {
    let project: DailyReportProjectDaySummary

    var body: some View {
        Text(project.displayName)
            .font(.sora(9, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DailyReportDayDetailPanel: View {
    let summary: DailyReportDaySummary
    let onProjectSelected: (DailyReportProjectDaySummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                        .font(.sora(17, weight: .semibold))
                    Text("\(summary.projectCount) projects · \(Format.duration(summary.totalActiveDuration)) · \(Format.tokens(summary.totalTokens)) tokens")
                        .font(.sora(12))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 12)
                if summary.totalGitCommitCount > 0 {
                    DailyReportMetricPill(symbol: AppIcon.Workspace.git, text: "\(summary.totalGitCommitCount) commits")
                }
            }

            if summary.projects.isEmpty {
                DailyReportEmptyState(
                    title: "No AI activity",
                    detail: "No provider sessions touched a project on this day."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(summary.projects) { project in
                        DailyReportProjectDayRow(project: project) {
                            onProjectSelected(project)
                        }
                    }
                }
            }
        }
        .mainWindowPanel(padding: 16)
    }
}

private struct DailyReportProjectDayRow: View {
    let project: DailyReportProjectDaySummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.displayName)
                        .font(.sora(13, weight: .semibold))
                        .lineLimit(1)
                    if let path = project.path {
                        Text(path)
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                HStack(spacing: 6) {
                    DailyReportMetricPill(symbol: AppIcon.Status.clock, text: Format.duration(project.activeDuration))
                    DailyReportMetricPill(symbol: AppIcon.Workspace.usage, text: Format.tokens(project.tokens))
                    DailyReportMetricPill(symbol: AppIcon.Resource.conversation, text: "\(project.sessionCount)")
                    if project.gitCommitCount > 0 {
                        DailyReportMetricPill(symbol: AppIcon.Workspace.git, text: "\(project.gitCommitCount)")
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.035)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open git commits and AI summary")
    }
}

private struct DailyReportMonthProjectsPanel: View {
    let snapshot: DailyReportMonthSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if snapshot.projects.isEmpty {
                DailyReportEmptyState(
                    title: "No project activity",
                    detail: "This month has no AI-active projects yet."
                )
                .mainWindowPanel(padding: 16)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(snapshot.projects) { project in
                        DailyReportProjectMonthRow(project: project)
                    }
                }
                .mainWindowPanel(padding: 12)
            }
        }
    }
}

private struct DailyReportProjectMonthRow: View {
    let project: DailyReportProjectMonthSummary

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.displayName)
                    .font(.sora(13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(project.activeDays) active days")
                    if let latest = project.latestActivity {
                        Text("Latest \(Format.relativeDate(latest))")
                    }
                }
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            DailyReportMetricPill(symbol: AppIcon.Status.clock, text: Format.duration(project.activeDuration))
            DailyReportMetricPill(symbol: AppIcon.Workspace.usage, text: Format.tokens(project.tokens))
            DailyReportMetricPill(symbol: AppIcon.Resource.conversation, text: "\(project.sessionCount)")
            if project.gitCommitCount > 0 {
                DailyReportMetricPill(symbol: AppIcon.Workspace.git, text: "\(project.gitCommitCount)")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.035)))
    }
}

private struct DailyReportMetricPill: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(.sora(10).monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.055)))
    }
}

private struct DailyReportEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.sora(14, weight: .semibold))
            Text(detail)
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

#if DEBUG
#Preview("Daily Report workspace") {
    return DailyReportWorkspaceView(store: DailyReportViewModel())
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 760)
        .background(Color.stxBackground)
}
#endif
