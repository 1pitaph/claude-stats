#if DEBUG
import Foundation

// Sample data + factory used by the `#Preview` blocks throughout the app.
// Compiled out of release builds.

extension AppEnvironment {
    /// An environment wired with canned data (or empty), with preferences
    /// stored in a throwaway suite so previews don't touch real defaults.
    static func preview(populated: Bool = true) -> AppEnvironment {
        let pricing = ModelPricing.fallback
        let registry = ProviderRegistry(pricing: pricing)
        let store = SessionStore(registry: registry, pricing: pricing)
        store.loadPreviewSessions(populated ? Session.previewSamples(pricing: pricing) : [])
        // Fresh, throwaway defaults so previews always reflect the code defaults.
        let suiteName = "com.claudestats.preview"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return AppEnvironment(
            pricing: pricing,
            preferences: Preferences(defaults: defaults),
            providerRegistry: registry,
            store: store,
            appleSignIn: AppleSignInStore(defaults: defaults, entitlementChecker: { false })
        )
    }
}

extension Session {
    static func previewSamples(pricing: ModelPricing = .fallback) -> [Session] {
        func usage(_ i: Int, _ o: Int, _ cr: Int, _ c5: Int = 0) -> TokenUsage {
            TokenUsage(inputTokens: i, outputTokens: o, cacheReadTokens: cr,
                       cacheCreation5mTokens: c5, cacheCreation1hTokens: 0)
        }
        func model(_ name: String, _ count: Int, _ u: TokenUsage) -> ModelUsage {
            ModelUsage(model: name, messageCount: count, usage: u, pricing: pricing)
        }
        let now = Date.now
        let cal = Calendar.current
        func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: now) ?? now }
        func dayStart(_ n: Int) -> Date { cal.startOfDay(for: daysAgo(n)) }
        func at(_ d: Int, _ hour: Double) -> Date {
            dayStart(d).addingTimeInterval(hour * 3_600)
        }
        func interval(_ d: Int, _ startHour: Double, _ endHour: Double) -> DateInterval {
            DateInterval(start: at(d, startHour), end: at(d, endHour))
        }
        /// `(daysAgo, hour, model, usage)` → an hourly ``ModelBucket``.
        func bucket(_ d: Int, _ h: Int, _ name: String, _ u: TokenUsage) -> ModelBucket {
            let start = cal.date(byAdding: .hour, value: h, to: dayStart(d)) ?? dayStart(d)
            return ModelBucket(model: name, start: start, usage: u)
        }

        return [
            Session(
                id: "-Users-dev-projects-aurora::a1", externalID: "a1", provider: .claude,
                projectDirectoryName: "-Users-dev-projects-aurora",
                filePath: "/Users/dev/.claude/projects/-Users-dev-projects-aurora/a1.jsonl",
                cwd: "/Users/dev/projects/aurora", lastModified: daysAgo(0), fileSize: 412_000,
                stats: SessionStats(
                    title: "Wire up the websocket reconnect logic",
                    messageCount: 84, firstActivity: daysAgo(1), lastActivity: daysAgo(0),
                    models: [
                        model("claude-opus-4-7", 41, usage(120_000, 38_000, 1_400_000, 90_000)),
                        model("claude-haiku-4-5", 12, usage(8_000, 2_000, 50_000)),
                    ],
                    timeline: [
                        bucket(1, 14, "claude-opus-4-7", usage(20_000, 6_000, 240_000, 15_000)),
                        bucket(1, 15, "claude-opus-4-7", usage(28_000, 8_000, 300_000, 18_000)),
                        bucket(1, 16, "claude-opus-4-7", usage(12_000, 4_000, 160_000, 12_000)),
                        bucket(1, 15, "claude-haiku-4-5", usage(3_000, 800, 18_000)),
                        bucket(0, 9, "claude-opus-4-7", usage(18_000, 6_000, 200_000, 12_000)),
                        bucket(0, 10, "claude-opus-4-7", usage(30_000, 10_000, 320_000, 20_000)),
                        bucket(0, 11, "claude-opus-4-7", usage(20_000, 6_000, 230_000, 13_000)),
                        bucket(0, 9, "claude-haiku-4-5", usage(2_000, 600, 14_000)),
                        bucket(0, 11, "claude-haiku-4-5", usage(3_000, 600, 18_000)),
                    ],
                    activityIntervals: [
                        interval(1, 14, 16.25),
                        interval(0, 9, 11.5),
                    ]
                )
            ),
            Session(
                id: "-Users-dev-projects-ledger::b2", externalID: "b2", provider: .claude,
                projectDirectoryName: "-Users-dev-projects-ledger",
                filePath: "/Users/dev/.claude/projects/-Users-dev-projects-ledger/b2.jsonl",
                cwd: "/Users/dev/projects/ledger", lastModified: daysAgo(2), fileSize: 96_000,
                stats: SessionStats(
                    title: "Fix the off-by-one in pagination",
                    messageCount: 22, firstActivity: daysAgo(2), lastActivity: daysAgo(2),
                    models: [model("claude-sonnet-4-6", 11, usage(34_000, 9_500, 210_000, 12_000))],
                    timeline: [
                        bucket(2, 13, "claude-sonnet-4-6", usage(16_000, 4_500, 100_000, 6_000)),
                        bucket(2, 14, "claude-sonnet-4-6", usage(18_000, 5_000, 110_000, 6_000)),
                    ],
                    activityIntervals: [
                        interval(2, 13, 14.5),
                    ]
                )
            ),
            Session(
                id: "-Users-dev-projects-aurora::c3", externalID: "c3", provider: .claude,
                projectDirectoryName: "-Users-dev-projects-aurora",
                filePath: "/Users/dev/.claude/projects/-Users-dev-projects-aurora/c3.jsonl",
                cwd: "/Users/dev/projects/aurora", lastModified: daysAgo(9), fileSize: 250_000,
                stats: SessionStats(
                    title: "Migrate the settings screen to the new design",
                    messageCount: 53, firstActivity: daysAgo(10), lastActivity: daysAgo(9),
                    models: [
                        model("claude-opus-4-7", 26, usage(70_000, 24_000, 880_000, 50_000)),
                        model("claude-sonnet-4-6", 9, usage(12_000, 3_000, 60_000, 4_000)),
                    ],
                    timeline: [
                        bucket(10, 17, "claude-opus-4-7", usage(30_000, 10_000, 380_000, 20_000)),
                        bucket(10, 18, "claude-sonnet-4-6", usage(12_000, 3_000, 60_000, 4_000)),
                        bucket(9, 10, "claude-opus-4-7", usage(40_000, 14_000, 500_000, 30_000)),
                    ],
                    activityIntervals: [
                        interval(10, 17, 18.2),
                        interval(9, 10, 11),
                    ]
                )
            ),
            Session(
                id: "codex::d4", externalID: "d4", provider: .codex,
                projectDirectoryName: "/Users/dev/projects/tag",
                filePath: "/Users/dev/.codex/sessions/2026/01/01/rollout-2026-01-01T10-00-00-d4.jsonl",
                cwd: "/Users/dev/projects/tag", lastModified: daysAgo(1), fileSize: 180_000,
                stats: SessionStats(
                    title: "Tidy up the markdown renderer",
                    messageCount: 31, firstActivity: daysAgo(1), lastActivity: daysAgo(1),
                    models: [model("gpt-5.1-codex", 14, usage(40_000, 6_000, 120_000))],
                    timeline: [
                        bucket(1, 11, "gpt-5.1-codex", usage(22_000, 3_000, 70_000)),
                        bucket(1, 12, "gpt-5.1-codex", usage(18_000, 3_000, 50_000)),
                    ],
                    activityIntervals: [
                        interval(1, 11, 12.4),
                    ]
                )
            ),
        ]
    }

    static var previewSamples: [Session] { previewSamples() }
}

extension GitGraph {
    /// A small hand-built commit DAG (linear `main` with one feature branch
    /// merged back in, plus a tag) so the `GitGraphView` `#Preview` shows the
    /// real lane/merge rendering — the live view shells out to `git log`.
    static func preview() -> GitGraph {
        let repo = GitRepo(rootPath: "/Users/dev/projects/aurora")
        let cal = Calendar.current
        let now = Date.now
        func at(_ hoursAgo: Int) -> Date { cal.date(byAdding: .hour, value: -hoursAgo, to: now) ?? now }

        func commit(_ hash: String, parents: [String], _ subject: String,
                    _ hoursAgo: Int, mine: Bool = true, refs: [GitRef] = []) -> GraphCommit {
            GraphCommit(hash: hash, parentHashes: parents, refs: refs,
                        author: mine ? "Ada Lovelace" : "Grace Hopper",
                        authorEmail: mine ? "ada@example.com" : "grace@example.com",
                        date: at(hoursAgo), subject: subject)
        }

        // newest first, --date-order; parents always appear below their children
        let commits: [GraphCommit] = [
            commit("a1b2c3d4e5f60718", parents: ["b2c3d4e5f6071829", "c3d4e5f607182930"],
                   "Merge branch 'feature/reconnect'", 2,
                   refs: [GitRef(kind: .head, name: "HEAD"), GitRef(kind: .branch, name: "main")]),
            commit("c3d4e5f607182930", parents: ["d4e5f60718293041"],
                   "fix: drop stale subscriptions on close", 5, mine: false,
                   refs: [GitRef(kind: .branch, name: "feature/reconnect")]),
            commit("b2c3d4e5f6071829", parents: ["e5f6071829304152"],
                   "chore: bump design-tokens to 2.3.0", 9),
            commit("d4e5f60718293041", parents: ["f607182930415263"],
                   "feat: websocket reconnect with backoff", 14, mine: false),
            commit("e5f6071829304152", parents: ["f607182930415263"],
                   "docs: document the transport layer", 20),
            commit("f607182930415263", parents: ["0718293041526374"],
                   "feat: initial websocket transport", 30,
                   refs: [GitRef(kind: .tag, name: "v1.0")]),
            commit("0718293041526374", parents: [],
                   "chore: project scaffolding", 48),
        ]
        return GitGraph(repo: repo, commits: commits, truncated: false)
    }

    /// Sample per-commit file churn for a couple of the `preview()` commits, so
    /// expanding those rows shows the detail block.
    static func previewFileChanges() -> [String: [CommitFileChange]] {
        [
            "d4e5f60718293041": [
                CommitFileChange(path: "Sources/Net/ConnectionCoordinator.swift", insertions: 188, deletions: 12),
                CommitFileChange(path: "Sources/Net/Reconnect.swift", insertions: 96, deletions: 0),
                CommitFileChange(path: "Tests/ReconnectTests.swift", insertions: 124, deletions: 6),
            ],
            "f607182930415263": [
                CommitFileChange(path: "Sources/Net/Transport.swift", insertions: 410, deletions: 0),
                CommitFileChange(path: "Resources/architecture.png", insertions: -1, deletions: -1),
            ],
            "a1b2c3d4e5f60718": [],
        ]
    }
}

extension CommitDetail {
    /// Default sample files for the `#Preview`s, exercising directory grouping
    /// and a binary file.
    static let previewFiles: [CommitFileChange] = [
        CommitFileChange(path: "Sources/Net/ConnectionCoordinator.swift", insertions: 188, deletions: 12),
        CommitFileChange(path: "Sources/Net/Reconnect.swift", insertions: 96, deletions: 0),
        CommitFileChange(path: "Sources/Net/Backoff.swift", insertions: 54, deletions: 4),
        CommitFileChange(path: "Tests/ReconnectTests.swift", insertions: 124, deletions: 6),
        CommitFileChange(path: "Resources/state-machine.png", insertions: -1, deletions: -1),
        CommitFileChange(path: "CHANGELOG.md", insertions: 3, deletions: 0),
    ]

    /// A sample commit (the `feat: websocket reconnect with backoff` commit from
    /// ``GitGraph/preview()``) for the ``CommitDetailView`` `#Preview`.
    static func preview() -> CommitDetail {
        let cal = Calendar.current
        let authored = cal.date(byAdding: .hour, value: -14, to: .now) ?? .now
        return CommitDetail(
            hash: "d4e5f607182930415263748596a7b8c9d0e1f203",
            abbreviatedHash: "d4e5f60",
            parentHashes: ["f607182930415263"],
            authorName: "Grace Hopper", authorEmail: "grace@example.com", authorDate: authored,
            committerName: "Ada Lovelace", committerEmail: "ada@example.com",
            commitDate: authored.addingTimeInterval(420),
            subject: "feat: websocket reconnect with backoff",
            body: "Reconnect with exponential backoff and full jitter, capped at 30s.\n\nDrops stale subscriptions on close so a reconnect doesn't double-deliver.",
            files: previewFiles
        )
    }

    /// Build a `CommitDetail` from a ``GraphCommit`` for previews — used when the
    /// ``GitGraphView`` preview drills into a commit (the live view shells out to
    /// `git show`). Falls back to ``previewFiles`` when no churn was supplied.
    static func preview(from commit: GraphCommit, files: [CommitFileChange]) -> CommitDetail {
        CommitDetail(
            hash: commit.hash,
            abbreviatedHash: String(commit.hash.prefix(7)),
            parentHashes: commit.parentHashes,
            authorName: commit.author, authorEmail: commit.authorEmail, authorDate: commit.date,
            committerName: commit.author, committerEmail: commit.authorEmail, commitDate: commit.date,
            subject: commit.subject,
            body: "Sample commit body for the Xcode preview — the live view loads the real message via `git show`.",
            files: commit.isMerge ? [] : (files.isEmpty ? previewFiles : files)
        )
    }
}

extension FileDiff {
    /// A small hand-written unified diff for the ``FileDiffView`` `#Preview` (and
    /// the previewed double-click flow from ``CommitDetailView``).
    static func preview(path: String = "Sources/Net/Reconnect.swift") -> FileDiff {
        FileDiff(path: path, isBinary: false, lines: GitAnalyzer.parseUnifiedDiff("""
        diff --git a/\(path) b/\(path)
        index 1a2b3c4..5d6e7f8 100644
        --- a/\(path)
        +++ b/\(path)
        @@ -12,7 +12,11 @@ final class Reconnector {
             private let maxDelay: TimeInterval = 30
        -    private var attempt = 0
        +    private var attempt = 0 { didSet { onAttemptChange?(attempt) } }
        +    var onAttemptChange: ((Int) -> Void)?

             func nextDelay() -> TimeInterval {
        -        let base = pow(2, Double(attempt))
        +        let base = min(pow(2, Double(attempt)), maxDelay)
        +        attempt += 1
                 return base + Double.random(in: 0..<base)
             }
         }
        """))
    }
}
#endif
