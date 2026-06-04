import Foundation

enum GitCommitMessageTarget: Sendable, Hashable {
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

enum GitCommitMessageAlgorithm: String, Codable, CaseIterable, Sendable, Hashable {
    case singleShot
    case fileLevel
    case mapReduce

    var title: String {
        switch self {
        case .singleShot: "single-shot"
        case .fileLevel: "file-level"
        case .mapReduce: "map-reduce"
        }
    }
}

enum GitCommitMessageAlgorithmPreference: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case automatic
    case singleShot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .singleShot: "Single-shot"
        }
    }

    var subtitle: String {
        switch self {
        case .automatic: "Choose a flow based on diff size and risk"
        case .singleShot: "Always use one LLM call"
        }
    }
}

enum GitCommitMessageRiskCategory: String, Codable, CaseIterable, Sendable, Hashable {
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

struct GitCommitMessageRiskLabel: Codable, Hashable, Sendable, Identifiable {
    var category: GitCommitMessageRiskCategory
    var title: String
    var reason: String
    var score: Int
    var paths: [String]

    var id: String { "\(category.rawValue)|\(title)|\(paths.joined(separator: ","))" }
}

struct GitCommitMessageFileChange: Codable, Hashable, Sendable, Identifiable {
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

struct GitCommitMessageSnapshot: Hashable, Sendable {
    var repo: GitRepo
    var target: GitCommitMessageTarget
    var targetSubject: String?
    var body: String?
    var diffText: String
    var files: [GitCommitMessageFileChange]
    var untrackedSnippets: [GitUntrackedSnippet]
    var diffHash: String

    var tokenEstimate: Int {
        GitCommitMessageTokenEstimator.estimate(diffText + "\n" + untrackedSnippets.map(\.text).joined(separator: "\n"))
    }
}

struct GitCommitMessageAnalysis: Hashable, Sendable {
    var riskLabels: [GitCommitMessageRiskLabel]
    var riskScore: Int
    var skippedPaths: [String]

    var hasRiskAgentTrigger: Bool {
        riskLabels.contains {
            [.api, .schema, .auth].contains($0.category)
        }
    }

    var hasStrongAuthOrSchemaRisk: Bool {
        riskLabels.contains {
            [.auth, .schema].contains($0.category) && $0.score >= 7
        }
    }
}

struct GitDiffChunk: Hashable, Sendable, Identifiable {
    var id: String
    var path: String
    var text: String
    var estimatedTokens: Int
    var riskLabels: [GitCommitMessageRiskLabel]
}

struct GitCommitMessagePlan: Hashable, Sendable {
    var algorithm: GitCommitMessageAlgorithm
    var useRiskAgent: Bool
    var includeRepoContext: Bool
    var tokenEstimate: Int
    var fileCount: Int
    var riskScore: Int
}

struct GitLLMUsage: Codable, Hashable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
    var requestCount: Int

    static let zero = GitLLMUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0, requestCount: 0)

    mutating func add(_ result: LLMGenerationResult) {
        inputTokens += result.inputTokens
        outputTokens += result.outputTokens
        totalTokens += result.totalTokens
        requestCount += 1
    }

    mutating func add(_ other: GitLLMUsage) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        totalTokens += other.totalTokens
        requestCount += other.requestCount
    }
}

struct GitCommitMessageResult: Codable, Hashable, Sendable {
    var commitTitle: String
    var commitBody: String
    var algorithm: GitCommitMessageAlgorithm
    var modelName: String
    var usage: GitLLMUsage
    var isCached: Bool
    var generatedAt: Date
    var language: String
    var diffHash: String
    var targetTitle: String

    init(
        commitTitle: String,
        commitBody: String,
        algorithm: GitCommitMessageAlgorithm,
        modelName: String,
        usage: GitLLMUsage,
        isCached: Bool,
        generatedAt: Date,
        language: String,
        diffHash: String,
        targetTitle: String
    ) {
        self.commitTitle = Self.trimmed(commitTitle)
        self.commitBody = Self.trimmed(commitBody)
        self.algorithm = algorithm
        self.modelName = modelName
        self.usage = usage
        self.isCached = isCached
        self.generatedAt = generatedAt
        self.language = language
        self.diffHash = diffHash
        self.targetTitle = targetTitle
    }

    var commitMessage: String {
        let title = commitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = commitBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return body }
        if body.isEmpty { return title }
        return "\(title)\n\n\(body)"
    }

    var copyText: String {
        commitMessage
    }

    func cachedCopy() -> GitCommitMessageResult {
        var copy = self
        copy.isCached = true
        return copy
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case commitTitle
        case commitBody
        case algorithm
        case modelName
        case usage
        case isCached
        case generatedAt
        case language
        case diffHash
        case targetTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            commitTitle: try container.decode(String.self, forKey: .commitTitle),
            commitBody: try container.decode(String.self, forKey: .commitBody),
            algorithm: try container.decode(GitCommitMessageAlgorithm.self, forKey: .algorithm),
            modelName: try container.decode(String.self, forKey: .modelName),
            usage: try container.decode(GitLLMUsage.self, forKey: .usage),
            isCached: try container.decode(Bool.self, forKey: .isCached),
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            language: try container.decode(String.self, forKey: .language),
            diffHash: try container.decode(String.self, forKey: .diffHash),
            targetTitle: try container.decode(String.self, forKey: .targetTitle)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(commitTitle, forKey: .commitTitle)
        try container.encode(commitBody, forKey: .commitBody)
        try container.encode(algorithm, forKey: .algorithm)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(usage, forKey: .usage)
        try container.encode(isCached, forKey: .isCached)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(language, forKey: .language)
        try container.encode(diffHash, forKey: .diffHash)
        try container.encode(targetTitle, forKey: .targetTitle)
    }
}

enum GitCommitMessageLoadState: Sendable, Hashable {
    case idle
    case loading
    case loaded(GitCommitMessageResult)
    case failed(String)
}

enum GitCommitMessageTokenEstimator {
    static func estimate(_ text: String) -> Int {
        max(1, Int((Double(text.count) / 4.0).rounded(.up)))
    }
}
