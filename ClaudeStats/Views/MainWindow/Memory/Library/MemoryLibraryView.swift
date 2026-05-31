import SwiftUI

struct MemoryLibraryView: View {
    @Bindable var store: MemoryStore

    private let sidebarWidth: CGFloat = 290
    @State private var sidebarScope: MemoryLibrarySidebarScope = .projects

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
        VStack(alignment: .leading, spacing: 0) {
            sidebarScopePicker
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            AppScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch sidebarScope {
                    case .projects:
                        projectList
                    case .modules:
                        moduleList
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .id(sidebarScope)
        }
    }

    private var sidebarScopePicker: some View {
        PillSegmentedBar(
            MemoryLibrarySidebarScope.allCases,
            selection: $sidebarScope,
            help: { $0.help },
            accessibilityLabel: { $0.title },
            onSelect: { scope in
                if scope == .projects, store.library.selectedModuleID != nil {
                    Task { await store.selectModule(nil) }
                }
            }
        ) { scope, isSelected in
            HStack(spacing: 6) {
                Image(systemName: scope.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(scope.title)
                AIConfigsBadge(
                    text: "\(count(for: scope))",
                    color: isSelected ? Color.stxAccent : Color.stxMuted
                )
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var projectList: some View {
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
                        Task { await store.selectLibraryProject(project.projectID) }
                    }
                }
            }
        }
    }

    private var moduleList: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if store.codeHealth == nil {
                MemoryMutedLine(text: "sidecar offline")
                    .padding(.vertical, 8)
            } else {
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

    private func count(for scope: MemoryLibrarySidebarScope) -> Int {
        switch scope {
        case .projects:
            store.codeProjects.count
        case .modules:
            store.codeModules.count
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
                if store.codeMemories.isEmpty {
                    MemoryEmptyState(
                        title: store.codeHealth == nil ? "Sidecar offline" : "No memories",
                        message: store.library.statusFilter,
                        symbol: "text.badge.checkmark"
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 320)
                    .padding(18)
                } else {
                    MemoryMasonryLayout(minimumColumnWidth: 260, spacing: 12) {
                        ForEach(store.codeMemories) { memory in
                            MemoryFactCard(memory: memory)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(18)
                }
            }
        }
    }
}

private struct MemoryMasonryLayout: Layout {
    var minimumColumnWidth: CGFloat
    var spacing: CGFloat

    private var resolvedMinimumColumnWidth: CGFloat {
        guard minimumColumnWidth.isFinite, minimumColumnWidth > 0 else { return 260 }
        return minimumColumnWidth
    }

    private var resolvedSpacing: CGFloat {
        guard spacing.isFinite, spacing > 0 else { return 0 }
        return spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = resolvedWidth(proposal.width)
        let layout = masonryLayout(width: width, subviews: subviews)
        return CGSize(width: width, height: layout.height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let layout = masonryLayout(width: resolvedWidth(bounds.width), subviews: subviews)
        for index in subviews.indices {
            guard index < layout.positions.count else { continue }
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + layout.positions[index].x,
                    y: bounds.minY + layout.positions[index].y
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: layout.columnWidth, height: layout.sizes[index].height)
            )
        }
    }

    private func resolvedWidth(_ width: CGFloat?) -> CGFloat {
        guard let width, width.isFinite, width > 0 else { return resolvedMinimumColumnWidth }
        return width
    }

    private func masonryLayout(width: CGFloat, subviews: Subviews) -> MemoryMasonryLayoutResult {
        let availableWidth = resolvedWidth(width)
        let minimumColumnWidth = resolvedMinimumColumnWidth
        let spacing = resolvedSpacing

        guard !subviews.isEmpty else {
            return MemoryMasonryLayoutResult(columnWidth: availableWidth, positions: [], sizes: [], height: 0)
        }

        let rawColumnCount = (availableWidth + spacing) / (minimumColumnWidth + spacing)
        let columnCount = max(1, Int(rawColumnCount.rounded(.down)))
        let columnWidth = max((availableWidth - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount), 1)
        var columnHeights = Array(repeating: CGFloat.zero, count: columnCount)
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        positions.reserveCapacity(subviews.count)
        sizes.reserveCapacity(subviews.count)

        for subview in subviews {
            let measuredSize = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let height = measuredSize.height.isFinite ? max(measuredSize.height, 0) : 0
            let size = CGSize(width: columnWidth, height: height)
            let columnIndex = shortestColumnIndex(in: columnHeights)
            let y = columnHeights[columnIndex] == 0 ? 0 : columnHeights[columnIndex] + spacing
            let x = CGFloat(columnIndex) * (columnWidth + spacing)
            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            columnHeights[columnIndex] = y + size.height
        }

        let height = columnHeights.max() ?? 0
        return MemoryMasonryLayoutResult(
            columnWidth: columnWidth,
            positions: positions,
            sizes: sizes,
            height: height.isFinite ? height : 0
        )
    }

    private func shortestColumnIndex(in heights: [CGFloat]) -> Int {
        var bestIndex = 0
        var bestHeight = heights[0]
        for index in heights.indices.dropFirst() where heights[index] < bestHeight {
            bestIndex = index
            bestHeight = heights[index]
        }
        return bestIndex
    }
}

private struct MemoryMasonryLayoutResult {
    let columnWidth: CGFloat
    let positions: [CGPoint]
    let sizes: [CGSize]
    let height: CGFloat
}

private enum MemoryLibrarySidebarScope: String, CaseIterable, Identifiable {
    case projects
    case modules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects:
            "Project"
        case .modules:
            "Modules"
        }
    }

    var symbol: String {
        switch self {
        case .projects:
            "folder"
        case .modules:
            "square.stack.3d.up"
        }
    }

    var help: String {
        switch self {
        case .projects:
            "Show project folders"
        case .modules:
            "Show memory modules"
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
                    Text(project.folderDisplayName)
                        .font(.sora(12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
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
