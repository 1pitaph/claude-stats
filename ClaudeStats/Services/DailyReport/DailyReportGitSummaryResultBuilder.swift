import Foundation

struct DailyReportGitSummaryResultBuilder: Sendable {
    func build(
        from response: LLMGenerationResult,
        snapshot: DailyReportGitDaySnapshot,
        plan: DailyReportGitSummaryPlan,
        language: String,
        contentHash: String
    ) -> DailyReportGitDayLLMSummary {
        var usage = GitLLMUsage.zero
        usage.add(response)
        let parsed = DailyReportGitSummaryResponseParser.parse(response.text)

        return DailyReportGitDayLLMSummary(
            summary: parsed.summary,
            keyChanges: parsed.keyChanges,
            risksOrNotes: parsed.risksOrNotes,
            modelName: response.model,
            usage: usage,
            isCached: false,
            generatedAt: .now,
            language: language,
            inputMode: plan.inputMode,
            algorithm: plan.algorithm,
            commitCount: snapshot.commitCount,
            contentHash: contentHash
        )
    }
}
