import Foundation

struct LeaderboardScoreBuilder: Sendable {
    func submissions(sessions: [Session],
                     nickname: String,
                     includeActivity: Bool,
                     now: Date = .now,
                     appVersion: String = Self.appVersion) -> [LeaderboardSubmission] {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNickname.isEmpty else { return [] }

        let windows = LeaderboardPeriodCalculator.windows(now: now)
        return windows.flatMap { window in
            submissions(
                sessions: sessions,
                nickname: trimmedNickname,
                includeActivity: includeActivity,
                window: window,
                now: now,
                appVersion: appVersion
            )
        }
    }

    func submissions(sessions: [Session],
                     nickname: String,
                     includeActivity: Bool,
                     window: LeaderboardPeriodWindow,
                     now: Date = .now,
                     appVersion: String = Self.appVersion) -> [LeaderboardSubmission] {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNickname.isEmpty else { return [] }

        var out: [LeaderboardSubmission] = []
        let usage = tokenUsage(in: sessions, window: window)
        append(.tokensWithCache, score: Int64(usage.total), to: &out,
               nickname: trimmedNickname, window: window, now: now, appVersion: appVersion)
        append(.tokensWithoutCacheRead, score: Int64(usage.total(includingCacheRead: false)), to: &out,
               nickname: trimmedNickname, window: window, now: now, appVersion: appVersion)

        if includeActivity {
            let minutes = Int64(activitySeconds(in: sessions, window: window) / 60)
            append(.activityMinutes, score: minutes, to: &out,
                   nickname: trimmedNickname, window: window, now: now, appVersion: appVersion)
        }
        return out
    }

    func historySubmissions(sessions: [Session],
                            includeActivity: Bool,
                            now: Date = .now,
                            appVersion: String = Self.appVersion) -> [LeaderboardHistorySubmission] {
        let windows = uploadHistoryWindows(sessions: sessions, now: now)
        let metrics: [LeaderboardMetric] = includeActivity
            ? LeaderboardMetric.allCases
            : [.tokensWithCache, .tokensWithoutCacheRead]

        var submissions: [LeaderboardHistorySubmission] = []
        for window in windows {
            for metric in metrics {
                let score = historyScore(metric: metric, sessions: sessions, window: window, includeActivity: includeActivity)
                guard score > 0 else { continue }
                submissions.append(LeaderboardHistorySubmission(
                    metric: metric,
                    bucketPeriod: window.period,
                    periodKey: window.periodKey,
                    score: score,
                    periodStartUTC: window.startUTC,
                    periodEndUTC: window.endUTC,
                    appVersion: appVersion,
                    updatedAt: now
                ))
            }
        }
        return submissions
    }

    func historyPoints(sessions: [Session],
                       metric: LeaderboardMetric,
                       period: LeaderboardPeriod,
                       includeActivity: Bool,
                       now: Date = .now) -> [LeaderboardScoreHistoryPoint] {
        guard metric != .activityMinutes || includeActivity else { return [] }
        let historyStart = period == .allTime ? historyStartDate(sessions: sessions) : nil
        let windows = LeaderboardPeriodCalculator.historyScope(for: period, now: now, historyStart: historyStart)
        return windows.map { window in
            LeaderboardScoreHistoryPoint(
                metric: metric,
                period: window.period,
                window: window,
                score: historyScore(metric: metric, sessions: sessions, window: window, includeActivity: includeActivity),
                updatedAt: nil
            )
        }
    }

    func historyStartMonthKey(sessions: [Session]) -> String? {
        historyStartDate(sessions: sessions).map {
            LeaderboardPeriodCalculator.window(for: .month, now: $0).periodKey
        }
    }

    func favoriteModels(sessions: [Session], limit: Int = 3) -> [LeaderboardFavoriteModel] {
        guard limit > 0 else { return [] }

        let totals = SessionUsageAggregator.favoriteModelTotals(sessions: sessions)

        return totals
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .prefix(limit)
            .enumerated()
            .map { index, entry in
                LeaderboardFavoriteModel(rank: index + 1, model: entry.key, tokens: entry.value)
            }
    }

    private func tokenUsage(in sessions: [Session], window: LeaderboardPeriodWindow) -> TokenUsage {
        SessionUsageAggregator.aggregate(sessions: sessions, in: interval(for: window)).totalUsage
    }

    private func activitySeconds(in sessions: [Session], window: LeaderboardPeriodWindow) -> Int {
        let boundsEnd = window.endUTC ?? Date.distantFuture
        let bounds = DateInterval(start: window.startUTC, end: boundsEnd)
        let intervals = sessions
            .flatMap { $0.stats?.activityIntervals ?? [] }
            .compactMap { ActivityAnalyzer.clip($0, to: bounds) }
        return Int(ActivityAnalyzer.totalDuration(ActivityAnalyzer.union(intervals)))
    }

    private func uploadHistoryWindows(sessions: [Session], now: Date) -> [LeaderboardPeriodWindow] {
        var windows = LeaderboardPeriodCalculator.historyScope(for: .day, now: now)
        windows += LeaderboardPeriodCalculator.historyScope(for: .week, now: now)
        if let historyStart = historyStartDate(sessions: sessions) {
            windows += LeaderboardPeriodCalculator.historyScope(for: .allTime, now: now, historyStart: historyStart)
        }
        return windows
    }

    private func historyScore(metric: LeaderboardMetric,
                              sessions: [Session],
                              window: LeaderboardPeriodWindow,
                              includeActivity: Bool) -> Int64 {
        switch metric {
        case .tokensWithCache:
            return Int64(historyTokenUsage(in: sessions, window: window).total)
        case .tokensWithoutCacheRead:
            return Int64(historyTokenUsage(in: sessions, window: window).total(includingCacheRead: false))
        case .activityMinutes:
            guard includeActivity else { return 0 }
            return Int64(activitySeconds(in: sessions, window: window) / 60)
        }
    }

    private func historyTokenUsage(in sessions: [Session], window: LeaderboardPeriodWindow) -> TokenUsage {
        SessionUsageAggregator.aggregate(sessions: sessions, in: interval(for: window)).totalUsage
    }

    private func historyStartDate(sessions: [Session]) -> Date? {
        sessions.compactMap { session -> Date? in
            guard let stats = session.stats else { return nil }
            let billableStart = stats.billableMessages.compactMap(\.timestamp).min()
            let timelineStart = stats.timeline.map(\.start).min()
            let activityStart = stats.activityIntervals.map(\.start).min()
            let fallbackStart = stats.totalUsage.total > 0 ? (stats.lastActivity ?? session.lastModified) : nil
            return [billableStart, timelineStart, activityStart, fallbackStart].compactMap { $0 }.min()
        }
        .min()
    }

    private func interval(for window: LeaderboardPeriodWindow) -> DateInterval {
        DateInterval(start: window.startUTC, end: window.endUTC ?? Date.distantFuture)
    }

    private func append(_ metric: LeaderboardMetric,
                        score: Int64,
                        to submissions: inout [LeaderboardSubmission],
                        nickname: String,
                        window: LeaderboardPeriodWindow,
                        now: Date,
                        appVersion: String) {
        guard score > 0 else { return }
        submissions.append(LeaderboardSubmission(
            metric: metric,
            period: window.period,
            periodKey: window.periodKey,
            score: score,
            nickname: nickname,
            periodStartUTC: window.startUTC,
            periodEndUTC: window.endUTC,
            appVersion: appVersion,
            updatedAt: now
        ))
    }

    private static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
}
