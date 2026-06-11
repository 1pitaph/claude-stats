import Foundation
import Testing
@testable import ClaudeStats

@Suite("LeaderboardScoreBuilder")
struct LeaderboardScoreBuilderTests {
    private let builder = LeaderboardScoreBuilder()

    @Test("UTC period keys are stable")
    func periodKeys() {
        let now = dateUTC(2026, 5, 15, 13)

        #expect(LeaderboardPeriodCalculator.window(for: .day, now: now).periodKey == "2026-05-15")
        #expect(LeaderboardPeriodCalculator.window(for: .week, now: now).periodKey == "2026-W20")
        #expect(LeaderboardPeriodCalculator.window(for: .month, now: now).periodKey == "2026-05")
        #expect(LeaderboardPeriodCalculator.window(for: .allTime, now: now).periodKey == "all")
    }

    @Test("Token scores aggregate all providers and preserve cache semantics")
    func tokenScores() {
        let now = dateUTC(2026, 5, 15, 13)
        let window = LeaderboardPeriodCalculator.window(for: .day, now: now)
        let sessions = [
            session("claude", provider: .claude, at: dateUTC(2026, 5, 15, 10),
                    usage: TokenUsage(inputTokens: 100, outputTokens: 50, cacheReadTokens: 1_000,
                                      cacheCreation5mTokens: 25, cacheCreation1hTokens: 0)),
            session("codex", provider: .codex, at: dateUTC(2026, 5, 15, 11),
                    usage: TokenUsage(inputTokens: 200, outputTokens: 75, cacheReadTokens: 2_000,
                                      cacheCreation5mTokens: 0, cacheCreation1hTokens: 5)),
            session("outside", provider: .claude, at: dateUTC(2026, 5, 14, 23),
                    usage: TokenUsage(inputTokens: 9_999, outputTokens: 0, cacheReadTokens: 0,
                                      cacheCreation5mTokens: 0, cacheCreation1hTokens: 0)),
        ]

        let submissions = builder.submissions(
            sessions: sessions,
            nickname: "Ada",
            includeActivity: false,
            window: window,
            now: now,
            appVersion: "test"
        )

        #expect(submissions.first { $0.metric == .tokensWithCache }?.score == 3_455)
        #expect(submissions.first { $0.metric == .tokensWithoutCacheRead }?.score == 455)
        #expect(submissions.contains { $0.metric == .activityMinutes } == false)
    }

    @Test("Token scores dedupe Claude cowork turns by billable message hash")
    func tokenScoresDedupeClaudeBillableMessages() {
        let now = dateUTC(2026, 5, 15, 13)
        let window = LeaderboardPeriodCalculator.window(for: .day, now: now)
        let parentOnly = billable(
            hash: "msg_parent:req_parent",
            model: "sonnet",
            usage: TokenUsage(inputTokens: 500),
            at: dateUTC(2026, 5, 15, 9)
        )
        let sharedCoworkTurn = billable(
            hash: "msg_cowork:req_cowork",
            model: "sonnet",
            usage: TokenUsage(inputTokens: 1_000, cacheReadTokens: 9_000),
            at: dateUTC(2026, 5, 15, 10)
        )
        let sessions = [
            billableSession("parent", at: dateUTC(2026, 5, 15, 10), messages: [parentOnly, sharedCoworkTurn]),
            billableSession("cowork", at: dateUTC(2026, 5, 15, 10), messages: [sharedCoworkTurn]),
        ]

        let submissions = builder.submissions(
            sessions: sessions,
            nickname: "Ada",
            includeActivity: false,
            window: window,
            now: now,
            appVersion: "test"
        )
        let withCacheHistory = Dictionary(uniqueKeysWithValues: builder.historyPoints(
            sessions: sessions,
            metric: .tokensWithCache,
            period: .day,
            includeActivity: false,
            now: now
        ).map { ($0.periodKey, $0.score) })
        let withoutCacheHistory = Dictionary(uniqueKeysWithValues: builder.historyPoints(
            sessions: sessions,
            metric: .tokensWithoutCacheRead,
            period: .day,
            includeActivity: false,
            now: now
        ).map { ($0.periodKey, $0.score) })

        #expect(submissions.first { $0.metric == .tokensWithCache }?.score == 10_500)
        #expect(submissions.first { $0.metric == .tokensWithoutCacheRead }?.score == 1_500)
        #expect(withCacheHistory["2026-05-15"] == 10_500)
        #expect(withoutCacheHistory["2026-05-15"] == 1_500)
    }

    @Test("Current token scores use timeline buckets for window attribution")
    func tokenScoresUseTimelineBuckets() {
        let now = dateUTC(2026, 5, 16, 8)
        let window = LeaderboardPeriodCalculator.window(for: .day, now: now)
        let sessions = [
            session(
                "cross-day",
                provider: .claude,
                at: dateUTC(2026, 5, 16, 23),
                usage: TokenUsage(inputTokens: 9_999),
                timeline: [
                    ModelBucket(model: "model", start: dateUTC(2026, 5, 15, 23), usage: TokenUsage(inputTokens: 100)),
                    ModelBucket(model: "model", start: dateUTC(2026, 5, 16, 1), usage: TokenUsage(inputTokens: 250, cacheReadTokens: 1_000)),
                ]
            )
        ]

        let submissions = builder.submissions(
            sessions: sessions,
            nickname: "Ada",
            includeActivity: false,
            window: window,
            now: now,
            appVersion: "test"
        )

        #expect(submissions.first { $0.metric == .tokensWithCache }?.score == 1_250)
        #expect(submissions.first { $0.metric == .tokensWithoutCacheRead }?.score == 250)
    }

    @Test("Activity score is optional and measured in whole minutes")
    func activityScore() {
        let now = dateUTC(2026, 5, 15, 13)
        let window = LeaderboardPeriodCalculator.window(for: .day, now: now)
        let sessions = [
            session("activity", provider: .claude, at: dateUTC(2026, 5, 15, 10),
                    usage: TokenUsage(inputTokens: 1, outputTokens: 0, cacheReadTokens: 0,
                                      cacheCreation5mTokens: 0, cacheCreation1hTokens: 0),
                    activityIntervals: [
                        DateInterval(start: dateUTC(2026, 5, 15, 9), end: dateUTC(2026, 5, 15, 9, minute: 40)),
                        DateInterval(start: dateUTC(2026, 5, 15, 9, minute: 30), end: dateUTC(2026, 5, 15, 10)),
                    ])
        ]

        let withoutActivity = builder.submissions(
            sessions: sessions,
            nickname: "Ada",
            includeActivity: false,
            window: window,
            now: now,
            appVersion: "test"
        )
        let withActivity = builder.submissions(
            sessions: sessions,
            nickname: "Ada",
            includeActivity: true,
            window: window,
            now: now,
            appVersion: "test"
        )

        #expect(withoutActivity.contains { $0.metric == .activityMinutes } == false)
        #expect(withActivity.first { $0.metric == .activityMinutes }?.score == 60)
    }

    @Test("History points use timeline buckets instead of session last activity")
    func historyUsesTimelineBuckets() {
        let now = dateUTC(2026, 5, 16, 8)
        let sessions = [
            session(
                "cross-day",
                provider: .claude,
                at: dateUTC(2026, 5, 16, 23),
                usage: TokenUsage(inputTokens: 9_999),
                timeline: [
                    ModelBucket(model: "model", start: dateUTC(2026, 5, 15, 23), usage: TokenUsage(inputTokens: 100)),
                    ModelBucket(model: "model", start: dateUTC(2026, 5, 16, 1), usage: TokenUsage(inputTokens: 250, cacheReadTokens: 1_000)),
                ]
            )
        ]

        let withCache = builder.historyPoints(
            sessions: sessions,
            metric: .tokensWithCache,
            period: .day,
            includeActivity: false,
            now: now
        )
        let withoutCache = builder.historyPoints(
            sessions: sessions,
            metric: .tokensWithoutCacheRead,
            period: .day,
            includeActivity: false,
            now: now
        )

        let withCacheByKey = Dictionary(uniqueKeysWithValues: withCache.map { ($0.periodKey, $0.score) })
        let withoutCacheByKey = Dictionary(uniqueKeysWithValues: withoutCache.map { ($0.periodKey, $0.score) })
        #expect(withCacheByKey["2026-05-15"] == 100)
        #expect(withCacheByKey["2026-05-16"] == 1_250)
        #expect(withoutCacheByKey["2026-05-16"] == 250)
    }

    @Test("History scopes are fixed and zero-filled")
    func historyScopes() {
        let now = dateUTC(2026, 5, 16, 8)

        #expect(LeaderboardPeriodCalculator.historyScope(for: .day, now: now).map(\.periodKey) == [
            "2026-05-10", "2026-05-11", "2026-05-12", "2026-05-13", "2026-05-14", "2026-05-15", "2026-05-16",
        ])
        #expect(LeaderboardPeriodCalculator.historyScope(for: .week, now: now).map(\.periodKey) == [
            "2026-W17", "2026-W18", "2026-W19", "2026-W20",
        ])
        #expect(LeaderboardPeriodCalculator.historyScope(for: .month, now: now).map(\.periodKey) == [
            "2026-03", "2026-04", "2026-05",
        ])
        #expect(LeaderboardPeriodCalculator.historyScope(
            for: .allTime,
            now: now,
            historyStart: dateUTC(2026, 2, 7)
        ).map(\.periodKey) == [
            "2026-02", "2026-03", "2026-04", "2026-05",
        ])

        let points = builder.historyPoints(
            sessions: [],
            metric: .tokensWithCache,
            period: .day,
            includeActivity: false,
            now: now
        )
        #expect(points.count == 7)
        #expect(points.allSatisfy { $0.score == 0 })
    }

    @Test("History submissions include token and activity metrics")
    func historySubmissionsIncludeMetrics() {
        let now = dateUTC(2026, 5, 16, 8)
        let sessions = [
            session("history", provider: .claude, at: now,
                    usage: TokenUsage(inputTokens: 20),
                    timeline: [
                        ModelBucket(model: "model", start: dateUTC(2026, 5, 16, 1), usage: TokenUsage(inputTokens: 20)),
                    ],
                    activityIntervals: [
                        DateInterval(start: dateUTC(2026, 5, 16, 1), end: dateUTC(2026, 5, 16, 1, minute: 30)),
                    ]),
        ]

        let submissions = builder.historySubmissions(
            sessions: sessions,
            includeActivity: true,
            now: now,
            appVersion: "test"
        )

        #expect(submissions.contains {
            $0.metric == .tokensWithCache && $0.bucketPeriod == .day && $0.periodKey == "2026-05-16" && $0.score == 20
        })
        #expect(submissions.contains {
            $0.metric == .activityMinutes && $0.bucketPeriod == .day && $0.periodKey == "2026-05-16" && $0.score == 30
        })
        #expect(builder.historyStartMonthKey(sessions: sessions) == "2026-05")
    }

    @Test("Favorite models use timeline totals with legacy model fallback")
    func favoriteModelsUseTimelineTotals() {
        let now = dateUTC(2026, 5, 16, 8)
        let sessions = [
            session(
                "timeline",
                provider: .claude,
                at: now,
                usage: TokenUsage(inputTokens: 9_999),
                timeline: [
                    ModelBucket(model: "sonnet", start: dateUTC(2026, 5, 16, 1), usage: TokenUsage(inputTokens: 300)),
                    ModelBucket(model: "opus", start: dateUTC(2026, 5, 16, 2), usage: TokenUsage(inputTokens: 100)),
                ]
            ),
            session(
                "legacy",
                provider: .codex,
                at: now,
                usage: TokenUsage(inputTokens: 50),
                modelName: "gpt-5.5"
            ),
        ]

        let favoriteModels = builder.favoriteModels(sessions: sessions)

        #expect(favoriteModels.map(\.model) == ["sonnet", "opus", "gpt-5.5"])
        #expect(favoriteModels.map(\.tokens) == [300, 100, 50])
        #expect(favoriteModels.map(\.rank) == [1, 2, 3])
    }

    @Test("Favorite models ignore provider placeholder names")
    func favoriteModelsIgnoreProviderPlaceholderNames() {
        let now = dateUTC(2026, 5, 16, 8)
        let sessions = [
            session(
                "opencode-placeholder",
                provider: .opencode,
                at: now,
                usage: TokenUsage(inputTokens: 1_000),
                modelName: "opencode"
            ),
            session(
                "hermes-placeholder",
                provider: .hermes,
                at: now,
                usage: TokenUsage(inputTokens: 900),
                modelName: "Hermes"
            ),
            session(
                "real-model",
                provider: .opencode,
                at: now,
                usage: TokenUsage(inputTokens: 50),
                modelName: "gpt-5.3-codex"
            ),
        ]

        let favoriteModels = builder.favoriteModels(sessions: sessions)

        #expect(favoriteModels.map(\.model) == ["gpt-5.3-codex"])
        #expect(favoriteModels.map(\.tokens) == [50])
        #expect(favoriteModels.map(\.rank) == [1])
    }

    @Test("Favorite models dedupe Claude cowork turns by billable message hash")
    func favoriteModelsDedupeClaudeBillableMessages() {
        let now = dateUTC(2026, 5, 16, 8)
        let parentOnly = billable(
            hash: "msg_parent:req_parent",
            model: "opus",
            usage: TokenUsage(inputTokens: 700),
            at: dateUTC(2026, 5, 16, 7)
        )
        let sharedCoworkTurn = billable(
            hash: "msg_cowork:req_cowork",
            model: "sonnet",
            usage: TokenUsage(inputTokens: 1_000),
            at: dateUTC(2026, 5, 16, 8)
        )
        let sessions = [
            billableSession("parent", at: now, messages: [parentOnly, sharedCoworkTurn]),
            billableSession("cowork", at: now, messages: [sharedCoworkTurn]),
        ]

        let favoriteModels = builder.favoriteModels(sessions: sessions)

        #expect(favoriteModels.map(\.model) == ["sonnet", "opus"])
        #expect(favoriteModels.map(\.tokens) == [1_000, 700])
    }

    private func session(_ id: String,
                         provider: ProviderKind,
                         at date: Date,
                         usage: TokenUsage,
                         modelName: String = "model",
                         timeline: [ModelBucket] = [],
                         activityIntervals: [DateInterval] = []) -> Session {
        let stats = SessionStats(
            title: id,
            messageCount: 1,
            firstActivity: date,
            lastActivity: date,
            models: [ModelUsage(model: modelName, messageCount: 1, usage: usage, pricing: TestPricing.table)],
            timeline: timeline,
            activityIntervals: activityIntervals
        )
        return Session(
            id: id,
            externalID: id,
            provider: provider,
            projectDirectoryName: "-project",
            filePath: "/tmp/\(id).jsonl",
            cwd: nil,
            lastModified: date,
            fileSize: 1,
            stats: stats
        )
    }

    private func billable(hash: String, model: String, usage: TokenUsage, at date: Date) -> BillableMessage {
        BillableMessage(
            hash: hash,
            model: model,
            usage: usage,
            cost: CostEstimate(standardAPI: 0),
            timestamp: date
        )
    }

    private func billableSession(_ id: String, at date: Date, messages: [BillableMessage]) -> Session {
        var byModel: [String: (count: Int, usage: TokenUsage, cost: CostEstimate)] = [:]
        for message in messages {
            var acc = byModel[message.model] ?? (0, .zero, .zero)
            acc.count += 1
            acc.usage += message.usage
            acc.cost += message.cost
            byModel[message.model] = acc
        }
        let models = byModel
            .map { ModelUsage(model: $0.key, messageCount: $0.value.count, usage: $0.value.usage, costEstimate: $0.value.cost) }
            .sorted { $0.usage.total > $1.usage.total }
        let timestamps = messages.compactMap(\.timestamp)
        let stats = SessionStats(
            title: id,
            messageCount: messages.count,
            firstActivity: timestamps.min() ?? date,
            lastActivity: timestamps.max() ?? date,
            models: models,
            timeline: [],
            billableMessages: messages
        )
        return Session(
            id: id,
            externalID: id,
            provider: .claude,
            projectDirectoryName: "-project",
            filePath: "/tmp/\(id).jsonl",
            cwd: nil,
            lastModified: date,
            fileSize: 1,
            stats: stats
        )
    }

    private func dateUTC(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
