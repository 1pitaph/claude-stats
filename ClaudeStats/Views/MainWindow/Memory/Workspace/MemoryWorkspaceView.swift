import SwiftUI

struct MemoryWorkspaceView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var store: MemoryStore

    private let horizontalInset: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await store.loadIfNeeded(sessions: env.store.sessions)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MEMORY")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Text(title(for: store.section))
                    .font(.sora(24, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle(for: store.section))
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                WorkspaceMiniStat(value: "\(store.codeHealth?.memoryCount ?? 0)", label: "active")
                WorkspaceMiniStat(value: "\(store.review.totalCount)", label: "review")
                if store.isCodeMemoryLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task { await store.refreshCodeMemoryStatus(sessions: env.store.sessions) }
                } label: {
                    Label("Refresh", systemImage: AppIcon.Action.sync)
                }
                .controlSize(.small)
                .disabled(store.isCodeMemoryLoading)
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var content: some View {
        switch store.section {
        case .search:
            MemorySearchView(store: store)
        case .memories:
            MemoryLibraryView(store: store)
        case .graph:
            MemoryGraphWorkspaceView(store: store)
        case .review:
            MemoryReviewView(store: store)
        case .settings:
            MemorySettingsView(store: store)
        }
    }

    private func title(for section: MemoryWorkspaceSection) -> String {
        switch section {
        case .search: "Search"
        case .memories: "Memories"
        case .graph: "Graph"
        case .review: "Review"
        case .settings: "Settings"
        }
    }

    private func subtitle(for section: MemoryWorkspaceSection) -> String {
        switch section {
        case .search: "Canonical memory, graph facts, sources, and trace provenance."
        case .memories: "Active project and module memory library."
        case .graph: "Temporal knowledge graph of entities, facts, and provenance."
        case .review: "Human gate for proposals, conflicts, and low-confidence facts."
        case .settings: "Local sidecar, adapters, projection jobs, and shell capture."
        }
    }
}
