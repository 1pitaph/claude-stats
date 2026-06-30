import Foundation

struct GitReferenceService: Sendable {
    private static let fieldSep = "\u{1f}"
    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    var isAvailable: Bool { runner.isAvailable }

    func snapshot(for repo: GitRepo, reflogLimit: Int = 200) -> GitReferenceSnapshot {
        guard runner.isAvailable else { return .empty }

        let normalizedLimit = max(reflogLimit, 1)
        let headHash = runText(["-C", repo.rootPath, "rev-parse", "--verify", "HEAD"], timeout: 15)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
        let currentBranchName = runText(["-C", repo.rootPath, "branch", "--show-current"], timeout: 15)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
        let refs = references(for: repo, currentBranchName: currentBranchName)
        let localBranches = refs.filter { $0.kind == .localBranch }
        let remoteBranches = refs.filter { $0.kind == .remoteBranch }
        let tags = refs.filter { $0.kind == .tag }
        let remoteGroups = Dictionary(grouping: remoteBranches, by: { $0.remoteName ?? "remote" })
            .mapValues { $0.sorted(by: Self.referenceSort) }
        let remotes = remoteInfo(for: repo)
        let reflogResult = reflogs(for: repo, limit: normalizedLimit)

        return GitReferenceSnapshot(
            localBranches: localBranches.sorted(by: Self.referenceSort),
            remoteGroups: remoteGroups,
            remotes: remotes,
            tags: tags.sorted(by: Self.tagSort),
            reflogs: reflogResult.entries,
            headHash: headHash,
            currentBranchName: currentBranchName,
            isDetachedHead: headHash != nil && currentBranchName == nil,
            reflogLimit: normalizedLimit,
            hasMoreReflogs: reflogResult.hasMore
        )
    }

    func references(for repo: GitRepo, currentBranchName: String? = nil) -> [GitReference] {
        guard runner.isAvailable else { return [] }
        let f = Self.fieldSep
        let format = "%(refname)\(f)%(refname:short)\(f)%(objectname)\(f)%(*objectname)\(f)%(upstream:short)\(f)%(upstream)\(f)%(creatordate:unix)"
        let output = runText([
            "-C", repo.rootPath,
            "for-each-ref",
            "--format=\(format)",
            "refs/heads",
            "refs/remotes",
            "refs/tags",
        ]) ?? ""
        return Self.parseReferences(output, currentBranchName: currentBranchName) { branch, upstream in
            aheadBehind(repo: repo, branch: branch, upstream: upstream)
        }
    }

    func remoteInfo(for repo: GitRepo) -> [GitRemoteInfo] {
        guard let output = runText(["-C", repo.rootPath, "remote", "-v"], timeout: 15) else { return [] }
        return Self.parseRemoteInfo(output)
    }

    func reflogs(for repo: GitRepo, limit: Int) -> (entries: [GitReflogEntry], hasMore: Bool) {
        let normalizedLimit = max(limit, 1)
        guard runner.isAvailable else { return ([], false) }
        let f = Self.fieldSep
        guard let output = runText([
            "-C", repo.rootPath,
            "reflog",
            "--all",
            "--date=iso",
            "--format=%H\(f)%gD\(f)%gd\(f)%gs",
            "-n", "\(normalizedLimit + 1)",
        ], timeout: 20) else {
            return ([], false)
        }
        let parsed = Self.parseReflogs(output)
        return (Array(parsed.prefix(normalizedLimit)), parsed.count > normalizedLimit)
    }

    static func parseReferences(
        _ output: String,
        currentBranchName: String?,
        aheadBehind: (String, String) -> GitReferenceAheadBehind? = { _, _ in nil }
    ) -> [GitReference] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { rawLine -> GitReference? in
                let fields = String(rawLine).components(separatedBy: fieldSep)
                guard fields.count >= 4 else { return nil }
                let fullName = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let shortName = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let objectHash = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
                let peeledHash = fields[3].trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                let upstreamShortName = fields.count > 4 ? fields[4].trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank : nil
                let upstreamFullName = fields.count > 5 ? fields[5].trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank : nil
                let sortTimestamp = fields.count > 6 ? Int(fields[6].trimmingCharacters(in: .whitespacesAndNewlines)) : nil
                guard !fullName.isEmpty, !shortName.isEmpty, !objectHash.isEmpty else { return nil }
                guard let kind = kind(for: fullName) else { return nil }
                if kind == .remoteBranch, shortName.hasSuffix("/HEAD") { return nil }
                let isCurrent = kind == .localBranch && shortName == currentBranchName
                let counts = upstreamShortName.map { aheadBehind(shortName, $0) }
                return GitReference(
                    kind: kind,
                    fullName: fullName,
                    shortName: shortName,
                    objectHash: objectHash,
                    peeledHash: peeledHash,
                    isCurrent: isCurrent,
                    upstreamShortName: upstreamShortName,
                    upstreamFullName: upstreamFullName,
                    aheadBehind: counts ?? nil,
                    sortTimestamp: sortTimestamp
                )
            }
    }

    static func parseRemoteInfo(_ output: String) -> [GitRemoteInfo] {
        struct RemoteAccumulator {
            var fetchURL: String?
            var pushURL: String?
        }

        var remotes: [String: RemoteAccumulator] = [:]
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard parts.count >= 3 else { continue }
            let name = parts[0]
            let url = parts[1]
            let direction = parts[2]
            var remote = remotes[name] ?? RemoteAccumulator()
            if direction == "(fetch)" {
                remote.fetchURL = url
            } else if direction == "(push)" {
                remote.pushURL = url
            }
            remotes[name] = remote
        }
        return remotes
            .map { GitRemoteInfo(name: $0.key, fetchURL: $0.value.fetchURL, pushURL: $0.value.pushURL) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func parseReflogs(_ output: String) -> [GitReflogEntry] {
        var counters: [String: Int] = [:]
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { rawLine -> GitReflogEntry? in
                let fields = String(rawLine).components(separatedBy: fieldSep)
                guard fields.count >= 4 else { return nil }
                let hash = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let selector = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let shortSelector = fields[2].trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? selector
                let message = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !hash.isEmpty, !selector.isEmpty else { return nil }
                let ordinal = counters[selector, default: 0]
                counters[selector] = ordinal + 1
                return GitReflogEntry(
                    id: ordinal == 0 ? selector : "\(selector)#\(ordinal)",
                    selector: selector,
                    shortSelector: shortSelector,
                    targetHash: hash,
                    message: message,
                    dateLabel: dateLabel(from: selector)
                )
            }
    }

    private func aheadBehind(repo: GitRepo, branch: String, upstream: String) -> GitReferenceAheadBehind? {
        guard let output = runText([
            "-C", repo.rootPath,
            "rev-list",
            "--left-right",
            "--count",
            "\(branch)...\(upstream)",
        ], timeout: 15) else {
            return nil
        }
        let counts = output
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .compactMap { Int($0) }
        guard counts.count >= 2 else { return nil }
        return GitReferenceAheadBehind(ahead: counts[0], behind: counts[1])
    }

    private static func kind(for fullName: String) -> GitReferenceKind? {
        if fullName.hasPrefix("refs/heads/") { return .localBranch }
        if fullName.hasPrefix("refs/remotes/") { return .remoteBranch }
        if fullName.hasPrefix("refs/tags/") { return .tag }
        return nil
    }

    private static func dateLabel(from selector: String) -> String? {
        guard let open = selector.lastIndex(of: "{"),
              let close = selector.lastIndex(of: "}"),
              open < close else { return nil }
        let value = selector[selector.index(after: open)..<close]
        return String(value).nilIfBlank
    }

    private func runText(_ arguments: [String], timeout: TimeInterval = 30) -> String? {
        let result = runner.run(arguments, timeout: timeout)
        guard result.succeeded else {
            return nil
        }
        return result.stdout
    }

    private static func referenceSort(_ lhs: GitReference, _ rhs: GitReference) -> Bool {
        if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
        return lhs.shortName.localizedStandardCompare(rhs.shortName) == .orderedAscending
    }

    private static func tagSort(_ lhs: GitReference, _ rhs: GitReference) -> Bool {
        switch (lhs.sortTimestamp, rhs.sortTimestamp) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.shortName.localizedStandardCompare(rhs.shortName) == .orderedAscending
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
