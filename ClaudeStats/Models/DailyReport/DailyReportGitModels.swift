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
    var usage: GitSummaryUsage
    var isCached: Bool
    var generatedAt: Date
    var language: String
    var inputMode: DailyReportGitSummaryInputMode
    var commitCount: Int
    var contentHash: String

    var id: String { "\(contentHash)|\(inputMode.rawValue)|\(generatedAt.timeIntervalSinceReferenceDate)" }

    func cachedCopy() -> DailyReportGitDayLLMSummary {
        var copy = self
        copy.isCached = true
        return copy
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
