import Foundation

enum MemoryKnowledgeFactVisibility: String, CaseIterable, Identifiable, Sendable, Hashable {
    case active
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active:
            "Active"
        case .all:
            "All"
        }
    }
}

struct MemoryKnowledgeGraphPresentation: Sendable, Hashable {
    struct Node: Identifiable, Sendable, Hashable {
        var id: String
        var rawNode: CodeMemoryGraphNode
        var displayTitle: String
        var subtitle: String?
        var badges: [String]
        var labels: [String]
        var attributes: [String: String]
        var degree: Int
        var episodeIDs: [String]
        var helpText: String
    }

    struct Edge: Identifiable, Sendable, Hashable {
        var id: String
        var rawEdge: CodeMemoryGraphEdge
        var source: String
        var target: String
        var relation: String
        var fact: String
        var validAt: String?
        var invalidAt: String?
        var expiredAt: String?
        var referenceTime: String?
        var episodeIDs: [String]
        var isActive: Bool
        var badges: [String]
        var helpText: String
    }

    var projectID: String
    var nodes: [Node]
    var edges: [Edge]
    var totalEntityCount: Int
    var totalFactCount: Int
    var activeFactCount: Int
    var factVisibility: MemoryKnowledgeFactVisibility
    var searchText: String
    var summary: String

    var isKnowledgeEmpty: Bool {
        totalEntityCount == 0 || totalFactCount == 0
    }

    static func build(
        graph: CodeMemoryGraph,
        factVisibility: MemoryKnowledgeFactVisibility,
        searchText: String
    ) -> MemoryKnowledgeGraphPresentation {
        let entities = graph.nodes
            .filter { $0.kind == "graphiti_entity" }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let entityIDs = Set(entities.map(\.id))
        let semanticEdges = graph.edges
            .filter { edge in
                entityIDs.contains(edge.source)
                    && entityIDs.contains(edge.target)
                    && (edge.metadata?["adapter"] == "graphiti" || edge.source.hasPrefix("graphiti:") || edge.target.hasPrefix("graphiti:"))
            }
            .map(Edge.init(rawEdge:))
            .sorted { lhs, rhs in
                if lhs.relation != rhs.relation {
                    return lhs.relation.localizedStandardCompare(rhs.relation) == .orderedAscending
                }
                return lhs.id < rhs.id
            }
        let activeFacts = semanticEdges.filter(\.isActive)
        let visibilityEdges = factVisibility == .active ? activeFacts : semanticEdges
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var visibleEdgeIDs = Set(visibilityEdges.map(\.id))
        var visibleNodeIDs = Set(entityIDs)

        if !normalizedSearch.isEmpty {
            let entitiesByID = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
            let nodeMatches = Set(entities.filter { Self.nodeMatches($0, search: normalizedSearch) }.map(\.id))
            let edgeMatches = Set(visibilityEdges.filter { Self.edgeMatches($0, entitiesByID: entitiesByID, search: normalizedSearch) }.map(\.id))
            visibleEdgeIDs = edgeMatches
            visibleNodeIDs = nodeMatches
            for edge in visibilityEdges where edgeMatches.contains(edge.id) || nodeMatches.contains(edge.source) || nodeMatches.contains(edge.target) {
                visibleEdgeIDs.insert(edge.id)
                visibleNodeIDs.insert(edge.source)
                visibleNodeIDs.insert(edge.target)
            }
            for edge in visibilityEdges where visibleNodeIDs.contains(edge.source) && visibleNodeIDs.contains(edge.target) {
                visibleEdgeIDs.insert(edge.id)
            }
        }

        let visibleEdges = visibilityEdges.filter { visibleEdgeIDs.contains($0.id) }
        let edgesByNodeID = Dictionary(grouping: visibleEdges.flatMap { edge in
            [(edge.source, edge), (edge.target, edge)]
        }, by: \.0)
        let visibleNodes = entities
            .filter { visibleNodeIDs.contains($0.id) }
            .map { rawNode in
                Node(
                    rawNode: rawNode,
                    connectedEdges: edgesByNodeID[rawNode.id]?.map(\.1) ?? []
                )
            }

        return MemoryKnowledgeGraphPresentation(
            projectID: graph.projectID,
            nodes: visibleNodes,
            edges: visibleEdges,
            totalEntityCount: entities.count,
            totalFactCount: semanticEdges.count,
            activeFactCount: activeFacts.count,
            factVisibility: factVisibility,
            searchText: searchText,
            summary: Self.summary(
                visibleNodes: visibleNodes.count,
                visibleEdges: visibleEdges.count,
                totalEntities: entities.count,
                totalFacts: semanticEdges.count,
                activeFacts: activeFacts.count,
                episodeCount: Set(visibleEdges.flatMap(\.episodeIDs)).count,
                searchText: normalizedSearch
            )
        )
    }

    func node(id: String) -> Node? {
        nodes.first { $0.id == id }
    }

    func edge(id: String) -> Edge? {
        edges.first { $0.id == id }
    }

    func connectedEdges(for nodeID: String) -> [Edge] {
        edges.filter { $0.source == nodeID || $0.target == nodeID }
    }

    func neighborNodeIDs(selectedNodeID: String?, selectedEdgeID: String?) -> Set<String> {
        var result = Set<String>()
        if let selectedNodeID {
            result.insert(selectedNodeID)
            for edge in edges where edge.source == selectedNodeID || edge.target == selectedNodeID {
                result.insert(edge.source)
                result.insert(edge.target)
            }
        }
        if let selectedEdgeID, let edge = edge(id: selectedEdgeID) {
            result.insert(edge.source)
            result.insert(edge.target)
        }
        return result
    }

    private static func summary(
        visibleNodes: Int,
        visibleEdges: Int,
        totalEntities: Int,
        totalFacts: Int,
        activeFacts: Int,
        episodeCount: Int,
        searchText: String
    ) -> String {
        guard totalEntities > 0, totalFacts > 0 else {
            return "Graphiti knowledge graph is not ready"
        }
        let prefix = searchText.isEmpty ? "" : "Filtered: "
        return "\(prefix)\(visibleNodes)/\(totalEntities) entities, \(visibleEdges)/\(totalFacts) facts, \(activeFacts) active, \(episodeCount) episodes"
    }

    private static func nodeMatches(_ node: CodeMemoryGraphNode, search: String) -> Bool {
        [
            node.id,
            node.title,
            node.body,
            node.kind,
            node.metadata?.values.joined(separator: " "),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
        .contains(search)
    }

    private static func edgeMatches(_ edge: Edge, entitiesByID: [String: CodeMemoryGraphNode], search: String) -> Bool {
        [
            edge.id,
            edge.relation,
            edge.fact,
            edge.validAt,
            edge.invalidAt,
            edge.expiredAt,
            edge.referenceTime,
            edge.episodeIDs.joined(separator: " "),
            entitiesByID[edge.source]?.title,
            entitiesByID[edge.target]?.title,
            edge.rawEdge.metadata?.values.joined(separator: " "),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
        .contains(search)
    }
}

private extension MemoryKnowledgeGraphPresentation.Node {
    init(rawNode: CodeMemoryGraphNode, connectedEdges: [MemoryKnowledgeGraphPresentation.Edge]) {
        let labels = rawNode.metadata?.memoryKnowledgeStringArray(forKey: "labels") ?? []
        let attributes = rawNode.metadata?.memoryKnowledgeStringDictionary(forKey: "attributes") ?? [:]
        let episodeIDs = Array(Set(connectedEdges.flatMap(\.episodeIDs))).sorted()
        let degree = connectedEdges.count
        let title = rawNode.title.isEmpty ? rawNode.id : rawNode.title
        var badges = labels.prefix(2).map { $0 }
        if degree > 0 {
            badges.append("\(degree) facts")
        }
        if !episodeIDs.isEmpty {
            badges.append("\(episodeIDs.count) episodes")
        }
        if !attributes.isEmpty {
            badges.append("\(attributes.count) attrs")
        }

        self.init(
            id: rawNode.id,
            rawNode: rawNode,
            displayTitle: title,
            subtitle: rawNode.body?.memoryKnowledgeTrimmed(maxLength: 118) ?? (degree > 0 ? "Connected to \(degree) fact\(degree == 1 ? "" : "s")" : nil),
            badges: badges,
            labels: labels,
            attributes: attributes,
            degree: degree,
            episodeIDs: episodeIDs,
            helpText: [
                rawNode.id,
                rawNode.body,
                labels.joined(separator: " "),
                attributes.values.joined(separator: " "),
            ].compactMap { $0 }.joined(separator: "\n")
        )
    }
}

private extension MemoryKnowledgeGraphPresentation.Edge {
    init(rawEdge: CodeMemoryGraphEdge) {
        let metadata = rawEdge.metadata ?? [:]
        let relation = rawEdge.kind.isEmpty ? (metadata["relation"] ?? "RELATES_TO") : rawEdge.kind
        let fact = rawEdge.factText?.nilIfEmpty ?? metadata["fact"]?.nilIfEmpty ?? relation
        let validAt = rawEdge.validAtLabel?.nilIfEmpty
        let invalidAt = rawEdge.invalidAtLabel?.nilIfEmpty
        let expiredAt = metadata["expired_at"]?.nilIfEmpty
        let referenceTime = metadata["reference_time"]?.nilIfEmpty
        let episodeIDs = metadata.memoryKnowledgeStringArray(forKey: "episodes")
        let isActive = invalidAt == nil && expiredAt == nil
        var badges = [isActive ? "active" : "inactive"]
        if let validAt {
            badges.append("valid \(MemoryKnowledgeFormat.compact(validAt))")
        }
        if let invalidAt {
            badges.append("invalid \(MemoryKnowledgeFormat.compact(invalidAt))")
        } else if let expiredAt {
            badges.append("expired \(MemoryKnowledgeFormat.compact(expiredAt))")
        }
        if !episodeIDs.isEmpty {
            badges.append("\(episodeIDs.count) episodes")
        }

        self.init(
            id: rawEdge.id,
            rawEdge: rawEdge,
            source: rawEdge.source,
            target: rawEdge.target,
            relation: relation,
            fact: fact,
            validAt: validAt,
            invalidAt: invalidAt,
            expiredAt: expiredAt,
            referenceTime: referenceTime,
            episodeIDs: episodeIDs,
            isActive: isActive,
            badges: badges,
            helpText: [
                rawEdge.id,
                relation,
                fact,
                episodeIDs.joined(separator: " "),
            ].joined(separator: "\n")
        )
    }
}

private enum MemoryKnowledgeFormat {
    static func compact(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 10 {
            return String(trimmed.prefix(10))
        }
        return trimmed
    }
}

private extension Dictionary where Key == String, Value == String {
    func memoryKnowledgeStringArray(forKey key: String) -> [String] {
        guard let raw = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return []
        }
        if let data = raw.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return decoded.map { "\($0)" }.filter { !$0.isEmpty }.sorted()
        }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    func memoryKnowledgeStringDictionary(forKey key: String) -> [String: String] {
        guard let raw = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: decoded.map { key, value in
            (key, "\(value)")
        })
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func memoryKnowledgeTrimmed(maxLength: Int) -> String {
        guard count > maxLength else { return self }
        return String(prefix(maxLength - 1)) + "..."
    }
}
