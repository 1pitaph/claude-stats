import Foundation

struct DailyReportGitSummaryPlanner: Sendable {
    func plan(inputMode: DailyReportGitSummaryInputMode) -> DailyReportGitSummaryPlan {
        DailyReportGitSummaryPlan(
            algorithm: .singleShot,
            inputMode: inputMode,
            includeDiffExcerpts: inputMode == .diffAware,
            diffPerCommitLimit: 8_000,
            diffTotalLimit: 30_000,
            maxTokens: 1_200,
            temperature: 0.2
        )
    }
}
