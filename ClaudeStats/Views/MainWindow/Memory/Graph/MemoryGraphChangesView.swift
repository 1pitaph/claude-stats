import SwiftUI

struct MemoryGraphChangesView: View {
    @Bindable var store: MemoryStore

    var body: some View {
        HStack(spacing: 0) {
            MemoryKnowledgeGraphCanvasView(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle()
                .fill(Color.stxStroke)
                .frame(width: 1)
            MemoryKnowledgeGraphInspectorView(store: store)
                .frame(width: 330)
        }
    }
}

private struct MemoryKnowledgeGraphCanvasView: View {
    @Bindable var store: MemoryStore
    @State private var dragStart = CGSize.zero
    @State private var isDragging = false
    @State private var hoveredEdgeID: String?

    var body: some View {
        GeometryReader { proxy in
            graphContent(size: proxy.size)
        }
        .background(Color.primary.opacity(0.012))
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !isDragging {
                        dragStart = store.graph.pan
                        isDragging = true
                    }
                    store.graph.pan = CGSize(
                        width: dragStart.width + value.translation.width,
                        height: dragStart.height + value.translation.height
                    )
                }
                .onEnded { _ in isDragging = false }
        )
    }

    @ViewBuilder
    private func graphContent(size: CGSize) -> some View {
        if store.graph.isLoadingKnowledgeGraph {
            MemoryEmptyState(title: "Loading knowledge graph", message: "Fetching Graphiti entities and facts.", symbol: AppIcon.Action.sync)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let presentation = store.graph.knowledgePresentation, !presentation.isKnowledgeEmpty, !presentation.nodes.isEmpty, !presentation.edges.isEmpty {
            graphCanvas(presentation: presentation, size: size)
        } else if store.graph.knowledgeGraph != nil {
            knowledgeEmptyState
        } else {
            MemoryEmptyState(
                title: "No graph loaded",
                message: store.graph.knowledgeLastError ?? "Select a project and refresh the knowledge graph.",
                symbol: AppIcon.Network.webSocket
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func graphCanvas(presentation: MemoryKnowledgeGraphPresentation, size: CGSize) -> some View {
        let positions = MemoryKnowledgeGraphLayout.positions(
            for: presentation.nodes,
            edges: presentation.edges,
            in: size,
            pan: store.graph.pan,
            zoom: CGFloat(store.graph.zoom)
        )
        let neighborhood = presentation.neighborNodeIDs(
            selectedNodeID: store.graph.selectedKnowledgeNodeID,
            selectedEdgeID: store.graph.selectedKnowledgeEdgeID
        )

        return ZStack {
            Canvas { context, _ in
                drawEdges(presentation.edges, positions: positions, in: &context)
            }

            ForEach(presentation.edges) { edge in
                if let midpoint = MemoryGraphLayout.midpoint(for: edge, positions: positions) {
                    let isSelected = store.graph.selectedKnowledgeEdgeID == edge.id
                    let showsLabel = presentation.edges.count <= 45 || hoveredEdgeID == edge.id || isSelected
                    Button {
                        store.graph.selectKnowledgeEdge(edge.id)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(isSelected ? Color.stxAccent : MemoryGraphStyle.edgeColor(for: edge).opacity(0.75))
                                .frame(width: isSelected ? 10 : 7, height: isSelected ? 10 : 7)
                            if showsLabel {
                                Text(edge.relation)
                                    .font(.sora(8, weight: .semibold))
                                    .foregroundStyle(MemoryGraphStyle.edgeColor(for: edge))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.regularMaterial, in: Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .position(midpoint)
                    .help(edge.fact)
                    .onHover { hovering in
                        hoveredEdgeID = hovering ? edge.id : nil
                    }
                }
            }

            ForEach(presentation.nodes) { node in
                if let position = positions[node.id] {
                    let selected = store.graph.selectedKnowledgeNodeID == node.id
                    let highlighted = isHighlighted(node)
                    MemoryKnowledgeGraphNodeCardView(
                        node: node,
                        isSelected: selected,
                        isHighlighted: highlighted,
                        isDimmed: !neighborhood.isEmpty && !neighborhood.contains(node.id),
                        isCompact: presentation.nodes.count > 80 && !selected && !highlighted
                    ) {
                        store.graph.selectKnowledgeNode(node.id)
                    }
                    .position(position)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(alignment: .top) {
            MemoryKnowledgeGraphSummaryBadge(summary: presentation.summary)
                .padding(.top, 12)
        }
    }

    private var knowledgeEmptyState: some View {
        VStack(spacing: 14) {
            MemoryEmptyState(
                title: "Graphiti knowledge graph is not ready",
                message: knowledgeEmptyMessage,
                symbol: AppIcon.Network.webSocket
            )
            if !knowledgeEmptyDiagnostics.isEmpty {
                MemoryKnowledgeEmptyDiagnosticsView(diagnostics: knowledgeEmptyDiagnostics)
            }
            HStack(spacing: 8) {
                Button {
                    Task { await store.graph.loadGraph(projectID: store.codeSelectedProjectID ?? store.codeProjects.first?.projectID) }
                } label: {
                    Label("Refresh", systemImage: AppIcon.Action.refresh)
                }
                .controlSize(.small)

                Button {
                    Task {
                        await store.reindexCodeMemory()
                        await store.graph.loadGraph(projectID: store.codeSelectedProjectID ?? store.codeProjects.first?.projectID)
                    }
                } label: {
                    Label("Reindex Graphiti", systemImage: AppIcon.Action.sync)
                }
                .controlSize(.small)

                Button {
                    store.section = .settings
                } label: {
                    Label("Open Memory Settings", systemImage: AppIcon.Workspace.settings)
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var knowledgeEmptyMessage: String {
        if let error = store.graph.knowledgeLastError {
            return error
        }
        if let graphitiStatus = store.codeHealth?.adapters["graphiti"],
           graphitiStatus.localizedCaseInsensitiveContains("disabled") {
            return "The /graph endpoint returned data, but Graphiti memory model adapters are disabled, so no Graphiti entities or fact relationships can be rendered."
        }
        if let graph = store.graph.knowledgeGraph, !graph.nodes.isEmpty || !graph.edges.isEmpty {
            return "The /graph endpoint returned raw project/module/memory data, but this view now only renders Graphiti entities and fact relationships."
        }
        return "No Graphiti entities or fact relationships are available for this project yet."
    }

    private var knowledgeEmptyDiagnostics: [MemoryKnowledgeEmptyDiagnostic] {
        var diagnostics: [MemoryKnowledgeEmptyDiagnostic] = []
        if let projectID = store.codeSelectedProjectID ?? store.codeProjects.first?.projectID {
            diagnostics.append(MemoryKnowledgeEmptyDiagnostic(label: "project", value: projectID.memoryAbbreviatingHomeDirectory))
        }
        if let graphitiStatus = store.codeHealth?.adapters["graphiti"] {
            diagnostics.append(MemoryKnowledgeEmptyDiagnostic(label: "graphiti", value: graphitiStatus))
        }
        if let graph = store.graph.knowledgeGraph {
            diagnostics.append(MemoryKnowledgeEmptyDiagnostic(label: "raw graph", value: "\(graph.nodes.count) nodes, \(graph.edges.count) edges returned"))
            let ignoredKinds = graph.nodes.reduce(into: [String: Int]()) { counts, node in
                counts[node.kind, default: 0] += 1
            }
            let kindSummary = ignoredKinds
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value { return lhs.key < rhs.key }
                    return lhs.value > rhs.value
                }
                .prefix(4)
                .map { "\($0.key) \($0.value)" }
                .joined(separator: ", ")
            if !kindSummary.isEmpty {
                diagnostics.append(MemoryKnowledgeEmptyDiagnostic(label: "ignored", value: kindSummary))
            }
        }
        if let presentation = store.graph.knowledgePresentation {
            diagnostics.append(MemoryKnowledgeEmptyDiagnostic(label: "knowledge", value: "\(presentation.totalEntityCount) Graphiti entities, \(presentation.totalFactCount) fact edges"))
        }
        return diagnostics
    }

    private func drawEdges(_ edges: [MemoryKnowledgeGraphPresentation.Edge], positions: [String: CGPoint], in context: inout GraphicsContext) {
        for edge in edges {
            guard let source = positions[edge.source], let target = positions[edge.target] else { continue }
            var path = Path()
            path.move(to: source)
            path.addLine(to: target)
            let isSelected = store.graph.selectedKnowledgeEdgeID == edge.id
            let color = isSelected ? Color.stxAccent : MemoryGraphStyle.edgeColor(for: edge).opacity(edge.isActive ? 0.72 : 0.42)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: isSelected ? 2.2 : 1.15, lineCap: .round, dash: edge.isActive ? [] : [4, 4]))
            drawArrowHead(from: source, to: target, color: color, in: &context)
        }
    }

    private func drawArrowHead(from source: CGPoint, to target: CGPoint, color: Color, in context: inout GraphicsContext) {
        let dx = target.x - source.x
        let dy = target.y - source.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let unitX = dx / length
        let unitY = dy / length
        let tip = CGPoint(x: target.x - unitX * 118, y: target.y - unitY * 44)
        let base = CGPoint(x: tip.x - unitX * 8, y: tip.y - unitY * 8)
        let perpendicular = CGPoint(x: -unitY * 4.5, y: unitX * 4.5)
        var arrow = Path()
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: base.x + perpendicular.x, y: base.y + perpendicular.y))
        arrow.addLine(to: CGPoint(x: base.x - perpendicular.x, y: base.y - perpendicular.y))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(color))
    }

    private func isHighlighted(_ node: MemoryKnowledgeGraphPresentation.Node) -> Bool {
        let search = store.graph.knowledgeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !search.isEmpty else { return false }
        return "\(node.displayTitle) \(node.subtitle ?? "") \(node.badges.joined(separator: " ")) \(node.helpText)"
            .lowercased()
            .contains(search)
    }
}

private struct MemoryKnowledgeGraphSummaryBadge: View {
    let summary: String

    var body: some View {
        Text(summary)
            .font(.sora(10, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.055), in: Capsule())
    }
}

private struct MemoryKnowledgeEmptyDiagnostic: Identifiable, Hashable {
    let label: String
    let value: String

    var id: String { "\(label):\(value)" }
}

private struct MemoryKnowledgeEmptyDiagnosticsView: View {
    let diagnostics: [MemoryKnowledgeEmptyDiagnostic]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            diagnosticRow(at: 0)
            diagnosticRow(at: 1)
            diagnosticRow(at: 2)
            diagnosticRow(at: 3)
            diagnosticRow(at: 4)
        }
        .padding(12)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1))
    }

    @ViewBuilder
    private func diagnosticRow(at index: Int) -> some View {
        if diagnostics.indices.contains(index) {
            diagnosticRow(diagnostics[index])
        }
    }

    private func diagnosticRow(_ item: MemoryKnowledgeEmptyDiagnostic) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.label)
                .font(.sora(10, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 90, alignment: .leading)
            Text(item.value)
                .font(.sora(10))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

private struct MemoryKnowledgeGraphInspectorView: View {
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
            Text("Knowledge Graph")
                .font(.sora(13, weight: .semibold))
            if let presentation = store.graph.knowledgePresentation {
                HStack(spacing: 10) {
                    AIConfigsMiniStat(value: "\(presentation.totalEntityCount)", label: "entities")
                    AIConfigsMiniStat(value: "\(presentation.totalFactCount)", label: "facts")
                    AIConfigsMiniStat(value: "\(presentation.activeFactCount)", label: "active")
                }
                MemoryGraphInspectorFactRow(label: "project", value: presentation.projectID.memoryAbbreviatingHomeDirectory)
                MemoryGraphInspectorFactRow(label: "view", value: store.graph.factVisibility.label)
                Text(presentation.summary)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(store.graph.knowledgeLastError ?? "No graph loaded.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.54, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    @ViewBuilder
    private var selection: some View {
        if let edge = store.graph.selectedKnowledgeEdge {
            edgeInspector(edge)
        } else if let node = store.graph.selectedKnowledgeNode {
            nodeInspector(node)
        } else {
            MemoryEmptyState(title: "No selection", message: "Select an entity or fact relationship.", symbol: AppIcon.Pointer.click)
                .frame(minHeight: 220)
        }
    }

    private func nodeInspector(_ node: MemoryKnowledgeGraphPresentation.Node) -> some View {
        let connectedEdges = store.graph.knowledgePresentation?.connectedEdges(for: node.id) ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: MemoryGraphStyle.symbol(for: node.rawNode.kind))
                    .foregroundStyle(MemoryGraphStyle.color(for: node))
                Text(node.displayTitle)
                    .font(.sora(14, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            MemoryGraphInspectorFactRow(label: "id", value: node.id)
            MemoryGraphInspectorFactRow(label: "facts", value: "\(node.degree)")
            if let summary = node.subtitle, !summary.isEmpty {
                Text(summary)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !node.labels.isEmpty {
                badgeRow(title: "Labels", values: node.labels)
            }
            if !node.attributes.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Attributes")
                        .font(.sora(10, weight: .semibold))
                        .foregroundStyle(Color.stxMuted)
                    ForEach(node.attributes.sorted(by: { $0.key < $1.key }).prefix(8), id: \.key) { key, value in
                        MemoryGraphInspectorFactRow(label: key, value: value)
                    }
                }
            }
            if !node.episodeIDs.isEmpty {
                badgeRow(title: "Episodes", values: node.episodeIDs)
            }
            if !connectedEdges.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Connected Facts")
                        .font(.sora(12, weight: .semibold))
                    ForEach(connectedEdges.prefix(8)) { edge in
                        Button {
                            store.graph.selectKnowledgeEdge(edge.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(edge.relation)
                                    .font(.sora(10, weight: .semibold))
                                Text(edge.fact)
                                    .font(.sora(10))
                                    .foregroundStyle(Color.stxMuted)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(7)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            rawMetadata(node.rawNode.metadata)
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.54, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private func edgeInspector(_ edge: MemoryKnowledgeGraphPresentation.Edge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: AppIcon.Network.webSocket)
                    .foregroundStyle(MemoryGraphStyle.edgeColor(for: edge))
                Text(edge.relation)
                    .font(.sora(14, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            if let presentation = store.graph.knowledgePresentation {
                MemoryGraphInspectorFactRow(label: "source", value: presentation.node(id: edge.source)?.displayTitle ?? edge.source)
                MemoryGraphInspectorFactRow(label: "target", value: presentation.node(id: edge.target)?.displayTitle ?? edge.target)
            }
            MemoryGraphInspectorFactRow(label: "status", value: edge.isActive ? "active" : "inactive")
            if let validAt = edge.validAt {
                MemoryGraphInspectorFactRow(label: "valid", value: validAt)
            }
            if let invalidAt = edge.invalidAt {
                MemoryGraphInspectorFactRow(label: "invalid", value: invalidAt)
            }
            if let expiredAt = edge.expiredAt {
                MemoryGraphInspectorFactRow(label: "expired", value: expiredAt)
            }
            if let referenceTime = edge.referenceTime {
                MemoryGraphInspectorFactRow(label: "reference", value: referenceTime)
            }
            Text(edge.fact)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
            if !edge.episodeIDs.isEmpty {
                badgeRow(title: "Episodes", values: edge.episodeIDs)
            }
            rawMetadata(edge.rawEdge.metadata)
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.54, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private func badgeRow(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.sora(10, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            FlowBadgeRow(values: values)
        }
    }

    @ViewBuilder
    private func rawMetadata(_ metadata: [String: String]?) -> some View {
        if let metadata, !metadata.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        MemoryGraphInspectorFactRow(label: key, value: value)
                    }
                }
                .padding(.top, 5)
            } label: {
                Text("Raw Metadata")
                    .font(.sora(11, weight: .semibold))
            }
        }
    }
}

private struct FlowBadgeRow: View {
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { value in
                        Text(value)
                            .font(.sora(9, weight: .semibold).monospaced())
                            .foregroundStyle(Color.stxAccent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.stxAccent.opacity(0.11), in: Capsule())
                    }
                }
            }
        }
    }

    private var rows: [[String]] {
        var result: [[String]] = [[]]
        var currentWidth = 0
        for value in values.prefix(9) {
            let estimated = max(5, value.count) + 2
            if currentWidth + estimated > 34, result.last?.isEmpty == false {
                result.append([value])
                currentWidth = estimated
            } else {
                result[result.count - 1].append(value)
                currentWidth += estimated
            }
        }
        return result.filter { !$0.isEmpty }
    }
}
