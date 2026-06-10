import CoreGraphics
import Foundation

struct TrackToolStack: Identifiable, Hashable, Sendable {
    typealias ID = String

    let id: String
    let title: String
    let column: Int
    let nodes: [TrackNode]

    var subtitle: String {
        if nodes.count == 1 { return "1 tool use in this column" }
        return "\(nodes.count) tool uses in this column"
    }

    var status: TrackStatus {
        nodes.map(\.status).max { lhs, rhs in
            lhs.priority < rhs.priority
        } ?? .unknown
    }

    var source: TrackEventSource {
        representative.source
    }

    var confidence: TrackConfidence {
        nodes.map(\.confidence).max() ?? .low
    }

    var startedAt: Date? {
        nodes.compactMap(\.startedAt).min()
    }

    var endedAt: Date? {
        guard nodes.allSatisfy({ $0.endedAt != nil }) else { return nil }
        return nodes.compactMap(\.endedAt).max()
    }

    var eventIDs: [TrackEvent.ID] {
        nodes.flatMap(\.eventIDs)
    }

    var memberNodeIDs: Set<TrackNode.ID> {
        Set(nodes.map(\.id))
    }

    var representative: TrackNode {
        nodes.first!
    }
}

struct TrackGraphItem: Identifiable, Hashable, Sendable {
    typealias ID = String

    let id: String
    let node: TrackNode?
    let stack: TrackToolStack?

    static func node(_ node: TrackNode) -> TrackGraphItem {
        TrackGraphItem(id: node.id, node: node, stack: nil)
    }

    static func stack(_ stack: TrackToolStack) -> TrackGraphItem {
        TrackGraphItem(id: stack.id, node: nil, stack: stack)
    }

    var displayKind: TrackNodeKind {
        stack == nil ? node?.kind ?? .result : .tool
    }

    var startedAt: Date? {
        stack?.startedAt ?? node?.startedAt
    }

    var sortID: String {
        id
    }
}

struct TrackGraphDisplayEdge: Identifiable, Hashable, Sendable {
    var id: String { "\(from)->\(to)" }
    var from: TrackGraphItem.ID
    var to: TrackGraphItem.ID
    var source: TrackEventSource
    var confidence: TrackConfidence
    var count: Int
    var visibility: TrackGraphEdgeVisibility
    var role: TrackGraphEdgeRole
}

enum TrackGraphEdgeVisibility: Hashable, Sendable {
    case overview
    case focusOnly
}

enum TrackGraphEdgeRole: Hashable, Sendable {
    case flow
    case relation
}

struct TrackGraphPresentation: Hashable, Sendable {
    let items: [TrackGraphItem]
    let edges: [TrackGraphDisplayEdge]
    let itemIDByNodeID: [TrackNode.ID: TrackGraphItem.ID]
    let columnByItemID: [TrackGraphItem.ID: Int]
    let stacksByID: [TrackToolStack.ID: TrackToolStack]

    init(run: TrackRun) {
        let compression = Self.compressToolStacks(nodes: run.nodes, edges: run.edges)
        items = compression.items
        itemIDByNodeID = compression.itemIDByNodeID
        columnByItemID = compression.columnByItemID
        stacksByID = Dictionary(uniqueKeysWithValues: compression.stacks.map { ($0.id, $0) })
        edges = Self.displayEdges(
            from: run.edges,
            nodes: run.nodes,
            items: items,
            stacks: compression.stacks,
            itemIDByNodeID: itemIDByNodeID,
            columnByItemID: columnByItemID
        )
    }

    func stack(containing nodeID: TrackNode.ID?) -> TrackToolStack? {
        guard let nodeID,
              let itemID = itemIDByNodeID[nodeID] else { return nil }
        return stacksByID[itemID]
    }

    private static func compressToolStacks(nodes: [TrackNode], edges: [TrackEdge]) -> (
        items: [TrackGraphItem],
        itemIDByNodeID: [TrackNode.ID: TrackGraphItem.ID],
        columnByItemID: [TrackGraphItem.ID: Int],
        stacks: [TrackToolStack]
    ) {
        let depthByNodeID = Self.nodeDepths(nodes: nodes, edges: edges)
        let toolNodesByColumn = Dictionary(grouping: nodes.filter { $0.kind == .tool }) { node in
            depthByNodeID[node.id] ?? 0
        }
        let stacksByColumn: [Int: TrackToolStack] = Dictionary(uniqueKeysWithValues: toolNodesByColumn.compactMap { column, tools in
            guard !tools.isEmpty else { return nil }
            let sortedTools = tools.sorted(by: Self.chronologicalOrder)
            let stack = TrackToolStack(
                id: "tool-stack::column-\(column)",
                title: Self.toolStackTitle(for: sortedTools),
                column: column,
                nodes: sortedTools
            )
            return (column, stack)
        })

        var items: [TrackGraphItem] = []
        var itemIDByNodeID: [TrackNode.ID: TrackGraphItem.ID] = [:]
        var columnByItemID: [TrackGraphItem.ID: Int] = [:]
        var stacks: [TrackToolStack] = []
        var insertedStackColumns: Set<Int> = []

        for node in nodes.sorted(by: chronologicalOrder) {
            guard node.kind == .tool,
                  let column = depthByNodeID[node.id],
                  let stack = stacksByColumn[column] else {
                if itemIDByNodeID[node.id] == nil {
                    items.append(.node(node))
                    itemIDByNodeID[node.id] = node.id
                }
                continue
            }

            itemIDByNodeID[node.id] = stack.id
            guard !insertedStackColumns.contains(column) else { continue }
            insertedStackColumns.insert(column)
            stacks.append(stack)
            items.append(.stack(stack))
            columnByItemID[stack.id] = column
            for member in stack.nodes {
                itemIDByNodeID[member.id] = stack.id
            }
        }

        for item in items where columnByItemID[item.id] == nil {
            if let node = item.node {
                columnByItemID[item.id] = depthByNodeID[node.id] ?? 0
            }
        }

        return (items, itemIDByNodeID, columnByItemID, stacks)
    }

    private static func nodeDepths(nodes: [TrackNode], edges: [TrackEdge]) -> [TrackNode.ID: Int] {
        let childrenByParent = Dictionary(grouping: edges, by: \.from)
        var depthByNode: [TrackNode.ID: Int] = [:]
        var queue: [(TrackNode.ID, Int)] = []
        if let root = nodes.first(where: { $0.kind == .session }) {
            queue.append((root.id, 0))
        }
        for node in nodes where !depthByNode.keys.contains(node.id) && queue.isEmpty {
            queue.append((node.id, 0))
        }

        var cursor = 0
        while cursor < queue.count {
            let (id, depth) = queue[cursor]
            cursor += 1
            guard depthByNode[id] == nil || depth < depthByNode[id]! else { continue }
            depthByNode[id] = depth
            for edge in childrenByParent[id] ?? [] {
                queue.append((edge.to, depth + 1))
            }
        }
        for node in nodes where depthByNode[node.id] == nil {
            depthByNode[node.id] = 0
        }
        return depthByNode
    }

    private static func displayEdges(
        from edges: [TrackEdge],
        nodes: [TrackNode],
        items: [TrackGraphItem],
        stacks: [TrackToolStack],
        itemIDByNodeID: [TrackNode.ID: TrackGraphItem.ID],
        columnByItemID: [TrackGraphItem.ID: Int]
    ) -> [TrackGraphDisplayEdge] {
        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var merged: [String: TrackGraphDisplayEdge] = [:]
        for edge in edges {
            guard let from = itemIDByNodeID[edge.from],
                  let to = itemIDByNodeID[edge.to],
                  from != to,
                  let fromItem = itemByID[from],
                  let toItem = itemByID[to] else { continue }
            let style = Self.edgeStyle(
                fromItem: fromItem,
                toItem: toItem,
                fromColumn: columnByItemID[from] ?? 0,
                toColumn: columnByItemID[to] ?? 0,
                rawFromKind: nodeByID[edge.from]?.kind,
                rawToKind: nodeByID[edge.to]?.kind
            )
            let displayEdge = TrackGraphDisplayEdge(
                from: from,
                to: to,
                source: edge.source,
                confidence: edge.confidence,
                count: 1,
                visibility: style.visibility,
                role: style.role
            )
            Self.merge(displayEdge, into: &merged)
        }
        Self.addSyntheticFlowEdges(
            items: items,
            stacks: stacks,
            into: &merged
        )
        return merged.values.sorted { lhs, rhs in
            let lhsFrom = columnByItemID[lhs.from] ?? 0
            let rhsFrom = columnByItemID[rhs.from] ?? 0
            if lhsFrom != rhsFrom { return lhsFrom < rhsFrom }
            let lhsTo = columnByItemID[lhs.to] ?? 0
            let rhsTo = columnByItemID[rhs.to] ?? 0
            if lhsTo != rhsTo { return lhsTo < rhsTo }
            return lhs.id < rhs.id
        }
    }

    private static func edgeStyle(
        fromItem: TrackGraphItem,
        toItem: TrackGraphItem,
        fromColumn: Int,
        toColumn: Int,
        rawFromKind: TrackNodeKind?,
        rawToKind: TrackNodeKind?
    ) -> (visibility: TrackGraphEdgeVisibility, role: TrackGraphEdgeRole) {
        let involvesStack = fromItem.stack != nil || toItem.stack != nil
        let forwardAdjacent = toColumn == fromColumn + 1

        guard involvesStack else {
            if forwardAdjacent || fromItem.displayKind == .session {
                return (.overview, .relation)
            }
            return (.focusOnly, .relation)
        }

        if fromItem.stack != nil, toItem.stack != nil, forwardAdjacent {
            return (.overview, .flow)
        }
        if toItem.stack != nil,
           forwardAdjacent,
           [.session, .turn].contains(fromItem.displayKind) {
            return (.overview, .flow)
        }
        if fromItem.stack != nil,
           forwardAdjacent,
           rawToKind == .approval || toItem.displayKind == .approval {
            return (.overview, .relation)
        }
        if rawFromKind == .approval || rawToKind == .approval {
            return (.overview, .relation)
        }
        return (.focusOnly, .relation)
    }

    private static func addSyntheticFlowEdges(
        items: [TrackGraphItem],
        stacks: [TrackToolStack],
        into merged: inout [String: TrackGraphDisplayEdge]
    ) {
        let sortedStacks = stacks.sorted { lhs, rhs in
            if lhs.column != rhs.column { return lhs.column < rhs.column }
            return lhs.id < rhs.id
        }

        if let root = items.first(where: { $0.displayKind == .session }),
           let firstStack = sortedStacks.first {
            Self.mergeSyntheticFlow(
                TrackGraphDisplayEdge(
                    from: root.id,
                    to: firstStack.id,
                    source: firstStack.source,
                    confidence: firstStack.confidence,
                    count: firstStack.nodes.count,
                    visibility: .overview,
                    role: .flow
                ),
                into: &merged
            )
        }

        for (lhs, rhs) in zip(sortedStacks, sortedStacks.dropFirst()) {
            guard rhs.column > lhs.column else { continue }
            Self.mergeSyntheticFlow(
                TrackGraphDisplayEdge(
                    from: lhs.id,
                    to: rhs.id,
                    source: rhs.source,
                    confidence: max(lhs.confidence, rhs.confidence),
                    count: rhs.nodes.count,
                    visibility: .overview,
                    role: .flow
                ),
                into: &merged
            )
        }
    }

    private static func mergeSyntheticFlow(
        _ edge: TrackGraphDisplayEdge,
        into merged: inout [String: TrackGraphDisplayEdge]
    ) {
        let key = edge.id
        guard var existing = merged[key] else {
            merged[key] = edge
            return
        }

        existing.visibility = .overview
        existing.role = .flow
        if existing.confidence < edge.confidence {
            existing.confidence = edge.confidence
            existing.source = edge.source
        }
        merged[key] = existing
    }

    private static func merge(
        _ edge: TrackGraphDisplayEdge,
        into merged: inout [String: TrackGraphDisplayEdge]
    ) {
        let key = edge.id
        guard var existing = merged[key] else {
            merged[key] = edge
            return
        }

        existing.count += edge.count
        if existing.confidence < edge.confidence {
            existing.confidence = edge.confidence
            existing.source = edge.source
        }
        if edge.visibility == .overview {
            existing.visibility = .overview
        }
        if edge.role == .flow {
            existing.role = .flow
        }
        merged[key] = existing
    }

    private static func chronologicalOrder(_ lhs: TrackNode, _ rhs: TrackNode) -> Bool {
        let lhsDate = lhs.startedAt ?? lhs.endedAt ?? .distantPast
        let rhsDate = rhs.startedAt ?? rhs.endedAt ?? .distantPast
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return lhs.id < rhs.id
    }

    private static func toolStackKey(for node: TrackNode) -> String {
        let raw = node.metadata["toolName"] ?? node.metadata["tool_name"] ?? node.title
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func toolStackTitle(for nodes: [TrackNode]) -> String {
        let titles = Set(nodes.map { toolStackKey(for: $0) })
        if titles.count == 1, let title = nodes.first?.title {
            return title
        }
        return "Tools"
    }
}

struct TrackGraphLayout: Sendable {
    let frames: [TrackGraphItem.ID: CGRect]
    let columns: [TrackGraphItem.ID: Int]
    let size: CGSize

    init(presentation: TrackGraphPresentation) {
        let nodeWidth: CGFloat = 190
        let nodeHeight: CGFloat = 112
        let columnGap: CGFloat = 76
        let rowGap: CGFloat = 30
        let origin = CGPoint(x: 30, y: 30)

        let grouped = Dictionary(grouping: presentation.items) { presentation.columnByItemID[$0.id] ?? 0 }
        var frames: [TrackGraphItem.ID: CGRect] = [:]
        for depth in grouped.keys.sorted() {
            let items = (grouped[depth] ?? []).sorted { lhs, rhs in
                let lhsDate = lhs.startedAt ?? .distantPast
                let rhsDate = rhs.startedAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.sortID < rhs.sortID
            }
            for (row, item) in items.enumerated() {
                frames[item.id] = CGRect(
                    x: origin.x + CGFloat(depth) * (nodeWidth + columnGap),
                    y: origin.y + CGFloat(row) * (nodeHeight + rowGap),
                    width: nodeWidth,
                    height: nodeHeight
                )
            }
        }

        let maxX = frames.values.map(\.maxX).max() ?? 600
        let maxY = frames.values.map(\.maxY).max() ?? 420
        self.frames = frames
        self.columns = presentation.columnByItemID
        self.size = CGSize(width: max(720, maxX + 40), height: max(460, maxY + 40))
    }
}
