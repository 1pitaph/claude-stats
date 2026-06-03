import Foundation
import Testing
@testable import ClaudeStats

@Suite("UsageLimitHistoryStore")
struct UsageLimitHistoryStoreTests {
    @Test("Fresh reports append forecastable entries and dedupe")
    func freshReportsAppendForecastableEntries() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageLimitHistoryStore(url: root.appendingPathComponent("history.json"))
        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-10T09:00:00.000Z")
        let report = Self.codexReport(status: .fresh, used: 42, capturedAt: now)

        _ = try store.append(report: report, now: now)
        let entries = try store.append(report: report, now: now)

        #expect(entries.count == 2)
        #expect(entries.map(\.provider) == [.codex, .codex])
        #expect(entries.map(\.windowID) == ["primary", "secondary"])
        #expect(entries.map(\.usedPercent) == [80, 42])
    }

    @Test("Cached reports do not append history")
    func cachedReportsDoNotAppendHistory() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageLimitHistoryStore(url: root.appendingPathComponent("history.json"))
        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-10T09:00:00.000Z")

        let entries = try store.append(report: Self.codexReport(status: .cached, used: 42, capturedAt: now), now: now)

        #expect(entries.isEmpty)
        #expect(store.load().isEmpty)
    }

    @Test("History retention keeps recent entries")
    func retentionKeepsRecentEntries() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageLimitHistoryStore(url: root.appendingPathComponent("history.json"), retention: 14 * 86_400)
        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-20T09:00:00.000Z")
        let recent = Self.entry(capturedAt: now.addingTimeInterval(-13 * 86_400), used: 10)
        let old = Self.entry(capturedAt: now.addingTimeInterval(-15 * 86_400), used: 20)

        let entries = try store.append(entries: [old, recent], now: now)

        #expect(entries.count == 1)
        #expect(entries.first?.usedPercent == 10)
    }

    private static func codexReport(status: UsageLimitStatus, used: Double, capturedAt: Date) -> UsageLimitReport {
        let snapshot = UsageLimitSnapshot(
            provider: .codex,
            windows: [
                UsageLimitWindow(id: "primary", label: "5h", usedPercent: 80, resetAt: capturedAt.addingTimeInterval(3_600), windowMinutes: 300),
                UsageLimitWindow(id: "secondary", label: "7d", usedPercent: used, resetAt: capturedAt.addingTimeInterval(86_400), windowMinutes: UsageLimitWindowCatalog.sevenDayWindowMinutes),
            ],
            capturedAt: capturedAt,
            sourceLabel: "Test",
            sourcePath: nil,
            planType: nil,
            limitID: nil
        )
        switch status {
        case .fresh:
            return .fresh(provider: .codex, snapshot: snapshot)
        case .cached:
            return .cached(provider: .codex, snapshot: snapshot)
        case .setupRequired, .waitingForNextResponse, .unavailable, .unsupported:
            return UsageLimitReport(provider: .codex, status: status, snapshot: snapshot, message: nil)
        }
    }

    private static func entry(capturedAt: Date, used: Double) -> UsageLimitHistoryEntry {
        UsageLimitHistoryEntry(
            provider: .codex,
            window: UsageLimitWindow(
                id: "secondary",
                label: "7d",
                usedPercent: used,
                resetAt: capturedAt.addingTimeInterval(86_400),
                windowMinutes: UsageLimitWindowCatalog.sevenDayWindowMinutes
            ),
            capturedAt: capturedAt,
            sourceLabel: "Test",
            sourcePath: nil,
            planType: nil,
            limitID: nil
        )
    }
}
