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
            let positions = MemoryGraphLayout.positions(
                for: nodes,
                in: size,
                pan: graphStore.pan,
                zoom: CGFloat(graphStore.zoom)
            )

            ZStack {
                Canvas { context, _ in
                    drawEdges(edges, positions: positions, in: &context)
                }

                ForEach(edges) { edge in
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

                ForEach(nodes) { node in
                    if let position = positions[node.id] {
                        MemoryGraphNodeView(
                            node: node,
                            isSelected: graphStore.selectedNodeID == node.id,
                            isHighlighted: isHighlighted(node)
                        ) {
                            graphStore.selectNode(node.id)
                        }
                        .position(position)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .buttonStyle(.plain)
        .help(node.id)
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
