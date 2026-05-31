import SwiftUI

struct MemoryGanttWorkspaceView: View {
    @Bindable var store: MemoryStore

    private let projectColumnWidth: CGFloat = 290
    @State private var selectedMemory: CodeMemoryMemory?

    var body: some View {
        HStack(spacing: 0) {
            projectColumn
                .frame(width: projectColumnWidth)
            Rectangle()
                .fill(Color.stxStroke)
                .frame(width: 1)
            ganttPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: store.codeSelectedProjectID) {
            await loadGanttIfNeeded()
        }
        .sheet(item: $selectedMemory) { memory in
            MemoryDetailSheet(memory: memory)
        }
    }

    private var projectColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: AppIcon.Resource.folder)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.stxAccent)
                Text("Project")
                    .font(.sora(12, weight: .semibold))
                Spacer()
                Text("\(store.sortedCodeProjects.count)")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if store.codeProjects.isEmpty {
                        MemoryMutedLine(text: store.codeHealth == nil ? "sidecar offline" : "No projects")
                            .padding(.vertical, 8)
                    } else {
                        ForEach(store.sortedCodeProjects) { project in
                            MemoryProjectButton(
                                project: project,
                                isSelected: store.codeSelectedProjectID == project.projectID
                            ) {
                                Task { await store.selectGanttProject(project.projectID) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }

    private var ganttPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            StxRule()
            content
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedProjectTitle)
                    .font(.sora(13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(store.codeSelectedProjectID ?? selectedProjectTitle)
                HStack(spacing: 8) {
                    AIConfigsBadge(text: "\(store.gantt.items.count) memories", color: Color.stxMuted)
                    AIConfigsBadge(text: "\(store.gantt.openEndedCount) open-ended", color: Color.stxAccent)
                    if let loadedAt = store.gantt.loadedAt {
                        Text("loaded \(MemoryFormat.timestamp(loadedAt))")
                            .font(.sora(10).monospaced())
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 12)

            if store.gantt.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await store.gantt.refresh(projectID: store.codeSelectedProjectID) }
            } label: {
                Label("Refresh", systemImage: AppIcon.Action.refresh)
            }
            .controlSize(.small)
            .disabled(store.gantt.isLoading || store.codeSelectedProjectID == nil)
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if store.gantt.isLoading && store.gantt.items.isEmpty {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.gantt.items.isEmpty {
            MemoryEmptyState(
                title: emptyTitle,
                message: emptyMessage,
                symbol: AppIcon.Leaderboard.month
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(18)
        } else if let domain = store.gantt.domain {
            MemoryGanttChartView(
                items: store.gantt.items,
                domain: domain
            ) { memory in
                selectedMemory = memory
            }
        }
    }

    private var selectedProjectTitle: String {
        if let selectedProject {
            return selectedProject.folderDisplayName
        }
        return store.codeSelectedProjectID?.memoryAbbreviatingHomeDirectory ?? "No Project"
    }

    private var selectedProject: CodeMemoryProject? {
        guard let projectID = store.codeSelectedProjectID else { return nil }
        return store.sortedCodeProjects.first { $0.projectID == projectID }
    }

    private var emptyTitle: String {
        if store.codeHealth == nil {
            return "Sidecar offline"
        }
        if store.codeProjects.isEmpty {
            return "No projects"
        }
        return "No intervals"
    }

    private var emptyMessage: String {
        if let error = store.gantt.lastError {
            return error
        }
        if store.codeProjects.isEmpty {
            return "No memory project is available."
        }
        return "This project has no canonical memories across the tracked statuses."
    }

    private func loadGanttIfNeeded() async {
        if let projectID = store.codeSelectedProjectID, !projectID.isEmpty {
            if store.gantt.loadedProjectID != projectID {
                await store.gantt.load(projectID: projectID)
            }
        } else {
            await store.loadGanttForSelectedProject()
        }
    }
}
