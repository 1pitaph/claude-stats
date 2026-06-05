import ClaudeStatsCore
import Foundation
import XCTest

final class StatsStatusSnapshotTests: XCTestCase {
    func testUptimePercentUsesSourceValueAndRecentDaysTrim() throws {
        var days: [StatsStatusUptimeDay] = []
        for index in 0..<100 {
            days.append(StatsStatusUptimeDay(
                date: Date(timeIntervalSince1970: TimeInterval(index * 86_400)),
                fullOutageSeconds: index == 99 ? 3_600 : 0
            ))
        }
        let history = StatsStatusUptimeHistory(
            itemID: "codex",
            itemName: "Codex",
            days: days,
            sourceUptimePercent: 99.96
        )

        XCTAssertEqual(history.recentDays().count, 90)
        XCTAssertEqual(try XCTUnwrap(history.uptimePercent()), 99.96)
    }

    func testUptimePercentComputesFromOutageSeconds() throws {
        var days: [StatsStatusUptimeDay] = []
        let dayCount = StatsStatusUptimeWindow.dayCount
        let secondsPerDay = StatsStatusUptimeWindow.secondsPerDay
        for index in 0..<dayCount {
            let timestamp = TimeInterval(index * secondsPerDay)
            let degradedSeconds = index == 0 ? 3_600 : 0
            let fullOutageSeconds = index == 1 ? 7_200 : 0
            days.append(
                StatsStatusUptimeDay(
                    date: Date(timeIntervalSince1970: timestamp),
                    degradedPerformanceSeconds: degradedSeconds,
                    fullOutageSeconds: fullOutageSeconds
                )
            )
        }
        let history = StatsStatusUptimeHistory(
            itemID: "codex",
            itemName: "Codex",
            days: days
        )

        let percent = try XCTUnwrap(history.uptimePercent())
        let totalSeconds = Double(dayCount * secondsPerDay)
        let downtimeSeconds = 10_800.0
        let expected = (1.0 - (downtimeSeconds / totalSeconds)) * 100.0
        let difference = abs(percent - expected)
        XCTAssertLessThan(difference, 0.0001)
    }

    @MainActor
    func testStatusDisplayPreferencesPersistSelectionAndVisibleItems() {
        let suiteName = "com.claudestats.core.status-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let provider = Self.openAIProvider()
        let store = StatsStatusDisplayPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.selectedProviderID, .openAI)
        XCTAssertEqual(store.visibleItemIDs(for: provider), Set(["chatgpt", "codex"]))

        store.selectedProviderID = .claude
        store.setItemVisibility(provider.items[1], in: provider, isVisible: false)

        let reloaded = StatsStatusDisplayPreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.selectedProviderID, .claude)
        XCTAssertEqual(reloaded.visibleItemIDs(for: provider), Set(["chatgpt"]))
    }

    @MainActor
    func testStatusDisplayPreferencesProtectLastVisibleItemAndFallbackToFirst() {
        let suiteName = "com.claudestats.core.status-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let provider = StatsStatusProviderSnapshot(
            providerID: .openAI,
            providerName: "OpenAI",
            items: [
                StatsStatusItem(id: "apis", name: "APIs", status: .operational, position: 1),
                StatsStatusItem(id: "codex", name: "Codex", status: .operational, position: 2),
            ],
            defaultVisibleItemIDs: Set(["missing-id"])
        )
        let store = StatsStatusDisplayPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.visibleItemIDs(for: provider), Set(["apis"]))
        store.setItemVisibility(provider.items[0], in: provider, isVisible: false)
        XCTAssertEqual(store.visibleItemIDs(for: provider), Set(["apis"]))
        store.setItemVisibility(provider.items[1], in: provider, isVisible: true)
        store.setItemVisibility(provider.items[0], in: provider, isVisible: false)
        XCTAssertEqual(store.visibleItemIDs(for: provider), Set(["codex"]))
    }

    private static func openAIProvider() -> StatsStatusProviderSnapshot {
        StatsStatusProviderSnapshot(
            providerID: .openAI,
            providerName: "OpenAI",
            items: [
                StatsStatusItem(id: "chatgpt", name: "ChatGPT", status: .operational, position: 1),
                StatsStatusItem(id: "codex", name: "Codex", status: .operational, position: 2),
            ],
            defaultVisibleItemIDs: Set(["chatgpt", "codex"])
        )
    }
}
