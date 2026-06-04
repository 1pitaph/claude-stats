import Foundation

struct GitCommitMessageService: Sendable {
    static let promptVersion = "git-commit-message-prompt-v2"
    static let algorithmVersion = "git-commit-message-algorithm-v1"

    private let snapshotBuilder: GitCommitMessageSnapshotBuilder
    private let classifier: GitChangeClassifier
    private let chunker: GitDiffChunker
    private let planner: GitCommitMessagePlanner
    private let cache: GitCommitMessageCache
    private let pipeline: GitCommitMessageGenerationPipeline

    init(
        snapshotBuilder: GitCommitMessageSnapshotBuilder = GitCommitMessageSnapshotBuilder(),
        classifier: GitChangeClassifier = GitChangeClassifier(),
        chunker: GitDiffChunker = GitDiffChunker(),
        planner: GitCommitMessagePlanner = GitCommitMessagePlanner(),
        cache: GitCommitMessageCache = GitCommitMessageCache(),
        generator: any LLMGenerating = AppLLMClient()
    ) {
        self.snapshotBuilder = snapshotBuilder
        self.classifier = classifier
        self.chunker = chunker
        self.planner = planner
        self.cache = cache
        self.pipeline = GitCommitMessageGenerationPipeline(generator: generator)
    }

    func cachedCommitMessage(
        repo: GitRepo,
        target: GitCommitMessageTarget,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        algorithmPreference: GitCommitMessageAlgorithmPreference = .automatic
    ) async -> GitCommitMessageResult? {
        let runID = UUID().uuidString
        do {
            let context = try await preparedContext(
                repo: repo,
                target: target,
                endpoint: endpoint,
                language: language,
                algorithmPreference: algorithmPreference
            )
            let cached = await cache.read(context.key)?.cachedCopy()
            recordCacheLookup(runID: runID, context: context, endpoint: endpoint, hit: cached != nil, phase: "hydrate")
            return cached
        } catch {
            GitCommitMessageDiagnosticsLog.record("cache.lookup.error", level: "warn", fields: [
                "run_id": runID,
                "phase": "hydrate",
                "target_kind": target.kind,
                "target_id_hash": GitCommitMessageDiagnosticsLog.hash(target.identity),
                "repo_key_hash": GitCommitMessageDiagnosticsLog.hash(repo.cacheKey),
                "mode": endpoint.mode.rawValue,
                "protocol": endpoint.protocol.rawValue,
                "base_host": endpoint.baseURL.host ?? "-",
                "model": endpoint.model,
                "prompt_version": Self.promptVersion,
                "algorithm_version": Self.algorithmVersion,
                "cache_hit": "false",
                "error_type": String(describing: type(of: error)),
                "error": cacheDiagnosticError(error),
            ])
            return nil
        }
    }

    func generateCommitMessage(
        repo: GitRepo,
        target: GitCommitMessageTarget,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        algorithmPreference: GitCommitMessageAlgorithmPreference = .automatic,
        forceRefresh: Bool = false
    ) async throws -> GitCommitMessageResult {
        let runID = UUID().uuidString
        let context = try await preparedContext(
            repo: repo,
            target: target,
            endpoint: endpoint,
            language: language,
            algorithmPreference: algorithmPreference
        )

        if !forceRefresh, let cached = await cache.read(context.key) {
            recordCacheLookup(runID: runID, context: context, endpoint: endpoint, hit: true, phase: "generate")
            return cached.cachedCopy()
        }
        recordCacheLookup(runID: runID, context: context, endpoint: endpoint, hit: false, phase: forceRefresh ? "refresh" : "generate")

        let generated = try await pipeline.generate(
            snapshot: context.snapshot,
            analysis: context.analysis,
            chunks: context.chunks,
            plan: context.plan,
            endpoint: endpoint,
            language: language,
            runID: runID
        )
        await cache.write(generated, for: context.key)
        return generated
    }

    private func preparedContext(
        repo: GitRepo,
        target: GitCommitMessageTarget,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        algorithmPreference: GitCommitMessageAlgorithmPreference
    ) async throws -> GitCommitMessagePreparedContext {
        let snapshot = try await snapshotBuilder.snapshot(for: target, repo: repo)
        var analysis = classifier.classify(snapshot)
        let chunks = chunker.chunks(for: snapshot, analysis: analysis)
        analysis.skippedPaths = chunker.skippedPaths(for: snapshot)
        let plan = planner.plan(snapshot: snapshot, analysis: analysis, chunks: chunks, preference: algorithmPreference)
        let key = cacheKey(
            snapshot: snapshot,
            endpoint: endpoint,
            language: language,
            algorithmPreference: algorithmPreference
        )
        return GitCommitMessagePreparedContext(snapshot: snapshot, analysis: analysis, chunks: chunks, plan: plan, key: key)
    }

    private func cacheKey(
        snapshot: GitCommitMessageSnapshot,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        algorithmPreference: GitCommitMessageAlgorithmPreference
    ) -> GitCommitMessageCacheKey {
        GitCommitMessageCacheKey(
            repoKey: snapshot.repo.cacheKey,
            targetKind: snapshot.target.kind,
            targetID: snapshot.target.identity,
            diffHash: snapshot.diffHash,
            language: language,
            modelID: "\(endpoint.mode.rawValue)|\(endpoint.protocol.rawValue)|\(endpoint.baseURL.absoluteString)|\(endpoint.model)",
            algorithmPreference: algorithmPreference.rawValue,
            promptVersion: Self.promptVersion,
            algorithmVersion: Self.algorithmVersion
        )
    }

    private func recordCacheLookup(
        runID: String,
        context: GitCommitMessagePreparedContext,
        endpoint: AppLLMGenerationEndpoint,
        hit: Bool,
        phase: String
    ) {
        GitCommitMessageDiagnosticsLog.record("cache.lookup", fields: [
            "run_id": runID,
            "phase": phase,
            "algorithm": context.plan.algorithm.title,
            "target_kind": context.snapshot.target.kind,
            "target_id_hash": GitCommitMessageDiagnosticsLog.hash(context.snapshot.target.identity),
            "repo_key_hash": GitCommitMessageDiagnosticsLog.hash(context.snapshot.repo.cacheKey),
            "diff_hash": context.snapshot.diffHash,
            "file_count": "\(context.plan.fileCount)",
            "risk_categories": riskCategories(context.analysis),
            "prompt_version": Self.promptVersion,
            "algorithm_version": Self.algorithmVersion,
            "mode": endpoint.mode.rawValue,
            "protocol": endpoint.protocol.rawValue,
            "base_host": endpoint.baseURL.host ?? "-",
            "model": endpoint.model,
            "cache_hit": hit ? "true" : "false",
        ])
    }

    private func riskCategories(_ analysis: GitCommitMessageAnalysis) -> String {
        let categories = Set(analysis.riskLabels.map { $0.category.rawValue })
        return categories.sorted().joined(separator: ",").gitCommitMessageNilIfEmpty ?? "-"
    }

    private func cacheDiagnosticError(_ error: Error) -> String {
        switch error {
        case GitCommitMessageSnapshotBuilderError.emptyDiff:
            return "There is no diff to generate a commit message for."
        case GitCommitMessageSnapshotBuilderError.gitFailed:
            return "Git command failed."
        case is CancellationError:
            return "Cancelled"
        default:
            return error.localizedDescription.gitCommitMessageTruncated(to: 240)
        }
    }
}

private struct GitCommitMessagePreparedContext: Sendable {
    var snapshot: GitCommitMessageSnapshot
    var analysis: GitCommitMessageAnalysis
    var chunks: [GitDiffChunk]
    var plan: GitCommitMessagePlan
    var key: GitCommitMessageCacheKey
}
