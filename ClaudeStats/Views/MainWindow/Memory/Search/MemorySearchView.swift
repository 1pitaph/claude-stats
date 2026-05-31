import SwiftUI

struct MemorySearchView: View {
    @Bindable var store: MemoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            StxRule()
            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    traceHeader
                    canonicalSection
                    graphSection
                    sourceSection
                    contextPreview
                    tracePreview
                }
                .padding(18)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: AppIcon.Action.search)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.stxMuted)
                TextField("Search memory", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.sora(12))
                    .onSubmit { search() }
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                        store.clearSearchResults()
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

            Menu {
                Button("All Projects") {
                    store.codeSelectedProjectID = nil
                }
                Divider()
                ForEach(store.codeProjects) { project in
                    Button(project.projectID) {
                        Task { await store.selectCodeProject(project.projectID) }
                    }
                }
            } label: {
                Label(projectLabel, systemImage: AppIcon.Resource.folder)
            }
            .menuStyle(.button)
            .controlSize(.small)

            Button {
                search()
            } label: {
                Label("Search", systemImage: AppIcon.Navigation.forward)
            }
            .controlSize(.small)
            .disabled(store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSearching)

            Button {
                Task { await store.loadContextPack() }
            } label: {
                Label("Context", systemImage: AppIcon.Resource.transcriptSearch)
            }
            .controlSize(.small)
            .disabled((store.contextText.isEmpty && store.searchText.isEmpty) || store.isCodeMemoryLoading)

            Spacer(minLength: 8)
        }
        .padding(14)
    }

    @ViewBuilder
    private var traceHeader: some View {
        if let traceID = store.codeLastTraceID {
            HStack(spacing: 10) {
                Image(systemName: AppIcon.Resource.clipboardList)
                    .foregroundStyle(Color.stxAccent)
                Text(traceID)
                    .font(.sora(10).monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button {
                    Task { await store.loadLastTrace() }
                } label: {
                    Label("Trace", systemImage: AppIcon.Navigation.forward)
                }
                .controlSize(.small)
                MemoryCopyButton(value: traceID, label: "Copy Trace", systemImage: AppIcon.Resource.link)
            }
            .padding(10)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var canonicalSection: some View {
        MemorySection(title: "Canonical Memories", count: store.codeSearchResults.count, symbol: AppIcon.Git.commitCheck) {
            if store.codeSearchResults.isEmpty {
                MemoryEmptyState(
                    title: store.searchText.isEmpty ? "Search memory" : "No canonical matches",
                    message: store.codeHealth == nil ? "memoryd offline" : "Active canonical memories only",
                    symbol: AppIcon.Action.search
                )
                .frame(minHeight: 190)
            } else {
                ForEach(store.codeSearchResults) { result in
                    MemorySearchResultRow(result: result)
                }
            }
        }
    }

    private var graphSection: some View {
        MemorySection(title: "Graph Facts", count: store.codeGraphResults.count, symbol: AppIcon.Network.webSocket) {
            if store.codeGraphResults.isEmpty {
                MemoryMutedLine(text: "No graph facts returned.")
                    .padding(.vertical, 8)
            } else {
                ForEach(store.codeGraphResults) { fact in
                    MemoryGraphFactRow(fact: fact) {
                        Task { await store.promoteGraphFact(fact) }
                    }
                }
            }
        }
    }

    private var sourceSection: some View {
        MemorySection(title: "Sources", count: store.codeSourceResults.count, symbol: AppIcon.Resource.transcriptSearch) {
            if store.codeSourceResults.isEmpty {
                MemoryMutedLine(text: "No source matches.")
                    .padding(.vertical, 8)
            } else {
                ForEach(store.codeSourceResults) { source in
                    MemoryEpisodeRow(episode: source)
                }
            }
        }
    }

    @ViewBuilder
    private var contextPreview: some View {
        if let pack = store.codeContextPack {
            MemorySection(title: "Context Preview", count: contextCount(pack), symbol: AppIcon.Resource.documentText) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    contextGroup("Rules", pack.context.rules)
                    contextGroup("Facts", pack.context.facts)
                    contextGroup("Risks", pack.context.risks)
                    contextGroup("Commands", pack.context.commands)
                    contextGroup("Decisions", pack.context.decisions)
                    if !pack.graphFacts.isEmpty {
                        MemorySubsectionHeader(title: "Graph Facts", count: pack.graphFacts.count)
                        ForEach(pack.graphFacts) { fact in
                            MemoryGraphFactRow(fact: fact) {
                                Task { await store.promoteGraphFact(fact) }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tracePreview: some View {
        if let trace = store.codeTrace {
            MemorySection(title: "Trace", count: trace.memoryUsage.count, symbol: AppIcon.Resource.clipboardList) {
                VStack(alignment: .leading, spacing: 8) {
                    traceFact("run", trace.runID)
                    traceFact("project", trace.projectID ?? "-")
                    ForEach(trace.memoryUsage) { usage in
                        HStack(spacing: 8) {
                            Text("#\(usage.rank)")
                                .font(.sora(10).monospacedDigit())
                                .foregroundStyle(Color.stxAccent)
                                .frame(width: 36, alignment: .leading)
                            Text(usage.usageKind)
                                .font(.sora(10).monospaced())
                                .foregroundStyle(Color.stxMuted)
                                .frame(width: 84, alignment: .leading)
                            Text(usage.memoryID)
                                .font(.sora(10).monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(String(format: "%.2f", usage.score))
                                .font(.sora(10).monospacedDigit())
                                .foregroundStyle(Color.stxMuted)
                        }
                    }
                }
            }
        }
    }

    private var projectLabel: String {
        store.codeSelectedProjectID?.memoryAbbreviatingHomeDirectory ?? "All Projects"
    }

    private func search() {
        Task { await store.performSearch() }
    }

    private func contextCount(_ pack: CodeMemoryContextPack) -> Int {
        pack.context.rules.count
            + pack.context.facts.count
            + pack.context.risks.count
            + pack.context.commands.count
            + pack.context.decisions.count
            + pack.graphFacts.count
    }

    private func contextGroup(_ title: String, _ memories: [CodeMemoryMemory]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MemorySubsectionHeader(title: title, count: memories.count)
            if memories.isEmpty {
                MemoryMutedLine(text: "None")
            } else {
                ForEach(memories) { memory in
                    MemoryFactRow(memory: memory)
                }
            }
        }
    }

    private func traceFact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.sora(10).monospaced())
                .foregroundStyle(Color.stxMuted)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.sora(10).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct MemorySection<Content: View>: View {
    let title: String
    let count: Int?
    let symbol: String
    let content: Content

    init(title: String, count: Int? = nil, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.stxAccent)
                    .frame(width: 18)
                Text(title)
                    .font(.sora(13, weight: .semibold))
                if let count {
                    AIConfigsBadge(text: "\(count)", color: Color.stxMuted)
                }
                Spacer(minLength: 0)
            }
            content
        }
    }
}

struct MemorySubsectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.sora(12, weight: .semibold))
            AIConfigsBadge(text: "\(count)", color: Color.stxMuted)
            Spacer(minLength: 0)
        }
    }
}

struct MemoryMutedLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.sora(11))
            .foregroundStyle(Color.stxMuted)
    }
}

struct MemoryEmptyState: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        AIConfigsEmptyState(title: title, message: message, symbol: symbol)
    }
}
