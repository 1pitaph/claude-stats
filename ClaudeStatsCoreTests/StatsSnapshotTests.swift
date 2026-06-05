import ClaudeStatsCore
import ClaudeStatsSync
import Foundation
import XCTest

final class StatsSnapshotTests: XCTestCase {
    func testStatsSnapshotRoundTrip() throws {
        let snapshot = StatsSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "1.0 (1)",
            usageBuckets: [
                StatsUsageBucket(
                    id: "all|today|summary",
                    period: .today,
                    granularity: .period,
                    start: Date(timeIntervalSince1970: 1_700_000_000),
                    sessionCount: 2,
                    messageCount: 4,
                    usage: StatsTokenUsage(inputTokens: 10, outputTokens: 20),
                    estimatedCost: 0.12
                ),
            ],
            modelBreakdowns: [
                StatsModelBreakdown(
                    id: "all|today|gpt",
                    period: .today,
                    model: "gpt-test",
                    messageCount: 4,
                    usage: StatsTokenUsage(inputTokens: 10, outputTokens: 20),
                    estimatedCost: 0.12
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
                        score: 30,
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
                        score: 30,
                        isCurrentUser: true,
                        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
                    ),
                ],
                favoriteModels: [
                    StatsLeaderboardFavoriteModel(id: "model-1", rank: 1, model: "gpt-test", tokens: 30),
                ]
            ),
            activitySummary: StatsActivitySummary(
                sourceLabel: "Fixture",
                totalAISeconds: 300,
                activeDayCount: 1,
                days: [
                    StatsActivityDay(
                        id: "1700000000",
                        day: Date(timeIntervalSince1970: 1_700_000_000),
                        aiSeconds: 300,
                        sessionCount: 2,
                        messageCount: 4,
                        totalTokens: 30,
                        burstCount: 2
                    ),
                ]
            ),
            dashboardSummary: StatsDashboardSummary(
                totalTokens: 30,
                totalCost: 0.12,
                sessionCount: 2,
                messageCount: 4,
                activeProjectCount: 1
            ),
            statusSummary: StatsStatusSummary(
                providers: [
                    StatsStatusProviderSnapshot(
                        providerID: .openAI,
                        providerName: "OpenAI",
                        statusPageURL: URL(string: "https://status.openai.com/"),
                        rollup: StatsStatusRollup(severity: .operational, description: "All Systems Operational"),
                        items: [
                            StatsStatusItem(
                                id: "chatgpt",
                                name: "ChatGPT",
                                status: .operational,
                                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                position: 1
                            ),
                        ],
                        defaultVisibleItemIDs: ["chatgpt"],
                        uptimeHistories: [
                            StatsStatusUptimeHistory(
                                itemID: "chatgpt",
                                itemName: "ChatGPT",
                                days: [
                                    StatsStatusUptimeDay(date: Date(timeIntervalSince1970: 1_700_000_000)),
                                ],
                                sourceUptimePercent: 99.99
                            ),
                        ],
                        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
                    ),
                ]
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StatsSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.schemaVersion, StatsSnapshotSchema.currentVersion)
    }

    func testV1SnapshotDecodesWithNewFieldDefaults() throws {
        let json = """
        {
          "schemaVersion": 1,
          "generatedAt": "2023-11-14T22:13:20Z",
          "appVersion": "1.0 (1)",
          "usageBuckets": [],
          "modelBreakdowns": [],
          "usageLimitSnapshots": [],
          "dailyReports": [],
          "ganttTimeline": { "segments": [] },
          "gitActivitySummary": {
            "totalRepositories": 0,
            "totalCommits": 0,
            "totalInsertions": 0,
            "totalDeletions": 0,
            "totalFilesChanged": 0,
            "rows": []
          },
          "dashboardSummary": {
            "totalTokens": 30,
            "totalCost": 0.12,
            "sessionCount": 2,
            "messageCount": 4,
            "activeProjectCount": 1,
            "providerSummaries": []
          }
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StatsSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.dashboardSummary.totalTokens, 30)
        XCTAssertFalse(decoded.leaderboardSummary.isEnabled)
        XCTAssertEqual(decoded.activitySummary.totalAISeconds, 0)
        XCTAssertTrue(decoded.statusSummary.providers.isEmpty)
    }

    func testCloudStatsSyncPublishAndLoadWithMockClient() async throws {
        let client = MockCloudStatsRemoteClient()
        let service = CloudStatsSyncService(client: client)
        let snapshot = StatsSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "1.0 (1)",
            dashboardSummary: StatsDashboardSummary(totalTokens: 42)
        )

        try await service.publish(snapshot: snapshot)
        let loaded = try await service.loadLatestSnapshot()
        let metadata = await client.currentMetadata()

        XCTAssertEqual(loaded?.dashboardSummary.totalTokens, 42)
        XCTAssertEqual(metadata?.schemaVersion, StatsSnapshotSchema.currentVersion)
    }

    func testCloudStatsSyncReturnsNilWhenNoSnapshotExists() async throws {
        let service = CloudStatsSyncService(client: MockCloudStatsRemoteClient())
        let loaded = try await service.loadLatestSnapshot()
        XCTAssertNil(loaded)
    }

    func testCloudStatsSyncRejectsFutureSchema() async throws {
        let client = MockCloudStatsRemoteClient()
        let service = CloudStatsSyncService(client: client)
        let future = StatsSnapshot(
            schemaVersion: StatsSnapshotSchema.currentVersion + 1,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "Future"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        await client.setData(try encoder.encode(future))

        do {
            _ = try await service.loadLatestSnapshot()
            XCTFail("Expected unsupported schema error")
        } catch let error as CloudStatsSyncError {
            XCTAssertEqual(error, .unsupportedSchema(StatsSnapshotSchema.currentVersion + 1))
        }
    }
}

private actor MockCloudStatsRemoteClient: CloudStatsRemoteClient {
    private var data: Data?
    private(set) var savedMetadata: CloudStatsRemoteMetadata?

    func setData(_ data: Data?) {
        self.data = data
    }

    func currentMetadata() -> CloudStatsRemoteMetadata? {
        savedMetadata
    }

    func saveLatestSnapshotData(_ data: Data, metadata: CloudStatsRemoteMetadata) async throws {
        self.data = data
        savedMetadata = metadata
    }

    func fetchLatestSnapshotData() async throws -> Data? {
        data
    }

    func accountStatus() async -> CloudStatsAccountStatus {
        .available
    }
}
