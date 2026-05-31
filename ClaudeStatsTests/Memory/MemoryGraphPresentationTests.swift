import Foundation
import Testing
@testable import ClaudeStats

@Suite("Memory graph presentation")
struct MemoryGraphPresentationTests {
    @Test("Source observed events get friendly readable labels")
    func sourceObservedFriendlyLabels() {
        let event = Self.event(
            eventID: "event:1",
            seq: 2983,
            eventType: "memory.source_observed",
            memoryID: nil,
            title: "Observed session",
            sourceID: "session:one",
            sourcePath: "/Users/test/.codex/sessions/rollout-2026-05-31T15-29.jsonl",
            after: [
                "body": .string("Transcript body"),
                "content_hash": .string("abc"),
                "id": .string("session:one"),
            ]
        )
        let graph = MemoryChangeGraphBuilder.build(projectID: "claude-stats", events: [event])

        let presentation = MemoryGraphPresentation.build(
            projectID: "claude-stats",
            graph: graph,
            events: [event],
            mode: .sourceCentric,
            density: .events,
            expandedGroupIDs: [],
            searchText: ""
        )

        let eventNode = try! #require(presentation.nodes.first { $0.eventID == "event:1" })
        #expect(eventNode.displayTitle == "#2983 · Source observed")
        #expect(eventNode.subtitle?.contains("sync") == true)
        #expect(eventNode.subtitle?.contains("codex_transcript") == true)
        #expect(eventNode.badges.contains("body"))
        #expect(eventNode.badges.contains("content_hash"))
    }

    @Test("Source-centric grouped view keeps source-only events")
    func sourceCentricGroupedKeepsSourceOnlyEvents() {
        let events = [
            Self.event(eventID: "event:1", seq: 1, eventType: "memory.source_observed", memoryID: nil, title: "One", sourceID: "session:one"),
            Self.event(eventID: "event:2", seq: 2, eventType: "memory.source_observed", memoryID: nil, title: "Two", sourceID: "session:one"),
        ]
        let graph = MemoryChangeGraphBuilder.build(projectID: "claude-stats", events: events)

        let presentation = MemoryGraphPresentation.build(
            projectID: "claude-stats",
            graph: graph,
            events: events,
            mode: .sourceCentric,
            density: .grouped,
            expandedGroupIDs: [],
            searchText: ""
        )

        let group = try! #require(presentation.nodes.first { $0.kind == "group" })
        #expect(group.displayTitle == "2 Source observations")
        #expect(group.count == 2)
        #expect(presentation.groups[group.id]?.eventIDs == ["event:1", "event:2"])
        #expect(presentation.nodes.contains { $0.lane == .source })
        #expect(!presentation.nodes.contains { $0.lane == .memory })
    }

    @Test("Timeline mode preserves event order in event density")
    func timelineEventModePreservesOrder() {
        let events = [
            Self.event(eventID: "event:2", seq: 2, eventType: "memory.updated", memoryID: "one", title: "Two", sourceID: "src:2"),
            Self.event(eventID: "event:1", seq: 1, eventType: "memory.created", memoryID: "one", title: "One", sourceID: "src:1"),
        ]
        let graph = MemoryChangeGraphBuilder.build(projectID: "claude-stats", events: events)

        let presentation = MemoryGraphPresentation.build(
            projectID: "claude-stats",
            graph: graph,
            events: events,
            mode: .timeline,
            density: .events,
            expandedGroupIDs: [],
            searchText: ""
        )
        let eventIDs = presentation.nodes
            .filter { $0.lane == .event }
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap(\.eventID)

        #expect(eventIDs == ["event:1", "event:2"])
        #expect(presentation.edges.contains { $0.kind == "NEXT_EVENT" })
    }

    @Test("Memory-centric grouped view creates an unlinked source observations group")
    func memoryCentricGroupsUnlinkedEvents() {
        let events = [
            Self.event(eventID: "event:1", seq: 1, eventType: "memory.source_observed", memoryID: nil, title: "One", sourceID: "session:one"),
            Self.event(eventID: "event:2", seq: 2, eventType: "memory.updated", memoryID: "memory:one", title: "Two", sourceID: "src:2"),
        ]
        let graph = MemoryChangeGraphBuilder.build(projectID: "claude-stats", events: events)

        let presentation = MemoryGraphPresentation.build(
            projectID: "claude-stats",
            graph: graph,
            events: events,
            mode: .memoryCentric,
            density: .grouped,
            expandedGroupIDs: [],
            searchText: ""
        )

        #expect(presentation.nodes.contains { $0.displayTitle == "Unlinked source observations" })
        #expect(presentation.nodes.contains { $0.lane == .memory && $0.memoryID == "memory:one" })
    }

    @Test("Presentation search matches changed fields and source paths")
    func presentationSearchMatchesFieldsAndSources() {
        let events = [
            Self.event(
                eventID: "event:1",
                seq: 1,
                eventType: "memory.source_observed",
                memoryID: nil,
                title: "One",
                sourceID: "session:one",
                sourcePath: "/tmp/sessions/session-one.jsonl",
                after: ["content_hash": .string("abc"), "body": .string("One")]
            ),
            Self.event(
                eventID: "event:2",
                seq: 2,
                eventType: "memory.source_observed",
                memoryID: nil,
                title: "Two",
                sourceID: "session:two",
                sourcePath: "/tmp/sessions/session-two.jsonl",
                after: ["body": .string("Two")]
            ),
        ]
        let graph = MemoryChangeGraphBuilder.build(projectID: "claude-stats", events: events)

        let fieldMatch = MemoryGraphPresentation.build(
            projectID: "claude-stats",
            graph: graph,
            events: events,
            mode: .sourceCentric,
            density: .events,
            expandedGroupIDs: [],
            searchText: "content_hash"
        )
        let pathMatch = MemoryGraphPresentation.build(
            projectID: "claude-stats",
            graph: graph,
            events: events,
            mode: .sourceCentric,
            density: .events,
            expandedGroupIDs: [],
            searchText: "session-two"
        )

        #expect(fieldMatch.nodes.contains { $0.eventID == "event:1" })
        #expect(!fieldMatch.nodes.contains { $0.eventID == "event:2" })
        #expect(pathMatch.nodes.contains { $0.eventID == "event:2" })
    }

    @Test("Selected event neighborhood includes one hop source and memory")
    func selectedEventNeighborhoodIncludesOneHop() {
        let event = Self.event(eventID: "event:1", seq: 1, eventType: "memory.updated", memoryID: "memory:one", title: "One", sourceID: "src:1")
        let graph = MemoryChangeGraphBuilder.build(projectID: "claude-stats", events: [event])
        let presentation = MemoryGraphPresentation.build(
            projectID: "claude-stats",
            graph: graph,
            events: [event],
            mode: .sourceCentric,
            density: .events,
            expandedGroupIDs: [],
            searchText: ""
        )
        let eventNode = try! #require(presentation.nodes.first { $0.eventID == "event:1" })

        let neighborhood = presentation.neighborNodeIDs(selectedNodeID: eventNode.id, selectedEdgeID: nil, selectedGroupID: nil)

        #expect(neighborhood.contains(eventNode.id))
        #expect(neighborhood.contains { id in presentation.nodes.contains { $0.id == id && $0.lane == .source } })
        #expect(neighborhood.contains { id in presentation.nodes.contains { $0.id == id && $0.lane == .memory } })
    }

    @Test("Presentation layer does not rewrite raw graph identifiers")
    func presentationDoesNotRewriteRawGraphIdentifiers() {
        let event = Self.event(eventID: "event:1", seq: 1, eventType: "memory.source_observed", memoryID: nil, title: "One", sourceID: "src:1")
        let graph = MemoryChangeGraphBuilder.build(projectID: "claude-stats", events: [event])

        _ = MemoryGraphPresentation.build(
            projectID: "claude-stats",
            graph: graph,
            events: [event],
            mode: .sourceCentric,
            density: .grouped,
            expandedGroupIDs: [],
            searchText: ""
        )

        #expect(graph.nodes.contains { $0.id == "change:event:event:1" && $0.title == "memory.source_observed" })
        #expect(graph.edges.contains { $0.kind == "FROM_SOURCE" && $0.source == "change:event:event:1" })
    }

    private static func event(
        eventID: String,
        seq: Int,
        eventType: String,
        memoryID: String?,
        title: String,
        sourceID: String,
        sourcePath: String? = nil,
        after: CodeMemoryEventPayload? = nil
    ) -> CodeMemoryEvent {
        CodeMemoryEvent(
            eventID: eventID,
            seq: seq,
            timestamp: Double(seq),
            projectID: "claude-stats",
            actor: ["kind": "sync", "id": "sync"],
            eventType: eventType,
            memoryID: memoryID,
            before: seq == 1 ? nil : ["title": .string(title), "status": .string("active")],
            after: after ?? ["title": .string(title), "body": .string("\(title) body"), "status": .string("active"), "type": .string("fact")],
            delta: nil,
            sourceRefs: [
                CodeMemorySourceRef(
                    kind: "codex_transcript",
                    path: sourcePath,
                    sourceID: sourceID,
                    quote: "\(title) quote"
                ),
            ],
            hash: "h\(seq)",
            prevHash: seq == 1 ? nil : "h\(seq - 1)"
        )
    }
}
