import Foundation

struct GitCommitMessagePlanner: Sendable {
    func plan(
        snapshot: GitCommitMessageSnapshot,
        analysis: GitCommitMessageAnalysis,
        chunks: [GitDiffChunk],
        preference: GitCommitMessageAlgorithmPreference = .automatic
    ) -> GitCommitMessagePlan {
        let tokenEstimate = max(snapshot.tokenEstimate, chunks.reduce(0) { $0 + $1.estimatedTokens })
        let fileCount = snapshot.files.count
        let algorithm: GitCommitMessageAlgorithm
        let useRiskAgent: Bool
        let includeRepoContext: Bool
        let needsDeepContext = shouldIncludeRepoContext(tokenEstimate: tokenEstimate, fileCount: fileCount, analysis: analysis)

        if preference == .singleShot {
            algorithm = .singleShot
            useRiskAgent = false
            includeRepoContext = false
        } else if needsDeepContext || tokenEstimate > 18_000 || fileCount > 15 || analysis.riskScore >= 13 {
            algorithm = .mapReduce
            useRiskAgent = shouldUseRiskAgent(tokenEstimate: tokenEstimate, fileCount: fileCount, analysis: analysis, chunks: chunks)
            includeRepoContext = needsDeepContext
        } else if tokenEstimate >= 6_000 || analysis.riskScore >= 8 {
            algorithm = .fileLevel
            useRiskAgent = false
            includeRepoContext = false
        } else {
            algorithm = .singleShot
            useRiskAgent = false
            includeRepoContext = false
        }

        return GitCommitMessagePlan(
            algorithm: algorithm,
            useRiskAgent: useRiskAgent,
            includeRepoContext: includeRepoContext,
            tokenEstimate: tokenEstimate,
            fileCount: fileCount,
            riskScore: analysis.riskScore
        )
    }

    private func shouldIncludeRepoContext(tokenEstimate: Int, fileCount: Int, analysis: GitCommitMessageAnalysis) -> Bool {
        if tokenEstimate > 35_000 || fileCount > 25 || analysis.riskScore >= 16 {
            return true
        }
        let isSmallDiff = tokenEstimate < 6_000 && fileCount <= 5
        return analysis.hasStrongAuthOrSchemaRisk && !isSmallDiff
    }

    private func shouldUseRiskAgent(
        tokenEstimate: Int,
        fileCount: Int,
        analysis: GitCommitMessageAnalysis,
        chunks: [GitDiffChunk]
    ) -> Bool {
        guard analysis.hasRiskAgentTrigger, chunks.count > 1 else { return false }
        return tokenEstimate >= 6_000 || fileCount > 5 || analysis.riskScore >= 8
    }
}
