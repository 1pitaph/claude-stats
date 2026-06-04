import Foundation

struct DailyReportGitSummaryPromptFactory: Sendable {
    func systemPrompt(language: String) -> String {
        """
        You write concise engineering daily reports in \(language).
        Return only a valid JSON object. Do not wrap it in Markdown.
        Keep claims grounded in the provided git commits and diff excerpts.
        If diff excerpts are truncated, avoid pretending omitted code was inspected.
        """
    }

    func userPrompt(
        snapshot: DailyReportGitDaySnapshot,
        language: String,
        plan: DailyReportGitSummaryPlan,
        excerpts: [DailyReportGitDayDiffExcerpt]
    ) -> String {
        """
        Project: \(snapshot.projectName)
        Project path: \(snapshot.projectPath ?? "-")
        Repository: \(snapshot.repo?.rootPath ?? "-")
        Branch: \(snapshot.repo?.currentBranch ?? "HEAD")
        Day: \(Self.isoDateString(snapshot.day))
        Language: \(language)
        Algorithm: \(plan.algorithm.title)
        Input mode: \(plan.inputMode.promptTitle)
        Author filter: \(snapshot.authorEmail ?? "all authors")

        Commits:
        \(commitList(snapshot.commits))

        \(diffPromptSection(excerpts: excerpts, snapshot: snapshot, plan: plan))

        Summarize this day's git commits for a developer reading a daily report.
        Focus on concrete product/code changes and mention risk only when supported by the commit data.
        Return only JSON with keys:
        - summary: string
        - key_changes: string[]
        - risks_or_notes: string[]

        Return compact JSON like:
        {"summary":"...","key_changes":["..."],"risks_or_notes":[]}
        """
    }

    private func commitList(_ commits: [DailyReportGitDayCommit]) -> String {
        commits.map { commit in
            """
            - \(Self.isoDateTimeString(commit.authorDate)) \(commit.shortHash) \(commit.subject)
              author: \(commit.authorName) <\(commit.authorEmail)>
              stats: \(commit.filesChanged) files, +\(commit.insertions) -\(commit.deletions)
              body: \(commit.body.trimmingCharacters(in: .whitespacesAndNewlines).dailyReportGitSummaryNilIfEmpty ?? "-")
              files:
            \(fileList(commit.files, fallbackFileCount: commit.filesChanged))
            """
        }
        .joined(separator: "\n")
    }

    private func fileList(_ files: [CommitFileChange], fallbackFileCount: Int) -> String {
        guard !files.isEmpty else { return "                - \(fallbackFileCount) changed files" }
        let visible = files.prefix(24).map { file in
            let stat = file.isBinary ? "binary" : "+\(file.insertions) -\(file.deletions)"
            return "                - \(file.path) (\(stat))"
        }
        let overflow = files.count - visible.count
        if overflow > 0 {
            return (visible + ["                - +\(overflow) more files"]).joined(separator: "\n")
        }
        return visible.joined(separator: "\n")
    }

    private func diffPromptSection(
        excerpts: [DailyReportGitDayDiffExcerpt],
        snapshot: DailyReportGitDaySnapshot,
        plan: DailyReportGitSummaryPlan
    ) -> String {
        guard plan.includeDiffExcerpts else { return "Diff excerpts: disabled by user selection." }
        guard !excerpts.isEmpty else { return "Diff excerpts: none available." }

        let byHash = Dictionary(uniqueKeysWithValues: snapshot.commits.map { ($0.hash, $0) })
        let chunks = excerpts.map { excerpt in
            let commit = byHash[excerpt.commitHash]
            let title = [commit?.shortHash, commit?.subject]
                .compactMap { $0?.dailyReportGitSummaryNilIfEmpty }
                .joined(separator: " ")
            return """
            ### \(title.isEmpty ? String(excerpt.commitHash.prefix(7)) : title)
            \(excerpt.truncated ? "[truncated]\n" : "")\(excerpt.text)
            """
        }
        return "Diff excerpts:\n\(chunks.joined(separator: "\n\n"))"
    }

    private static func isoDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    private static func isoDateTimeString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private extension String {
    var dailyReportGitSummaryNilIfEmpty: String? { isEmpty ? nil : self }
}
