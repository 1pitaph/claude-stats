import ClaudeStatsCore
import Foundation
import XCTest
@testable import ClaudeStats

@MainActor
final class StatsStatusSnapshotBuilderTests: XCTestCase {
    func testOpenAIConverterPublishesAllGroupsDefaultsIncidentsAndTrimmedUptime() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let viewModel = makeOpenAIStatusViewModel(now: now)

        await viewModel.refresh(force: true, now: now)
        let provider = try XCTUnwrap(StatsStatusSnapshotBuilder.makeOpenAIStatus(status: viewModel))

        XCTAssertEqual(provider.providerID, .openAI)
        XCTAssertTrue(provider.items.map(\.id).contains(OpenAIStatusGroupCatalog.apisID))
        XCTAssertEqual(provider.defaultVisibleItemIDs, Set([OpenAIStatusGroupCatalog.chatGPTID, OpenAIStatusGroupCatalog.codexID]))
        XCTAssertEqual(provider.incidents.first?.name, "Codex outage")

        let chatGPT = try XCTUnwrap(provider.uptimeHistories.first { $0.itemID == OpenAIStatusGroupCatalog.chatGPTID })
        XCTAssertEqual(chatGPT.days.count, StatsStatusUptimeWindow.dayCount)
        XCTAssertEqual(chatGPT.sourceUptimePercent, 99.83)
    }

    func testClaudeConverterPublishesDefaultComponentsAndTrimmedUptime() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let viewModel = makeClaudeStatusViewModel(now: now)

        await viewModel.refresh(force: true, now: now)
        let provider = try XCTUnwrap(StatsStatusSnapshotBuilder.makeClaudeStatus(status: viewModel))

        XCTAssertEqual(provider.providerID, .claude)
        XCTAssertEqual(provider.items.map(\.id), [
            ClaudeStatusComponentCatalog.claudeAIID,
            ClaudeStatusComponentCatalog.claudeCodeID,
        ])
        XCTAssertEqual(provider.defaultVisibleItemIDs, Set([
            ClaudeStatusComponentCatalog.claudeAIID,
            ClaudeStatusComponentCatalog.claudeCodeID,
        ]))

        let claudeAI = try XCTUnwrap(provider.uptimeHistories.first { $0.itemID == ClaudeStatusComponentCatalog.claudeAIID })
        XCTAssertEqual(claudeAI.days.count, StatsStatusUptimeWindow.dayCount)
        XCTAssertEqual(claudeAI.days.last?.partialOutageSeconds, 3_600)
    }

    private func makeOpenAIStatusViewModel(now: Date) -> OpenAIStatusViewModel {
        let preferences = Preferences(defaults: makeDefaults())
        let components = [
            OpenAIStatusComponent(
                id: OpenAIStatusGroupCatalog.chatGPTLoginID,
                name: "Login",
                status: .operational,
                updatedAt: now,
                position: 1
            ),
            OpenAIStatusComponent(
                id: OpenAIStatusGroupCatalog.codexWebID,
                name: "Codex Web",
                status: .operational,
                updatedAt: now,
                position: 2
            ),
        ]
        let snapshot = OpenAIStatusSnapshot(
            pageName: "OpenAI",
            pageUpdatedAt: now,
            rollup: OpenAIStatusRollup(severity: .operational, description: "All Systems Operational"),
            groups: OpenAIStatusGroupCatalog.groups(from: components),
            components: components,
            incidents: [
                OpenAIStatusIncident(
                    id: "incident-openai",
                    name: "Codex outage",
                    status: "investigating",
                    impact: .degradedPerformance,
                    shortlink: URL(string: "https://status.openai.com/incidents/codex"),
                    startedAt: now.addingTimeInterval(-3_600),
                    updatedAt: now
                ),
            ],
            scheduledMaintenances: [],
            fetchedAt: now
        )
        let uptimeSnapshot = OpenAIStatusUptimeSnapshot(
            histories: [
                OpenAIStatusGroupCatalog.chatGPTID: OpenAIStatusUptimeHistory(
                    groupID: OpenAIStatusGroupCatalog.chatGPTID,
                    groupName: "ChatGPT",
                    startDate: nil,
                    days: openAIDays(count: 100),
                    sourceUptimePercent: 99.83
                ),
                OpenAIStatusGroupCatalog.codexID: OpenAIStatusUptimeHistory(
                    groupID: OpenAIStatusGroupCatalog.codexID,
                    groupName: "Codex",
                    startDate: nil,
                    days: openAIDays(count: 100),
                    sourceUptimePercent: 99.96
                ),
            ],
            groupDefinitions: OpenAIStatusGroupCatalog.defaultGroupDefinitions,
            fetchedAt: now
        )
        return OpenAIStatusViewModel(
            preferences: preferences,
            client: StaticOpenAIStatusClient(snapshot: snapshot),
            cache: EmptyOpenAIStatusCache(),
            uptimeClient: StaticOpenAIStatusUptimeClient(snapshot: uptimeSnapshot),
            uptimeCache: EmptyOpenAIStatusUptimeCache(),
            notifications: NoopStatusNotifications()
        )
    }

    private func makeClaudeStatusViewModel(now: Date) -> ClaudeStatusViewModel {
        let preferences = Preferences(defaults: makeDefaults())
        let components = [
            ClaudeStatusComponent(
                id: ClaudeStatusComponentCatalog.claudeAIID,
                name: "claude.ai",
                status: .operational,
                updatedAt: now,
                position: 1
            ),
            ClaudeStatusComponent(
                id: ClaudeStatusComponentCatalog.claudeCodeID,
                name: "Claude Code",
                status: .operational,
                updatedAt: now,
                position: 4
            ),
        ]
        let snapshot = ClaudeStatusSnapshot(
            pageName: "Claude",
            pageUpdatedAt: now,
            rollup: ClaudeStatusRollup(severity: .operational, description: "All Systems Operational"),
            components: components,
            incidents: [],
            scheduledMaintenances: [],
            fetchedAt: now
        )
        let uptimeSnapshot = ClaudeStatusUptimeSnapshot(
            histories: [
                ClaudeStatusComponentCatalog.claudeAIID: ClaudeStatusUptimeHistory(
                    componentID: ClaudeStatusComponentCatalog.claudeAIID,
                    componentName: "claude.ai",
                    startDate: nil,
                    days: claudeDays(count: 100),
                    sourceUptimePercent: nil
                ),
            ],
            fetchedAt: now
        )
        return ClaudeStatusViewModel(
            preferences: preferences,
            client: StaticClaudeStatusClient(snapshot: snapshot),
            cache: EmptyClaudeStatusCache(),
            uptimeClient: StaticClaudeStatusUptimeClient(snapshot: uptimeSnapshot),
            uptimeCache: EmptyClaudeStatusUptimeCache(),
            notifications: NoopStatusNotifications()
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.claudestats.tests.status-builder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func openAIDays(count: Int) -> [OpenAIStatusUptimeDay] {
        (0..<count).map { index in
            OpenAIStatusUptimeDay(
                date: Date(timeIntervalSince1970: TimeInterval(index * 86_400)),
                degradedPerformanceSeconds: 0,
                partialOutageSeconds: 0,
                fullOutageSeconds: index == count - 1 ? 3_600 : 0,
                relatedEvents: []
            )
        }
    }

    private func claudeDays(count: Int) -> [ClaudeStatusUptimeDay] {
        (0..<count).map { index in
            ClaudeStatusUptimeDay(
                date: Date(timeIntervalSince1970: TimeInterval(index * 86_400)),
                partialOutageSeconds: index == count - 1 ? 3_600 : 0,
                majorOutageSeconds: 0,
                relatedEvents: [],
                barFillHex: nil
            )
        }
    }
}

private struct StaticOpenAIStatusClient: OpenAIStatusFetching {
    let snapshot: OpenAIStatusSnapshot

    func fetchSummary(now: Date) async throws -> OpenAIStatusSnapshot {
        snapshot
    }
}

private struct StaticOpenAIStatusUptimeClient: OpenAIStatusUptimeFetching {
    let snapshot: OpenAIStatusUptimeSnapshot

    func fetchUptimeHistories(now: Date) async throws -> OpenAIStatusUptimeSnapshot {
        snapshot
    }
}

private struct EmptyOpenAIStatusCache: OpenAIStatusCaching {
    func read(ttl: TimeInterval, now: Date) -> (snapshot: OpenAIStatusSnapshot, isStale: Bool)? {
        nil
    }

    func write(_ snapshot: OpenAIStatusSnapshot) throws {}
}

private struct EmptyOpenAIStatusUptimeCache: OpenAIStatusUptimeCaching {
    func read(ttl: TimeInterval, now: Date) -> (snapshot: OpenAIStatusUptimeSnapshot, isStale: Bool)? {
        nil
    }

    func write(_ snapshot: OpenAIStatusUptimeSnapshot) throws {}
}

private struct StaticClaudeStatusClient: ClaudeStatusFetching {
    let snapshot: ClaudeStatusSnapshot

    func fetchSummary(now: Date) async throws -> ClaudeStatusSnapshot {
        snapshot
    }
}

private struct StaticClaudeStatusUptimeClient: ClaudeStatusUptimeFetching {
    let snapshot: ClaudeStatusUptimeSnapshot

    func fetchUptimeHistories(now: Date) async throws -> ClaudeStatusUptimeSnapshot {
        snapshot
    }
}

private struct EmptyClaudeStatusCache: ClaudeStatusCaching {
    func read(ttl: TimeInterval, now: Date) -> (snapshot: ClaudeStatusSnapshot, isStale: Bool)? {
        nil
    }

    func write(_ snapshot: ClaudeStatusSnapshot) throws {}
}

private struct EmptyClaudeStatusUptimeCache: ClaudeStatusUptimeCaching {
    func read(ttl: TimeInterval, now: Date) -> (snapshot: ClaudeStatusUptimeSnapshot, isStale: Bool)? {
        nil
    }

    func write(_ snapshot: ClaudeStatusUptimeSnapshot) throws {}
}

private struct NoopStatusNotifications: ClaudeStatusNotificationServicing {
    func authorizationStatus() async -> ClaudeStatusNotificationAuthorizationStatus {
        .notDetermined
    }

    func requestAuthorization() async -> ClaudeStatusNotificationAuthorizationStatus {
        .notDetermined
    }

    func sendStatusAlert(title: String, body: String, identifier: String) async throws {}
}
