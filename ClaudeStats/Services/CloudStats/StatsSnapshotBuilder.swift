import ClaudeStatsCore
import Foundation

@MainActor
enum StatsSnapshotBuilder {
    private static let periodPairs: [(StatsPeriod, StatsPeriodIdentifier)] = [
        (.today, .today),
        (.last7Days, .last7Days),
        (.last30Days, .last30Days),
        (.allTime, .allTime),
    ]

    static func make(environment env: AppEnvironment, now: Date = .now, calendar: Calendar = .current) -> StatsSnapshot {
        let projectLabels = ProjectLabelCatalog(sessions: env.store.sessions)
        let usageBuckets = makeUsageBuckets(store: env.store, now: now, calendar: calendar)
        let modelBreakdowns = makeModelBreakdowns(store: env.store, now: now)
        let usageLimits = makeUsageLimitSnapshots(usageLimits: env.usageLimits)
        let dailyReports = makeDailyReports(store: env.store, projectLabels: projectLabels, now: now, calendar: calendar)
        let gantt = makeGanttTimeline(sessions: env.store.sessions, projectLabels: projectLabels, now: now, calendar: calendar)
        let git = makeGitActivitySummary(gitActivity: env.gitActivity)
        let leaderboards = makeLeaderboardSummary(environment: env, now: now)
        let activity = makeActivitySummary(store: env.store, now: now, calendar: calendar)
        let dashboard = makeDashboardSummary(store: env.store, projectLabels: projectLabels, now: now)

        return StatsSnapshot(
            generatedAt: now,
            appVersion: appVersion(),
            usageBuckets: usageBuckets,
            modelBreakdowns: modelBreakdowns,
            usageLimitSnapshots: usageLimits,
            dailyReports: dailyReports,
            ganttTimeline: gantt,
            gitActivitySummary: git,
            leaderboardSummary: leaderboards,
            activitySummary: activity,
            dashboardSummary: dashboard
        )
    }

    private static func makeUsageBuckets(store: SessionStore, now: Date, calendar: Calendar) -> [StatsUsageBucket] {
        periodPairs.flatMap { period, periodID in
            let summary = store.summary(for: period, now: now)
            var buckets = [
                usageBucket(
                    id: "all|\(periodID.rawValue)|summary",
                    period: periodID,
                    provider: nil,
                    summary: summary,
                    lowerBound: period.lowerBound(now: now, calendar: calendar) ?? Date.distantPast,
                    now: now
                ),
            ]

            for provider in ProviderKind.allCases {
                let providerSummary = store.summary(for: period, provider: provider, now: now)
                guard providerSummary.sessionCount > 0 || providerSummary.totalTokens > 0 else { continue }
                buckets.append(
                    usageBucket(
                        id: "\(provider.rawValue)|\(periodID.rawValue)|summary",
                        period: periodID,
                        provider: provider,
                        summary: providerSummary,
                        lowerBound: period.lowerBound(now: now, calendar: calendar) ?? Date.distantPast,
                        now: now
                    )
                )
            }

            return buckets
        }
    }

    private static func usageBucket(
        id: String,
        period: StatsPeriodIdentifier,
        provider: ProviderKind?,
        summary: UsageSummary,
        lowerBound: Date,
        now: Date
    ) -> StatsUsageBucket {
        StatsUsageBucket(
            id: id,
            period: period,
            providerID: provider?.rawValue,
            providerName: provider?.displayName,
            granularity: .period,
            start: lowerBound,
            end: now,
            sessionCount: summary.sessionCount,
            messageCount: summary.messageCount,
            usage: statsUsage(summary.totalUsage),
            estimatedCost: summary.totalCost
        )
    }

    private static func makeModelBreakdowns(store: SessionStore, now: Date) -> [StatsModelBreakdown] {
        periodPairs.flatMap { period, periodID in
            var rows: [StatsModelBreakdown] = []
            let summary = store.summary(for: period, now: now)
            rows += modelBreakdowns(prefix: "all|\(periodID.rawValue)", period: periodID, provider: nil, models: summary.models)
            for provider in ProviderKind.allCases {
                let providerSummary = store.summary(for: period, provider: provider, now: now)
                rows += modelBreakdowns(
                    prefix: "\(provider.rawValue)|\(periodID.rawValue)",
                    period: periodID,
                    provider: provider,
                    models: providerSummary.models
                )
            }
            return rows
        }
    }

    private static func modelBreakdowns(
        prefix: String,
        period: StatsPeriodIdentifier,
        provider: ProviderKind?,
        models: [ModelUsage]
    ) -> [StatsModelBreakdown] {
        models.prefix(12).map { model in
            StatsModelBreakdown(
                id: "\(prefix)|\(model.model)",
                period: period,
                providerID: provider?.rawValue,
                providerName: provider?.displayName,
                model: model.model,
                messageCount: model.messageCount,
                usage: statsUsage(model.usage),
                estimatedCost: model.estimatedCost
            )
        }
    }

    private static func makeUsageLimitSnapshots(usageLimits: UsageLimitStore) -> [StatsUsageLimitSnapshot] {
        ProviderKind.allCases.compactMap { provider in
            guard let report = usageLimits.report(for: provider) else { return nil }
            return StatsUsageLimitSnapshot(
                id: provider.rawValue,
                providerID: provider.rawValue,
                providerName: provider.displayName,
                status: report.status.rawValue,
                capturedAt: report.snapshot?.capturedAt,
                sourceLabel: report.snapshot?.sourceLabel,
                message: report.message,
                windows: report.snapshot?.windows.map { window in
                    StatsUsageLimitWindow(
                        id: window.id,
                        label: window.label,
                        usedPercent: window.usedPercent,
                        resetAt: window.resetAt,
                        windowMinutes: window.windowMinutes
                    )
                } ?? []
            )
        }
    }

    private static func makeDailyReports(
        store: SessionStore,
        projectLabels: ProjectLabelCatalog,
        now: Date,
        calendar: Calendar
    ) -> [StatsDailyReport] {
        (0..<30).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)) else {
                return nil
            }
            let summary = store.summary(forDay: day)
            let projects = Set(sessions(on: day, in: store.sessions, calendar: calendar).map { projectLabels.label(for: $0) })
            return StatsDailyReport(
                id: String(Int(day.timeIntervalSince1970)),
                day: day,
                sessionCount: summary.sessionCount,
                messageCount: summary.messageCount,
                totalTokens: summary.totalTokens,
                estimatedCost: summary.totalCost,
                projectCount: projects.count,
                commitCount: 0
            )
        }
    }

    private static func makeGanttTimeline(
        sessions: [Session],
        projectLabels: ProjectLabelCatalog,
        now: Date,
        calendar: Calendar
    ) -> StatsGanttTimeline {
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? calendar.startOfDay(for: now)
        let end = now
        let segments = sessions
            .flatMap { session -> [StatsGanttSegment] in
                guard let stats = session.stats else { return [] }
                let fallbackStart = stats.firstActivity ?? stats.lastActivity ?? session.lastModified
                let fallbackEnd = max(stats.lastActivity ?? fallbackStart, fallbackStart.addingTimeInterval(60))
                let intervals = stats.activityIntervals.isEmpty
                    ? [DateInterval(start: fallbackStart, end: fallbackEnd)]
                    : stats.activityIntervals
                let tokenCount = max(0, stats.totalTokens / max(1, intervals.count))

                return intervals.enumerated().compactMap { index, interval in
                    guard interval.end >= start, interval.start <= end else { return nil }
                    let clippedStart = max(interval.start, start)
                    let clippedEnd = min(max(interval.end, interval.start.addingTimeInterval(60)), end)
                    guard clippedEnd > clippedStart else { return nil }
                    return StatsGanttSegment(
                        id: "\(session.id)|\(index)",
                        label: projectLabels.label(for: session),
                        providerID: session.provider.rawValue,
                        start: clippedStart,
                        end: clippedEnd,
                        tokenCount: tokenCount
                    )
                }
            }
            .sorted { $0.start > $1.start }
            .prefix(80)
        return StatsGanttTimeline(periodStart: start, periodEnd: end, segments: Array(segments))
    }

    private static func makeGitActivitySummary(gitActivity: GitActivityViewModel) -> StatsGitActivitySummary {
        let rows = gitActivity.repos.prefix(12).enumerated().map { index, activity in
            StatsGitRepositoryRow(
                id: "repo-\(index + 1)",
                label: "Repo \(index + 1)",
                commitCount: activity.commitCount,
                churn: activity.churn
            )
        }
        return StatsGitActivitySummary(
            totalRepositories: gitActivity.repos.count,
            totalCommits: gitActivity.totalCommits,
            totalInsertions: gitActivity.totalInsertions,
            totalDeletions: gitActivity.totalDeletions,
            totalFilesChanged: gitActivity.totalFilesChanged,
            rows: rows
        )
    }

    private static func makeLeaderboardSummary(environment env: AppEnvironment, now: Date) -> StatsLeaderboardSummary {
        let isEnabled = AppVariant.isEnabled(.leaderboards) && env.preferences.leaderboardsEnabled
        let includeActivity = env.preferences.aiActivityAnalysisEnabled
        let builder = LeaderboardScoreBuilder()
        let version = appVersion()

        let localScores = builder
            .submissions(
                sessions: env.store.sessions,
                nickname: "You",
                includeActivity: includeActivity,
                now: now,
                appVersion: version
            )
            .sorted { lhs, rhs in
                if lhs.period.rawValue != rhs.period.rawValue {
                    return lhs.period.rawValue < rhs.period.rawValue
                }
                return lhs.metric.rawValue < rhs.metric.rawValue
            }
            .prefix(12)
            .map { submission in
                StatsLeaderboardLocalScore(
                    id: submission.id,
                    metricID: submission.metric.rawValue,
                    metricName: submission.metric.displayName,
                    periodID: submission.period.rawValue,
                    periodName: submission.period.displayName,
                    periodKey: submission.periodKey,
                    score: submission.score,
                    updatedAt: submission.updatedAt
                )
            }

        let currentUserHash = env.leaderboards.currentUserHash
        let visibleRows = env.leaderboards.scores.prefix(25).enumerated().map { index, score in
            let rank = score.rank ?? index + 1
            let isCurrentUser = currentUserHash != nil && score.userHash == currentUserHash
            return StatsLeaderboardRow(
                id: "rank-\(rank)-\(score.metric.rawValue)-\(score.period.rawValue)-\(score.periodKey)",
                rank: rank,
                displayName: isCurrentUser ? "You" : sanitizedLeaderboardName(score.nickname, fallback: "Rank \(rank)"),
                metricID: score.metric.rawValue,
                metricName: score.metric.displayName,
                periodID: score.period.rawValue,
                periodName: score.period.displayName,
                periodKey: score.periodKey,
                score: score.score,
                isCurrentUser: isCurrentUser,
                updatedAt: score.updatedAt
            )
        }

        let favoriteModels = env.leaderboards.currentUserFavoriteModels.prefix(5).map { model in
            StatsLeaderboardFavoriteModel(
                id: "model-\(model.rank)",
                rank: model.rank,
                model: model.model,
                tokens: model.tokens
            )
        }

        return StatsLeaderboardSummary(
            isEnabled: isEnabled,
            statusText: env.leaderboards.leaderboardStatusText,
            accountText: env.leaderboards.accountState.displayText,
            realtimeStatusText: env.leaderboards.leaderboardRealtimeStatusText,
            lastLoadedPeriodKey: env.leaderboards.lastLoadedPeriodKey,
            localScores: Array(localScores),
            visibleRows: visibleRows,
            favoriteModels: Array(favoriteModels),
            errorMessage: env.leaderboards.scoreError,
            emptyMessage: env.leaderboards.scoreEmptyMessage
        )
    }

    private static func makeActivitySummary(store: SessionStore, now: Date, calendar: Calendar) -> StatsActivitySummary {
        let today = calendar.startOfDay(for: now)
        let days = (0..<30).reversed().compactMap { offset -> StatsActivityDay? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return makeActivityDay(day: day, store: store, calendar: calendar)
        }
        return StatsActivitySummary(
            sourceLabel: "Synced AI activity intervals from Mac sessions",
            hasFocusData: false,
            totalAISeconds: days.reduce(0) { $0 + $1.aiSeconds },
            totalCodingSurfaceSeconds: days.reduce(0) { $0 + $1.codingSurfaceSeconds },
            totalOverlapSeconds: days.reduce(0) { $0 + $1.overlapSeconds },
            totalCLIHostSeconds: days.reduce(0) { $0 + $1.cliHostSeconds },
            totalCLIAIOverlapSeconds: days.reduce(0) { $0 + $1.cliAIOverlapSeconds },
            activeDayCount: days.filter { $0.aiSeconds > 0 || $0.sessionCount > 0 }.count,
            days: days
        )
    }

    private static func makeActivityDay(day: Date, store: SessionStore, calendar: Calendar) -> StatsActivityDay {
        let bounds = ActivityAnalyzer.dayBounds(for: day, calendar: calendar)
        let intervals = store.sessions
            .flatMap { $0.stats?.activityIntervals ?? [] }
            .compactMap { ActivityAnalyzer.clip($0, to: bounds) }
        let aiIntervals = ActivityAnalyzer.union(intervals)
        let summary = store.summary(forDay: day)
        return StatsActivityDay(
            id: String(Int(bounds.start.timeIntervalSince1970)),
            day: bounds.start,
            aiSeconds: ActivityAnalyzer.totalDuration(aiIntervals),
            sessionCount: summary.sessionCount,
            messageCount: summary.messageCount,
            totalTokens: summary.totalTokens,
            burstCount: intervals.count
        )
    }

    private static func makeDashboardSummary(
        store: SessionStore,
        projectLabels: ProjectLabelCatalog,
        now: Date
    ) -> StatsDashboardSummary {
        let allTime = store.summary(for: .allTime, now: now)
        let latestActivity = store.sessions
            .compactMap { $0.stats?.lastActivity ?? $0.stats?.firstActivity ?? $0.lastModified }
            .max()
        let providers = ProviderKind.allCases.compactMap { provider -> StatsProviderSummary? in
            let summary = store.summary(for: .allTime, provider: provider, now: now)
            guard summary.sessionCount > 0 || summary.totalTokens > 0 else { return nil }
            return StatsProviderSummary(
                id: provider.rawValue,
                name: provider.displayName,
                sessionCount: summary.sessionCount,
                totalTokens: summary.totalTokens,
                estimatedCost: summary.totalCost
            )
        }

        return StatsDashboardSummary(
            totalTokens: allTime.totalTokens,
            totalCost: allTime.totalCost,
            sessionCount: allTime.sessionCount,
            messageCount: allTime.messageCount,
            activeProjectCount: projectLabels.count,
            latestActivityAt: latestActivity,
            providerSummaries: providers
        )
    }

    private static func sessions(on day: Date, in sessions: [Session], calendar: Calendar) -> [Session] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return sessions.filter { session in
            let activity = session.stats?.lastActivity ?? session.stats?.firstActivity ?? session.lastModified
            return activity >= start && activity < end
        }
    }

    private static func statsUsage(_ usage: TokenUsage) -> StatsTokenUsage {
        StatsTokenUsage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheReadTokens: usage.cacheReadTokens,
            cacheCreation5mTokens: usage.cacheCreation5mTokens,
            cacheCreation1hTokens: usage.cacheCreation1hTokens
        )
    }

    private static func appVersion() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return switch (version, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            "\(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            version
        case let (_, build?) where !build.isEmpty:
            build
        default:
            "Unknown"
        }
    }

    private static func sanitizedLeaderboardName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private struct ProjectLabelCatalog {
    private let labels: [String: String]
    let count: Int

    init(sessions: [Session]) {
        let keys = sessions
            .map(Self.projectKey(for:))
            .uniquedPreservingOrder()
        labels = Dictionary(uniqueKeysWithValues: keys.enumerated().map { index, key in
            (key, "Project \(index + 1)")
        })
        count = keys.count
    }

    func label(for session: Session) -> String {
        labels[Self.projectKey(for: session)] ?? "Project"
    }

    private static func projectKey(for session: Session) -> String {
        if let cwd = session.cwd, !cwd.isEmpty {
            return cwd
        }
        return session.projectDirectoryName.isEmpty ? session.id : session.projectDirectoryName
    }
}

private extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
