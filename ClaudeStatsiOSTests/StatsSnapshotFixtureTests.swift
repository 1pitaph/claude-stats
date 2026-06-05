import ClaudeStatsCore
import XCTest

final class StatsSnapshotFixtureTests: XCTestCase {
    func testFixtureSnapshotContainsRenderableDashboardData() {
        let snapshot = StatsSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "1.0 (1)",
            usageBuckets: [
                StatsUsageBucket(
                    id: "all|last30Days|summary",
                    period: .last30Days,
                    granularity: .period,
                    start: Date(timeIntervalSince1970: 1_699_000_000),
                    sessionCount: 3,
                    messageCount: 9,
                    usage: StatsTokenUsage(inputTokens: 100, outputTokens: 200),
                    estimatedCost: 1.23
                ),
            ],
            dailyReports: [
                StatsDailyReport(
                    id: "today",
                    day: Date(timeIntervalSince1970: 1_700_000_000),
                    sessionCount: 3,
                    messageCount: 9,
                    totalTokens: 300,
                    estimatedCost: 1.23,
                    projectCount: 2
                ),
            ],
            leaderboardSummary: StatsLeaderboardSummary(
                isEnabled: true,
                statusText: "Synced",
                accountText: "iCloud available",
                localScores: [
                    StatsLeaderboardLocalScore(
                        id: "tokensWithCache-day-2023-11-14",
                        metricID: "tokensWithCache",
                        metricName: "Tokens incl. cache",
                        periodID: "day",
                        periodName: "Daily",
                        periodKey: "2023-11-14",
                        score: 300,
                        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
                    ),
                ],
                visibleRows: [
                    StatsLeaderboardRow(
                        id: "rank-1",
                        rank: 1,
                        displayName: "You",
                        metricID: "tokensWithCache",
                        metricName: "Tokens incl. cache",
                        periodID: "day",
                        periodName: "Daily",
                        periodKey: "2023-11-14",
                        score: 300,
                        isCurrentUser: true,
                        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
                    ),
                ]
            ),
            activitySummary: StatsActivitySummary(
                sourceLabel: "Fixture",
                totalAISeconds: 600,
                activeDayCount: 1,
                days: [
                    StatsActivityDay(
                        id: "today",
                        day: Date(timeIntervalSince1970: 1_700_000_000),
                        aiSeconds: 600,
                        sessionCount: 3,
                        messageCount: 9,
                        totalTokens: 300,
                        burstCount: 3
                    ),
                ]
            ),
            dashboardSummary: StatsDashboardSummary(totalTokens: 300, totalCost: 1.23, sessionCount: 3),
            statusSummary: StatsStatusSummary(
                providers: [
                    StatsStatusProviderSnapshot(
                        providerID: .openAI,
                        providerName: "OpenAI",
                        rollup: StatsStatusRollup(severity: .operational, description: "All Systems Operational"),
                        items: [
                            StatsStatusItem(id: "chatgpt", name: "ChatGPT", status: .operational, position: 1),
                            StatsStatusItem(id: "codex", name: "Codex", status: .operational, position: 2),
                        ],
                        defaultVisibleItemIDs: ["chatgpt", "codex"]
                    ),
                ]
            )
        )

        XCTAssertEqual(snapshot.dashboardSummary.totalTokens, 300)
        XCTAssertEqual(snapshot.usageBuckets.first?.period, .last30Days)
        XCTAssertFalse(snapshot.dailyReports.isEmpty)
        XCTAssertFalse(snapshot.leaderboardSummary.localScores.isEmpty)
        XCTAssertEqual(snapshot.activitySummary.activeDayCount, 1)
        XCTAssertEqual(snapshot.statusSummary.provider(.openAI)?.items.count, 2)
    }
}
