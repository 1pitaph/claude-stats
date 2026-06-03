import Foundation
import Testing
@testable import ClaudeStats

@Suite("Codex usage-limit loader")
struct CodexUsageLimitLoaderTests {
    @Test("Newest null rate_limits falls back to latest non-null snapshot")
    func nullSnapshotFallback() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let day = root.appendingPathComponent("sessions/2026/01/10", isDirectory: true)

        let older = day.appendingPathComponent("rollout-2026-01-10T09-00-00-a.jsonl")
        try TempDir.write(Self.rateLimitLine(timestamp: "2026-01-10T09:00:00.000Z", used: 25, reset: 1_768_100_000), to: older)
        try Self.setModified(older, Date(timeIntervalSince1970: 1_000))

        let newer = day.appendingPathComponent("rollout-2026-01-10T09-10-00-b.jsonl")
        try TempDir.write(Self.nullRateLimitLine(timestamp: "2026-01-10T09:10:00.000Z"), to: newer)
        try Self.setModified(newer, Date(timeIntervalSince1970: 2_000))

        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-10T09:05:00.000Z")
        let report = CodexUsageLimitLoader(paths: CodexPaths(homeDirectory: root)).report(now: now)

        #expect(report.status == .fresh)
        let window = try #require(report.snapshot?.windows.first)
        #expect(window.label == "5h")
        #expect(window.usedPercent == 25)
        #expect(window.remainingPercent == 75)
    }

    @Test("Expired reset or old snapshot returns cached usage")
    func staleSnapshotsReturnCachedUsage() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let day = root.appendingPathComponent("sessions/2026/01/10", isDirectory: true)
        let url = day.appendingPathComponent("rollout-2026-01-10T09-00-00-a.jsonl")
        try TempDir.write(Self.rateLimitLine(timestamp: "2026-01-10T09:00:00.000Z", used: 25, reset: 1_768_100_000), to: url)

        let staleNow = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-10T09:45:01.000Z")
        let stale = CodexUsageLimitLoader(paths: CodexPaths(homeDirectory: root)).report(now: staleNow)
        #expect(stale.status == .cached)
        #expect(stale.snapshot?.windows.first?.usedPercent == 25)

        let expiredNow = Date(timeIntervalSince1970: 1_768_100_001)
        let expired = CodexUsageLimitLoader(paths: CodexPaths(homeDirectory: root)).report(now: expiredNow)
        #expect(expired.status == .cached)
        #expect(expired.snapshot?.windows.first?.usedPercent == 25)
    }

    @Test("Parses string fields and clamps remaining percentage")
    func parsesStringFieldsAndClamps() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let day = root.appendingPathComponent("sessions/2026/01/10", isDirectory: true)
        let url = day.appendingPathComponent("rollout-2026-01-10T09-00-00-a.jsonl")
        try TempDir.write("""
        {"timestamp":"2026-01-10T09:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","plan_type":"pro","primary":{"used_percent":"101","window_minutes":"300","resets_at":"1768100000"},"secondary":{"used_percent":"-5","window_minutes":"10080","resets_at":"1768100000"}}}}
        """, to: url)

        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-10T09:05:00.000Z")
        let report = CodexUsageLimitLoader(paths: CodexPaths(homeDirectory: root)).report(now: now)

        #expect(report.status == .fresh)
        let windows = try #require(report.snapshot?.windows)
        #expect(windows.map(\.label) == ["5h", "7d"])
        #expect(windows[0].remainingPercent == 0)
        #expect(windows[1].remainingPercent == 100)
        #expect(report.snapshot?.planType == "pro")
    }

    @Test("Reads primary and secondary history from recent rollout logs")
    func readsPrimaryAndSecondaryHistory() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let day = root.appendingPathComponent("sessions/2026/01/10", isDirectory: true)
        let url = day.appendingPathComponent("rollout-2026-01-10T09-00-00-a.jsonl")
        try TempDir.write(
            [
                Self.rateLimitLine(timestamp: "2026-01-10T09:00:00.000Z", used: 25, reset: 1_768_700_000, secondaryUsed: 10),
                Self.nullRateLimitLine(timestamp: "2026-01-10T09:10:00.000Z"),
                Self.rateLimitLine(timestamp: "2026-01-10T10:00:00.000Z", used: 30, reset: 1_768_700_000, secondaryUsed: 12),
            ].joined(separator: "\n"),
            to: url
        )

        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-10T11:00:00.000Z")
        let history = CodexUsageLimitLoader(paths: CodexPaths(homeDirectory: root))
            .history(since: now.addingTimeInterval(-7 * 86_400), now: now)

        #expect(history.map(\.windowID) == ["primary", "secondary", "primary", "secondary"])
        #expect(history.map(\.usedPercent) == [25, 10, 30, 12])
    }

    @Test("History ignores expired usage windows")
    func historyIgnoresExpiredUsageWindows() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let day = root.appendingPathComponent("sessions/2026/01/10", isDirectory: true)
        let url = day.appendingPathComponent("rollout-2026-01-10T09-00-00-a.jsonl")
        try TempDir.write(
            Self.rateLimitLine(timestamp: "2026-01-10T09:00:00.000Z", used: 25, reset: 1, secondaryUsed: 10),
            to: url
        )

        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-10T11:00:00.000Z")
        let history = CodexUsageLimitLoader(paths: CodexPaths(homeDirectory: root))
            .history(since: now.addingTimeInterval(-7 * 86_400), now: now)

        #expect(history.isEmpty)
    }

    private static func rateLimitLine(timestamp: String, used: Int, reset: Int) -> String {
        rateLimitLine(timestamp: timestamp, used: used, reset: reset, secondaryUsed: 1)
    }

    private static func rateLimitLine(timestamp: String, used: Int, reset: Int, secondaryUsed: Int) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":\(used),"window_minutes":300,"resets_at":\(reset)},"secondary":{"used_percent":\(secondaryUsed),"window_minutes":10080,"resets_at":\(reset)}}}}
        """
    }

    private static func nullRateLimitLine(timestamp: String) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","rate_limits":null}}
        """
    }

    private static func setModified(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
