import SwiftUI

struct AIConfigsWorkspaceView: View {
    let section: AIConfigsSection
    let searchText: String
    @Binding var selectedProjectID: String
    @Binding var selectedDocumentID: String
    var relatedSkills: (AIConfigDocument) -> [ConfigRelatedSkill] = { _ in [] }
    var createMissingDocument: (AIConfigDocument) -> Void = { _ in }

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let projects = env.aiConfigs.filteredProjects(section: section, query: searchText)
        let selectedProject = projects.first { $0.id == selectedProjectID }
        let documents = env.aiConfigs.documents(in: selectedProject, section: section, query: searchText)
        let selectedDocument = documents.first { $0.id == selectedDocumentID }

        VStack(spacing: 0) {
            toolbar(projectCount: projects.count, documentCount: documents.count)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            StxRule()
            GeometryReader { proxy in
                if proxy.size.width < AIConfigsPaneMetrics.workspaceAutoBreakpoint {
                    stackedLayout(
                        projects: projects,
                        selectedProject: selectedProject,
                        documents: documents,
                        selectedDocument: selectedDocument
                    )
                } else {
                    sideBySideLayout(
                        projects: projects,
                        selectedProject: selectedProject,
                        documents: documents,
                        selectedDocument: selectedDocument
                    )
                }
            }
        }
    }

    private func sideBySideLayout(
        projects: [AIConfigProject],
        selectedProject: AIConfigProject?,
        documents: [AIConfigDocument],
        selectedDocument: AIConfigDocument?
    ) -> some View {
        HoverableSplitView(
            axis: .vertical,
            primaryFraction: 0.34,
            configuration: AIConfigsPaneMetrics.sideBySideConfiguration
        ) {
            AIConfigsBrowserPane(
                section: section,
                projects: projects,
                selectedProjectID: selectedProjectID,
                documents: documents,
                selectedDocumentID: selectedDocumentID,
                selectProject: selectProject,
                selectDocument: selectDocument
            )
            .frame(minWidth: 0, idealWidth: 360, maxWidth: .infinity)
        } secondary: {
            AIConfigDocumentInspector(
                document: selectedDocument,
                relatedSkills: selectedDocument.map(relatedSkills) ?? [],
                createMissingDocument: createMissingDocument,
                refresh: refresh
            )
                .frame(minWidth: 0, idealWidth: 520, maxWidth: .infinity)
        }
    }

    private func stackedLayout(
        projects: [AIConfigProject],
        selectedProject: AIConfigProject?,
        documents: [AIConfigDocument],
        selectedDocument: AIConfigDocument?
    ) -> some View {
        HoverableSplitView(
            axis: .horizontal,
            primaryFraction: 0.42,
            configuration: AIConfigsPaneMetrics.stackedConfiguration
        ) {
            AIConfigsBrowserPane(
                section: section,
                projects: projects,
                selectedProjectID: selectedProjectID,
                documents: documents,
                selectedDocumentID: selectedDocumentID,
                selectProject: selectProject,
                selectDocument: selectDocument
            )
            .frame(minHeight: 0, maxHeight: .infinity)
        } secondary: {
            AIConfigDocumentInspector(
                document: selectedDocument,
                relatedSkills: selectedDocument.map(relatedSkills) ?? [],
                createMissingDocument: createMissingDocument,
                refresh: refresh
            )
                .frame(minHeight: 0, maxHeight: .infinity)
        }
    }

    private func toolbar(projectCount: Int, documentCount: Int) -> some View {
        HStack(spacing: 10) {
            Label(section.title, systemImage: section.symbol)
                .font(.sora(12, weight: .semibold))
                .foregroundStyle(Color.stxAccent)
            Text("\(projectCount) scopes")
            Text("·")
            Text("\(documentCount) files")
            if !searchText.isEmpty {
                Text("·")
                Text("Search: \(searchText)")
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button {
                refresh()
            } label: {
                Label("Refresh", systemImage: AppIcon.Action.refresh)
            }
            .controlSize(.small)
            .disabled(env.aiConfigs.isLoading)
            .help("Refresh configs")
        }
        .font(.sora(11))
        .foregroundStyle(Color.stxMuted)
    }

    private func selectProject(_ project: AIConfigProject) {
        selectedProjectID = project.id
        selectedDocumentID = env.aiConfigs.resolvedDocumentID(
            current: nil,
            projectID: project.id,
            section: section,
            query: searchText
        ) ?? ""
    }

    private func selectDocument(_ document: AIConfigDocument) {
        selectedDocumentID = document.id
    }

    private func refresh() {
        Task {
            await env.aiConfigs.reload(sessions: env.store.sessions)
        }
    }
}

private struct AIConfigsBrowserPane: View {
    let section: AIConfigsSection
    let projects: [AIConfigProject]
    let selectedProjectID: String
    let documents: [AIConfigDocument]
    let selectedDocumentID: String
    let selectProject: (AIConfigProject) -> Void
    let selectDocument: (AIConfigDocument) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader("Scopes", symbol: AppIcon.Resource.folder)
            StxRule()
            projectList
                .frame(minHeight: 120, maxHeight: 230)
            StxRule()
            paneHeader("Files", symbol: section.symbol)
            StxRule()
            documentList
        }
        .background(Color.primary.opacity(0.025))
    }

    private var projectList: some View {
        AppScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if projects.isEmpty {
                    AIConfigsEmptyState(
                        title: "No matching scopes",
                        message: "Refresh or adjust the search query to inspect configs.",
                        symbol: AppIcon.Resource.unknownFolder
                    )
                    .frame(minHeight: 120)
                } else {
                    ForEach(projects) { project in
                        AIConfigProjectRow(
                            project: project,
                            isSelected: selectedProjectID == project.id,
                            select: { selectProject(project) }
                        )
                    }
                }
            }
            .padding(10)
        }
    }

    private var documentList: some View {
        AppScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if documents.isEmpty {
                    AIConfigsEmptyState(
                        title: "No files",
                        message: "This scope has no files for the selected Config section.",
                        symbol: AppIcon.Resource.document
                    )
                    .frame(minHeight: 220)
                } else {
                    ForEach(documents) { document in
                        AIConfigDocumentRow(
                            document: document,
                            isSelected: selectedDocumentID == document.id,
                            select: { selectDocument(document) }
                        )
                    }
                }
            }
            .padding(10)
        }
    }

    private func paneHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            Text(title)
                .font(.sora(12, weight: .semibold))
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct AIConfigProjectRow: View {
    let project: AIConfigProject
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: project.configsIconName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 18)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(project.name)
                            .font(.sora(12, weight: .semibold))
                            .lineLimit(1)
                        if project.summary.errorCount > 0 {
                            AIConfigsBadge(text: "\(project.summary.errorCount)", color: Color(red: 0.85, green: 0.22, blue: 0.18))
                        }
                    }
                    Text(project.configsDetailText)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 8) {
                        AIConfigsMiniStat(value: "\(project.summary.existingDocumentCount)", label: "files")
                        AIConfigsMiniStat(value: "\(project.summary.planStats.total)", label: "plans")
                        if project.summary.missingExpectedCount > 0 {
                            AIConfigsMiniStat(value: "\(project.summary.missingExpectedCount)", label: "missing")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7).fill(Color.stxAccent.opacity(0.11))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(project.name), \(project.summary.existingDocumentCount) config files")
    }
}

private struct AIConfigDocumentRow: View {
    let document: AIConfigDocument
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: document.kind.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(document.title)
                            .font(.sora(11, weight: .semibold))
                            .lineLimit(1)
                        AIConfigsBadge(text: document.provider.shortName, color: document.provider.accentColor)
                        if !document.exists {
                            AIConfigsBadge(text: "Missing", color: Color.stxMuted)
                        }
                    }
                    Text(document.displayPath)
                        .font(.sora(9))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.stxAccent.opacity(0.10) : Color.primary.opacity(0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? Color.stxAccent.opacity(0.34) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(document.title), \(document.kind.singularDisplayName)")
    }

    private var iconColor: Color {
        if !document.exists { return Color.stxMuted }
        if document.diagnostics.contains(where: { $0.severity == .error }) {
            return Color(red: 0.85, green: 0.22, blue: 0.18)
        }
        if document.hasProblems {
            return Color(red: 0.92, green: 0.58, blue: 0.16)
        }
        return Color.stxAccent
    }
}
