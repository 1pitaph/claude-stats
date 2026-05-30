import SwiftUI

struct MemoryGraphWorkspaceView: View {
    @Bindable var store: MemoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            StxRule()
            if store.graph.layer == .knowledge {
                HStack(spacing: 0) {
                    MemoryGraphCanvasView(graphStore: store.graph)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Rectangle()
                        .fill(Color.stxStroke)
                        .frame(width: 1)
                    MemoryGraphInspectorView(store: store)
                        .frame(width: 330)
                }
            } else {
                MemoryGraphChangesView(store: store)
            }
        }
        .task(id: store.codeSelectedProjectID) {
            await loadCurrentLayerIfNeeded()
        }
        .task(id: store.graph.layer) {
            await loadCurrentLayerIfNeeded()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("Layer", selection: Binding(
                get: { store.graph.layer },
                set: { store.graph.layer = $0 }
            )) {
                ForEach(MemoryGraphLayer.allCases) { layer in
                    Text(layer.title).tag(layer)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 186)

            searchField

            Menu {
                Button("All Projects") {
                    store.codeSelectedProjectID = nil
                }
                Divider()
                ForEach(store.codeProjects) { project in
                    Button(project.projectID) {
                        Task { await store.selectCodeProject(project.projectID) }
                    }
                }
            } label: {
                Label(store.codeSelectedProjectID?.memoryAbbreviatingHomeDirectory ?? "Project", systemImage: "folder")
            }
            .menuStyle(.button)
            .controlSize(.small)

            if store.graph.layer == .knowledge {
                Menu {
                    Button("All Kinds") {
                        store.graph.selectedKinds = Set(store.graph.nodeKinds)
                    }
                    Button("None") {
                        store.graph.selectedKinds = []
                    }
                    Divider()
                    ForEach(store.graph.nodeKinds, id: \.self) { kind in
                        Button {
                            if store.graph.selectedKinds.contains(kind) {
                                store.graph.selectedKinds.remove(kind)
                            } else {
                                store.graph.selectedKinds.insert(kind)
                            }
                        } label: {
                            Label(kind, systemImage: store.graph.selectedKinds.contains(kind) ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    Label("Kinds", systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.button)
                .controlSize(.small)

                Toggle("Canonical", isOn: Binding(
                    get: { store.graph.showCanonical },
                    set: { store.graph.showCanonical = $0 }
                ))
                    .toggleStyle(.checkbox)
                    .font(.sora(11))
                Toggle("Episodes", isOn: Binding(
                    get: { store.graph.showEpisodes },
                    set: { store.graph.showEpisodes = $0 }
                ))
                    .toggleStyle(.checkbox)
                    .font(.sora(11))
                Toggle("Graphiti", isOn: Binding(
                    get: { store.graph.showGraphiti },
                    set: { store.graph.showGraphiti = $0 }
                ))
                    .toggleStyle(.checkbox)
                    .font(.sora(11))
            }

            Spacer(minLength: 8)

            if store.graph.layer == .knowledge {
                MemoryGraphTimeControl(graphStore: store.graph)
            }

            Button {
                store.graph.zoom = max(0.45, store.graph.zoom - 0.1)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .controlSize(.small)
            .help("Zoom Out")

            Slider(value: Binding(
                get: { store.graph.zoom },
                set: { store.graph.zoom = $0 }
            ), in: 0.45...2.2)
                .frame(width: 90)

            Button {
                store.graph.zoom = min(2.2, store.graph.zoom + 0.1)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .controlSize(.small)
            .help("Zoom In")

            Button {
                store.graph.resetViewport()
            } label: {
                Image(systemName: "viewfinder")
            }
            .controlSize(.small)
            .help("Reset View")

            Button {
                Task { await reloadCurrentLayer() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(store.codeSelectedProjectID == nil || store.graph.isLoading || store.graph.isLoadingChanges)
        }
        .padding(14)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color.stxMuted)
            TextField(searchPlaceholder, text: Binding(
                get: { store.graph.layer == .knowledge ? store.graph.searchText : store.graph.changeSearchText },
                set: { value in
                    if store.graph.layer == .knowledge {
                        store.graph.searchText = value
                    } else {
                        store.graph.changeSearchText = value
                    }
                }
            ))
                .textFieldStyle(.plain)
                .font(.sora(12))
            if !currentSearchText.isEmpty {
                Button {
                    if store.graph.layer == .knowledge {
                        store.graph.searchText = ""
                    } else {
                        store.graph.changeSearchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxMuted)
                .help("Clear")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .frame(width: store.graph.layer == .knowledge ? 190 : 240)
    }

    private var searchPlaceholder: String {
        store.graph.layer == .knowledge ? "Find node or fact" : "Event type or memory id"
    }

    private var currentSearchText: String {
        store.graph.layer == .knowledge ? store.graph.searchText : store.graph.changeSearchText
    }

    private func loadCurrentLayerIfNeeded() async {
        switch store.graph.layer {
        case .knowledge:
            await store.loadCodeGraphIfNeeded()
        case .changes:
            guard let projectID = store.codeSelectedProjectID ?? store.codeProjects.first?.projectID else { return }
            if store.graph.changeGraph?.projectID != projectID {
                await store.graph.loadChanges(projectID: projectID)
            }
        }
    }

    private func reloadCurrentLayer() async {
        switch store.graph.layer {
        case .knowledge:
            await store.loadCodeGraph()
        case .changes:
            await store.graph.loadChanges(projectID: store.codeSelectedProjectID)
        }
    }
}

private struct MemoryGraphTimeControl: View {
    @Bindable var graphStore: MemoryGraphStore

    private var range: ClosedRange<Double> {
        MemoryGraphTemporalRange.range(for: graphStore.graph)
    }

    var body: some View {
        HStack(spacing: 6) {
            Toggle("Time", isOn: Binding(
                get: { graphStore.asOf != nil },
                set: { enabled in graphStore.asOf = enabled ? range.upperBound : nil }
            ))
            .toggleStyle(.checkbox)
            .font(.sora(11))

            Slider(
                value: Binding(
                    get: { graphStore.asOf ?? range.upperBound },
                    set: { graphStore.asOf = $0 }
                ),
                in: range
            )
            .frame(width: 110)
            .disabled(graphStore.asOf == nil)
        }
    }
}

private struct MemoryGraphInspectorView: View {
    @Bindable var store: MemoryStore

    var body: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 14) {
                graphStats
                selection
            }
            .padding(14)
        }
    }

    private var graphStats: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Graph")
                .font(.sora(13, weight: .semibold))
            HStack(spacing: 10) {
                AIConfigsMiniStat(value: "\(store.codeGraph?.nodes.count ?? 0)", label: "nodes")
                AIConfigsMiniStat(value: "\(store.codeGraph?.edges.count ?? 0)", label: "edges")
            }
            if let graph = store.codeGraph, graph.truncated == true {
                let totalNodes = graph.totalNodes ?? graph.nodes.count
                let totalEdges = graph.totalEdges ?? graph.edges.count
                inspectorFact("limited", "\(graph.nodes.count)/\(totalNodes) nodes, \(graph.edges.count)/\(totalEdges) edges")
            }
            if let projectID = store.codeGraph?.projectID {
                inspectorFact("project", projectID.memoryAbbreviatingHomeDirectory)
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.54, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    @ViewBuilder
    private var selection: some View {
        if let node = store.graph.selectedNode {
            nodeInspector(node)
        } else if let edge = store.graph.selectedEdge {
            edgeInspector(edge)
        } else {
            MemoryEmptyState(title: "No selection", message: "Select a node or edge.", symbol: "cursorarrow.click")
                .frame(minHeight: 220)
        }
    }

    private func nodeInspector(_ node: CodeMemoryGraphNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: MemoryGraphStyle.symbol(for: node.kind))
                    .foregroundStyle(MemoryGraphStyle.color(for: node.kind))
                Text(node.title)
                    .font(.sora(14, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            inspectorFact("id", node.id)
            inspectorFact("kind", node.kind)
            if let type = node.type {
                inspectorFact("type", type)
            }
            if let status = node.status {
                inspectorFact("status", status)
            }
            if let seq = node.seq {
                inspectorFact("seq", "\(seq)")
            }
            if let body = node.body, !body.isEmpty {
                Text(body)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            metadata(node.metadata)
            if let sourceRefs = node.sourceRefs, !sourceRefs.isEmpty {
                MemorySourceRefsView(sourceRefs: sourceRefs)
            }
            if let memoryID = memoryID(from: node) {
                MemoryGraphMemoryHistorySection(graphStore: store.graph, memoryID: memoryID)
            }
            HStack(spacing: 8) {
                MemoryCopyButton(value: node.id, label: "Copy ID", systemImage: "link")
                if let body = node.body {
                    MemoryCopyButton(value: body, label: "Copy Text")
                }
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.54, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private func edgeInspector(_ edge: CodeMemoryGraphEdge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(Color.stxAccent)
                Text(edge.kind)
                    .font(.sora(14, weight: .semibold))
                Spacer(minLength: 0)
            }
            inspectorFact("source", edge.source)
            inspectorFact("target", edge.target)
            if let fact = edge.factText, !fact.isEmpty {
                Text(fact)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let validAt = edge.validAtLabel {
                inspectorFact("valid", validAt)
            }
            if let invalidAt = edge.invalidAtLabel {
                inspectorFact("invalid", invalidAt)
            }
            metadata(edge.metadata)
            HStack(spacing: 8) {
                MemoryCopyButton(value: edge.id, label: "Copy ID", systemImage: "link")
                if let fact = edge.factText {
                    MemoryCopyButton(value: fact, label: "Copy Fact")
                }
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.54, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    @ViewBuilder
    private func metadata(_ metadata: [String: String]?) -> some View {
        if let metadata, !metadata.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Metadata")
                    .font(.sora(12, weight: .semibold))
                ForEach(metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    inspectorFact(key, value)
                }
            }
        }
    }

    private func memoryID(from node: CodeMemoryGraphNode) -> String? {
        guard node.kind == "memory" else { return nil }
        if let memoryID = node.metadata?["memory_id"], !memoryID.isEmpty {
            return memoryID
        }
        let prefix = "memory:"
        if node.id.hasPrefix(prefix) {
            return String(node.id.dropFirst(prefix.count))
        }
        return node.id
    }

    private func inspectorFact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.sora(10).monospaced())
                .foregroundStyle(Color.stxMuted)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.sora(10).monospaced())
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}
