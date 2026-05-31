import SwiftUI

/// The full detail of one commit — reached via the **MORE** button in
/// ``GitGraphView``'s expanded row. Shows concise metadata (hash, author,
/// dates), the full commit message, and the changed files grouped by directory
/// (each group collapsible). Double-clicking a file opens its diff in
/// ``FileDiffView``. Shells out to `git show --numstat` via ``GitAnalyzer``.
struct CommitDetailView: View {
    let repo: GitRepo
    let hash: String
    var onBack: () -> Void
    private let isPreview: Bool

    @State private var detail: CommitDetail?
    @State private var isLoading = false
    @State private var collapsed: Set<String> = []
    @State private var diffPath: String?

    init(repo: GitRepo, hash: String, onBack: @escaping () -> Void) {
        self.repo = repo
        self.hash = hash
        self.onBack = onBack
        self.isPreview = false
    }

    #if DEBUG
    /// Preview-only: starts already populated so the Xcode canvas renders the
    /// metadata and file groups — the live view shells out to `git`.
    init(detail: CommitDetail, repo: GitRepo? = nil, onBack: @escaping () -> Void = {}) {
        self.repo = repo ?? GitRepo(rootPath: "/Users/dev/projects/aurora")
        self.hash = detail.hash
        self.onBack = onBack
        self.isPreview = true
        _detail = State(initialValue: detail)
    }
    #endif

    var body: some View {
        if let diffPath {
            #if DEBUG
            if isPreview {
                FileDiffView(diff: .preview(path: diffPath), onBack: { self.diffPath = nil })
            } else {
                FileDiffView(repo: repo, hash: hash, path: diffPath, onBack: { self.diffPath = nil })
            }
            #else
            FileDiffView(repo: repo, hash: hash, path: diffPath, onBack: { self.diffPath = nil })
            #endif
        } else {
            detailBody
        }
    }

    private var detailBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            content
        }
        .task(id: "\(repo.id)|\(hash)") {
            if isPreview { return }
            isLoading = true
            let r = repo, h = hash
            let loaded = await GitRepositoryService.shared.commitDetail(for: h, in: r)
            guard !Task.isCancelled, repo.id == r.id, hash == h else { return }
            detail = loaded
            isLoading = false
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            GitBackButton(help: "Back to the commit graph", action: onBack)

            Text((detail?.abbreviatedHash ?? String(hash.prefix(7))).uppercased())
                .font(.sora(13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if isLoading { ProgressView().controlSize(.mini) }
            Spacer()
            if let d = detail, !d.files.isEmpty {
                Text("+\(d.totalInsertions)")
                    .font(.sora(9).monospacedDigit()).foregroundStyle(GitPalette.add)
                Text("−\(d.totalDeletions)")
                    .font(.sora(9).monospacedDigit()).foregroundStyle(GitPalette.del)
                Text("· \(d.files.count) file\(d.files.count == 1 ? "" : "s")")
                    .font(.sora(9).monospacedDigit()).foregroundStyle(Color.stxMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let detail {
            AppScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    metadataBlock(detail)
                    messageBlock(detail)
                    filesBlock(detail)
                }
                .padding(14)
            }
        } else if isLoading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 80)
        } else {
            Text("Couldn't load this commit.")
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    private func metadataBlock(_ d: CommitDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            metaRow("Commit", d.hash, mono: true, selectable: true)
            metaRow("Author", "\(d.authorName) <\(d.authorEmail)>")
            metaRow("Authored", Format.shortDate(d.authorDate), mono: true)
            if d.commitDate != d.authorDate {
                metaRow("Committed", "\(Format.shortDate(d.commitDate))" +
                        (d.committerEmail == d.authorEmail ? "" : " · \(d.committerName) <\(d.committerEmail)>"), mono: true)
            }
            if d.isMerge {
                metaRow("Parents", d.parentHashes.map { String($0.prefix(7)) }.joined(separator: ", "), mono: true)
            }
        }
        .stxPanel(12)
    }

    private func metaRow(_ label: String, _ value: String, mono: Bool = false, selectable: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(.sora(9)).tracking(0.4)
                .foregroundStyle(Color.stxMuted)
                .frame(width: 72, alignment: .trailing)
            Group {
                if selectable {
                    Text(value).textSelection(.enabled)
                } else {
                    Text(value)
                }
            }
            .font(mono ? .sora(10).monospacedDigit() : .sora(10))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .truncationMode(.middle)
            .help(value)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func messageBlock(_ d: CommitDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TitleSanitizer.sanitize(d.subject) ?? d.subject)
                .font(.sora(12, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !d.body.isEmpty {
                Text(d.body)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private struct FileGroup: Identifiable {
        let directory: String
        let files: [CommitFileChange]
        var id: String { directory }
        var insertions: Int { files.lazy.filter { !$0.isBinary }.reduce(0) { $0 + $1.insertions } }
        var deletions: Int { files.lazy.filter { !$0.isBinary }.reduce(0) { $0 + $1.deletions } }
    }

    private func grouped(_ files: [CommitFileChange]) -> [FileGroup] {
        Dictionary(grouping: files, by: { $0.directory })
            .map { FileGroup(directory: $0.key.isEmpty ? "/" : $0.key, files: $0.value) }
            .sorted { $0.directory.localizedCaseInsensitiveCompare($1.directory) == .orderedAscending }
    }

    @ViewBuilder
    private func filesBlock(_ d: CommitDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("FILES CHANGED")
                    .font(.sora(13, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(.primary)
                Spacer()
                if !d.files.isEmpty {
                    Text("DOUBLE-CLICK FOR DIFF")
                        .font(.sora(8)).tracking(0.6)
                        .foregroundStyle(Color.stxMuted)
                }
            }
            if d.files.isEmpty {
                Text(d.isMerge ? "Merge commit — no file diff." : "No file changes.")
                    .font(.sora(10)).foregroundStyle(Color.stxMuted.opacity(0.7))
            } else {
                ForEach(grouped(d.files)) { group in
                    fileGroupView(group)
                }
            }
        }
    }

    @ViewBuilder
    private func fileGroupView(_ group: FileGroup) -> some View {
        let isCollapsed = collapsed.contains(group.directory)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isCollapsed { collapsed.remove(group.directory) } else { collapsed.insert(group.directory) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: AppIcon.Navigation.disclosure)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.stxMuted)
                        .frame(width: 10)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    Text(group.directory)
                        .font(.sora(10, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1).truncationMode(.middle)
                    Text("\(group.files.count)")
                        .font(.sora(8).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                    Spacer(minLength: 8)
                    Text("+\(group.insertions)").font(.sora(9).monospacedDigit()).foregroundStyle(GitPalette.add)
                    Text("−\(group.deletions)").font(.sora(9).monospacedDigit()).foregroundStyle(GitPalette.del)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            StxRule().opacity(0.5)
            if !isCollapsed {
                ForEach(group.files) { fc in
                    FileRow(change: fc) { diffPath = fc.path }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .appSurface(.compactCard(radius: 3, fillOpacity: 0.5, cornerStyle: .circular), padding: nil)
    }
}

/// One changed file inside a directory group. A double-click opens its diff.
private struct FileRow: View {
    let change: CommitFileChange
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if change.isBinary {
                Text("bin").font(.sora(9).monospacedDigit()).foregroundStyle(Color.stxMuted)
                    .frame(width: 56, alignment: .leading)
            } else {
                HStack(spacing: 4) {
                    Text("+\(change.insertions)").font(.sora(9).monospacedDigit()).foregroundStyle(GitPalette.add)
                    Text("−\(change.deletions)").font(.sora(9).monospacedDigit()).foregroundStyle(GitPalette.del)
                }
                .frame(width: 56, alignment: .leading)
            }
            churnBar
            Text(change.fileName)
                .font(.sora(10)).foregroundStyle(.primary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Image(systemName: AppIcon.Git.code)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.stxMuted)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
        .help("Double-click to view the diff of \(change.path)")
    }

    @ViewBuilder
    private var churnBar: some View {
        let total = max(change.insertions, 0) + max(change.deletions, 0)
        GeometryReader { geo in
            HStack(spacing: 1) {
                if change.isBinary || total == 0 {
                    Rectangle().fill(Color.stxMuted.opacity(0.25))
                } else {
                    Rectangle().fill(GitPalette.add)
                        .frame(width: geo.size.width * CGFloat(change.insertions) / CGFloat(total))
                    Rectangle().fill(GitPalette.del)
                }
            }
        }
        .frame(width: 28, height: 5)
        .clipShape(Capsule())
    }
}

#if DEBUG
#Preview("Commit detail") {
    CommitDetailView(detail: .preview())
        .environment(AppEnvironment.preview())
        .frame(width: 420, height: 560)
        .background(Color.stxBackground)
}
#endif
