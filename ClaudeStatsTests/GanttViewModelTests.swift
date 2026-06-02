import Foundation
import Testing
@testable import ClaudeStats

@Suite("GanttViewModel")
@MainActor
struct GanttViewModelTests {
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
}
