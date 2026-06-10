import Foundation

struct TrackSnapshotBuilder: Sendable {
    func build(
        sessions: [Session],
        commandEventsBySessionID: [Session.ID: [SessionCommandEvent]],
        hookEvents: [TrackEvent],
        now: Date = .now,
        eventLogURLs: [URL] = []
    ) -> TrackSnapshot {
        let fallbackEvents = transcriptFallbackEvents(
            sessions: sessions,
            commandEventsBySessionID: commandEventsBySessionID,
            now: now
        )
        let allEvents = (hookEvents + fallbackEvents).sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id < rhs.id
        }

        let sessionIndex = SessionIndex(sessions: sessions)
        let parentSessionIDBySessionID = Self.parentSessionIndex(from: allEvents)
        let grouped = Dictionary(grouping: allEvents) { event in
            if let parentSessionID = parentSessionIDBySessionID[event.sessionID] ?? event.parentSessionID {
                return sessionIndex.runID(for: parentSessionID)
                    ?? "hook::\(parentSessionID)"
            }
            return sessionIndex.runID(for: event.sessionID) ?? "hook::\(event.sessionID)"
        }

        let runs = grouped.map { runID, events in
            RunReducer(
                runID: runID,
                events: events.sorted { lhs, rhs in
                    if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                    return lhs.id < rhs.id
                },
                session: sessionIndex.session(forRunID: runID),
                now: now
            ).run()
        }
        .sorted { lhs, rhs in
            if lhs.status.priority != rhs.status.priority { return lhs.status.priority > rhs.status.priority }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        let approvals = runs.flatMap(\.approvals).sorted { lhs, rhs in
            if lhs.status.priority != rhs.status.priority { return lhs.status.priority > rhs.status.priority }
            return lhs.requestedAt > rhs.requestedAt
        }
        let tools = runs.flatMap(\.tools).sorted { lhs, rhs in
            if lhs.status.priority != rhs.status.priority { return lhs.status.priority > rhs.status.priority }
            return lhs.startedAt > rhs.startedAt
        }

        return TrackSnapshot(
            runs: runs,
            events: allEvents.sorted { $0.timestamp > $1.timestamp },
            approvals: approvals,
            tools: tools,
            loadedAt: now,
            eventLogURLs: eventLogURLs
        )
    }

    private func transcriptFallbackEvents(
        sessions: [Session],
        commandEventsBySessionID: [Session.ID: [SessionCommandEvent]],
        now: Date
    ) -> [TrackEvent] {
        sessions.flatMap { session in
            var events: [TrackEvent] = []
            let lastActivity = session.stats?.lastActivity ?? session.lastModified
            let age = now.timeIntervalSince(lastActivity)
            let statusSummary = age < 90
                ? "Transcript changed recently"
                : "Transcript activity"
            events.append(TrackEvent(
                id: "transcript::\(session.id)::activity",
                timestamp: lastActivity,
                source: .transcript,
                kind: .transcriptActivity,
                provider: session.provider,
                sessionID: session.externalID.isEmpty ? session.id : session.externalID,
                parentSessionID: nil,
                turnID: nil,
                agentID: nil,
                agentType: nil,
                toolUseID: nil,
                approvalID: nil,
                toolName: nil,
                permissionMode: nil,
                cwd: session.cwd,
                transcriptPath: session.filePath,
                summary: statusSummary,
                detail: session.stats?.title,
                confidence: .medium
            ))

            let commandEvents = Array((commandEventsBySessionID[session.id] ?? []).prefix(8))
            for (index, command) in commandEvents.enumerated() {
                let timestamp = command.timestamp ?? lastActivity.addingTimeInterval(Double(index))
                events.append(TrackEvent(
                    id: "transcript::\(session.id)::command::\(index)",
                    timestamp: timestamp,
                    source: .transcript,
                    kind: .toolRequested,
                    provider: session.provider,
                    sessionID: session.externalID.isEmpty ? session.id : session.externalID,
                    parentSessionID: nil,
                    turnID: nil,
                    agentID: nil,
                    agentType: nil,
                    toolUseID: "transcript-command-\(index)",
                    approvalID: nil,
                    toolName: commandName(from: command.command),
                    permissionMode: nil,
                    cwd: session.cwd,
                    transcriptPath: session.filePath,
                    summary: "Observed command",
                    detail: command.command,
                    confidence: .medium
                ))
            }
            return events
        }
    }

    private func commandName(from command: String) -> String {
        command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "command"
    }

    private static func parentSessionIndex(from events: [TrackEvent]) -> [String: String] {
        var index: [String: String] = [:]
        for event in events {
            guard let parentSessionID = event.parentSessionID,
                  parentSessionID != event.sessionID else { continue }
            index[event.sessionID] = parentSessionID
        }
        return index
    }
}

private struct SessionIndex {
    private let byRunID: [String: Session]
    private let runIDByExternalID: [String: String]

    init(sessions: [Session]) {
        byRunID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        var ids: [String: String] = [:]
        for session in sessions {
            for externalID in Self.aliases(for: session.externalID.isEmpty ? session.id : session.externalID) {
                ids[externalID] = session.id
            }
            for id in Self.aliases(for: session.id) {
                ids[id] = session.id
            }
        }
        runIDByExternalID = ids
    }

    func runID(for externalID: String) -> String? {
        runIDByExternalID[externalID] ?? byRunID[externalID]?.id
    }

    func session(forRunID runID: String) -> Session? {
        byRunID[runID]
    }

    private static func aliases(for raw: String) -> Set<String> {
        var values: Set<String> = [raw]
        if raw.hasPrefix("codex:") {
            values.insert(String(raw.dropFirst("codex:".count)))
        } else {
            values.insert("codex:\(raw)")
        }
        if raw.hasPrefix("codex::") {
            let stripped = String(raw.dropFirst("codex::".count))
            values.insert(stripped)
            values.insert("codex:\(stripped)")
        }
        return values
    }
}

private struct RunReducer {
    let runID: String
    let events: [TrackEvent]
    let session: Session?
    let now: Date

    private var sessionID: String {
        if let session, !session.externalID.isEmpty {
            return session.externalID
        }
        return events.first?.sessionID ?? runID
    }

    func run() -> TrackRun {
        var state = State(
            runID: runID,
            sessionID: sessionID,
            session: session,
            fallbackUpdatedAt: events.last?.timestamp ?? session?.lastModified ?? now
        )

        state.ensureSessionNode(event: events.first)
        for event in events {
            state.apply(event)
        }
        state.finishOpenNodes(now: now)
        return state.makeRun(events: events, now: now)
    }

    private struct State {
        let runID: String
        let sessionID: String
        let session: Session?
        let fallbackUpdatedAt: Date
        var nodes: [TrackNode.ID: TrackNode] = [:]
        var edges: [TrackEdge] = []
        var edgeIDs: Set<String> = []
        var eventIDsByNodeID: [TrackNode.ID: Set<TrackEvent.ID>] = [:]
        var lastTurnNodeID: TrackNode.ID?
        var activeAgentNodeIDByAgentID: [String: TrackNode.ID] = [:]
        var activeToolNodeIDByToolUseID: [String: TrackNode.ID] = [:]
        var approvalNodeIDByApprovalID: [String: TrackNode.ID] = [:]
        var approvalItems: [TrackApprovalItem.ID: TrackApprovalItem] = [:]
        var toolItems: [TrackToolItem.ID: TrackToolItem] = [:]
        var runStatus: TrackStatus = .unknown
        var latestStatus: TrackStatus = .unknown
        var latestStatusConfidence: TrackConfidence = .low
        var sessionStoppedAt: Date?
        var runConfidence: TrackConfidence = .low

        mutating func ensureSessionNode(event: TrackEvent?) {
            let id = sessionNodeID
            guard nodes[id] == nil else { return }
            let stats = session?.stats
            let eventIDs = event.map { [$0.id] } ?? []
            nodes[id] = TrackNode(
                id: id,
                kind: .session,
                title: session?.stats?.title ?? event?.summary ?? session?.projectDisplayName ?? "Agent session",
                subtitle: session?.projectDisplayName ?? event?.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? event?.sessionID ?? "Unknown project",
                status: .unknown,
                source: event?.source ?? .transcript,
                confidence: event?.confidence ?? .low,
                startedAt: stats?.firstActivity ?? event?.timestamp,
                endedAt: nil,
                provider: session?.provider ?? event?.provider,
                eventIDs: eventIDs,
                metadata: [
                    "Session": sessionID,
                    "Provider": (session?.provider ?? event?.provider)?.displayName ?? "Unknown",
                ]
            )
            eventIDsByNodeID[id] = Set(eventIDs)
        }

        mutating func apply(_ event: TrackEvent) {
            ensureSessionNode(event: event)
            let status = eventStatus(for: event)
            runConfidence = max(runConfidence, event.confidence)
            if event.confidence >= latestStatusConfidence {
                latestStatus = status
                latestStatusConfidence = event.confidence
            }
            runStatus = higherPriority(runStatus, status)
            if event.kind == .sessionStopped {
                sessionStoppedAt = event.timestamp
            }
            appendEventID(event.id, to: sessionNodeID)
            updateSessionStatus(status, event: event)

            switch event.kind {
            case .sessionStarted:
                mark(sessionNodeID, status: .running, event: event)
            case .sessionStopped:
                mark(sessionNodeID, status: .completed, event: event, endedAt: event.timestamp)
            case .turnStarted:
                let id = nodeID("turn", event.turnID ?? event.id)
                upsertNode(
                    id: id,
                    kind: .turn,
                    title: "Turn",
                    subtitle: event.permissionMode ?? "Prompt submitted",
                    status: .running,
                    event: event,
                    parent: sessionNodeID
                )
                lastTurnNodeID = id
            case .subagentStarted:
                let agentID = event.agentID ?? event.id
                let id = nodeID("agent", agentID)
                upsertNode(
                    id: id,
                    kind: .subagent,
                    title: event.agentType ?? "Subagent",
                    subtitle: event.agentID ?? "Parallel worker",
                    status: .running,
                    event: event,
                    parent: lastTurnNodeID ?? sessionNodeID
                )
                activeAgentNodeIDByAgentID[agentID] = id
            case .subagentStopped:
                let id = event.agentID.flatMap { activeAgentNodeIDByAgentID[$0] } ?? nodeID("agent", event.agentID ?? event.id)
                upsertNode(
                    id: id,
                    kind: .subagent,
                    title: event.agentType ?? "Subagent",
                    subtitle: "Finished",
                    status: eventStatus(for: event),
                    event: event,
                    parent: lastTurnNodeID ?? sessionNodeID
                )
                mark(id, status: eventStatus(for: event), event: event, endedAt: event.timestamp)
                if let agentID = event.agentID { activeAgentNodeIDByAgentID.removeValue(forKey: agentID) }
            case .toolRequested, .toolStarted, .toolSucceeded, .toolFailed:
                applyTool(event)
            case .approvalRequested, .approvalAllowed, .approvalDenied:
                applyApproval(event)
            case .questionAsked, .questionReplied, .statusChanged, .transcriptActivity, .error:
                applyStatus(event)
            }
        }

        mutating func finishOpenNodes(now: Date) {
            for id in Array(nodes.keys) {
                guard var node = nodes[id], node.endedAt == nil else { continue }
                if node.status == .usingTool || node.status == .running {
                    if let sessionStoppedAt, node.kind != .session {
                        node.status = .completed
                        node.endedAt = sessionStoppedAt
                        nodes[id] = node
                        continue
                    }
                    if node.confidence == .high { continue }
                    node.status = .recentlyActive
                    nodes[id] = node
                }
            }
            if runStatus == .unknown {
                runStatus = inferredCompletionStatus
            }
        }

        func makeRun(events: [TrackEvent], now: Date) -> TrackRun {
            let nodes = Array(nodes.values).sorted { lhs, rhs in
                let lhsDate = lhs.startedAt ?? .distantPast
                let rhsDate = rhs.startedAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.id < rhs.id
            }
            let updatedAt = events.map(\.timestamp).max() ?? fallbackUpdatedAt
            return TrackRun(
                id: runID,
                provider: session?.provider ?? events.first?.provider,
                sessionID: sessionID,
                title: session?.stats?.title ?? nodes.first?.title ?? "Agent session",
                projectName: session?.projectDisplayName ?? events.first?.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown project",
                cwd: session?.cwd ?? events.first?.cwd,
                status: resolvedRunStatus,
                confidence: runConfidence,
                startedAt: session?.stats?.firstActivity ?? events.map(\.timestamp).min(),
                updatedAt: updatedAt,
                nodes: nodes,
                edges: edges.sorted { $0.id < $1.id },
                events: events.sorted { $0.timestamp > $1.timestamp },
                approvals: Array(approvalItems.values),
                tools: Array(toolItems.values)
            )
        }

        private var sessionNodeID: TrackNode.ID { nodeID("session", sessionID) }

        private var inferredCompletionStatus: TrackStatus {
            return .recentlyActive
        }

        private var resolvedRunStatus: TrackStatus {
            if approvalItems.values.contains(where: { $0.status == .waitingApproval }) { return .waitingApproval }
            let childNodes = nodes.values.filter { $0.kind != .session }
            if childNodes.contains(where: { $0.status == .usingTool }) { return .usingTool }
            if childNodes.contains(where: { $0.status == .running }) { return .running }
            if nodes.values.contains(where: { $0.status == .failed }) { return .failed }
            if latestStatus.isSettledRunStatus { return latestStatus }
            if runStatus.isSettledRunStatus { return runStatus }
            return inferredCompletionStatus
        }

        private mutating func applyTool(_ event: TrackEvent) {
            ensureSyntheticAgentIfNeeded(for: event)
            let toolID = event.toolUseID ?? event.id
            let id = activeToolNodeIDByToolUseID[toolID] ?? nodeID("tool", toolID)
            let status = eventStatus(for: event)
            let parent = activeAgentNodeID(for: event) ?? lastTurnNodeID ?? sessionNodeID
            upsertNode(
                id: id,
                kind: .tool,
                title: event.toolName ?? "Tool",
                subtitle: event.detail ?? event.summary,
                status: status,
                event: event,
                parent: parent
            )
            if status == .usingTool || status == .running || status == .recentlyActive {
                activeToolNodeIDByToolUseID[toolID] = id
            } else {
                activeToolNodeIDByToolUseID.removeValue(forKey: toolID)
            }
            mark(id, status: status, event: event, endedAt: status.isTerminalToolStatus ? event.timestamp : nil)
            let itemID = "tool::\(toolID)"
            let existing = toolItems[itemID]
            toolItems[itemID] = TrackToolItem(
                id: itemID,
                runID: runID,
                nodeID: id,
                sessionID: sessionID,
                title: event.toolName ?? existing?.title ?? "Tool",
                detail: event.detail ?? existing?.detail ?? event.summary,
                toolName: event.toolName ?? existing?.toolName,
                status: status,
                startedAt: existing?.startedAt ?? event.timestamp,
                endedAt: status.isTerminalToolStatus ? event.timestamp : existing?.endedAt,
                source: event.source,
                confidence: max(existing?.confidence ?? .low, event.confidence)
            )
            resolveApprovalForCompletedToolIfNeeded(event: event, toolStatus: status)
        }

        private mutating func ensureSyntheticAgentIfNeeded(for event: TrackEvent) {
            guard let agentID = event.agentID,
                  activeAgentNodeIDByAgentID[agentID] == nil else { return }
            let id = nodeID("agent", agentID)
            guard nodes[id] == nil else {
                activeAgentNodeIDByAgentID[agentID] = id
                return
            }
            upsertNode(
                id: id,
                kind: .subagent,
                title: event.agentType ?? "Subagent",
                subtitle: event.agentID ?? "Inferred worker",
                status: .running,
                event: event,
                parent: lastTurnNodeID ?? sessionNodeID
            )
            activeAgentNodeIDByAgentID[agentID] = id
        }

        private mutating func resolveApprovalForCompletedToolIfNeeded(event: TrackEvent, toolStatus: TrackStatus) {
            guard toolStatus.isTerminalToolStatus,
                  let toolUseID = event.toolUseID else { return }
            guard let nodeID = approvalNodeIDByApprovalID[toolUseID] else { return }
            let matchingApprovalID = approvalItems.first { _, item in
                item.status == .waitingApproval && item.nodeID == nodeID
            }?.key
            guard let matchingApprovalID else { return }

            let resolvedStatus: TrackStatus = toolStatus == .failed ? .denied : .approved
            mark(nodeID, status: resolvedStatus, event: event, endedAt: event.timestamp)
            if var item = approvalItems[matchingApprovalID] {
                item.status = resolvedStatus
                item.resolvedAt = event.timestamp
                item.confidence = max(item.confidence, event.confidence)
                approvalItems[matchingApprovalID] = item
            }
        }

        private mutating func applyApproval(_ event: TrackEvent) {
            let approvalID = event.approvalID ?? event.toolUseID ?? event.id
            let id = approvalNodeIDByApprovalID[approvalID] ?? nodeID("approval", approvalID)
            let status = eventStatus(for: event)
            let parent = event.toolUseID.flatMap { activeToolNodeIDByToolUseID[$0] }
                ?? activeAgentNodeID(for: event)
                ?? lastTurnNodeID
                ?? sessionNodeID
            upsertNode(
                id: id,
                kind: .approval,
                title: "Approval",
                subtitle: event.toolName ?? event.permissionMode ?? "Permission gate",
                status: status,
                event: event,
                parent: parent
            )
            approvalNodeIDByApprovalID[approvalID] = id
            if let toolUseID = event.toolUseID {
                approvalNodeIDByApprovalID[toolUseID] = id
            }
            mark(id, status: status, event: event, endedAt: status == .waitingApproval ? nil : event.timestamp)
            let itemID = "approval::\(approvalID)"
            let existing = approvalItems[itemID]
            approvalItems[itemID] = TrackApprovalItem(
                id: itemID,
                runID: runID,
                nodeID: id,
                sessionID: sessionID,
                title: event.toolName.map { "Approve \($0)?" } ?? existing?.title ?? "Approve tool call?",
                detail: event.detail ?? existing?.detail ?? event.summary,
                toolName: event.toolName ?? existing?.toolName,
                status: status,
                requestedAt: existing?.requestedAt ?? event.timestamp,
                resolvedAt: status == .waitingApproval ? existing?.resolvedAt : event.timestamp,
                source: event.source,
                confidence: max(existing?.confidence ?? .low, event.confidence)
            )
        }

        private mutating func applyStatus(_ event: TrackEvent) {
            if event.kind == .transcriptActivity {
                let id = nodeID("turn", "transcript")
                upsertNode(
                    id: id,
                    kind: .turn,
                    title: "Transcript",
                    subtitle: event.summary,
                    status: .recentlyActive,
                    event: event,
                    parent: sessionNodeID
                )
                lastTurnNodeID = id
                return
            }

            if event.kind == .error {
                let id = nodeID("result", event.id)
                upsertNode(
                    id: id,
                    kind: .result,
                    title: "Error",
                    subtitle: event.detail ?? event.summary,
                    status: .failed,
                    event: event,
                    parent: lastTurnNodeID ?? sessionNodeID
                )
            }
        }

        private mutating func upsertNode(
            id: TrackNode.ID,
            kind: TrackNodeKind,
            title: String,
            subtitle: String,
            status: TrackStatus,
            event: TrackEvent,
            parent: TrackNode.ID?
        ) {
            if var node = nodes[id] {
                node.title = title
                node.subtitle = subtitle
                node.status = higherPriority(node.status, status)
                node.confidence = max(node.confidence, event.confidence)
                node.source = node.confidence >= event.confidence ? node.source : event.source
                node.startedAt = node.startedAt ?? event.timestamp
                appendEventIDIfNeeded(event.id, to: &node)
                node.metadata = mergedMetadata(node.metadata, event: event)
                nodes[id] = node
            } else {
                nodes[id] = TrackNode(
                    id: id,
                    kind: kind,
                    title: title,
                    subtitle: subtitle,
                    status: status,
                    source: event.source,
                    confidence: event.confidence,
                    startedAt: event.timestamp,
                    endedAt: nil,
                    provider: event.provider,
                    eventIDs: [event.id],
                    metadata: mergedMetadata([:], event: event)
                )
                eventIDsByNodeID[id] = [event.id]
            }
            if let parent { appendEdge(from: parent, to: id, source: event.source, confidence: event.confidence) }
        }

        private mutating func mark(_ id: TrackNode.ID, status: TrackStatus, event: TrackEvent, endedAt: Date? = nil) {
            guard var node = nodes[id] else { return }
            node.status = status
            node.confidence = max(node.confidence, event.confidence)
            node.endedAt = endedAt ?? node.endedAt
            appendEventIDIfNeeded(event.id, to: &node)
            nodes[id] = node
        }

        private mutating func updateSessionStatus(_ status: TrackStatus, event: TrackEvent) {
            guard var node = nodes[sessionNodeID] else { return }
            node.status = higherPriority(node.status, status)
            node.confidence = max(node.confidence, event.confidence)
            node.startedAt = node.startedAt ?? event.timestamp
            nodes[sessionNodeID] = node
        }

        private mutating func appendEventID(_ eventID: TrackEvent.ID, to nodeID: TrackNode.ID) {
            guard var node = nodes[nodeID] else { return }
            appendEventIDIfNeeded(eventID, to: &node)
            nodes[nodeID] = node
        }

        private mutating func appendEventIDIfNeeded(_ eventID: TrackEvent.ID, to node: inout TrackNode) {
            var eventIDs = eventIDsByNodeID[node.id] ?? Set(node.eventIDs)
            if eventIDs.insert(eventID).inserted {
                node.eventIDs.append(eventID)
            }
            eventIDsByNodeID[node.id] = eventIDs
        }

        private mutating func appendEdge(
            from: TrackNode.ID,
            to: TrackNode.ID,
            source: TrackEventSource,
            confidence: TrackConfidence
        ) {
            guard from != to else { return }
            let edge = TrackEdge(from: from, to: to, source: source, confidence: confidence)
            if edgeIDs.insert(edge.id).inserted {
                edges.append(edge)
            }
        }

        private func activeAgentNodeID(for event: TrackEvent) -> TrackNode.ID? {
            if let agentID = event.agentID, let match = activeAgentNodeIDByAgentID[agentID] { return match }
            return activeAgentNodeIDByAgentID.values.sorted().last
        }

        private func eventStatus(for event: TrackEvent) -> TrackStatus {
            switch event.kind {
            case .sessionStarted, .turnStarted, .subagentStarted:
                .running
            case .toolRequested, .toolStarted:
                .usingTool
            case .toolSucceeded:
                .completed
            case .toolFailed, .error:
                .failed
            case .approvalRequested, .questionAsked:
                .waitingApproval
            case .approvalAllowed, .questionReplied:
                .approved
            case .approvalDenied:
                .denied
            case .sessionStopped, .subagentStopped:
                event.source.confidence == .high ? .completed : .recentlyActive
            case .statusChanged:
                .maybeRunning
            case .transcriptActivity:
                .recentlyActive
            }
        }

        private func higherPriority(_ lhs: TrackStatus, _ rhs: TrackStatus) -> TrackStatus {
            rhs.priority > lhs.priority ? rhs : lhs
        }

        private func nodeID(_ kind: String, _ raw: String) -> String {
            "\(runID)::\(kind)::\(raw)"
        }

        private func mergedMetadata(_ existing: [String: String], event: TrackEvent) -> [String: String] {
            var metadata = existing
            metadata["Source"] = event.source.title
            metadata["Confidence"] = event.confidence.title
            if let cwd = event.cwd { metadata["CWD"] = cwd }
            if let permissionMode = event.permissionMode { metadata["Permission"] = permissionMode }
            if let toolName = event.toolName { metadata["Tool"] = toolName }
            if let agentType = event.agentType { metadata["Agent"] = agentType }
            return metadata
        }
    }
}

private extension TrackStatus {
    var isTerminalToolStatus: Bool {
        switch self {
        case .completed, .failed, .denied:
            return true
        default:
            return false
        }
    }

    var isSettledRunStatus: Bool {
        switch self {
        case .approved, .denied, .completed, .failed, .recentlyActive, .maybeRunning:
            return true
        case .running, .usingTool, .waitingApproval, .unknown:
            return false
        }
    }
}
