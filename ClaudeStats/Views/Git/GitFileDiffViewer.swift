import SwiftUI

struct GitFileDiffRequest: Identifiable, Hashable {
    let repo: GitRepo
    let hash: String
    let parentHash: String?
    let abbreviatedHash: String
    let path: String

    var id: String {
        "\(repo.id)|\(hash)|\(path)"
    }

    var oldLabel: String {
        parentHash.map { String($0.prefix(7)) } ?? "root"
    }

    var newLabel: String {
        abbreviatedHash.isEmpty ? String(hash.prefix(7)) : abbreviatedHash
    }
}

struct GitFileDiffViewer: View {
    let request: GitFileDiffRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @State private var diff: FileDiff?
    @State private var structuredDiff: StructuredFileDiff?
    @State private var isLoading = false
    @State private var didFail = false
    @State private var mode: DiffViewMode = .fluid

    var body: some View {
        VStack(spacing: 0) {
            header
            StxRule()
            content
        }
        .frame(minWidth: 1100, idealWidth: 1180, minHeight: 720, idealHeight: 780)
        .background(AppSurface.panelFill)
        .task(id: request.id) {
            await loadDiff()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: AppIcon.Action.close)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close diff")

            VStack(alignment: .leading, spacing: 4) {
                Text(request.path)
                    .font(.sora(13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(request.path)
                HStack(spacing: 8) {
                    refPill(label: "A", value: request.oldLabel)
                    refPill(label: "B", value: request.newLabel)
                    Text(request.repo.displayName)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            if isLoading {
                ProgressView()
                    .controlSize(.mini)
            }

            PillSegmentedBar(
                DiffViewMode.allCases,
                selection: $mode,
                style: .toolbarModeSwitch,
                help: { "Show \( $0.title ) diff" },
                accessibilityLabel: { "\($0.title) diff mode" }
            ) { option, _ in
                Label(option.title, systemImage: option.systemImage)
                    .labelStyle(.titleAndIcon)
            }
            .frame(width: 304)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && diff == nil {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if didFail {
            GitDiffViewerEmptyState("Couldn't load the diff.")
        } else if let diff {
            if diff.isBinary {
                GitDiffViewerEmptyState("Binary file — no textual diff.")
            } else if let structured = structuredDiff {
                if structured.isEmpty {
                    GitDiffViewerEmptyState("No changes to show.")
                } else {
                    GitDiffRendererView(
                        diff: structured,
                        mode: mode,
                        granularity: env.preferences.gitDiffBlockGranularity
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                GitDiffViewerEmptyState("No changes to show.")
            }
        } else {
            GitDiffViewerEmptyState("No changes to show.")
        }
    }

    private func loadDiff() async {
        isLoading = true
        didFail = false
        let repo = request.repo
        let hash = request.hash
        let path = request.path
        diff = nil
        structuredDiff = nil
        let loaded = await GitRepositoryService.shared.fileDiff(for: hash, path: path, in: repo)
        guard !Task.isCancelled, request.repo == repo, request.hash == hash, request.path == path else { return }
        diff = loaded
        structuredDiff = loaded.flatMap { $0.isBinary ? nil : StructuredFileDiff.build(from: $0) }
        didFail = loaded == nil
        isLoading = false
    }

    private func refPill(label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.sora(8, weight: .semibold))
                .foregroundStyle(Color.stxAccent)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.stxAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(value)
                .font(.sora(10).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
        }
    }
}

private struct GitDiffViewerEmptyState: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.sora(11))
            .foregroundStyle(Color.stxMuted.opacity(0.82))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("Git diff viewer") {
    GitFileDiffViewer(
        request: GitFileDiffRequest(
            repo: GitRepo(rootPath: "/Users/dev/projects/aurora"),
            hash: "9f5743e",
            parentHash: "64590d7",
            abbreviatedHash: "9f5743e",
            path: ".github/workflows/release.yml"
        )
    )
    .frame(width: 1180, height: 780)
    .background(Color.stxBackground)
    .environment(AppEnvironment.preview())
}
#endif
