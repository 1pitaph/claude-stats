import Foundation
import Testing
@testable import ClaudeStats

@Suite("AI activity view model")
struct AIActivityViewModelTests {
    @MainActor
    @Test("Out-of-order reload results do not overwrite newer activity")
    func outOfOrderReloadResultsDoNotOverwriteNewerActivity() async {
        let loader = OrderedFocusLoader()
        let viewModel = AIActivityViewModel(focusIntervalLoader: { range, bundleIDs in
            await loader.load(range: range, bundleIDs: bundleIDs)
        })
        let bundleIDs: Set<String> = ["com.example.editor"]

        let first = Task {
            await viewModel.reload(
                sessions: [],
                codingSurfaceBundleIDs: bundleIDs,
                cliHostBundleIDs: []
            )
        }
        guard await loader.waitForFirstSuspension() else {
            first.cancel()
            Issue.record("First reload did not suspend")
            return
        }

        let second = Task {
            await viewModel.reload(
                sessions: [],
                codingSurfaceBundleIDs: bundleIDs,
                cliHostBundleIDs: []
            )
        }
        guard await loader.waitForCallCount(2) else {
            first.cancel()
            second.cancel()
            Issue.record("Second reload did not start")
            return
        }

        await second.value
        #expect(viewModel.dayActivity?.codingSurfaceSeconds == 120)
        #expect(viewModel.isLoading == false)

        #expect(await loader.finishFirst())
        await first.value

        #expect(viewModel.dayActivity?.codingSurfaceSeconds == 120)
        #expect(viewModel.isLoading == false)
    }
}

private actor OrderedFocusLoader {
    private var callCount = 0
    private var firstRange: DateInterval?
    private var firstContinuation: CheckedContinuation<Result<[AppFocusInterval], ScreenTimeService.Failure>, Never>?

    func load(
        range: DateInterval,
        bundleIDs: Set<String>
    ) async -> Result<[AppFocusInterval], ScreenTimeService.Failure> {
        callCount += 1
        if callCount == 1 {
            firstRange = range
            return await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }

        return .success([Self.interval(in: range, bundleID: bundleIDs.first, duration: 120)])
    }

    func waitForFirstSuspension() async -> Bool {
        for _ in 0..<1_000 {
            if firstContinuation != nil { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    func waitForCallCount(_ expected: Int) async -> Bool {
        for _ in 0..<1_000 {
            if callCount >= expected { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    func finishFirst() -> Bool {
        guard let firstContinuation, let firstRange else { return false }
        self.firstContinuation = nil
        self.firstRange = nil
        firstContinuation.resume(
            returning: .success([Self.interval(in: firstRange, bundleID: "com.example.editor", duration: 60)])
        )
        return true
    }

    private static func interval(in range: DateInterval, bundleID: String?, duration: TimeInterval) -> AppFocusInterval {
        AppFocusInterval(
            bundleID: bundleID ?? "com.example.editor",
            interval: DateInterval(start: range.start.addingTimeInterval(60), duration: duration)
        )
    }
}
