import Foundation

/// A ref (branch / tag / HEAD) pointing at a commit, parsed from `git log`'s
/// `%D` decoration field.
struct GitRef: Sendable, Hashable {
    enum Kind: Sendable { case head, branch, remoteBranch, tag }
    let kind: Kind
    /// `"main"`, `"v1.0"`, `"claude/fix-drawer-card-bugs"`, …
    let name: String
}

/// One commit as it appears in the graph: enough to draw the DAG (parents) and
/// the row (refs, author, date, subject). No diff stats — those are fetched
/// lazily per row via ``GitAnalyzer/fileChanges(for:in:)``.
struct GraphCommit: Sendable, Identifiable, Hashable {
    let hash: String
    /// Parent hashes in git's order; more than one ⇒ a merge commit.
    let parentHashes: [String]
    let refs: [GitRef]
    let author: String
    let authorEmail: String
    let date: Date
    let subject: String

    var id: String { hash }
    var isMerge: Bool { parentHashes.count > 1 }
    var shortHash: String { String(hash.prefix(7)) }
}

/// One uncommitted working-tree change from `git status --porcelain`.
struct GitWorkingTreeChange: Sendable, Identifiable, Hashable {
    enum Kind: Sendable, Hashable {
        case added
        case modified
        case deleted
        case renamed
        case copied
        case untracked
        case conflicted
        case changed

        var label: String {
            switch self {
            case .added: return "Added"
            case .modified: return "Modified"
            case .deleted: return "Deleted"
            case .renamed: return "Renamed"
            case .copied: return "Copied"
            case .untracked: return "Untracked"
            case .conflicted: return "Conflict"
            case .changed: return "Changed"
            }
        }

        var shortLabel: String {
            switch self {
            case .added: return "ADD"
            case .modified: return "MOD"
            case .deleted: return "DEL"
            case .renamed: return "REN"
            case .copied: return "CPY"
            case .untracked: return "NEW"
            case .conflicted: return "CON"
            case .changed: return "CHG"
            }
        }
    }

    let path: String
    let oldPath: String?
    let indexStatus: String
    let worktreeStatus: String
    let kind: Kind

    var id: String { "\(indexStatus)\(worktreeStatus)|\(oldPath ?? "")|\(path)" }
    var isStaged: Bool { indexStatus != " " && indexStatus != "?" }
    var isUnstaged: Bool { indexStatus == "?" || worktreeStatus != " " }

    var displayPath: String {
        guard let oldPath, !oldPath.isEmpty else { return path }
        return "\(oldPath) -> \(path)"
    }
}

/// Summary of changes that are present in the working tree but not represented
/// by any commit in the graph.
struct GitWorkingTreeSummary: Sendable, Equatable {
    let changes: [GitWorkingTreeChange]

    static let clean = GitWorkingTreeSummary(changes: [])

    var isDirty: Bool { !changes.isEmpty }
    var fileCount: Int { changes.count }
    var stagedCount: Int { changes.filter(\.isStaged).count }
    var unstagedCount: Int { changes.filter(\.isUnstaged).count }

    var title: String {
        "\(fileCount) modified file\(fileCount == 1 ? "" : "s")"
    }
}

/// Local commits that are not yet represented on the current branch's remote
/// target. This is a virtual graph row, similar to ``GitWorkingTreeSummary``.
struct GitOutgoingChangesSummary: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case outgoing
        case publishBranch
    }

    let kind: Kind
    let totalCount: Int
    let behindCount: Int
    let upstreamName: String?
    let headHash: String?
    let pushTarget: GitPushTarget?
    let commits: [GraphCommit]

    static let none = GitOutgoingChangesSummary(
        kind: .outgoing,
        totalCount: 0,
        behindCount: 0,
        upstreamName: nil,
        headHash: nil,
        pushTarget: nil,
        commits: []
    )

    var isActive: Bool { totalCount > 0 && pushTarget != nil }

    var title: String {
        switch kind {
        case .outgoing:
            return "Outgoing Changes"
        case .publishBranch:
            return "Publish Branch"
        }
    }

    var countLabel: String {
        "\(totalCount) commit\(totalCount == 1 ? "" : "s")"
    }

    var targetLabel: String {
        switch kind {
        case .outgoing:
            return upstreamName ?? "upstream"
        case .publishBranch:
            return pushTarget?.branchName ?? "current branch"
        }
    }
}

/// The commit list for one repo, in display order (`--date-order`, newest first).
struct GitGraph: Sendable {
    let repo: GitRepo
    let commits: [GraphCommit]
    /// `true` when the log hit the requested limit (more history exists).
    let truncated: Bool
    let workingTree: GitWorkingTreeSummary
    let outgoingChanges: GitOutgoingChangesSummary

    init(
        repo: GitRepo,
        commits: [GraphCommit],
        truncated: Bool,
        workingTree: GitWorkingTreeSummary = .clean,
        outgoingChanges: GitOutgoingChangesSummary = .none
    ) {
        self.repo = repo
        self.commits = commits
        self.truncated = truncated
        self.workingTree = workingTree
        self.outgoingChanges = outgoingChanges
    }
}

struct GitGraphPage: Sendable {
    let repo: GitRepo
    let commits: [GraphCommit]
    let offset: Int
    let limit: Int
    let hasMore: Bool
    let workingTree: GitWorkingTreeSummary
    let outgoingChanges: GitOutgoingChangesSummary

    init(
        repo: GitRepo,
        commits: [GraphCommit],
        offset: Int,
        limit: Int,
        hasMore: Bool,
        workingTree: GitWorkingTreeSummary,
        outgoingChanges: GitOutgoingChangesSummary = .none
    ) {
        self.repo = repo
        self.commits = commits
        self.offset = offset
        self.limit = limit
        self.hasMore = hasMore
        self.workingTree = workingTree
        self.outgoingChanges = outgoingChanges
    }
}

struct GitGraphMinimapData: Sendable, Hashable {
    enum Granularity: String, Sendable, Hashable, CaseIterable {
        case day
        case week
        case month
        case quarter
        case year
    }

    struct Bucket: Sendable, Hashable, Identifiable {
        let start: Date
        let commitCount: Int
        let insertions: Int
        let deletions: Int
        let representativeHash: String?

        var id: TimeInterval { start.timeIntervalSinceReferenceDate }
        var churn: Int { insertions + deletions }
    }

    struct Marker: Sendable, Hashable, Identifiable {
        enum Priority: Int, Sendable, Hashable {
            case secondary
            case normal
            case primary
        }

        enum Kind: Sendable, Hashable {
            case head
            case branch
            case remoteBranch
            case tag
            case workingTree
        }

        let kind: Kind
        let label: String
        let hash: String?
        let bucketStart: Date
        let priority: Priority

        var id: String {
            "\(priority)|\(kind)|\(label)|\(hash ?? "")|\(bucketStart.timeIntervalSinceReferenceDate)"
        }
    }

    let granularity: Granularity
    let buckets: [Bucket]
    let markers: [Marker]
    let hashBucketStarts: [String: Date]
    let selectedHash: String?

    var maxCommitCount: Int { max(buckets.map(\.commitCount).max() ?? 0, 1) }
    var maxChurn: Int { max(buckets.map(\.churn).max() ?? 0, 1) }
    var selectedBucketStart: Date? {
        guard let selectedHash else { return nil }
        return hashBucketStarts[selectedHash]
    }

    func selecting(hash: String?) -> GitGraphMinimapData {
        GitGraphMinimapData(
            granularity: granularity,
            buckets: buckets,
            markers: markers,
            hashBucketStarts: hashBucketStarts,
            selectedHash: hash
        )
    }

    func bucket(containing hash: String) -> Bucket? {
        guard let start = hashBucketStarts[hash] else { return nil }
        return buckets.first { $0.start == start }
    }

    static func build(
        commits: [GitCommit],
        refsByHash: [String: [GitRef]],
        workingTree: GitWorkingTreeSummary,
        selectedHash: String?,
        targetMaxBuckets: Int = 120,
        currentBranch: String? = nil,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> GitGraphMinimapData {
        let granularity = selectGranularity(
            commits: commits,
            workingTree: workingTree,
            targetMaxBuckets: targetMaxBuckets,
            calendar: calendar,
            now: now
        )
        var cells: [Date: (count: Int, insertions: Int, deletions: Int, representativeHash: String?, representativeDate: Date?)] = [:]
        var hashBucketStarts: [String: Date] = [:]

        for commit in commits {
            let start = bucketStart(for: commit.date, granularity: granularity, calendar: calendar)
            var cell = cells[start, default: (0, 0, 0, nil, nil)]
            cell.count += 1
            cell.insertions += max(commit.insertions, 0)
            cell.deletions += max(commit.deletions, 0)
            if cell.representativeDate == nil || commit.date > (cell.representativeDate ?? .distantPast) {
                cell.representativeHash = commit.hash
                cell.representativeDate = commit.date
            }
            cells[start] = cell
            hashBucketStarts[commit.hash] = start
        }

        let today = bucketStart(for: now, granularity: granularity, calendar: calendar)
        if workingTree.isDirty, cells[today] == nil {
            cells[today] = (0, 0, 0, nil, nil)
        }

        let buckets = cells
            .map { start, cell in
                Bucket(
                    start: start,
                    commitCount: cell.count,
                    insertions: cell.insertions,
                    deletions: cell.deletions,
                    representativeHash: cell.representativeHash
                )
            }
            .sorted { $0.start < $1.start }

        var markers: [Marker] = []
        for (hash, refs) in refsByHash {
            guard let start = hashBucketStarts[hash] else { continue }
            for ref in refs {
                let kind: Marker.Kind
                let priority: Marker.Priority
                switch ref.kind {
                case .head:
                    kind = .head
                    priority = .primary
                case .branch:
                    kind = .branch
                    priority = ref.name == currentBranch ? .primary : .normal
                case .remoteBranch:
                    kind = .remoteBranch
                    priority = .secondary
                case .tag:
                    kind = .tag
                    priority = .secondary
                }
                markers.append(Marker(kind: kind, label: ref.name, hash: hash, bucketStart: start, priority: priority))
            }
        }
        if workingTree.isDirty {
            markers.append(Marker(kind: .workingTree, label: "Working Tree", hash: nil, bucketStart: today, priority: .primary))
        }

        return GitGraphMinimapData(
            granularity: granularity,
            buckets: buckets,
            markers: reducedMarkers(markers).sorted { lhs, rhs in
                if lhs.bucketStart != rhs.bucketStart { return lhs.bucketStart < rhs.bucketStart }
                if lhs.priority != rhs.priority { return lhs.priority.rawValue < rhs.priority.rawValue }
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            },
            hashBucketStarts: hashBucketStarts,
            selectedHash: selectedHash
        )
    }

    static func selectGranularity(
        commits: [GitCommit],
        workingTree: GitWorkingTreeSummary,
        targetMaxBuckets: Int,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Granularity {
        let target = max(targetMaxBuckets, 1)
        for granularity in Granularity.allCases {
            var starts = Set(commits.map { bucketStart(for: $0.date, granularity: granularity, calendar: calendar) })
            if workingTree.isDirty {
                starts.insert(bucketStart(for: now, granularity: granularity, calendar: calendar))
            }
            if starts.count <= target {
                return granularity
            }
        }
        return .year
    }

    static func bucketStart(for date: Date, granularity: Granularity, calendar: Calendar = .current) -> Date {
        switch granularity {
        case .day:
            return calendar.dateInterval(of: .day, for: date)?.start ?? date
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start ?? date
        case .quarter:
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let year = components.year, let month = components.month else { return date }
            let firstMonth = ((month - 1) / 3) * 3 + 1
            return calendar.date(from: DateComponents(year: year, month: firstMonth, day: 1)) ?? date
        case .year:
            return calendar.dateInterval(of: .year, for: date)?.start ?? date
        }
    }

    private static func reducedMarkers(_ markers: [Marker]) -> [Marker] {
        var output: [Marker] = []
        let byBucket = Dictionary(grouping: markers, by: \.bucketStart)
        for (bucketStart, markers) in byBucket {
            let primary = markers.filter { $0.priority == .primary }
            output.append(contentsOf: primary)

            let normal = markers
                .filter { $0.priority == .normal }
                .reduce(into: [Marker.Kind: Marker]()) { result, marker in
                    let existing = result[marker.kind]
                    if existing == nil || marker.label.localizedStandardCompare(existing?.label ?? "") == .orderedAscending {
                        result[marker.kind] = marker
                    }
                }
                .values
            output.append(contentsOf: normal)

            let secondary = markers.filter { $0.priority == .secondary }
            if secondary.count == 1, let marker = secondary.first {
                output.append(marker)
            } else if let first = secondary.sorted(by: markerSort).first {
                let hasRemote = secondary.contains { $0.kind == .remoteBranch }
                output.append(
                    Marker(
                        kind: hasRemote ? .remoteBranch : first.kind,
                        label: "\(secondary.count) refs",
                        hash: first.hash,
                        bucketStart: bucketStart,
                        priority: .secondary
                    )
                )
            }
        }
        return output
    }

    private static func markerSort(_ lhs: Marker, _ rhs: Marker) -> Bool {
        if lhs.kind != rhs.kind {
            return markerKindRank(lhs.kind) < markerKindRank(rhs.kind)
        }
        return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
    }

    private static func markerKindRank(_ kind: Marker.Kind) -> Int {
        switch kind {
        case .workingTree: return 0
        case .head: return 1
        case .branch: return 2
        case .remoteBranch: return 3
        case .tag: return 4
        }
    }
}

/// One file's churn within a commit — the expanded-row detail in the graph.
/// `insertions`/`deletions` are `-1` for binary files (git prints `-`).
struct CommitFileChange: Sendable, Identifiable, Hashable {
    let path: String
    let insertions: Int
    let deletions: Int
    var id: String { path }
    var isBinary: Bool { insertions < 0 || deletions < 0 }

    /// The directory the file lives in (`""` ⇒ repo root); used to group the
    /// file list in ``CommitDetailView``.
    var directory: String { (path as NSString).deletingLastPathComponent }
    var fileName: String { (path as NSString).lastPathComponent }
}

/// Full metadata + per-file churn for one commit — the ``CommitDetailView``
/// model, loaded via ``GitAnalyzer/commitDetail(for:in:)`` (`git show --numstat`).
struct CommitDetail: Sendable, Hashable, Identifiable {
    let hash: String
    let abbreviatedHash: String
    let parentHashes: [String]
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let committerName: String
    let committerEmail: String
    let commitDate: Date
    let subject: String
    /// The commit message body (everything after the subject), trimmed; may be empty.
    let body: String
    let files: [CommitFileChange]

    var id: String { hash }
    var isMerge: Bool { parentHashes.count > 1 }
    var totalInsertions: Int { files.lazy.filter { !$0.isBinary }.reduce(0) { $0 + $1.insertions } }
    var totalDeletions: Int { files.lazy.filter { !$0.isBinary }.reduce(0) { $0 + $1.deletions } }
}

/// One line of a unified diff, for the ``FileDiffView``.
struct DiffLine: Sendable, Hashable, Identifiable {
    enum Kind: Sendable, Hashable { case fileHeader, hunkHeader, context, addition, deletion }
    let kind: Kind
    /// The line text without the leading `+`/`-`/space marker.
    let text: String
    let oldLine: Int?
    let newLine: Int?
    let id = UUID()
}

/// The unified diff of one file within a commit (`git show -- <path>`).
struct FileDiff: Sendable, Hashable {
    let path: String
    let isBinary: Bool
    let lines: [DiffLine]
}
