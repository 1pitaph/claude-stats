import Foundation
import Observation

@MainActor
@Observable
final class DailyReportProjectGitSheetViewModel {
    private(set) var commitState: DailyReportGitDayLoadState = .idle
    private(set) var summaryState: DailyReportGitDaySummaryLoadState = .idle
    private(set) var llmReadinessMessage: String?

    @ObservationIgnored private let gitProvider: any DailyReportGitDayActivityProviding
    @ObservationIgnored private let summaryService: DailyReportGitDaySummaryService

    init(
        gitProvider: any DailyReportGitDayActivityProviding = DailyReportGitDayActivityProvider(),
        summaryService: DailyReportGitDaySummaryService = DailyReportGitDaySummaryService()
    ) {
        self.gitProvider = gitProvider
        self.summaryService = summaryService
    }

    var snapshot: DailyReportGitDaySnapshot? {
        if case .loaded(let snapshot) = commitState { return snapshot }
        return nil
    }

    var summary: DailyReportGitDayLLMSummary? {
        if case .loaded(let summary) = summaryState { return summary }
        return nil
    }

    var isLoadingCommits: Bool {
        if case .loading = commitState { return true }
        return false
    }

    var isGeneratingSummary: Bool {
        if case .loading = summaryState { return true }
        return false
    }

    var canGenerate: Bool {
        guard !isLoadingCommits, !isGeneratingSummary else { return false }
        guard let snapshot, snapshot.repo != nil, !snapshot.commits.isEmpty else { return false }
        return true
    }

    func loadCommits(
        project: DailyReportProjectDaySummary,
        day: Date,
        calendar: Calendar
    ) async {
        commitState = .loading
        summaryState = .idle
        let snapshot = await gitProvider.snapshot(for: project, day: day, calendar: calendar)
        guard !Task.isCancelled else { return }
        commitState = .loaded(snapshot)
    }

    func loadCachedSummary(
        endpoint: AppLLMGenerationEndpoint?,
        endpointError: String?,
        language: String,
        inputMode: DailyReportGitSummaryInputMode
    ) async {
        llmReadinessMessage = endpointError
        guard let endpoint else {
            if summary == nil { summaryState = .idle }
            return
        }
        guard let snapshot, snapshot.repo != nil, !snapshot.commits.isEmpty else {
            summaryState = .idle
            return
        }
        if let cached = await summaryService.cachedSummary(
            for: snapshot,
            endpoint: endpoint,
            language: language,
            inputMode: inputMode
        ) {
            guard !Task.isCancelled else { return }
            summaryState = .loaded(cached)
        } else if summary?.inputMode != inputMode {
            summaryState = .idle
        }
    }

    func generate(
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        inputMode: DailyReportGitSummaryInputMode,
        forceRefresh: Bool
    ) async {
        guard let snapshot else {
            summaryState = .failed("Load git commits before generating a summary.")
            return
        }
        llmReadinessMessage = nil
        summaryState = .loading
        do {
            let summary = try await summaryService.summarize(
                snapshot: snapshot,
                endpoint: endpoint,
                language: language,
                inputMode: inputMode,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled else { return }
            summaryState = .loaded(summary)
        } catch is CancellationError {
            summaryState = .idle
        } catch {
            summaryState = .failed(error.localizedDescription)
        }
    }

    func failSummary(_ message: String) {
        llmReadinessMessage = message
        summaryState = .failed(message)
    }
}
