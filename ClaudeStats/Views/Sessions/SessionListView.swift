import SwiftUI

struct SessionListView: View {
    /// `export` renders a static, non-scrolling slice of the sessions scoped to
    /// a ``PeriodSelection`` (no search/sort chrome) so it can be image-captured.
    enum Mode: Hashable { case interactive, export(PeriodSelection) }

    @Environment(AppEnvironment.self) private var env
    @State private var vm = SessionListViewModel()
    var mode: Mode = .interactive

    private static let exportRowLimit = 14

    var body: some View {
        @Bindable var vm = vm
        let store = env.store
        if case .export(let selection) = mode {
            exportContent(store: store, selection: selection)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: AppIcon.Action.search).foregroundStyle(Color.stxMuted)
                    TextField(L10n.string("sessions.search.placeholder", defaultValue: "Search project or title"),
                              text: $vm.searchText)
                        .textFieldStyle(.plain)
                        .font(.sora(12))
                    Picker("Sort", selection: $vm.sortOrder) {
                        ForEach(SessionListViewModel.SortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 126)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                StxRule()
                content(store: store)
            }
        }
    }

    @ViewBuilder
    private func exportContent(store: SessionStore, selection: PeriodSelection) -> some View {
        let sessions = store.sessions(for: env.preferences.selectedProvider)
            .filter { selection.contains($0.stats?.lastActivity ?? $0.lastModified) }
            .prefix(Self.exportRowLimit)
        if sessions.isEmpty {
            Text(L10n.string("sessions.empty.period", defaultValue: "No sessions for this period."))
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    SessionRow(session: session)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    if index < sessions.count - 1 {
                        StxRule().padding(.horizontal, 12)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func content(store: SessionStore) -> some View {
        let provider = env.preferences.selectedProvider
        let providerSessions = store.sessions(for: provider)
        if !store.dataDirectoryExists(for: provider) {
            ContentUnavailableView {
                Label {
                    Text(L10n.format("sessions.empty.no_provider_data",
                                     defaultValue: "No %@ Data",
                                     provider.shortName))
                } icon: {
                    Image(systemName: AppIcon.Resource.tray)
                }
            } description: {
                if let path = store.dataDirectoryPath(for: provider) {
                    Text(L10n.format("sessions.empty.could_not_find",
                                     defaultValue: "Couldn't find %@.",
                                     path))
                } else {
                    Text(L10n.format("sessions.empty.unsupported_provider",
                                     defaultValue: "%@ usage isn't supported yet.",
                                     provider.displayName))
                }
            }
            .font(.sora(12))
        } else {
            let groups = vm.projectGroups(from: store, provider: provider, costMode: env.preferences.costEstimationMode)
            if groups.isEmpty {
                if store.isLoading && providerSessions.isEmpty {
                    ProgressView(L10n.string("sessions.scanning", defaultValue: "Scanning sessions…"))
                        .font(.sora(11))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label {
                            Text(providerSessions.isEmpty
                                ? L10n.string("sessions.empty.no_sessions", defaultValue: "No Sessions")
                                : L10n.string("sessions.empty.no_matches", defaultValue: "No Matches"))
                        } icon: {
                            Image(systemName: providerSessions.isEmpty ? "tray" : "magnifyingglass")
                        }
                    } description: {
                        Text(providerSessions.isEmpty
                            ? L10n.format("sessions.empty.no_transcripts",
                                          defaultValue: "No usable %@ transcripts found yet.",
                                          provider.shortName)
                            : L10n.format("sessions.empty.no_match_query",
                                          defaultValue: "No session matches \"%@\".",
                                          vm.searchText))
                    }
                    .font(.sora(12))
                }
            } else {
                AppScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            let isExpanded = vm.expandedProjects.contains(group.id)
                            ProjectGroupRow(group: group, isExpanded: isExpanded) {
                                withAnimation(.easeInOut(duration: 0.18)) { vm.toggle(group.id) }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            if isExpanded {
                                ForEach(group.sessions) { session in
                                    SessionRow(session: session)
                                        .padding(.leading, 28)
                                        .padding(.trailing, 12)
                                        .padding(.vertical, 7)
                                }
                            }
                            if index < groups.count - 1 {
                                StxRule().padding(.horizontal, 12)
                            }
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Populated") {
    SessionListView()
        .environment(AppEnvironment.preview())
        .frame(width: 380, height: 420)
        .background(Color.stxBackground)
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    SessionListView()
        .environment(AppEnvironment.preview(populated: false))
        .frame(width: 380, height: 420)
        .background(Color.stxBackground)
        .preferredColorScheme(.dark)
}
#endif
