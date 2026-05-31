import Foundation

enum MemoryProjectSortMode: String, CaseIterable, Identifiable, Sendable {
    case recentGitCommit
    case recentSessionActivity
    case alphabetical
    case recentMemoryUpdate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentGitCommit:
            "Git"
        case .recentSessionActivity:
            "Session"
        case .alphabetical:
            "A-Z"
        case .recentMemoryUpdate:
            "Memory"
        }
    }

    var help: String {
        switch self {
        case .recentGitCommit:
            "Sort projects by your latest git commit."
        case .recentSessionActivity:
            "Sort projects by the latest active session across all providers."
        case .alphabetical:
            "Sort projects alphabetically."
        case .recentMemoryUpdate:
            "Sort projects by the latest memory or source update."
        }
    }
}

struct MemoryProjectSortMetadata: Sendable, Equatable {
    var gitCommitDatesByProjectID: [String: Date]
    var sessionActivityDatesByProjectID: [String: Date]

    static let empty = MemoryProjectSortMetadata(
        gitCommitDatesByProjectID: [:],
        sessionActivityDatesByProjectID: [:]
    )
}

protocol MemoryProjectSortMetadataResolving: Sendable {
    func metadata(projects: [CodeMemoryProject], sessions: [Session]) async -> MemoryProjectSortMetadata
}

struct MemoryProjectSortMetadataResolver: MemoryProjectSortMetadataResolving {
    private let analyzer: GitAnalyzer

    init(analyzer: GitAnalyzer = GitAnalyzer()) {
        self.analyzer = analyzer
    }

    func metadata(projects: [CodeMemoryProject], sessions: [Session]) async -> MemoryProjectSortMetadata {
        let analyzer = analyzer
        return await Task.detached(priority: .utility) {
            let sessionDates = Self.sessionActivityDates(for: sessions)
            let gitDates = Self.gitCommitDates(for: projects, analyzer: analyzer)
            return MemoryProjectSortMetadata(
                gitCommitDatesByProjectID: gitDates,
                sessionActivityDatesByProjectID: sessionDates
            )
        }.value
    }

    private static func sessionActivityDates(for sessions: [Session]) -> [String: Date] {
        var dates: [String: Date] = [:]
        for session in sessions {
            guard let cwd = session.cwd,
                  let projectID = MemoryProjectIdentity.normalizedPathKey(for: cwd) else { continue }
            let activity = session.stats?.lastActivity ?? session.lastModified
            if dates[projectID].map({ activity > $0 }) ?? true {
                dates[projectID] = activity
            }
        }
        return dates
    }

    private static func gitCommitDates(
        for projects: [CodeMemoryProject],
        analyzer: GitAnalyzer
    ) -> [String: Date] {
        guard let authorEmail = analyzer.currentUserEmail(),
              !authorEmail.isEmpty else { return [:] }

        var repoDatesByRoot: [String: Date] = [:]
        var dates: [String: Date] = [:]
        let projectIDs = Set(projects.compactMap { MemoryProjectIdentity.normalizedPathKey(for: $0.projectID) })
        for projectID in projectIDs.sorted() {
            guard FileManager.default.fileExists(atPath: projectID),
                  let repo = analyzer.repo(forCwd: projectID) else { continue }

            if let cached = repoDatesByRoot[repo.rootPath] {
                dates[projectID] = cached
                continue
            }
            if let loaded = analyzer.latestCommitDate(in: repo, authorEmail: authorEmail) {
                repoDatesByRoot[repo.rootPath] = loaded
                dates[projectID] = loaded
            }
        }
        return dates
    }
}

enum MemoryProjectSorter {
    static func sorted(
        projects: [CodeMemoryProject],
        mode: MemoryProjectSortMode,
        metadata: MemoryProjectSortMetadata
    ) -> [CodeMemoryProject] {
        projects.sorted { lhs, rhs in
            precedes(lhs, rhs, mode: mode, metadata: metadata)
        }
    }

    private static func precedes(
        _ lhs: CodeMemoryProject,
        _ rhs: CodeMemoryProject,
        mode: MemoryProjectSortMode,
        metadata: MemoryProjectSortMetadata
    ) -> Bool {
        if mode != .alphabetical {
            let lhsDate = date(for: lhs, mode: mode, metadata: metadata)
            let rhsDate = date(for: rhs, mode: mode, metadata: metadata)
            if lhsDate != rhsDate {
                if let lhsDate, let rhsDate {
                    return lhsDate > rhsDate
                }
                return lhsDate != nil
            }
        }

        let nameComparison = lhs.folderDisplayName.localizedCaseInsensitiveCompare(rhs.folderDisplayName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        return lhs.projectID.localizedStandardCompare(rhs.projectID) == .orderedAscending
    }

    private static func date(
        for project: CodeMemoryProject,
        mode: MemoryProjectSortMode,
        metadata: MemoryProjectSortMetadata
    ) -> Date? {
        switch mode {
        case .recentGitCommit:
            guard let key = MemoryProjectIdentity.normalizedPathKey(for: project.projectID) else { return nil }
            return metadata.gitCommitDatesByProjectID[key]
        case .recentSessionActivity:
            guard let key = MemoryProjectIdentity.normalizedPathKey(for: project.projectID) else { return nil }
            return metadata.sessionActivityDatesByProjectID[key]
        case .alphabetical:
            return nil
        case .recentMemoryUpdate:
            return project.updatedAt.map { Date(timeIntervalSince1970: $0) }
        }
    }
}

enum MemoryProjectIdentity {
    static func normalizedPathKey(for rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
}
