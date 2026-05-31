import SwiftUI

/// The commit DAG for one repository — gitk/GitLens-style: colored branch lanes
/// drawn per row, commit nodes, merge bends, ref pills, author initials, subject,
/// date. Reached by tapping a repo row in ``GitActivityView``; tapping a commit
/// row expands its per-file churn (`git show --numstat`, fetched lazily).
struct GitGraphView: View {
    let repo: GitRepo
    var onBack: () -> Void
    private let isPreview: Bool

    // Rail geometry — `rowHeight` must be fixed so each row's `Canvas` lines up.
    private static let rowHeight: CGFloat = 38
    private static let workingTreeRowHeight: CGFloat = 56
    private static let laneSpacing: CGFloat = 14
    private static let railPad: CGFloat = 18
    private static let nodeRadius: CGFloat = 3

    @State private var graph: GitGraph?
    @State private var layout: GraphLayout?
    @State private var isLoading = false
    @State private var limit = 200
    @State private var loadedLimit = 0
    @State private var expandedHash: String?
    @State private var fileChanges: [String: [CommitFileChange]] = [:]
    @State private var detailHash: String?

    init(repo: GitRepo, onBack: @escaping () -> Void) {
        self.repo = repo
        self.onBack = onBack
        self.isPreview = false
    }

    #if DEBUG
    /// Preview-only: starts already populated with a canned commit DAG (and
    /// optionally per-commit file churn) so the Xcode canvas renders the lanes,
    /// merges and detail rows — the live view shells out to `git`.
    init(previewGraph: GitGraph,
         fileChanges: [String: [CommitFileChange]] = [:],
         onBack: @escaping () -> Void = {}) {
        self.repo = previewGraph.repo
        self.onBack = onBack
        self.isPreview = true
        _graph = State(initialValue: previewGraph)
        _layout = State(initialValue: GraphLayout.build(previewGraph.commits))
        _fileChanges = State(initialValue: fileChanges)
    }
    #endif

    private var railWidth: CGFloat {
        rowGeometry.railWidth(maxColumn: layout?.maxColumn ?? 0)
    }
    private var rowGeometry: GitGraphRowGeometry {
        GitGraphRowGeometry(laneSpacing: Self.laneSpacing, railPad: Self.railPad)
    }
    private func laneColor(_ idx: Int) -> Color { Color.stxRamp[idx % Color.stxRamp.count] }

    var body: some View {
        if let detailHash {
            #if DEBUG
            if isPreview, let commit = graph?.commits.first(where: { $0.hash == detailHash }) {
                CommitDetailView(detail: .preview(from: commit, files: fileChanges[detailHash] ?? []),
                                 repo: repo, onBack: { self.detailHash = nil })
            } else {
                CommitDetailView(repo: repo, hash: detailHash, onBack: { self.detailHash = nil })
            }
            #else
            CommitDetailView(repo: repo, hash: detailHash, onBack: { self.detailHash = nil })
            #endif
        } else {
            graphBody
        }
    }

    private var graphBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            content
        }
        .task(id: [repo.id, "\(limit)"]) {
            if isPreview { return }
            if graph != nil, loadedLimit == limit { return }   // keep state when returning from a detail screen
            isLoading = true
            let r = repo
            let n = limit
            let page = await GitRepositoryService.shared.graphPage(for: r, offset: 0, limit: n)
            guard !Task.isCancelled, repo.id == r.id, limit == n else { return }
            let g = page.map {
                GitGraph(repo: $0.repo, commits: $0.commits, truncated: $0.hasMore, workingTree: $0.workingTree)
            }
            graph = g
            layout = g.map { GraphLayout.build($0.commits) }
            loadedLimit = n
            isLoading = false
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            GitBackButton(help: "Back to git overview", action: onBack)

            Text(repo.displayName.uppercased())
                .font(.sora(13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if isLoading { ProgressView().controlSize(.mini) }
            Spacer()
            if let g = graph {
                Text("\(g.commits.count)\(g.truncated ? "+" : "") commit\(g.commits.count == 1 ? "" : "s")")
                    .font(.sora(9).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                if g.workingTree.isDirty {
                    Text("\(g.workingTree.fileCount) modified")
                        .font(.sora(9).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }
                if g.truncated {
                    Button("More") { limit += 200 }
                        .buttonStyle(.plain)
                        .font(.sora(9, weight: .semibold))
                        .foregroundStyle(Color.stxAccent)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let graph, let layout, graph.workingTree.isDirty || !layout.rows.isEmpty {
            let hasWorkingTree = graph.workingTree.isDirty
            AppScrollView {
                LazyVStack(spacing: 0) {
                    if hasWorkingTree {
                        GitWorkingTreeRowView(
                            summary: graph.workingTree,
                            rowHeight: Self.workingTreeRowHeight,
                            geometry: rowGeometry,
                            nodeRadius: Self.nodeRadius,
                            railWidth: railWidth,
                            railColorIndex: layout.rows.first?.colorIndex ?? 0,
                            isSelected: false
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                expandedHash = nil
                            }
                        }
                    }
                    ForEach(layout.rows) { row in
                        VStack(spacing: 0) {
                            GitGraphRowView(row: row,
                                            rowHeight: Self.rowHeight,
                                            geometry: rowGeometry,
                                            nodeRadius: Self.nodeRadius,
                                            railWidth: railWidth,
                                            isSelected: expandedHash == row.id,
                                            connectsFromTop: hasWorkingTree && row.id == layout.rows.first?.id) {
                                toggle(row.commit.hash)
                            }
                            if expandedHash == row.id {
                                detail(for: row)
                            }
                        }
                    }
                }
            }
        } else if isLoading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 80)
        } else {
            Text("No commits to graph.")
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    /// The expanded detail block under a commit row. The left rail gutter draws
    /// the lanes that continue past this row as same-colored *dashed* verticals,
    /// so the graph reads as connected across the inserted block.
    @ViewBuilder
    private func detail(for row: GraphLayout.Row) -> some View {
        let commit = row.commit
        ZStack(alignment: .leading) {
            railContinuation(for: row).frame(width: railWidth)

            HStack(spacing: 0) {
                Color.clear
                    .frame(width: rowGeometry.contentLeading(for: row))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(commit.shortHash).font(.sora(9).monospacedDigit()).foregroundStyle(Color.stxAccent)
                        Text("\(commit.author) <\(commit.authorEmail)>")
                            .font(.sora(9)).foregroundStyle(Color.stxMuted).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Format.shortDate(commit.date)).font(.sora(9).monospacedDigit()).foregroundStyle(Color.stxMuted)
                    }
                    if let changes = fileChanges[commit.hash] {
                        if changes.isEmpty {
                            Text(commit.isMerge ? "Merge commit — no file diff." : "No file changes.")
                                .font(.sora(9)).foregroundStyle(Color.stxMuted.opacity(0.7))
                        } else {
                            ForEach(changes) { fc in
                                HStack(spacing: 6) {
                                    if fc.isBinary {
                                        Text("bin").font(.sora(9).monospacedDigit()).foregroundStyle(Color.stxMuted)
                                    } else {
                                        Text("+\(fc.insertions)").font(.sora(9).monospacedDigit()).foregroundStyle(GitPalette.add)
                                        Text("−\(fc.deletions)").font(.sora(9).monospacedDigit()).foregroundStyle(GitPalette.del)
                                    }
                                    Text(fc.path)
                                        .font(.sora(9)).foregroundStyle(.primary)
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    } else {
                        Text("Loading…").font(.sora(9)).foregroundStyle(Color.stxMuted.opacity(0.7))
                    }
                    HStack(spacing: 0) {
                        Spacer()
                        Button { detailHash = commit.hash } label: {
                            BracketBox(spacing: 4) {
                                Text("MORE").font(.sora(9, weight: .semibold)).tracking(0.8)
                                Image(systemName: AppIcon.Navigation.openForward).font(.system(size: 9, weight: .bold))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.stxAccent)
                        .help("Open the full commit detail")
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.trailing, 14)
        }
        .background(Color.primary.opacity(0.05))
    }

    private func railContinuation(for row: GraphLayout.Row) -> some View {
        Canvas { ctx, size in
            var seen = Set<Int>()
            var lanes: [(column: Int, colorIndex: Int)] = row.passThrough.map { ($0.column, $0.colorIndex) }
            lanes += row.edgesDown.map { ($0.toColumn, $0.colorIndex) }
            for lane in lanes where seen.insert(lane.column).inserted {
                var p = Path()
                p.move(to: CGPoint(x: rowGeometry.laneX(lane.column), y: 0))
                p.addLine(to: CGPoint(x: rowGeometry.laneX(lane.column), y: size.height))
                ctx.stroke(p, with: .color(laneColor(lane.colorIndex)),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [1.5, 3.5]))
            }
        }
    }

    private func toggle(_ hash: String) {
        let willExpand = expandedHash != hash
        withAnimation(.easeInOut(duration: 0.18)) {
            expandedHash = willExpand ? hash : nil
        }
        guard willExpand, fileChanges[hash] == nil else { return }
        if isPreview {
            withAnimation(.easeInOut(duration: 0.15)) { fileChanges[hash] = [] }
            return
        }
        let r = repo
        Task {
            let fc = await GitRepositoryService.shared.fileChanges(for: hash, in: r)
            withAnimation(.easeInOut(duration: 0.15)) { fileChanges[hash] = fc }
        }
    }
}

#if DEBUG
#Preview("Git graph") {
    GitGraphView(previewGraph: .preview(), fileChanges: GitGraph.previewFileChanges())
        .environment(AppEnvironment.preview())
        .frame(width: 420, height: 520)
        .background(Color.stxBackground)
}

#Preview("Git graph — empty") {
    GitGraphView(previewGraph: GitGraph(repo: GitRepo(rootPath: "/Users/dev/projects/empty"),
                                        commits: [], truncated: false))
        .environment(AppEnvironment.preview())
        .frame(width: 420, height: 520)
        .background(Color.stxBackground)
}
#endif
