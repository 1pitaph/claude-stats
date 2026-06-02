import Foundation
import Testing
@testable import ClaudeStats

@Suite("GanttTimelineBuilder")
struct GanttTimelineBuilderTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func h(_ value: Double) -> Date {
        base.addingTimeInterval(value * 3_600)
    }

    private func m(_ value: Double) -> Date {
        base.addingTimeInterval(value * 60)
    }

    private func iv(_ start: Double, _ end: Double) -> DateInterval {
        DateInterval(start: h(start), end: h(end))
    }

    private func im(_ start: Double, _ end: Double) -> DateInterval {
        DateInterval(start: m(start), end: m(end))
    }

    private func period(range: GanttRange = .day, start: Double = 0, end: Double = 24) -> GanttPeriod {
        let domain = iv(start, end)
        return GanttPeriod(range: range, domain: domain, dataRange: domain)
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour).date!
    }

    private func session(
        _ id: String,
        provider: ProviderKind = .claude,
        projectDirectoryName: String,
        cwd: String?,
        intervals: [DateInterval],
        models: [ModelUsage] = [],
        messageCount: Int = 1
    ) -> Session {
        let stats = SessionStats(
            title: id,
            messageCount: messageCount,
            firstActivity: intervals.map(\.start).min(),
            lastActivity: intervals.map(\.end).max(),
            models: models,
            timeline: [],
            activityIntervals: intervals
        )
        return Session(
            id: "\(projectDirectoryName)::\(id)",
            externalID: id,
            provider: provider,
            projectDirectoryName: projectDirectoryName,
            filePath: "/tmp/\(id).jsonl",
            cwd: cwd,
            lastModified: base,
            fileSize: 1,
            stats: stats
        )
    }

    @Test("Same cwd across providers merges into one project row")
    func sameCwdAcrossProvidersMerges() {
        let sessions = [
            session("a", provider: .claude, projectDirectoryName: "-Users-dev-app", cwd: "/Users/dev/app", intervals: [iv(1, 2)]),
            session("b", provider: .codex, projectDirectoryName: "/Users/dev/app", cwd: "/Users/dev/app/.", intervals: [iv(3, 4)]),
        ]

        let snapshot = GanttTimelineBuilder.build(
            sessions: sessions,
            period: period(),
            activityMode: .aiActive
        )

        #expect(snapshot.projects.count == 1)
        #expect(snapshot.projects.first?.id == "/Users/dev/app")
        #expect(snapshot.projects.first?.displayName == "app")
        #expect(snapshot.projects.first?.providers == Set([ProviderKind.claude, .codex]))
        #expect(snapshot.projects.first?.segments.count == 2)
    }

    @Test("Missing cwd uses stable provider and project directory fallback id")
    func missingCwdUsesStableFallbackID() {
        let sessions = [
            session("a", projectDirectoryName: "-Users-dev-fallback", cwd: nil, intervals: [iv(1, 2)]),
            session("b", projectDirectoryName: "-Users-dev-fallback", cwd: nil, intervals: [iv(3, 4)]),
        ]

        let snapshot = GanttTimelineBuilder.build(
            sessions: sessions,
            period: period(),
            activityMode: .aiActive
        )

        #expect(snapshot.projects.count == 1)
        #expect(snapshot.projects.first?.id == "claude:-Users-dev-fallback")
        #expect(snapshot.projects.first?.displayName == "fallback")
    }

    @Test("Intervals clip to day week and month ranges")
    func clipsIntervalsToPeriods() {
        for range in [GanttRange.day, .week, .month] {
            let clippedPeriod = period(range: range, start: 2, end: 6)
            let snapshot = GanttTimelineBuilder.build(
                sessions: [
                    session("a", projectDirectoryName: "-Users-dev-app", cwd: "/Users/dev/app", intervals: [iv(1, 3), iv(5, 8)]),
                ],
                period: clippedPeriod,
                activityMode: .aiActive
            )

            #expect(snapshot.range == range)
            #expect(snapshot.projects.first?.segments.map(\.interval) == [iv(2, 3), iv(5, 6)])
        }
    }

    @Test("Gaps up to ten minutes merge, larger gaps stay separate")
    func mergesDisplayGapsAtTenMinutes() {
        let withinGap = GanttTimelineBuilder.build(
            sessions: [
                session("a", projectDirectoryName: "-Users-dev-app", cwd: "/Users/dev/app", intervals: [im(0, 30), im(40, 60)]),
            ],
            period: GanttPeriod(range: .day, domain: im(0, 120), dataRange: im(0, 120)),
            activityMode: .aiActive
        )
        #expect(withinGap.projects.first?.segments.map(\.interval) == [im(0, 60)])

        let beyondGap = GanttTimelineBuilder.build(
            sessions: [
                session("a", projectDirectoryName: "-Users-dev-app", cwd: "/Users/dev/app", intervals: [im(0, 30), im(41, 60)]),
            ],
            period: GanttPeriod(range: .day, domain: im(0, 120), dataRange: im(0, 120)),
            activityMode: .aiActive
        )
        #expect(beyondGap.projects.first?.segments.map(\.interval) == [im(0, 30), im(41, 60)])
    }

    @Test("Assisted focus keeps only AI and focus intersections")
    func assistedFocusIntersectsAIWithFocus() {
        let snapshot = GanttTimelineBuilder.build(
            sessions: [
                session("a", projectDirectoryName: "-Users-dev-app", cwd: "/Users/dev/app", intervals: [iv(1, 5)]),
            ],
            period: period(),
            activityMode: .assistedFocus,
            focusIntervals: [iv(2, 3), iv(4, 6)]
        )

        #expect(snapshot.projects.first?.segments.map(\.interval) == [iv(2, 3), iv(4, 5)])
        #expect(abs((snapshot.projects.first?.totalDuration ?? 0) - 7_200) < 0.001)
    }

    @Test("Project id filter returns only the selected project")
    func projectIDFilterReturnsOnlySelectedProject() {
        let snapshot = GanttTimelineBuilder.build(
            sessions: [
                session("a", projectDirectoryName: "-Users-dev-app", cwd: "/Users/dev/app", intervals: [iv(1, 2)]),
                session("b", projectDirectoryName: "-Users-dev-other", cwd: "/Users/dev/other", intervals: [iv(3, 5)]),
            ],
            period: period(),
            activityMode: .aiActive,
            projectIDFilter: "/Users/dev/app"
        )

        #expect(snapshot.projects.map(\.id) == ["/Users/dev/app"])
        #expect(snapshot.projects.first?.segments.map(\.interval) == [iv(1, 2)])
        #expect(snapshot.sourceSessionCount == 2)
    }

    @Test("Project id filter with no match keeps source session count")
    func projectIDFilterNoMatchKeepsSourceSessionCount() {
        let snapshot = GanttTimelineBuilder.build(
            sessions: [
                session("a", projectDirectoryName: "-Users-dev-app", cwd: "/Users/dev/app", intervals: [iv(1, 2)]),
                session("b", projectDirectoryName: "-Users-dev-other", cwd: "/Users/dev/other", intervals: [iv(3, 5)]),
            ],
            period: period(),
            activityMode: .aiActive,
            projectIDFilter: "/Users/dev/missing"
        )

        #expect(snapshot.projects.isEmpty)
        #expect(snapshot.sourceSessionCount == 2)
    }

    @Test("Recent seven days covers local natural days and clips data end to now")
    func recentSevenDaysCoversLocalNaturalDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = utcDate(2026, 6, 1, 15)

        let recent = GanttPeriod.recentSevenDays(endingAt: now, calendar: calendar)

        #expect(recent.range == .week)
        #expect(recent.domain.start == utcDate(2026, 5, 26))
        #expect(recent.domain.end == utcDate(2026, 6, 2))
        #expect(recent.dataRange.start == recent.domain.start)
        #expect(recent.dataRange.end == now)
        #expect(calendar.dateComponents([.day], from: recent.domain.start, to: recent.domain.end).day == 7)
    }

    @Test("Assisted focus project filter keeps only selected project intersections")
    func assistedFocusProjectFilterKeepsSelectedIntersections() {
        let snapshot = GanttTimelineBuilder.build(
            sessions: [
                session("a", projectDirectoryName: "-Users-dev-app", cwd: "/Users/dev/app", intervals: [iv(1, 5)]),
                session("b", projectDirectoryName: "-Users-dev-other", cwd: "/Users/dev/other", intervals: [iv(2, 6)]),
            ],
            period: period(),
            activityMode: .assistedFocus,
            focusIntervals: [iv(3, 4)],
            projectIDFilter: "/Users/dev/app"
        )

        #expect(snapshot.projects.map(\.id) == ["/Users/dev/app"])
        #expect(snapshot.projects.first?.segments.map(\.interval) == [iv(3, 4)])
    }

    @Test("Projects sort by total duration then latest activity")
    func projectsSortByDurationThenLatestActivity() {
        let snapshot = GanttTimelineBuilder.build(
            sessions: [
                session("short-old", projectDirectoryName: "-Users-dev-old", cwd: "/Users/dev/old", intervals: [iv(4, 5)]),
                session("long", projectDirectoryName: "-Users-dev-long", cwd: "/Users/dev/long", intervals: [iv(1, 3)]),
                session("short-new", projectDirectoryName: "-Users-dev-new", cwd: "/Users/dev/new", intervals: [iv(10, 11)]),
            ],
            period: period(),
            activityMode: .aiActive
        )

        #expect(snapshot.projects.map(\.displayName) == ["long", "new", "old"])
    }

    @Test("Segments and load lanes aggregate tokens cost focus and usage limits")
    func segmentsAndLoadLanesAggregateMetrics() {
        let usage = TokenUsage(inputTokens: 100, outputTokens: 50)
        let snapshot = GanttTimelineBuilder.build(
            sessions: [
                session(
                    "feature",
                    provider: .codex,
                    projectDirectoryName: "-Users-dev-app",
                    cwd: "/Users/dev/app",
                    intervals: [iv(1, 3)],
                    models: [
                        ModelUsage(model: "gpt-5-codex", messageCount: 4, usage: usage, estimatedCost: 1.25),
                    ],
                    messageCount: 4
                ),
            ],
            period: period(),
            activityMode: .aiActive,
            focusAppIntervals: [
                AppFocusInterval(bundleID: "com.apple.dt.Xcode", interval: iv(1.5, 2.5)),
            ],
            usageLimitReports: [
                .fresh(
                    provider: .claude,
                    snapshot: UsageLimitSnapshot(
                        provider: .claude,
                        windows: [
                            UsageLimitWindow(id: "five_hour", label: "5h", usedPercent: 75, resetAt: h(6), windowMinutes: 300),
                        ],
                        capturedAt: h(2),
                        sourceLabel: "Test",
                        sourcePath: nil,
                        planType: nil,
                        limitID: nil
                    )
                ),
            ]
        )

        let project = snapshot.projects.first
        let segment = project?.segments.first
        #expect(project?.sessionCount == 1)
        #expect(project?.messageCount == 4)
        #expect(project?.totalUsage.total == 150)
        #expect(abs((project?.totalCost ?? 0) - 1.25) < 0.001)
        #expect(abs((project?.focusOverlapDuration ?? 0) - 3_600) < 0.001)
        #expect(segment?.models.first?.model == "gpt-5-codex")
        #expect(segment?.usage.total == 150)
        #expect(snapshot.metrics.tokens == 150)
        #expect(snapshot.metrics.messageCount == 4)

        let providerLane = snapshot.load.groups.first { $0.kind == .provider }?.lanes.first
        let modelLane = snapshot.load.groups.first { $0.kind == .model }?.lanes.first
        let focusLane = snapshot.load.groups.first { $0.kind == .focus }?.lanes.first
        let usageLimitLane = snapshot.load.groups.first { $0.kind == .usageLimit }?.lanes.first
        #expect(providerLane?.id == ProviderKind.codex.rawValue)
        #expect(providerLane?.tokens == 150)
        #expect(modelLane?.id == "gpt-5-codex")
        #expect(focusLane?.id == "com.apple.dt.Xcode")
        #expect(usageLimitLane?.id == "\(ProviderKind.claude.rawValue)|five_hour")
        #expect(abs((usageLimitLane?.intensity ?? 0) - 0.75) < 0.001)
    }

    @Test("Baseline comparison exposes metric deltas")
    func baselineComparisonExposesMetricDeltas() {
        let current = GanttTimelineBuilder.build(
            sessions: [
                session(
                    "fix retry current",
                    projectDirectoryName: "-Users-dev-app",
                    cwd: "/Users/dev/app",
                    intervals: [iv(1, 3)],
                    models: [
                        ModelUsage(
                            model: "claude-sonnet",
                            messageCount: 2,
                            usage: TokenUsage(inputTokens: 20, outputTokens: 10),
                            estimatedCost: 0.30
                        ),
                    ],
                    messageCount: 2
                ),
            ],
            period: period(),
            activityMode: .aiActive,
            externalMetrics: GanttExternalMetrics(commitCount: 3, failureSignals: 1, retrySignals: 2)
        )
        let baseline = GanttTimelineBuilder.build(
            sessions: [
                session(
                    "baseline",
                    projectDirectoryName: "-Users-dev-app",
                    cwd: "/Users/dev/app",
                    intervals: [iv(-22, -21)],
                    models: [
                        ModelUsage(
                            model: "claude-sonnet",
                            messageCount: 1,
                            usage: TokenUsage(inputTokens: 5, outputTokens: 5),
                            estimatedCost: 0.10
                        ),
                    ],
                    messageCount: 1
                ),
            ],
            period: period(start: -24, end: 0),
            activityMode: .aiActive,
            externalMetrics: GanttExternalMetrics(commitCount: 1, failureSignals: 0, retrySignals: 1)
        )

        let comparison = GanttTimelineBuilder.baselineComparison(current: current, baseline: baseline)

        #expect(abs(comparison.activeDurationDelta - 3_600) < 0.001)
        #expect(comparison.tokensDelta == 20)
        #expect(abs(comparison.costDelta - 0.20) < 0.001)
        #expect(comparison.commitDelta == 2)
        #expect(comparison.failureSignalDelta == 2)
        #expect(comparison.retrySignalDelta == 2)
    }
}
