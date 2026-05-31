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
    @State private var hoveredEdgeID: String?
    @State private var selectedDisplayEdgeID: String?

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
        if let presentation = graphStore.changePresentation, !presentation.nodes.isEmpty {
            let positions = MemoryChangeGraphLayout.positions(
                for: presentation.nodes,
                in: size,
                pan: graphStore.pan,
                zoom: CGFloat(graphStore.zoom)
            )
            let selectedNodeID = selectedPresentationNodeID(in: presentation)
            let neighborhood = presentation.neighborNodeIDs(
                selectedNodeID: selectedNodeID,
                selectedEdgeID: selectedDisplayEdgeID,
                selectedGroupID: graphStore.selectedChangeGroupID
            )

            ZStack {
                Canvas { context, _ in
                    drawEdges(presentation.edges, positions: positions, in: &context)
                }

                ForEach(presentation.edges) { edge in
                    if let midpoint = MemoryGraphLayout.midpoint(for: edge, positions: positions) {
                        let showsLabel = hoveredEdgeID == edge.id || selectedDisplayEdgeID == edge.id
                        Button {
                            selectedDisplayEdgeID = edge.id
                            if let eventID = edge.eventIDs.first {
                                graphStore.selectChangeEvent(eventID)
                                if let memoryID = graphStore.selectedChangeEvent?.memoryID {
                                    Task { await graphStore.loadHistory(memoryID: memoryID) }
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(selectedDisplayEdgeID == edge.id ? Color.stxAccent : MemoryGraphStyle.edgeColor(for: edge.kind).opacity(0.48))
                                    .frame(width: selectedDisplayEdgeID == edge.id ? 10 : 7, height: selectedDisplayEdgeID == edge.id ? 10 : 7)
                                if showsLabel {
                                    Text(edge.label)
                                        .font(.sora(8, weight: .semibold))
                                        .foregroundStyle(MemoryGraphStyle.edgeColor(for: edge.kind))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(.regularMaterial, in: Capsule())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .position(midpoint)
                        .help(edge.label)
                        .onHover { isHovering in
                            hoveredEdgeID = isHovering ? edge.id : nil
                        }
                    }
                }

                ForEach(presentation.nodes) { node in
                    if let position = positions[node.id] {
                        let isSelected = isSelected(node)
                        let highlighted = isHighlighted(node)
                        MemoryGraphNodeCardView(
                            node: node,
                            isSelected: isSelected,
                            isHighlighted: highlighted,
                            isDimmed: !neighborhood.isEmpty && !neighborhood.contains(node.id),
                            isCompact: presentation.nodes.count > 90
                                && !isSelected
                                && !highlighted
                                && node.kind != "group"
                        ) {
                            select(node)
                        }
                        .position(position)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    MemoryGraphLaneHeaderView()
                    MemoryGraphSummaryBadge(summary: presentation.summary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
        } else {
            MemoryEmptyState(
                title: graphStore.isLoadingChanges ? "Loading changes" : "No changes loaded",
                message: graphStore.changeLastError ?? "Select a project.",
                symbol: "arrow.triangle.2.circlepath"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func selectedPresentationNodeID(in presentation: MemoryGraphPresentation) -> String? {
        if let selectedChangeGroupID = graphStore.selectedChangeGroupID {
            return selectedChangeGroupID
        }
        if let selectedChangeNodeID = graphStore.selectedChangeNodeID {
            return presentation.nodes.first { node in
                node.rawNodeID == selectedChangeNodeID || node.id == selectedChangeNodeID
            }?.id
        }
        return nil
    }

    private func isSelected(_ node: MemoryGraphPresentation.Node) -> Bool {
        if let groupID = node.groupID, groupID == graphStore.selectedChangeGroupID {
            return true
        }
        if let rawNodeID = node.rawNodeID, rawNodeID == graphStore.selectedChangeNodeID {
            return true
        }
        if let eventID = node.eventID, eventID == graphStore.selectedChangeEvent?.eventID {
            return true
        }
        return false
    }

    private func select(_ node: MemoryGraphPresentation.Node) {
        if let groupID = node.groupID, node.kind == "group" {
            graphStore.selectChangeGroup(groupID)
            return
        }
        if let eventID = node.eventID {
            graphStore.selectChangeEvent(eventID)
            if let memoryID = node.memoryID {
                Task { await graphStore.loadHistory(memoryID: memoryID) }
            }
            return
        }
        if let rawNodeID = node.rawNodeID {
            graphStore.selectChangeNode(rawNodeID)
            if let memoryID = node.memoryID {
                Task { await graphStore.loadHistory(memoryID: memoryID) }
            }
        }
    }

    private func drawEdges(_ edges: [MemoryGraphPresentation.Edge], positions: [String: CGPoint], in context: inout GraphicsContext) {
        for edge in edges {
            guard let source = positions[edge.source], let target = positions[edge.target] else { continue }
            var path = Path()
            path.move(to: source)
            path.addLine(to: target)
            let selected = selectedDisplayEdgeID == edge.id
            let color = selected ? Color.stxAccent : MemoryGraphStyle.edgeColor(for: edge.kind).opacity(0.68)
            context.stroke(path, with: .color(color), style: MemoryGraphStyle.edgeStrokeStyle(for: edge.kind, isSelected: selected))
            if edge.kind != "NEXT_EVENT" {
                drawArrowHead(from: source, to: target, color: color, in: &context)
            }
        }
    }

    private func drawArrowHead(from source: CGPoint, to target: CGPoint, color: Color, in context: inout GraphicsContext) {
        let dx = target.x - source.x
        let dy = target.y - source.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let unitX = dx / length
        let unitY = dy / length
        let tip = CGPoint(x: target.x - unitX * 18, y: target.y - unitY * 18)
        let base = CGPoint(x: tip.x - unitX * 8, y: tip.y - unitY * 8)
        let perpendicular = CGPoint(x: -unitY * 4.5, y: unitX * 4.5)
        var arrow = Path()
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: base.x + perpendicular.x, y: base.y + perpendicular.y))
        arrow.addLine(to: CGPoint(x: base.x - perpendicular.x, y: base.y - perpendicular.y))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(color))
    }

    private func isHighlighted(_ node: MemoryGraphPresentation.Node) -> Bool {
        let search = graphStore.changeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !search.isEmpty else { return false }
        return "\(node.displayTitle) \(node.subtitle ?? "") \(node.badges.joined(separator: " ")) \(node.helpText)"
            .lowercased()
            .contains(search)
    }
}

private struct MemoryGraphLaneHeaderView: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(MemoryGraphLane.allCases, id: \.rawValue) { lane in
                Text(lane.label)
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.55), lineWidth: 1))
    }
}

private struct MemoryGraphSummaryBadge: View {
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
                AIConfigsMiniStat(value: "\(store.graph.focusedChangeGraph?.nodes.count ?? 0)", label: "nodes")
                AIConfigsMiniStat(value: "\(store.graph.focusedChangeGraph?.edges.count ?? 0)", label: "edges")
            }
            if let projectID = store.graph.changeGraph?.projectID {
                MemoryGraphInspectorFactRow(label: "project", value: projectID.memoryAbbreviatingHomeDirectory)
            }
            if let graph = store.graph.changeGraph,
               let focused = store.graph.focusedChangeGraph,
               focused.nodes.count != graph.nodes.count || focused.edges.count != graph.edges.count {
                MemoryGraphInspectorFactRow(label: "focus", value: "\(focused.nodes.count)/\(graph.nodes.count) nodes, \(focused.edges.count)/\(graph.edges.count) edges")
            }
            if let presentation = store.graph.changePresentation {
                MemoryGraphInspectorFactRow(label: "view", value: "\(presentation.mode.label) · \(presentation.density.label)")
                Text(presentation.summary)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.54, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    @ViewBuilder
    private var selection: some View {
        if let group = store.graph.selectedChangeGroup {
            groupInspector(group)
        } else if let event = store.graph.selectedChangeEvent {
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
        let changedFields = MemoryGraphPresentation.changedFields(for: event)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: MemoryGraphStyle.symbol(for: "change_event"))
                    .foregroundStyle(MemoryGraphStyle.eventColor(for: event.eventType))
                Text(MemoryGraphPresentation.friendlyEventName(for: event.eventType))
                    .font(.sora(14, weight: .semibold))
                Spacer(minLength: 0)
            }
            MemoryGraphInspectorFactRow(label: "type", value: event.eventType)
            MemoryGraphInspectorFactRow(label: "seq", value: "\(event.seq)")
            MemoryGraphInspectorFactRow(label: "event", value: event.eventID)
            MemoryGraphInspectorFactRow(label: "memory", value: event.memoryID ?? "-")
            MemoryGraphInspectorFactRow(label: "actor", value: event.actor["id"] ?? event.actor["kind"] ?? "system")
            MemoryGraphInspectorFactRow(label: "time", value: MemoryFormat.timestamp(event.timestamp))
            if let status = event.statusTransition {
                MemoryGraphInspectorFactRow(label: "status", value: status)
            }
            if !changedFields.isEmpty {
                badgeRow(title: "Changed", values: changedFields)
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

    private func groupInspector(_ group: MemoryGraphPresentation.GroupSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: MemoryGraphStyle.symbol(for: "group"))
                    .foregroundStyle(MemoryGraphStyle.color(for: "group"))
                Text(group.title)
                    .font(.sora(14, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            if !group.subtitle.isEmpty {
                Text(group.subtitle)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MemoryGraphInspectorFactRow(label: "events", value: "\(group.eventIDs.count)")
            if !group.memoryIDs.isEmpty {
                badgeRow(title: "Memories", values: group.memoryIDs)
            }
            if !group.sourceLabels.isEmpty {
                badgeRow(title: "Sources", values: group.sourceLabels)
            }
            if !group.changedFieldCounts.isEmpty {
                let fields = group.changedFieldCounts.sorted { lhs, rhs in
                    if lhs.value != rhs.value {
                        return lhs.value > rhs.value
                    }
                    return lhs.key < rhs.key
                }.map { "\($0.key) ×\($0.value)" }
                badgeRow(title: "Changed", values: fields)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Events")
                    .font(.sora(12, weight: .semibold))
                ForEach(group.eventIDs, id: \.self) { eventID in
                    if let event = store.graph.events.first(where: { $0.eventID == eventID }) {
                        Button {
                            store.graph.selectChangeEvent(event.eventID)
                            if let memoryID = event.memoryID {
                                Task { await store.graph.loadHistory(memoryID: memoryID) }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text("#\(event.seq)")
                                    .font(.sora(10, weight: .semibold).monospaced())
                                    .foregroundStyle(Color.stxMuted)
                                Text(MemoryGraphPresentation.friendlyEventName(for: event.eventType))
                                    .font(.sora(10, weight: .semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(7)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.54, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private func memoryInspector(_ memoryID: String) -> some View {
        let selectedNode = store.graph.selectedChangeNode
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: MemoryGraphStyle.symbol(for: "memory"))
                    .foregroundStyle(MemoryGraphStyle.color(for: "memory"))
                Text(selectedNode?.title ?? memoryID)
                    .font(.sora(14, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            MemoryGraphInspectorFactRow(label: "id", value: memoryID)
            if let selectedNode {
                if let type = selectedNode.type, !type.isEmpty {
                    MemoryGraphInspectorFactRow(label: "type", value: type)
                }
                if let status = selectedNode.status, !status.isEmpty {
                    MemoryGraphInspectorFactRow(label: "status", value: status)
                }
                if let body = selectedNode.body, !body.isEmpty {
                    Text(body)
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let sourceRefs = selectedNode.sourceRefs, !sourceRefs.isEmpty {
                    MemorySourceRefsView(sourceRefs: sourceRefs)
                }
            }
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

    private func badgeRow(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.sora(10, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            FlowBadgeRow(values: values)
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
