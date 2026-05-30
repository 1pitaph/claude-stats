import SwiftUI

struct MemoryGraphCanvasView: View {
    @Bindable var graphStore: MemoryGraphStore
    @State private var dragStart = CGSize.zero
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            graphContent(size: proxy.size)
        }
        .background(Color.primary.opacity(0.018))
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
                .onEnded { _ in
                    isDragging = false
                }
        )
    }

    @ViewBuilder
    private func graphContent(size: CGSize) -> some View {
        if let graph = graphStore.graph, !graph.nodes.isEmpty {
            let nodes = filteredNodes(graph.nodes)
            let nodeIDs = Set(nodes.map(\.id))
            let edges = filteredEdges(graph.edges, nodeIDs: nodeIDs)
            let render = MemoryGraphRenderLimiter.limit(
                nodes: nodes,
                edges: edges,
                maxNodes: MemoryGraphRenderLimiter.knowledgeNodeLimit,
                maxEdges: MemoryGraphRenderLimiter.knowledgeEdgeLimit,
                selectedNodeID: graphStore.selectedNodeID,
                selectedEdgeID: graphStore.selectedEdgeID
            )
            let positions = MemoryGraphLayout.positions(
                for: render.nodes,
                in: size,
                pan: graphStore.pan,
                zoom: CGFloat(graphStore.zoom)
            )

            ZStack {
                Canvas { context, _ in
                    drawEdges(render.edges, positions: positions, in: &context)
                }

                if render.showsEdgeHitTargets {
                    ForEach(render.edges) { edge in
                        if let midpoint = MemoryGraphLayout.midpoint(for: edge, positions: positions) {
                            Button {
                                graphStore.selectEdge(edge.id)
                            } label: {
                                Circle()
                                    .fill(graphStore.selectedEdgeID == edge.id ? Color.stxAccent : Color.primary.opacity(0.18))
                                    .frame(width: graphStore.selectedEdgeID == edge.id ? 10 : 7, height: graphStore.selectedEdgeID == edge.id ? 10 : 7)
                            }
                            .buttonStyle(.plain)
                            .position(midpoint)
                            .help(edge.kind)
                        }
                    }
                }

                ForEach(render.nodes) { node in
                    if let position = positions[node.id] {
                        let highlighted = isHighlighted(node)
                        MemoryGraphNodeView(
                            node: node,
                            isSelected: graphStore.selectedNodeID == node.id,
                            isHighlighted: highlighted,
                            isCompact: render.usesCompactNodes
                                && graphStore.selectedNodeID != node.id
                                && !highlighted
                                && node.kind != "project"
                        ) {
                            graphStore.selectNode(node.id)
                        }
                        .position(position)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay(alignment: .topLeading) {
                if render.usesCompactNodes || graph.truncated == true {
                    MemoryGraphRenderLimitBadge(
                        render: render,
                        backendTotalNodes: graph.totalNodes,
                        backendTotalEdges: graph.totalEdges,
                        backendTruncated: graph.truncated == true
                    )
                    .padding(12)
                }
            }
        } else {
            MemoryEmptyState(
                title: graphStore.isLoading ? "Loading graph" : "No graph loaded",
                message: graphStore.lastError ?? "Select a project.",
                symbol: "point.3.connected.trianglepath.dotted"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func drawEdges(_ edges: [CodeMemoryGraphEdge], positions: [String: CGPoint], in context: inout GraphicsContext) {
        for edge in edges {
            guard let source = positions[edge.source], let target = positions[edge.target] else { continue }
            var path = Path()
            path.move(to: source)
            path.addLine(to: target)
            let selected = graphStore.selectedEdgeID == edge.id
            let color = selected ? Color.stxAccent : Color.stxStroke.opacity(0.72)
            context.stroke(path, with: .color(color), lineWidth: selected ? 2.0 : 1.0)
        }
    }

    private func filteredNodes(_ nodes: [CodeMemoryGraphNode]) -> [CodeMemoryGraphNode] {
        MemoryKnowledgeGraphFilter.nodes(
            nodes,
            selectedKinds: graphStore.selectedKinds,
            showCanonical: graphStore.showCanonical,
            showEpisodes: graphStore.showEpisodes,
            showEvents: graphStore.showEvents,
            showGraphiti: graphStore.showGraphiti,
            asOf: graphStore.asOf,
            searchText: graphStore.searchText
        )
    }

    private func filteredEdges(_ edges: [CodeMemoryGraphEdge], nodeIDs: Set<String>) -> [CodeMemoryGraphEdge] {
        MemoryKnowledgeGraphFilter.edges(edges, nodeIDs: nodeIDs, asOf: graphStore.asOf)
    }

    private func isHighlighted(_ node: CodeMemoryGraphNode) -> Bool {
        let search = graphStore.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !search.isEmpty else { return false }
        return "\(node.title) \(node.body ?? "") \(node.kind) \(node.type ?? "")"
            .lowercased()
            .contains(search)
    }

}

struct MemoryGraphNodeView: View {
    let node: CodeMemoryGraphNode
    let isSelected: Bool
    let isHighlighted: Bool
    var isCompact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isCompact {
                Image(systemName: MemoryGraphStyle.symbol(for: node.kind))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MemoryGraphStyle.color(for: node.kind))
                    .frame(width: 24, height: 24)
                    .background(fill, in: Circle())
                    .overlay(Circle().strokeBorder(stroke, lineWidth: isSelected ? 2 : 1))
                    .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0.04), radius: isSelected ? 8 : 3, y: 2)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: MemoryGraphStyle.symbol(for: node.kind))
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 14)
                    Text(node.title)
                        .font(.sora(10, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: width, alignment: .leading)
                .background(fill, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(stroke, lineWidth: isSelected ? 2 : 1))
                .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0.04), radius: isSelected ? 8 : 3, y: 2)
            }
        }
        .buttonStyle(.plain)
        .help("\(node.title)\n\(node.id)")
    }

    private var width: CGFloat {
        switch node.kind {
        case "project":
            176
        case "memory":
            190
        case "change_event":
            178
        default:
            156
        }
    }

    private var fill: Color {
        if isSelected {
            return MemoryGraphStyle.color(for: node.kind).opacity(0.24)
        }
        if isHighlighted {
            return Color.stxAccent.opacity(0.18)
        }
        return Color.primary.opacity(0.07)
    }

    private var stroke: Color {
        if isSelected {
            return Color.stxAccent
        }
        if isHighlighted {
            return Color.stxAccent.opacity(0.85)
        }
        return MemoryGraphStyle.color(for: node.kind).opacity(0.42)
    }
}

struct MemoryGraphRenderModel: Sendable, Hashable {
    var nodes: [CodeMemoryGraphNode]
    var edges: [CodeMemoryGraphEdge]
    var totalNodes: Int
    var totalEdges: Int
    var maxNodes: Int
    var maxEdges: Int

    var hiddenNodes: Int { max(0, totalNodes - nodes.count) }
    var hiddenEdges: Int { max(0, totalEdges - edges.count) }
    var isLimited: Bool { hiddenNodes > 0 || hiddenEdges > 0 }
    var usesCompactNodes: Bool { isLimited || nodes.count > 90 }
    var showsEdgeHitTargets: Bool { !isLimited && edges.count <= 180 }
}

enum MemoryGraphRenderLimiter {
    static let knowledgeNodeLimit = 180
    static let knowledgeEdgeLimit = 360
    static let changeNodeLimit = 220
    static let changeEdgeLimit = 420

    static func limit(
        nodes: [CodeMemoryGraphNode],
        edges: [CodeMemoryGraphEdge],
        maxNodes: Int,
        maxEdges: Int,
        selectedNodeID: String?,
        selectedEdgeID: String?
    ) -> MemoryGraphRenderModel {
        guard nodes.count > maxNodes || edges.count > maxEdges else {
            return MemoryGraphRenderModel(
                nodes: nodes,
                edges: edges,
                totalNodes: nodes.count,
                totalEdges: edges.count,
                maxNodes: maxNodes,
                maxEdges: maxEdges
            )
        }

        var requiredNodeIDs = Set<String>()
        if let selectedNodeID {
            requiredNodeIDs.insert(selectedNodeID)
        }
        if let selectedEdgeID,
           let edge = edges.first(where: { $0.id == selectedEdgeID }) {
            requiredNodeIDs.insert(edge.source)
            requiredNodeIDs.insert(edge.target)
        }

        var selectedNodes: [CodeMemoryGraphNode] = []
        var selectedNodeIDs = Set<String>()

        func include(_ node: CodeMemoryGraphNode) {
            guard selectedNodes.count < maxNodes else { return }
            guard selectedNodeIDs.insert(node.id).inserted else { return }
            selectedNodes.append(node)
        }

        for node in nodes where requiredNodeIDs.contains(node.id) {
            include(node)
        }

        let remaining = nodes
            .filter { !selectedNodeIDs.contains($0.id) }
            .sorted(by: nodePrecedes)
        for node in remaining {
            include(node)
        }

        let visibleNodeIDs = Set(selectedNodes.map(\.id))
        let visibleEdges = edges
            .filter { visibleNodeIDs.contains($0.source) && visibleNodeIDs.contains($0.target) }
            .sorted { lhs, rhs in
                edgePriority(lhs, selectedEdgeID: selectedEdgeID) < edgePriority(rhs, selectedEdgeID: selectedEdgeID)
            }
        return MemoryGraphRenderModel(
            nodes: selectedNodes,
            edges: Array(visibleEdges.prefix(maxEdges)),
            totalNodes: nodes.count,
            totalEdges: edges.count,
            maxNodes: maxNodes,
            maxEdges: maxEdges
        )
    }

    private static func nodePrecedes(_ lhs: CodeMemoryGraphNode, _ rhs: CodeMemoryGraphNode) -> Bool {
        let leftPriority = nodePriority(lhs)
        let rightPriority = nodePriority(rhs)
        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }
        let leftSeq = lhs.seq ?? Int.min
        let rightSeq = rhs.seq ?? Int.min
        if leftSeq != rightSeq {
            return leftSeq > rightSeq
        }
        return lhs.id < rhs.id
    }

    private static func nodePriority(_ node: CodeMemoryGraphNode) -> Int {
        switch node.kind {
        case "project":
            return 0
        case "module", "scope":
            return 1
        case "memory":
            return node.status == "active" || node.status == nil ? 2 : 4
        case "change_event":
            return 3
        case "source", "episode":
            return 5
        case "event":
            return 6
        default:
            return MemoryGraphStyle.isGraphitiKind(node.kind) ? 7 : 8
        }
    }

    private static func edgePriority(_ edge: CodeMemoryGraphEdge, selectedEdgeID: String?) -> (Int, String) {
        if edge.id == selectedEdgeID {
            return (-1, edge.id)
        }
        let priority: Int
        switch edge.kind {
        case "HAS_SCOPE":
            priority = 0
        case "SCOPED_TO":
            priority = 1
        case "AFFECTS":
            priority = 2
        case "NEXT_EVENT":
            priority = 3
        case "FROM_SOURCE", "HAS_PROVENANCE", "HAS_EPISODE":
            priority = 4
        default:
            priority = 5
        }
        return (priority, edge.id)
    }
}

struct MemoryGraphRenderLimitBadge: View {
    let render: MemoryGraphRenderModel
    let backendTotalNodes: Int?
    let backendTotalEdges: Int?
    let backendTruncated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.compress.vertical")
                    .font(.system(size: 11, weight: .semibold))
                Text("Large graph")
                    .font(.sora(11, weight: .semibold))
                Spacer(minLength: 0)
            }
            Text(summary)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(width: 250, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.72), lineWidth: 1))
    }

    private var summary: String {
        var parts = [
            "Rendering \(render.nodes.count)/\(render.totalNodes) nodes and \(render.edges.count)/\(render.totalEdges) edges."
        ]
        if backendTruncated, let backendTotalNodes, let backendTotalEdges {
            parts.append("Backend capped source graph from \(backendTotalNodes) nodes and \(backendTotalEdges) edges.")
        }
        parts.append("Use search or kind filters to expand a focused area.")
        return parts.joined(separator: " ")
    }
}

enum MemoryGraphStyle {
    static func color(for kind: String) -> Color {
        switch kind {
        case "project":
            Color.stxAccent
        case "module", "scope":
            Color(red: 0.22, green: 0.58, blue: 0.9)
        case "memory":
            Color(red: 0.42, green: 0.72, blue: 0.35)
        case "event":
            Color(red: 0.9, green: 0.56, blue: 0.22)
        case "change_event":
            Color(red: 0.95, green: 0.38, blue: 0.28)
        case "source", "episode":
            Color(red: 0.76, green: 0.48, blue: 0.86)
        default:
            isGraphitiKind(kind) ? Color(red: 0.94, green: 0.37, blue: 0.46) : Color.stxMuted
        }
    }

    static func symbol(for kind: String) -> String {
        switch kind {
        case "project":
            "folder"
        case "module", "scope":
            "shippingbox"
        case "memory":
            "text.badge.checkmark"
        case "event":
            "bolt.horizontal"
        case "change_event":
            "arrow.triangle.2.circlepath"
        case "source":
            "doc.text"
        case "episode":
            "doc.text.magnifyingglass"
        default:
            isGraphitiKind(kind) ? "point.3.connected.trianglepath.dotted" : "circle.hexagongrid"
        }
    }

    static func isGraphitiKind(_ kind: String) -> Bool {
        let lower = kind.lowercased()
        return lower.contains("graphiti") || lower == "entity" || lower == "relationship"
    }
}

enum MemoryGraphLayout {
    static func positions(for nodes: [CodeMemoryGraphNode], in size: CGSize, pan: CGSize, zoom: CGFloat) -> [String: CGPoint] {
        guard !nodes.isEmpty else { return [:] }
        let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
        var positions: [String: CGPoint] = [:]
        let grouped = Dictionary(grouping: nodes.sorted(by: { $0.id < $1.id }), by: \.kind)
        let orderedKinds = grouped.keys.sorted(by: kindOrder)
        let maxRadius = max(80, min(size.width, size.height) * 0.38)

        for (kindIndex, kind) in orderedKinds.enumerated() {
            let group = grouped[kind] ?? []
            if kind == "project", group.count == 1 {
                positions[group[0].id] = center
                continue
            }
            let ring = radius(for: kind, kindIndex: kindIndex, maxRadius: maxRadius) * zoom
            let angleOffset = Double(kindIndex) * .pi / 9
            for (index, node) in group.enumerated() {
                let angle = angleOffset + (Double(index) / Double(max(group.count, 1))) * 2 * .pi
                positions[node.id] = CGPoint(
                    x: center.x + cos(angle) * ring,
                    y: center.y + sin(angle) * ring
                )
            }
        }
        return positions
    }

    static func midpoint(for edge: CodeMemoryGraphEdge, positions: [String: CGPoint]) -> CGPoint? {
        guard let source = positions[edge.source], let target = positions[edge.target] else { return nil }
        return CGPoint(x: (source.x + target.x) / 2, y: (source.y + target.y) / 2)
    }

    private static func radius(for kind: String, kindIndex: Int, maxRadius: CGFloat) -> CGFloat {
        switch kind {
        case "project":
            0
        case "module", "scope":
            maxRadius * 0.35
        case "memory":
            maxRadius * 0.58
        case "event", "change_event":
            maxRadius * 0.78
        case "source", "episode":
            maxRadius * 0.92
        default:
            maxRadius * (0.48 + min(CGFloat(kindIndex) * 0.08, 0.44))
        }
    }

    private static func kindOrder(_ lhs: String, _ rhs: String) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ kind: String) -> Int {
        switch kind {
        case "project": 0
        case "module", "scope": 1
        case "memory": 2
        case "event", "change_event": 3
        case "source", "episode": 4
        default: MemoryGraphStyle.isGraphitiKind(kind) ? 5 : 6
        }
    }
}

enum MemoryKnowledgeGraphFilter {
    static func nodes(
        _ nodes: [CodeMemoryGraphNode],
        selectedKinds: Set<String>,
        showCanonical: Bool,
        showEpisodes: Bool,
        showEvents: Bool,
        showGraphiti: Bool,
        asOf: Double?,
        searchText: String
    ) -> [CodeMemoryGraphNode] {
        nodes.filter { node in
            if !selectedKinds.contains(node.kind) {
                return false
            }
            if !showCanonical, node.kind == "memory" {
                return false
            }
            if !showEvents, node.kind == "event" {
                return false
            }
            if !showEpisodes, node.kind == "source" || node.kind == "episode" {
                return false
            }
            if !showGraphiti, MemoryGraphStyle.isGraphitiKind(node.kind) {
                return false
            }
            if !isValid(node.metadata, asOf: asOf) {
                return false
            }
            let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !search.isEmpty else { return true }
            return "\(node.title) \(node.body ?? "") \(node.kind) \(node.type ?? "")"
                .lowercased()
                .contains(search)
        }
    }

    static func edges(_ edges: [CodeMemoryGraphEdge], nodeIDs: Set<String>, asOf: Double?) -> [CodeMemoryGraphEdge] {
        edges.filter { edge in
            nodeIDs.contains(edge.source)
                && nodeIDs.contains(edge.target)
                && isValid(edge.metadata, validAt: edge.validAt, invalidAt: edge.invalidAt, asOf: asOf)
        }
    }

    private static func isValid(_ metadata: [String: String]?, validAt: String? = nil, invalidAt: String? = nil, asOf: Double?) -> Bool {
        guard let asOf else { return true }
        let start = GraphTemporalValue.parse(validAt ?? metadata?["valid_at"])
        let end = GraphTemporalValue.parse(invalidAt ?? metadata?["invalid_at"])
        if let start, start > asOf {
            return false
        }
        if let end, end <= asOf {
            return false
        }
        return true
    }
}

enum MemoryGraphTemporalRange {
    static func range(for graph: CodeMemoryGraph?) -> ClosedRange<Double> {
        let items = graph.map { temporalValues(in: $0) } ?? []
        if let minValue = items.min(), let maxValue = items.max(), minValue < maxValue {
            return minValue...maxValue
        }
        let now = Date().timeIntervalSince1970
        return (now - 86_400 * 30)...(now + 86_400 * 30)
    }

    private static func temporalValues(in graph: CodeMemoryGraph) -> [Double] {
        var result: [Double] = []
        for node in graph.nodes {
            if let value = GraphTemporalValue.parse(node.metadata?["valid_at"]) {
                result.append(value)
            }
            if let value = GraphTemporalValue.parse(node.metadata?["invalid_at"]) {
                result.append(value)
            }
        }
        for edge in graph.edges {
            if let value = GraphTemporalValue.parse(edge.validAt ?? edge.metadata?["valid_at"]) {
                result.append(value)
            }
            if let value = GraphTemporalValue.parse(edge.invalidAt ?? edge.metadata?["invalid_at"]) {
                result.append(value)
            }
        }
        return result
    }
}

enum GraphTemporalValue {
    static func parse(_ value: String?) -> Double? {
        guard let value, !value.isEmpty else { return nil }
        if let number = Double(value) {
            return number
        }
        return ISO8601DateFormatter().date(from: value)?.timeIntervalSince1970
    }
}
