import SwiftUI

struct ProjectLauncherListPane: View {
    @Bindable var store: ProjectLauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            statusCard
                .padding(.horizontal, 10)

            searchField
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if !store.visibleRunningProjects.isEmpty {
                        ProjectLauncherSidebarSectionHeader(title: "RUNNING")
                        ForEach(store.visibleRunningProjects) { project in
                            projectRow(project)
                        }
                    }

                    ProjectLauncherSidebarSectionHeader(title: "PROJECTS")
                    ForEach(store.visibleOtherProjects) { project in
                        projectRow(project)
                    }

                    if store.visibleRunningProjects.isEmpty,
                       store.visibleOtherProjects.isEmpty,
                       !store.isScanning {
                        Text(store.query.isEmpty ? "No projects discovered" : "No matching projects")
                            .font(.sora(11))
                            .foregroundStyle(Color.stxMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .padding(.bottom, 10)
        .background(Color.primary.opacity(0.025))
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PROJECTS")
                    .font(.sora(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.stxMuted)
                Text("Launcher")
                    .font(.sora(18, weight: .semibold))
            }
            Spacer(minLength: 8)
            if store.isScanning {
                ProgressView()
                    .controlSize(.mini)
                    .help("Scanning projects")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 50)
        .padding(.bottom, 12)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                WorkspaceMiniStat(value: "\(store.projects.count)", label: "projects")
                WorkspaceMiniStat(value: "\(store.runningActionCount)", label: "running")
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: store.runningActionCount > 0 ? AppIcon.Status.successFilled : AppIcon.Status.clock)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.runningActionCount > 0 ? Color.stxAccent : Color.stxMuted)
                    .accessibilityHidden(true)
                Text(statusMessage)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1))
    }

    private var statusMessage: String {
        if store.isScanning { return "discovering launch methods" }
        if store.runningActionCount > 0 { return "managed services are running" }
        return store.projects.isEmpty ? "waiting for project sources" : "ready to launch"
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: AppIcon.Action.search)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .accessibilityHidden(true)
            TextField("Search projects", text: $store.query)
                .textFieldStyle(.plain)
                .font(.sora(11))
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                } label: {
                    Image(systemName: AppIcon.Action.clear)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxMuted)
                .accessibilityLabel("Clear project search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.stxStroke.opacity(0.65), lineWidth: 1))
    }

    private func projectRow(_ project: ProjectLaunchDescriptor) -> some View {
        ProjectLauncherSidebarRow(
            project: project,
            phase: store.phase(for: project),
            isSelected: store.selectedProjectID == project.id,
            select: { store.selectProject(project) },
            toggleLaunch: {
                if store.isProjectRunning(project) {
                    store.stopProject(project)
                } else {
                    store.startProject(project)
                }
            }
        )
        .help(project.rootPath)
    }
}

private struct ProjectLauncherSidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.sora(10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Color.stxMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }
}

private struct ProjectLauncherSidebarRow: View {
    let project: ProjectLaunchDescriptor
    let phase: ProjectLaunchPhase
    let isSelected: Bool
    let select: () -> Void
    let toggleLaunch: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: select) {
                HStack(spacing: 9) {
                    Image(systemName: project.primaryAction?.kind.symbol ?? AppIcon.Resource.folder)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                        .frame(width: 17)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.sora(11, weight: .semibold))
                            .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(rowDetail)
                            .font(.sora(9))
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(project.name), \(rowDetail)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button(action: toggleLaunch) {
                Image(systemName: launchSymbol)
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(isHovering ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(phase.isActive ? Color(red: 0.90, green: 0.38, blue: 0.30) : Color.stxAccent)
            .disabled(!project.isLaunchable || phase == .starting || phase == .stopping)
            .help(phase.isActive ? "Stop \(project.name)" : "Start \(project.name)")
            .accessibilityLabel(phase.isActive ? "Stop \(project.name)" : "Start \(project.name)")
        }
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.primary.opacity(0.10) : Color.primary.opacity(isHovering ? 0.05 : 0))
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var rowDetail: String {
        switch phase {
        case .starting: "Starting…"
        case .running: "Running"
        case .stopping: "Stopping…"
        case .failed: "Launch failed"
        case .stopped: project.primaryAction?.kind.title ?? "No launch method"
        }
    }

    private var launchSymbol: String {
        switch phase {
        case .starting, .stopping: AppIcon.Status.clock
        case .running: AppIcon.Action.stop
        case .failed, .stopped: AppIcon.Action.start
        }
    }
}

#if DEBUG
#Preview("Projects list pane") {
    ProjectLauncherListPane(store: ProjectLauncherStore())
        .frame(width: 270, height: 680)
        .background(VisualEffectBackground())
}
#endif
