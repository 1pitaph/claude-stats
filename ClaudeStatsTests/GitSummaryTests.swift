import Foundation
import Testing
@testable import ClaudeStats

@Suite("Git LLM summary")
struct GitSummaryTests {
    @Test("Classifier detects high-risk API schema auth build and concurrency changes")
    func classifierDetectsHighRiskLabels() {
        let diff = """
        diff --git a/Sources/API/AuthController.swift b/Sources/API/AuthController.swift
        --- a/Sources/API/AuthController.swift
        +++ b/Sources/API/AuthController.swift
        @@ -1,3 +1,5 @@
        -public func login(password: String) async -> Token
        +public func login(password: String, otp: String?) async throws -> Token
        +Task { await refreshJWTBearerToken() }
        diff --git a/project.yml b/project.yml
        @@ -1 +1 @@
        +SWIFT_STRICT_CONCURRENCY: complete
        diff --git a/db/migrations/001.sql b/db/migrations/001.sql
        @@ -1 +1 @@
        +ALTER TABLE users ADD COLUMN otp TEXT;
        """
        let snapshot = snapshot(
            diff: diff,
            files: [
                GitSummaryFileChange(path: "Sources/API/AuthController.swift", oldPath: nil, status: .modified, insertions: 2, deletions: 1, isBinary: false),
                GitSummaryFileChange(path: "project.yml", oldPath: nil, status: .modified, insertions: 1, deletions: 0, isBinary: false),
                GitSummaryFileChange(path: "db/migrations/001.sql", oldPath: nil, status: .added, insertions: 1, deletions: 0, isBinary: false),
            ]
        )

        let analysis = GitChangeClassifier().classify(snapshot)
        let categories = Set(analysis.riskLabels.map(\.category))
        let chunks = GitDiffChunker().chunks(for: snapshot, analysis: analysis)
        let plan = GitSummaryPlanner().plan(snapshot: snapshot, analysis: analysis, chunks: chunks)

        #expect(categories.isSuperset(of: [.api, .schema, .auth, .build, .concurrency]))
        #expect(plan.algorithm == .mapReduceWithVerifier)
        #expect(plan.useVerifier)
    }

    @Test("Planner follows token and risk thresholds")
    func plannerThresholds() {
        let planner = GitSummaryPlanner()
        let clean = GitSummaryAnalysis(riskLabels: [], riskScore: 0, skippedPaths: [])
        let small = snapshot(diff: String(repeating: "a", count: 1_000), files: [file("Sources/App.swift")])
        let medium = snapshot(diff: String(repeating: "a", count: 36_000), files: [file("Sources/App.swift")])
        let huge = snapshot(diff: String(repeating: "a", count: 180_000), files: [file("Sources/App.swift")])
        let chunks = [GitDiffChunk(id: "1", path: "Sources/App.swift", text: "x", estimatedTokens: 1, riskLabels: [])]

        #expect(planner.plan(snapshot: small, analysis: clean, chunks: chunks).algorithm == .singleShot)
        #expect(planner.plan(snapshot: medium, analysis: clean, chunks: chunks).algorithm == .fileLevel)
        #expect(planner.plan(snapshot: huge, analysis: clean, chunks: chunks).algorithm == .mapReduce)

        let risk = GitSummaryRiskLabel(category: .dependencies, title: "Dependencies", reason: "Manifest changed.", score: 8, paths: ["Package.swift"])
        let risky = GitSummaryAnalysis(riskLabels: [risk], riskScore: 8, skippedPaths: [])
        #expect(planner.plan(snapshot: small, analysis: risky, chunks: chunks).algorithm == .mapReduce)
    }

    @Test("Chunker skips binary lock generated and large resource files")
    func chunkerSkipsNoisyFiles() {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        @@ -1 +1 @@
        -let old = 1
        +let new = 2
        diff --git a/package-lock.json b/package-lock.json
        @@ -1 +1 @@
        -{}
        +{"lock": true}
        diff --git a/Generated/API.generated.swift b/Generated/API.generated.swift
        @@ -1 +1 @@
        -old
        +new
        diff --git a/Assets/logo.png b/Assets/logo.png
        Binary files a/Assets/logo.png and b/Assets/logo.png differ
        """
        let snapshot = snapshot(
            diff: diff,
            files: [
                file("Sources/App.swift"),
                file("package-lock.json"),
                file("Generated/API.generated.swift"),
                GitSummaryFileChange(path: "Assets/logo.png", oldPath: nil, status: .modified, insertions: -1, deletions: -1, isBinary: true),
            ]
        )
        let analysis = GitChangeClassifier().classify(snapshot)
        let chunker = GitDiffChunker()
        let chunks = chunker.chunks(for: snapshot, analysis: analysis)

        #expect(chunks.map(\.path) == ["Sources/App.swift"])
        #expect(Set(chunker.skippedPaths(for: snapshot)) == Set(["Assets/logo.png", "Generated/API.generated.swift", "package-lock.json"]))
    }

    @Test("Summary service cache hit does not call LLM again and language changes miss")
    func cacheHitAvoidsLLM() async throws {
        let repoURL = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let cacheURL = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let runner = GitCommandRunner()

        try runGit(runner, ["-C", repoURL.path, "init"])
        try runGit(runner, ["-C", repoURL.path, "config", "user.email", "test@example.com"])
        try runGit(runner, ["-C", repoURL.path, "config", "user.name", "Test User"])
        try "one\n".write(to: repoURL.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        try runGit(runner, ["-C", repoURL.path, "add", "hello.txt"])
        try runGit(runner, ["-C", repoURL.path, "commit", "-m", "Initial"])
        try "two\n".write(to: repoURL.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)

        let llm = CountingLLM()
        let service = GitSummaryService(
            cache: GitSummaryCache(rootDirectory: cacheURL),
            generator: llm
        )
        let endpoint = AppLLMGenerationEndpoint(
            mode: .online,
            protocol: .openAIResponses,
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "test-key",
            model: "test-model",
            displayName: "Test"
        )
        let repo = GitRepo(rootPath: repoURL.path)

        _ = try await service.summarize(repo: repo, target: .workingTree, endpoint: endpoint, language: "English")
        let callsAfterFirst = await llm.callCount()
        let firstRequest = try #require(await llm.lastRequest())
        let cached = try await service.summarize(repo: repo, target: .workingTree, endpoint: endpoint, language: "English")
        let callsAfterSecond = await llm.callCount()
        _ = try await service.summarize(repo: repo, target: .workingTree, endpoint: endpoint, language: "Simplified Chinese")

        #expect(firstRequest.outputShape == .jsonObject)
        #expect(firstRequest.userPrompt.contains(#"{"summary":"...","key_changes":["..."],"risks_or_notes":[],"commit_title":"...","commit_body":"...","verifier_notes":""}"#))
        #expect(cached.isCached)
        #expect(callsAfterSecond == callsAfterFirst)
        #expect(await llm.callCount() == callsAfterFirst + 1)
    }

    @Test("Summary result Markdown preserves copied sections")
    func summaryResultMarkdown() {
        let result = GitAISummaryResult(
            summary: "Stabilized the Gantt layout during sidebar changes.",
            commitTitle: "Fix Gantt sidebar layout jitter",
            commitBody: "Adds a hysteresis band and stabilizes the scroll stack.",
            keyChanges: [
                "Added a hysteresis band.",
                "Stabilized compact layout state."
            ],
            risksOrNotes: [
                "Verified with focused tests."
            ],
            riskLabels: [],
            algorithm: .singleShot,
            modelName: "test-model",
            usage: .zero,
            isCached: false,
            generatedAt: Date(timeIntervalSince1970: 0),
            language: "English",
            diffHash: "hash",
            targetTitle: "Working Tree",
            verifierNotes: "No material issues found."
        )

        #expect(result.markdown == """
        # AI Summary

        Stabilized the Gantt layout during sidebar changes.

        ## Key Changes

        - Added a hysteresis band.
        - Stabilized compact layout state.

        ## Risks / Notes

        - Verified with focused tests.

        ## Commit Message

        Fix Gantt sidebar layout jitter

        Adds a hysteresis band and stabilizes the scroll stack.

        ## Verifier Notes

        No material issues found.
        """)
    }

    @Test("Summary result decoding upgrades legacy Markdown list text")
    func summaryResultDecodingUpgradesLegacyMarkdownListText() throws {
        let json = """
        {
          "summary": "Updated the Git summary UI.\\n- Added header copy button.\\n- Rendered key changes as native rows.\\n- Risk: cached summaries may need regeneration.",
          "commitTitle": "Update Git summary UI",
          "commitBody": "Aligns the Git summary panel with the daily report.",
          "riskLabels": [],
          "algorithm": "singleShot",
          "modelName": "test-model",
          "usage": {"inputTokens": 1, "outputTokens": 2, "totalTokens": 3, "requestCount": 1},
          "isCached": true,
          "generatedAt": "1970-01-01T00:00:00Z",
          "language": "English",
          "diffHash": "hash",
          "targetTitle": "Working Tree"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(GitAISummaryResult.self, from: Data(json.utf8))

        #expect(result.summary == "Updated the Git summary UI.")
        #expect(result.keyChanges == [
            "Added header copy button.",
            "Rendered key changes as native rows."
        ])
        #expect(result.risksOrNotes == ["Risk: cached summaries may need regeneration."])
    }

    private func snapshot(diff: String, files: [GitSummaryFileChange]) -> GitSummarySnapshot {
        GitSummarySnapshot(
            repo: GitRepo(rootPath: "/tmp/repo"),
            target: .workingTree,
            targetSubject: nil,
            body: nil,
            diffText: diff,
            files: files,
            untrackedSnippets: [],
            diffHash: "\(diff.count)"
        )
    }

    private func file(_ path: String) -> GitSummaryFileChange {
        GitSummaryFileChange(path: path, oldPath: nil, status: .modified, insertions: 1, deletions: 1, isBinary: false)
    }

    private func runGit(_ runner: GitCommandRunner, _ arguments: [String]) throws {
        let result = runner.run(arguments, timeout: 15)
        if !result.succeeded {
            throw GitTestError.gitFailed(result.stderr)
        }
    }
}

private actor CountingLLM: LLMGenerating {
    private var calls = 0
    private var requests: [LLMGenerationRequest] = []

    func generate(endpoint: AppLLMGenerationEndpoint, request: LLMGenerationRequest) async throws -> LLMGenerationResult {
        calls += 1
        requests.append(request)
        return LLMGenerationResult(
            text: #"{"summary":"Updated hello text.","commit_title":"Update hello text","commit_body":"Updates hello.txt.","verifier_notes":""}"#,
            model: endpoint.model,
            inputTokens: 10,
            outputTokens: 8,
            totalTokens: 18
        )
    }

    func callCount() -> Int {
        calls
    }

    func lastRequest() -> LLMGenerationRequest? {
        requests.last
    }
}

private enum GitTestError: Error {
    case gitFailed(String)
}
