import Foundation
import Observation

@MainActor
@Observable
final class TrackStore {
    private let eventReader: any TrackEventLogReading
    private let builder: TrackSnapshotBuilder

    var snapshot: TrackSnapshot = .empty {
        didSet { keepSelectionValid() }
    }
    var selectedRunID: TrackRun.ID?
    var selectedNodeID: TrackNode.ID?
    var isLoading = false
    var lastError: String?
    var searchText = ""
    var statusFilter: TrackStatus?
    var sourceFilter: TrackEventSource?

    private var hasLoaded = false
    private var queuedRefresh = false

    init(
        eventReader: any TrackEventLogReading = TrackEventLogReader(),
        builder: TrackSnapshotBuilder = TrackSnapshotBuilder()
    ) {
        self.eventReader = eventReader
        self.builder = builder
    }

    var filteredRuns: [TrackRun] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.runs.filter { run in
            if let statusFilter, run.status != statusFilter { return false }
            if let sourceFilter, !run.events.contains(where: { $0.source == sourceFilter }) { return false }
            guard !query.isEmpty else { return true }
            return run.title.localizedCaseInsensitiveContains(query)
                || run.projectName.localizedCaseInsensitiveContains(query)
                || (run.cwd?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var selectedRun: TrackRun? {
        if let selectedRunID,
           let match = snapshot.runs.first(where: { $0.id == selectedRunID }) {
            return match
        }
        return filteredRuns.first ?? snapshot.runs.first
    }

    var selectedNode: TrackNode? {
        guard let selectedRun else { return nil }
        if let selectedNodeID,
           let match = selectedRun.nodes.first(where: { $0.id == selectedNodeID }) {
            return match
        }
        return selectedRun.nodes.first
    }

    var visibleApprovals: [TrackApprovalItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.approvals.filter { item in
            if let statusFilter, item.status != statusFilter { return false }
            if let sourceFilter, item.source != sourceFilter { return false }
            guard !query.isEmpty else { return true }
            return item.title.localizedCaseInsensitiveContains(query)
                || item.detail.localizedCaseInsensitiveContains(query)
        }
    }

    var visibleTools: [TrackToolItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.tools.filter { item in
            if let statusFilter, item.status != statusFilter { return false }
            if let sourceFilter, item.source != sourceFilter { return false }
            guard !query.isEmpty else { return true }
            return item.title.localizedCaseInsensitiveContains(query)
                || item.detail.localizedCaseInsensitiveContains(query)
                || (item.toolName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var visibleEvents: [TrackEvent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.events.filter { event in
            if let statusFilter, status(for: event) != statusFilter { return false }
            if let sourceFilter, event.source != sourceFilter { return false }
            guard !query.isEmpty else { return true }
            return event.summary.localizedCaseInsensitiveContains(query)
                || (event.detail?.localizedCaseInsensitiveContains(query) ?? false)
                || (event.toolName?.localizedCaseInsensitiveContains(query) ?? false)
                || (event.agentType?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    func loadIfNeeded(
        sessions: [Session],
        commandLoader: (Session) async -> [SessionCommandEvent]
    ) async {
        guard !hasLoaded else { return }
        await refresh(sessions: sessions, commandLoader: commandLoader)
    }

    func refresh(
        sessions: [Session],
        commandLoader: (Session) async -> [SessionCommandEvent]
    ) async {
        if isLoading {
            queuedRefresh = true
            return
        }

        isLoading = true
        repeat {
            queuedRefresh = false
            var commandEventsBySessionID: [Session.ID: [SessionCommandEvent]] = [:]
            for session in sessions.sorted(by: { $0.lastModified > $1.lastModified }).prefix(24) {
                commandEventsBySessionID[session.id] = await commandLoader(session)
            }

            let hookEvents = await eventReader.loadEvents()
            let nextSnapshot = builder.build(
                sessions: Array(sessions.prefix(80)),
                commandEventsBySessionID: commandEventsBySessionID,
                hookEvents: hookEvents,
                eventLogURLs: eventReader.eventLogURLs
            )
            snapshot = nextSnapshot
            hasLoaded = true
        } while queuedRefresh

        isLoading = false
    }

    func selectRun(_ run: TrackRun) {
        selectedRunID = run.id
        selectedNodeID = run.nodes.first?.id
    }

    func selectNode(_ node: TrackNode) {
        selectedNodeID = node.id
    }

    func clearError() {
        lastError = nil
    }

    func clearFilters() {
        searchText = ""
        statusFilter = nil
        sourceFilter = nil
    }

    private func keepSelectionValid() {
        if let selectedRunID,
           !snapshot.runs.contains(where: { $0.id == selectedRunID }) {
            self.selectedRunID = nil
            self.selectedNodeID = nil
        }
        if selectedRunID == nil {
            selectedRunID = snapshot.runs.first?.id
        }
        if let selectedRun,
           let selectedNodeID,
           !selectedRun.nodes.contains(where: { $0.id == selectedNodeID }) {
            self.selectedNodeID = selectedRun.nodes.first?.id
        }
        if selectedNodeID == nil {
            selectedNodeID = selectedRun?.nodes.first?.id
        }
    }

    private func status(for event: TrackEvent) -> TrackStatus {
        switch event.kind {
        case .sessionStarted, .turnStarted, .subagentStarted:
            .running
        case .toolRequested, .toolStarted:
            .usingTool
        case .approvalRequested, .questionAsked:
            .waitingApproval
        case .toolFailed, .error:
            .failed
        case .approvalDenied:
            .denied
        case .approvalAllowed, .questionReplied:
            .approved
        case .toolSucceeded, .sessionStopped, .subagentStopped:
            .completed
        case .transcriptActivity:
            .recentlyActive
        case .statusChanged:
            .maybeRunning
        }
    }
}
