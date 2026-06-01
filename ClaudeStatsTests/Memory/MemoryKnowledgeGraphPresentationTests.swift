import Foundation
import Testing
@testable import ClaudeStats

@Suite("Memory knowledge graph presentation")
struct MemoryKnowledgeGraphPresentationTests {
    @Test("Graphiti entity nodes and fact edges become primary graph")
    func graphitiEntitiesAndFactsArePrimary() throws {
        let presentation = MemoryKnowledgeGraphPresentation.build(
            graph: Self.graph(),
            factVisibility: .active,
            searchText: ""
        )

        #expect(presentation.nodes.map(\.id).sorted() == ["graphiti:entity:a", "graphiti:entity:b"])
        #expect(presentation.edges.count == 1)
        let edge = try #require(presentation.edges.first)
        #expect(edge.relation == "PREFERS")
        #expect(edge.fact == "User prefers SwiftUI for graph interfaces.")
        #expect(edge.validAt == "2026-06-01T00:00:00Z")
        #expect(edge.episodeIDs == ["episode:one", "episode:two"])
        #expect(edge.badges.contains("2 episodes"))
    }

    @Test("Non Graphiti memory source and episode nodes stay out of default canvas")
    func nonGraphitiNodesStayOutOfDefaultCanvas() {
        let presentation = MemoryKnowledgeGraphPresentation.build(
            graph: Self.graph(),
            factVisibility: .active,
            searchText: ""
        )

        #expect(!presentation.nodes.contains { $0.rawNode.kind == "memory" })
        #expect(!presentation.nodes.contains { $0.rawNode.kind == "source" })
        #expect(!presentation.nodes.contains { $0.rawNode.kind == "episode" })
    }

    @Test("Active visibility filters invalid facts and all visibility includes them")
    func activeVisibilityFiltersInvalidFacts() {
        let active = MemoryKnowledgeGraphPresentation.build(
            graph: Self.graph(includeInvalid: true),
            factVisibility: .active,
            searchText: ""
        )
        let all = MemoryKnowledgeGraphPresentation.build(
            graph: Self.graph(includeInvalid: true),
            factVisibility: .all,
            searchText: ""
        )

        #expect(active.edges.map(\.relation) == ["PREFERS"])
        #expect(all.edges.map(\.relation).sorted() == ["DISLIKES", "PREFERS"])
    }

    @Test("Fact search keeps both endpoint entities")
    func factSearchKeepsEndpointEntities() {
        let presentation = MemoryKnowledgeGraphPresentation.build(
            graph: Self.graph(),
            factVisibility: .active,
            searchText: "SwiftUI"
        )

        #expect(presentation.edges.count == 1)
        #expect(Set(presentation.nodes.map(\.id)) == ["graphiti:entity:a", "graphiti:entity:b"])
    }

    @Test("No Graphiti entity or fact reports knowledge empty")
    func noGraphitiFactsReportsKnowledgeEmpty() {
        let graph = CodeMemoryGraph(
            projectID: "claude-stats",
            nodes: [
                CodeMemoryGraphNode(id: "memory:one", kind: "memory", title: "Memory", type: "fact", status: "active", seq: nil, body: "Body", sourceRefs: nil, metadata: nil),
                CodeMemoryGraphNode(id: "source:one", kind: "source", title: "Source", type: nil, status: nil, seq: nil, body: nil, sourceRefs: nil, metadata: nil),
            ],
            edges: []
        )

        let presentation = MemoryKnowledgeGraphPresentation.build(
            graph: graph,
            factVisibility: .active,
            searchText: ""
        )

        #expect(presentation.isKnowledgeEmpty)
        #expect(presentation.nodes.isEmpty)
        #expect(presentation.edges.isEmpty)
    }

    @Test("Presentation does not rewrite raw graph edge identifiers")
    func presentationPreservesRawEdgeIdentifiers() throws {
        let graph = Self.graph()
        let rawEdge = try #require(graph.edges.first { $0.kind == "PREFERS" })

        let presentation = MemoryKnowledgeGraphPresentation.build(
            graph: graph,
            factVisibility: .active,
            searchText: ""
        )

        let displayEdge = try #require(presentation.edges.first)
        #expect(displayEdge.id == rawEdge.id)
        #expect(displayEdge.rawEdge.id == rawEdge.id)
    }

    private static func graph(includeInvalid: Bool = false) -> CodeMemoryGraph {
        var edges = [
            CodeMemoryGraphEdge(
                source: "graphiti:entity:a",
                target: "graphiti:entity:b",
                kind: "PREFERS",
                primary: nil,
                fact: "User prefers SwiftUI for graph interfaces.",
                validAt: "2026-06-01T00:00:00Z",
                invalidAt: nil,
                metadata: [
                    "adapter": "graphiti",
                    "episodes": "[\"episode:two\", \"episode:one\"]",
                    "reference_time": "2026-06-01T00:00:00Z",
                ]
            ),
        ]
        if includeInvalid {
            edges.append(
                CodeMemoryGraphEdge(
                    source: "graphiti:entity:a",
                    target: "graphiti:entity:b",
                    kind: "DISLIKES",
                    primary: nil,
                    fact: "User disliked the old event graph.",
                    validAt: "2026-05-31T00:00:00Z",
                    invalidAt: "2026-06-01T00:00:00Z",
                    metadata: ["adapter": "graphiti"]
                )
            )
        }

        return CodeMemoryGraph(
            projectID: "claude-stats",
            nodes: [
                CodeMemoryGraphNode(
                    id: "graphiti:entity:a",
                    kind: "graphiti_entity",
                    title: "User",
                    type: nil,
                    status: nil,
                    seq: nil,
                    body: "Person giving feedback.",
                    sourceRefs: nil,
                    metadata: [
                        "adapter": "graphiti",
                        "labels": "[\"Person\"]",
                        "attributes": "{\"role\":\"owner\"}",
                    ]
                ),
                CodeMemoryGraphNode(
                    id: "graphiti:entity:b",
                    kind: "graphiti_entity",
                    title: "SwiftUI graph",
                    type: nil,
                    status: nil,
                    seq: nil,
                    body: "Knowledge graph interface.",
                    sourceRefs: nil,
                    metadata: ["adapter": "graphiti"]
                ),
                CodeMemoryGraphNode(id: "memory:one", kind: "memory", title: "Memory", type: "fact", status: "active", seq: nil, body: "Body", sourceRefs: nil, metadata: nil),
                CodeMemoryGraphNode(id: "source:one", kind: "source", title: "Source", type: nil, status: nil, seq: nil, body: nil, sourceRefs: nil, metadata: nil),
                CodeMemoryGraphNode(id: "episode:one", kind: "episode", title: "Episode", type: nil, status: nil, seq: nil, body: nil, sourceRefs: nil, metadata: nil),
            ],
            edges: edges
        )
    }
}
