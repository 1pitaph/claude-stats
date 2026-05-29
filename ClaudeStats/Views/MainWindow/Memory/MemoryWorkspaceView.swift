import AppKit
import SwiftUI

struct MemoryWorkspaceView: View {
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
            await store.loadIfNeeded()
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
                Text("\(store.codeHealth?.memoryCount ?? 0) memories · \(store.codeHealth?.eventCount ?? 0) events")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                if store.isCodeMemoryLoading || store.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task { await store.refreshCodeMemoryStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
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
        case .overview:
            CodeMemoryOverviewView(store: store)
        case .search:
            MemorySearchView(store: store)
        case .context:
            CodeMemoryContextView(store: store)
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
        case .settings:
            CodeMemorySettingsView(store: store)
        }
    }

    private func title(for section: MemoryWorkspaceSection) -> String {
        switch section {
        case .overview: "Overview"
        case .search: "Code Memory Search"
        case .context: "Context Pack"
        case .projects: "Projects"
        case .modules: "Modules"
        case .graph: "Graph"
        case .trace: "Trace"
        case .proposals: "Proposals"
        case .settings: "Settings"
        }
    }

    private func description(for section: MemoryWorkspaceSection) -> String {
        switch section {
        case .overview:
            "Monitor sync, projection health, proposals, modules, and local adapter status."
        case .search:
            "Search deterministic, mem0, and Graphiti memories from the local sidecar."
        case .context:
            "Preview the grouped memory context that an agent can receive."
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
        case .settings:
            "Check sidecar health, adapters, local-first defaults, and shell capture."
        }
    }
}

private struct CodeMemoryOverviewView: View {
    @Bindable var store: MemoryStore

    var body: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    AIConfigsMiniStat(value: "\(store.codeHealth?.memoryCount ?? 0)", label: "memories")
                    AIConfigsMiniStat(value: "\(store.codeHealth?.proposalCount ?? store.codeProposals.count)", label: "proposals")
                    AIConfigsMiniStat(value: "\(store.codeHealth?.moduleCount ?? store.codeModules.count)", label: "modules")
                    AIConfigsMiniStat(value: "\(store.codeHealth?.projectionPending ?? 0)", label: "pending")
                }
                .padding(12)
                .appSurface(.compactCard(radius: 8, fillOpacity: 0.58, cornerStyle: .circular, maxWidth: nil), padding: nil)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sync")
                        .font(.sora(14, weight: .semibold))
                    Text(store.codeLastSyncSummary ?? "Automatic local sync runs after session/config refresh when memoryd is available.")
                        .font(.sora(12))
                        .foregroundStyle(Color.stxMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .appSurface(.compactCard(radius: 8, fillOpacity: 0.52, cornerStyle: .circular, maxWidth: nil), padding: nil)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Adapters")
                        .font(.sora(14, weight: .semibold))
                    ForEach((store.codeHealth?.adapters ?? [:]).sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(spacing: 8) {
                            Text(key)
                                .font(.sora(11, weight: .medium))
                                .frame(width: 120, alignment: .leading)
                            Text(value)
                                .font(.sora(11))
                                .foregroundStyle(Color.stxMuted)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .padding(14)
                .appSurface(.compactCard(radius: 8, fillOpacity: 0.52, cornerStyle: .circular, maxWidth: nil), padding: nil)
            }
            .padding(18)
        }
        .task {
            await store.refreshCodeMemoryStatus()
        }
    }
}

private struct MemorySearchView: View {
    @Bindable var store: MemoryStore

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
                                ? "Start memoryd to search local Code Memory."
                                : "Code Memory search fuses deterministic, mem0, and Graphiti results when those adapters are enabled.",
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
            await store.performSearch()
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
                        message: store.codeHealth == nil ? "Start memoryd from Settings or the CLI helper." : "Record memories to create the first project graph.",
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

private struct CodeMemoryContextView: View {
    @Bindable var store: MemoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                TextField("Build context for...", text: $store.contextText)
                    .textFieldStyle(.roundedBorder)
                    .font(.sora(12))
                    .onSubmit { load() }
                Button {
                    load()
                } label: {
                    Label("Build", systemImage: "doc.text.magnifyingglass")
                }
                .controlSize(.small)
                .disabled((store.contextText.isEmpty && store.searchText.isEmpty) || store.isCodeMemoryLoading)
            }
            .padding(14)
            StxRule()
            AppScrollView {
                if let pack = store.codeContextPack {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            fact("Trace", pack.traceID)
                            Spacer()
                            Button {
                                copy(pack.traceID)
                            } label: {
                                Label("Copy Trace", systemImage: "link")
                            }
                            .controlSize(.small)
                        }
                        contextGroup("Rules", pack.context.rules)
                        contextGroup("Facts", pack.context.facts)
                        contextGroup("Risks", pack.context.risks)
                        contextGroup("Commands", pack.context.commands)
                        contextGroup("Decisions", pack.context.decisions)
                    }
                    .padding(18)
                } else {
                    AIConfigsEmptyState(title: "No context built", message: "Build a context pack to see grouped active memory for an agent run.", symbol: "doc.text.magnifyingglass")
                        .frame(minHeight: 320)
                }
            }
        }
    }

    private func load() {
        Task { await store.loadContextPack() }
    }

    private func contextGroup(_ title: String, _ memories: [CodeMemoryMemory]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.sora(13, weight: .semibold))
            if memories.isEmpty {
                Text("No \(title.lowercased()) selected.")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            } else {
                ForEach(memories) { memory in
                    Text("• \(memory.title): \(memory.body)")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.48, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.sora(11, weight: .medium))
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(10).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
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

    var body: some View {
        AppScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if store.codeModules.isEmpty {
                    AIConfigsEmptyState(
                        title: "No module graph yet",
                        message: "Module classification starts with project events and path-scoped memories.",
                        symbol: "square.stack.3d.up"
                    )
                    .frame(minHeight: 320)
                } else {
                    ForEach(store.codeModules) { module in
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox")
                                .foregroundStyle(Color.stxAccent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(module.title)
                                    .font(.sora(13, weight: .semibold))
                                Text("\(module.memoryCount) memories · \(module.classifier)")
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
            await store.loadCodeModules()
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
                        graphList(title: "Nodes", items: graph.nodes.map { nodeSummary($0) })
                        graphList(title: "Edges", items: graph.edges.map { "\($0.source) -[\($0.kind)]-> \($0.target)" })
                    } else {
                        AIConfigsEmptyState(title: "No graph loaded", message: "Select a project to load its memory graph projection.", symbol: "point.3.connected.trianglepath.dotted")
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

    private func nodeSummary(_ node: CodeMemoryGraphNode) -> String {
        let body = node.body.map { " — \($0.prefix(160))" } ?? ""
        let type = node.type.map { " [\($0)]" } ?? ""
        return "\(node.kind): \(node.title)\(type)\(body)"
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
        AppScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if store.codeProposals.isEmpty {
                    AIConfigsEmptyState(
                        title: "No proposals",
                        message: "mem0 inference and source sync proposals will appear here for review.",
                        symbol: "checklist"
                    )
                    .frame(minHeight: 320)
                } else {
                    ForEach(store.codeProposals) { memory in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(memory.title)
                                    .font(.sora(13, weight: .semibold))
                                    .lineLimit(1)
                                AIConfigsBadge(text: memory.type, color: Color.stxMuted)
                                Spacer(minLength: 8)
                                Button {
                                    Task { await store.acceptProposal(memory) }
                                } label: {
                                    Label("Accept", systemImage: "checkmark")
                                }
                                .controlSize(.small)
                                Button {
                                    Task { await store.rejectProposal(memory) }
                                } label: {
                                    Label("Reject", systemImage: "xmark")
                                }
                                .controlSize(.small)
                            }
                            Text(memory.body)
                                .font(.sora(11))
                                .foregroundStyle(Color.stxMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .appSurface(.compactCard(radius: 8, fillOpacity: 0.62, cornerStyle: .circular, maxWidth: nil), padding: nil)
                    }
                }
            }
            .padding(18)
        }
        .task {
            await store.loadCodeProposals()
        }
    }
}

private struct CodeMemorySettingsView: View {
    @Bindable var store: MemoryStore

    @Environment(AppEnvironment.self) private var env

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
                    sidecarCard
                    adaptersCard
                    shellCard
                    privacyCard
                }
                .padding(.bottom, 24)
            }
        }
        .task {
            await store.refreshCodeMemoryStatus()
        }
    }

    private var sidecarCard: some View {
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
                    Task {
                        env.localAI.restartOpenAICompatibleServerIfNeeded()
                        await store.startCodeMemorySidecar(localAIEnvironment: env.localAI.localAIEnvironment())
                    }
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
                    Task { await store.reindexCodeMemory() }
                } label: {
                    Label("Reindex", systemImage: "arrow.triangle.2.circlepath")
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
            if let result = store.codeOutboxLastDrainResult {
                Text("Outbox: \(result.delivered) delivered, \(result.remaining) pending")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
            if let result = store.codeLastReindexResult {
                Text("Reindex: \(result.enqueued ?? 0) enqueued, \(result.drained?.delivered ?? result.delivered ?? 0) delivered, \(result.drained?.failed ?? result.failed ?? 0) failed")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
            if let sync = store.codeLastSyncSummary {
                Text(sync)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
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
    }

    private var adaptersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Adapters")
                .font(.sora(15, weight: .semibold))
            if let adapters = store.codeHealth?.adapters, !adapters.isEmpty {
                ForEach(adapters.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack(spacing: 10) {
                        Text(key)
                            .font(.sora(11, weight: .medium))
                            .frame(width: 90, alignment: .leading)
                        AIConfigsBadge(text: value, color: value == "ok" ? Color.stxAccent : Color.stxMuted)
                        Spacer(minLength: 0)
                    }
                }
            } else {
                Text("mem0 and Graphiti health appears here after memoryd starts with complete local mode enabled.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private var shellCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shell Capture")
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
        }
        .padding(16)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy")
                .font(.sora(15, weight: .semibold))
            Text("Terminal output is captured only when you use run or pipe. Shell integration records command metadata only: command, cwd, exit status, and timestamp. Events are written to memoryd or a local outbox when memoryd is offline.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
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
                if let evidence = result.evidence, !evidence.isEmpty {
                    Text(evidence.map(\.adapter).joined(separator: " + "))
                        .font(.sora(10).monospaced())
                        .foregroundStyle(Color.stxAccent)
                        .lineLimit(1)
                } else {
                    Text(result.matchKind)
                        .font(.sora(10).monospaced())
                        .foregroundStyle(Color.stxMuted)
                }
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

private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}
