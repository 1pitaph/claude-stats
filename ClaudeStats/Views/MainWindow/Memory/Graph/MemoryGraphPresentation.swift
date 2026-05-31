import Foundation

enum MemoryGraphDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case sourceCentric
    case timeline
    case memoryCentric

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sourceCentric:
            "Source"
        case .timeline:
            "Timeline"
        case .memoryCentric:
            "Memory"
        }
    }
}

enum MemoryGraphDensity: String, CaseIterable, Identifiable, Sendable {
    case grouped
    case events

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grouped:
            "Grouped"
        case .events:
            "Events"
        }
    }
}

enum MemoryGraphLane: Int, CaseIterable, Sendable {
    case source
    case event
    case memory

    var label: String {
        switch self {
        case .source:
            "Source"
        case .event:
            "Event"
        case .memory:
            "Memory"
        }
    }
}

struct MemoryGraphPresentation: Sendable, Hashable {
    struct Node: Identifiable, Sendable, Hashable {
        var id: String
        var lane: MemoryGraphLane
        var kind: String
        var displayTitle: String
        var subtitle: String?
        var badges: [String]
        var helpText: String
        var rawNodeID: String?
        var eventID: String?
        var eventType: String?
        var memoryID: String?
        var groupID: String?
        var sortIndex: Int
        var count: Int
        var isExpandedGroup: Bool
    }

    struct Edge: Identifiable, Sendable, Hashable {
        var id: String
        var source: String
        var target: String
        var kind: String
        var label: String
        var eventIDs: [String]
    }

    struct GroupSummary: Identifiable, Sendable, Hashable {
        var id: String
        var title: String
        var subtitle: String
        var eventIDs: [String]
        var changedFieldCounts: [String: Int]
        var sourceLabels: [String]
        var memoryIDs: [String]
    }

    var projectID: String
    var nodes: [Node]
    var edges: [Edge]
    var groups: [String: GroupSummary]
    var summary: String
    var mode: MemoryGraphDisplayMode
    var density: MemoryGraphDensity

    func group(id: String?) -> GroupSummary? {
        guard let id else { return nil }
        return groups[id]
    }

    func neighborNodeIDs(selectedNodeID: String?, selectedEdgeID: String?, selectedGroupID: String?) -> Set<String> {
        var selectedIDs = Set<String>()
        if let selectedGroupID {
            selectedIDs.insert(selectedGroupID)
        }
        if let selectedNodeID {
            selectedIDs.insert(selectedNodeID)
        }
        if let selectedEdgeID, let edge = edges.first(where: { $0.id == selectedEdgeID }) {
            selectedIDs.insert(edge.source)
            selectedIDs.insert(edge.target)
        }
        guard !selectedIDs.isEmpty else { return [] }

        var result = selectedIDs
        for edge in edges where selectedIDs.contains(edge.source) || selectedIDs.contains(edge.target) {
            result.insert(edge.source)
            result.insert(edge.target)
        }
        return result
    }

    static func build(
        projectID: String,
        graph: CodeMemoryGraph,
        events: [CodeMemoryEvent],
        mode: MemoryGraphDisplayMode,
        density: MemoryGraphDensity,
        expandedGroupIDs: Set<String>,
        searchText: String
    ) -> MemoryGraphPresentation {
        let eventIDsInGraph = Set(graph.nodes.compactMap { MemoryChangeGraphBuilder.eventID(fromNodeID: $0.id) })
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visibleEvents = events
            .filter { eventIDsInGraph.isEmpty || eventIDsInGraph.contains($0.eventID) }
            .filter { normalizedSearch.isEmpty || matches($0, search: normalizedSearch) }
            .sorted { lhs, rhs in (lhs.seq, lhs.eventID) < (rhs.seq, rhs.eventID) }

        var builder = Builder(
            projectID: projectID,
            graph: graph,
            events: visibleEvents,
            mode: mode,
            density: density,
            expandedGroupIDs: expandedGroupIDs
        )
        return builder.build()
    }

    static func friendlyEventName(for eventType: String) -> String {
        switch eventType {
        case "memory.source_observed":
            "Source observed"
        case "memory.observed":
            "Memory observed"
        case "memory.created", "created":
            "Memory created"
        case "memory.updated", "updated":
            "Memory updated"
        case "memory.proposed":
            "Memory proposed"
        case "memory.accepted":
            "Memory accepted"
        case "memory.deprecated":
            "Memory deprecated"
        case "memory.retracted":
            "Memory retracted"
        case "memory.superseded":
            "Memory superseded"
        case "memory.conflict_detected":
            "Conflict detected"
        default:
            eventType
                .replacingOccurrences(of: "memory.", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    static func changedFields(for event: CodeMemoryEvent) -> [String] {
        var keys = Set<String>()
        if let before = event.before {
            keys.formUnion(before.keys)
        }
        if let after = event.after {
            keys.formUnion(after.keys)
        }
        if let delta = event.delta {
            keys.formUnion(delta.keys)
        }
        return keys.sorted()
    }

    static func sourceLabel(for sourceRef: CodeMemorySourceRef) -> String {
        if let path = sourceRef.path, !path.isEmpty {
            let last = (path as NSString).lastPathComponent
            let base = last.isEmpty ? path.memoryAbbreviatingHomeDirectory : last
            return trimExtension(base)
        }
        if let uri = sourceRef.uri, !uri.isEmpty {
            return trimExtension((uri as NSString).lastPathComponent.isEmpty ? uri : (uri as NSString).lastPathComponent)
        }
        if let sourceID = sourceRef.sourceID, !sourceID.isEmpty {
            return sourceID
        }
        if let episodeID = sourceRef.episodeID, !episodeID.isEmpty {
            return episodeID
        }
        return sourceRef.kind
    }

    private static func matches(_ event: CodeMemoryEvent, search: String) -> Bool {
        let values: [String?] = [
            event.eventType,
            friendlyEventName(for: event.eventType),
            event.memoryID,
            event.titleCandidate,
            event.statusTransition,
            event.actor["id"],
            event.actor["kind"],
            event.after?.displayValue("body"),
            event.before?.displayValue("body"),
            changedFields(for: event).joined(separator: " "),
            event.sourceRefs.map { sourceRef in
                [
                    sourceRef.kind,
                    sourceRef.path,
                    sourceRef.uri,
                    sourceRef.sourceID,
                    sourceRef.episodeID,
                    sourceRef.quote,
                    sourceRef.metadata.values.joined(separator: " "),
                ]
                .compactMap { $0 }
                .joined(separator: " ")
            }
            .joined(separator: " "),
        ]
        return values
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            .contains(search)
    }

    private static func trimExtension(_ value: String) -> String {
        for suffix in [".jsonl", ".json", ".md", ".txt"] where value.hasSuffix(suffix) {
            return String(value.dropLast(suffix.count))
        }
        return value
    }
}

private struct MemoryGraphEventGroup: Sendable, Hashable {
    var id: String
    var key: String
    var events: [CodeMemoryEvent]
}

private extension MemoryGraphPresentation {
    struct Builder {
        var projectID: String
        var graph: CodeMemoryGraph
        var events: [CodeMemoryEvent]
        var mode: MemoryGraphDisplayMode
        var density: MemoryGraphDensity
        var expandedGroupIDs: Set<String>

        private var nodesByID: [String: Node] = [:]
        private var edgesByID: [String: Edge] = [:]
        private var groupsByID: [String: GroupSummary] = [:]

        init(
            projectID: String,
            graph: CodeMemoryGraph,
            events: [CodeMemoryEvent],
            mode: MemoryGraphDisplayMode,
            density: MemoryGraphDensity,
            expandedGroupIDs: Set<String>
        ) {
            self.projectID = projectID
            self.graph = graph
            self.events = events
            self.mode = mode
            self.density = density
            self.expandedGroupIDs = expandedGroupIDs
        }

        mutating func build() -> MemoryGraphPresentation {
            switch mode {
            case .sourceCentric:
                buildSourceCentric()
            case .timeline:
                buildTimeline()
            case .memoryCentric:
                buildMemoryCentric()
            }

            let nodes = nodesByID.values.sorted { lhs, rhs in
                if lhs.lane.rawValue != rhs.lane.rawValue {
                    return lhs.lane.rawValue < rhs.lane.rawValue
                }
                if lhs.sortIndex != rhs.sortIndex {
                    return lhs.sortIndex < rhs.sortIndex
                }
                return lhs.id < rhs.id
            }
            let edges = edgesByID.values.sorted { $0.id < $1.id }

            return MemoryGraphPresentation(
                projectID: projectID,
                nodes: nodes,
                edges: edges,
                groups: groupsByID,
                summary: summary(for: events),
                mode: mode,
                density: density
            )
        }

        private mutating func buildSourceCentric() {
            switch density {
            case .events:
                for event in events {
                    addSourceEventMemoryPath(for: event)
                }
            case .grouped:
                for group in groupedEvents(mode: .sourceCentric) {
                    addSourceGroupMemoryPath(for: group)
                }
            }
        }

        private mutating func buildTimeline() {
            switch density {
            case .events:
                for event in events {
                    addSourceEventMemoryPath(for: event)
                }
                addTimelineEdges(events)
            case .grouped:
                let groups = contiguousGroups()
                for group in groups {
                    addSourceGroupMemoryPath(for: group)
                }
                addTimelineEdges(groups.map(\.id))
            }
        }

        private mutating func buildMemoryCentric() {
            switch density {
            case .events:
                for event in events {
                    addSourceEventMemoryPath(for: event)
                }
            case .grouped:
                for group in groupedEvents(mode: .memoryCentric) {
                    addSourceGroupMemoryPath(for: group)
                }
            }
        }

        private mutating func addSourceEventMemoryPath(for event: CodeMemoryEvent) {
            let eventNode = makeEventNode(event)
            nodesByID[eventNode.id] = eventNode

            let sourceIDs = addSources(for: event, sortIndex: event.seq)
            for sourceID in sourceIDs {
                addEdge(source: sourceID, target: eventNode.id, kind: "FROM_SOURCE", eventIDs: [event.eventID])
            }

            if let memoryID = event.memoryID, !memoryID.isEmpty {
                let memoryNode = makeMemoryNode(for: memoryID, events: [event])
                nodesByID[memoryNode.id] = memoryNode
                addEdge(source: eventNode.id, target: memoryNode.id, kind: "AFFECTS", eventIDs: [event.eventID])
            }
        }

        private mutating func addSourceGroupMemoryPath(for group: MemoryGraphEventGroup) {
            let isExpanded = expandedGroupIDs.contains(group.id)
            let groupNode = makeGroupNode(group, isExpanded: isExpanded)
            nodesByID[groupNode.id] = groupNode
            groupsByID[group.id] = makeGroupSummary(group)

            let sourceIDs = addSources(for: group.events, sortIndex: groupNode.sortIndex)
            for sourceID in sourceIDs {
                addEdge(source: sourceID, target: groupNode.id, kind: "FROM_SOURCE", eventIDs: group.events.map(\.eventID))
            }

            let memoryIDs = Set(group.events.compactMap(\.memoryID).filter { !$0.isEmpty })
            for memoryID in memoryIDs.sorted() {
                let memoryNode = makeMemoryNode(for: memoryID, events: group.events.filter { $0.memoryID == memoryID })
                nodesByID[memoryNode.id] = memoryNode
                addEdge(source: groupNode.id, target: memoryNode.id, kind: "AFFECTS", eventIDs: group.events.map(\.eventID))
            }

            guard isExpanded else { return }
            for event in group.events {
                let eventNode = makeEventNode(event, parentGroupID: group.id)
                nodesByID[eventNode.id] = eventNode
                addEdge(source: groupNode.id, target: eventNode.id, kind: "GROUP_CONTAINS", eventIDs: [event.eventID])
                if let memoryID = event.memoryID, !memoryID.isEmpty {
                    addEdge(source: eventNode.id, target: MemoryChangeGraphBuilder.memoryNodeID(memoryID), kind: "AFFECTS", eventIDs: [event.eventID])
                }
            }
        }

        private mutating func addSources(for event: CodeMemoryEvent, sortIndex: Int) -> [String] {
            addSources(for: [event], sortIndex: sortIndex)
        }

        private mutating func addSources(for events: [CodeMemoryEvent], sortIndex: Int) -> [String] {
            let refs = events.flatMap(\.sourceRefs)
            guard !refs.isEmpty else { return [] }

            var sourceIDs: [String] = []
            var seen = Set<String>()
            for ref in refs {
                let sourceID = MemoryChangeGraphBuilder.sourceNodeID(for: ref)
                if seen.insert(sourceID).inserted {
                    sourceIDs.append(sourceID)
                }
                if nodesByID[sourceID] == nil {
                    nodesByID[sourceID] = makeSourceNode(ref, sortIndex: sortIndex)
                }
            }
            return sourceIDs
        }

        private mutating func addEdge(source: String, target: String, kind: String, eventIDs: [String]) {
            let id = "edge:\(source)->\(target):\(kind):\(eventIDs.joined(separator: ","))"
            edgesByID[id] = Edge(
                id: id,
                source: source,
                target: target,
                kind: kind,
                label: MemoryGraphStyle.edgeLabel(for: kind),
                eventIDs: eventIDs
            )
        }

        private mutating func addTimelineEdges(_ events: [CodeMemoryEvent]) {
            for pair in zip(events, events.dropFirst()) {
                addEdge(
                    source: makeEventNode(pair.0).id,
                    target: makeEventNode(pair.1).id,
                    kind: "NEXT_EVENT",
                    eventIDs: [pair.1.eventID]
                )
            }
        }

        private mutating func addTimelineEdges(_ nodeIDs: [String]) {
            for pair in zip(nodeIDs, nodeIDs.dropFirst()) {
                addEdge(source: pair.0, target: pair.1, kind: "NEXT_EVENT", eventIDs: [])
            }
        }

        private func makeSourceNode(_ sourceRef: CodeMemorySourceRef, sortIndex: Int) -> Node {
            let title = MemoryGraphPresentation.sourceLabel(for: sourceRef).memoryGraphPresentationTruncatedMiddle(maxLength: 34)
            let path = sourceRef.path ?? sourceRef.uri ?? sourceRef.sourceID ?? sourceRef.episodeID
            let subtitle = [sourceRef.kind, path?.memoryAbbreviatingHomeDirectory]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
            let help = [
                title,
                sourceRef.kind,
                sourceRef.path,
                sourceRef.uri,
                sourceRef.sourceID,
                sourceRef.episodeID,
                sourceRef.quote,
            ]
            .compactMap { $0 }
            .joined(separator: "\n")

            return Node(
                id: MemoryChangeGraphBuilder.sourceNodeID(for: sourceRef),
                lane: .source,
                kind: sourceRef.episodeID == nil ? "source" : "episode",
                displayTitle: title,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                badges: Array([sourceRef.kind].filter { !$0.isEmpty }.prefix(2)),
                helpText: help,
                rawNodeID: MemoryChangeGraphBuilder.sourceNodeID(for: sourceRef),
                eventID: nil,
                eventType: nil,
                memoryID: nil,
                groupID: nil,
                sortIndex: sortIndex,
                count: 1,
                isExpandedGroup: false
            )
        }

        private func makeEventNode(_ event: CodeMemoryEvent, parentGroupID: String? = nil) -> Node {
            let changedFields = MemoryGraphPresentation.changedFields(for: event)
            let title = "#\(event.seq) · \(MemoryGraphPresentation.friendlyEventName(for: event.eventType))"
            let actor = event.actor["id"] ?? event.actor["name"] ?? event.actor["kind"] ?? "system"
            let sourceKind = event.sourceRefs.first?.kind
            let subtitle = [
                MemoryFormat.timestamp(event.timestamp),
                actor,
                sourceKind,
            ]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
            let id = parentGroupID.map { "\($0):event:\(event.eventID)" } ?? MemoryChangeGraphBuilder.eventNodeID(event.eventID)
            let preview = event.after?.displayValue("body") ?? event.before?.displayValue("body") ?? event.titleCandidate
            let help = [
                title,
                event.eventID,
                "type: \(event.eventType)",
                event.memoryID.map { "memory: \($0)" },
                changedFields.isEmpty ? nil : "changed: \(changedFields.joined(separator: ", "))",
                preview,
            ]
            .compactMap { $0 }
            .joined(separator: "\n")

            return Node(
                id: id,
                lane: .event,
                kind: "event",
                displayTitle: title,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                badges: Array(changedFields.prefix(3)),
                helpText: help,
                rawNodeID: MemoryChangeGraphBuilder.eventNodeID(event.eventID),
                eventID: event.eventID,
                eventType: event.eventType,
                memoryID: event.memoryID,
                groupID: parentGroupID,
                sortIndex: event.seq,
                count: 1,
                isExpandedGroup: false
            )
        }

        private func makeMemoryNode(for memoryID: String, events: [CodeMemoryEvent]) -> Node {
            let representative = events.sorted { $0.seq > $1.seq }.first
            let nodeID = MemoryChangeGraphBuilder.memoryNodeID(memoryID)
            let title = representative?.titleCandidate.memoryGraphPresentationTruncatedMiddle(maxLength: 42) ?? memoryID
            let type = representative?.after?.displayValue("type") ?? representative?.before?.displayValue("type")
            let status = representative?.after?.displayValue("status") ?? representative?.before?.displayValue("status")
            let sourceCount = Set(events.flatMap(\.sourceRefs).map(\.id)).count
            let subtitle = [
                status,
                type,
                events.isEmpty ? nil : "\(events.count) events",
                sourceCount > 0 ? "\(sourceCount) sources" : nil,
            ]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
            let body = representative?.after?.displayValue("body") ?? representative?.before?.displayValue("body")
            let help = [
                title,
                "id: \(memoryID)",
                subtitle,
                body,
            ]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: "\n")

            return Node(
                id: nodeID,
                lane: .memory,
                kind: "memory",
                displayTitle: title,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                badges: [status, type].compactMap { $0 }.filter { !$0.isEmpty },
                helpText: help,
                rawNodeID: nodeID,
                eventID: nil,
                eventType: nil,
                memoryID: memoryID,
                groupID: nil,
                sortIndex: representative?.seq ?? Int.max,
                count: events.count,
                isExpandedGroup: false
            )
        }

        private func makeGroupNode(_ group: MemoryGraphEventGroup, isExpanded: Bool) -> Node {
            let changedFields = topChangedFields(in: group.events)
            let first = group.events.first
            let friendly = first.map { MemoryGraphPresentation.friendlyEventName(for: $0.eventType) } ?? "Events"
            let title: String
            if group.key == "memory:unlinked" {
                title = "Unlinked source observations"
            } else {
                title = "\(group.events.count) \(friendly.memoryGraphPresentationPluralized(count: group.events.count))"
            }
            let sourceLabels = sourceLabels(in: group.events)
            let memoryCount = Set(group.events.compactMap(\.memoryID)).count
            let subtitle = [
                sourceLabels.prefix(2).joined(separator: ", "),
                memoryCount > 0 ? "\(memoryCount) memories" : nil,
                isExpanded ? "expanded" : nil,
            ]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
            let help = [
                title,
                subtitle,
                changedFields.isEmpty ? nil : "changed: \(changedFields.joined(separator: ", "))",
                "events: \(group.events.map(\.eventID).joined(separator: ", "))",
            ]
            .compactMap { $0 }
            .joined(separator: "\n")

            return Node(
                id: group.id,
                lane: .event,
                kind: "group",
                displayTitle: title,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                badges: Array(changedFields.prefix(3)),
                helpText: help,
                rawNodeID: nil,
                eventID: nil,
                eventType: first?.eventType,
                memoryID: nil,
                groupID: group.id,
                sortIndex: group.events.map(\.seq).min() ?? Int.max,
                count: group.events.count,
                isExpandedGroup: isExpanded
            )
        }

        private func makeGroupSummary(_ group: MemoryGraphEventGroup) -> GroupSummary {
            let node = makeGroupNode(group, isExpanded: expandedGroupIDs.contains(group.id))
            return GroupSummary(
                id: group.id,
                title: node.displayTitle,
                subtitle: node.subtitle ?? "",
                eventIDs: group.events.map(\.eventID),
                changedFieldCounts: changedFieldCounts(in: group.events),
                sourceLabels: sourceLabels(in: group.events),
                memoryIDs: Array(Set(group.events.compactMap(\.memoryID))).sorted()
            )
        }

        private func groupedEvents(mode: MemoryGraphDisplayMode) -> [MemoryGraphEventGroup] {
            let grouped = Dictionary(grouping: events) { event in
                switch mode {
                case .sourceCentric:
                    return [
                        primarySourceKey(for: event),
                        event.eventType,
                        event.memoryID ?? "unlinked",
                    ].joined(separator: "|")
                case .memoryCentric:
                    return event.memoryID.map { "memory:\($0)" } ?? "memory:unlinked"
                case .timeline:
                    return timelineKey(for: event)
                }
            }
            return grouped
                .map { key, items in
                    MemoryGraphEventGroup(
                        id: "group:\(mode.rawValue):\(key.memoryGraphPresentationStableID)",
                        key: key,
                        events: items.sorted { ($0.seq, $0.eventID) < ($1.seq, $1.eventID) }
                    )
                }
                .sorted { lhs, rhs in
                    (lhs.events.map(\.seq).min() ?? Int.max, lhs.id) < (rhs.events.map(\.seq).min() ?? Int.max, rhs.id)
                }
        }

        private func contiguousGroups() -> [MemoryGraphEventGroup] {
            var groups: [MemoryGraphEventGroup] = []
            var currentKey: String?
            var currentEvents: [CodeMemoryEvent] = []

            func flush() {
                guard let currentKey, !currentEvents.isEmpty else { return }
                groups.append(MemoryGraphEventGroup(
                    id: "group:timeline:\(currentKey.memoryGraphPresentationStableID):\(currentEvents.first?.seq ?? 0)",
                    key: currentKey,
                    events: currentEvents
                ))
            }

            for event in events {
                let key = timelineKey(for: event)
                if key != currentKey {
                    flush()
                    currentKey = key
                    currentEvents = [event]
                } else {
                    currentEvents.append(event)
                }
            }
            flush()
            return groups
        }

        private func timelineKey(for event: CodeMemoryEvent) -> String {
            [primarySourceKey(for: event), event.eventType, event.memoryID ?? "unlinked"].joined(separator: "|")
        }

        private func primarySourceKey(for event: CodeMemoryEvent) -> String {
            guard let sourceRef = event.sourceRefs.first else { return "source:none" }
            return MemoryChangeGraphBuilder.sourceNodeID(for: sourceRef)
        }

        private func sourceLabels(in events: [CodeMemoryEvent]) -> [String] {
            let labels = events.flatMap(\.sourceRefs).map(MemoryGraphPresentation.sourceLabel(for:))
            var seen = Set<String>()
            return labels.filter { seen.insert($0).inserted }
        }

        private func topChangedFields(in events: [CodeMemoryEvent]) -> [String] {
            Array(changedFieldCounts(in: events).sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }.map(\.key).prefix(4))
        }

        private func changedFieldCounts(in events: [CodeMemoryEvent]) -> [String: Int] {
            var counts: [String: Int] = [:]
            for event in events {
                for field in MemoryGraphPresentation.changedFields(for: event) {
                    counts[field, default: 0] += 1
                }
            }
            return counts
        }

        private func summary(for events: [CodeMemoryEvent]) -> String {
            let sourceCount = Set(events.flatMap(\.sourceRefs).map(\.id)).count
            let memoryCount = Set(events.compactMap(\.memoryID)).count
            let fields = topChangedFields(in: events).prefix(3).joined(separator: ", ")
            var parts = ["\(events.count) events"]
            parts.append("from \(sourceCount) sources")
            if memoryCount > 0 {
                parts.append("\(memoryCount) linked memories")
            }
            if !fields.isEmpty {
                parts.append("changed \(fields)")
            }
            return parts.joined(separator: ", ")
        }
    }
}

private extension String {
    var memoryGraphPresentationStableID: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? self
    }

    func memoryGraphPresentationTruncatedMiddle(maxLength: Int) -> String {
        guard count > maxLength, maxLength > 8 else { return self }
        let headCount = max(4, (maxLength - 1) / 2)
        let tailCount = max(3, maxLength - headCount - 1)
        return "\(prefix(headCount))...\(suffix(tailCount))"
    }

    func memoryGraphPresentationPluralized(count: Int) -> String {
        guard count != 1 else { return self }
        if lowercased().hasSuffix("observed") {
            return replacingOccurrences(of: "observed", with: "observations")
        }
        if lowercased().hasSuffix("updated") {
            return replacingOccurrences(of: "updated", with: "updates")
        }
        if lowercased().hasSuffix("created") {
            return replacingOccurrences(of: "created", with: "creations")
        }
        return "\(self) events"
    }
}
