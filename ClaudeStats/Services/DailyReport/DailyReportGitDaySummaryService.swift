import CryptoKit
import Foundation

protocol DailyReportGitDayDiffProviding: Sendable {
    func excerpts(
        for snapshot: DailyReportGitDaySnapshot,
        perCommitLimit: Int,
        totalLimit: Int
    ) async -> [DailyReportGitDayDiffExcerpt]
}

struct DailyReportGitDayDiffProvider: DailyReportGitDayDiffProviding {
    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    func excerpts(
        for snapshot: DailyReportGitDaySnapshot,
        perCommitLimit: Int = 8_000,
        totalLimit: Int = 30_000
    ) async -> [DailyReportGitDayDiffExcerpt] {
        guard let repo = snapshot.repo, !snapshot.commits.isEmpty else { return [] }
        let runner = runner
        let commits = snapshot.commits

        return await Task.detached(priority: .utility) {
            var remaining = max(0, totalLimit)
            var out: [DailyReportGitDayDiffExcerpt] = []

            for commit in commits where remaining > 0 {
                let result = runner.run([
                    "-C", repo.rootPath,
                    "show",
                    "--format=",
                    "--no-color",
                    "--find-renames",
                    "--find-copies",
                    commit.hash,
                ], timeout: 30)
                guard result.succeeded else { continue }
                let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }

                let limit = min(perCommitLimit, remaining)
                let limited = String(raw.prefix(limit))
                remaining -= limited.count
                out.append(DailyReportGitDayDiffExcerpt(
                    commitHash: commit.hash,
                    text: limited,
                    truncated: limited.count < raw.count
                ))
            }

            return out
        }.value
    }
}

enum DailyReportGitDaySummaryServiceError: Error, LocalizedError, Sendable {
    case missingRepository
    case noCommits

    var errorDescription: String? {
        switch self {
        case .missingRepository:
            "This project is not connected to a git repository."
        case .noCommits:
            "There are no git commits to summarize for this day."
        }
    }
}

struct DailyReportGitDaySummaryService: Sendable {
    static let promptVersion = "daily-report-git-day-summary-prompt-v2"

    private let cache: DailyReportGitDaySummaryCache
    private let generator: any LLMGenerating
    private let diffProvider: any DailyReportGitDayDiffProviding

    init(
        cache: DailyReportGitDaySummaryCache = DailyReportGitDaySummaryCache(),
        generator: any LLMGenerating = AppLLMClient(),
        diffProvider: any DailyReportGitDayDiffProviding = DailyReportGitDayDiffProvider()
    ) {
        self.cache = cache
        self.generator = generator
        self.diffProvider = diffProvider
    }

    func cachedSummary(
        for snapshot: DailyReportGitDaySnapshot,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        inputMode: DailyReportGitSummaryInputMode
    ) async -> DailyReportGitDayLLMSummary? {
        guard snapshot.repo != nil, !snapshot.commits.isEmpty else { return nil }
        let contentHash = Self.contentHash(for: snapshot)
        let key = cacheKey(
            snapshot: snapshot,
            endpoint: endpoint,
            language: language,
            inputMode: inputMode,
            contentHash: contentHash
        )
        return await cache.read(key)?.cachedCopy()
    }

    func summarize(
        snapshot: DailyReportGitDaySnapshot,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        inputMode: DailyReportGitSummaryInputMode,
        forceRefresh: Bool = false
    ) async throws -> DailyReportGitDayLLMSummary {
        guard snapshot.repo != nil else { throw DailyReportGitDaySummaryServiceError.missingRepository }
        guard !snapshot.commits.isEmpty else { throw DailyReportGitDaySummaryServiceError.noCommits }

        let contentHash = Self.contentHash(for: snapshot)
        let key = cacheKey(
            snapshot: snapshot,
            endpoint: endpoint,
            language: language,
            inputMode: inputMode,
            contentHash: contentHash
        )

        if !forceRefresh, let cached = await cache.read(key) {
            return cached.cachedCopy()
        }

        let prompt = await prompt(for: snapshot, language: language, inputMode: inputMode)
        let response = try await generator.generate(
            endpoint: endpoint,
            request: LLMGenerationRequest(
                systemPrompt: systemPrompt(language: language),
                userPrompt: prompt,
                maxTokens: 1_200,
                temperature: 0.2,
                outputShape: .jsonObject
            )
        )

        var usage = GitLLMUsage.zero
        usage.add(response)
        let parsed = Self.parseResponse(response.text)
        let summary = DailyReportGitDayLLMSummary(
            summary: parsed.summary,
            keyChanges: parsed.keyChanges,
            risksOrNotes: parsed.risksOrNotes,
            modelName: response.model,
            usage: usage,
            isCached: false,
            generatedAt: .now,
            language: language,
            inputMode: inputMode,
            commitCount: snapshot.commitCount,
            contentHash: contentHash
        )
        await cache.write(summary, for: key)
        return summary
    }

    static func contentHash(for snapshot: DailyReportGitDaySnapshot) -> String {
        let lines = snapshot.commits.flatMap { commit -> [String] in
            let header = [
                commit.hash,
                "\(commit.authorDate.timeIntervalSince1970)",
                commit.authorName,
                commit.authorEmail,
                commit.subject,
                commit.body,
                "\(commit.filesChanged)",
                "\(commit.insertions)",
                "\(commit.deletions)",
            ].joined(separator: "\u{1f}")
            let files = commit.files.map {
                "\($0.path)\u{1f}\($0.insertions)\u{1f}\($0.deletions)\u{1f}\($0.isBinary)"
            }
            return [header] + files
        }
        let digest = SHA256.hash(data: Data(lines.joined(separator: "\u{1e}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func cacheKey(
        snapshot: DailyReportGitDaySnapshot,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        inputMode: DailyReportGitSummaryInputMode,
        contentHash: String
    ) -> DailyReportGitDaySummaryCacheKey {
        DailyReportGitDaySummaryCacheKey(
            repoKey: snapshot.repo?.cacheKey ?? snapshot.projectPath ?? snapshot.projectID,
            projectID: snapshot.projectID,
            day: snapshot.day,
            contentHash: contentHash,
            inputMode: inputMode,
            language: language,
            endpointIdentity: Self.endpointIdentity(endpoint),
            promptVersion: Self.promptVersion
        )
    }

    private static func endpointIdentity(_ endpoint: AppLLMGenerationEndpoint) -> String {
        [
            endpoint.mode.rawValue,
            endpoint.protocol.rawValue,
            endpoint.baseURL.absoluteString,
            endpoint.model,
        ].joined(separator: "\u{1f}")
    }

    private func prompt(
        for snapshot: DailyReportGitDaySnapshot,
        language: String,
        inputMode: DailyReportGitSummaryInputMode
    ) async -> String {
        let diffSection: String
        switch inputMode {
        case .metadataOnly:
            diffSection = "Diff excerpts: disabled by user selection."
        case .diffAware:
            let excerpts = await diffProvider.excerpts(for: snapshot, perCommitLimit: 8_000, totalLimit: 30_000)
            diffSection = diffPromptSection(excerpts: excerpts, snapshot: snapshot)
        }

        return """
        Project: \(snapshot.projectName)
        Project path: \(snapshot.projectPath ?? "-")
        Repository: \(snapshot.repo?.rootPath ?? "-")
        Branch: \(snapshot.repo?.currentBranch ?? "HEAD")
        Day: \(Self.isoDateString(snapshot.day))
        Language: \(language)
        Input mode: \(inputMode.promptTitle)
        Author filter: \(snapshot.authorEmail ?? "all authors")

        Commits:
        \(commitList(snapshot.commits))

        \(diffSection)

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

    private func systemPrompt(language: String) -> String {
        """
        You write concise engineering daily reports in \(language).
        Return only a valid JSON object. Do not wrap it in Markdown.
        Keep claims grounded in the provided git commits and diff excerpts.
        If diff excerpts are truncated, avoid pretending omitted code was inspected.
        """
    }

    private func commitList(_ commits: [DailyReportGitDayCommit]) -> String {
        commits.map { commit in
            """
            - \(Self.isoDateTimeString(commit.authorDate)) \(commit.shortHash) \(commit.subject)
              author: \(commit.authorName) <\(commit.authorEmail)>
              stats: \(commit.filesChanged) files, +\(commit.insertions) -\(commit.deletions)
              body: \(commit.body.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "-")
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
        snapshot: DailyReportGitDaySnapshot
    ) -> String {
        guard !excerpts.isEmpty else { return "Diff excerpts: none available." }
        let byHash = Dictionary(uniqueKeysWithValues: snapshot.commits.map { ($0.hash, $0) })
        let chunks = excerpts.map { excerpt in
            let commit = byHash[excerpt.commitHash]
            let title = [commit?.shortHash, commit?.subject]
                .compactMap { $0?.nilIfEmpty }
                .joined(separator: " ")
            return """
            ### \(title.isEmpty ? String(excerpt.commitHash.prefix(7)) : title)
            \(excerpt.truncated ? "[truncated]\n" : "")\(excerpt.text)
            """
        }
        return "Diff excerpts:\n\(chunks.joined(separator: "\n\n"))"
    }

    private static func parseResponse(_ raw: String) -> (summary: String, keyChanges: [String], risksOrNotes: [String]) {
        struct Response: Decodable {
            var summary: String?
            var keyChanges: [String]?
            var risksOrNotes: [String]?

            enum CodingKeys: String, CodingKey {
                case summary
                case keyChanges = "key_changes"
                case risksOrNotes = "risks_or_notes"
            }
        }

        let trimmed = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Response.self, from: data) {
            let summary = decoded.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? trimmed
            return (
                summary,
                (decoded.keyChanges ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                (decoded.risksOrNotes ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            )
        }
        return (trimmed.isEmpty ? raw : trimmed, [], [])
    }

    private static func stripCodeFence(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: "\n")
        if !lines.isEmpty { lines.removeFirst() }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
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
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
