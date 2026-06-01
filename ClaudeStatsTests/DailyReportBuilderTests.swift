import Foundation
import Testing
@testable import ClaudeStats

@Suite("Daily report builder")
struct DailyReportBuilderTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.startOfDay(for: date(year, month, day))
    }

    private func usage(_ tokens: Int) -> TokenUsage {
        TokenUsage(inputTokens: tokens)
    }

    private func session(
        _ id: String,
        provider: ProviderKind = .claude,
        projectDirectoryName: String = "-Users-dev-app",
        cwd: String? = "/Users/dev/app",
        intervals: [DateInterval] = [],
        timeline: [ModelBucket] = [],
        totalUsage: TokenUsage = .zero,
        lastActivity: Date? = nil
    ) -> Session {
        let inferredLast = lastActivity ?? intervals.map(\.end).max() ?? timeline.map(\.start).max() ?? date(2026, 1, 10)
        let stats = SessionStats(
            title: id,
            messageCount: 1,
            firstActivity: intervals.map(\.start).min() ?? inferredLast,
            lastActivity: inferredLast,
            models: [
                ModelUsage(model: "model", messageCount: 1, usage: totalUsage, estimatedCost: 0),
            ],
            timeline: timeline,
            activityIntervals: intervals
        )
        return Session(
            id: "\(provider.rawValue)::\(id)",
            externalID: id,
            provider: provider,
            projectDirectoryName: projectDirectoryName,
            filePath: "/tmp/\(id).jsonl",
            cwd: cwd,
            lastModified: inferredLast,
            fileSize: 200,
            stats: stats
        )
    }

    @Test("Cross-midnight activity is clipped into both days")
    func crossMidnightActivityClipsIntoBothDays() {
        let interval = DateInterval(
            start: date(2026, 1, 10, 23, 30),
            end: date(2026, 1, 11, 0, 30)
        )

        let snapshot = DailyReportBuilder.buildMonth(
            sessions: [session("a", intervals: [interval])],
            month: date(2026, 1, 1),
            calendar: calendar
        )

        let first = snapshot.summary(on: day(2026, 1, 10), calendar: calendar).projects.first
        let second = snapshot.summary(on: day(2026, 1, 11), calendar: calendar).projects.first
        #expect(first?.activeDuration == 1_800)
        #expect(second?.activeDuration == 1_800)
    }

    @Test("Same cwd across providers merges into one project")
    func sameCwdAcrossProvidersMerges() {
        let sessions = [
            session("claude", provider: .claude, cwd: "/Users/dev/app", intervals: [
                DateInterval(start: date(2026, 1, 10, 9), end: date(2026, 1, 10, 10)),
            ]),
            session("codex", provider: .codex, projectDirectoryName: "/Users/dev/app", cwd: "/Users/dev/app/.", intervals: [
                DateInterval(start: date(2026, 1, 10, 11), end: date(2026, 1, 10, 12)),
            ]),
        ]

        let daySummary = DailyReportBuilder.buildMonth(
            sessions: sessions,
            month: date(2026, 1, 1),
            calendar: calendar
        ).summary(on: day(2026, 1, 10), calendar: calendar)

        #expect(daySummary.projects.count == 1)
        #expect(daySummary.projects.first?.id == "/Users/dev/app")
        #expect(daySummary.projects.first?.displayName == "app")
        #expect(daySummary.projects.first?.providers == Set([ProviderKind.claude, .codex]))
        #expect(daySummary.projects.first?.activeDuration == 7_200)
        #expect(daySummary.projects.first?.sessionCount == 2)
    }

    @Test("Timeline tokens and no-timeline fallback are bucketed by day")
    func timelineTokensAndFallbackBucketByDay() {
        let timelineSession = session(
            "timeline",
            intervals: [
                DateInterval(start: date(2026, 1, 10, 9), end: date(2026, 1, 10, 9, 30)),
            ],
            timeline: [
                ModelBucket(model: "model", start: date(2026, 1, 10, 9), usage: usage(100)),
                ModelBucket(model: "model", start: date(2026, 1, 11, 10), usage: usage(200)),
            ]
        )
        let fallbackSession = session(
            "fallback",
            projectDirectoryName: "-Users-dev-fallback",
            cwd: "/Users/dev/fallback",
            totalUsage: usage(300),
            lastActivity: date(2026, 1, 12, 15)
        )

        let snapshot = DailyReportBuilder.buildMonth(
            sessions: [timelineSession, fallbackSession],
            month: date(2026, 1, 1),
            calendar: calendar
        )

        #expect(snapshot.summary(on: day(2026, 1, 10), calendar: calendar).projects.first { $0.id == "/Users/dev/app" }?.tokens == 100)
        #expect(snapshot.summary(on: day(2026, 1, 11), calendar: calendar).projects.first { $0.id == "/Users/dev/app" }?.tokens == 200)
        #expect(snapshot.summary(on: day(2026, 1, 12), calendar: calendar).projects.first { $0.id == "/Users/dev/fallback" }?.tokens == 300)
    }

    @Test("Month rollup sorts by duration then tokens")
    func monthRollupSortsByDurationThenTokens() {
        let appDayOne = session("app-1", cwd: "/Users/dev/app", intervals: [
            DateInterval(start: date(2026, 1, 10, 9), end: date(2026, 1, 10, 11)),
        ], totalUsage: usage(100), lastActivity: date(2026, 1, 10, 11))
        let appDayTwo = session("app-2", cwd: "/Users/dev/app", intervals: [
            DateInterval(start: date(2026, 1, 11, 9), end: date(2026, 1, 11, 10)),
        ], totalUsage: usage(50), lastActivity: date(2026, 1, 11, 10))
        let other = session("other", projectDirectoryName: "-Users-dev-other", cwd: "/Users/dev/other", intervals: [
            DateInterval(start: date(2026, 1, 10, 13), end: date(2026, 1, 10, 14)),
        ], totalUsage: usage(500), lastActivity: date(2026, 1, 10, 14))

        let snapshot = DailyReportBuilder.buildMonth(
            sessions: [other, appDayTwo, appDayOne],
            month: date(2026, 1, 1),
            calendar: calendar
        )

        #expect(snapshot.projects.map(\.id) == ["/Users/dev/app", "/Users/dev/other"])
        #expect(snapshot.projects.first?.activeDays == 2)
        #expect(snapshot.projects.first?.activeDuration == 10_800)
        #expect(snapshot.projects.first?.tokens == 150)
        #expect(snapshot.projects.first?.sessionCount == 2)
    }

    @Test("Injected git counts attach to day and month summaries")
    func injectedGitCountsAttachToSummaries() {
        let snapshot = DailyReportBuilder.buildMonth(
            sessions: [
                session("a", cwd: "/Users/dev/app", intervals: [
                    DateInterval(start: date(2026, 1, 10, 9), end: date(2026, 1, 10, 10)),
                ]),
            ],
            month: date(2026, 1, 1),
            gitCommitCounts: ["/Users/dev/app": [day(2026, 1, 10): 2]],
            calendar: calendar
        )

        #expect(snapshot.summary(on: day(2026, 1, 10), calendar: calendar).projects.first?.gitCommitCount == 2)
        #expect(snapshot.projects.first?.gitCommitCount == 2)
    }

    @Test("Daily report section falls back to calendar")
    func sectionFallback() {
        #expect(DailyReportSection(storedRawValue: "missing") == .calendar)
        #expect(DailyReportSection(storedRawValue: "projects") == .projects)
    }

    @Test("View model showToday selects current day and month")
    @MainActor
    func viewModelShowTodaySelectsCurrentDayAndMonth() {
        let model = DailyReportViewModel(calendar: calendar, gitActivityProvider: NoopDailyReportGitProvider())
        model.selectDate(date(2026, 1, 10))
        model.showToday()

        let today = calendar.startOfDay(for: .now)
        let currentMonth = DailyReportBuilder.monthInterval(for: today, calendar: calendar).start
        #expect(model.selectedDate == today)
        #expect(model.displayedMonthStart == currentMonth)
    }
}

private struct NoopDailyReportGitProvider: DailyReportGitActivityProviding {
    func commitCounts(
        for projectPaths: [String],
        in interval: DateInterval,
        calendar: Calendar
    ) async -> [String: [Date: Int]] {
        [:]
    }
}
