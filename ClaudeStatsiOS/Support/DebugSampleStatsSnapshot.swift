#if CLAUDE_STATS_DEV_TOOLS

import ClaudeStatsCore
import Foundation

enum DebugSampleStatsSnapshot {
    static func make(now: Date = Date()) -> StatsSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let dailyReports = makeDailyReports(today: today, calendar: calendar)
        let activityDays = makeActivityDays(from: dailyReports)
        let todayTokens = dailyReports.last?.totalTokens ?? 0
        let last7Tokens = dailyReports.suffix(7).reduce(0) { $0 + $1.totalTokens }
        let last30Tokens = dailyReports.reduce(0) { $0 + $1.totalTokens }
        let allTimeTokens = last30Tokens + 418_900
        let sessionCount = dailyReports.reduce(0) { $0 + $1.sessionCount }
        let messageCount = dailyReports.reduce(0) { $0 + $1.messageCount }
        let gitSummary = StatsGitActivitySummary(
            totalRepositories: 4,
            totalCommits: 38,
            totalInsertions: 12_840,
            totalDeletions: 4_275,
            totalFilesChanged: 126,
            rows: [
                StatsGitRepositoryRow(id: "claude-stats", label: "claude-stats", commitCount: 18, churn: 6_920),
                StatsGitRepositoryRow(id: "atoll", label: "Atoll", commitCount: 8, churn: 2_310),
                StatsGitRepositoryRow(id: "rockxy", label: "Rockxy", commitCount: 7, churn: 1_975),
                StatsGitRepositoryRow(id: "docs", label: "docs", commitCount: 5, churn: 1_635),
            ]
        )

        return StatsSnapshot(
            generatedAt: now,
            appVersion: "Dev Sample 1.8.9",
            usageBuckets: [
                usageBucket(id: "all|today|summary", period: .today, start: today, totalTokens: todayTokens, sessionCount: 7, messageCount: 46, estimatedCost: 3.24),
                usageBucket(id: "all|last7Days|summary", period: .last7Days, start: day(-6, from: today, calendar: calendar), totalTokens: last7Tokens, sessionCount: 34, messageCount: 219, estimatedCost: 17.82),
                usageBucket(id: "all|last30Days|summary", period: .last30Days, start: day(-29, from: today, calendar: calendar), totalTokens: last30Tokens, sessionCount: sessionCount, messageCount: messageCount, estimatedCost: 29.47),
                usageBucket(id: "all|allTime|summary", period: .allTime, start: day(-120, from: today, calendar: calendar), totalTokens: allTimeTokens, sessionCount: 384, messageCount: 2_418, estimatedCost: 118.64),
            ],
            modelBreakdowns: [
                modelBreakdown(id: "claude-sonnet-45", model: "Claude Sonnet 4.5", messages: 318, totalTokens: 224_800, cost: 18.42),
                modelBreakdown(id: "claude-opus-41", model: "Claude Opus 4.1", messages: 92, totalTokens: 82_100, cost: 21.86),
                modelBreakdown(id: "codex-gpt-5", model: "GPT-5 Codex", messages: 74, totalTokens: 61_400, cost: 12.28),
                modelBreakdown(id: "haiku-fast", model: "Claude Haiku", messages: 143, totalTokens: 43_600, cost: 2.95),
            ],
            usageLimitSnapshots: [
                StatsUsageLimitSnapshot(
                    id: "claude-limits",
                    providerID: "claude",
                    providerName: "Claude",
                    status: "Tracking",
                    capturedAt: now,
                    sourceLabel: "Debug sample",
                    windows: [
                        StatsUsageLimitWindow(id: "opus-5h", label: "Opus 5h", usedPercent: 63, resetAt: now.addingTimeInterval(7_200), windowMinutes: 300),
                        StatsUsageLimitWindow(id: "sonnet-week", label: "Sonnet weekly", usedPercent: 42, resetAt: now.addingTimeInterval(172_800), windowMinutes: 10_080),
                    ]
                ),
            ],
            dailyReports: dailyReports,
            ganttTimeline: makeTimeline(now: now),
            gitActivitySummary: gitSummary,
            leaderboardSummary: makeLeaderboard(now: now),
            activitySummary: StatsActivitySummary(
                sourceLabel: "Debug sample",
                hasFocusData: true,
                totalAISeconds: activityDays.reduce(0) { $0 + $1.aiSeconds },
                totalCodingSurfaceSeconds: activityDays.reduce(0) { $0 + $1.codingSurfaceSeconds },
                totalOverlapSeconds: activityDays.reduce(0) { $0 + $1.overlapSeconds },
                totalCLIHostSeconds: activityDays.reduce(0) { $0 + $1.cliHostSeconds },
                totalCLIAIOverlapSeconds: activityDays.reduce(0) { $0 + $1.cliAIOverlapSeconds },
                activeDayCount: activityDays.count,
                days: activityDays
            ),
            dashboardSummary: StatsDashboardSummary(
                totalTokens: last30Tokens,
                totalCost: 29.47,
                sessionCount: sessionCount,
                messageCount: messageCount,
                activeProjectCount: 6,
                latestActivityAt: now,
                providerSummaries: [
                    StatsProviderSummary(id: "claude", name: "Claude", sessionCount: 46, totalTokens: 291_700, estimatedCost: 25.58),
                    StatsProviderSummary(id: "codex", name: "Codex", sessionCount: 17, totalTokens: 61_400, estimatedCost: 3.89),
                    StatsProviderSummary(id: "local", name: "Local AI", sessionCount: 9, totalTokens: 58_800, estimatedCost: 0),
                ]
            ),
            statusSummary: makeStatusSummary(now: now, calendar: calendar)
        )
    }

    private static func makeDailyReports(today: Date, calendar: Calendar) -> [StatsDailyReport] {
        let tokenTotals = [18_400, 24_900, 31_200, 27_800, 36_400, 22_100, 44_700, 39_900, 28_600, 47_300, 34_500, 51_800, 42_200, 62_300]
        return tokenTotals.enumerated().map { index, totalTokens in
            let date = day(index - tokenTotals.count + 1, from: today, calendar: calendar)
            return StatsDailyReport(
                id: "sample-day-\(index)",
                day: date,
                sessionCount: 3 + index % 5,
                messageCount: 18 + index * 3,
                totalTokens: totalTokens,
                estimatedCost: Double(totalTokens) / 14_000,
                projectCount: 2 + index % 4,
                commitCount: index % 3 == 0 ? 5 : 2 + index % 4
            )
        }
    }

    private static func makeActivityDays(from reports: [StatsDailyReport]) -> [StatsActivityDay] {
        reports.enumerated().map { index, report in
            let aiSeconds = TimeInterval(1_800 + index * 260)
            return StatsActivityDay(
                id: "sample-activity-\(index)",
                day: report.day,
                aiSeconds: aiSeconds,
                codingSurfaceSeconds: aiSeconds + TimeInterval(1_200 + index * 90),
                overlapSeconds: aiSeconds * 0.68,
                cliHostSeconds: aiSeconds * 0.44,
                cliAIOverlapSeconds: aiSeconds * 0.31,
                sessionCount: report.sessionCount,
                messageCount: report.messageCount,
                totalTokens: report.totalTokens,
                burstCount: 2 + index % 5
            )
        }
    }

    private static func makeTimeline(now: Date) -> StatsGanttTimeline {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
        let segments = [
            ("Sync debug", -18_000.0, -15_600.0, 18_400),
            ("iOS settings", -14_700.0, -12_900.0, 11_200),
            ("Charts polish", -11_800.0, -9_600.0, 26_700),
            ("CloudKit retry", -8_900.0, -7_200.0, 14_300),
            ("Release notes", -5_800.0, -4_600.0, 8_900),
            ("Tests", -3_900.0, -2_400.0, 21_500),
        ]
        return StatsGanttTimeline(
            periodStart: dayStart,
            periodEnd: dayEnd,
            segments: segments.enumerated().map { index, value in
                StatsGanttSegment(
                    id: "sample-segment-\(index)",
                    label: value.0,
                    providerID: "claude",
                    start: now.addingTimeInterval(value.1),
                    end: now.addingTimeInterval(value.2),
                    tokenCount: value.3
                )
            }
        )
    }

    private static func makeLeaderboard(now: Date) -> StatsLeaderboardSummary {
        StatsLeaderboardSummary(
            isEnabled: true,
            statusText: "Synced",
            accountText: "Debug sample account",
            realtimeStatusText: "Live sample rows",
            lastLoadedPeriodKey: "last7Days",
            localScores: [
                StatsLeaderboardLocalScore(
                    id: "sample-local-tokens",
                    metricID: "tokensWithCache",
                    metricName: "Tokens incl. cache",
                    periodID: "week",
                    periodName: "Weekly",
                    periodKey: "last7Days",
                    score: 324_700,
                    updatedAt: now
                ),
            ],
            visibleRows: [
                leaderboardRow(rank: 1, name: "Avery", score: 389_200, now: now),
                leaderboardRow(rank: 2, name: "You", score: 324_700, isCurrentUser: true, now: now),
                leaderboardRow(rank: 3, name: "Mina", score: 287_400, now: now),
                leaderboardRow(rank: 4, name: "Kai", score: 211_900, now: now),
            ],
            favoriteModels: [
                StatsLeaderboardFavoriteModel(id: "favorite-sonnet", rank: 1, model: "Claude Sonnet 4.5", tokens: 224_800),
                StatsLeaderboardFavoriteModel(id: "favorite-opus", rank: 2, model: "Claude Opus 4.1", tokens: 82_100),
                StatsLeaderboardFavoriteModel(id: "favorite-codex", rank: 3, model: "GPT-5 Codex", tokens: 61_400),
            ]
        )
    }

    private static func makeStatusSummary(now: Date, calendar: Calendar) -> StatsStatusSummary {
        let fetchedAt = now.addingTimeInterval(-60)
        return StatsStatusSummary(
            providers: [
                StatsStatusProviderSnapshot(
                    providerID: .openAI,
                    providerName: "OpenAI",
                    statusPageURL: URL(string: "https://status.openai.com/"),
                    pageName: "OpenAI Status",
                    pageUpdatedAt: fetchedAt,
                    rollup: StatsStatusRollup(severity: .operational, description: "All Systems Operational"),
                    items: [
                        StatsStatusItem(id: SampleStatusIDs.chatGPT, name: "ChatGPT", status: .operational, updatedAt: fetchedAt, position: 1),
                        StatsStatusItem(id: SampleStatusIDs.codex, name: "Codex", status: .operational, updatedAt: fetchedAt, position: 2),
                    ],
                    defaultVisibleItemIDs: [SampleStatusIDs.chatGPT, SampleStatusIDs.codex],
                    uptimeHistories: [
                        makeUptimeHistory(
                            itemID: SampleStatusIDs.chatGPT,
                            itemName: "ChatGPT",
                            sourceUptimePercent: 99.83,
                            now: now,
                            calendar: calendar,
                            degradedOffsets: [4, 11, 23, 49, 67, 83],
                            partialOffsets: [18, 71],
                            majorOffsets: [],
                            fullOffsets: [80]
                        ),
                        makeUptimeHistory(
                            itemID: SampleStatusIDs.codex,
                            itemName: "Codex",
                            sourceUptimePercent: 99.96,
                            now: now,
                            calendar: calendar,
                            degradedOffsets: [6, 14, 52, 76, 85],
                            partialOffsets: [61],
                            majorOffsets: [],
                            fullOffsets: []
                        ),
                    ],
                    fetchedAt: fetchedAt
                ),
                StatsStatusProviderSnapshot(
                    providerID: .claude,
                    providerName: "Claude",
                    statusPageURL: URL(string: "https://status.claude.com/"),
                    pageName: "Claude Status",
                    pageUpdatedAt: fetchedAt,
                    rollup: StatsStatusRollup(severity: .operational, description: "All Systems Operational"),
                    items: [
                        StatsStatusItem(id: SampleStatusIDs.claudeAI, name: "claude.ai", status: .operational, updatedAt: fetchedAt, position: 1),
                        StatsStatusItem(id: SampleStatusIDs.claudeCode, name: "Claude Code", status: .operational, updatedAt: fetchedAt, position: 4),
                    ],
                    defaultVisibleItemIDs: [SampleStatusIDs.claudeAI, SampleStatusIDs.claudeCode],
                    uptimeHistories: [
                        makeUptimeHistory(
                            itemID: SampleStatusIDs.claudeAI,
                            itemName: "claude.ai",
                            sourceUptimePercent: 99.91,
                            now: now,
                            calendar: calendar,
                            degradedOffsets: [],
                            partialOffsets: [19, 64],
                            majorOffsets: [],
                            fullOffsets: []
                        ),
                        makeUptimeHistory(
                            itemID: SampleStatusIDs.claudeCode,
                            itemName: "Claude Code",
                            sourceUptimePercent: 99.97,
                            now: now,
                            calendar: calendar,
                            degradedOffsets: [],
                            partialOffsets: [44],
                            majorOffsets: [],
                            fullOffsets: []
                        ),
                    ],
                    fetchedAt: fetchedAt
                ),
            ]
        )
    }

    private static func makeUptimeHistory(
        itemID: String,
        itemName: String,
        sourceUptimePercent: Double,
        now: Date,
        calendar: Calendar,
        degradedOffsets: Set<Int>,
        partialOffsets: Set<Int>,
        majorOffsets: Set<Int>,
        fullOffsets: Set<Int>
    ) -> StatsStatusUptimeHistory {
        let today = calendar.startOfDay(for: now)
        let days = (0..<StatsStatusUptimeWindow.dayCount).map { index in
            StatsStatusUptimeDay(
                date: day(index - StatsStatusUptimeWindow.dayCount + 1, from: today, calendar: calendar),
                degradedPerformanceSeconds: degradedOffsets.contains(index) ? 3_600 : 0,
                partialOutageSeconds: partialOffsets.contains(index) ? 3_600 : 0,
                majorOutageSeconds: majorOffsets.contains(index) ? 7_200 : 0,
                fullOutageSeconds: fullOffsets.contains(index) ? 7_200 : 0,
                relatedEvents: []
            )
        }
        return StatsStatusUptimeHistory(
            itemID: itemID,
            itemName: itemName,
            startDate: days.first?.date,
            days: days,
            sourceUptimePercent: sourceUptimePercent
        )
    }

    private static func usageBucket(
        id: String,
        period: StatsPeriodIdentifier,
        start: Date,
        totalTokens: Int,
        sessionCount: Int,
        messageCount: Int,
        estimatedCost: Double
    ) -> StatsUsageBucket {
        StatsUsageBucket(
            id: id,
            period: period,
            granularity: .period,
            start: start,
            sessionCount: sessionCount,
            messageCount: messageCount,
            usage: tokenUsage(totalTokens: totalTokens),
            estimatedCost: estimatedCost
        )
    }

    private static func modelBreakdown(id: String, model: String, messages: Int, totalTokens: Int, cost: Double) -> StatsModelBreakdown {
        StatsModelBreakdown(
            id: id,
            period: .last30Days,
            model: model,
            messageCount: messages,
            usage: tokenUsage(totalTokens: totalTokens),
            estimatedCost: cost
        )
    }

    private static func leaderboardRow(rank: Int, name: String, score: Int64, isCurrentUser: Bool = false, now: Date) -> StatsLeaderboardRow {
        StatsLeaderboardRow(
            id: "sample-rank-\(rank)",
            rank: rank,
            displayName: name,
            metricID: "tokensWithCache",
            metricName: "Tokens incl. cache",
            periodID: "week",
            periodName: "Weekly",
            periodKey: "last7Days",
            score: score,
            isCurrentUser: isCurrentUser,
            updatedAt: now
        )
    }

    private static func tokenUsage(totalTokens: Int) -> StatsTokenUsage {
        let input = totalTokens * 36 / 100
        let output = totalTokens * 24 / 100
        let cacheRead = totalTokens * 28 / 100
        let cache5m = totalTokens * 7 / 100
        return StatsTokenUsage(
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreation5mTokens: cache5m,
            cacheCreation1hTokens: max(0, totalTokens - input - output - cacheRead - cache5m)
        )
    }

    private static func day(_ offset: Int, from day: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: offset, to: day) ?? day
    }

    private enum SampleStatusIDs {
        static let chatGPT = "01K5H8S53SY1KMS4GQMNMZXTR1"
        static let codex = "01KMKF9EBTCD8BN9PG8DJZXRSQ"
        static let claudeAI = "rwppv331jlwc"
        static let claudeCode = "yyzkbfz2thpt"
    }
}

#endif
