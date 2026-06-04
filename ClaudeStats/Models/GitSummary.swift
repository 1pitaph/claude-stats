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
    var keyChanges: [String]
    var risksOrNotes: [String]
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

    init(
        summary: String,
        commitTitle: String,
        commitBody: String,
        keyChanges: [String] = [],
        risksOrNotes: [String] = [],
        riskLabels: [GitSummaryRiskLabel],
        algorithm: GitSummaryAlgorithm,
        modelName: String,
        usage: GitSummaryUsage,
        isCached: Bool,
        generatedAt: Date,
        language: String,
        diffHash: String,
        targetTitle: String,
        verifierNotes: String?
    ) {
        let sections = Self.normalizedSections(
            summary: summary,
            keyChanges: keyChanges,
            risksOrNotes: risksOrNotes
        )
        self.summary = sections.summary
        self.commitTitle = Self.trimmed(commitTitle)
        self.commitBody = Self.trimmed(commitBody)
        self.keyChanges = sections.keyChanges
        self.risksOrNotes = sections.risksOrNotes
        self.riskLabels = riskLabels
        self.algorithm = algorithm
        self.modelName = modelName
        self.usage = usage
        self.isCached = isCached
        self.generatedAt = generatedAt
        self.language = language
        self.diffHash = diffHash
        self.targetTitle = targetTitle
        self.verifierNotes = verifierNotes
    }

    var commitMessage: String {
        let title = commitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = commitBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return title }
        return "\(title)\n\n\(body)"
    }

    var markdown: String {
        var sections = ["# AI Summary"]
        let summary = Self.trimmed(summary)
        if !summary.isEmpty {
            sections.append(summary)
        }

        if !keyChangesMarkdown.isEmpty {
            sections.append(keyChangesMarkdown)
        }
        if !risksOrNotesMarkdown.isEmpty {
            sections.append(risksOrNotesMarkdown)
        }

        let commitMessage = Self.trimmed(commitMessage)
        if !commitMessage.isEmpty {
            sections.append(Self.markdownBodySection(title: "Commit Message", body: commitMessage))
        }

        let verifierNotes = Self.trimmed(verifierNotes ?? "")
        if !verifierNotes.isEmpty {
            sections.append(Self.markdownBodySection(title: "Verifier Notes", body: verifierNotes))
        }

        return sections.joined(separator: "\n\n")
    }

    var keyChangesMarkdown: String {
        Self.markdownListSection(title: "Key Changes", rows: keyChanges)
    }

    var risksOrNotesMarkdown: String {
        Self.markdownListSection(title: "Risks / Notes", rows: risksOrNotes)
    }

    func cachedCopy() -> GitAISummaryResult {
        var copy = self
        copy.isCached = true
        return copy
    }

    private static func markdownBodySection(title: String, body: String) -> String {
        let body = trimmed(body)
        guard !body.isEmpty else { return "" }
        return "## \(title)\n\n\(body)"
    }

    private static func markdownListSection(title: String, rows: [String]) -> String {
        let items = normalizedList(rows)
        guard !items.isEmpty else { return "" }
        return "## \(title)\n\n" + items.map { "- \(markdownListItem($0))" }.joined(separator: "\n")
    }

    private static func markdownListItem(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: "\n  ")
    }

    private static func normalizedSections(
        summary: String,
        keyChanges: [String],
        risksOrNotes: [String]
    ) -> (summary: String, keyChanges: [String], risksOrNotes: [String]) {
        var summaryLines: [String] = []
        var inferredKeyChanges: [String] = []
        var inferredRisksOrNotes: [String] = []

        for line in summary.components(separatedBy: .newlines) {
            let trimmed = trimmed(line)
            guard !trimmed.isEmpty else { continue }
            if let listItem = markdownListItemText(trimmed) {
                if listItem.lowercased().hasPrefix("risk") || listItem.lowercased().hasPrefix("risks") {
                    inferredRisksOrNotes.append(listItem)
                } else {
                    inferredKeyChanges.append(listItem)
                }
            } else {
                summaryLines.append(trimmed)
            }
        }

        return (
            summaryLines.joined(separator: "\n"),
            normalizedList(keyChanges + inferredKeyChanges),
            normalizedList(risksOrNotes + inferredRisksOrNotes)
        )
    }

    private static func normalizedList(_ rows: [String]) -> [String] {
        rows.map { row in
            row.components(separatedBy: .newlines)
                .map(trimmed)
                .filter { !$0.isEmpty }
                .map { markdownListItemText($0) ?? $0 }
                .joined(separator: "\n")
        }
        .filter { !$0.isEmpty }
    }

    private static func markdownListItemText(_ value: String) -> String? {
        let patterns = [
            #"^\s*[-*•]\s+"#,
            #"^\s*\d+[.)]\s+"#
        ]
        for pattern in patterns {
            if let range = value.range(of: pattern, options: .regularExpression) {
                return trimmed(String(value[range.upperBound...]))
            }
        }
        return nil
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case summary
        case commitTitle
        case commitBody
        case keyChanges
        case risksOrNotes
        case riskLabels
        case algorithm
        case modelName
        case usage
        case isCached
        case generatedAt
        case language
        case diffHash
        case targetTitle
        case verifierNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            summary: try container.decode(String.self, forKey: .summary),
            commitTitle: try container.decode(String.self, forKey: .commitTitle),
            commitBody: try container.decode(String.self, forKey: .commitBody),
            keyChanges: try container.decodeIfPresent([String].self, forKey: .keyChanges) ?? [],
            risksOrNotes: try container.decodeIfPresent([String].self, forKey: .risksOrNotes) ?? [],
            riskLabels: try container.decode([GitSummaryRiskLabel].self, forKey: .riskLabels),
            algorithm: try container.decode(GitSummaryAlgorithm.self, forKey: .algorithm),
            modelName: try container.decode(String.self, forKey: .modelName),
            usage: try container.decode(GitSummaryUsage.self, forKey: .usage),
            isCached: try container.decode(Bool.self, forKey: .isCached),
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            language: try container.decode(String.self, forKey: .language),
            diffHash: try container.decode(String.self, forKey: .diffHash),
            targetTitle: try container.decode(String.self, forKey: .targetTitle),
            verifierNotes: try container.decodeIfPresent(String.self, forKey: .verifierNotes)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(summary, forKey: .summary)
        try container.encode(commitTitle, forKey: .commitTitle)
        try container.encode(commitBody, forKey: .commitBody)
        try container.encode(keyChanges, forKey: .keyChanges)
        try container.encode(risksOrNotes, forKey: .risksOrNotes)
        try container.encode(riskLabels, forKey: .riskLabels)
        try container.encode(algorithm, forKey: .algorithm)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(usage, forKey: .usage)
        try container.encode(isCached, forKey: .isCached)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(language, forKey: .language)
        try container.encode(diffHash, forKey: .diffHash)
        try container.encode(targetTitle, forKey: .targetTitle)
        try container.encodeIfPresent(verifierNotes, forKey: .verifierNotes)
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
