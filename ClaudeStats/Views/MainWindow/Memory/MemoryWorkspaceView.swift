import AppKit
import SwiftUI

struct MemoryWorkspaceView: View {
    @Bindable var store: MemoryStore
    @Binding var aiDestination: MemoryAIDestination

    @Environment(AppEnvironment.self) private var env
    private let horizontalInset: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await store.loadIfNeeded(sessionStore: env.store)
            if store.counts.blockCount == 0 {
                await store.index(sessionStore: env.store)
            }
        }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in
            Task { await store.index(sessionStore: env.store) }
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
                Text(description(for: store.section))
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                Text("\(store.counts.recordCount) records · \(store.counts.blockCount) blocks · \(store.counts.sourceCount) sources")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                if store.isIndexing || store.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task { await store.index(sessionStore: env.store) }
                } label: {
                    Label("Index", systemImage: "arrow.triangle.2.circlepath")
                }
                .controlSize(.small)
                .disabled(store.isIndexing)
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
        case .projects:
            CodeMemoryProjectsView(store: store)
        case .modules:
            CodeMemoryModulesView(store: store)
        case .graph:
            CodeMemoryGraphView(store: store)
        case .trace:
            CodeMemoryTraceView(store: store)
        case .proposals:
            CodeMemoryProposalsView(store: store)
        case .legacyHistory:
            MemoryLegacyHistoryView(store: store, aiDestination: $aiDestination)
        case .settings:
            CodeMemorySettingsView(store: store)
        case .aiSessions:
            MemoryAISessionsView(store: store, destination: $aiDestination)
        case .terminalHistory:
            MemoryRecordsBrowser(
                records: store.terminalRecords,
                selectedRecord: store.selectedRecord,
                selectedBlocks: store.selectedBlocks,
                emptyTitle: "No terminal captures yet",
                emptyMessage: "Use the CLI helper's run or pipe commands to save terminal output.",
                select: { record in Task { await store.selectRecord(record) } }
            )
        case .sources:
            MemorySourcesView(store: store)
        case .setup:
            MemorySetupView(store: store)
        }
    }

    private func title(for section: MemoryWorkspaceSection) -> String {
        switch section {
        case .search: "Code Memory Search"
        case .projects: "Projects"
        case .modules: "Modules"
        case .graph: "Graph"
        case .trace: "Trace"
        case .proposals: "Proposals"
        case .legacyHistory: "Legacy History"
        case .settings: "Settings"
        case .aiSessions: "AI Sessions"
        case .terminalHistory: "Terminal History"
        case .sources: "Sources"
        case .setup: "Setup"
        }
    }

    private func description(for section: MemoryWorkspaceSection) -> String {
        switch section {
        case .search:
            "Search project, module, path, and workflow memories from the sidecar."
        case .projects:
            "Review projects known to Code Memory and their active memory counts."
        case .modules:
            "Inspect module-scoped memories and deterministic classification output."
        case .graph:
            "Browse the event-sourced memory graph projection for the selected project."
        case .trace:
            "Inspect retrieval traces that explain what memory was selected for an agent run."
        case .proposals:
            "Review candidate memories before they can affect future agent context."
        case .legacyHistory:
            "Keep existing AI session and terminal history available, with manual import."
        case .settings:
            "Check sidecar health, adapters, local-first defaults, and migration actions."
        case .aiSessions:
            "Browse sessions with stats, analysis, transcript refs, and reusable indexed blocks."
        case .terminalHistory:
            "Review run, pipe, and shell metadata captures."
        case .sources:
            "Manage Memory-only roots and source health."
        case .setup:
            "Install the CLI helper and explicit shell metadata integration."
        }
    }
}

private struct MemorySearchView: View {
    @Bindable var store: MemoryStore
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.stxMuted)
                    TextField("Search memory", text: $store.searchText)
                        .textFieldStyle(.plain)
                        .font(.sora(12))
                        .onSubmit { search() }
                    if !store.searchText.isEmpty {
                        Button {
                            store.searchText = ""
                            store.clearSearchResults()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.stxMuted)
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))

                Picker("", selection: $store.searchMode) {
                    Text("Text").tag(MemorySearchMode.text)
                    Text("Semantic").tag(MemorySearchMode.semantic)
                    Text("Hybrid").tag(MemorySearchMode.hybrid)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .disabled(!env.localAI.semanticSearchAvailable && store.searchMode != .text)

                Button {
                    search()
                } label: {
                    Label("Search", systemImage: "arrow.right")
                }
                .controlSize(.small)
                .disabled(store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSearching)
            }
            .padding(14)

            StxRule()

            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if store.codeSearchResults.isEmpty {
                        AIConfigsEmptyState(
                            title: store.searchText.isEmpty ? "Search memory" : "No matches",
                            message: store.codeHealth == nil
                                ? "Start memoryd to search Code Agent memory. Legacy history remains available separately."
                                : "Code Memory text search is ready. Local semantic search can be enabled later.",
                            symbol: "magnifyingglass"
                        )
                        .frame(minHeight: 320)
                    } else {
                        ForEach(store.codeSearchResults) { result in
                            CodeMemorySearchResultRow(result: result)
                        }
                    }
                }
                .padding(18)
            }
        }
    }

    private func search() {
        Task {
            await store.performSearch(localAI: env.localAI, sessionStore: env.store)
        }
    }
}

private struct CodeMemoryProjectsView: View {
    @Bindable var store: MemoryStore

    var body: some View {
        AppScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if store.codeProjects.isEmpty {
                    AIConfigsEmptyState(
                        title: store.codeHealth == nil ? "Sidecar offline" : "No projects yet",
                        message: store.codeHealth == nil ? "Start memoryd from Settings or the CLI helper." : "Record or import memories to create the first project graph.",
                        symbol: "folder.badge.questionmark"
                    )
                    .frame(minHeight: 320)
                } else {
                    ForEach(store.codeProjects) { project in
                        CodeMemoryProjectRow(project: project, isSelected: store.codeSelectedProjectID == project.projectID) {
                            Task { await store.selectCodeProject(project.projectID) }
                        }
                    }
                }
            }
            .padding(18)
        }
    }
}

private struct CodeMemoryProjectRow: View {
    let project: CodeMemoryProject
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.projectID)
                        .font(.sora(13, weight: .semibold))
                    Text("\(project.memoryCount) active memories")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
                Spacer(minLength: 8)
                if isSelected {
                    AIConfigsBadge(text: "Selected", color: Color.stxAccent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSurface(.compactCard(radius: 8, fillOpacity: isSelected ? 0.78 : 0.58, cornerStyle: .circular, maxWidth: nil), padding: nil)
        }
        .buttonStyle(.plain)
    }
}

private struct CodeMemoryModulesView: View {
    @Bindable var store: MemoryStore

    private var moduleScopes: [CodeMemoryScope] {
        let scopes = store.codeGraph?.nodes.compactMap { node -> CodeMemoryScope? in
            guard node.kind == "module" else { return nil }
            return CodeMemoryScope(id: node.id, kind: node.kind, key: node.id, title: node.title, metadata: nil, primary: nil)
        } ?? []
        return scopes.sorted { $0.title < $1.title }
    }

    var body: some View {
        AppScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if moduleScopes.isEmpty {
                    AIConfigsEmptyState(
                        title: "No module graph yet",
                        message: "Module classification starts with project events and path-scoped memories. Import or record code memories first.",
                        symbol: "square.stack.3d.up"
                    )
                    .frame(minHeight: 320)
                } else {
                    ForEach(moduleScopes) { scope in
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox")
                                .foregroundStyle(Color.stxAccent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(scope.title)
                                    .font(.sora(13, weight: .semibold))
                                Text(scope.id)
                                    .font(.sora(10).monospaced())
                                    .foregroundStyle(Color.stxMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                        }
                        .padding(12)
                        .appSurface(.compactCard(radius: 8, fillOpacity: 0.58, cornerStyle: .circular, maxWidth: nil), padding: nil)
                    }
                }
            }
            .padding(18)
        }
        .task {
            if let project = store.codeSelectedProjectID {
                await store.loadCodeGraph(projectID: project)
            }
        }
    }
}

private struct CodeMemoryGraphView: View {
    @Bindable var store: MemoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(store.codeSelectedProjectID ?? "No project selected")
                    .font(.sora(13, weight: .semibold))
                Spacer(minLength: 8)
                Button {
                    Task { await store.loadCodeGraph() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(store.codeSelectedProjectID == nil)
            }
            .padding(14)
            StxRule()

            AppScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let graph = store.codeGraph
                    if let graph {
                        graphStats(graph)
                        graphList(title: "Nodes", items: graph.nodes.map { "\($0.kind): \($0.title)" })
                        graphList(title: "Edges", items: graph.edges.map { "\($0.source) -[\($0.kind)]-> \($0.target)" })
                    } else {
                        AIConfigsEmptyState(title: "No graph loaded", message: "Select a project or import legacy records to build the graph projection.", symbol: "point.3.connected.trianglepath.dotted")
                            .frame(minHeight: 320)
                    }
                }
                .padding(18)
            }
        }
        .task {
            if store.codeGraph == nil {
                await store.loadCodeGraph()
            }
        }
    }

    private func graphStats(_ graph: CodeMemoryGraph) -> some View {
        HStack(spacing: 10) {
            AIConfigsMiniStat(value: "\(graph.nodes.count)", label: "nodes")
            AIConfigsMiniStat(value: "\(graph.edges.count)", label: "edges")
            AIConfigsMiniStat(value: graph.projectID, label: "project")
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.58, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private func graphList(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.sora(13, weight: .semibold))
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.prefix(80).enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(.sora(10).monospaced())
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.48, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }
}

private struct CodeMemoryTraceView: View {
    @Bindable var store: MemoryStore
    @State private var runID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                TextField("Trace run id", text: $runID)
                    .textFieldStyle(.roundedBorder)
                    .font(.sora(12))
                Button {
                    Task { await store.loadCodeTrace(runID: runID) }
                } label: {
                    Label("Load Trace", systemImage: "arrow.right")
                }
                .controlSize(.small)
            }
            .padding(14)
            StxRule()
            AppScrollView {
                if let trace = store.codeTrace {
                    VStack(alignment: .leading, spacing: 10) {
                        fact("Run", trace.runID)
                        fact("Project", trace.projectID ?? "-")
                        fact("Memory usage", "\(trace.memoryUsage.count)")
                        ForEach(trace.memoryUsage) { usage in
                            Text("#\(usage.rank) \(usage.usageKind) \(usage.memoryID) score \(String(format: "%.2f", usage.score))")
                                .font(.sora(10).monospaced())
                                .foregroundStyle(Color.stxMuted)
                                .lineLimit(1)
                        }
                    }
                    .padding(18)
                } else {
                    AIConfigsEmptyState(title: "No trace loaded", message: "Search results include trace IDs that can be loaded here.", symbol: "list.bullet.clipboard")
                        .frame(minHeight: 320)
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.sora(11, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.sora(11).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct CodeMemoryProposalsView: View {
    @Bindable var store: MemoryStore

    var body: some View {
        AIConfigsEmptyState(
            title: "Proposal review is staged",
            message: "The sidecar records proposed memories today. Accept/reject controls will be wired after proposal listing is exposed.",
            symbol: "checklist"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MemoryLegacyHistoryView: View {
    @Bindable var store: MemoryStore
    @Binding var aiDestination: MemoryAIDestination

    var body: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    legacyCard(
                        title: "AI Sessions",
                        count: store.aiRecords.count,
                        symbol: "text.bubble",
                        open: { store.select(.aiSessions) },
                        importAction: { Task { await store.importLegacyRecords(kind: .aiSession) } }
                    )
                    legacyCard(
                        title: "Terminal History",
                        count: store.terminalRecords.count,
                        symbol: "terminal",
                        open: { store.select(.terminalHistory) },
                        importAction: { Task { await store.importLegacyRecords(kind: nil) } }
                    )
                }
                if let result = store.codeLastImportResult {
                    Text("Last import: \(result.imported) imported, \(result.skipped) skipped")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
                Text("Legacy records stay read-only until you explicitly import them into Code Memory. Imported records become event-sourced graph memories and keep their original memory:// refs as source references.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .appSurface(.compactCard(radius: 8, fillOpacity: 0.48, cornerStyle: .circular, maxWidth: nil), padding: nil)
            }
            .padding(18)
        }
    }

    private func legacyCard(title: String, count: Int, symbol: String, open: @escaping () -> Void, importAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.stxAccent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.sora(13, weight: .semibold))
                    Text("\(count) records")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
                Spacer(minLength: 8)
            }
            HStack(spacing: 8) {
                Button(action: open) {
                    Label("Open", systemImage: "sidebar.leading")
                }
                .controlSize(.small)
                Button(action: importAction) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
                .disabled(count == 0 || store.codeHealth == nil)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.58, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }
}

private struct CodeMemorySettingsView: View {
    @Bindable var store: MemoryStore

    private var helperPath: String {
        CodeMemorySidecarManager.defaultHelperPath()
    }

    private var startCommand: String {
        CodeMemorySidecarManager.shellCommand(arguments: ["memoryd", "start"])
    }

    var body: some View {
        CenteredPaneContainer(maxWidth: 900, topPadding: 18) {
            AppScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sidecar")
                            .font(.sora(15, weight: .semibold))
                        fact("Endpoint", "http://127.0.0.1:8765")
                        fact("Status", store.codeHealth?.status ?? "offline")
                        fact("Store", store.codeHealth?.store ?? "-")
                        fact("Events", "\(store.codeHealth?.eventCount ?? 0)")
                        fact("Memories", "\(store.codeHealth?.memoryCount ?? 0)")
                        fact("Helper", helperPath)
                        fact("Command", startCommand)
                        HStack(spacing: 8) {
                            Button {
                                Task { await store.startCodeMemorySidecar() }
                            } label: {
                                Label("Start", systemImage: "play.fill")
                            }
                            .controlSize(.small)
                            .disabled(store.isCodeMemoryLoading)
                            Button {
                                Task { await store.stopCodeMemorySidecar() }
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .controlSize(.small)
                            .disabled(store.isCodeMemoryLoading)
                            Button {
                                Task { await store.refreshCodeMemoryStatus() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .controlSize(.small)
                            .disabled(store.isCodeMemoryLoading)
                            Button {
                                copy(startCommand)
                            } label: {
                                Label("Copy Start Command", systemImage: "doc.on.doc")
                            }
                            .controlSize(.small)
                        }
                        if let message = store.setupMessage {
                            Text(message)
                                .font(.sora(11))
                                .foregroundStyle(Color.stxMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Adapters")
                            .font(.sora(15, weight: .semibold))
                        Text("mem0 and Graphiti are sidecar projections behind feature flags. Default mode is deterministic and local-first; cloud LLMs are never enabled implicitly.")
                            .font(.sora(12))
                            .foregroundStyle(Color.stxMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
                }
                .padding(.bottom, 24)
            }
        }
        .task {
            await store.refreshCodeMemoryStatus()
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.sora(11, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 90, alignment: .leading)
            Text(value.memoryAbbreviatingHomeDirectory)
                .font(.sora(11).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct CodeMemorySearchResultRow: View {
    let result: CodeMemorySearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.stxAccent)
                    .frame(width: 18)
                Text(result.memory.title)
                    .font(.sora(13, weight: .semibold))
                    .lineLimit(1)
                AIConfigsBadge(text: result.memory.type, color: Color.stxMuted)
                AIConfigsBadge(text: result.memory.status, color: result.memory.status == "active" ? Color.stxAccent : Color.stxMuted)
                Spacer(minLength: 8)
                Text(String(format: "%.2f", result.score))
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
            Text(result.memory.body)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(3)
            HStack(spacing: 8) {
                Text(result.memory.projectID)
                    .font(.sora(10).monospaced())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button {
                    copy(result.memory.body)
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                Button {
                    copy(result.memory.id)
                } label: {
                    Label("Copy ID", systemImage: "link")
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.65, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private var icon: String {
        switch result.memory.type {
        case "command": "terminal"
        case "risk": "exclamationmark.triangle"
        case "rule", "convention": "checkmark.seal"
        default: "text.badge.checkmark"
        }
    }
}

private struct MemoryRecordsBrowser: View {
    let records: [MemoryRecord]
    let selectedRecord: MemoryRecord?
    let selectedBlocks: [MemoryBlock]
    let emptyTitle: String
    let emptyMessage: String
    let select: (MemoryRecord) -> Void

    var body: some View {
        HoverableSplitView(
            axis: .vertical,
            primaryFraction: 0.34,
            configuration: HoverableSplitViewConfiguration(
                primaryMinimumPaneLength: 280,
                primaryMaximumPaneLength: 460,
                secondaryMinimumPaneLength: 420
            )
        ) {
            recordsList
        } secondary: {
            MemoryRecordDetail(record: selectedRecord, blocks: selectedBlocks)
        }
    }

    @ViewBuilder
    private var recordsList: some View {
        if records.isEmpty {
            AIConfigsEmptyState(title: emptyTitle, message: emptyMessage, symbol: "tray")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appSurface(.plainFill)
        } else {
            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(records) { record in
                        MemoryRecordRow(record: record, isSelected: selectedRecord?.id == record.id) {
                            select(record)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .appSurface(.plainFill)
        }
    }
}

private struct MemorySourcesView: View {
    @Bindable var store: MemoryStore
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 14) {
                addSourceCard
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(store.sources) { source in
                        MemorySourceRow(
                            source: source,
                            status: store.sourceStatuses[source.id],
                            refresh: { Task { await store.index(sessionStore: env.store) } },
                            reveal: { store.revealSource(source) },
                            remove: { Task { await store.removeSource(source) } }
                        )
                    }
                }
            }
            .padding(18)
        }
    }

    private var addSourceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add AI Session Root")
                .font(.sora(13, weight: .semibold))
            HStack(spacing: 10) {
                Picker("", selection: $store.newSourceProviderRaw) {
                    ForEach(ProviderKind.allCases) { provider in
                        Text(provider.shortName).tag(provider.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                TextField("Path to .claude, .claude/projects, .codex, or .codex/sessions", text: $store.newSourcePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.sora(11))
                Button {
                    Task { await store.addSource() }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }
}

private struct MemorySetupView: View {
    @Bindable var store: MemoryStore

    private var helperPath: String {
        CodeMemorySidecarManager.defaultHelperPath()
    }

    var body: some View {
        CenteredPaneContainer(maxWidth: 900, topPadding: 18) {
            AppScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    setupCard
                    shellCard
                    privacyCard
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CLI Helper")
                .font(.sora(15, weight: .semibold))
            fact("Path", value: helperPath)
            fact("Status", value: FileManager.default.isExecutableFile(atPath: helperPath) ? "Bundled helper available" : "Use installed command on PATH")
            HStack(spacing: 8) {
                Button {
                    copy(helperPath)
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                Button(role: .destructive) {
                    Task { await store.clearIndex() }
                } label: {
                    Label("Clear Index", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private var shellCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shell Integration")
                .font(.sora(15, weight: .semibold))
            ForEach(MemoryShell.allCases) { shell in
                let status = MemoryShellIntegrationManager().status(shell: shell)
                HStack(spacing: 10) {
                    Image(systemName: status.isInstalled ? "checkmark.circle" : "circle")
                        .foregroundStyle(status.isInstalled ? Color.stxAccent : Color.stxMuted)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(shell.rawValue)
                            .font(.sora(12, weight: .semibold))
                        Text(status.rcPath.memoryAbbreviatingHomeDirectory)
                            .font(.sora(10).monospaced())
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button {
                        store.installShell(shell: shell, helperPath: helperPath)
                    } label: {
                        Label("Install", systemImage: "square.and.arrow.down")
                    }
                    .controlSize(.small)
                    Button {
                        store.uninstallShell(shell: shell)
                    } label: {
                        Label("Uninstall", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
            }
            if let message = store.setupMessage {
                Text(message)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
        }
        .padding(16)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy")
                .font(.sora(15, weight: .semibold))
            Text("Terminal output is captured only when you use run or pipe. Shell integration records command metadata only: command, cwd, exit status, and timestamp.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private func fact(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.sora(11, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 80, alignment: .leading)
            Text(value.memoryAbbreviatingHomeDirectory)
                .font(.sora(11).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct MemorySearchResultRow: View {
    let result: MemorySearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: result.record.kind == .aiSession ? "text.bubble" : "terminal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.stxAccent)
                    .frame(width: 18)
                Text(result.record.title)
                    .font(.sora(13, weight: .semibold))
                    .lineLimit(1)
                AIConfigsBadge(text: result.block.role.rawValue, color: Color.stxMuted)
                AIConfigsBadge(text: result.matchKind.rawValue, color: result.matchKind == .semantic ? Color.stxAccent : Color.stxMuted)
                Spacer(minLength: 8)
                if let score = result.score {
                    Text(String(format: "%.2f", score))
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }
            }
            Text(result.snippet?.isEmpty == false ? result.snippet! : result.block.excerpt)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(3)
            HStack(spacing: 8) {
                Text(result.block.ref)
                    .font(.sora(10).monospaced())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button {
                    copy(result.block.text)
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                Button {
                    copy(result.block.ref)
                } label: {
                    Label("Copy Ref", systemImage: "link")
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.65, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }
}

private struct MemoryRecordRow: View {
    let record: MemoryRecord
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: record.kind == .aiSession ? "text.bubble" : "terminal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    Text(record.title)
                        .font(.sora(12, weight: .semibold))
                        .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let exit = record.exitCode {
                        Text("\(exit)")
                            .font(.sora(9).monospacedDigit())
                            .foregroundStyle(exit == 0 ? Color.stxAccent : Color(red: 0.85, green: 0.22, blue: 0.18))
                    }
                }
                Text(record.subtitle ?? record.cwd ?? record.projectPath ?? record.id)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.10))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .onHover { hovering = $0 }
    }
}

struct MemoryRecordDetail: View {
    let record: MemoryRecord?
    let blocks: [MemoryBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let record {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title)
                            .font(.sora(15, weight: .semibold))
                            .lineLimit(1)
                        Text(record.filePath ?? record.cwd ?? record.id)
                            .font(.sora(10).monospaced())
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button {
                        copy(blocks.map(\.text).joined(separator: "\n\n"))
                    } label: {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                }
                .padding(14)
                StxRule()
                AppScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(blocks) { block in
                            MemoryBlockCard(block: block)
                        }
                    }
                    .padding(14)
                }
            } else {
                AIConfigsEmptyState(title: "Select a record", message: "Choose a memory record to inspect its indexed blocks.", symbol: "text.bubble")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .appSurface(.plainFill)
    }
}

private struct MemoryBlockCard: View {
    let block: MemoryBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AIConfigsBadge(text: block.role.rawValue, color: Color.stxMuted)
                if let model = block.model {
                    AIConfigsBadge(text: model, color: Color.stxMuted)
                }
                Spacer(minLength: 8)
                Button {
                    copy(block.text)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .controlSize(.small)
                .help("Copy text")
                Button {
                    copy(block.ref)
                } label: {
                    Image(systemName: "link")
                }
                .controlSize(.small)
                .help("Copy ref")
            }
            Text(block.text)
                .font(.sora(11))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(block.ref)
                .font(.sora(10).monospaced())
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }
}

private struct MemorySourceRow: View {
    let source: MemorySource
    let status: MemorySourceStatus?
    let refresh: () -> Void
    let reveal: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: source.kind == .terminal ? "terminal" : "text.bubble")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(statusColor)
                .frame(width: 22)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(source.title)
                        .font(.sora(13, weight: .semibold))
                    if source.isDefault {
                        AIConfigsBadge(text: "Default", color: Color.stxMuted)
                    }
                    if let provider = source.providerRaw {
                        AIConfigsBadge(text: ProviderKind(rawValue: provider)?.shortName ?? provider, color: Color.stxMuted)
                    }
                    Spacer(minLength: 8)
                }
                Text(source.path?.memoryAbbreviatingHomeDirectory ?? "No fixed path")
                    .font(.sora(10).monospaced())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    statusBadge("readable", on: status?.readable == true)
                    statusBadge("readonly", on: status?.readOnly == true)
                    statusBadge("indexed", on: status?.indexed == true)
                    if status?.unsupported == true {
                        AIConfigsBadge(text: "Unsupported", color: Color(red: 0.92, green: 0.58, blue: 0.16))
                    }
                    if let error = status?.error {
                        Text(error)
                            .font(.sora(10))
                            .foregroundStyle(Color(red: 0.85, green: 0.22, blue: 0.18))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .controlSize(.small)
                .help("Refresh index")
                Button(action: reveal) {
                    Image(systemName: "finder")
                }
                .controlSize(.small)
                .disabled(source.path == nil)
                .help("Reveal source")
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .disabled(source.isDefault)
                .help("Remove source")
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.65, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private var statusColor: Color {
        if status?.unsupported == true || status?.error != nil { return Color(red: 0.92, green: 0.58, blue: 0.16) }
        if status?.indexed == true { return Color.stxAccent }
        return Color.stxMuted
    }

    private func statusBadge(_ title: String, on: Bool) -> some View {
        AIConfigsBadge(text: title, color: on ? Color.stxAccent : Color.stxMuted)
            .opacity(on ? 1 : 0.55)
    }
}

private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}
