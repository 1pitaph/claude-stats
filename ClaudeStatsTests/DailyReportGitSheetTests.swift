import Foundation
import Testing
@testable import ClaudeStats

@Suite("Daily report git sheet")
struct DailyReportGitSheetTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    @Test("Git commits are constrained to the selected day and author")
    func gitCommitsConstrainedToDayAndAuthor() throws {
        let repoURL = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let runner = GitCommandRunner()
        let selectedStart = calendar.startOfDay(for: .now)
        let selectedEnd = calendar.date(byAdding: .day, value: 1, to: selectedStart)!

        try runGit(runner, ["-C", repoURL.path, "init"])
        try commit(runner, repoURL: repoURL, message: "Previous day", date: iso(selectedStart.addingTimeInterval(-1_800)), name: "Test User", email: "test@example.com")
        try commit(runner, repoURL: repoURL, message: "Selected day", date: iso(selectedStart.addingTimeInterval(3_600)), name: "Test User", email: "test@example.com")
        try commit(runner, repoURL: repoURL, message: "Other author", date: iso(selectedStart.addingTimeInterval(7_200)), name: "Other User", email: "other@example.com")
        try commit(runner, repoURL: repoURL, message: "Next day", date: iso(selectedEnd.addingTimeInterval(1_800)), name: "Test User", email: "test@example.com")

        let analyzer = GitAnalyzer(runner: runner)
        let repo = try #require(analyzer.repo(forCwd: repoURL.path))
        let interval = DateInterval(start: selectedStart, end: selectedEnd)
        let commits = analyzer.commits(in: repo, during: interval, authorEmail: "test@example.com")

        #expect(commits.map(\.subject) == ["Selected day"])
    }

    @Test("Git provider returns empty-state snapshots for unavailable projects")
    func gitProviderUnavailableStates() async {
        let day = date(2026, 1, 10)
        let missingPathProject = project(path: nil)
        let missingGit = GitAnalyzer(runner: GitCommandRunner(executablePath: "/tmp/missing-git-\(UUID().uuidString)"))
        let provider = DailyReportGitDayActivityProvider(git: missingGit)

        let missingPath = await provider.snapshot(for: missingPathProject, day: day, calendar: calendar)
        let gitUnavailable = await provider.snapshot(for: project(path: "/tmp"), day: day, calendar: calendar)

        #expect(missingPath.availability == .missingProjectPath)
        #expect(gitUnavailable.availability == .gitUnavailable)
    }

    @Test("Summary service caches, regenerates, and parses JSON")
    func summaryServiceCachesAndRegenerates() async throws {
        let cacheURL = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let llm = CapturingLLM()
        let diffProvider = CapturingDiffProvider()
        let service = DailyReportGitDaySummaryService(
            cache: DailyReportGitDaySummaryCache(rootDirectory: cacheURL),
            generator: llm,
            diffProvider: diffProvider
        )
        let snapshot = Self.snapshot(day: date(2026, 1, 10))
        let endpoint = Self.endpoint()

        let first = try await service.summarize(
            snapshot: snapshot,
            endpoint: endpoint,
            language: "English",
            inputMode: .diffAware
        )
        let callsAfterFirst = await llm.callCount()
        let firstRequest = try #require(await llm.lastRequest())
        let firstPrompt = firstRequest.userPrompt
        let cached = try await service.summarize(
            snapshot: snapshot,
            endpoint: endpoint,
            language: "English",
            inputMode: .diffAware
        )
        let callsAfterCached = await llm.callCount()
        _ = try await service.summarize(
            snapshot: snapshot,
            endpoint: endpoint,
            language: "English",
            inputMode: .diffAware,
            forceRefresh: true
        )

        #expect(first.summary == "Implemented the daily report git sheet.")
        #expect(first.keyChanges == ["Added the timeline", "Added LLM summary caching"])
        #expect(first.algorithm == .singleShot)
        #expect(firstRequest.outputShape == .jsonObject)
        #expect(firstPrompt.contains(#"{"summary":"...","key_changes":["..."],"risks_or_notes":[]}"#))
        #expect(!firstPrompt.contains("commit_title"))
        #expect(!firstPrompt.contains("commit_body"))
        #expect(firstPrompt.contains("DIFF-SENTINEL"))
        #expect(await diffProvider.callCount() == 2)
        #expect(cached.isCached)
        #expect(callsAfterCached == callsAfterFirst)
        #expect(await llm.callCount() == callsAfterFirst + 1)
    }

    @Test("Metadata summary mode excludes diff excerpts")
    func metadataModeExcludesDiffs() async throws {
        let cacheURL = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let llm = CapturingLLM()
        let diffProvider = CapturingDiffProvider()
        let service = DailyReportGitDaySummaryService(
            cache: DailyReportGitDaySummaryCache(rootDirectory: cacheURL),
            generator: llm,
            diffProvider: diffProvider
        )

        _ = try await service.summarize(
            snapshot: Self.snapshot(day: date(2026, 1, 10)),
            endpoint: Self.endpoint(),
            language: "English",
            inputMode: .metadataOnly
        )
        let prompt = try #require(await llm.lastRequest()?.userPrompt)

        #expect(!prompt.contains("DIFF-SENTINEL"))
        #expect(await diffProvider.callCount() == 0)
    }

    @Test("Summary parser extracts three-part JSON from common LLM wrappers")
    func summaryParserExtractsWrappedJSON() {
        let pure = DailyReportGitSummaryResponseParser.parse("""
        {"summary":"Implemented daily report summaries.","key_changes":["Split prompts"],"risks_or_notes":[]}
        """)
        let fenced = DailyReportGitSummaryResponseParser.parse("""
        ```json
        {"summary":"Trimmed fenced JSON.","key_changes":["Parsed fences"],"risks_or_notes":["Check cache version"]}
        ```
        """)
        let wrapped = DailyReportGitSummaryResponseParser.parse("""
        Here is the summary:
        {"summary":"Extracted embedded JSON.","key_changes":["Kept the schema"],"risks_or_notes":[]}
        Done.
        """)

        #expect(pure.jsonParseOK)
        #expect(pure.summary == "Implemented daily report summaries.")
        #expect(pure.keyChanges == ["Split prompts"])
        #expect(pure.risksOrNotes == [])
        #expect(fenced.jsonParseOK)
        #expect(fenced.summary == "Trimmed fenced JSON.")
        #expect(fenced.risksOrNotes == ["Check cache version"])
        #expect(wrapped.jsonParseOK)
        #expect(wrapped.summary == "Extracted embedded JSON.")
        #expect(wrapped.keyChanges == ["Kept the schema"])
    }

    @Test("Summary planner maps input modes to explicit single-shot plans")
    func summaryPlannerMapsInputModes() {
        let planner = DailyReportGitSummaryPlanner()
        let diffAware = planner.plan(inputMode: .diffAware)
        let metadataOnly = planner.plan(inputMode: .metadataOnly)

        #expect(diffAware.algorithm == .singleShot)
        #expect(diffAware.inputMode == .diffAware)
        #expect(diffAware.includeDiffExcerpts)
        #expect(diffAware.diffPerCommitLimit == 8_000)
        #expect(diffAware.diffTotalLimit == 30_000)
        #expect(diffAware.maxTokens == 1_200)
        #expect(diffAware.temperature == 0.2)
        #expect(metadataOnly.algorithm == .singleShot)
        #expect(metadataOnly.inputMode == .metadataOnly)
        #expect(!metadataOnly.includeDiffExcerpts)
    }

    @Test("LLM summary Markdown preserves document and section structure")
    func summaryMarkdownStructure() {
        let summary = DailyReportGitDayLLMSummary(
            summary: "Implemented the daily report git sheet.",
            keyChanges: ["Added the timeline", "Added LLM summary caching"],
            risksOrNotes: ["Verify local LLM setup.", "Multi-line\nnote keeps indentation."],
            modelName: "test-model",
            usage: .zero,
            isCached: false,
            generatedAt: date(2026, 1, 10, 18, 38),
            language: "English",
            inputMode: .diffAware,
            commitCount: 2,
            contentHash: "hash"
        )

        #expect(summary.markdown == """
        # LLM Summary

        Implemented the daily report git sheet.

        ## Key Changes

        - Added the timeline
        - Added LLM summary caching

        ## Risks / Notes

        - Verify local LLM setup.
        - Multi-line
          note keeps indentation.
        """)
        #expect(summary.summaryMarkdown == """
        ## Summary

        Implemented the daily report git sheet.
        """)
        #expect(summary.keyChangesMarkdown == """
        ## Key Changes

        - Added the timeline
        - Added LLM summary caching
        """)
        #expect(summary.risksOrNotesMarkdown == """
        ## Risks / Notes

        - Verify local LLM setup.
        - Multi-line
          note keeps indentation.
        """)
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

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func project(path: String?) -> DailyReportProjectDaySummary {
        DailyReportProjectDaySummary(
            id: path ?? "codex:unknown",
            displayName: "app",
            path: path,
            providers: [.codex],
            activeDuration: 3_600,
            tokens: 1_000,
            sessionCount: 1,
            gitCommitCount: 1,
            latestActivity: nil
        )
    }

    private func runGit(_ runner: GitCommandRunner, _ arguments: [String]) throws {
        let result = runner.run(arguments, timeout: 15)
        if !result.succeeded {
            throw GitSheetTestError.gitFailed(result.stderr)
        }
    }

    private func commit(
        _ runner: GitCommandRunner,
        repoURL: URL,
        message: String,
        date: String,
        name: String,
        email: String
    ) throws {
        try runGit(runner, [
            "-C", repoURL.path,
            "-c", "user.name=\(name)",
            "-c", "user.email=\(email)",
            "commit",
            "--allow-empty",
            "-m", message,
            "--date", date,
            "--author", "\(name) <\(email)>",
        ])
    }

    private static func snapshot(day: Date) -> DailyReportGitDaySnapshot {
        let repo = GitRepo(rootPath: "/tmp/repo", gitDirPath: "/tmp/repo/.git", commonDirPath: "/tmp/repo/.git", currentBranch: "main")
        let commit = DailyReportGitDayCommit(
            hash: "abcdef1234567890",
            abbreviatedHash: "abcdef1",
            authorName: "Test User",
            authorEmail: "test@example.com",
            authorDate: day.addingTimeInterval(3_600),
            commitDate: day.addingTimeInterval(3_600),
            subject: "Add daily report sheet",
            body: "Adds commit timeline and LLM summary.",
            files: [
                CommitFileChange(path: "ClaudeStats/Views/MainWindow/DailyReport/DailyReportProjectGitDetailSheet.swift", insertions: 120, deletions: 4),
            ],
            insertions: 120,
            deletions: 4,
            filesChanged: 1,
            repoID: repo.id
        )
        return DailyReportGitDaySnapshot(
            projectID: "/tmp/repo",
            projectName: "repo",
            projectPath: "/tmp/repo",
            day: day,
            interval: DateInterval(start: day, duration: 86_400),
            repo: repo,
            commits: [commit],
            authorEmail: "test@example.com",
            availability: .loaded
        )
    }

    private static func endpoint(model: String = "test-model") -> AppLLMGenerationEndpoint {
        AppLLMGenerationEndpoint(
            mode: .online,
            protocol: .openAIResponses,
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "test-key",
            model: model,
            displayName: "Test"
        )
    }
}

private actor CapturingLLM: LLMGenerating {
    private var calls = 0
    private var requests: [LLMGenerationRequest] = []

    func generate(endpoint: AppLLMGenerationEndpoint, request: LLMGenerationRequest) async throws -> LLMGenerationResult {
        calls += 1
        requests.append(request)
        let body = """
        {"summary":"Implemented the daily report git sheet.","key_changes":["Added the timeline","Added LLM summary caching"],"risks_or_notes":["Verify local LLM setup."]}
        """
        return LLMGenerationResult(
            text: body,
            model: endpoint.model,
            inputTokens: 20,
            outputTokens: 12,
            totalTokens: 32
        )
    }

    func callCount() -> Int { calls }
    func lastRequest() -> LLMGenerationRequest? { requests.last }
}

private actor CapturingDiffProvider: DailyReportGitDayDiffProviding {
    private var calls = 0

    func excerpts(
        for snapshot: DailyReportGitDaySnapshot,
        perCommitLimit: Int,
        totalLimit: Int
    ) async -> [DailyReportGitDayDiffExcerpt] {
        calls += 1
        return [
            DailyReportGitDayDiffExcerpt(
                commitHash: snapshot.commits.first?.hash ?? "",
                text: "DIFF-SENTINEL",
                truncated: false
            ),
        ]
    }

    func callCount() -> Int { calls }
}

private enum GitSheetTestError: Error {
    case gitFailed(String)
}
