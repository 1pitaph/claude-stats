import AppKit
import SwiftUI

struct ProjectLauncherDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var store: ProjectLauncherStore

    private struct ReloadKey: Equatable {
        let token: UInt64
        let lastRefreshedAt: Date?
        let sourceIDs: String
    }

    var body: some View {
        let sourceIDs = env.preferences.gitWorkspaceSourceIDs
        let reloadKey = ReloadKey(
            token: store.reloadToken,
            lastRefreshedAt: env.store.lastRefreshedAt,
            sourceIDs: GitWorkspaceSourceCatalog.storageString(for: sourceIDs)
        )

        VStack(alignment: .leading, spacing: 0) {
            ProjectLauncherHeader(
                store: store,
                project: store.selectedProject,
                revealProject: revealSelectedProject
            )
            StxRule()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: reloadKey) {
            await store.reloadIfNeeded(
                sessions: env.store.sessions,
                sourceIDs: sourceIDs,
                lastRefreshedAt: env.store.lastRefreshedAt
            )
        }
        .alert("Projects", isPresented: errorPresented) {
            Button("OK") { store.clearError() }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isScanning, store.projects.isEmpty {
            ProjectLauncherEmptyState(
                title: "Discovering projects",
                message: "Scanning known coding workspaces and detecting launch methods.",
                showsProgress: true
            )
        } else if let project = store.selectedProject {
            ProjectLauncherWorkspace(store: store, project: project)
        } else {
            ProjectLauncherEmptyState(
                title: "No projects discovered",
                message: "Open a repository with Claude Code, Codex, Cursor, Windsurf, Trae, or another enabled workspace source, then refresh.",
                showsProgress: false
            )
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.clearError() } }
        )
    }

    private func revealSelectedProject() {
        guard let project = store.selectedProject else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.rootPath, isDirectory: true)])
    }
}

private struct ProjectLauncherHeader: View {
    let store: ProjectLauncherStore
    let project: ProjectLaunchDescriptor?
    let revealProject: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PROJECTS")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Text(project?.name ?? "Project launcher")
                    .font(.sora(24, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(project?.rootPath ?? "Automatically detected development commands and managed runtime logs.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            if store.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .help("Scanning projects")
            }

            if let project {
                Button(action: revealProject) {
                    Label("Reveal", systemImage: AppIcon.Action.revealInFinder)
                }
                .controlSize(.small)

                if store.isProjectRunning(project) {
                    Button {
                        store.restartProject(project)
                    } label: {
                        Label("Restart", systemImage: AppIcon.Action.refresh)
                    }
                    .controlSize(.small)

                    Button {
                        store.stopProject(project)
                    } label: {
                        Label("Stop", systemImage: AppIcon.Action.stop)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.82, green: 0.28, blue: 0.23))
                    .controlSize(.small)
                } else {
                    Button {
                        store.startProject(project)
                    } label: {
                        Label(project.recommendedActions.count > 1 ? "Start All" : "Start", systemImage: AppIcon.Action.start)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!project.isLaunchable)
                }
            }

            Button {
                store.bumpReload()
            } label: {
                Label("Refresh", systemImage: AppIcon.Action.refresh)
            }
            .controlSize(.small)
            .disabled(store.isScanning)
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }
}

private struct ProjectLauncherWorkspace: View {
    let store: ProjectLauncherStore
    let project: ProjectLaunchDescriptor

    var body: some View {
        if project.actions.isEmpty {
            ProjectLauncherEmptyState(
                title: "No launch method detected",
                message: "This project is still listed, but it does not expose a recognized development script, package command, Compose file, Xcode workspace, Make/Just target, Cargo manifest, or Django entry point.",
                showsProgress: false
            )
        } else {
            VSplitView {
                ProjectLaunchActionsPane(store: store, project: project)
                    .frame(minHeight: 220, idealHeight: 310, maxHeight: .infinity)
                ProjectLaunchLogPane(store: store, project: project)
                    .frame(minHeight: 190, idealHeight: 310, maxHeight: .infinity)
            }
        }
    }
}

private struct ProjectLaunchActionsPane: View {
    let store: ProjectLauncherStore
    let project: ProjectLaunchDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DETECTED LAUNCH METHODS")
                        .font(.sora(10, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(Color.stxMuted)
                    Text(actionSummary)
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
                Spacer(minLength: 12)
                if project.recommendedActions.count > 1 {
                    Text("Start All runs \(project.recommendedActions.count) components")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(project.actions) { action in
                        ProjectLaunchActionCard(
                            action: action,
                            state: store.state(for: action.id),
                            isRecommended: project.recommendedActionIDs.contains(action.id),
                            isSelected: store.selectedActionID == action.id,
                            select: { store.selectAction(action) },
                            start: { store.start(action) },
                            stop: { store.stop(action) },
                            restart: { store.restart(action) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
    }

    private var actionSummary: String {
        let kinds = Set(project.actions.map(\.kind.title)).sorted()
        return "\(project.actions.count) method\(project.actions.count == 1 ? "" : "s") · \(kinds.joined(separator: ", "))"
    }
}

private struct ProjectLaunchActionCard: View {
    let action: ProjectLaunchAction
    let state: ProjectLaunchRuntimeState
    let isRecommended: Bool
    let isSelected: Bool
    let select: () -> Void
    let start: () -> Void
    let stop: () -> Void
    let restart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: select) {
                    HStack(spacing: 10) {
                        Image(systemName: action.kind.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 7) {
                                Text(action.title)
                                    .font(.sora(12, weight: .semibold))
                                if isRecommended {
                                    Text("RECOMMENDED")
                                        .font(.sora(8, weight: .semibold))
                                        .tracking(0.5)
                                        .foregroundStyle(Color.stxAccent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.stxAccent.opacity(0.12), in: Capsule())
                                }
                            }
                            Text("\(action.kind.title) · \(action.confidence.title) · \(action.sourcePath)")
                                .font(.sora(9))
                                .foregroundStyle(Color.stxMuted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show logs for \(action.title)")

                ProjectLaunchPhaseLabel(phase: state.phase)

                if state.phase == .running {
                    Button(action: restart) {
                        Image(systemName: AppIcon.Action.refresh)
                    }
                    .buttonStyle(.borderless)
                    .help("Restart \(action.title)")
                    .accessibilityLabel("Restart \(action.title)")
                }

                Button(action: state.phase.isActive ? stop : start) {
                    Image(systemName: state.phase.isActive ? AppIcon.Action.stop : AppIcon.Action.start)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.phase == .starting || state.phase == .stopping)
                .help(state.phase.isActive ? "Stop \(action.title)" : "Start \(action.title)")
                .accessibilityLabel(state.phase.isActive ? "Stop \(action.title)" : "Start \(action.title)")
            }

            Text(action.displayCommand)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.88))
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 8) {
                Text(action.workingDirectory)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let pid = state.pid {
                    Text("PID \(pid)")
                }
                if let error = state.lastError {
                    Text(error)
                        .foregroundStyle(Color(red: 0.90, green: 0.38, blue: 0.30))
                        .lineLimit(1)
                }
            }
            .font(.sora(9))
            .foregroundStyle(Color.stxMuted)
        }
        .padding(12)
        .background(Color.primary.opacity(isSelected ? 0.075 : 0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.stxAccent.opacity(0.55) : Color.stxStroke.opacity(0.7), lineWidth: 1)
        )
    }
}

private struct ProjectLaunchPhaseLabel: View {
    let phase: ProjectLaunchPhase

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(title)
                .font(.sora(9, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(title)")
    }

    private var title: String {
        switch phase {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .running: "Running"
        case .stopping: "Stopping"
        case .failed: "Failed"
        }
    }

    private var tint: Color {
        switch phase {
        case .stopped: Color.stxMuted
        case .starting, .stopping: Color(red: 0.93, green: 0.62, blue: 0.16)
        case .running: Color.stxAccent
        case .failed: Color(red: 0.90, green: 0.30, blue: 0.24)
        }
    }
}

private struct ProjectLaunchLogPane: View {
    let store: ProjectLauncherStore
    let project: ProjectLaunchDescriptor

    private let bottomID = "project-launch-log-bottom"

    private var selectedAction: ProjectLaunchAction? {
        if let selectedActionID = store.selectedActionID,
           let selected = project.actions.first(where: { $0.id == selectedActionID }) {
            return selected
        }
        return project.primaryAction ?? project.actions.first
    }

    private var entries: [ProjectLaunchLogEntry] {
        guard let selectedAction else { return [] }
        return store.logs(for: selectedAction.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RUNTIME LOG")
                        .font(.sora(10, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(Color.stxMuted)
                    Text(selectedAction?.title ?? "Select a launch method")
                        .font(.sora(11, weight: .semibold))
                }
                Spacer(minLength: 12)
                if project.actions.count > 1 {
                    Picker("Log source", selection: actionSelection) {
                        ForEach(project.actions) { action in
                            Text(action.title).tag(action.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                Button {
                    if let selectedAction {
                        store.clearLogs(actionID: selectedAction.id)
                    }
                } label: {
                    Label("Clear", systemImage: AppIcon.Action.clear)
                }
                .controlSize(.small)
                .disabled(entries.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)

            StxRule()

            ScrollViewReader { proxy in
                AppScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if entries.isEmpty {
                            Text("Launch this component to see its output here.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.stxMuted)
                                .padding(14)
                        } else {
                            ForEach(entries) { entry in
                                ProjectLaunchLogRow(entry: entry)
                            }
                        }
                        Color.clear
                            .frame(width: 1, height: 1)
                            .id(bottomID)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(Color.black.opacity(0.22))
                .onChange(of: entries.last?.id) { _, _ in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var actionSelection: Binding<ProjectLaunchAction.ID> {
        Binding(
            get: { selectedAction?.id ?? project.actions[0].id },
            set: { nextID in
                if let action = project.actions.first(where: { $0.id == nextID }) {
                    store.selectAction(action)
                }
            }
        )
    }
}

private struct ProjectLaunchLogRow: View {
    let entry: ProjectLaunchLogEntry

    var body: some View {
        Text(entry.text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(foreground)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var foreground: Color {
        switch entry.stream {
        case .system: Color.stxMuted
        case .stdout: Color.primary.opacity(0.90)
        case .stderr: Color(red: 0.94, green: 0.48, blue: 0.40)
        }
    }
}

private struct ProjectLauncherEmptyState: View {
    let title: String
    let message: String
    let showsProgress: Bool

    var body: some View {
        VStack(spacing: 14) {
            if showsProgress {
                ProgressView()
                    .controlSize(.regular)
            } else {
                Image(systemName: AppIcon.Workspace.projects)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Color.stxMuted)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.sora(16, weight: .semibold))
            Text(message)
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

#if DEBUG
#Preview("Projects detail") {
    ProjectLauncherDetailView(store: ProjectLauncherStore())
        .environment(AppEnvironment.preview())
        .frame(width: 1000, height: 720)
        .background(Color.stxBackground)
}
#endif
