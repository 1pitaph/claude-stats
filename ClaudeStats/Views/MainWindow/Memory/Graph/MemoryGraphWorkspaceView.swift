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
                    Button(project.projectID) {
                        Task { await store.selectCodeProject(project.projectID) }
                    }
                }
            } label: {
                Label(selectedGraphProjectID?.memoryAbbreviatingHomeDirectory ?? "Project", systemImage: AppIcon.Resource.folder)
            }
            .menuStyle(.button)
            .controlSize(.small)

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
        Picker("Facts", selection: Binding(
            get: { store.graph.factVisibility },
            set: { store.graph.factVisibility = $0 }
        )) {
            ForEach(MemoryKnowledgeFactVisibility.allCases) { visibility in
                Text(visibility.label).tag(visibility)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 124)
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
