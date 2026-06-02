import Foundation
import Testing
@testable import ClaudeStats

@Suite("GanttViewModel")
@MainActor
struct GanttViewModelTests {
    @Test("AI active publishes current snapshot before git and baseline enrichment")
    func aiActivePublishesCurrentSnapshotBeforeEnrichment() async {
        let markerDate = pastDay().addingTimeInterval(4 * 3_600)
        let gitLoader = DelayedGanttGitMetricsLoader(
            delay: .milliseconds(80),
            metrics: GanttExternalMetrics(
                commitCount: 4,
                failureSignals: 0,
                retrySignals: 0,
                commitMarkers: [
                    GanttCommitMarker(
                        id: "repo|abcdef123",
                        projectID: "/Users/dev/app",
                        date: markerDate,
                        repoName: "app",
                        shortHash: "abcdef1",
                        subject: "Ship gantt markers"
                    ),
                ]
            )
        )
        let viewModel = GanttViewModel(gitMetricsLoader: gitLoader)
        viewModel.selectedDate = pastDay()
        let interval = interval(in: viewModel.period, startOffset: 3_600, duration: 3_600)

        await viewModel.reload(
            sessions: [session(intervals: [interval])],
            codingSurfaceBundleIDs: [],
            cliHostBundleIDs: []
        )

        #expect(!viewModel.isLoading)
        #expect(viewModel.isEnriching)
        #expect(viewModel.snapshot.projects.count == 1)
        #expect(viewModel.snapshot.metrics.commitCount == 0)
        #expect(viewModel.snapshot.commitMarkers.isEmpty)
        #expect(viewModel.snapshot.baselineComparison == nil)

        let enriched = await eventually {
            viewModel.snapshot.baselineComparison != nil
        }
        #expect(enriched)
        #expect(viewModel.snapshot.metrics.commitCount == 4)
        #expect(viewModel.snapshot.commitMarkers.map(\.shortHash) == ["abcdef1"])
        #expect(viewModel.snapshot.commitMarkers.map(\.projectID) == ["/Users/dev/app"])
        #expect(!viewModel.isEnriching)
    }

    @Test("Assisted focus does not wait for baseline focus query before publishing current snapshot")
    func assistedFocusPublishesBeforeBaselineFocusQuery() async {
        let focusRecorder = FocusCallRecorder()
        let gitLoader = DelayedGanttGitMetricsLoader(
            delay: .milliseconds(80),
            metrics: .zero
        )
        let viewModel = GanttViewModel(
            focusIntervalLoader: { range, bundleIDs in
                await focusRecorder.load(range: range, bundleIDs: bundleIDs)
            },
            gitMetricsLoader: gitLoader
        )
        viewModel.selectedDate = pastDay()
        viewModel.activityMode = .assistedFocus
        let interval = interval(in: viewModel.period, startOffset: 3_600, duration: 3_600)

        await viewModel.reload(
            sessions: [session(intervals: [interval])],
            codingSurfaceBundleIDs: ["com.apple.Terminal"],
            cliHostBundleIDs: []
        )

        #expect(viewModel.snapshot.projects.count == 1)
        #expect(await focusRecorder.callCount() == 1)

        let baselineQueried = await eventually {
            await focusRecorder.callCount() >= 2
        }
        #expect(baselineQueried)
    }

    @Test("Usage limit refresh updates load lanes without changing timeline render revision")
    func usageLimitRefreshOnlyUpdatesLoadLanes() async {
        let viewModel = GanttViewModel(gitMetricsLoader: DelayedGanttGitMetricsLoader(delay: .milliseconds(200), metrics: .zero))
        viewModel.selectedDate = pastDay()
        let interval = interval(in: viewModel.period, startOffset: 3_600, duration: 3_600)

        await viewModel.reload(
            sessions: [session(intervals: [interval])],
            codingSurfaceBundleIDs: [],
            cliHostBundleIDs: []
        )

        let revision = viewModel.snapshot.renderRevisionID
        #expect(viewModel.snapshot.load.groups.first { $0.kind == .usageLimit } == nil)

        viewModel.refreshUsageLimitReports([
            usageLimitReport(
                provider: .claude,
                resetAt: viewModel.snapshot.domain.start.addingTimeInterval(5 * 3_600)
            ),
        ])

        #expect(viewModel.snapshot.renderRevisionID == revision)
        #expect(viewModel.snapshot.load.groups.first { $0.kind == .usageLimit }?.lanes.count == 1)
    }

    @Test("Focusing inside the same period does not bump the manual reload token")
    func focusInsideSamePeriodDoesNotBumpReloadToken() {
        let viewModel = GanttViewModel()
        viewModel.range = .week
        viewModel.selectedDate = pastDay()
        let token = viewModel.reloadToken
        let domain = viewModel.period.domain

        viewModel.focusDate(domain.start.addingTimeInterval(12 * 3_600))

        #expect(viewModel.reloadToken == token)
        #expect(viewModel.period.domain == domain)
    }

    @Test("Assisted focus records no matching focus data")
    func assistedFocusRecordsNoMatchingFocusData() async {
        let viewModel = GanttViewModel(focusIntervalLoader: { _, _ in
            .success([])
        })
        viewModel.selectedDate = pastDay()
        viewModel.activityMode = .assistedFocus

        let interval = interval(in: viewModel.period, startOffset: 3_600, duration: 3_600)

        await viewModel.reload(
            sessions: [session(intervals: [interval])],
            codingSurfaceBundleIDs: ["com.apple.dt.Xcode"],
            cliHostBundleIDs: ["com.apple.Terminal"]
        )

        #expect(viewModel.permissionState == .ok)
        #expect(viewModel.focusDataState == .noMatchingFocusData)
        #expect(viewModel.snapshot.projects.isEmpty)
        #expect(viewModel.snapshot.sourceSessionCount == 1)
    }

    @Test("Assisted focus uses matching focus data")
    func assistedFocusUsesMatchingFocusData() async {
        let focusBundleID = "com.apple.Terminal"
        let viewModel = GanttViewModel(focusIntervalLoader: { range, _ in
            let focus = DateInterval(start: range.start.addingTimeInterval(3_600), duration: 3_600)
            return .success([AppFocusInterval(bundleID: focusBundleID, interval: focus)])
        })
        viewModel.selectedDate = pastDay()
        viewModel.activityMode = .assistedFocus

        let interval = interval(in: viewModel.period, startOffset: 3_600, duration: 3_600)

        await viewModel.reload(
            sessions: [session(intervals: [interval])],
            codingSurfaceBundleIDs: [],
            cliHostBundleIDs: [focusBundleID]
        )

        #expect(viewModel.permissionState == .ok)
        #expect(viewModel.focusDataState == .available)
        #expect(viewModel.snapshot.projects.count == 1)
        #expect(viewModel.snapshot.totalDuration == 3_600)
    }

    @Test("Project detail assisted focus records query failures")
    func projectDetailAssistedFocusRecordsQueryFailures() async {
        let viewModel = GanttProjectDetailViewModel(
            initialMode: .assistedFocus,
            focusIntervalLoader: { _, _ in .failure(.queryFailed("boom")) }
        )
        let interval = interval(in: viewModel.period, startOffset: 3_600, duration: 3_600)

        await viewModel.reload(
            projectID: "/Users/dev/app",
            sessions: [session(intervals: [interval])],
            codingSurfaceBundleIDs: ["com.apple.dt.Xcode"],
            cliHostBundleIDs: ["com.apple.Terminal"]
        )

        #expect(viewModel.permissionState == .ok)
        #expect(viewModel.focusDataState == .queryFailed)
        #expect(viewModel.snapshot.projects.isEmpty)
        #expect(viewModel.snapshot.sourceSessionCount == 1)
    }

    private func pastDay() -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86_400)
    }

    private func interval(in period: GanttPeriod, startOffset: TimeInterval, duration: TimeInterval) -> DateInterval {
        DateInterval(
            start: period.dataRange.start.addingTimeInterval(startOffset),
            duration: duration
        )
    }

    private func interval(in range: DateInterval, startOffset: TimeInterval, duration: TimeInterval) -> DateInterval {
        DateInterval(
            start: range.start.addingTimeInterval(startOffset),
            duration: duration
        )
    }

    private func session(intervals: [DateInterval]) -> Session {
        let stats = SessionStats(
            title: "session",
            messageCount: 1,
            firstActivity: intervals.map(\.start).min(),
            lastActivity: intervals.map(\.end).max(),
            models: [],
            timeline: [],
            activityIntervals: intervals
        )
        return Session(
            id: "app::session",
            externalID: "session",
            provider: .claude,
            projectDirectoryName: "-Users-dev-app",
            filePath: "/tmp/session.jsonl",
            cwd: "/Users/dev/app",
            lastModified: intervals.map(\.end).max() ?? .now,
            fileSize: 1,
            stats: stats
        )
    }

    private func usageLimitReport(provider: ProviderKind, resetAt: Date) -> UsageLimitReport {
        .fresh(
            provider: provider,
            snapshot: UsageLimitSnapshot(
                provider: provider,
                windows: [
                    UsageLimitWindow(
                        id: "five_hour",
                        label: "5h",
                        usedPercent: 50,
                        resetAt: resetAt,
                        windowMinutes: 300
                    ),
                ],
                capturedAt: resetAt.addingTimeInterval(-60),
                sourceLabel: "Test",
                sourcePath: nil,
                planType: nil,
                limitID: nil
            )
        )
    }

    private func eventually(_ condition: @escaping @MainActor () async -> Bool) async -> Bool {
        for _ in 0 ..< 50 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}

private actor DelayedGanttGitMetricsLoader: GanttGitMetricsLoading {
    let delay: Duration
    let metrics: GanttExternalMetrics
    private(set) var calls: [DateInterval] = []

    init(delay: Duration, metrics: GanttExternalMetrics) {
        self.delay = delay
        self.metrics = metrics
    }

    func externalMetrics(
        sessions: [Session],
        during interval: DateInterval,
        projectIDFilter: String?
    ) async -> GanttExternalMetrics {
        calls.append(interval)
        try? await Task.sleep(for: delay)
        return metrics
    }
}

private actor FocusCallRecorder {
    private var calls: [DateInterval] = []

    func load(
        range: DateInterval,
        bundleIDs: Set<String>
    ) -> Result<[AppFocusInterval], ScreenTimeService.Failure> {
        calls.append(range)
        return .success(bundleIDs.map { AppFocusInterval(bundleID: $0, interval: range) })
    }

    func callCount() -> Int {
        calls.count
    }
}
