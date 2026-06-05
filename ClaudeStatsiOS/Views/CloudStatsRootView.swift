import ClaudeStatsCore
import ClaudeStatsSync
import SwiftUI

struct CloudStatsRootView: View {
    let store: CloudStatsSnapshotStore

    var body: some View {
        Group {
            switch store.state {
            case .idle, .loading:
                loadingView
            case .empty(let message):
                CloudStatsTabView(
                    store: store,
                    snapshot: StatsSnapshot.empty(appVersion: "No Snapshot"),
                    accountStatus: store.accountStatus,
                    availability: .placeholder(message),
                    refresh: { Task { await store.load() } }
                )
            case .failed(let message):
                failureView(message)
            case .loaded:
                if let snapshot = store.snapshot {
                    CloudStatsTabView(
                        store: store,
                        snapshot: snapshot,
                        accountStatus: store.accountStatus,
                        availability: store.usesSampleData ? .sample : .synced
                    ) {
                        Task { await store.load() }
                    }
                } else {
                    CloudStatsTabView(
                        store: store,
                        snapshot: StatsSnapshot.empty(appVersion: "No Snapshot"),
                        accountStatus: store.accountStatus,
                        availability: .placeholder("Open Claude Stats Lite on your Mac and let it sync a snapshot to iCloud."),
                        refresh: { Task { await store.load() } }
                    )
                }
            }
        }
        .task {
            if store.state == .idle {
                await store.load()
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Loading iCloud stats")
                .font(.headline)
            Text(store.accountStatus.displayText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Could Not Load Stats", systemImage: "exclamationmark.icloud")
        } description: {
            Text(message.isEmpty ? store.accountStatus.displayText : message)
        } actions: {
            Button("Retry") {
                Task { await store.load() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private enum CloudStatsDataAvailability: Equatable {
    case synced
    case sample
    case placeholder(String)

    var isPlaceholder: Bool {
        switch self {
        case .synced, .sample: false
        case .placeholder: true
        }
    }

    var message: String? {
        switch self {
        case .synced, .sample: nil
        case .placeholder(let message): message
        }
    }
}

private enum CloudStatsSheet: Identifiable {
    case settings

    var id: String {
        switch self {
        case .settings: "settings"
        }
    }
}

private struct CloudStatsTabView: View {
    let store: CloudStatsSnapshotStore
    let snapshot: StatsSnapshot
    let accountStatus: CloudStatsAccountStatus
    let availability: CloudStatsDataAvailability
    let refresh: () -> Void

    @State private var activeSheet: CloudStatsSheet?
    @State private var statusPreferences = StatsStatusDisplayPreferencesStore()

    var body: some View {
        TabView {
            NavigationStack {
                DashboardScreen(
                    snapshot: snapshot,
                    accountStatus: accountStatus,
                    availability: availability,
                    statusPreferences: statusPreferences,
                    refresh: refresh,
                    openSettings: openSettings
                )
            }
            .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent") }

            NavigationStack {
                StatsScreen(snapshot: snapshot, availability: availability, openSettings: openSettings)
            }
            .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }

            NavigationStack {
                ToolScreen(snapshot: snapshot, availability: availability, openSettings: openSettings)
            }
            .tabItem { Label("Tool", systemImage: "wrench.and.screwdriver") }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings:
                #if CLAUDE_STATS_DEV_TOOLS
                CloudStatsSettingsView(
                    statusSummary: snapshot.statusSummary,
                    statusPreferences: statusPreferences,
                    loadSampleData: loadSampleData
                )
                #else
                CloudStatsSettingsView(
                    statusSummary: snapshot.statusSummary,
                    statusPreferences: statusPreferences
                )
                #endif
            }
        }
    }

    private func openSettings() {
        activeSheet = .settings
    }

    #if CLAUDE_STATS_DEV_TOOLS
    private func loadSampleData() {
        activeSheet = nil
        store.loadSampleData()
    }
    #endif
}

private struct SettingsToolbarButton: View {
    let openSettings: () -> Void

    var body: some View {
        Button(action: openSettings) {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
    }
}

private struct DashboardScreen: View {
    let snapshot: StatsSnapshot
    let accountStatus: CloudStatsAccountStatus
    let availability: CloudStatsDataAvailability
    let statusPreferences: StatsStatusDisplayPreferencesStore
    let refresh: () -> Void
    let openSettings: () -> Void

    private let metricColumns = [
        GridItem(.adaptive(minimum: 104, maximum: 136), spacing: 10),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let message = availability.message {
                    SnapshotStatusBanner(message: message)
                }
                LazyVGrid(columns: metricColumns, spacing: 10) {
                    MetricTile(title: "Tokens", value: StatsFormat.tokens(snapshot.dashboardSummary.totalTokens), symbol: "sum")
                    MetricTile(title: "Cost", value: StatsFormat.cost(snapshot.dashboardSummary.totalCost), symbol: "dollarsign")
                    MetricTile(title: "Sessions", value: "\(snapshot.dashboardSummary.sessionCount)", symbol: "rectangle.stack")
                    MetricTile(title: "Projects", value: "\(snapshot.dashboardSummary.activeProjectCount)", symbol: "folder")
                    MetricTile(title: "AI Time", value: StatsFormat.duration(snapshot.activitySummary.totalAISeconds), symbol: "clock")
                    MetricTile(title: "Active Days", value: "\(snapshot.activitySummary.activeDayCount)", symbol: "calendar.badge.clock")
                }
                .frame(maxWidth: 430, alignment: .leading)
                CloudStatsStatusPanel(
                    summary: snapshot.statusSummary,
                    preferences: statusPreferences
                )
                BarChartCard(
                    title: "Usage Trend",
                    subtitle: "Last 7 synced days",
                    points: snapshot.dailyTokenChartPoints(),
                    tint: .teal,
                    emptyCaption: "Chart ready. No synced usage yet."
                )
                BarChartCard(
                    title: "Token Mix",
                    subtitle: "Input, output, and cache",
                    points: snapshot.tokenMixChartPoints(),
                    tint: .indigo,
                    emptyCaption: "Chart ready. No token mix yet."
                )
                providerSection
                usageLimitSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Claude Stats")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")

                SettingsToolbarButton(openSettings: openSettings)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerTitle)
                .font(.headline)
            Text(headerSubtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerTitle: String {
        switch availability {
        case .synced:
            "Synced \(StatsFormat.shortDate(snapshot.generatedAt))"
        case .sample:
            "Sample Data \(StatsFormat.shortDate(snapshot.generatedAt))"
        case .placeholder:
            "Waiting for synced data"
        }
    }

    private var headerSubtitle: String {
        switch availability {
        case .sample:
            "Debug fixture - \(snapshot.appVersion)"
        case .synced, .placeholder:
            "\(accountStatus.displayText) - \(snapshot.appVersion)"
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Providers")
            if snapshot.dashboardSummary.providerSummaries.isEmpty {
                EmptyRow(text: "No provider usage in this snapshot.")
            } else {
                ForEach(snapshot.dashboardSummary.providerSummaries) { provider in
                    ValueRow(
                        title: provider.name,
                        subtitle: "\(provider.sessionCount) sessions",
                        value: StatsFormat.tokens(provider.totalTokens)
                    )
                }
            }
        }
    }

    private var usageLimitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Usage Limits")
            if snapshot.usageLimitSnapshots.isEmpty {
                EmptyRow(text: "No usage limit snapshot has been synced yet.")
            } else {
                ForEach(snapshot.usageLimitSnapshots) { limit in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(limit.providerName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(limit.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(limit.windows) { window in
                            ProgressRow(title: window.label, percent: window.usedPercent)
                        }
                    }
                    .panelStyle()
                }
            }
        }
    }
}

private struct StatsScreen: View {
    let snapshot: StatsSnapshot
    let availability: CloudStatsDataAvailability
    let openSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let message = availability.message {
                    SnapshotStatusBanner(message: message)
                }

                BarChartCard(
                    title: "Period Usage",
                    subtitle: "Token totals by range",
                    points: snapshot.periodUsageChartPoints(),
                    tint: .blue,
                    emptyCaption: "Chart ready. No period totals yet."
                )

                BarChartCard(
                    title: "Daily Activity",
                    subtitle: "AI minutes by day",
                    points: snapshot.activityMinuteChartPoints(),
                    tint: .mint,
                    emptyCaption: "Chart ready. No activity minutes yet."
                )

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Usage Summary")
                    ForEach(StatsPeriodIdentifier.allCases) { period in
                        let bucket = snapshot.summaryBucket(period: period)
                        ValueRow(
                            title: period.displayName,
                            subtitle: "\(bucket?.sessionCount ?? 0) sessions - \(bucket?.messageCount ?? 0) messages",
                            value: StatsFormat.tokens(bucket?.usage.totalTokens ?? 0)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Top Models")
                    let models = snapshot.modelBreakdowns
                        .filter { $0.providerID == nil && $0.period == .last30Days }
                        .sorted { $0.usage.totalTokens > $1.usage.totalTokens }
                    if models.isEmpty {
                        EmptyRow(text: "Model rows will appear after the Mac snapshot includes usage.")
                    } else {
                        ForEach(models.prefix(12)) { model in
                            ValueRow(
                                title: model.model,
                                subtitle: "\(model.messageCount) messages - \(StatsFormat.cost(model.estimatedCost))",
                                value: StatsFormat.tokens(model.usage.totalTokens)
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Daily Reports")
                    if snapshot.dailyReports.isEmpty {
                        EmptyRow(text: "Daily report rows will appear after the Mac snapshot includes reports.")
                    } else {
                        ForEach(snapshot.dailyReports.sorted { $0.day > $1.day }.prefix(30)) { report in
                            ValueRow(
                                title: StatsFormat.day(report.day),
                                subtitle: "\(report.projectCount) projects - \(report.sessionCount) sessions",
                                value: StatsFormat.tokens(report.totalTokens)
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Stats")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsToolbarButton(openSettings: openSettings)
            }
        }
    }
}

private struct ToolScreen: View {
    let snapshot: StatsSnapshot
    let availability: CloudStatsDataAvailability
    let openSettings: () -> Void

    @State private var selectedMode: ToolContentMode = .dailyReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                toolModePicker

                if let message = availability.message {
                    SnapshotStatusBanner(message: message)
                }

                selectedContent
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Tool")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsToolbarButton(openSettings: openSettings)
            }
        }
    }

    private var toolModePicker: some View {
        Picker("Tool Content", selection: $selectedMode) {
            ForEach(ToolContentMode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Tool content")
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedMode {
        case .dailyReport:
            dailyReportSection
        case .gantt:
            ganttSection
        case .git:
            gitSection
        }
    }

    private var dailyReportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Daily Report")
            if snapshot.dailyReports.isEmpty {
                EmptyRow(text: "Daily report rows will appear after the Mac snapshot includes reports.")
            } else {
                ForEach(snapshot.dailyReports.sorted { $0.day > $1.day }.prefix(30)) { report in
                    ValueRow(
                        title: StatsFormat.day(report.day),
                        subtitle: "\(report.projectCount) projects - \(report.sessionCount) sessions - \(report.messageCount) messages",
                        value: StatsFormat.tokens(report.totalTokens)
                    )
                }
            }
        }
    }

    private var ganttSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SyncedGanttTimelineCard(timeline: snapshot.ganttTimeline)
        }
    }

    private var gitSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            BarChartCard(
                title: "Git Activity",
                subtitle: "Repository churn",
                points: snapshot.gitActivityChartPoints(),
                tint: .orange,
                emptyCaption: "Chart ready. No repository activity yet."
            )

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Git Overview")
                ValueRow(title: "Repos", subtitle: "Loaded on Mac", value: "\(snapshot.gitActivitySummary.totalRepositories)")
                ValueRow(title: "Commits", subtitle: "Current Git view range", value: "\(snapshot.gitActivitySummary.totalCommits)")
                ValueRow(title: "Lines +/-", subtitle: "Insertions / deletions", value: "\(snapshot.gitActivitySummary.totalInsertions)/\(snapshot.gitActivitySummary.totalDeletions)")
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Repositories")
                if snapshot.gitActivitySummary.rows.isEmpty {
                    EmptyRow(text: "Repository rows will appear after the Mac snapshot includes Git activity.")
                } else {
                    ForEach(snapshot.gitActivitySummary.rows) { row in
                        ValueRow(
                            title: row.label,
                            subtitle: "\(row.commitCount) commits",
                            value: StatsFormat.tokens(row.churn)
                        )
                    }
                }
            }
        }
    }
}

private enum ToolContentMode: String, CaseIterable, Identifiable {
    case dailyReport
    case gantt
    case git

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dailyReport: "Daily Report"
        case .gantt: "Gantt"
        case .git: "Git"
        }
    }
}

private struct ActivityScreen: View {
    let snapshot: StatsSnapshot

    var body: some View {
        List {
            Section("Overview") {
                ValueRow(
                    title: "AI Active Time",
                    subtitle: snapshot.activitySummary.sourceLabel,
                    value: StatsFormat.duration(snapshot.activitySummary.totalAISeconds)
                )
                ValueRow(
                    title: "Active Days",
                    subtitle: "Last 30 synced days",
                    value: "\(snapshot.activitySummary.activeDayCount)"
                )
                if snapshot.activitySummary.hasFocusData {
                    ValueRow(
                        title: "Assisted Time",
                        subtitle: "Coding surface and AI overlap",
                        value: StatsFormat.duration(snapshot.activitySummary.totalOverlapSeconds)
                    )
                    ValueRow(
                        title: "CLI AI Time",
                        subtitle: "Terminal and AI overlap",
                        value: StatsFormat.duration(snapshot.activitySummary.totalCLIAIOverlapSeconds)
                    )
                } else {
                    EmptyRow(text: "iOS displays synced Mac aggregates only. Coding-surface overlap is not collected on this device.")
                }
            }

            Section("Daily Activity") {
                let days = snapshot.activitySummary.days.sorted { $0.day > $1.day }
                if days.isEmpty || days.allSatisfy({ $0.aiSeconds <= 0 && $0.sessionCount == 0 }) {
                    EmptyRow(text: "No activity summary was synced.")
                } else {
                    ForEach(days.prefix(30)) { day in
                        ValueRow(
                            title: StatsFormat.day(day.day),
                            subtitle: "\(day.sessionCount) sessions - \(day.messageCount) messages - \(day.burstCount) bursts",
                            value: StatsFormat.duration(day.aiSeconds)
                        )
                    }
                }
            }
        }
        .navigationTitle("Activity")
    }
}

private struct SnapshotStatusBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "icloud.slash")
                .font(.body.weight(.semibold))
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 3) {
                Text("No synced data yet")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .panelStyle()
    }
}

private struct ChartPoint: Identifiable, Hashable {
    let id: String
    let label: String
    let value: Double
    let detail: String

    init(id: String, label: String, value: Double, detail: String = "") {
        self.id = id
        self.label = label
        self.value = max(0, value)
        self.detail = detail
    }
}

private struct BarChartCard: View {
    let title: String
    let subtitle: String
    let points: [ChartPoint]
    let tint: Color
    let emptyCaption: String

    private var maxValue: Double {
        max(points.map(\.value).max() ?? 0, 1)
    }

    private var hasData: Bool {
        points.contains { $0.value > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(hasData ? StatsFormat.tokens(Int(maxValue.rounded())) : "0")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ZStack {
                chartGrid
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(points) { point in
                        ChartBar(point: point, maxValue: maxValue, tint: tint, hasData: hasData)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.top, 8)
            }
            .frame(height: 152)

            if !hasData {
                Text(emptyCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .panelStyle()
    }

    private var chartGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                Divider()
                    .opacity(index == 3 ? 0.5 : 0.25)
                if index < 3 {
                    Spacer()
                }
            }
        }
        .padding(.bottom, 24)
    }
}

private struct ChartBar: View {
    let point: ChartPoint
    let maxValue: Double
    let tint: Color
    let hasData: Bool

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(point.value > 0 ? tint : Color(.tertiarySystemFill))
                        .frame(height: barHeight(in: proxy.size.height))
                }
            }
            Text(point.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(point.label), \(point.detail.isEmpty ? StatsFormat.tokens(Int(point.value.rounded())) : point.detail)")
    }

    private func barHeight(in availableHeight: CGFloat) -> CGFloat {
        if point.value <= 0 {
            return hasData ? 3 : 6
        }
        let ratio = point.value / maxValue
        return max(6, availableHeight * CGFloat(ratio))
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.teal)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
    }
}

private struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
    }
}

private struct ValueRow: View {
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .panelStyle()
    }
}

private struct EmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelStyle()
    }
}

private struct ProgressRow: View {
    let title: String
    let percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(StatsFormat.percentPoints(percent))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(100, max(0, percent)), total: 100)
                .tint(percent >= 85 ? .orange : .teal)
        }
    }
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension StatsSnapshot {
    func summaryBucket(period: StatsPeriodIdentifier) -> StatsUsageBucket? {
        usageBuckets.first { $0.providerID == nil && $0.period == period && $0.granularity == .period }
    }

    func periodUsageChartPoints() -> [ChartPoint] {
        StatsPeriodIdentifier.allCases.map { period in
            let bucket = summaryBucket(period: period)
            return ChartPoint(
                id: period.id,
                label: period.shortDisplayName,
                value: Double(bucket?.usage.totalTokens ?? 0),
                detail: StatsFormat.tokens(bucket?.usage.totalTokens ?? 0)
            )
        }
    }

    func tokenMixChartPoints() -> [ChartPoint] {
        let usage = summaryBucket(period: .last30Days)?.usage ?? summaryBucket(period: .allTime)?.usage ?? .zero
        return [
            ChartPoint(id: "input", label: "Input", value: Double(usage.inputTokens), detail: StatsFormat.tokens(usage.inputTokens)),
            ChartPoint(id: "output", label: "Output", value: Double(usage.outputTokens), detail: StatsFormat.tokens(usage.outputTokens)),
            ChartPoint(id: "cache-read", label: "Cache", value: Double(usage.cacheReadTokens), detail: StatsFormat.tokens(usage.cacheReadTokens)),
            ChartPoint(
                id: "cache-write",
                label: "Write",
                value: Double(usage.cacheCreation5mTokens + usage.cacheCreation1hTokens),
                detail: StatsFormat.tokens(usage.cacheCreation5mTokens + usage.cacheCreation1hTokens)
            ),
        ]
    }

    func dailyTokenChartPoints() -> [ChartPoint] {
        var reportsByDay: [Date: StatsDailyReport] = [:]
        for report in dailyReports {
            reportsByDay[Calendar.current.startOfDay(for: report.day)] = report
        }
        return recentDays().map { day in
            let report = reportsByDay[day]
            return ChartPoint(
                id: "tokens-\(Int(day.timeIntervalSince1970))",
                label: StatsFormat.day(day),
                value: Double(report?.totalTokens ?? 0),
                detail: StatsFormat.tokens(report?.totalTokens ?? 0)
            )
        }
    }

    func activityMinuteChartPoints() -> [ChartPoint] {
        var daysByDay: [Date: StatsActivityDay] = [:]
        for activityDay in activitySummary.days {
            daysByDay[Calendar.current.startOfDay(for: activityDay.day)] = activityDay
        }
        return recentDays().map { day in
            let activityDay = daysByDay[day]
            let minutes = (activityDay?.aiSeconds ?? 0) / 60
            return ChartPoint(
                id: "activity-\(Int(day.timeIntervalSince1970))",
                label: StatsFormat.day(day),
                value: minutes,
                detail: StatsFormat.duration(activityDay?.aiSeconds ?? 0)
            )
        }
    }

    func gitActivityChartPoints() -> [ChartPoint] {
        if gitActivitySummary.rows.isEmpty {
            return [
                ChartPoint(id: "repos", label: "Repos", value: Double(gitActivitySummary.totalRepositories), detail: "\(gitActivitySummary.totalRepositories)"),
                ChartPoint(id: "commits", label: "Commits", value: Double(gitActivitySummary.totalCommits), detail: "\(gitActivitySummary.totalCommits)"),
                ChartPoint(id: "files", label: "Files", value: Double(gitActivitySummary.totalFilesChanged), detail: "\(gitActivitySummary.totalFilesChanged)"),
            ]
        }
        return gitActivitySummary.rows.prefix(6).map { row in
            ChartPoint(
                id: row.id,
                label: row.label,
                value: Double(row.churn),
                detail: StatsFormat.tokens(row.churn)
            )
        }
    }

    private func recentDays(count: Int = 7) -> [Date] {
        let calendar = Calendar.current
        let sourceDays = Set(dailyReports.map { calendar.startOfDay(for: $0.day) } + activitySummary.days.map { calendar.startOfDay(for: $0.day) })
        let endDay = sourceDays.max() ?? calendar.startOfDay(for: generatedAt)
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - count + 1, to: endDay)
        }
    }
}

private extension StatsPeriodIdentifier {
    var shortDisplayName: String {
        switch self {
        case .today: "Today"
        case .last7Days: "7d"
        case .last30Days: "30d"
        case .allTime: "All"
        }
    }
}
