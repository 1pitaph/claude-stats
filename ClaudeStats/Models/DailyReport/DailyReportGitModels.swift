import Foundation

enum DailyReportGitSummaryInputMode: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case diffAware
    case metadataOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .diffAware: "Diff-aware"
        case .metadataOnly: "Metadata"
        }
    }

    var promptTitle: String {
        switch self {
        case .diffAware: "commit metadata plus capped diff excerpts"
        case .metadataOnly: "commit metadata only"
        }
    }
}

enum DailyReportGitSummaryAlgorithm: String, Codable, CaseIterable, Sendable, Hashable {
    case singleShot

    var title: String {
        switch self {
        case .singleShot: "single-shot"
        }
    }
}

struct DailyReportGitSummaryPlan: Hashable, Sendable {
    var algorithm: DailyReportGitSummaryAlgorithm
    var inputMode: DailyReportGitSummaryInputMode
    var includeDiffExcerpts: Bool
    var diffPerCommitLimit: Int
    var diffTotalLimit: Int
    var maxTokens: Int
    var temperature: Double
}

struct DailyReportProjectGitSheetSelection: Identifiable, Hashable, Sendable {
    let project: DailyReportProjectDaySummary
    let day: Date

    var id: String { "\(project.id)|\(day.timeIntervalSinceReferenceDate)" }
}

struct DailyReportGitDayCommit: Identifiable, Hashable, Sendable {
    let hash: String
    let abbreviatedHash: String
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let commitDate: Date
    let subject: String
    let body: String
    let files: [CommitFileChange]
    let insertions: Int
    let deletions: Int
    let filesChanged: Int
    let repoID: String

    var id: String { "\(repoID)|\(hash)" }
    var shortHash: String { abbreviatedHash.isEmpty ? String(hash.prefix(7)) : abbreviatedHash }
    var churn: Int { max(insertions, 0) + max(deletions, 0) }
}

struct DailyReportGitDaySnapshot: Hashable, Sendable {
    enum Availability: Hashable, Sendable {
        case loaded
        case missingProjectPath
        case gitUnavailable
        case notRepository
    }

    let projectID: String
    let projectName: String
    let projectPath: String?
    let day: Date
    let interval: DateInterval
    let repo: GitRepo?
    let commits: [DailyReportGitDayCommit]
    let authorEmail: String?
    let availability: Availability

    var commitCount: Int { commits.count }

    var statusMessage: String? {
        switch availability {
        case .loaded:
            nil
        case .missingProjectPath:
            "This AI project does not have a local working directory, so git commits cannot be resolved."
        case .gitUnavailable:
            "Git is unavailable on this Mac."
        case .notRepository:
            "This project path is not inside a git repository."
        }
    }

    static func unavailable(
        project: DailyReportProjectDaySummary,
        day: Date,
        interval: DateInterval,
        availability: Availability
    ) -> DailyReportGitDaySnapshot {
        DailyReportGitDaySnapshot(
            projectID: project.id,
            projectName: project.displayName,
            projectPath: project.path,
            day: day,
            interval: interval,
            repo: nil,
            commits: [],
            authorEmail: nil,
            availability: availability
        )
    }
}

struct DailyReportGitDayDiffExcerpt: Hashable, Sendable {
    let commitHash: String
    let text: String
    let truncated: Bool
}

struct DailyReportGitDayLLMSummary: Codable, Hashable, Sendable, Identifiable {
    var summary: String
    var keyChanges: [String]
    var risksOrNotes: [String]
    var modelName: String
    var usage: GitLLMUsage
    var isCached: Bool
    var generatedAt: Date
    var language: String
    var inputMode: DailyReportGitSummaryInputMode
    var algorithm: DailyReportGitSummaryAlgorithm
    var commitCount: Int
    var contentHash: String

    init(
        summary: String,
        keyChanges: [String],
        risksOrNotes: [String],
        modelName: String,
        usage: GitLLMUsage,
        isCached: Bool,
        generatedAt: Date,
        language: String,
        inputMode: DailyReportGitSummaryInputMode,
        algorithm: DailyReportGitSummaryAlgorithm = .singleShot,
        commitCount: Int,
        contentHash: String
    ) {
        self.summary = Self.trimmed(summary)
        self.keyChanges = keyChanges.map(Self.trimmed).filter { !$0.isEmpty }
        self.risksOrNotes = risksOrNotes.map(Self.trimmed).filter { !$0.isEmpty }
        self.modelName = modelName
        self.usage = usage
        self.isCached = isCached
        self.generatedAt = generatedAt
        self.language = language
        self.inputMode = inputMode
        self.algorithm = algorithm
        self.commitCount = commitCount
        self.contentHash = contentHash
    }

    var id: String { "\(contentHash)|\(inputMode.rawValue)|\(algorithm.rawValue)|\(generatedAt.timeIntervalSinceReferenceDate)" }

    func cachedCopy() -> DailyReportGitDayLLMSummary {
        var copy = self
        copy.isCached = true
        return copy
    }

    var markdown: String {
        var sections = ["# LLM Summary"]
        let body = Self.trimmed(summary)
        if !body.isEmpty {
            sections.append(body)
        }
        if !keyChangesMarkdown.isEmpty {
            sections.append(keyChangesMarkdown)
        }
        if !risksOrNotesMarkdown.isEmpty {
            sections.append(risksOrNotesMarkdown)
        }
        return sections.joined(separator: "\n\n")
    }

    var summaryMarkdown: String {
        Self.markdownBodySection(title: "Summary", body: summary)
    }

    var keyChangesMarkdown: String {
        Self.markdownListSection(title: "Key Changes", rows: keyChanges)
    }

    var risksOrNotesMarkdown: String {
        Self.markdownListSection(title: "Risks / Notes", rows: risksOrNotes)
    }

    private static func markdownBodySection(title: String, body: String) -> String {
        let body = trimmed(body)
        guard !body.isEmpty else { return "" }
        return "## \(title)\n\n\(body)"
    }

    private static func markdownListSection(title: String, rows: [String]) -> String {
        let items = rows.map(trimmed).filter { !$0.isEmpty }
        guard !items.isEmpty else { return "" }
        return "## \(title)\n\n" + items.map { "- \(markdownListItem($0))" }.joined(separator: "\n")
    }

    private static func markdownListItem(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: "\n  ")
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case summary
        case keyChanges
        case risksOrNotes
        case modelName
        case usage
        case isCached
        case generatedAt
        case language
        case inputMode
        case algorithm
        case commitCount
        case contentHash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            summary: try container.decode(String.self, forKey: .summary),
            keyChanges: try container.decode([String].self, forKey: .keyChanges),
            risksOrNotes: try container.decode([String].self, forKey: .risksOrNotes),
            modelName: try container.decode(String.self, forKey: .modelName),
            usage: try container.decode(GitLLMUsage.self, forKey: .usage),
            isCached: try container.decode(Bool.self, forKey: .isCached),
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            language: try container.decode(String.self, forKey: .language),
            inputMode: try container.decode(DailyReportGitSummaryInputMode.self, forKey: .inputMode),
            algorithm: try container.decodeIfPresent(DailyReportGitSummaryAlgorithm.self, forKey: .algorithm) ?? .singleShot,
            commitCount: try container.decode(Int.self, forKey: .commitCount),
            contentHash: try container.decode(String.self, forKey: .contentHash)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(summary, forKey: .summary)
        try container.encode(keyChanges, forKey: .keyChanges)
        try container.encode(risksOrNotes, forKey: .risksOrNotes)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(usage, forKey: .usage)
        try container.encode(isCached, forKey: .isCached)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(language, forKey: .language)
        try container.encode(inputMode, forKey: .inputMode)
        try container.encode(algorithm, forKey: .algorithm)
        try container.encode(commitCount, forKey: .commitCount)
        try container.encode(contentHash, forKey: .contentHash)
    }
}

enum DailyReportGitDayLoadState: Hashable, Sendable {
    case idle
    case loading
    case loaded(DailyReportGitDaySnapshot)
    case failed(String)
}

enum DailyReportGitDaySummaryLoadState: Hashable, Sendable {
    case idle
    case loading
    case loaded(DailyReportGitDayLLMSummary)
    case failed(String)
}
