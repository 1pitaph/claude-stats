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

    @Test("Forecasts 5h reach interval from short window history")
    func fiveHourForecastsReachInterval() throws {
        let now = try Self.date("2026-01-08T12:00:00.000Z")
        let resetAt = try Self.date("2026-01-08T14:00:00.000Z")
        let history = Self.fiveHourHistory(points: [
            (now.addingTimeInterval(-90 * 60), 20),
            (now.addingTimeInterval(-45 * 60), 40),
        ], resetAt: resetAt)
        let report = Self.fiveHourReport(status: .fresh, used: 60, resetAt: resetAt, capturedAt: now)
        let sessions = [Self.billableSession(provider: .codex, from: now.addingTimeInterval(-5 * 3_600), to: now, tokensPerFiveMinutes: 1_000)]

        let forecast = try #require(Self.service.forecasts(sessions: sessions, reports: [report], history: history, now: now).first { $0.horizon == .fiveHour })

        #expect(forecast.status == .forecast)
        #expect(forecast.reachInterval != nil)
        #expect(forecast.medianReachAt ?? .distantFuture < resetAt)
    }

    @Test("5h stale current snapshot is unavailable")
    func fiveHourStaleCurrentSnapshotUnavailable() throws {
        let now = try Self.date("2026-01-08T12:00:00.000Z")
        let resetAt = try Self.date("2026-01-08T14:00:00.000Z")
        let report = Self.fiveHourReport(status: .cached, used: 60, resetAt: resetAt, capturedAt: now)

        let forecast = try #require(Self.service.forecasts(sessions: [], reports: [report], history: [], now: now).first)

        #expect(forecast.status == .unavailable)
        #expect(forecast.reachInterval == nil)
    }

    @Test("5h collects with too few usage snapshots")
    func fiveHourCollectsWithTooFewSnapshots() throws {
        let now = try Self.date("2026-01-08T12:00:00.000Z")
        let resetAt = try Self.date("2026-01-08T14:00:00.000Z")
        let history = Self.fiveHourHistory(points: [
            (now.addingTimeInterval(-45 * 60), 40),
        ], resetAt: resetAt)
        let report = Self.fiveHourReport(status: .fresh, used: 60, resetAt: resetAt, capturedAt: now)
        let sessions = [Self.billableSession(provider: .codex, from: now.addingTimeInterval(-2 * 3_600), to: now, tokensPerFiveMinutes: 1_000)]

        let forecast = try #require(Self.service.forecasts(sessions: sessions, reports: [report], history: history, now: now).first)

        #expect(forecast.status == .collecting)
    }

    @Test("5h usage drop starts a new segment")
    func fiveHourDropStartsNewSegment() throws {
        let now = try Self.date("2026-01-08T12:00:00.000Z")
        let resetAt = try Self.date("2026-01-08T14:00:00.000Z")
        let history = Self.fiveHourHistory(points: [
            (now.addingTimeInterval(-90 * 60), 80),
            (now.addingTimeInterval(-45 * 60), 70),
        ], resetAt: resetAt)
        let report = Self.fiveHourReport(status: .fresh, used: 90, resetAt: resetAt, capturedAt: now)
        let sessions = [Self.billableSession(provider: .codex, from: now.addingTimeInterval(-2 * 3_600), to: now, tokensPerFiveMinutes: 1_000)]

        let forecast = try #require(Self.service.forecasts(sessions: sessions, reports: [report], history: history, now: now).first)

        #expect(forecast.status == .collecting)
    }

    @Test("5h collects when token movement is insufficient")
    func fiveHourCollectsWithInsufficientTokenMovement() throws {
        let now = try Self.date("2026-01-08T12:00:00.000Z")
        let resetAt = try Self.date("2026-01-08T14:00:00.000Z")
        let history = Self.fiveHourHistory(points: [
            (now.addingTimeInterval(-90 * 60), 20),
            (now.addingTimeInterval(-45 * 60), 40),
        ], resetAt: resetAt)
        let report = Self.fiveHourReport(status: .fresh, used: 60, resetAt: resetAt, capturedAt: now)

        let forecast = try #require(Self.service.forecasts(sessions: [], reports: [report], history: history, now: now).first)

        #expect(forecast.status == .collecting)
    }

    @Test("5h reports will not reach before reset when hit samples are sparse")
    func fiveHourWillNotReachBeforeReset() throws {
        let now = try Self.date("2026-01-08T12:00:00.000Z")
        let resetAt = try Self.date("2026-01-08T12:30:00.000Z")
        let history = Self.fiveHourHistory(points: [
            (now.addingTimeInterval(-90 * 60), 10),
            (now.addingTimeInterval(-45 * 60), 12),
        ], resetAt: resetAt)
        let report = Self.fiveHourReport(status: .fresh, used: 13, resetAt: resetAt, capturedAt: now)
        let sessions = [Self.billableSession(provider: .codex, from: now.addingTimeInterval(-2 * 3_600), to: now, tokensPerFiveMinutes: 1_000)]

        let forecast = try #require(Self.service.forecasts(sessions: sessions, reports: [report], history: history, now: now).first)

        #expect(forecast.status == .willNotReachBeforeReset)
        #expect(forecast.reachInterval == nil)
    }

    @Test("5h reports limit reached at 100 percent")
    func fiveHourLimitReached() throws {
        let now = try Self.date("2026-01-08T12:00:00.000Z")
        let resetAt = try Self.date("2026-01-08T14:00:00.000Z")
        let report = Self.fiveHourReport(status: .fresh, used: 100, resetAt: resetAt, capturedAt: now)

        let forecast = try #require(Self.service.forecasts(sessions: [], reports: [report], history: [], now: now).first)

        #expect(forecast.horizon == .fiveHour)
        #expect(forecast.status == .limitReached)
    }

    @Test("5h timeline fallback forecasts with low confidence")
    func fiveHourTimelineFallbackForecastsWithLowConfidence() throws {
        let now = try Self.date("2026-01-08T12:00:00.000Z")
        let resetAt = try Self.date("2026-01-08T14:00:00.000Z")
        let history = Self.fiveHourHistory(points: [
            (now.addingTimeInterval(-90 * 60), 20),
            (now.addingTimeInterval(-45 * 60), 40),
        ], resetAt: resetAt)
        let report = Self.fiveHourReport(status: .fresh, used: 60, resetAt: resetAt, capturedAt: now)
        let sessions = [Self.session(provider: .codex, from: now.addingTimeInterval(-5 * 3_600), to: now, tokensPerHour: 12_000)]

        let forecast = try #require(Self.service.forecasts(sessions: sessions, reports: [report], history: history, now: now).first)

        #expect(forecast.status == .forecast)
        #expect(forecast.confidence == .low)
    }

    private static let service = UsageLimitForecastService()

    private static func fiveHourHistory(points: [(Date, Double)], resetAt: Date) -> [UsageLimitHistoryEntry] {
        points.map { capturedAt, used in
            UsageLimitHistoryEntry(
                provider: .codex,
                window: UsageLimitWindow(
                    id: "primary",
                    label: "5h",
                    usedPercent: used,
                    resetAt: resetAt,
                    windowMinutes: UsageLimitWindowCatalog.fiveHourWindowMinutes
                ),
                capturedAt: capturedAt,
                sourceLabel: "Test",
                sourcePath: nil,
                planType: nil,
                limitID: nil
            )
        }
    }

    private static func fiveHourReport(
        status: UsageLimitStatus,
        used: Double,
        resetAt: Date,
        capturedAt: Date
    ) -> UsageLimitReport {
        let snapshot = UsageLimitSnapshot(
            provider: .codex,
            windows: [
                UsageLimitWindow(
                    id: "primary",
                    label: "5h",
                    usedPercent: used,
                    resetAt: resetAt,
                    windowMinutes: UsageLimitWindowCatalog.fiveHourWindowMinutes
                ),
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

    private static func billableSession(
        provider: ProviderKind,
        from start: Date,
        to end: Date,
        tokensPerFiveMinutes: Int
    ) -> Session {
        var messages: [BillableMessage] = []
        var current = start
        var index = 0
        while current <= end {
            messages.append(BillableMessage(
                hash: "message-\(index)",
                model: "model",
                usage: TokenUsage(inputTokens: tokensPerFiveMinutes, outputTokens: 0),
                cost: .zero,
                timestamp: current
            ))
            current = current.addingTimeInterval(5 * 60)
            index += 1
        }
        let total = messages.reduce(TokenUsage.zero) { $0 + $1.usage }
        let stats = SessionStats(
            title: "Test",
            messageCount: messages.count,
            firstActivity: start,
            lastActivity: end,
            models: [ModelUsage(model: "model", messageCount: messages.count, usage: total, estimatedCost: 0)],
            timeline: [],
            activityIntervals: [DateInterval(start: start, end: end)],
            billableMessages: messages
        )
        return Session(
            id: "billable-\(provider.rawValue)",
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
