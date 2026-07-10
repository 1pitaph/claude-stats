import Foundation
import Observation

@MainActor
@Observable
final class ProjectLauncherStore {
    private(set) var snapshot: ProjectLaunchSnapshot = .empty
    private(set) var isScanning = false
    private(set) var visibleRunningProjects: [ProjectLaunchDescriptor] = []
    private(set) var visibleOtherProjects: [ProjectLaunchDescriptor] = []
    private(set) var runtimeStates: [ProjectLaunchAction.ID: ProjectLaunchRuntimeState] = [:]
    private(set) var logsByActionID: [ProjectLaunchAction.ID: [ProjectLaunchLogEntry]] = [:]
    private(set) var reloadToken: UInt64 = 0
    var selectedProjectID: ProjectLaunchDescriptor.ID?
    var selectedActionID: ProjectLaunchAction.ID?
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            rebuildProjection()
        }
    }
    var lastError: String?

    @ObservationIgnored private let scanner: ProjectLaunchScanner
    @ObservationIgnored private var processes: [ProjectLaunchAction.ID: ProjectManagedProcess] = [:]
    @ObservationIgnored private var pendingRestarts: Set<ProjectLaunchAction.ID> = []
    @ObservationIgnored private var activeReloadIdentity: ReloadIdentity?
    @ObservationIgnored private var lastLoadedIdentity: ReloadIdentity?

    private struct ReloadIdentity: Equatable, Sendable {
        let lastRefreshedAt: Date?
        let sourceIDs: Set<GitWorkspaceSourceID>
        let reloadToken: UInt64
    }

    init(scanner: ProjectLaunchScanner = ProjectLaunchScanner()) {
        self.scanner = scanner
    }

    var projects: [ProjectLaunchDescriptor] { snapshot.projects }

    var selectedProject: ProjectLaunchDescriptor? {
        guard let selectedProjectID else { return projects.first }
        return projects.first { $0.id == selectedProjectID } ?? projects.first
    }

    var runningActionCount: Int {
        runtimeStates.values.filter { $0.phase.isActive }.count
    }

    func bumpReload() {
        reloadToken &+= 1
    }

    func reloadIfNeeded(
        sessions: [Session],
        sourceIDs: Set<GitWorkspaceSourceID>,
        lastRefreshedAt: Date?
    ) async {
        let identity = ReloadIdentity(
            lastRefreshedAt: lastRefreshedAt,
            sourceIDs: GitWorkspaceSourceCatalog.normalized(sourceIDs),
            reloadToken: reloadToken
        )
        if lastLoadedIdentity == identity || activeReloadIdentity == identity { return }
        activeReloadIdentity = identity
        isScanning = true

        let scanner = self.scanner
        let normalizedSourceIDs = identity.sourceIDs
        let result = await Task.detached(priority: .userInitiated) {
            let resolver = GitWorkspaceSourceResolver()
            let cwds = resolver.cwds(sessions: sessions, enabledSources: normalizedSourceIDs)
            let git = GitAnalyzer()
            var roots = Set<String>()
            for cwd in cwds {
                let standardized = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL.path
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }
                roots.insert(git.repo(forCwd: standardized)?.rootPath ?? standardized)
            }
            let projects = scanner.scan(rootPaths: Array(roots))
            return ProjectLaunchSnapshot(
                projects: projects,
                scannedAt: .now,
                sourcePathCount: cwds.count,
                gitAvailable: git.isAvailable
            )
        }.value

        guard activeReloadIdentity == identity else { return }
        snapshot = result
        lastLoadedIdentity = identity
        activeReloadIdentity = nil
        isScanning = false
        reconcileSelection()
        rebuildProjection()
        Log.scanner.info("Project launcher scanned \(result.projects.count, privacy: .public) projects from \(result.sourcePathCount, privacy: .public) paths")
    }

    func selectProject(_ project: ProjectLaunchDescriptor) {
        selectedProjectID = project.id
        reconcileActionSelection(for: project)
    }

    func selectAction(_ action: ProjectLaunchAction) {
        selectedActionID = action.id
    }

    func state(for actionID: ProjectLaunchAction.ID) -> ProjectLaunchRuntimeState {
        runtimeStates[actionID] ?? .stopped
    }

    func logs(for actionID: ProjectLaunchAction.ID) -> [ProjectLaunchLogEntry] {
        logsByActionID[actionID] ?? []
    }

    func isProjectRunning(_ project: ProjectLaunchDescriptor) -> Bool {
        project.actions.contains { state(for: $0.id).phase.isActive }
    }

    func phase(for project: ProjectLaunchDescriptor) -> ProjectLaunchPhase {
        let phases = project.actions.map { state(for: $0.id).phase }
        if phases.contains(.stopping) { return .stopping }
        if phases.contains(.starting) { return .starting }
        if phases.contains(.running) { return .running }
        if phases.contains(.failed) { return .failed }
        return .stopped
    }

    func startProject(_ project: ProjectLaunchDescriptor) {
        let actions = project.recommendedActions
        guard !actions.isEmpty else {
            lastError = "No launch method was detected for \(project.name)."
            return
        }
        for action in actions where !state(for: action.id).phase.isActive {
            start(action)
        }
    }

    func stopProject(_ project: ProjectLaunchDescriptor) {
        for action in project.actions where state(for: action.id).phase.isActive {
            stop(action)
        }
    }

    func restartProject(_ project: ProjectLaunchDescriptor) {
        let activeActions = project.actions.filter { state(for: $0.id).phase.isActive }
        let actions = activeActions.isEmpty ? project.recommendedActions : activeActions
        for action in actions {
            restart(action)
        }
    }

    func stopAll() {
        pendingRestarts.removeAll()
        for process in processes.values {
            let action = process.action
            var state = state(for: action.id)
            state.phase = .stopping
            runtimeStates[action.id] = state
            appendLog(actionID: action.id, stream: .system, text: "Stopping because Claude Stats is quitting…\n")
            process.stop()
        }
        rebuildProjection()
    }

    func start(_ action: ProjectLaunchAction) {
        guard !state(for: action.id).phase.isActive else { return }
        lastError = nil
        var state = ProjectLaunchRuntimeState.stopped
        state.phase = .starting
        runtimeStates[action.id] = state
        appendLog(actionID: action.id, stream: .system, text: "$ \(action.displayCommand)\n")

        let managed = ProjectManagedProcess(action: action) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
        processes[action.id] = managed

        do {
            let pid = try managed.start()
            guard processes[action.id]?.runID == managed.runID else { return }
            state.phase = .running
            state.pid = pid
            state.startedAt = .now
            runtimeStates[action.id] = state
            appendLog(actionID: action.id, stream: .system, text: "Started process \(pid).\n")
            rebuildProjection()
            Log.app.info("Started project action \(action.title, privacy: .public) with pid \(pid, privacy: .public)")
        } catch {
            processes[action.id] = nil
            state.phase = .failed
            state.lastError = error.localizedDescription
            runtimeStates[action.id] = state
            appendLog(actionID: action.id, stream: .stderr, text: "Launch failed: \(error.localizedDescription)\n")
            lastError = "Couldn't start \(action.title): \(error.localizedDescription)"
            rebuildProjection()
            Log.app.error("Failed to start project action \(action.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop(_ action: ProjectLaunchAction) {
        guard let process = processes[action.id], state(for: action.id).phase.isActive else { return }
        var state = state(for: action.id)
        state.phase = .stopping
        runtimeStates[action.id] = state
        appendLog(actionID: action.id, stream: .system, text: "Stopping…\n")
        process.stop()
        rebuildProjection()
    }

    func restart(_ action: ProjectLaunchAction) {
        if state(for: action.id).phase.isActive {
            pendingRestarts.insert(action.id)
            stop(action)
        } else {
            start(action)
        }
    }

    func clearLogs(actionID: ProjectLaunchAction.ID) {
        logsByActionID[actionID] = []
    }

    func clearError() {
        lastError = nil
    }

    private func handle(_ event: ProjectManagedProcessEvent) {
        switch event {
        case .output(let actionID, let runID, let stream, let text):
            guard processes[actionID]?.runID == runID else { return }
            appendLog(actionID: actionID, stream: stream, text: text)
        case .terminated(let actionID, let runID, let pid, let exitCode, let requestedStop):
            guard processes[actionID]?.runID == runID else { return }
            processes[actionID] = nil
            var state = state(for: actionID)
            state.pid = nil
            state.lastExitCode = exitCode
            if requestedStop || exitCode == 0 {
                state.phase = .stopped
                state.lastError = nil
            } else {
                state.phase = .failed
                state.lastError = "Process exited with status \(exitCode)."
                lastError = state.lastError
            }
            runtimeStates[actionID] = state
            appendLog(
                actionID: actionID,
                stream: .system,
                text: requestedStop ? "Stopped process \(pid).\n" : "Process \(pid) exited with status \(exitCode).\n"
            )
            rebuildProjection()

            if pendingRestarts.remove(actionID) != nil,
               let action = action(withID: actionID) {
                start(action)
            }
        }
    }

    private func action(withID actionID: ProjectLaunchAction.ID) -> ProjectLaunchAction? {
        for project in projects {
            if let action = project.actions.first(where: { $0.id == actionID }) {
                return action
            }
        }
        return nil
    }

    private func appendLog(
        actionID: ProjectLaunchAction.ID,
        stream: ProjectLaunchLogStream,
        text: String
    ) {
        guard !text.isEmpty else { return }
        var entries = logsByActionID[actionID] ?? []
        entries.append(ProjectLaunchLogEntry(stream: stream, text: text))
        if entries.count > 1_200 {
            entries.removeFirst(entries.count - 1_000)
        }
        logsByActionID[actionID] = entries
    }

    private func reconcileSelection() {
        if let selectedProjectID,
           let selected = projects.first(where: { $0.id == selectedProjectID }) {
            reconcileActionSelection(for: selected)
            return
        }
        selectedProjectID = projects.first?.id
        if let first = projects.first {
            reconcileActionSelection(for: first)
        } else {
            selectedActionID = nil
        }
    }

    private func reconcileActionSelection(for project: ProjectLaunchDescriptor) {
        if let selectedActionID, project.actions.contains(where: { $0.id == selectedActionID }) {
            return
        }
        selectedActionID = project.primaryActionID ?? project.actions.first?.id
    }

    private func rebuildProjection() {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = normalizedQuery.isEmpty ? projects : projects.filter { project in
            project.name.localizedCaseInsensitiveContains(normalizedQuery)
                || project.rootPath.localizedCaseInsensitiveContains(normalizedQuery)
                || project.actions.contains {
                    $0.title.localizedCaseInsensitiveContains(normalizedQuery)
                        || $0.kind.title.localizedCaseInsensitiveContains(normalizedQuery)
                }
        }
        visibleRunningProjects = filtered.filter(isProjectRunning)
        visibleOtherProjects = filtered.filter { !isProjectRunning($0) }
    }
}
