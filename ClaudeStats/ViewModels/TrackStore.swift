import Foundation
import Observation

@MainActor
@Observable
final class TrackStore {
    private let eventReader: any TrackEventLogReading
    private let builder: TrackSnapshotBuilder
    private let hookInstaller: CodexTrackHookInstaller

    var snapshot: TrackSnapshot = .empty {
        didSet { keepSelectionValid() }
    }
    var hookInstallationStatus: CodexTrackHookInstallationStatus?
    var selectedRunID: TrackRun.ID?
    var selectedNodeID: TrackNode.ID?
    var isLoading = false
    var isInstallingHookIntegration = false
    var lastError: String?
    var searchText = ""
    var statusFilter: TrackStatus?
    var sourceFilter: TrackEventSource?

    private var hasLoaded = false
    private var queuedRefresh = false

    init(
        eventReader: any TrackEventLogReading = TrackEventLogReader(),
        builder: TrackSnapshotBuilder = TrackSnapshotBuilder(),
        hookInstaller: CodexTrackHookInstaller = CodexTrackHookInstaller()
    ) {
        self.eventReader = eventReader
        self.builder = builder
        self.hookInstaller = hookInstaller
        self.hookInstallationStatus = hookInstaller.status()
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
        return selectedNode(in: selectedRun)
    }

    func selectedNode(in run: TrackRun) -> TrackNode? {
        if let selectedNodeID,
           let match = run.nodes.first(where: { $0.id == selectedNodeID }) {
            return match
        }
        return run.nodes.first
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
        commandLoader: (Session) async -> [SessionCommandEvent],
        trackEventLoader: (Session) async -> [TrackEvent] = { _ in [] }
    ) async {
        guard !hasLoaded else { return }
        await refresh(sessions: sessions, commandLoader: commandLoader, trackEventLoader: trackEventLoader)
    }

    func refresh(
        sessions: [Session],
        commandLoader: (Session) async -> [SessionCommandEvent],
        trackEventLoader: (Session) async -> [TrackEvent] = { _ in [] }
    ) async {
        if isLoading {
            queuedRefresh = true
            return
        }

        isLoading = true
        repeat {
            queuedRefresh = false
            let sortedSessions = sessions.sorted { $0.lastModified > $1.lastModified }
            let commandSessions = Array(sortedSessions.prefix(24))
            let trackSessions = Array(sortedSessions.prefix(80))
            var commandEventsBySessionID: [Session.ID: [SessionCommandEvent]] = [:]
            var providerTrackEvents: [TrackEvent] = []
            async let hookEvents = eventReader.loadEvents()
            for session in commandSessions {
                commandEventsBySessionID[session.id] = await commandLoader(session)
            }
            for session in trackSessions {
                providerTrackEvents.append(contentsOf: await trackEventLoader(session))
            }

            let snapshotBuilder = builder
            let eventLogURLs = eventReader.eventLogURLs
            let allHookEvents = await hookEvents + providerTrackEvents
            let nextSnapshot = await Task.detached(priority: .userInitiated) {
                snapshotBuilder.build(
                    sessions: trackSessions,
                    commandEventsBySessionID: commandEventsBySessionID,
                    hookEvents: allHookEvents,
                    eventLogURLs: eventLogURLs
                )
            }.value
            let installer = hookInstaller
            let nextHookInstallationStatus = await Task.detached(priority: .utility) {
                installer.status()
            }.value

            snapshot = nextSnapshot
            hookInstallationStatus = nextHookInstallationStatus
            hasLoaded = true
        } while queuedRefresh

        isLoading = false
    }

    func refreshHookInstallationStatus() async {
        let installer = hookInstaller
        hookInstallationStatus = await Task.detached(priority: .utility) {
            installer.status()
        }.value
    }

    func installCodexHookIntegration() async {
        guard !isInstallingHookIntegration else { return }
        isInstallingHookIntegration = true
        lastError = nil
        let installer = hookInstaller
        do {
            let status = try await Task.detached(priority: .utility) {
                try installer.install().status
            }.value
            hookInstallationStatus = status
        } catch {
            lastError = error.localizedDescription
        }
        isInstallingHookIntegration = false
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
