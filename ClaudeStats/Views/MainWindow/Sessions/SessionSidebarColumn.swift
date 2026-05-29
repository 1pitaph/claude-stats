import AppKit
import SwiftUI

/// Secondary main-window sidebar for browsing provider-scoped sessions.
struct SessionSidebarColumn: View {
    @Binding var destination: SessionsDestination
    var onExit: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var sessionsVM = SessionListViewModel()
    @State private var searchMode: SessionSearchMode = .text
    @State private var semanticResults: [SemanticSessionSearchResult] = []
    @State private var semanticIsLoading = false
    @State private var semanticSearchTask: Task<Void, Never>?
    @FocusState private var searchFieldFocused: Bool

    private var provider: ProviderKind {
        env.preferences.selectedProvider
    }

    private var providerSessionCount: Int {
        env.store.sessions(for: provider).count
    }

    var body: some View {
        @Bindable var vm = sessionsVM

        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)

            SidebarRow(
                title: "Back to App",
                symbol: "chevron.left",
                isSelected: false,
                action: close
            )

            statusCard(vm: vm)
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 10)

            searchField(vm: vm)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            searchModeControl
                .padding(.horizontal, 12)
                .padding(.bottom, env.localAI.semanticSearchAvailable ? 8 : 0)

            SidebarRow(
                title: "Overview",
                symbol: "chart.bar.xaxis",
                isSelected: destination == .overview
            ) {
                showOverview()
            }

            SidebarRow(
                title: "Analysis",
                symbol: "text.magnifyingglass",
                isSelected: destination == .analysis
            ) {
                showAnalysis()
            }
            .padding(.bottom, 4)

            sessionsTree(vm: vm)
        }
        .padding(.bottom, 10)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { clearSearchFocus() }
        }
        .onAppear { refreshSessionGroups() }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in refreshSessionGroups() }
        .onChange(of: env.preferences.selectedProvider) { _, _ in refreshSessionGroups() }
        .onChange(of: env.preferences.costEstimationMode) { _, _ in refreshSessionGroups() }
        .onChange(of: sessionsVM.searchText) { _, _ in scheduleSemanticSearch() }
        .onChange(of: sessionsVM.sortOrder) { _, _ in scheduleSemanticSearch() }
        .onChange(of: searchMode) { _, mode in
            if mode == .semantic {
                scheduleSemanticSearch()
            } else {
                semanticSearchTask?.cancel()
                semanticIsLoading = false
                semanticResults = []
            }
        }
        .onChange(of: env.localAI.semanticSearchAvailable) { _, available in
            if available {
                scheduleSemanticSearch()
            } else {
                searchMode = .text
                semanticSearchTask?.cancel()
                semanticIsLoading = false
                semanticResults = []
            }
        }
        .onDisappear {
            semanticSearchTask?.cancel()
        }
    }

    private func statusCard(vm: SessionListViewModel) -> some View {
        @Bindable var vm = vm

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("SESSIONS")
                    .font(.sora(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 8)
                Text(provider.shortName)
                    .font(.sora(10, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(providerSessionCount)")
                        .font(.sora(18, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(providerSessionCount == 1 ? "session" : "sessions")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 0)

                HeaderIconButton(
                    systemName: "arrow.down.right.and.arrow.up.left",
                    help: "Collapse all projects",
                    enabled: !vm.expandedProjects.isEmpty
                ) {
                    clearSearchFocus()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        vm.expandedProjects.removeAll()
                    }
                }

                Menu {
                    Picker("Sort by", selection: $vm.sortOrder) {
                        ForEach(SessionListViewModel.SortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sort sessions")
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1))
    }

    private func searchField(vm: SessionListViewModel) -> some View {
        @Bindable var vm = vm

        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.stxMuted)
                .accessibilityHidden(true)
            TextField("Search sessions", text: $vm.searchText)
                .textFieldStyle(.plain)
                .font(.sora(11))
                .focused($searchFieldFocused)
            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var searchModeControl: some View {
        if env.localAI.semanticSearchAvailable {
            Picker("", selection: $searchMode) {
                Text("Text").tag(SessionSearchMode.text)
                Text("Semantic").tag(SessionSearchMode.semantic)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private func sessionsTree(vm: SessionListViewModel) -> some View {
        let groups = vm.projectGroups

        if searchMode == .semantic && env.localAI.semanticSearchAvailable && !vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            semanticSessionsTree()
        } else if groups.isEmpty {
            sessionsEmptyState(
                hasQuery: !vm.searchText.isEmpty,
                isLoading: env.store.isLoading,
                hasProviderSessions: vm.hasProviderSessions
            )
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        let isExpanded = vm.expandedProjects.contains(group.id)
                        ProjectSidebarRow(
                            name: group.displayName,
                            count: group.count,
                            isExpanded: isExpanded
                        ) {
                            clearSearchFocus()
                            withAnimation(.easeInOut(duration: 0.18)) { vm.toggle(group.id) }
                        }
                        if isExpanded {
                            ForEach(group.sessions) { session in
                                SessionSidebarRow(
                                    session: session,
                                    isSelected: destination == .session(session.id)
                                ) {
                                    selectSession(session)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func semanticSessionsTree() -> some View {
        let sessionsByID = Dictionary(uniqueKeysWithValues: env.store.sessions(for: provider).map { ($0.id, $0) })
        let rows = semanticResults.compactMap { result -> SemanticSidebarResult? in
            guard let session = sessionsByID[result.sessionID] else { return nil }
            return SemanticSidebarResult(session: session, result: result)
        }

        if rows.isEmpty {
            sessionsEmptyState(
                hasQuery: true,
                isLoading: semanticIsLoading,
                hasProviderSessions: sessionsVM.hasProviderSessions
            )
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        SemanticSessionSidebarRow(
                            session: row.session,
                            result: row.result,
                            isSelected: destination == .session(row.session.id)
                        ) {
                            selectSession(row.session)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .overlay(alignment: .topTrailing) {
                if semanticIsLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .padding(.trailing, 12)
                        .padding(.top, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionsEmptyState(hasQuery: Bool, isLoading: Bool, hasProviderSessions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLoading {
                Text(hasQuery ? "Searching..." : "Scanning...")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            } else if hasQuery {
                Text("No matches")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            } else if hasProviderSessions {
                Text("Expand a project")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            } else {
                Text("No sessions yet")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func selectSession(_ session: Session) {
        clearSearchFocus()
        destination = .session(session.id)
    }

    private func showOverview() {
        clearSearchFocus()
        destination = .overview
    }

    private func showAnalysis() {
        clearSearchFocus()
        destination = .analysis
    }

    private func refreshSessionGroups() {
        sessionsVM.refresh(
            from: env.store,
            provider: provider,
            costMode: env.preferences.costEstimationMode
        )
        scheduleSemanticSearch()
    }

    private func close() {
        clearSearchFocus()
        onExit()
    }

    private func clearSearchFocus() {
        searchFieldFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func scheduleSemanticSearch() {
        semanticSearchTask?.cancel()
        let query = sessionsVM.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard searchMode == .semantic,
              env.localAI.semanticSearchAvailable,
              query.count >= 2 else {
            semanticIsLoading = false
            semanticResults = []
            return
        }
        semanticIsLoading = true
        let selectedProvider = provider
        semanticSearchTask = Task {
            let results = await env.localAI.search(
                query: query,
                provider: selectedProvider,
                sessions: env.store.sessions(for: selectedProvider),
                messageLoader: env.store.transcriptMessageLoader(for: selectedProvider)
            )
            guard !Task.isCancelled else { return }
            semanticResults = results
            semanticIsLoading = false
        }
    }
}

private enum SessionSearchMode: String, Hashable {
    case text
    case semantic
}

private struct SemanticSidebarResult: Identifiable {
    let session: Session
    let result: SemanticSessionSearchResult

    var id: String { session.id }
}

private struct ProjectSidebarRow: View {
    let name: String
    let count: Int
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10)
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.stxMuted)
                    .frame(width: 16)
                Text(name)
                    .font(.sora(12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(count)")
                    .font(.sora(9).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if hovering {
                    RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
    }
}

private struct SemanticSessionSidebarRow: View {
    let session: Session
    let result: SemanticSessionSearchResult
    let isSelected: Bool
    let select: () -> Void

    @State private var hovering = false

    private var title: String {
        if let title = session.stats?.title, !title.isEmpty { return title }
        return session.externalID
    }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.sora(11, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : Color.stxMuted.opacity(0.95))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(scoreText)
                        .font(.sora(9).monospacedDigit())
                        .foregroundStyle(Color.stxMuted.opacity(0.72))
                }
                Text(result.matchedExcerpt)
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted.opacity(0.72))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.10))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
    }

    private var scoreText: String {
        String(format: "%.2f", result.score)
    }
}

private struct SessionSidebarRow: View {
    let session: Session
    let isSelected: Bool
    let select: () -> Void

    @State private var hovering = false

    private var title: String {
        if let title = session.stats?.title, !title.isEmpty { return title }
        return session.externalID
    }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.sora(11))
                    .foregroundStyle(isSelected ? .primary : Color.stxMuted.opacity(0.95))
                    .lineLimit(1)
                Text(Format.relativeDate(session.stats?.lastActivity ?? session.lastModified))
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.10))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 36)
        .padding(.trailing, 8)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Reveal Transcript in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.filePath)])
            }
            if let cwd = session.cwd, FileManager.default.fileExists(atPath: cwd) {
                Button("Open Project Folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                }
            }
        }
    }
}

private struct HeaderIconButton: View {
    let systemName: String
    let help: String
    var enabled = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(enabled ? Color.stxMuted : Color.stxMuted.opacity(0.35))
                .frame(width: 24, height: 22)
                .background {
                    if enabled && hovering {
                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}

#if DEBUG
#Preview("Sessions sidebar") {
    @Previewable @State var destination: SessionsDestination = .overview

    return SessionSidebarColumn(destination: $destination, onExit: {})
        .environment(AppEnvironment.preview())
        .frame(width: 240, height: 640)
        .background(VisualEffectBackground())
}
#endif
