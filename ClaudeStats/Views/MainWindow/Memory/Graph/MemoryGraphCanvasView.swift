import SwiftUI

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
                Image(systemName: AppIcon.Layout.compressVertical)
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
        parts.append("Use search or selection to narrow the focused area.")
        return parts.joined(separator: " ")
    }
}

enum MemoryGraphLayout {
    static func midpoint(for edge: CodeMemoryGraphEdge, positions: [String: CGPoint]) -> CGPoint? {
        guard let source = positions[edge.source], let target = positions[edge.target] else { return nil }
        return CGPoint(x: (source.x + target.x) / 2, y: (source.y + target.y) / 2)
    }

    static func midpoint(for edge: MemoryGraphPresentation.Edge, positions: [String: CGPoint]) -> CGPoint? {
        guard let source = positions[edge.source], let target = positions[edge.target] else { return nil }
        return CGPoint(x: (source.x + target.x) / 2, y: (source.y + target.y) / 2)
    }
}

enum MemoryChangeGraphLayout {
    static func positions(
        for nodes: [MemoryGraphPresentation.Node],
        in size: CGSize,
        pan: CGSize,
        zoom: CGFloat
    ) -> [String: CGPoint] {
        guard !nodes.isEmpty else { return [:] }

        let canvasWidth = max(size.width, 360)
        let canvasHeight = max(size.height, 300)
        let center = CGPoint(x: canvasWidth / 2 + pan.width, y: canvasHeight / 2 + pan.height + 14)
        let laneX: [MemoryGraphLane: CGFloat] = [
            .source: max(125, center.x - max(205, canvasWidth * 0.29) * zoom),
            .event: center.x,
            .memory: min(canvasWidth - 125, center.x + max(205, canvasWidth * 0.29) * zoom),
        ]
        let grouped = Dictionary(grouping: nodes, by: \.lane)
        var positions: [String: CGPoint] = [:]

        for lane in MemoryGraphLane.allCases {
            let laneNodes = (grouped[lane] ?? []).sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex {
                    return lhs.sortIndex < rhs.sortIndex
                }
                return lhs.id < rhs.id
            }
            guard !laneNodes.isEmpty, let x = laneX[lane] else { continue }
            let rowGap = min(112 * zoom, max(86, canvasHeight / CGFloat(max(laneNodes.count, 4))))
            let startY = center.y - CGFloat(laneNodes.count - 1) * rowGap / 2
            for (index, node) in laneNodes.enumerated() {
                positions[node.id] = CGPoint(x: x, y: startY + CGFloat(index) * rowGap)
            }
        }

        return positions.mapValues { point in
            CGPoint(
                x: min(max(point.x, 54), canvasWidth - 54),
                y: min(max(point.y, 56), canvasHeight - 42)
            )
        }
    }

    static func positions(
        for nodes: [CodeMemoryGraphNode],
        edges: [CodeMemoryGraphEdge],
        in size: CGSize,
        pan: CGSize,
        zoom: CGFloat
    ) -> [String: CGPoint] {
        guard !nodes.isEmpty else { return [:] }

        let canvasWidth = max(size.width, 320)
        let canvasHeight = max(size.height, 260)
        let center = CGPoint(x: canvasWidth / 2 + pan.width, y: canvasHeight / 2 + pan.height)
        let rowGap = min(82 * zoom, max(52, canvasHeight / CGFloat(max(nodes.count, 4))))
        var positions: [String: CGPoint] = [:]

        let eventNodes = nodes
            .filter { $0.kind == "change_event" }
            .sorted { lhs, rhs in (lhs.seq ?? 0, lhs.id) < (rhs.seq ?? 0, rhs.id) }
        if !eventNodes.isEmpty {
            let startY = center.y - CGFloat(eventNodes.count - 1) * rowGap / 2
            for (index, node) in eventNodes.enumerated() {
                positions[node.id] = CGPoint(x: center.x, y: startY + CGFloat(index) * rowGap)
            }
        }

        place(
            nodes.filter { $0.kind == "memory" }.sorted { $0.id < $1.id },
            x: min(canvasWidth - 110, center.x + max(150, canvasWidth * 0.22) * zoom),
            fallbackCenterY: center.y,
            edges: edges,
            positions: &positions
        )
        place(
            nodes.filter { $0.kind == "source" || $0.kind == "episode" }.sorted { $0.id < $1.id },
            x: max(110, center.x - max(170, canvasWidth * 0.26) * zoom),
            fallbackCenterY: center.y,
            edges: edges,
            positions: &positions
        )
        place(
            nodes.filter { positions[$0.id] == nil }.sorted { lhs, rhs in (lhs.kind, lhs.id) < (rhs.kind, rhs.id) },
            x: center.x,
            fallbackCenterY: center.y + CGFloat(max(eventNodes.count, 1)) * rowGap / 2 + 72,
            edges: edges,
            positions: &positions
        )

        return positions.mapValues { point in
            CGPoint(
                x: min(max(point.x, 42), canvasWidth - 42),
                y: min(max(point.y, 34), canvasHeight - 34)
            )
        }
    }

    private static func place(
        _ nodes: [CodeMemoryGraphNode],
        x: CGFloat,
        fallbackCenterY: CGFloat,
        edges: [CodeMemoryGraphEdge],
        positions: inout [String: CGPoint]
    ) {
        guard !nodes.isEmpty else { return }

        var proposed = nodes.map { node in
            let connectedYValues = edges.compactMap { edge -> CGFloat? in
                if edge.source == node.id {
                    return positions[edge.target]?.y
                }
                if edge.target == node.id {
                    return positions[edge.source]?.y
                }
                return nil
            }
            let y = connectedYValues.isEmpty
                ? fallbackCenterY
                : connectedYValues.reduce(0, +) / CGFloat(connectedYValues.count)
            return (node: node, y: y)
        }
        proposed.sort { lhs, rhs in (lhs.y, lhs.node.id) < (rhs.y, rhs.node.id) }

        let minGap: CGFloat = 42
        var previousY: CGFloat?
        for item in proposed {
            let adjustedY = previousY.map { max(item.y, $0 + minGap) } ?? item.y
            positions[item.node.id] = CGPoint(x: x, y: adjustedY)
            previousY = adjustedY
        }
    }
}
