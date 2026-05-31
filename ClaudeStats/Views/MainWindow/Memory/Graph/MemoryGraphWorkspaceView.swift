import SwiftUI

struct MemoryGraphWorkspaceView: View {
    @Bindable var store: MemoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            StxRule()
            MemoryGraphChangesView(store: store)
        }
        .task(id: store.codeSelectedProjectID) {
            await loadChangesIfNeeded()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            searchField
            displayModePicker
            densityPicker

            Menu {
                ForEach(store.codeProjects) { project in
                    Button(project.projectID) {
                        Task { await store.selectCodeProject(project.projectID) }
                    }
                }
            } label: {
                let projectID = store.codeSelectedProjectID ?? store.codeProjects.first?.projectID
                Label(projectID?.memoryAbbreviatingHomeDirectory ?? "Project", systemImage: AppIcon.Resource.folder)
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
                Task { await store.graph.loadChanges(projectID: store.codeSelectedProjectID ?? store.codeProjects.first?.projectID) }
            } label: {
                Label("Refresh", systemImage: AppIcon.Action.refresh)
            }
            .controlSize(.small)
            .disabled((store.codeSelectedProjectID ?? store.codeProjects.first?.projectID) == nil || store.graph.isLoadingChanges)
        }
        .padding(14)
    }

    private var displayModePicker: some View {
        Picker("Mode", selection: Binding(
            get: { store.graph.displayMode },
            set: { store.graph.displayMode = $0 }
        )) {
            ForEach(MemoryGraphDisplayMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 220)
        .help("Graph Reading Mode")
    }

    private var densityPicker: some View {
        Picker("Density", selection: Binding(
            get: { store.graph.density },
            set: { store.graph.density = $0 }
        )) {
            ForEach(MemoryGraphDensity.allCases) { density in
                Text(density.label).tag(density)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 132)
        .help("Graph Density")
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: AppIcon.Action.search)
                .font(.system(size: 12))
                .foregroundStyle(Color.stxMuted)
            TextField("Event, field, source, or memory", text: Binding(
                get: { store.graph.changeSearchText },
                set: { store.graph.changeSearchText = $0 }
            ))
                .textFieldStyle(.plain)
                .font(.sora(12))
            if !store.graph.changeSearchText.isEmpty {
                Button {
                    store.graph.changeSearchText = ""
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

    private func loadChangesIfNeeded() async {
        guard let projectID = store.codeSelectedProjectID ?? store.codeProjects.first?.projectID else { return }
        if store.codeSelectedProjectID == nil {
            store.codeSelectedProjectID = projectID
        }
        if store.graph.changeGraph?.projectID != projectID {
            await store.graph.loadChanges(projectID: projectID)
        }
    }
}
