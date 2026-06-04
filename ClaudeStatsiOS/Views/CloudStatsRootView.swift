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
                emptyView(message)
            case .failed(let message):
                failureView(message)
            case .loaded:
                if let snapshot = store.snapshot {
                    CloudStatsTabView(snapshot: snapshot, accountStatus: store.accountStatus) {
                        Task { await store.load() }
                    }
                } else {
                    emptyView("Open Claude Stats Lite on your Mac and let it sync a snapshot to iCloud.")
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

    private func emptyView(_ message: String) -> some View {
        ContentUnavailableView(
            "No Synced Stats",
            systemImage: "icloud.slash",
            description: Text(message)
        )
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

private struct CloudStatsTabView: View {
    let snapshot: StatsSnapshot
    let accountStatus: CloudStatsAccountStatus
    let refresh: () -> Void

    var body: some View {
        TabView {
            NavigationStack {
                DashboardScreen(snapshot: snapshot, accountStatus: accountStatus, refresh: refresh)
            }
            .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent") }

            NavigationStack {
                UsageScreen(snapshot: snapshot)
            }
            .tabItem { Label("Usage", systemImage: "chart.bar.xaxis") }

            NavigationStack {
                LeaderboardsScreen(snapshot: snapshot)
            }
            .tabItem { Label("Boards", systemImage: "list.number") }

            NavigationStack {
                ActivityScreen(snapshot: snapshot)
            }
            .tabItem { Label("Activity", systemImage: "waveform.path.ecg") }

            NavigationStack {
                ReportsScreen(snapshot: snapshot)
            }
            .tabItem { Label("Reports", systemImage: "calendar") }

            NavigationStack {
                GanttScreen(snapshot: snapshot)
            }
            .tabItem { Label("Gantt", systemImage: "timeline.selection") }

            NavigationStack {
                GitScreen(snapshot: snapshot)
            }
            .tabItem { Label("Git", systemImage: "point.3.connected.trianglepath.dotted") }
        }
    }
}

private struct DashboardScreen: View {
    let snapshot: StatsSnapshot
    let accountStatus: CloudStatsAccountStatus
    let refresh: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                LazyVGrid(columns: columns, spacing: 10) {
                    MetricTile(title: "Tokens", value: StatsFormat.tokens(snapshot.dashboardSummary.totalTokens), symbol: "sum")
                    MetricTile(title: "Cost", value: StatsFormat.cost(snapshot.dashboardSummary.totalCost), symbol: "dollarsign")
                    MetricTile(title: "Sessions", value: "\(snapshot.dashboardSummary.sessionCount)", symbol: "rectangle.stack")
                    MetricTile(title: "Projects", value: "\(snapshot.dashboardSummary.activeProjectCount)", symbol: "folder")
                    MetricTile(title: "AI Time", value: StatsFormat.duration(snapshot.activitySummary.totalAISeconds), symbol: "clock")
                    MetricTile(title: "Active Days", value: "\(snapshot.activitySummary.activeDayCount)", symbol: "calendar.badge.clock")
                }
                providerSection
                usageLimitSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Claude Stats")
        .toolbar {
            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Synced \(StatsFormat.shortDate(snapshot.generatedAt))")
                .font(.headline)
            Text("\(accountStatus.displayText) - \(snapshot.appVersion)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct UsageScreen: View {
    let snapshot: StatsSnapshot

    var body: some View {
        List {
            Section("Summary") {
                ForEach(StatsPeriodIdentifier.allCases) { period in
                    if let bucket = snapshot.summaryBucket(period: period) {
                        ValueRow(
                            title: period.displayName,
                            subtitle: "\(bucket.sessionCount) sessions - \(bucket.messageCount) messages",
                            value: StatsFormat.tokens(bucket.usage.totalTokens)
                        )
                    }
                }
            }

            Section("Top Models") {
                let models = snapshot.modelBreakdowns
                    .filter { $0.providerID == nil && $0.period == .last30Days }
                    .sorted { $0.usage.totalTokens > $1.usage.totalTokens }
                if models.isEmpty {
                    EmptyRow(text: "No model breakdown was synced.")
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
        }
        .navigationTitle("Usage")
    }
}

private struct LeaderboardsScreen: View {
    let snapshot: StatsSnapshot

    var body: some View {
        List {
            Section("Status") {
                ValueRow(
                    title: snapshot.leaderboardSummary.isEnabled ? "Joined" : "Not Joined",
                    subtitle: snapshot.leaderboardSummary.accountText,
                    value: snapshot.leaderboardSummary.statusText
                )
                if let realtime = snapshot.leaderboardSummary.realtimeStatusText, !realtime.isEmpty {
                    ValueRow(title: "Realtime", subtitle: "Mac sync state", value: realtime)
                }
                if let periodKey = snapshot.leaderboardSummary.lastLoadedPeriodKey, !periodKey.isEmpty {
                    ValueRow(title: "Loaded Period", subtitle: "Visible board range", value: periodKey)
                }
            }

            Section("Local Scores") {
                if snapshot.leaderboardSummary.localScores.isEmpty {
                    EmptyRow(text: "No local leaderboard scores were synced.")
                } else {
                    ForEach(snapshot.leaderboardSummary.localScores) { score in
                        ValueRow(
                            title: "\(score.periodName) - \(score.metricName)",
                            subtitle: score.periodKey,
                            value: leaderboardScore(score.score, metricID: score.metricID)
                        )
                    }
                }
            }

            Section("Visible Board") {
                if let error = snapshot.leaderboardSummary.errorMessage, !error.isEmpty {
                    EmptyRow(text: error)
                } else if snapshot.leaderboardSummary.visibleRows.isEmpty {
                    EmptyRow(text: snapshot.leaderboardSummary.emptyMessage ?? "Open Leaderboards on Mac to sync visible rows.")
                } else {
                    ForEach(snapshot.leaderboardSummary.visibleRows) { row in
                        ValueRow(
                            title: "#\(row.rank) \(row.displayName)",
                            subtitle: "\(row.periodName) - \(row.metricName)",
                            value: leaderboardScore(row.score, metricID: row.metricID)
                        )
                    }
                }
            }

            Section("Favorite Models") {
                if snapshot.leaderboardSummary.favoriteModels.isEmpty {
                    EmptyRow(text: "No favorite model summary was synced.")
                } else {
                    ForEach(snapshot.leaderboardSummary.favoriteModels) { model in
                        ValueRow(
                            title: "#\(model.rank) \(model.model)",
                            subtitle: "Personal model mix",
                            value: StatsFormat.tokens(clampedInt(model.tokens))
                        )
                    }
                }
            }
        }
        .navigationTitle("Leaderboards")
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

private struct ReportsScreen: View {
    let snapshot: StatsSnapshot

    var body: some View {
        List {
            Section("Daily Reports") {
                if snapshot.dailyReports.isEmpty {
                    EmptyRow(text: "No daily report summaries were synced.")
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
        .navigationTitle("Reports")
    }
}

private struct GanttScreen: View {
    let snapshot: StatsSnapshot

    var body: some View {
        List {
            Section("Recent Timeline") {
                if snapshot.ganttTimeline.segments.isEmpty {
                    EmptyRow(text: "No Gantt segments were synced.")
                } else {
                    ForEach(snapshot.ganttTimeline.segments.sorted { $0.start > $1.start }) { segment in
                        let duration = segment.end.timeIntervalSince(segment.start)
                        ValueRow(
                            title: segment.label,
                            subtitle: "\(StatsFormat.shortDate(segment.start)) - \(StatsFormat.duration(duration))",
                            value: StatsFormat.tokens(segment.tokenCount)
                        )
                    }
                }
            }
        }
        .navigationTitle("Gantt")
    }
}

private struct GitScreen: View {
    let snapshot: StatsSnapshot

    var body: some View {
        List {
            Section("Overview") {
                ValueRow(title: "Repos", subtitle: "Loaded on Mac", value: "\(snapshot.gitActivitySummary.totalRepositories)")
                ValueRow(title: "Commits", subtitle: "Current Git view range", value: "\(snapshot.gitActivitySummary.totalCommits)")
                ValueRow(title: "Lines +/-", subtitle: "Insertions / deletions", value: "\(snapshot.gitActivitySummary.totalInsertions)/\(snapshot.gitActivitySummary.totalDeletions)")
            }

            Section("Repositories") {
                if snapshot.gitActivitySummary.rows.isEmpty {
                    EmptyRow(text: "Open Git in Claude Stats Lite on Mac to sync repository activity.")
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
        .navigationTitle("Git")
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

private func leaderboardScore(_ score: Int64, metricID: String) -> String {
    if metricID == "activityMinutes" {
        return StatsFormat.duration(TimeInterval(score) * 60)
    }
    return StatsFormat.tokens(clampedInt(score))
}

private func clampedInt(_ value: Int64) -> Int {
    Int(min(value, Int64(Int.max)))
}

private extension StatsSnapshot {
    func summaryBucket(period: StatsPeriodIdentifier) -> StatsUsageBucket? {
        usageBuckets.first { $0.providerID == nil && $0.period == period && $0.granularity == .period }
    }
}
