import Foundation

struct DailyReportGitSummaryPipeline: Sendable {
    private let generator: any LLMGenerating
    private let diffProvider: any DailyReportGitDayDiffProviding
    private let prompts: DailyReportGitSummaryPromptFactory
    private let resultBuilder: DailyReportGitSummaryResultBuilder

    init(
        generator: any LLMGenerating,
        diffProvider: any DailyReportGitDayDiffProviding,
        prompts: DailyReportGitSummaryPromptFactory = DailyReportGitSummaryPromptFactory(),
        resultBuilder: DailyReportGitSummaryResultBuilder = DailyReportGitSummaryResultBuilder()
    ) {
        self.generator = generator
        self.diffProvider = diffProvider
        self.prompts = prompts
        self.resultBuilder = resultBuilder
    }

    func generate(
        snapshot: DailyReportGitDaySnapshot,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        plan: DailyReportGitSummaryPlan,
        contentHash: String
    ) async throws -> DailyReportGitDayLLMSummary {
        switch plan.algorithm {
        case .singleShot:
            return try await runSingleShot(
                snapshot: snapshot,
                endpoint: endpoint,
                language: language,
                plan: plan,
                contentHash: contentHash
            )
        }
    }

    private func runSingleShot(
        snapshot: DailyReportGitDaySnapshot,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        plan: DailyReportGitSummaryPlan,
        contentHash: String
    ) async throws -> DailyReportGitDayLLMSummary {
        let excerpts = plan.includeDiffExcerpts
            ? await diffProvider.excerpts(
                for: snapshot,
                perCommitLimit: plan.diffPerCommitLimit,
                totalLimit: plan.diffTotalLimit
            )
            : []
        let request = LLMGenerationRequest(
            systemPrompt: prompts.systemPrompt(language: language),
            userPrompt: prompts.userPrompt(
                snapshot: snapshot,
                language: language,
                plan: plan,
                excerpts: excerpts
            ),
            maxTokens: plan.maxTokens,
            temperature: plan.temperature,
            outputShape: .jsonObject
        )
        let response = try await generator.generate(endpoint: endpoint, request: request)
        return resultBuilder.build(
            from: response,
            snapshot: snapshot,
            plan: plan,
            language: language,
            contentHash: contentHash
        )
    }
}
