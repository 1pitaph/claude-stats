import Foundation
import Testing
@testable import ClaudeStats

@Suite("Git commit message generation")
struct GitCommitMessageTests {
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
                GitCommitMessageFileChange(path: "Sources/API/AuthController.swift", oldPath: nil, status: .modified, insertions: 2, deletions: 1, isBinary: false),
                GitCommitMessageFileChange(path: "project.yml", oldPath: nil, status: .modified, insertions: 1, deletions: 0, isBinary: false),
                GitCommitMessageFileChange(path: "db/migrations/001.sql", oldPath: nil, status: .added, insertions: 1, deletions: 0, isBinary: false),
            ]
        )

        let analysis = GitChangeClassifier().classify(snapshot)
        let categories = Set(analysis.riskLabels.map(\.category))
        let chunks = GitDiffChunker().chunks(for: snapshot, analysis: analysis)
        let plan = GitCommitMessagePlanner().plan(snapshot: snapshot, analysis: analysis, chunks: chunks)

        #expect(categories.isSuperset(of: [.api, .schema, .auth, .build, .concurrency]))
        #expect(plan.algorithm == .mapReduce)
        #expect(plan.includeRepoContext)
    }

    @Test("Planner follows token and risk thresholds")
    func plannerThresholds() {
        let planner = GitCommitMessagePlanner()
        let clean = GitCommitMessageAnalysis(riskLabels: [], riskScore: 0, skippedPaths: [])
        let small = snapshot(diff: String(repeating: "a", count: 1_000), files: [file("Sources/App.swift")])
        let medium = snapshot(diff: String(repeating: "a", count: 30_000), files: [file("Sources/App.swift")])
        let large = snapshot(diff: String(repeating: "a", count: 80_000), files: [file("Sources/App.swift")])
        let huge = snapshot(diff: String(repeating: "a", count: 150_000), files: [file("Sources/App.swift")])
        let chunks = [GitDiffChunk(id: "1", path: "Sources/App.swift", text: "x", estimatedTokens: 1, riskLabels: [])]

        #expect(planner.plan(snapshot: small, analysis: clean, chunks: chunks).algorithm == .singleShot)
        #expect(planner.plan(snapshot: medium, analysis: clean, chunks: chunks).algorithm == .fileLevel)
        #expect(planner.plan(snapshot: large, analysis: clean, chunks: chunks).algorithm == .mapReduce)
        let hugePlan = planner.plan(snapshot: huge, analysis: clean, chunks: chunks)
        #expect(hugePlan.algorithm == .mapReduce)
        #expect(hugePlan.includeRepoContext)

        let risk = GitCommitMessageRiskLabel(category: .dependencies, title: "Dependencies", reason: "Manifest changed.", score: 8, paths: ["Package.swift"])
        let risky = GitCommitMessageAnalysis(riskLabels: [risk], riskScore: 8, skippedPaths: [])
        #expect(planner.plan(snapshot: small, analysis: risky, chunks: chunks).algorithm == .fileLevel)

        let severe = GitCommitMessageAnalysis(
            riskLabels: [GitCommitMessageRiskLabel(category: .build, title: "Build", reason: "CI changed.", score: 16, paths: [".github/workflows/ci.yml"])],
            riskScore: 16,
            skippedPaths: []
        )
        let severePlan = planner.plan(snapshot: small, analysis: severe, chunks: chunks)
        #expect(severePlan.algorithm == .mapReduce)
        #expect(severePlan.includeRepoContext)

        let forced = planner.plan(snapshot: huge, analysis: severe, chunks: chunks, preference: .singleShot)
        #expect(forced.algorithm == .singleShot)
        #expect(!forced.useRiskAgent)
    }

    @Test("Planner separates risk agent and repo context escalation")
    func plannerSeparatesRiskAgentAndRepoContext() {
        let planner = GitCommitMessagePlanner()
        let apiRisk = GitCommitMessageRiskLabel(category: .api, title: "API", reason: "Client changed.", score: 8, paths: ["Sources/API/Client.swift"])
        let apiAnalysis = GitCommitMessageAnalysis(riskLabels: [apiRisk], riskScore: 8, skippedPaths: [])
        let files = (0..<16).map { file("Sources/API/File\($0).swift") }
        let manyFileSnapshot = snapshot(diff: String(repeating: "a", count: 4_000), files: files)
        let chunks = [
            GitDiffChunk(id: "1", path: "Sources/API/File1.swift", text: "x", estimatedTokens: 1, riskLabels: [apiRisk]),
            GitDiffChunk(id: "2", path: "Sources/API/File2.swift", text: "x", estimatedTokens: 1, riskLabels: [apiRisk]),
        ]

        let plan = planner.plan(snapshot: manyFileSnapshot, analysis: apiAnalysis, chunks: chunks)
        #expect(plan.algorithm == .mapReduce)
        #expect(plan.useRiskAgent)
        #expect(!plan.includeRepoContext)

        let authRisk = GitCommitMessageRiskLabel(category: .auth, title: "Auth", reason: "Token flow changed.", score: 7, paths: ["Sources/Auth.swift"])
        let authAnalysis = GitCommitMessageAnalysis(riskLabels: [authRisk], riskScore: 7, skippedPaths: [])
        let tinyAuth = planner.plan(snapshot: snapshot(diff: "token", files: [file("Sources/Auth.swift")]), analysis: authAnalysis, chunks: chunks)
        let nonSmallAuth = planner.plan(snapshot: snapshot(diff: String(repeating: "a", count: 30_000), files: [file("Sources/Auth.swift")]), analysis: authAnalysis, chunks: chunks)
        #expect(tinyAuth.algorithm == .singleShot)
        #expect(!tinyAuth.includeRepoContext)
        #expect(nonSmallAuth.algorithm == .mapReduce)
        #expect(nonSmallAuth.includeRepoContext)
    }

    @Test("Classifier avoids noisy weak-risk escalation")
    func classifierAvoidsNoisyWeakRiskEscalation() {
        let diff = """
        diff --git a/scripts/cleanup.sh b/scripts/cleanup.sh
        @@ -1 +1 @@
        +echo cleanup
        diff --git a/Tests/PublicAPITests.swift b/Tests/PublicAPITests.swift
        @@ -1 +1 @@
        +public func helper() async { await doThing() }
        """
        let snapshot = snapshot(
            diff: diff,
            files: [
                file("scripts/cleanup.sh"),
                file("Tests/PublicAPITests.swift"),
            ]
        )

        let analysis = GitChangeClassifier().classify(snapshot)
        let categories = Set(analysis.riskLabels.map(\.category))
        let plan = GitCommitMessagePlanner().plan(
            snapshot: snapshot,
            analysis: analysis,
            chunks: GitDiffChunker().chunks(for: snapshot, analysis: analysis)
        )

        #expect(!categories.contains(.build))
        #expect(!categories.contains(.api))
        #expect(categories.contains(.tests))
        #expect(plan.algorithm == .singleShot)
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
                GitCommitMessageFileChange(path: "Assets/logo.png", oldPath: nil, status: .modified, insertions: -1, deletions: -1, isBinary: true),
            ]
        )
        let analysis = GitChangeClassifier().classify(snapshot)
        let chunker = GitDiffChunker()
        let chunks = chunker.chunks(for: snapshot, analysis: analysis)

        #expect(chunks.map(\.path) == ["Sources/App.swift"])
        #expect(Set(chunker.skippedPaths(for: snapshot)) == Set(["Assets/logo.png", "Generated/API.generated.swift", "package-lock.json"]))
    }

    @Test("Commit message service cache hit does not call LLM again and language changes miss")
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
        let service = GitCommitMessageService(
            cache: GitCommitMessageCache(rootDirectory: cacheURL),
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

        _ = try await service.generateCommitMessage(repo: repo, target: .workingTree, endpoint: endpoint, language: "English")
        let callsAfterFirst = await llm.callCount()
        let firstRequest = try #require(await llm.lastRequest())
        let cached = try await service.generateCommitMessage(repo: repo, target: .workingTree, endpoint: endpoint, language: "English")
        let callsAfterSecond = await llm.callCount()
        _ = try await service.generateCommitMessage(repo: repo, target: .workingTree, endpoint: endpoint, language: "Simplified Chinese")

        #expect(firstRequest.outputShape == .jsonObject)
        #expect(firstRequest.userPrompt.contains(#"{"commit_title":"...","commit_body":"..."}"#))
        #expect(!firstRequest.userPrompt.contains("risks_or_notes"))
        #expect(!firstRequest.userPrompt.contains("verifier_notes"))
        #expect(cached.isCached)
        #expect(callsAfterSecond == callsAfterFirst)
        #expect(await llm.callCount() == callsAfterFirst + 1)
    }

    @Test("Cache-only hydrate misses and hits without calling LLM")
    func cacheOnlyHydrateDoesNotCallLLM() async throws {
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
        let service = GitCommitMessageService(cache: GitCommitMessageCache(rootDirectory: cacheURL), generator: llm)
        let endpoint = testEndpoint(model: "test-model")
        let repo = GitRepo(rootPath: repoURL.path)

        let miss = await service.cachedCommitMessage(repo: repo, target: .workingTree, endpoint: endpoint, language: "English")
        #expect(miss == nil)
        #expect(await llm.callCount() == 0)

        _ = try await service.generateCommitMessage(repo: repo, target: .workingTree, endpoint: endpoint, language: "English")
        let callsAfterGenerate = await llm.callCount()
        let hit = await service.cachedCommitMessage(repo: repo, target: .workingTree, endpoint: endpoint, language: "English")
        let changedModelMiss = await service.cachedCommitMessage(repo: repo, target: .workingTree, endpoint: testEndpoint(model: "other-model"), language: "English")
        let changedAlgorithmMiss = await service.cachedCommitMessage(
            repo: repo,
            target: .workingTree,
            endpoint: endpoint,
            language: "English",
            algorithmPreference: .singleShot
        )

        #expect(hit?.isCached == true)
        #expect(changedModelMiss == nil)
        #expect(changedAlgorithmMiss == nil)
        #expect(await llm.callCount() == callsAfterGenerate)
    }

    @Test("Pipeline returns reduced commit message without verifier text call")
    func pipelineReturnsReducedCommitMessageWithoutVerifier() async throws {
        let risk = GitCommitMessageRiskLabel(category: .auth, title: "Auth", reason: "Token flow changed.", score: 16, paths: ["Sources/Auth.swift"])
        let analysis = GitCommitMessageAnalysis(riskLabels: [risk], riskScore: 16, skippedPaths: [])
        let snapshot = snapshot(
            diff: """
            diff --git a/Sources/Auth.swift b/Sources/Auth.swift
            @@ -1 +1 @@
            -old
            +new
            """,
            files: [file("Sources/Auth.swift")]
        )
        let chunk = GitDiffChunk(
            id: "file|Sources/Auth.swift",
            path: "Sources/Auth.swift",
            text: snapshot.diffText,
            estimatedTokens: 20,
            riskLabels: [risk]
        )
        let plan = GitCommitMessagePlan(
            algorithm: .mapReduce,
            useRiskAgent: false,
            includeRepoContext: false,
            tokenEstimate: 20,
            fileCount: 1,
            riskScore: 16
        )
        let pipeline = GitCommitMessageGenerationPipeline(generator: TextCallFailingLLM())

        let result = try await pipeline.generate(
            snapshot: snapshot,
            analysis: analysis,
            chunks: [chunk],
            plan: plan,
            endpoint: testEndpoint(model: "test-model"),
            language: "English",
            runID: "test-run"
        )

        #expect(result.commitTitle == "Update auth")
        #expect(result.commitBody == "Updates auth.")
        #expect(result.usage.requestCount == 2)
    }

    @MainActor
    @Test("View model hydrates cached result and keeps idle on corrupt cache")
    func viewModelHydratesCachedSummary() async throws {
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
        let cache = GitCommitMessageCache(rootDirectory: cacheURL)
        let service = GitCommitMessageService(cache: cache, generator: llm)
        let endpoint = testEndpoint(model: "test-model")
        let repo = GitRepo(rootPath: repoURL.path)

        _ = try await service.generateCommitMessage(repo: repo, target: .workingTree, endpoint: endpoint, language: "English")
        let callsAfterGenerate = await llm.callCount()

        let hydrated = GitCommitMessageViewModel(service: service)
        await hydrated.loadCached(repo: repo, target: .workingTree, endpoint: endpoint, language: "English")
        guard case .loaded(let result) = hydrated.state else {
            Issue.record("Expected cached commit message to hydrate")
            return
        }
        #expect(result.isCached)
        #expect(await llm.callCount() == callsAfterGenerate)

        let corruptFiles = try FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)
        for file in corruptFiles {
            try Data("not-json".utf8).write(to: file)
        }
        let corrupt = GitCommitMessageViewModel(service: service)
        await corrupt.loadCached(repo: repo, target: .workingTree, endpoint: endpoint, language: "English")
        guard case .idle = corrupt.state else {
            Issue.record("Expected corrupt cache to leave view model idle")
            return
        }
    }

    @Test("Git commit message diagnostics log lines are redacted flat JSONL")
    func gitCommitMessageDiagnosticsLogLinesAreRedactedFlatJSONL() throws {
        let data = GitCommitMessageDiagnosticsLog.recordData(
            "llm.call.start",
            date: Date(timeIntervalSince1970: 1_801_234_567.89),
            fields: [
                "phase": "reduce",
                "algorithm": "map-reduce",
                "max_tokens": "1600",
                "input_tokens": "100",
                "output_tokens": "50",
                "total_tokens": "150",
                "prompt_hash": "prompt-hash",
                "prompt_chars": "1234",
                "response_hash": "response-hash",
                "api_key": "secret-key",
                "prompt": "full prompt body",
                "diff": "full diff body",
                "response": "full response body",
            ]
        )
        let line = try #require(String(data: data, encoding: .utf8))
        let readableData = GitCommitMessageDiagnosticsLog.readableRecordData(
            "llm.call.start",
            date: Date(timeIntervalSince1970: 1_801_234_567.89),
            fields: [
                "phase": "reduce",
                "algorithm": "map-reduce",
                "prompt_hash": "prompt-hash",
            ]
        )
        let readable = try #require(String(data: readableData, encoding: .utf8))

        #expect(line.contains(#""phase": "reduce""#))
        #expect(line.contains(#""algorithm": "map-reduce""#))
        #expect(line.contains(#""max_tokens": "1600""#))
        #expect(line.contains(#""input_tokens": "100""#))
        #expect(line.contains(#""output_tokens": "50""#))
        #expect(line.contains(#""total_tokens": "150""#))
        #expect(line.contains(#""prompt_hash": "prompt-hash""#))
        #expect(!line.contains("secret-key"))
        #expect(!line.contains("full prompt body"))
        #expect(!line.contains("full diff body"))
        #expect(!line.contains("full response body"))
        #expect(!line.contains(#""api_key""#))
        #expect(!line.contains(#""prompt":"#))
        #expect(!line.contains(#""diff":"#))
        #expect(!line.contains(#""response":"#))
        _ = try JSONSerialization.jsonObject(with: data)
        #expect(readable.contains("INFO llm.call.start"))
        #expect(readable.contains("phase        reduce"))
    }

    @Test("Git commit message diagnostics writes readable logs and prunes expired files")
    func gitCommitMessageDiagnosticsWritesAndPrunes() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldJSON = root.appendingPathComponent("git-commit-message-2026-05-01-00.jsonl")
        let oldLog = root.appendingPathComponent("git-commit-message-2026-05-01-00.log")
        try Data("old\n".utf8).write(to: oldJSON)
        try Data("old\n".utf8).write(to: oldLog)

        GitCommitMessageDiagnosticsLog.record(
            "llm.call.start",
            directories: [root],
            date: Date(timeIntervalSince1970: 1_801_234_567.89),
            fields: ["phase": "single-shot"]
        )
        let currentJSON = GitCommitMessageDiagnosticsLog.currentLogURL(directory: root, date: Date(timeIntervalSince1970: 1_801_234_567.89))
        let currentLog = GitCommitMessageDiagnosticsLog.currentReadableLogURL(directory: root, date: Date(timeIntervalSince1970: 1_801_234_567.89))

        #expect(FileManager.default.fileExists(atPath: currentJSON.path))
        #expect(FileManager.default.fileExists(atPath: currentLog.path))
        #expect(!FileManager.default.fileExists(atPath: oldJSON.path))
        #expect(!FileManager.default.fileExists(atPath: oldLog.path))
    }

    @Test("Git commit message diagnostics exposes a code root log mirror")
    func gitCommitMessageDiagnosticsCodeRootMirror() throws {
        let mirror = try #require(GitCommitMessageDiagnosticsLog.sourceRootLogDirectory(
            filePath: "/tmp/claude-stats/ClaudeStats/Services/Git/CommitMessage/GitCommitMessageDiagnosticsLog.swift"
        ))
        let testMirror = try #require(GitCommitMessageDiagnosticsLog.sourceRootLogDirectory(
            filePath: "/tmp/claude-stats/ClaudeStatsTests/GitCommitMessageTests.swift"
        ))

        #expect(mirror.path == "/tmp/claude-stats/logs/git-commit-message")
        #expect(testMirror.path == "/tmp/claude-stats/logs/git-commit-message")
    }

    @Test("Commit message result copy text preserves only commit message")
    func commitMessageResultCopyText() {
        let result = GitCommitMessageResult(
            commitTitle: "Fix Gantt sidebar layout jitter",
            commitBody: "Adds a hysteresis band and stabilizes the scroll stack.",
            algorithm: .singleShot,
            modelName: "test-model",
            usage: .zero,
            isCached: false,
            generatedAt: Date(timeIntervalSince1970: 0),
            language: "English",
            diffHash: "hash",
            targetTitle: "Working Tree"
        )

        #expect(result.copyText == """
        Fix Gantt sidebar layout jitter

        Adds a hysteresis band and stabilizes the scroll stack.
        """)
    }

    @Test("Commit message result decoding reads only commit message fields")
    func commitMessageResultDecoding() throws {
        let json = """
        {
          "commitTitle": "Update Git commit message UI",
          "commitBody": "Aligns the Git commit message panel with the daily report.",
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
        let result = try decoder.decode(GitCommitMessageResult.self, from: Data(json.utf8))

        #expect(result.commitMessage == """
        Update Git commit message UI

        Aligns the Git commit message panel with the daily report.
        """)
    }

    @Test("App LLM settings decode missing Git commit message algorithm as automatic")
    func appLLMSettingsDefaultGitCommitMessageAlgorithmPreference() throws {
        let json = """
        {
          "mode": "online",
          "selectedProviderID": "openai-responses",
          "providers": [],
          "updatedAt": "2026-06-04T00:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let settings = try decoder.decode(AppLLMSettings.self, from: Data(json.utf8))

        #expect(settings.gitCommitMessageAlgorithmPreference == .automatic)
        #expect(settings.providers.contains { $0.id == AppLLMProvider.openAIResponsesID })
    }

    @Test("App LLM settings migrate old Git summary algorithm key")
    func appLLMSettingsMigratesOldGitSummaryAlgorithmPreference() throws {
        let json = """
        {
          "mode": "online",
          "selectedProviderID": "openai-responses",
          "providers": [],
          "gitSummaryAlgorithmPreference": "singleShot",
          "updatedAt": "2026-06-04T00:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let settings = try decoder.decode(AppLLMSettings.self, from: Data(json.utf8))

        #expect(settings.gitCommitMessageAlgorithmPreference == .singleShot)
    }

    private func snapshot(diff: String, files: [GitCommitMessageFileChange]) -> GitCommitMessageSnapshot {
        GitCommitMessageSnapshot(
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

    private func file(_ path: String) -> GitCommitMessageFileChange {
        GitCommitMessageFileChange(path: path, oldPath: nil, status: .modified, insertions: 1, deletions: 1, isBinary: false)
    }

    private func runGit(_ runner: GitCommandRunner, _ arguments: [String]) throws {
        let result = runner.run(arguments, timeout: 15)
        if !result.succeeded {
            throw GitTestError.gitFailed(result.stderr)
        }
    }

    private func testEndpoint(model: String) -> AppLLMGenerationEndpoint {
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

private actor CountingLLM: LLMGenerating {
    private var calls = 0
    private var requests: [LLMGenerationRequest] = []

    func generate(endpoint: AppLLMGenerationEndpoint, request: LLMGenerationRequest) async throws -> LLMGenerationResult {
        calls += 1
        requests.append(request)
        return LLMGenerationResult(
            text: #"{"commit_title":"Update hello text","commit_body":"Updates hello.txt."}"#,
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

private struct TextCallFailingLLM: LLMGenerating {
    func generate(endpoint: AppLLMGenerationEndpoint, request: LLMGenerationRequest) async throws -> LLMGenerationResult {
        if request.outputShape == .text {
            throw LLMClientError.emptyOutput
        }
        let text: String
        if request.userPrompt.contains("Diff chunk:") {
            text = #"{"id":"file|Sources/Auth.swift","path":"Sources/Auth.swift","summary":"Chunk summary.","key_changes":["Updated auth."],"risks":[],"public_interfaces":[],"questions":[]}"#
        } else {
            text = #"{"commit_title":"Update auth","commit_body":"Updates auth."}"#
        }
        return LLMGenerationResult(
            text: text,
            model: endpoint.model,
            inputTokens: 10,
            outputTokens: 8,
            totalTokens: 18
        )
    }
}

private enum GitTestError: Error {
    case gitFailed(String)
}
