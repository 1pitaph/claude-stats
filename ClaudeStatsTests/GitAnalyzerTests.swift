import Testing
import Foundation
@testable import ClaudeStats

@Suite("GitAnalyzer")
struct GitAnalyzerTests {

    // MARK: - parseLog (no git needed)

    private static let RS = "\u{1e}"
    private static let FS = "\u{1f}"

    @Test("parseLog reads header fields and sums numstat lines")
    func parseLogBasics() {
        let log = """
        \(Self.RS)abc123\(Self.FS)1705314600\(Self.FS)Ada\(Self.FS)ada@example.com\(Self.FS)Add parser
        3\t1\tsrc/a.swift
        10\t0\tsrc/b.swift
        \(Self.RS)def456\(Self.FS)1705222800\(Self.FS)Ada\(Self.FS)ada@example.com\(Self.FS)Tweak
        1\t1\tsrc/a.swift
        """
        let commits = GitAnalyzer.parseLog(log, repoID: "/repo")
        #expect(commits.count == 2)
        let first = commits[0]
        #expect(first.hash == "abc123")
        #expect(first.shortHash == "abc123")
        #expect(first.author == "Ada")
        #expect(first.authorEmail == "ada@example.com")
        #expect(first.subject == "Add parser")
        #expect(first.date == Date(timeIntervalSince1970: 1_705_314_600))
        #expect(first.insertions == 13)
        #expect(first.deletions == 1)
        #expect(first.filesChanged == 2)
        #expect(first.churn == 14)
        #expect(first.repoID == "/repo")
        #expect(commits[1].hash == "def456")
        #expect(commits[1].insertions == 1 && commits[1].deletions == 1 && commits[1].filesChanged == 1)
    }

    @Test("parseLog treats binary numstat ('-') as zero churn but counts the file")
    func parseLogBinary() {
        let log = "\(Self.RS)h1\(Self.FS)1705314600\(Self.FS)A\(Self.FS)a@x.com\(Self.FS)Add image\n-\t-\tassets/logo.png\n5\t2\tcode.swift"
        let commits = GitAnalyzer.parseLog(log, repoID: "r")
        #expect(commits.count == 1)
        #expect(commits[0].filesChanged == 2)
        #expect(commits[0].insertions == 5 && commits[0].deletions == 2)
    }

    @Test("parseLog ignores blank and malformed records")
    func parseLogMalformed() {
        let log = "\n\(Self.RS)\(Self.RS)onlytwo\(Self.FS)fields\n\(Self.RS)h1\(Self.FS)1705314600\(Self.FS)A\(Self.FS)a@x.com\(Self.FS)ok"
        let commits = GitAnalyzer.parseLog(log, repoID: "r")
        #expect(commits.count == 1)
        #expect(commits[0].subject == "ok")
    }

    // MARK: - parseNumstat / parseCommitShow / parseUnifiedDiff (no git needed)

    @Test("parseNumstat reads ins/del/path and maps binary '-' to -1")
    func parseNumstatBasics() {
        let out = "12\t3\tSources/A.swift\n0\t9\tSources/B.swift\n-\t-\tassets/logo.png\nmalformed line\n"
        let files = GitAnalyzer.parseNumstat(out)
        #expect(files.count == 3)
        #expect(files[0].path == "Sources/A.swift" && files[0].insertions == 12 && files[0].deletions == 3)
        #expect(files[0].directory == "Sources" && files[0].fileName == "A.swift")
        #expect(files[2].isBinary && files[2].insertions == -1 && files[2].deletions == -1)
    }

    @Test("parseCommitShow reads metadata, body and numstat")
    func parseCommitShowBasics() throws {
        let f = Self.FS, r = Self.RS
        let fields = ["abc123def456", "abc123d", "p1 p2",
                      "Ada", "ada@example.com", "1705314600",
                      "Grace", "grace@example.com", "1705315020",
                      "feat: do the thing", "Body line one\n\nBody line two\n"].joined(separator: f)
        let out = "\(r)\(fields)\(r)\n\n5\t1\tSources/A.swift\n-\t-\tlogo.png\n"
        let detail = try #require(GitAnalyzer.parseCommitShow(out))
        #expect(detail.hash == "abc123def456")
        #expect(detail.abbreviatedHash == "abc123d")
        #expect(detail.parentHashes == ["p1", "p2"])
        #expect(detail.isMerge)
        #expect(detail.authorName == "Ada" && detail.authorEmail == "ada@example.com")
        #expect(detail.authorDate == Date(timeIntervalSince1970: 1_705_314_600))
        #expect(detail.committerName == "Grace" && detail.commitDate == Date(timeIntervalSince1970: 1_705_315_020))
        #expect(detail.subject == "feat: do the thing")
        #expect(detail.body == "Body line one\n\nBody line two")
        #expect(detail.files.count == 2)
        #expect(detail.totalInsertions == 5 && detail.totalDeletions == 1)   // binary excluded
    }

    @Test("parseCommitShow on a merge commit (no numstat) yields empty files")
    func parseCommitShowMerge() throws {
        let f = Self.FS, r = Self.RS
        let fields = ["h", "h", "p1 p2", "A", "a@x", "1", "A", "a@x", "1", "Merge branch 'x'", ""].joined(separator: f)
        let detail = try #require(GitAnalyzer.parseCommitShow("\(r)\(fields)\(r)\n"))
        #expect(detail.isMerge && detail.files.isEmpty && detail.body.isEmpty)
    }

    @Test("parseUnifiedDiff classifies headers, hunk lines and tracks line numbers")
    func parseUnifiedDiffBasics() throws {
        let diff = """
        diff --git a/A.swift b/A.swift
        index 111..222 100644
        --- a/A.swift
        +++ b/A.swift
        @@ -10,3 +10,4 @@ func f() {
             let a = 1
        -    let b = 2
        +    let b = 3
        +    let c = 4
             return a
        """
        let lines = GitAnalyzer.parseUnifiedDiff(diff)
        #expect(lines.prefix(4).allSatisfy { $0.kind == .fileHeader })
        let hunk = try #require(lines.first { $0.kind == .hunkHeader })
        #expect(hunk.text.hasPrefix("@@ -10,3 +10,4 @@"))
        let body = lines.drop(while: { $0.kind != .hunkHeader }).dropFirst()
        #expect(Array(body).map(\.kind) == [.context, .deletion, .addition, .addition, .context])
        let firstContext = try #require(body.first)
        #expect(firstContext.oldLine == 10 && firstContext.newLine == 10)
        let delLine = try #require(body.first { $0.kind == .deletion })
        #expect(delLine.text == "    let b = 2" && delLine.oldLine == 11 && delLine.newLine == nil)
        let lastContext = try #require(body.last)
        #expect(lastContext.oldLine == 12 && lastContext.newLine == 13)
    }

    @Test("parseWorkingTreeStatus reads staged, unstaged, renamed and untracked files")
    func parseWorkingTreeStatusBasics() throws {
        let output = [
            " M Sources/App.swift",
            "M  Sources/Store.swift",
            "A  Sources/NewFile.swift",
            "R  Sources/OldName.swift -> Sources/NewName.swift",
            "?? Scratch Notes.md",
        ].joined(separator: "\n")
        let summary = GitAnalyzer.parseWorkingTreeStatus(output)

        #expect(summary.fileCount == 5)
        #expect(summary.stagedCount == 3)
        #expect(summary.unstagedCount == 2)
        #expect(summary.changes.contains { $0.path == "Sources/App.swift" && $0.kind == .modified && $0.isUnstaged })
        #expect(summary.changes.contains { $0.path == "Sources/Store.swift" && $0.kind == .modified && $0.isStaged })
        let renamed = try #require(summary.changes.first { $0.path == "Sources/NewName.swift" })
        #expect(renamed.oldPath == "Sources/OldName.swift")
        #expect(renamed.displayPath == "Sources/OldName.swift -> Sources/NewName.swift")
        #expect(summary.changes.contains { $0.path == "Scratch Notes.md" && $0.kind == .untracked })
    }

    @Test("parseWorkingTreeStatusZ reads NUL separated paths and rename pairs")
    func parseWorkingTreeStatusZ() throws {
        let output = [
            " M Sources/App With Spaces.swift",
            "R  Sources/New Name.swift",
            "Sources/Old Name.swift",
            "?? Scratch Notes.md",
            "UU Sources/Conflict.swift",
        ].joined(separator: "\0") + "\0"
        let summary = GitAnalyzer.parseWorkingTreeStatusZ(output)

        #expect(summary.fileCount == 4)
        #expect(summary.changes.contains { $0.path == "Sources/App With Spaces.swift" && $0.kind == .modified })
        let renamed = try #require(summary.changes.first { $0.kind == .renamed })
        #expect(renamed.path == "Sources/New Name.swift")
        #expect(renamed.oldPath == "Sources/Old Name.swift")
        #expect(summary.changes.contains { $0.path == "Scratch Notes.md" && $0.kind == .untracked })
        #expect(summary.changes.contains { $0.path == "Sources/Conflict.swift" && $0.kind == .conflicted })
    }

    // MARK: - bucketing

    @Test("RepoActivity.buckets groups commits per repo per calendar unit")
    func bucketing() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(identifier: "UTC")!
        func date(_ s: String) -> Date { iso.date(from: s + "Z")! }
        func commit(_ id: String, _ iso: String, ins: Int, del: Int, repo: String) -> GitCommit {
            GitCommit(hash: id, date: date(iso), author: "A", authorEmail: "a", subject: "s",
                      insertions: ins, deletions: del, filesChanged: 1, repoID: repo)
        }
        let repoA = GitRepo(rootPath: "/a")
        let repoB = GitRepo(rootPath: "/b")
        let activity = [
            RepoActivity(repo: repoA, commits: [
                commit("1", "2024-01-15T10:00:00", ins: 5, del: 1, repo: "/a"),
                commit("2", "2024-01-15T18:00:00", ins: 2, del: 0, repo: "/a"),
                commit("3", "2024-01-16T09:00:00", ins: 1, del: 1, repo: "/a"),
            ]),
            RepoActivity(repo: repoB, commits: [
                commit("4", "2024-01-15T12:00:00", ins: 8, del: 3, repo: "/b"),
            ]),
        ]
        let buckets = activity.buckets(by: .day, calendar: cal)
        #expect(buckets.count == 3)
        let aDay15 = buckets.first { $0.repoID == "/a" && cal.component(.day, from: $0.start) == 15 }
        #expect(aDay15?.commitCount == 2)
        #expect(aDay15?.insertions == 7 && aDay15?.deletions == 1)
        #expect(activity.allCommitsNewestFirst.map(\.hash) == ["3", "2", "4", "1"])
    }

    @Test("full ref names classify local branches, remote branches and tags")
    func fullRefNames() {
        #expect(GitAnalyzer.ref(fromFullName: "refs/heads/main") == GitRef(kind: .branch, name: "main"))
        #expect(GitAnalyzer.ref(fromFullName: "refs/remotes/origin/main") == GitRef(kind: .remoteBranch, name: "origin/main"))
        #expect(GitAnalyzer.ref(fromFullName: "refs/remotes/origin/HEAD") == nil)
        #expect(GitAnalyzer.ref(fromFullName: "refs/tags/v1.0") == GitRef(kind: .tag, name: "v1.0"))
    }

    @Test("minimap aggregation keeps density, churn, refs and selected bucket")
    func minimapAggregation() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(identifier: "UTC")!
        func date(_ value: String) -> Date { iso.date(from: value)! }
        let commits = [
            GitCommit(hash: "b", date: date("2024-01-15T18:00:00Z"), author: "A", authorEmail: "a@x", subject: "B", insertions: 5, deletions: 2, filesChanged: 1, repoID: "r"),
            GitCommit(hash: "a", date: date("2024-01-15T09:00:00Z"), author: "A", authorEmail: "a@x", subject: "A", insertions: 1, deletions: 1, filesChanged: 1, repoID: "r"),
            GitCommit(hash: "c", date: date("2024-01-16T10:00:00Z"), author: "A", authorEmail: "a@x", subject: "C", insertions: 3, deletions: 0, filesChanged: 1, repoID: "r"),
        ]
        let data = GitGraphMinimapData.build(
            commits: commits,
            refsByHash: ["b": [GitRef(kind: .head, name: "main")], "c": [GitRef(kind: .remoteBranch, name: "origin/main")]],
            workingTree: .clean,
            selectedHash: "a",
            calendar: cal,
            now: date("2024-01-16T10:00:00Z")
        )

        #expect(data.granularity == .day)
        #expect(data.buckets.count == 2)
        #expect(data.buckets[0].commitCount == 2)
        #expect(data.buckets[0].churn == 9)
        #expect(data.buckets[0].representativeHash == "b")
        #expect(data.buckets[1].commitCount == 1)
        #expect(data.markers.contains { $0.kind == .head && $0.label == "main" && $0.priority == .primary })
        #expect(data.markers.contains { $0.kind == .remoteBranch && $0.label == "origin/main" && $0.priority == .secondary })
        #expect(data.selectedBucketStart == data.buckets[0].start)
        let selectedBucket = try #require(data.bucket(containing: "a"))
        #expect(selectedBucket.start == data.buckets[0].start)
    }

    @Test("minimap chooses coarser granularity as commit density grows")
    func minimapAdaptiveGranularity() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let base = try #require(cal.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 12)))

        func commit(_ index: Int) -> GitCommit {
            GitCommit(
                hash: "c\(index)",
                date: cal.date(byAdding: .day, value: -index, to: base)!,
                author: "A",
                authorEmail: "a@x",
                subject: "Commit \(index)",
                insertions: 1,
                deletions: 0,
                filesChanged: 1,
                repoID: "r"
            )
        }

        let seventyDays = (0..<70).map(commit)
        let weekly = GitGraphMinimapData.build(
            commits: seventyDays,
            refsByHash: [:],
            workingTree: .clean,
            selectedHash: "c0",
            targetMaxBuckets: 20,
            calendar: cal,
            now: base
        )
        #expect(weekly.granularity == .week)
        #expect(weekly.buckets.count <= 20)
        #expect(weekly.bucket(containing: "c0")?.representativeHash == "c0")

        let monthly = GitGraphMinimapData.build(
            commits: seventyDays,
            refsByHash: [:],
            workingTree: .clean,
            selectedHash: nil,
            targetMaxBuckets: 4,
            calendar: cal,
            now: base
        )
        #expect(monthly.granularity == .month)

        let longHistory = (0..<700).map(commit)
        let yearly = GitGraphMinimapData.build(
            commits: longHistory,
            refsByHash: [:],
            workingTree: .clean,
            selectedHash: nil,
            targetMaxBuckets: 4,
            calendar: cal,
            now: base
        )
        #expect(yearly.granularity == .year)
    }

    @Test("minimap marker reduction prioritizes current branch and folds secondary refs")
    func minimapMarkerReduction() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 15, hour: 12)))
        let commit = GitCommit(
            hash: "h",
            date: date,
            author: "A",
            authorEmail: "a@x",
            subject: "H",
            insertions: 1,
            deletions: 1,
            filesChanged: 1,
            repoID: "r"
        )

        let data = GitGraphMinimapData.build(
            commits: [commit],
            refsByHash: [
                "h": [
                    GitRef(kind: .head, name: "HEAD"),
                    GitRef(kind: .branch, name: "main"),
                    GitRef(kind: .branch, name: "feature/a"),
                    GitRef(kind: .branch, name: "feature/b"),
                    GitRef(kind: .remoteBranch, name: "origin/main"),
                    GitRef(kind: .tag, name: "v1.0"),
                    GitRef(kind: .tag, name: "v2.0"),
                ],
            ],
            workingTree: .clean,
            selectedHash: nil,
            currentBranch: "main",
            calendar: cal,
            now: date
        )

        #expect(data.markers.contains { $0.kind == .head && $0.priority == .primary })
        #expect(data.markers.contains { $0.kind == .branch && $0.label == "main" && $0.priority == .primary })
        #expect(data.markers.filter { $0.kind == .branch && $0.priority == .normal }.map(\.label) == ["feature/a"])
        let secondary = data.markers.filter { $0.priority == .secondary }
        #expect(secondary.count == 1)
        #expect(secondary.first?.kind == .remoteBranch)
        #expect(secondary.first?.label == "3 refs")
    }

    @Test("dirty working tree marker uses the selected minimap granularity")
    func minimapWorkingTreeMarkerUsesGranularity() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let oldDate = try #require(cal.date(from: DateComponents(year: 2020, month: 1, day: 1, hour: 12)))
        let now = try #require(cal.date(from: DateComponents(year: 2024, month: 8, day: 20, hour: 12)))
        let commit = GitCommit(
            hash: "old",
            date: oldDate,
            author: "A",
            authorEmail: "a@x",
            subject: "Old",
            insertions: 1,
            deletions: 0,
            filesChanged: 1,
            repoID: "r"
        )
        let dirty = GitWorkingTreeSummary(changes: [
            GitWorkingTreeChange(path: "App.swift", oldPath: nil, indexStatus: " ", worktreeStatus: "M", kind: .modified),
        ])

        let data = GitGraphMinimapData.build(
            commits: [commit],
            refsByHash: [:],
            workingTree: dirty,
            selectedHash: nil,
            targetMaxBuckets: 1,
            calendar: cal,
            now: now
        )
        let expectedStart = GitGraphMinimapData.bucketStart(for: now, granularity: data.granularity, calendar: cal)
        #expect(data.markers.contains { $0.kind == .workingTree && $0.bucketStart == expectedStart && $0.priority == .primary })
        #expect(data.buckets.contains { $0.start == expectedStart })
    }

    // MARK: - against a real temp repo

    @Test("repos / activity / author filter against a real git repo", .enabled(if: GitAnalyzer().isAvailable))
    func realRepo() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitanalyzer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try run(["init", "-q"], in: dir)
        try run(["config", "user.email", "me@example.com"], in: dir)
        try run(["config", "user.name", "Me"], in: dir)
        try run(["config", "commit.gpgsign", "false"], in: dir)

        try (Array(repeating: "line", count: 3).joined(separator: "\n") + "\n")
            .write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try run(["add", "a.txt"], in: dir)
        try run(["commit", "-q", "-m", "Add a.txt"], in: dir)

        try (Array(repeating: "line", count: 5).joined(separator: "\n") + "\n")
            .write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try run(["commit", "-q", "-am", "Grow a.txt"], in: dir)

        // A commit by a different author.
        try "one\n".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try run(["add", "b.txt"], in: dir)
        try run(["-c", "user.email=other@example.com", "-c", "user.name=Other", "commit", "-q", "-m", "Add b.txt"], in: dir)

        let analyzer = GitAnalyzer()
        let resolvedRoot = try run(["rev-parse", "--show-toplevel"], in: dir).trimmingCharacters(in: .whitespacesAndNewlines)

        // Discovery + de-dup: the dir and a subdir resolve to the same root.
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let repos = analyzer.repos(forCwds: [dir.path, sub.path, "/nonexistent/path/xyz"])
        #expect(repos.count == 1)
        let repo = try #require(repos.first)
        #expect(repo.rootPath == resolvedRoot)
        #expect(repo.gitDirPath?.hasSuffix(".git") == true)
        #expect(repo.commonDirPath?.hasSuffix(".git") == true)
        #expect(repo.cacheKey == repo.commonDirPath)
        #expect(!repo.isWorktree)

        // All commits (no author filter).
        let all = analyzer.activity(for: repos, since: .distantPast, authorEmail: nil)
        #expect(all.count == 1)
        let activity = try #require(all.first)
        #expect(activity.commitCount == 3)
        // a.txt: +3 then +2 (no deletions when growing a file); b.txt: +1.
        #expect(activity.insertions == 6)
        #expect(activity.deletions == 0)
        #expect(activity.churn == 6)
        #expect(activity.filesChanged == 3)
        #expect(activity.commits.map(\.subject) == ["Add b.txt", "Grow a.txt", "Add a.txt"])

        // Author filter excludes "Other".
        let mine = analyzer.activity(for: repos, since: .distantPast, authorEmail: "me@example.com")
        #expect(mine.first?.commitCount == 2)
        #expect(mine.first?.commits.allSatisfy { $0.authorEmail == "me@example.com" } == true)

        // `since` in the future → nothing.
        let none = analyzer.activity(for: repos, since: Date(timeIntervalSinceNow: 86_400), authorEmail: nil)
        #expect(none.isEmpty)

        try run(["branch", "feature/test"], in: dir)
        try run(["tag", "v-test"], in: dir)
        let page = try #require(analyzer.graphPage(for: repo, offset: 0, limit: 2))
        #expect(page.commits.count == 2)
        #expect(page.hasMore)
        let refs = analyzer.refsByHash(for: repo)
        #expect(refs.values.flatMap { $0 }.contains(GitRef(kind: .branch, name: "feature/test")))
        #expect(refs.values.flatMap { $0 }.contains(GitRef(kind: .tag, name: "v-test")))
    }

    @Test("minimap cache key separates target bucket counts")
    func minimapCacheKeySeparatesTargetBucketCounts() {
        let repo = GitRepo(rootPath: "/repo", gitDirPath: "/repo/.git", commonDirPath: "/repo/.git")
        let wide = GitRepositoryService.minimapCacheKey(for: repo, limit: 800, targetMaxBuckets: 160)
        let narrow = GitRepositoryService.minimapCacheKey(for: repo, limit: 800, targetMaxBuckets: 80)
        #expect(wide != narrow)
        #expect(GitRepositoryService.minimapCacheKey(for: repo, limit: 800, targetMaxBuckets: 0).hasSuffix("|1"))
    }

    @Test("graph and minimap cache keys are worktree-specific")
    func graphAndMinimapCacheKeysAreWorktreeSpecific() {
        let common = "/repo/.git"
        let first = GitRepo(rootPath: "/repo/main", gitDirPath: "/repo/.git/worktrees/main", commonDirPath: common)
        let second = GitRepo(rootPath: "/repo/feature", gitDirPath: "/repo/.git/worktrees/feature", commonDirPath: common)

        #expect(GitRepositoryService.graphPageCacheKey(for: first, offset: 0, limit: 200) != GitRepositoryService.graphPageCacheKey(for: second, offset: 0, limit: 200))
        #expect(GitRepositoryService.minimapCacheKey(for: first, limit: 800, targetMaxBuckets: 120) != GitRepositoryService.minimapCacheKey(for: second, limit: 800, targetMaxBuckets: 120))
    }

    @Test("contributor stats include commits reachable only from remote refs", .enabled(if: GitAnalyzer().isAvailable))
    func contributorStatsIncludeRemoteRefs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("git-contributors-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try run(["init", "-q", "-b", "main"], in: dir)
        try run(["config", "user.email", "me@example.com"], in: dir)
        try run(["config", "user.name", "Me"], in: dir)
        try run(["config", "commit.gpgsign", "false"], in: dir)
        try "hello\n".write(to: dir.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        try run(["add", "readme.md"], in: dir)
        try run(["commit", "-q", "-m", "Initial"], in: dir)
        let hash = try run(["rev-parse", "HEAD"], in: dir).trimmingCharacters(in: .whitespacesAndNewlines)
        try run(["update-ref", "refs/remotes/origin/main", hash], in: dir)
        try run(["checkout", "--detach", "-q", hash], in: dir)
        try run(["branch", "-D", "main"], in: dir)

        let analyzer = GitAnalyzer()
        let repo = GitRepo(rootPath: dir.path)
        let contributors = analyzer.contributorStats(for: repo)

        #expect(contributors.first == GitContributorStat(name: "Me", email: "me@example.com", commitCount: 1, share: 1))
    }

    @Test("latest commit date honors author filter", .enabled(if: GitAnalyzer().isAvailable))
    func latestCommitDateHonorsAuthorFilter() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("git-latest-author-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try run(["init", "-q", "-b", "main"], in: dir)
        try run(["config", "user.email", "me@example.com"], in: dir)
        try run(["config", "user.name", "Me"], in: dir)
        try run(["config", "commit.gpgsign", "false"], in: dir)

        try "one\n".write(to: dir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try run(["add", "file.txt"], in: dir)
        try run(["commit", "-q", "-m", "Mine old"], in: dir, environment: gitDateEnvironment(1_700_000_000))

        try "two\n".write(to: dir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try run(["commit", "-q", "-am", "Mine new"], in: dir, environment: gitDateEnvironment(1_700_002_000))

        try "other\n".write(to: dir.appendingPathComponent("other.txt"), atomically: true, encoding: .utf8)
        try run(["add", "other.txt"], in: dir)
        try run(
            ["-c", "user.email=other@example.com", "-c", "user.name=Other", "commit", "-q", "-m", "Other newest"],
            in: dir,
            environment: gitDateEnvironment(1_700_003_000)
        )

        let analyzer = GitAnalyzer()
        let repo = try #require(analyzer.repo(forCwd: dir.path))

        #expect(analyzer.latestCommitDate(in: repo, authorEmail: "me@example.com") == Date(timeIntervalSince1970: 1_700_002_000))
        #expect(analyzer.latestCommitDate(in: repo, authorEmail: "other@example.com") == Date(timeIntervalSince1970: 1_700_003_000))
    }

    @Test("contributor shortlog parser groups committers")
    func contributorShortlogParserGroupsCommitters() {
        let rows = GitAnalyzer.parseContributorShortlog("""
             12\tAda Lovelace <ada@example.com>
              3\tGrace <grace@example.com>
              1\tAda Lovelace <ada@example.com>
        """)

        #expect(rows == [
            GitContributorStat(name: "Ada Lovelace", email: "ada@example.com", commitCount: 13, share: 13.0 / 16.0),
            GitContributorStat(name: "Grace", email: "grace@example.com", commitCount: 3, share: 3.0 / 16.0),
        ])
    }

    @Test("graph and contributors include detached HEAD without refs", .enabled(if: GitAnalyzer().isAvailable))
    func graphAndContributorsIncludeDetachedHeadWithoutRefs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("git-detached-head-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try run(["init", "-q", "-b", "main"], in: dir)
        try run(["config", "user.email", "me@example.com"], in: dir)
        try run(["config", "user.name", "Me"], in: dir)
        try run(["config", "commit.gpgsign", "false"], in: dir)
        try "hello\n".write(to: dir.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        try run(["add", "readme.md"], in: dir)
        try run(["commit", "-q", "-m", "Initial"], in: dir)
        let hash = try run(["rev-parse", "HEAD"], in: dir).trimmingCharacters(in: .whitespacesAndNewlines)
        try run(["checkout", "--detach", "-q", hash], in: dir)
        try run(["branch", "-D", "main"], in: dir)

        let analyzer = GitAnalyzer()
        let repo = GitRepo(rootPath: dir.path)
        let page = try #require(analyzer.graphPage(for: repo, offset: 0, limit: 10))
        let contributors = analyzer.contributorStats(for: repo)

        #expect(page.commits.map(\.hash) == [hash])
        #expect(contributors.first == GitContributorStat(name: "Me", email: "me@example.com", commitCount: 1, share: 1))
    }

    @Test("annotated tags map to peeled commit hash", .enabled(if: GitAnalyzer().isAvailable))
    func annotatedTagsMapToCommitHash() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("git-annotated-tag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try run(["init", "-q", "-b", "main"], in: dir)
        try run(["config", "user.email", "me@example.com"], in: dir)
        try run(["config", "user.name", "Me"], in: dir)
        try run(["config", "commit.gpgsign", "false"], in: dir)
        try "hello\n".write(to: dir.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        try run(["add", "readme.md"], in: dir)
        try run(["commit", "-q", "-m", "Initial"], in: dir)
        try run(["tag", "-a", "v-annotated", "-m", "v-annotated"], in: dir)
        let hash = try run(["rev-parse", "HEAD"], in: dir).trimmingCharacters(in: .whitespacesAndNewlines)

        let refs = GitAnalyzer().refsByHash(for: GitRepo(rootPath: dir.path))

        #expect(refs[hash]?.contains(GitRef(kind: .tag, name: "v-annotated")) == true)
    }

    // MARK: helpers

    @discardableResult
    private func run(_ args: [String], in dir: URL, environment: [String: String] = [:]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: GitAnalyzer.gitPath)
        p.arguments = ["-C", dir.path] + args
        p.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func gitDateEnvironment(_ timestamp: Int) -> [String: String] {
        let value = "@\(timestamp)"
        return [
            "GIT_AUTHOR_DATE": value,
            "GIT_COMMITTER_DATE": value,
        ]
    }
}
