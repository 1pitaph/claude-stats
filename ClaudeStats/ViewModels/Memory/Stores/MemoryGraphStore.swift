import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class MemoryGraphStore {
    var changeSearchText = ""
    var knowledgeSearchText = ""
    var selectedChangeNodeID: String?
    var selectedChangeEdgeID: String?
    var selectedChangeGroupID: String?
    var selectedKnowledgeNodeID: String?
    var selectedKnowledgeEdgeID: String?
    var displayMode: MemoryGraphDisplayMode = .sourceCentric
    var density: MemoryGraphDensity = .grouped
    var factVisibility: MemoryKnowledgeFactVisibility = .active
    var expandedGroupIDs: Set<String> = []
    var zoom: Double = 1
    var pan = CGSize.zero
    private(set) var knowledgeGraph: CodeMemoryGraph?
    private(set) var changeGraph: CodeMemoryGraph?
    private(set) var events: [CodeMemoryEvent] = []
    private(set) var histories: [String: CodeMemoryMemoryHistory] = [:]
    private(set) var isLoadingKnowledgeGraph = false
    private(set) var isLoadingChanges = false
    private(set) var knowledgeLastError: String?
    private(set) var changeLastError: String?
    private(set) var historyLastError: String?
    private(set) var loadingHistoryMemoryIDs: Set<String> = []

    @ObservationIgnored private let backend: any CodeMemoryBackend

    init(backend: any CodeMemoryBackend) {
        self.backend = backend
    }

    var filteredChangeEvents: [CodeMemoryEvent] {
        let search = changeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sorted = events.sorted { $0.seq > $1.seq }
        guard !search.isEmpty else { return sorted }
        return sorted.filter { event in
            [
                event.eventType,
                event.memoryID,
                event.titleCandidate,
                event.statusTransition,
                event.actor["id"],
                event.actor["kind"],
                event.after?.displayValue("body"),
                event.before?.displayValue("body"),
                MemoryGraphPresentation.changedFields(for: event).joined(separator: " "),
                event.sourceRefs.map { ref in
                    [ref.kind, ref.path, ref.uri, ref.sourceID, ref.episodeID, ref.quote, ref.metadata.values.joined(separator: " ")]
                        .compactMap { $0 }
                        .joined(separator: " ")
                }.joined(separator: " "),
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            .contains(search)
        }
    }

    var selectedChangeNode: CodeMemoryGraphNode? {
        guard let selectedChangeNodeID else { return nil }
        return changeGraph?.nodes.first { $0.id == selectedChangeNodeID }
    }

    var selectedChangeEdge: CodeMemoryGraphEdge? {
        guard let selectedChangeEdgeID else { return nil }
        return changeGraph?.edges.first { $0.id == selectedChangeEdgeID }
    }

    var knowledgePresentation: MemoryKnowledgeGraphPresentation? {
        guard let knowledgeGraph else { return nil }
        return MemoryKnowledgeGraphPresentation.build(
            graph: knowledgeGraph,
            factVisibility: factVisibility,
            searchText: knowledgeSearchText
        )
    }

    var selectedKnowledgeNode: MemoryKnowledgeGraphPresentation.Node? {
        guard let selectedKnowledgeNodeID else { return nil }
        return knowledgePresentation?.node(id: selectedKnowledgeNodeID)
    }

    var selectedKnowledgeEdge: MemoryKnowledgeGraphPresentation.Edge? {
        guard let selectedKnowledgeEdgeID else { return nil }
        return knowledgePresentation?.edge(id: selectedKnowledgeEdgeID)
    }

    var changePresentation: MemoryGraphPresentation? {
        guard let projectID = changeGraph?.projectID,
              let focusedChangeGraph else { return nil }
        return MemoryGraphPresentation.build(
            projectID: projectID,
            graph: focusedChangeGraph,
            events: events,
            mode: displayMode,
            density: density,
            expandedGroupIDs: expandedGroupIDs,
            searchText: changeSearchText
        )
    }

    var selectedChangeGroup: MemoryGraphPresentation.GroupSummary? {
        changePresentation?.group(id: selectedChangeGroupID)
    }

    var selectedChangeEvent: CodeMemoryEvent? {
        if let selectedChangeNodeID,
           let eventID = MemoryChangeGraphBuilder.eventID(fromNodeID: selectedChangeNodeID) {
            return events.first { $0.eventID == eventID }
        }
        if let eventID = selectedChangeNode?.metadata?["event_id"] {
            return events.first { $0.eventID == eventID }
        }
        if let eventID = selectedChangeEdge?.metadata?["event_id"] {
            return events.first { $0.eventID == eventID }
        }
        return nil
    }

    var selectedChangeMemoryID: String? {
        if selectedChangeNode?.kind == "memory" {
            return selectedChangeNode?.metadata?["memory_id"] ?? selectedChangeNode?.id.removingMemoryGraphPrefix("memory:")
        }
        return selectedChangeEvent?.memoryID ?? selectedChangeEdge?.metadata?["memory_id"]
    }

    var focusedChangeGraph: CodeMemoryGraph? {
        guard let projectID = changeGraph?.projectID else { return nil }
        return MemoryChangeGraphBuilder.focusedGraph(
            projectID: projectID,
            events: events,
            selectedEventID: selectedChangeEvent?.eventID,
            selectedMemoryID: selectedChangeMemoryID,
            selectedSourceNodeID: selectedChangeSourceNodeID,
            searchText: changeSearchText
        )
    }

    private var selectedChangeSourceNodeID: String? {
        guard let node = selectedChangeNode, node.kind == "source" || node.kind == "episode" else { return nil }
        return node.id
    }

    func loadGraph(projectID: String?) async {
        guard let projectID, !projectID.isEmpty else {
            knowledgeGraph = nil
            selectedKnowledgeNodeID = nil
            selectedKnowledgeEdgeID = nil
            return
        }

        isLoadingKnowledgeGraph = true
        defer { isLoadingKnowledgeGraph = false }

        do {
            knowledgeGraph = try await backend.graph(projectID: projectID)
            selectedKnowledgeNodeID = selectedKnowledgeNodeID.flatMap { id in
                knowledgePresentation?.nodes.contains { $0.id == id } == true ? id : nil
            }
            selectedKnowledgeEdgeID = selectedKnowledgeEdgeID.flatMap { id in
                knowledgePresentation?.edges.contains { $0.id == id } == true ? id : nil
            }
            knowledgeLastError = nil
        } catch {
            knowledgeGraph = nil
            selectedKnowledgeNodeID = nil
            selectedKnowledgeEdgeID = nil
            knowledgeLastError = error.localizedDescription
        }
    }

    func loadChanges(projectID: String?) async {
        guard let projectID, !projectID.isEmpty else {
            events = []
            changeGraph = nil
            selectedChangeNodeID = nil
            selectedChangeEdgeID = nil
            return
        }

        isLoadingChanges = true
        defer { isLoadingChanges = false }

        do {
            events = try await backend.events(projectID: projectID, afterSeq: nil, limit: 500)
            changeGraph = MemoryChangeGraphBuilder.build(projectID: projectID, events: events)
            selectedChangeNodeID = selectedChangeNodeID.flatMap { id in changeGraph?.nodes.contains { $0.id == id } == true ? id : nil }
            selectedChangeEdgeID = selectedChangeEdgeID.flatMap { id in changeGraph?.edges.contains { $0.id == id } == true ? id : nil }
            if selectedChangeNodeID == nil, selectedChangeEdgeID == nil {
                selectedChangeNodeID = events.max { $0.seq < $1.seq }.map { MemoryChangeGraphBuilder.eventNodeID($0.eventID) }
            }
            changeLastError = nil
        } catch {
            events = []
            changeGraph = nil
            selectedChangeNodeID = nil
            selectedChangeEdgeID = nil
            changeLastError = error.localizedDescription
        }
    }

    func loadHistory(memoryID: String, limit: Int = 80) async {
        guard !memoryID.isEmpty else { return }
        if histories[memoryID] != nil {
            return
        }
        if loadingHistoryMemoryIDs.contains(memoryID) {
            return
        }
        loadingHistoryMemoryIDs.insert(memoryID)
        defer { loadingHistoryMemoryIDs.remove(memoryID) }

        do {
            histories[memoryID] = try await backend.memoryHistory(memoryID: memoryID, limit: limit)
            historyLastError = nil
        } catch {
            historyLastError = error.localizedDescription
        }
    }

    func refreshHistory(memoryID: String, limit: Int = 80) async {
        histories[memoryID] = nil
        await loadHistory(memoryID: memoryID, limit: limit)
    }

    func selectChangeNode(_ id: String?) {
        selectedChangeNodeID = id
        selectedChangeEdgeID = nil
        selectedChangeGroupID = nil
    }

    func selectChangeEdge(_ id: String?) {
        selectedChangeEdgeID = id
        selectedChangeNodeID = nil
        selectedChangeGroupID = nil
    }

    func selectChangeEvent(_ eventID: String) {
        selectedChangeGroupID = nil
        selectChangeNode(MemoryChangeGraphBuilder.eventNodeID(eventID))
    }

    func selectChangeGroup(_ id: String) {
        selectedChangeGroupID = id
        selectedChangeNodeID = nil
        selectedChangeEdgeID = nil
        if expandedGroupIDs.contains(id) {
            expandedGroupIDs.remove(id)
        } else {
            expandedGroupIDs.insert(id)
        }
    }

    func history(for memoryID: String) -> CodeMemoryMemoryHistory? {
        histories[memoryID]
    }

    func selectKnowledgeNode(_ id: String?) {
        selectedKnowledgeNodeID = id
        selectedKnowledgeEdgeID = nil
    }

    func selectKnowledgeEdge(_ id: String?) {
        selectedKnowledgeEdgeID = id
        selectedKnowledgeNodeID = nil
    }

    func resetViewport() {
        zoom = 1
        pan = .zero
    }
}

enum MemoryChangeGraphBuilder {
    private static let focusedEventLimit = 18
    private static let focusedSeqRadius = 5

    static func build(projectID: String, events: [CodeMemoryEvent]) -> CodeMemoryGraph {
        var nodesByID: [String: CodeMemoryGraphNode] = [:]
        var edges: [CodeMemoryGraphEdge] = []
        let eventsBySeq = events.sorted { $0.seq < $1.seq }

        for event in eventsBySeq {
            let eventNodeID = eventNodeID(event.eventID)
            nodesByID[eventNodeID] = CodeMemoryGraphNode(
                id: eventNodeID,
                kind: "change_event",
                title: event.eventType,
                type: event.eventType,
                status: event.statusTransition,
                seq: event.seq,
                body: event.titleCandidate,
                sourceRefs: event.sourceRefs,
                metadata: [
                    "event_id": event.eventID,
                    "memory_id": event.memoryID ?? "",
                    "timestamp": "\(event.timestamp)",
                    "actor": actorLabel(event.actor),
                ].filter { !$0.value.isEmpty }
            )

            var sourceAnchorNodeID = eventNodeID
            var sourceMetadata = [
                "event_id": event.eventID,
                "memory_id": event.memoryID ?? "",
            ].filter { !$0.value.isEmpty }

            if let memoryID = event.memoryID, !memoryID.isEmpty {
                let memoryNodeID = memoryNodeID(memoryID)
                let existingBody = nodesByID[memoryNodeID]?.body
                nodesByID[memoryNodeID] = CodeMemoryGraphNode(
                    id: memoryNodeID,
                    kind: "memory",
                    title: event.titleCandidate,
                    type: event.after?.displayValue("type") ?? event.before?.displayValue("type"),
                    status: event.after?.displayValue("status") ?? event.before?.displayValue("status"),
                    seq: nil,
                    body: event.after?.displayValue("body") ?? event.before?.displayValue("body") ?? existingBody,
                    sourceRefs: event.sourceRefs,
                    metadata: ["memory_id": memoryID]
                )
                edges.append(CodeMemoryGraphEdge(
                    source: eventNodeID,
                    target: memoryNodeID,
                    kind: "AFFECTS",
                    primary: true,
                    fact: event.statusTransition,
                    validAt: nil,
                    invalidAt: nil,
                    metadata: ["event_id": event.eventID, "memory_id": memoryID]
                ))
                sourceAnchorNodeID = memoryNodeID
                sourceMetadata["memory_id"] = memoryID
            }

            for ref in event.sourceRefs {
                let sourceNode = sourceNode(for: ref, projectID: projectID)
                nodesByID[sourceNode.id] = sourceNode
                var metadata = sourceMetadata
                metadata["source_kind"] = ref.kind
                edges.append(CodeMemoryGraphEdge(
                    source: sourceAnchorNodeID,
                    target: sourceNode.id,
                    kind: "FROM_SOURCE",
                    primary: nil,
                    fact: ref.quote,
                    validAt: nil,
                    invalidAt: nil,
                    metadata: metadata
                ))
            }
        }

        for pair in zip(eventsBySeq, eventsBySeq.dropFirst()) {
            edges.append(CodeMemoryGraphEdge(
                source: eventNodeID(pair.0.eventID),
                target: eventNodeID(pair.1.eventID),
                kind: "NEXT_EVENT",
                primary: nil,
                fact: nil,
                validAt: nil,
                invalidAt: nil,
                metadata: ["event_id": pair.1.eventID, "previous_event_id": pair.0.eventID]
            ))
        }

        return CodeMemoryGraph(
            projectID: projectID,
            nodes: nodesByID.values.sorted { $0.id < $1.id },
            edges: dedupe(edges).sorted { $0.id < $1.id }
        )
    }

    static func focusedGraph(
        projectID: String,
        events: [CodeMemoryEvent],
        selectedEventID: String?,
        selectedMemoryID: String?,
        selectedSourceNodeID: String? = nil,
        searchText: String,
        eventLimit: Int = focusedEventLimit
    ) -> CodeMemoryGraph {
        guard !events.isEmpty else {
            return CodeMemoryGraph(projectID: projectID, nodes: [], edges: [])
        }

        let sortedAscending = events.sorted { $0.seq < $1.seq }
        let sortedDescending = sortedAscending.reversed()
        let selectedEvent = selectedEventID.flatMap { id in events.first { $0.eventID == id } }
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var includedEventIDs: Set<String> = []
        var orderedEvents: [CodeMemoryEvent] = []

        func append(_ event: CodeMemoryEvent) {
            if includedEventIDs.insert(event.eventID).inserted {
                orderedEvents.append(event)
            }
        }

        if !normalizedSearch.isEmpty {
            for event in sortedDescending where matches(event, search: normalizedSearch) {
                append(event)
                if orderedEvents.count >= eventLimit {
                    break
                }
            }
        }

        if let selectedEvent {
            append(selectedEvent)
            appendSequenceWindow(around: selectedEvent, from: sortedAscending, into: append)
        }

        let memoryID = selectedMemoryID ?? selectedEvent?.memoryID
        if let memoryID, !memoryID.isEmpty {
            for event in sortedDescending where event.memoryID == memoryID {
                append(event)
                if orderedEvents.count >= eventLimit {
                    break
                }
            }
        }

        if let selectedSourceNodeID, !selectedSourceNodeID.isEmpty {
            for event in sortedDescending where event.sourceRefs.contains(where: { sourceNodeID(for: $0) == selectedSourceNodeID }) {
                append(event)
                if orderedEvents.count >= eventLimit {
                    break
                }
            }
        }

        if orderedEvents.isEmpty {
            for event in sortedDescending.prefix(min(eventLimit, 8)) {
                append(event)
            }
        }

        var focusedEvents = Array(orderedEvents.prefix(eventLimit))
        if let selectedEvent, !focusedEvents.contains(where: { $0.eventID == selectedEvent.eventID }) {
            if focusedEvents.count >= eventLimit {
                focusedEvents.removeLast()
            }
            focusedEvents.insert(selectedEvent, at: 0)
        }
        focusedEvents.sort { $0.seq < $1.seq }
        return build(projectID: projectID, events: focusedEvents)
    }

    static func eventNodeID(_ eventID: String) -> String {
        "change:event:\(eventID)"
    }

    static func eventID(fromNodeID nodeID: String) -> String? {
        let prefix = "change:event:"
        guard nodeID.hasPrefix(prefix) else { return nil }
        return String(nodeID.dropFirst(prefix.count))
    }

    static func memoryNodeID(_ memoryID: String) -> String {
        memoryID.hasPrefix("memory:") ? memoryID : "memory:\(memoryID)"
    }

    private static func sourceNode(for ref: CodeMemorySourceRef, projectID: String) -> CodeMemoryGraphNode {
        let rawID = ref.episodeID ?? ref.sourceID ?? ref.uri ?? ref.path ?? ref.id
        let kind = ref.episodeID == nil ? "source" : "episode"
        let title = ref.path?.memoryAbbreviatingHomeDirectory
            ?? ref.uri
            ?? ref.sourceID
            ?? ref.episodeID
            ?? ref.kind
        return CodeMemoryGraphNode(
            id: sourceNodeID(rawID: rawID, kind: kind),
            kind: kind,
            title: title,
            type: ref.kind,
            status: nil,
            seq: nil,
            body: ref.quote,
            sourceRefs: [ref],
            metadata: [
                "project_id": projectID,
                "source_id": ref.sourceID ?? "",
                "episode_id": ref.episodeID ?? "",
                "uri": ref.uri ?? "",
                "path": ref.path ?? "",
            ].filter { !$0.value.isEmpty }
                .merging(ref.metadata, uniquingKeysWith: { current, _ in current })
        )
    }

    static func sourceNodeID(for ref: CodeMemorySourceRef) -> String {
        let rawID = ref.episodeID ?? ref.sourceID ?? ref.uri ?? ref.path ?? ref.id
        let kind = ref.episodeID == nil ? "source" : "episode"
        return sourceNodeID(rawID: rawID, kind: kind)
    }

    static func sourceNodeID(rawID: String, kind: String) -> String {
        "\(kind):\(rawID.memoryGraphStableIDComponent)"
    }

    private static func actorLabel(_ actor: [String: String]) -> String {
        actor["id"] ?? actor["name"] ?? actor["kind"] ?? "system"
    }

    private static func appendSequenceWindow(
        around selectedEvent: CodeMemoryEvent,
        from sortedAscending: [CodeMemoryEvent],
        into append: (CodeMemoryEvent) -> Void
    ) {
        guard let selectedIndex = sortedAscending.firstIndex(where: { $0.eventID == selectedEvent.eventID }) else { return }
        let lowerBound = max(sortedAscending.startIndex, selectedIndex - focusedSeqRadius)
        let upperBound = min(sortedAscending.endIndex, selectedIndex + focusedSeqRadius + 1)
        for index in lowerBound..<upperBound {
            append(sortedAscending[index])
        }
    }

    private static func matches(_ event: CodeMemoryEvent, search: String) -> Bool {
        [
            event.eventType,
            event.memoryID,
            event.titleCandidate,
            event.statusTransition,
            event.actor["id"],
            event.actor["kind"],
            event.after?.displayValue("body"),
            event.before?.displayValue("body"),
            MemoryGraphPresentation.changedFields(for: event).joined(separator: " "),
            event.sourceRefs.map { ref in
                [ref.kind, ref.path, ref.uri, ref.sourceID, ref.episodeID, ref.quote, ref.metadata.values.joined(separator: " ")]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }.joined(separator: " "),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
        .contains(search)
    }

    private static func dedupe(_ edges: [CodeMemoryGraphEdge]) -> [CodeMemoryGraphEdge] {
        var seen: Set<String> = []
        var result: [CodeMemoryGraphEdge] = []
        for edge in edges where seen.insert(edge.id).inserted {
            result.append(edge)
        }
        return result
    }
}

private extension String {
    func removingMemoryGraphPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    var memoryGraphStableIDComponent: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? self
    }
}
