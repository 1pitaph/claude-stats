import CryptoKit
import Foundation

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
    static let promptVersion = "daily-report-git-day-summary-prompt-v3"
    static let algorithmVersion = "daily-report-git-summary-algorithm-v1"

    private let cache: DailyReportGitDaySummaryCache
    private let planner: DailyReportGitSummaryPlanner
    private let pipeline: DailyReportGitSummaryPipeline

    init(
        cache: DailyReportGitDaySummaryCache = DailyReportGitDaySummaryCache(),
        generator: any LLMGenerating = AppLLMClient(),
        diffProvider: any DailyReportGitDayDiffProviding = DailyReportGitDayDiffProvider(),
        planner: DailyReportGitSummaryPlanner = DailyReportGitSummaryPlanner()
    ) {
        self.cache = cache
        self.planner = planner
        self.pipeline = DailyReportGitSummaryPipeline(generator: generator, diffProvider: diffProvider)
    }

    func cachedSummary(
        for snapshot: DailyReportGitDaySnapshot,
        endpoint: AppLLMGenerationEndpoint,
        language: String,
        inputMode: DailyReportGitSummaryInputMode
    ) async -> DailyReportGitDayLLMSummary? {
        guard snapshot.repo != nil, !snapshot.commits.isEmpty else { return nil }
        let contentHash = Self.contentHash(for: snapshot)
        let plan = planner.plan(inputMode: inputMode)
        let key = cacheKey(
            snapshot: snapshot,
            endpoint: endpoint,
            language: language,
            plan: plan,
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
        let plan = planner.plan(inputMode: inputMode)
        let key = cacheKey(
            snapshot: snapshot,
            endpoint: endpoint,
            language: language,
            plan: plan,
            contentHash: contentHash
        )

        if !forceRefresh, let cached = await cache.read(key) {
            return cached.cachedCopy()
        }

        let summary = try await pipeline.generate(
            snapshot: snapshot,
            endpoint: endpoint,
            language: language,
            plan: plan,
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
        plan: DailyReportGitSummaryPlan,
        contentHash: String
    ) -> DailyReportGitDaySummaryCacheKey {
        DailyReportGitDaySummaryCacheKey(
            repoKey: snapshot.repo?.cacheKey ?? snapshot.projectPath ?? snapshot.projectID,
            projectID: snapshot.projectID,
            day: snapshot.day,
            contentHash: contentHash,
            inputMode: plan.inputMode,
            algorithm: plan.algorithm,
            language: language,
            endpointIdentity: Self.endpointIdentity(endpoint),
            promptVersion: Self.promptVersion,
            algorithmVersion: Self.algorithmVersion
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
}
