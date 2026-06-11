import Foundation
import Testing
@testable import ClaudeStats

@Suite("DashboardViewModel all-provider aggregation")
struct DashboardViewModelTests {
    private let calendar = Calendar.current

    @MainActor
    @Test("Stats and models aggregate all providers inside the selected period")
    func aggregatesAllProvidersInsideSelectedPeriod() async {
        let viewModel = DashboardViewModel(pricing: TestPricing.table)
        viewModel.period = .last7Days
        let sessions = [
            session("claude-recent", provider: .claude, daysAgo: 1, hour: 10, model: "shared-model", tokens: 100, messages: 3),
            session("codex-recent", provider: .codex, daysAgo: 2, hour: 11, model: "shared-model", tokens: 250, messages: 5),
            session("old", provider: .claude, daysAgo: 10, hour: 12, model: "old-model", tokens: 900, messages: 7),
        ]

        await viewModel.reload(sessions: sessions)

        #expect(viewModel.stats.sessions == 2)
        #expect(viewModel.stats.messages == 8)
        #expect(viewModel.stats.totalTokens == 350)
        #expect(viewModel.stats.activeDays == 2)
        #expect(viewModel.stats.favoriteModel == DashboardModelKey(provider: .codex, model: "shared-model"))
        #expect(viewModel.modelBreakdown.map(\.key) == [
            DashboardModelKey(provider: .codex, model: "shared-model"),
            DashboardModelKey(provider: .claude, model: "shared-model"),
        ])
        #expect(viewModel.modelBreakdown.map(\.usage.total) == [250, 100])
        #expect(viewModel.modelTrend.models == viewModel.modelBreakdown.map(\.id))
    }

    @MainActor
    @Test("Favorite model stat ignores provider placeholder names")
    func favoriteModelStatIgnoresProviderPlaceholderNames() async {
        let viewModel = DashboardViewModel(pricing: TestPricing.table)
        viewModel.period = .last7Days
        let sessions = [
            session("placeholder", provider: .opencode, daysAgo: 1, hour: 10, model: "opencode", tokens: 1_000, messages: 3),
            session("real", provider: .opencode, daysAgo: 1, hour: 11, model: "gpt-5.3-codex", tokens: 50, messages: 1),
        ]

        await viewModel.reload(sessions: sessions)

        #expect(viewModel.stats.totalTokens == 1_050)
        #expect(viewModel.stats.favoriteModel == DashboardModelKey(provider: .opencode, model: "gpt-5.3-codex"))
        #expect(viewModel.modelBreakdown.map(\.key.model) == ["opencode", "gpt-5.3-codex"])
    }

    @MainActor
    @Test("Heatmap aggregates all providers over the fixed 90 day window")
    func heatmapAggregatesAllProvidersInFixedWindow() async {
        let viewModel = DashboardViewModel(pricing: TestPricing.table)
        viewModel.period = .last7Days
        let sessions = [
            session("claude-recent", provider: .claude, daysAgo: 1, hour: 10, model: "claude-model", tokens: 100, messages: 1),
            session("codex-recent", provider: .codex, daysAgo: 2, hour: 11, model: "codex-model", tokens: 250, messages: 1),
            session("outside-selected-period", provider: .codex, daysAgo: 10, hour: 12, model: "codex-model", tokens: 900, messages: 1),
        ]

        await viewModel.reload(sessions: sessions)

        #expect(viewModel.stats.totalTokens == 350)
        #expect(viewModel.heatmapCells.reduce(0) { $0 + $1.value } == 1_250)
        #expect(viewModel.heatmapActiveDays == 3)
    }

    @MainActor
    @Test("Timeline fallback feeds both heatmap and model trend")
    func emptyTimelineFallbackFeedsHeatmapAndTrend() async {
        let viewModel = DashboardViewModel(pricing: TestPricing.table)
        viewModel.period = .last30Days
        let sessions = [
            session("legacy-claude", provider: .claude, daysAgo: 3, hour: 9, model: "legacy-model", tokens: 420, messages: 2, includeTimeline: false),
        ]

        await viewModel.reload(sessions: sessions)

        #expect(viewModel.stats.totalTokens == 420)
        #expect(viewModel.heatmapCells.reduce(0) { $0 + $1.value } == 420)
        #expect(viewModel.heatmapActiveDays == 1)
        #expect(viewModel.modelTrend.buckets.reduce(0) { $0 + $1.tokens } == 420)
    }

    @MainActor
    @Test("Model trend data revision changes when period changes the data")
    func modelTrendRevisionChangesWhenPeriodDataChanges() async {
        let viewModel = DashboardViewModel(pricing: TestPricing.table)
        let sessions = [
            session("recent", provider: .codex, daysAgo: 1, hour: 10, model: "gpt-shared", tokens: 100, messages: 1),
            session("older", provider: .codex, daysAgo: 10, hour: 10, model: "gpt-shared", tokens: 250, messages: 1),
        ]

        viewModel.period = .last7Days
        await viewModel.reload(sessions: sessions)
        let last7Revision = viewModel.modelTrend.dataRevisionID
        #expect(viewModel.modelTrend.buckets.reduce(0) { $0 + $1.tokens } == 100)

        viewModel.period = .last30Days
        await viewModel.reload(sessions: sessions)

        #expect(viewModel.modelTrend.buckets.reduce(0) { $0 + $1.tokens } == 350)
        #expect(viewModel.modelTrend.dataRevisionID != last7Revision)
    }

    @MainActor
    @Test("Claude cowork billable turns are deduped across dashboard totals and charts")
    func claudeCoworkBillableTurnsAreDeduped() async {
        let viewModel = DashboardViewModel(pricing: TestPricing.table)
        viewModel.period = .last7Days
        let timestamp = dayTime(daysAgo: 1, hour: 14)
        let shared = BillableMessage(
            hash: "assistant-shared:req-1",
            model: "claude-sonnet-4.5",
            usage: usage(1_000),
            cost: CostEstimate(standardAPI: 0.42),
            timestamp: timestamp
        )
        let sessions = [
            billableSession("parent", timestamp: timestamp, messages: [shared]),
            billableSession("cowork", timestamp: timestamp, messages: [shared]),
        ]

        await viewModel.reload(sessions: sessions)

        #expect(viewModel.stats.totalTokens == 1_000)
        #expect(abs(viewModel.stats.totalCost - 0.42) < 1e-9)
        #expect(viewModel.stats.favoriteModel == DashboardModelKey(provider: .claude, model: "claude-sonnet-4.5"))
        #expect(viewModel.modelBreakdown.map(\.usage.total) == [1_000])
        #expect(viewModel.modelTrend.buckets.reduce(0) { $0 + $1.tokens } == 1_000)
        #expect(viewModel.heatmapCells.reduce(0) { $0 + $1.value } == 1_000)
        #expect(viewModel.stats.peakHour == 14)
    }

    private func session(
        _ id: String,
        provider: ProviderKind,
        daysAgo: Int,
        hour: Int,
        model: String,
        tokens: Int,
        messages: Int,
        includeTimeline: Bool = true
    ) -> Session {
        let dayStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysAgo, to: .now)!)
        let when = calendar.date(byAdding: .hour, value: hour, to: dayStart)!
        let usage = TokenUsage(
            inputTokens: tokens,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreation5mTokens: 0,
            cacheCreation1hTokens: 0
        )
        let stats = SessionStats(
            title: id,
            messageCount: messages,
            firstActivity: when,
            lastActivity: when,
            models: [
                ModelUsage(model: model, messageCount: messages, usage: usage, pricing: TestPricing.table),
            ],
            timeline: includeTimeline ? [
                ModelBucket(model: model, start: when, usage: usage),
            ] : []
        )
        return Session(
            id: "\(provider.rawValue)-\(id)",
            externalID: id,
            provider: provider,
            projectDirectoryName: "-p",
            filePath: "/\(provider.rawValue)-\(id).jsonl",
            cwd: nil,
            lastModified: when,
            fileSize: 1,
            stats: stats
        )
    }

    private func billableSession(
        _ id: String,
        timestamp: Date,
        messages: [BillableMessage]
    ) -> Session {
        let modelUsage = ModelUsage(
            model: "claude-sonnet-4.5",
            messageCount: messages.count,
            usage: messages.reduce(.zero) { $0 + $1.usage },
            costEstimate: messages.reduce(.zero) { $0 + $1.cost }
        )
        let stats = SessionStats(
            title: id,
            messageCount: messages.count,
            firstActivity: timestamp,
            lastActivity: timestamp,
            models: [modelUsage],
            timeline: messages.map { ModelBucket(model: $0.model, start: timestamp, usage: $0.usage) },
            billableMessages: messages
        )
        return Session(
            id: "claude-\(id)",
            externalID: id,
            provider: .claude,
            projectDirectoryName: "-p",
            filePath: "/claude-\(id).jsonl",
            cwd: nil,
            lastModified: timestamp,
            fileSize: 1,
            stats: stats
        )
    }

    private func dayTime(daysAgo: Int, hour: Int) -> Date {
        let dayStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysAgo, to: .now)!)
        return calendar.date(byAdding: .hour, value: hour, to: dayStart)!
    }

    private func usage(_ tokens: Int) -> TokenUsage {
        TokenUsage(
            inputTokens: tokens,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreation5mTokens: 0,
            cacheCreation1hTokens: 0
        )
    }
}
