import SwiftUI

struct MemoryLibraryView: View {
    @Environment(AppEnvironment.self) private var env
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
                ForEach(store.sortedCodeProjects) { project in
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
                    Task { await store.refreshCodeMemoryStatus(sessions: env.store.sessions) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(store.isCodeMemoryLoading)

                if store.library.isLoadingProjectSortMetadata {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 16)
                }

                projectSortPicker
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
                    MemoryMasonryColumnsView(memories: store.codeMemories, minimumColumnWidth: 260, spacing: 12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(18)
                }
            }
        }
    }

    private var projectSortPicker: some View {
        @Bindable var library = store.library
        return PillSegmentedBar(
            MemoryProjectSortMode.allCases,
            selection: $library.projectSortMode,
            style: .standard,
            help: { $0.help },
            accessibilityLabel: { "Sort projects by \($0.title)" }
        ) { mode, _ in
            Text(mode.title)
        }
    }
}

private struct MemoryMasonryColumnsView: View {
    let models: [MemoryFactCardModel]
    let minimumColumnWidth: CGFloat
    let spacing: CGFloat
    @State private var columnCount = 1

    init(memories: [CodeMemoryMemory], minimumColumnWidth: CGFloat, spacing: CGFloat) {
        self.models = memories.map(MemoryFactCardModel.init(memory:))
        self.minimumColumnWidth = minimumColumnWidth
        self.spacing = spacing
    }

    var body: some View {
        HStack(alignment: .top, spacing: resolvedSpacing) {
            ForEach(columns) { column in
                LazyVStack(alignment: .leading, spacing: resolvedSpacing) {
                    ForEach(column.models) { model in
                        MemoryFactCard(model: model)
                            .equatable()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: Int.self) { proxy in
            Self.resolvedColumnCount(
                for: proxy.size.width,
                minimumColumnWidth: minimumColumnWidth,
                spacing: spacing
            )
        } action: { newColumnCount in
            if columnCount != newColumnCount {
                columnCount = newColumnCount
            }
        }
    }

    private var resolvedSpacing: CGFloat {
        Self.resolvedSpacing(spacing)
    }

    private var columns: [MemoryMasonryColumn] {
        Self.columns(for: models, columnCount: columnCount)
    }

    nonisolated private static func columns(for models: [MemoryFactCardModel], columnCount: Int) -> [MemoryMasonryColumn] {
        let count = max(1, columnCount)
        var columnModels = Array(repeating: [MemoryFactCardModel](), count: count)
        var columnWeights = Array(repeating: 0, count: count)

        for model in models {
            let columnIndex = shortestColumnIndex(in: columnWeights)
            columnModels[columnIndex].append(model)
            columnWeights[columnIndex] += model.estimatedWeight
        }

        return columnModels.indices.map { index in
            MemoryMasonryColumn(id: index, models: columnModels[index])
        }
    }

    nonisolated private static func shortestColumnIndex(in weights: [Int]) -> Int {
        var bestIndex = 0
        var bestWeight = weights[0]
        for index in weights.indices.dropFirst() where weights[index] < bestWeight {
            bestIndex = index
            bestWeight = weights[index]
        }
        return bestIndex
    }

    nonisolated private static func resolvedColumnCount(
        for width: CGFloat,
        minimumColumnWidth: CGFloat,
        spacing: CGFloat
    ) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        let minimumColumnWidth = resolvedMinimumColumnWidth(minimumColumnWidth)
        let spacing = resolvedSpacing(spacing)
        let rawColumnCount = (width + spacing) / (minimumColumnWidth + spacing)
        guard rawColumnCount.isFinite, rawColumnCount > 0 else { return 1 }
        return max(1, Int(rawColumnCount.rounded(.down)))
    }

    nonisolated private static func resolvedMinimumColumnWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return 260 }
        return width
    }

    nonisolated private static func resolvedSpacing(_ spacing: CGFloat) -> CGFloat {
        guard spacing.isFinite, spacing > 0 else { return 0 }
        return spacing
    }
}

private struct MemoryMasonryColumn: Identifiable {
    let id: Int
    let models: [MemoryFactCardModel]
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
