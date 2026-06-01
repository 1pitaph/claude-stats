import SwiftUI

struct MemoryGraphWorkspaceView: View {
    @Bindable var store: MemoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            StxRule()
            MemoryGraphChangesView(store: store)
        }
        .task(id: selectedGraphProjectID) {
            await loadGraphIfNeeded()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            searchField
            factVisibilityPicker

            Menu {
                ForEach(store.codeProjects) { project in
                    Button(project.folderDisplayName) {
                        Task { await store.selectCodeProject(project.projectID) }
                    }
                }
            } label: {
                Label(selectedProjectDisplayName, systemImage: AppIcon.Resource.folder)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .menuStyle(.button)
            .controlSize(.small)
            .frame(width: 180)
            .help(selectedGraphProjectID ?? "Project")

            Spacer(minLength: 8)

            Button {
                store.graph.zoom = max(0.45, store.graph.zoom - 0.1)
            } label: {
                Image(systemName: AppIcon.Action.zoomOut)
            }
            .controlSize(.small)
            .help("Zoom Out")

            Slider(value: Binding(
                get: { store.graph.zoom },
                set: { store.graph.zoom = $0 }
            ), in: 0.45...2.2)
                .frame(width: 90)

            Button {
                store.graph.zoom = min(2.2, store.graph.zoom + 0.1)
            } label: {
                Image(systemName: AppIcon.Action.zoomIn)
            }
            .controlSize(.small)
            .help("Zoom In")

            Button {
                store.graph.resetViewport()
            } label: {
                Image(systemName: AppIcon.Action.viewfinder)
            }
            .controlSize(.small)
            .help("Reset View")

            Button {
                Task { await store.graph.loadGraph(projectID: selectedGraphProjectID) }
            } label: {
                Label("Refresh", systemImage: AppIcon.Action.refresh)
            }
            .controlSize(.small)
            .disabled(selectedGraphProjectID == nil || store.graph.isLoadingKnowledgeGraph)
        }
        .padding(14)
    }

    private var factVisibilityPicker: some View {
        HStack(spacing: 7) {
            Text("Facts")
                .font(.sora(12, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Picker("", selection: Binding(
                get: { store.graph.factVisibility },
                set: { store.graph.factVisibility = $0 }
            )) {
                ForEach(MemoryKnowledgeFactVisibility.allCases) { visibility in
                    Text(visibility.label).tag(visibility)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 176)
        }
        .frame(width: 222, alignment: .leading)
        .layoutPriority(1)
        .help("Fact Visibility")
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: AppIcon.Action.search)
                .font(.system(size: 12))
                .foregroundStyle(Color.stxMuted)
            TextField("Entity, fact, relation, or source", text: Binding(
                get: { store.graph.knowledgeSearchText },
                set: { store.graph.knowledgeSearchText = $0 }
            ))
                .textFieldStyle(.plain)
                .font(.sora(12))
            if !store.graph.knowledgeSearchText.isEmpty {
                Button {
                    store.graph.knowledgeSearchText = ""
                } label: {
                    Image(systemName: AppIcon.Action.clear)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxMuted)
                .help("Clear")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .frame(width: 280)
    }

    private var selectedGraphProjectID: String? {
        store.codeSelectedProjectID ?? store.codeProjects.first?.projectID
    }

    private var selectedProjectDisplayName: String {
        guard let projectID = selectedGraphProjectID else { return "Project" }
        return store.codeProjects.first { $0.projectID == projectID }?.folderDisplayName
            ?? Self.projectDisplayName(for: projectID)
    }

    private static func projectDisplayName(for projectID: String) -> String {
        let trimmedProjectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProjectID.isEmpty else { return "Project" }
        let expandedPath = (trimmedProjectID as NSString).expandingTildeInPath
        let lastPathComponent = (expandedPath as NSString).lastPathComponent
        return lastPathComponent.isEmpty ? trimmedProjectID.memoryAbbreviatingHomeDirectory : lastPathComponent
    }

    private func loadGraphIfNeeded() async {
        guard let projectID = selectedGraphProjectID else { return }
        if store.codeSelectedProjectID == nil {
            store.codeSelectedProjectID = projectID
        }
        if store.graph.knowledgeGraph?.projectID != projectID {
            await store.graph.loadGraph(projectID: projectID)
        }
    }
}
