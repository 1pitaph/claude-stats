import SwiftUI

struct MemoryGraphChangesView: View {
    @Bindable var store: MemoryStore

    var body: some View {
        HStack(spacing: 0) {
            MemoryChangeTimelineView(store: store)
                .frame(width: 330)
            Rectangle()
                .fill(Color.stxStroke)
                .frame(width: 1)
            MemoryChangeGraphCanvasView(graphStore: store.graph)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle()
                .fill(Color.stxStroke)
                .frame(width: 1)
            MemoryGraphChangeInspectorView(store: store)
                .frame(width: 330)
        }
    }
}

private struct MemoryChangeTimelineView: View {
    @Bindable var store: MemoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Timeline")
                    .font(.sora(13, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(store.graph.filteredChangeEvents.count)")
                    .font(.sora(10, weight: .semibold).monospaced())
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            StxRule()

            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if store.graph.isLoadingChanges {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if store.graph.filteredChangeEvents.isEmpty {
                        MemoryEmptyState(
                            title: "No changes",
                            message: store.graph.changeLastError ?? "No memory events match this filter.",
                            symbol: "clock.arrow.circlepath"
                        )
                        .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        ForEach(store.graph.filteredChangeEvents) { event in
                            MemoryChangeTimelineRow(
                                event: event,
                                isSelected: store.graph.selectedChangeEvent?.eventID == event.eventID
                            ) {
                                store.graph.selectChangeEvent(event.eventID)
                                if let memoryID = event.memoryID {
                                    Task { await store.graph.loadHistory(memoryID: memoryID) }
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Color.primary.opacity(0.018))
    }
}

private struct MemoryChangeTimelineRow: View {
    let event: CodeMemoryEvent
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("#\(event.seq)")
                        .font(.sora(10, weight: .semibold).monospaced())
                        .foregroundStyle(Color.stxMuted)
                    Text(event.eventType)
                        .font(.sora(11, weight: .semibold))
                        .foregroundStyle(MemoryGraphStyle.color(for: "change_event"))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let status = event.statusTransition {
                        Text(status)
                            .font(.sora(9, weight: .semibold))
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                    }
                }

                Text(event.titleCandidate)
                    .font(.sora(12, weight: .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Label(actorLabel, systemImage: "person.crop.circle")
                        .lineLimit(1)
                    Text(MemoryFormat.timestamp(event.timestamp))
                        .lineLimit(1)
                }
                .font(.sora(9).monospaced())
                .foregroundStyle(Color.stxMuted)
            }
            .padding(10)
            .background(isSelected ? Color.stxAccent.opacity(0.13) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.stxAccent : Color.stxStroke.opacity(0.6), lineWidth: isSelected ? 1.4 : 1))
        }
        .buttonStyle(.plain)
        .help(event.eventID)
    }

    private var actorLabel: String {
        event.actor["id"] ?? event.actor["name"] ?? event.actor["kind"] ?? "system"
    }
}

private struct MemoryChangeGraphCanvasView: View {
    @Bindable var graphStore: MemoryGraphStore
    @State private var dragStart = CGSize.zero
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            graphContent(size: proxy.size)
        }
        .background(Color.primary.opacity(0.012))
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !isDragging {
                        dragStart = graphStore.pan
                        isDragging = true
                    }
                    graphStore.pan = CGSize(
                        width: dragStart.width + value.translation.width,
                        height: dragStart.height + value.translation.height
                    )
                }
                .onEnded { _ in isDragging = false }
        )
    }

    @ViewBuilder
    private func graphContent(size: CGSize) -> some View {
        if let graph = visibleGraph, !graph.nodes.isEmpty {
            let positions = MemoryGraphLayout.positions(
                for: graph.nodes,
                in: size,
                pan: graphStore.pan,
                zoom: CGFloat(graphStore.zoom)
            )

            ZStack {
                Canvas { context, _ in
                    drawEdges(graph.edges, positions: positions, in: &context)
                }

                ForEach(graph.edges) { edge in
                    if let midpoint = MemoryGraphLayout.midpoint(for: edge, positions: positions) {
                        Button {
                            graphStore.selectChangeEdge(edge.id)
                            if let memoryID = edge.metadata?["memory_id"] {
                                Task { await graphStore.loadHistory(memoryID: memoryID) }
                            }
                        } label: {
                            Circle()
                                .fill(graphStore.selectedChangeEdgeID == edge.id ? Color.stxAccent : edgeColor(edge).opacity(0.42))
                                .frame(width: graphStore.selectedChangeEdgeID == edge.id ? 10 : 7, height: graphStore.selectedChangeEdgeID == edge.id ? 10 : 7)
                        }
                        .buttonStyle(.plain)
                        .position(midpoint)
                        .help(edge.kind)
                    }
                }

                ForEach(graph.nodes) { node in
                    if let position = positions[node.id] {
                        MemoryGraphNodeView(
                            node: node,
                            isSelected: graphStore.selectedChangeNodeID == node.id,
                            isHighlighted: isHighlighted(node)
                        ) {
                            graphStore.selectChangeNode(node.id)
                            if let memoryID = node.metadata?["memory_id"] {
                                Task { await graphStore.loadHistory(memoryID: memoryID) }
                            }
                        }
                        .position(position)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        } else {
            MemoryEmptyState(
                title: graphStore.isLoadingChanges ? "Loading changes" : "No changes loaded",
                message: graphStore.changeLastError ?? "Select a project.",
                symbol: "arrow.triangle.2.circlepath"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var visibleGraph: CodeMemoryGraph? {
        guard let graph = graphStore.changeGraph else { return nil }
        let search = graphStore.changeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return graph }

        let eventNodeIDs = Set(graphStore.filteredChangeEvents.map { MemoryChangeGraphBuilder.eventNodeID($0.eventID) })
        var includedNodeIDs = eventNodeIDs
        var includedEdges: [CodeMemoryGraphEdge] = []

        for edge in graph.edges where eventNodeIDs.contains(edge.source) || eventNodeIDs.contains(edge.target) {
            includedEdges.append(edge)
            includedNodeIDs.insert(edge.source)
            includedNodeIDs.insert(edge.target)
        }
        for edge in graph.edges where includedNodeIDs.contains(edge.source) && edge.kind == "FROM_SOURCE" {
            includedEdges.append(edge)
            includedNodeIDs.insert(edge.target)
        }

        return CodeMemoryGraph(
            projectID: graph.projectID,
            nodes: graph.nodes.filter { includedNodeIDs.contains($0.id) },
            edges: dedupe(includedEdges.filter { includedNodeIDs.contains($0.source) && includedNodeIDs.contains($0.target) })
        )
    }

    private func drawEdges(_ edges: [CodeMemoryGraphEdge], positions: [String: CGPoint], in context: inout GraphicsContext) {
        for edge in edges {
            guard let source = positions[edge.source], let target = positions[edge.target] else { continue }
            var path = Path()
            path.move(to: source)
            path.addLine(to: target)
            let selected = graphStore.selectedChangeEdgeID == edge.id
            context.stroke(path, with: .color(selected ? Color.stxAccent : edgeColor(edge).opacity(0.64)), lineWidth: selected ? 2 : 1)
        }
    }

    private func edgeColor(_ edge: CodeMemoryGraphEdge) -> Color {
        switch edge.kind {
        case "NEXT_EVENT":
            Color.stxMuted
        case "AFFECTS":
            MemoryGraphStyle.color(for: "change_event")
        case "FROM_SOURCE":
            MemoryGraphStyle.color(for: "episode")
        default:
            Color.stxStroke
        }
    }

    private func isHighlighted(_ node: CodeMemoryGraphNode) -> Bool {
        let search = graphStore.changeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !search.isEmpty else { return false }
        return "\(node.title) \(node.body ?? "") \(node.kind) \(node.status ?? "")"
            .lowercased()
            .contains(search)
    }

    private func dedupe(_ edges: [CodeMemoryGraphEdge]) -> [CodeMemoryGraphEdge] {
        var seen: Set<String> = []
        var result: [CodeMemoryGraphEdge] = []
        for edge in edges where seen.insert(edge.id).inserted {
            result.append(edge)
        }
        return result
    }
}

private struct MemoryGraphChangeInspectorView: View {
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
            Text("Changes")
                .font(.sora(13, weight: .semibold))
            HStack(spacing: 10) {
                AIConfigsMiniStat(value: "\(store.graph.events.count)", label: "events")
                AIConfigsMiniStat(value: "\(store.graph.changeGraph?.nodes.count ?? 0)", label: "nodes")
                AIConfigsMiniStat(value: "\(store.graph.changeGraph?.edges.count ?? 0)", label: "edges")
            }
            if let projectID = store.graph.changeGraph?.projectID {
                MemoryGraphInspectorFactRow(label: "project", value: projectID.memoryAbbreviatingHomeDirectory)
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.54, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    @ViewBuilder
    private var selection: some View {
        if let event = store.graph.selectedChangeEvent {
            eventInspector(event)
        } else if let memoryID = store.graph.selectedChangeMemoryID {
            memoryInspector(memoryID)
        } else if let node = store.graph.selectedChangeNode {
            nodeInspector(node)
        } else if let edge = store.graph.selectedChangeEdge {
            edgeInspector(edge)
        } else {
            MemoryEmptyState(title: "No selection", message: "Select an event, memory, or edge.", symbol: "cursorarrow.click")
                .frame(minHeight: 220)
        }
    }

    private func eventInspector(_ event: CodeMemoryEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: MemoryGraphStyle.symbol(for: "change_event"))
                    .foregroundStyle(MemoryGraphStyle.color(for: "change_event"))
                Text(event.eventType)
                    .font(.sora(14, weight: .semibold))
                Spacer(minLength: 0)
            }
            MemoryGraphInspectorFactRow(label: "seq", value: "\(event.seq)")
            MemoryGraphInspectorFactRow(label: "event", value: event.eventID)
            MemoryGraphInspectorFactRow(label: "memory", value: event.memoryID ?? "-")
            MemoryGraphInspectorFactRow(label: "actor", value: event.actor["id"] ?? event.actor["kind"] ?? "system")
            MemoryGraphInspectorFactRow(label: "time", value: MemoryFormat.timestamp(event.timestamp))
            if let status = event.statusTransition {
                MemoryGraphInspectorFactRow(label: "status", value: status)
            }
            MemoryChangePayloadDiffView(before: event.before, after: event.after, delta: event.delta)
            if !event.sourceRefs.isEmpty {
                MemorySourceRefsView(sourceRefs: event.sourceRefs)
            }
            HStack(spacing: 8) {
                MemoryCopyButton(value: event.eventID, label: "Copy Event", systemImage: "link")
                if let memoryID = event.memoryID {
                    MemoryCopyButton(value: memoryID, label: "Copy Memory")
                }
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.54, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private func memoryInspector(_ memoryID: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: MemoryGraphStyle.symbol(for: "memory"))
                    .foregroundStyle(MemoryGraphStyle.color(for: "memory"))
                Text(memoryID)
                    .font(.sora(14, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            MemoryGraphInspectorFactRow(label: "id", value: memoryID)
            MemoryGraphMemoryHistorySection(graphStore: store.graph, memoryID: memoryID)
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.54, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private func nodeInspector(_ node: CodeMemoryGraphNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(node.title)
                .font(.sora(14, weight: .semibold))
                .lineLimit(2)
            MemoryGraphInspectorFactRow(label: "id", value: node.id)
            MemoryGraphInspectorFactRow(label: "kind", value: node.kind)
            if let body = node.body, !body.isEmpty {
                Text(body)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let sourceRefs = node.sourceRefs, !sourceRefs.isEmpty {
                MemorySourceRefsView(sourceRefs: sourceRefs)
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.54, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private func edgeInspector(_ edge: CodeMemoryGraphEdge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(edge.kind)
                .font(.sora(14, weight: .semibold))
            MemoryGraphInspectorFactRow(label: "source", value: edge.source)
            MemoryGraphInspectorFactRow(label: "target", value: edge.target)
            if let fact = edge.factText, !fact.isEmpty {
                Text(fact)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let metadata = edge.metadata {
                ForEach(metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    MemoryGraphInspectorFactRow(label: key, value: value)
                }
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.54, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }
}

private struct MemoryChangePayloadDiffView: View {
    let before: CodeMemoryEventPayload?
    let after: CodeMemoryEventPayload?
    let delta: CodeMemoryEventPayload?

    private var keys: [String] {
        var result: Set<String> = []
        if let before {
            result.formUnion(before.keys)
        }
        if let after {
            result.formUnion(after.keys)
        }
        if let delta {
            result.formUnion(delta.keys)
        }
        return result.sorted()
    }

    var body: some View {
        if !keys.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Diff")
                    .font(.sora(12, weight: .semibold))
                ForEach(keys, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(key)
                            .font(.sora(10, weight: .semibold).monospaced())
                            .foregroundStyle(Color.stxMuted)
                        HStack(alignment: .top, spacing: 8) {
                            payloadColumn(title: "before", value: before?[key])
                            payloadColumn(title: "after", value: after?[key])
                        }
                        if let deltaValue = delta?[key] {
                            Text("delta: \(deltaValue.displayString)")
                                .font(.sora(10).monospaced())
                                .foregroundStyle(Color.stxMuted)
                                .lineLimit(4)
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private func payloadColumn(title: String, value: CodeMemoryEventPayloadValue?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.sora(9, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            Text(value?.displayString ?? "-")
                .font(.sora(10).monospaced())
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
