import Foundation

enum GitSummaryTarget: Sendable, Hashable {
    case commit(hash: String, subject: String?)
    case workingTree

    var kind: String {
        switch self {
        case .commit: "commit"
        case .workingTree: "worktree"
        }
    }

    var identity: String {
        switch self {
        case .commit(let hash, _): hash
        case .workingTree: "working-tree"
        }
    }

    var displayTitle: String {
        switch self {
        case .commit(let hash, let subject):
            let short = String(hash.prefix(7))
            if let subject, !subject.isEmpty { return "\(short) \(subject)" }
            return short
        case .workingTree:
            return "Working Tree"
        }
    }
}

enum GitSummaryAlgorithm: String, Codable, CaseIterable, Sendable, Hashable {
    case singleShot
    case fileLevel
    case mapReduce
    case mapReduceWithVerifier

    var title: String {
        switch self {
        case .singleShot: "single-shot"
        case .fileLevel: "file-level"
        case .mapReduce: "map-reduce"
        case .mapReduceWithVerifier: "map-reduce + verifier"
        }
    }
}

enum GitSummaryRiskCategory: String, Codable, CaseIterable, Sendable, Hashable {
    case api
    case schema
    case auth
    case build
    case release
    case concurrency
    case dependencies
    case tests
    case docs
    case generated
    case binary
    case rename
    case large

    var title: String {
        switch self {
        case .api: "API"
        case .schema: "Schema"
        case .auth: "Auth"
        case .build: "Build"
        case .release: "Release"
        case .concurrency: "Concurrency"
        case .dependencies: "Dependencies"
        case .tests: "Tests"
        case .docs: "Docs"
        case .generated: "Generated"
        case .binary: "Binary"
        case .rename: "Rename"
        case .large: "Large"
        }
    }
}

struct GitSummaryRiskLabel: Codable, Hashable, Sendable, Identifiable {
    var category: GitSummaryRiskCategory
    var title: String
    var reason: String
    var score: Int
    var paths: [String]

    var id: String { "\(category.rawValue)|\(title)|\(paths.joined(separator: ","))" }
}

struct GitSummaryFileChange: Codable, Hashable, Sendable, Identifiable {
    enum Status: String, Codable, Sendable, Hashable {
        case added
        case modified
        case deleted
        case renamed
        case copied
        case untracked
        case conflicted
        case changed
    }

    var path: String
    var oldPath: String?
    var status: Status
    var insertions: Int
    var deletions: Int
    var isBinary: Bool

    var id: String { "\(status.rawValue)|\(oldPath ?? "")|\(path)" }
    var churn: Int { max(insertions, 0) + max(deletions, 0) }
}

struct GitUntrackedSnippet: Codable, Hashable, Sendable, Identifiable {
    var path: String
    var text: String
    var truncated: Bool

    var id: String { path }
}

struct GitSummarySnapshot: Hashable, Sendable {
    var repo: GitRepo
    var target: GitSummaryTarget
    var targetSubject: String?
    var body: String?
    var diffText: String
    var files: [GitSummaryFileChange]
    var untrackedSnippets: [GitUntrackedSnippet]
    var diffHash: String

    var tokenEstimate: Int {
        GitSummaryTokenEstimator.estimate(diffText + "\n" + untrackedSnippets.map(\.text).joined(separator: "\n"))
    }
}

struct GitSummaryAnalysis: Hashable, Sendable {
    var riskLabels: [GitSummaryRiskLabel]
    var riskScore: Int
    var skippedPaths: [String]

    var hasVerifierTrigger: Bool {
        riskLabels.contains {
            [.api, .schema, .auth, .build, .concurrency].contains($0.category)
        }
    }
}

struct GitDiffChunk: Hashable, Sendable, Identifiable {
    var id: String
    var path: String
    var text: String
    var estimatedTokens: Int
    var riskLabels: [GitSummaryRiskLabel]
}

struct GitSummaryPlan: Hashable, Sendable {
    var algorithm: GitSummaryAlgorithm
    var useVerifier: Bool
    var includeRepoContext: Bool
    var tokenEstimate: Int
    var fileCount: Int
    var riskScore: Int
}

struct GitSummaryUsage: Codable, Hashable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
    var requestCount: Int

    static let zero = GitSummaryUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0, requestCount: 0)

    mutating func add(_ result: LLMGenerationResult) {
        inputTokens += result.inputTokens
        outputTokens += result.outputTokens
        totalTokens += result.totalTokens
        requestCount += 1
    }

    mutating func add(_ other: GitSummaryUsage) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        totalTokens += other.totalTokens
        requestCount += other.requestCount
    }
}

struct GitAISummaryResult: Codable, Hashable, Sendable {
    var summary: String
    var commitTitle: String
    var commitBody: String
    var riskLabels: [GitSummaryRiskLabel]
    var algorithm: GitSummaryAlgorithm
    var modelName: String
    var usage: GitSummaryUsage
    var isCached: Bool
    var generatedAt: Date
    var language: String
    var diffHash: String
    var targetTitle: String
    var verifierNotes: String?

    var commitMessage: String {
        let title = commitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = commitBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return title }
        return "\(title)\n\n\(body)"
    }

    func cachedCopy() -> GitAISummaryResult {
        var copy = self
        copy.isCached = true
        return copy
    }
}

enum GitSummaryLoadState: Sendable, Hashable {
    case idle
    case loading
    case loaded(GitAISummaryResult)
    case failed(String)
}

enum GitSummaryTokenEstimator {
    static func estimate(_ text: String) -> Int {
        max(1, Int((Double(text.count) / 4.0).rounded(.up)))
    }
}
