import SwiftUI

struct MemoryLibraryView: View {
    @Bindable var store: MemoryStore

    private let sidebarWidth: CGFloat = 290

    var body: some View {
        HStack(spacing: 0) {
            librarySidebar
                .frame(width: sidebarWidth)
            Rectangle()
                .fill(Color.stxStroke)
                .frame(width: 1)
            memoryList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var librarySidebar: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 14) {
                projectSection
                moduleSection
            }
            .padding(14)
        }
    }

    private var projectSection: some View {
        MemorySection(title: "Projects", count: store.codeProjects.count, symbol: "folder") {
            LazyVStack(alignment: .leading, spacing: 8) {
                if store.codeProjects.isEmpty {
                    MemoryMutedLine(text: store.codeHealth == nil ? "sidecar offline" : "No projects")
                        .padding(.vertical, 8)
                } else {
                    ForEach(store.codeProjects) { project in
                        ProjectButton(
                            project: project,
                            isSelected: store.codeSelectedProjectID == project.projectID
                        ) {
                            Task { await store.selectCodeProject(project.projectID) }
                        }
                    }
                }
            }
        }
    }

    private var moduleSection: some View {
        MemorySection(title: "Modules", count: store.codeModules.count, symbol: "square.stack.3d.up") {
            LazyVStack(alignment: .leading, spacing: 8) {
                ModuleButton(
                    title: "All Modules",
                    subtitle: "\(store.codeHealth?.memoryCount ?? store.codeMemories.count) active",
                    count: nil,
                    isSelected: store.library.selectedModuleID == nil
                ) {
                    Task { await store.selectModule(nil) }
                }

                ForEach(store.codeModules) { module in
                    ModuleButton(
                        title: module.title,
                        subtitle: "\(module.memoryCount) active · \(module.totalMemoryCount ?? module.memoryCount) total",
                        count: module.memoryCount,
                        isSelected: store.library.selectedModuleID == module.scopeID
                    ) {
                        Task { await store.selectModule(module.scopeID) }
                    }
                }
            }
        }
    }

    private var memoryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(store.codeSelectedProjectID?.memoryAbbreviatingHomeDirectory ?? "All Projects")
                    .font(.sora(13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Menu {
                    ForEach(["active", "proposed", "conflicted", "deprecated", "retracted"], id: \.self) { status in
                        Button(status.capitalized) {
                            store.library.statusFilter = status
                            Task { await store.library.loadMemories(projectID: store.codeSelectedProjectID) }
                        }
                    }
                } label: {
                    Label(store.library.statusFilter.capitalized, systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.button)
                .controlSize(.small)

                Spacer(minLength: 8)

                Button {
                    Task { await store.library.loadMemories(projectID: store.codeSelectedProjectID) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(store.library.isLoading)
            }
            .padding(14)

            StxRule()

            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if store.codeMemories.isEmpty {
                        MemoryEmptyState(
                            title: store.codeHealth == nil ? "Sidecar offline" : "No memories",
                            message: store.library.statusFilter,
                            symbol: "text.badge.checkmark"
                        )
                        .frame(minHeight: 320)
                    } else {
                        ForEach(store.codeMemories) { memory in
                            MemoryFactRow(memory: memory)
                        }
                    }
                }
                .padding(18)
            }
        }
    }
}

private struct ProjectButton: View {
    let project: CodeMemoryProject
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.projectID.memoryAbbreviatingHomeDirectory)
                        .font(.sora(12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(project.memoryCount) active · \(project.totalMemoryCount ?? project.memoryCount) total")
                        .font(.sora(10).monospaced())
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let proposalCount = project.proposalCount, proposalCount > 0 {
                    AIConfigsBadge(text: "\(proposalCount)", color: Color(red: 0.92, green: 0.58, blue: 0.16))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(isSelected ? 0.095 : 0.045), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.stxStroke.opacity(isSelected ? 0.75 : 0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct ModuleButton: View {
    let title: String
    let subtitle: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "shippingbox.fill" : "shippingbox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.sora(12, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.sora(10).monospaced())
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let count {
                    Text("\(count)")
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(isSelected ? 0.095 : 0.045), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.stxStroke.opacity(isSelected ? 0.75 : 0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
