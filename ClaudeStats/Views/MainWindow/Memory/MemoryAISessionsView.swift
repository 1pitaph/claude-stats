import AppKit
import SwiftUI

struct MemoryAISessionsView: View {
    @Bindable var store: MemoryStore
    @Binding var destination: MemoryAIDestination

    @Environment(AppEnvironment.self) private var env
    @State private var searchText = ""
    @State private var searchMode: MemoryAISessionSearchMode = .text
    @State private var expandedProjects: Set<String> = []
    @State private var semanticResults: [SemanticSessionSearchResult] = []
    @State private var semanticIsLoading = false
    @State private var semanticSearchTask: Task<Void, Never>?
    @FocusState private var searchFieldFocused: Bool

    private var provider: ProviderKind {
        env.preferences.selectedProvider
    }

    private var items: [MemoryAISessionItem] {
        store.aiSessionItems(sessionStore: env.store, provider: provider)
    }

    var body: some View {
        HoverableSplitView(
            axis: .vertical,
            primaryFraction: 0.34,
            configuration: HoverableSplitViewConfiguration(
                primaryMinimumPaneLength: 280,
                primaryMaximumPaneLength: 460,
                secondaryMinimumPaneLength: 480
            )
        ) {
            sidebar
        } secondary: {
            detail
        }
        .onAppear { scheduleSemanticSearch() }
        .onChange(of: searchText) { _, _ in scheduleSemanticSearch() }
        .onChange(of: searchMode) { _, mode in
            if mode == .semantic {
                scheduleSemanticSearch()
            } else {
                semanticSearchTask?.cancel()
                semanticIsLoading = false
                semanticResults = []
            }
        }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in scheduleSemanticSearch() }
        .onChange(of: env.preferences.selectedProvider) { _, _ in
            destination = .overview
            semanticResults = []
            scheduleSemanticSearch()
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusCard
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 10)

            searchField
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
                clearSearchFocus()
                destination = .overview
            }

            SidebarRow(
                title: "Analysis",
                symbol: "text.magnifyingglass",
                isSelected: destination == .analysis
            ) {
                clearSearchFocus()
                destination = .analysis
            }
            .padding(.bottom, 4)

            sessionsTree
        }
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { clearSearchFocus() }
        }
        .appSurface(.plainFill)
    }

    private var statusCard: some View {
        let providerSessions = env.store.sessions(for: provider).count
        let indexedOnly = items.filter(\.isIndexedOnly).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("AI SESSIONS")
                    .font(.sora(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 8)
                Text(provider.shortName)
                    .font(.sora(10, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
            }

            HStack(spacing: 10) {
                AIConfigsMiniStat(value: "\(providerSessions)", label: providerSessions == 1 ? "session" : "sessions")
                AIConfigsMiniStat(value: "\(indexedOnly)", label: "memory-only")
                Spacer(minLength: 0)
                MemoryAIHeaderIconButton(
                    systemName: "arrow.down.right.and.arrow.up.left",
                    help: "Collapse all projects",
                    enabled: !expandedProjects.isEmpty
                ) {
                    clearSearchFocus()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expandedProjects.removeAll()
                    }
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.stxMuted)
                .accessibilityHidden(true)
            TextField("Search AI sessions", text: $searchText)
                .textFieldStyle(.plain)
                .font(.sora(11))
                .focused($searchFieldFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
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
                Text("Text").tag(MemoryAISessionSearchMode.text)
                Text("Semantic").tag(MemoryAISessionSearchMode.semantic)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var sessionsTree: some View {
        if usesSemanticResults {
            semanticSessionsTree
        } else {
            let groups = projectGroups(for: textFilteredItems)
            if groups.isEmpty {
                emptyState(
                    hasQuery: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isLoading: env.store.isLoading,
                    hasProviderSessions: !items.isEmpty
                )
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                AppScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            let isExpanded = expandedProjects.contains(group.id)
                            MemoryAIProjectRow(
                                name: group.displayName,
                                count: group.items.count,
                                isExpanded: isExpanded
                            ) {
                                clearSearchFocus()
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    toggleProject(group.id)
                                }
                            }
                            if isExpanded {
                                ForEach(group.items) { item in
                                    MemoryAISessionRow(item: item, isSelected: isSelected(item)) {
                                        select(item)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var semanticSessionsTree: some View {
        let rows = semanticRows
        return ZStack(alignment: .topTrailing) {
            if rows.isEmpty {
                emptyState(
                    hasQuery: true,
                    isLoading: semanticIsLoading,
                    hasProviderSessions: !items.isEmpty
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                AppScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            MemoryAISemanticSessionRow(row: row, isSelected: isSelected(row.item)) {
                                select(row.item)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            if semanticIsLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .padding(.trailing, 12)
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch destination {
        case .overview:
            SessionsOverviewDetailView()
        case .analysis:
            SessionsAnalysisDetailView()
        case .session(let id):
            if let session = env.store.sessions(for: provider).first(where: { $0.id == id }) {
                MemorySessionDetailContainer(store: store, session: session)
            } else if let record = store.aiRecords.first(where: { $0.externalID == id || $0.id == id }) {
                MemoryIndexedRecordDetail(store: store, record: record)
            } else {
                SessionsOverviewDetailView()
            }
        case .indexedRecord(let id):
            if let record = store.aiRecords.first(where: { $0.id == id }) {
                MemoryIndexedRecordDetail(store: store, record: record)
            } else {
                AIConfigsEmptyState(
                    title: "Missing memory record",
                    message: "Rebuild the Memory index to refresh this selection.",
                    symbol: "text.bubble"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appSurface(.plainFill)
            }
        }
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var usesSemanticResults: Bool {
        searchMode == .semantic && env.localAI.semanticSearchAvailable && query.count >= 2
    }

    private var textFilteredItems: [MemoryAISessionItem] {
        let lowered = query.lowercased()
        guard !lowered.isEmpty else { return items }
        return items.filter { item in
            item.title.lowercased().contains(lowered)
                || item.subtitle.lowercased().contains(lowered)
                || item.projectDisplayName.lowercased().contains(lowered)
        }
    }

    private var semanticRows: [MemoryAISemanticRow] {
        let itemsBySessionID = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, MemoryAISessionItem)? in
            guard let session = item.session else { return nil }
            return (session.id, item)
        })
        return semanticResults.compactMap { result in
            guard let item = itemsBySessionID[result.sessionID] else { return nil }
            return MemoryAISemanticRow(item: item, result: result)
        }
    }

    private func projectGroups(for sourceItems: [MemoryAISessionItem]) -> [MemoryAIProjectGroup] {
        let grouped = Dictionary(grouping: sourceItems, by: \.projectID)
        return grouped.map { key, value in
            let sorted = value.sorted { lhs, rhs in
                if lhs.lastActivity != rhs.lastActivity { return lhs.lastActivity > rhs.lastActivity }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return MemoryAIProjectGroup(
                id: key,
                displayName: sorted.first?.projectDisplayName ?? key,
                items: sorted,
                lastActivity: sorted.map(\.lastActivity).max() ?? .distantPast
            )
        }
        .sorted {
            if $0.lastActivity != $1.lastActivity { return $0.lastActivity > $1.lastActivity }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func isSelected(_ item: MemoryAISessionItem) -> Bool {
        if let session = item.session {
            return destination == .session(session.id)
        }
        if let record = item.record {
            return destination == .indexedRecord(record.id)
        }
        return false
    }

    private func select(_ item: MemoryAISessionItem) {
        clearSearchFocus()
        if let session = item.session {
            destination = .session(session.id)
        } else if let record = item.record {
            destination = .indexedRecord(record.id)
        }
    }

    private func toggleProject(_ id: String) {
        if expandedProjects.contains(id) {
            expandedProjects.remove(id)
        } else {
            expandedProjects.insert(id)
        }
    }

    private func emptyState(hasQuery: Bool, isLoading: Bool, hasProviderSessions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLoading {
                Text(hasQuery ? "Searching..." : "Scanning...")
            } else if hasQuery {
                Text("No matches")
            } else if hasProviderSessions {
                Text("Expand a project")
            } else {
                Text("No AI sessions yet")
            }
        }
        .font(.sora(11))
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func scheduleSemanticSearch() {
        semanticSearchTask?.cancel()
        guard usesSemanticResults else {
            semanticIsLoading = false
            semanticResults = []
            return
        }
        semanticIsLoading = true
        let selectedProvider = provider
        let searchQuery = query
        semanticSearchTask = Task {
            let results = await env.localAI.search(
                query: searchQuery,
                provider: selectedProvider,
                sessions: env.store.sessions(for: selectedProvider),
                messageLoader: env.store.transcriptMessageLoader(for: selectedProvider),
                limit: 30
            )
            guard !Task.isCancelled else { return }
            semanticResults = results
            semanticIsLoading = false
        }
    }

    private func clearSearchFocus() {
        searchFieldFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

private struct MemorySessionDetailContainer: View {
    let store: MemoryStore
    let session: Session

    @State private var memoryBlocks: [MemoryBlock] = []

    private var recordID: String {
        store.aiRecord(for: session)?.id ?? "none"
    }

    var body: some View {
        CenteredPaneContainer {
            SessionDetailView(session: session, memoryBlocks: memoryBlocks)
        }
        .task(id: "\(session.id)-\(recordID)") {
            if let record = store.aiRecord(for: session) {
                memoryBlocks = await store.blocks(recordID: record.id)
            } else {
                memoryBlocks = []
            }
        }
    }
}

private struct MemoryIndexedRecordDetail: View {
    let store: MemoryStore
    let record: MemoryRecord

    @State private var blocks: [MemoryBlock] = []

    var body: some View {
        MemoryRecordDetail(record: record, blocks: blocks)
            .task(id: record.id) {
                blocks = await store.blocks(recordID: record.id)
            }
    }
}

private enum MemoryAISessionSearchMode: String, Hashable {
    case text
    case semantic
}

private struct MemoryAIProjectGroup: Identifiable {
    let id: String
    let displayName: String
    let items: [MemoryAISessionItem]
    let lastActivity: Date
}

private struct MemoryAISemanticRow: Identifiable {
    let item: MemoryAISessionItem
    let result: SemanticSessionSearchResult

    var id: String { item.id }
}

private struct MemoryAIProjectRow: View {
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

private struct MemoryAISessionRow: View {
    let item: MemoryAISessionItem
    let isSelected: Bool
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.sora(11, weight: item.isIndexedOnly ? .medium : .regular))
                        .foregroundStyle(isSelected ? .primary : Color.stxMuted.opacity(0.95))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if item.record != nil {
                        Image(systemName: "link")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.stxMuted.opacity(0.72))
                    }
                }
                HStack(spacing: 6) {
                    Text(item.isIndexedOnly ? "Memory-only" : Format.relativeDate(item.lastActivity))
                        .font(.sora(9))
                        .foregroundStyle(Color.stxMuted.opacity(0.7))
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.sora(9))
                        .foregroundStyle(Color.stxMuted.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
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
        .padding(.leading, 36)
        .padding(.trailing, 8)
        .onHover { hovering = $0 }
        .contextMenu {
            if let session = item.session {
                Button("Reveal Transcript in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.filePath)])
                }
                if let cwd = session.cwd, FileManager.default.fileExists(atPath: cwd) {
                    Button("Open Project Folder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                    }
                }
            } else if let path = item.record?.filePath {
                Button("Reveal Source in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
        }
    }
}

private struct MemoryAISemanticSessionRow: View {
    let row: MemoryAISemanticRow
    let isSelected: Bool
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.item.title)
                        .font(.sora(11, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : Color.stxMuted.opacity(0.95))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(String(format: "%.2f", row.result.score))
                        .font(.sora(9).monospacedDigit())
                        .foregroundStyle(Color.stxMuted.opacity(0.72))
                }
                Text(row.result.matchedExcerpt)
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
}

private struct MemoryAIHeaderIconButton: View {
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
