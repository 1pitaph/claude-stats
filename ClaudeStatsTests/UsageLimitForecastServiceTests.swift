import Foundation
import Testing
@testable import ClaudeStats

@Suite("UsageLimitForecastService")
struct UsageLimitForecastServiceTests {
    @Test("Forecasts reach interval from 7d history and token curve")
    func forecastsReachInterval() throws {
        let now = try Self.date("2026-01-08T12:00:00.000Z")
        let resetAt = try Self.date("2026-01-15T12:00:00.000Z")
        let history = Self.history(usedPercents: [20, 40, 60, 80], resetAt: resetAt, lastCapturedAt: now)
        let report = Self.report(used: 80, resetAt: resetAt, capturedAt: now)
        let sessions = [Self.session(provider: .codex, from: try Self.date("2026-01-05T12:00:00.000Z"), to: now, tokensPerHour: 1_000)]

        let forecast = try #require(Self.service.forecasts(sessions: sessions, reports: [report], history: history, now: now).first)

        #expect(forecast.status == .forecast)
        #expect(forecast.reachInterval != nil)
        #expect(forecast.medianReachAt ?? .distantFuture < resetAt)
    }

    @Test("Collects when fewer than four usage snapshots are available")
    func collectsWithTooFewSnapshots() throws {
        let now = try Self.date("2026-01-08T12:00:00.000Z")
        let resetAt = try Self.date("2026-01-15T12:00:00.000Z")
        let history = Self.history(usedPercents: [10, 20, 30], resetAt: resetAt, lastCapturedAt: now)
        let report = Self.report(used: 30, resetAt: resetAt, capturedAt: now)
        let sessions = [Self.session(provider: .codex, from: try Self.date("2026-01-05T12:00:00.000Z"), to: now, tokensPerHour: 1_000)]

        let forecast = try #require(Self.service.forecasts(sessions: sessions, reports: [report], history: history, now: now).first)

        #expect(forecast.status == .collecting)
        #expect(forecast.reachInterval == nil)
    }

    @Test("Does not cross reset cycles")
    func doesNotCrossResetCycles() throws {
        let now = try Self.date("2026-01-08T12:00:00.000Z")
        let resetAt = try Self.date("2026-01-15T12:00:00.000Z")
        let oldReset = try Self.date("2026-01-10T12:00:00.000Z")
        let history = Self.history(usedPercents: [10, 20, 30, 40, 50], resetAt: oldReset, lastCapturedAt: now)
            + Self.history(usedPercents: [10, 20], resetAt: resetAt, lastCapturedAt: now)
        let report = Self.report(used: 30, resetAt: resetAt, capturedAt: now)
        let sessions = [Self.session(provider: .codex, from: try Self.date("2026-01-05T12:00:00.000Z"), to: now, tokensPerHour: 1_000)]

        let forecast = try #require(Self.service.forecasts(sessions: sessions, reports: [report], history: history, now: now).first)

        #expect(forecast.status == .collecting)
    }

    @Test("Reports will not reach before reset when horizon is too short")
    func willNotReachBeforeReset() throws {
        let now = try Self.date("2026-01-08T12:00:00.000Z")
        let resetAt = try Self.date("2026-01-09T00:00:00.000Z")
        let history = Self.history(usedPercents: [10, 20, 30, 40], resetAt: resetAt, lastCapturedAt: now)
        let report = Self.report(used: 40, resetAt: resetAt, capturedAt: now)
        let sessions = [Self.session(provider: .codex, from: try Self.date("2026-01-05T12:00:00.000Z"), to: now, tokensPerHour: 1_000)]

        let forecast = try #require(Self.service.forecasts(sessions: sessions, reports: [report], history: history, now: now).first)

        #expect(forecast.status == .willNotReachBeforeReset)
        #expect(forecast.reachInterval == nil)
    }

    @Test("Reports limit reached at 100 percent")
    func limitReached() throws {
        let now = try Self.date("2026-01-08T12:00:00.000Z")
        let resetAt = try Self.date("2026-01-15T12:00:00.000Z")
        let report = Self.report(used: 100, resetAt: resetAt, capturedAt: now)

        let forecast = try #require(Self.service.forecasts(sessions: [], reports: [report], history: [], now: now).first)

        #expect(forecast.status == .limitReached)
    }

    private static let service = UsageLimitForecastService()

    private static func history(usedPercents: [Double], resetAt: Date, lastCapturedAt: Date) -> [UsageLimitHistoryEntry] {
        usedPercents.enumerated().map { offset, used in
            let capturedAt = lastCapturedAt.addingTimeInterval(TimeInterval(offset - usedPercents.count + 1) * 86_400)
            return UsageLimitHistoryEntry(
                provider: .codex,
                window: UsageLimitWindow(
                    id: "secondary",
                    label: "7d",
                    usedPercent: used,
                    resetAt: resetAt,
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

    private static func report(used: Double, resetAt: Date, capturedAt: Date) -> UsageLimitReport {
        .fresh(
            provider: .codex,
            snapshot: UsageLimitSnapshot(
                provider: .codex,
                windows: [
                    UsageLimitWindow(
                        id: "secondary",
                        label: "7d",
                        usedPercent: used,
                        resetAt: resetAt,
                        windowMinutes: UsageLimitWindowCatalog.sevenDayWindowMinutes
                    ),
                ],
                capturedAt: capturedAt,
                sourceLabel: "Test",
                sourcePath: nil,
                planType: nil,
                limitID: nil
            )
        )
    }

    private static func session(provider: ProviderKind, from start: Date, to end: Date, tokensPerHour: Int) -> Session {
        var buckets: [ModelBucket] = []
        var current = start
        while current <= end {
            buckets.append(ModelBucket(
                model: "model",
                start: current,
                usage: TokenUsage(inputTokens: tokensPerHour, outputTokens: 0)
            ))
            current = current.addingTimeInterval(3_600)
        }
        let total = buckets.reduce(TokenUsage.zero) { $0 + $1.usage }
        let stats = SessionStats(
            title: "Test",
            messageCount: buckets.count,
            firstActivity: start,
            lastActivity: end,
            models: [ModelUsage(model: "model", messageCount: buckets.count, usage: total, estimatedCost: 0)],
            timeline: buckets,
            activityIntervals: [DateInterval(start: start, end: end)],
            billableMessages: []
        )
        return Session(
            id: "session-\(provider.rawValue)",
            externalID: "external",
            provider: provider,
            projectDirectoryName: "project",
            filePath: "/tmp/session.jsonl",
            cwd: "/tmp/project",
            lastModified: end,
            fileSize: 1,
            stats: stats
        )
    }

    private static func date(_ string: String) throws -> Date {
        try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string)
    }
}
