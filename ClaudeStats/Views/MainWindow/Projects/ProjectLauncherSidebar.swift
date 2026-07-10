import SwiftUI

struct ProjectLauncherListPane: View {
    let store: ProjectLauncherStore

    var body: some View {
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
                    Text("No projects discovered")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(AppSurface.panelFill)
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
        .frame(width: 210, height: 680)
        .background(VisualEffectBackground())
}
#endif
