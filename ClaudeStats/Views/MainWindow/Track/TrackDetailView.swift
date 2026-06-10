import SwiftUI

struct TrackDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var store: TrackStore
    let section: TrackSection
    private let horizontalInset: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            filterBar
            StxRule()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await store.loadIfNeeded(sessions: env.store.sessions) { session in
                await env.store.executedCommands(for: session)
            }
        }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in
            Task {
                await store.refresh(sessions: env.store.sessions) { session in
                    await env.store.executedCommands(for: session)
                }
            }
        }
        .alert("Track", isPresented: errorPresented) {
            Button("OK") { store.clearError() }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TRACK")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Text(section.detailTitle)
                    .font(.sora(24, weight: .semibold))
                    .lineLimit(1)
                Text(section.detailDescription)
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            headerMetric("\(store.snapshot.activeCount)", "Active")
            headerMetric("\(store.snapshot.pendingApprovalCount)", "Waiting")
            headerMetric("\(store.snapshot.highConfidenceEventCount)", "Hook events")

            Button {
                Task {
                    await store.refresh(sessions: env.store.sessions) { session in
                        await env.store.executedCommands(for: session)
                    }
                }
            } label: {
                Image(systemName: AppIcon.Action.refresh)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(.plain)
            .help("Refresh Track")
            .disabled(store.isLoading)

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }

    private func headerMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.sora(16, weight: .semibold).monospacedDigit())
            Text(label)
                .font(.sora(9, weight: .medium))
                .foregroundStyle(Color.stxMuted)
        }
        .frame(minWidth: 74, alignment: .trailing)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("All statuses") { store.statusFilter = nil }
                Divider()
                ForEach(TrackStatusFilterItem.allCases) { item in
                    Button(item.status.title) { store.statusFilter = item.status }
                }
            } label: {
                filterLabel(title: store.statusFilter?.title ?? "All statuses", symbol: AppIcon.Filter.filter)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Menu {
                Button("All sources") { store.sourceFilter = nil }
                Divider()
                ForEach(TrackEventSourceFilterItem.allCases) { item in
                    Button(item.source.title) { store.sourceFilter = item.source }
                }
            } label: {
                filterLabel(title: store.sourceFilter?.title ?? "All sources", symbol: AppIcon.Resource.link)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            if store.statusFilter != nil || store.sourceFilter != nil || !store.searchText.isEmpty {
                Button("Clear") { store.clearFilters() }
                    .buttonStyle(.plain)
                    .font(.sora(11, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
            }

            Spacer(minLength: 8)

            Text("Updated \(store.snapshot.loadedAt == .distantPast ? "--" : Format.relativeDate(store.snapshot.loadedAt))")
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, 10)
    }

    private func filterLabel(title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
            Text(title)
                .font(.sora(11, weight: .medium))
        }
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var content: some View {
        TrackFlowWorkspace(store: store)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.clearError() } }
        )
    }
}

private struct TrackStatusFilterItem: Identifiable {
    let status: TrackStatus
    var id: String { status.rawValue }

    static let allCases: [TrackStatusFilterItem] = [
        .init(status: .waitingApproval),
        .init(status: .running),
        .init(status: .usingTool),
        .init(status: .recentlyActive),
        .init(status: .completed),
        .init(status: .failed),
    ]
}

private struct TrackEventSourceFilterItem: Identifiable {
    let source: TrackEventSource
    var id: String { source.rawValue }

    static let allCases: [TrackEventSourceFilterItem] = [
        .init(source: .hook),
        .init(source: .appServer),
        .init(source: .transcript),
        .init(source: .process),
        .init(source: .notification),
    ]
}

#if DEBUG
#Preview("Track detail") {
    TrackDetailView(store: TrackStore(), section: .flow)
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
        .background(Color.stxBackground)
}
#endif
