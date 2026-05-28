import AppKit
import SwiftUI

private enum SkillsPaneMetrics {
    static let listMinWidth: CGFloat = 320
    static let detailMinWidth: CGFloat = 420
    static let listIdealWidth: CGFloat = 390
    static let detailIdealWidth: CGFloat = 560
    static let stackedEnterWidth: CGFloat = 760
    static let sideBySideEnterWidth: CGFloat = 840
    static let listMinHeight: CGFloat = 220
    static let detailMinHeight: CGFloat = 300
    static let listMaxWidth: CGFloat = 480
    static let sideBySideSplitConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: listMinWidth,
        primaryMaximumPaneLength: listMaxWidth,
        secondaryMinimumPaneLength: detailMinWidth
    )
    static let stackedSplitConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: listMinHeight,
        secondaryMinimumPaneLength: detailMinHeight
    )
}

private enum SkillsWorkspaceLayout {
    case sideBySide
    case stacked
}

struct SkillsWorkspaceView: View {
    @Bindable var store: SkillsStore
    var showsHeader = true

    @Environment(AppEnvironment.self) private var env
    @State private var workspaceLayout: SkillsWorkspaceLayout = .sideBySide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                SkillsHeader(
                    summaryText: store.headerSummaryText,
                    isLoading: store.isScanning || store.isRemoteLoading,
                    selectedTab: store.selectedTab,
                    refreshLocal: refreshLocal,
                    refreshRemote: refreshRemote
                )
                StxRule()
            }
            SkillsWorkspaceBar(
                selectedTab: store.selectedTab,
                layout: workspaceLayout,
                providers: store.snapshot.providers,
                selectedProviderID: $store.selectedProviderID,
                scopeFilter: $store.scopeFilter,
                hasAPIKey: store.hasAPIKey,
                apiKeyDraft: $store.apiKeyDraft,
                remoteError: store.remoteError,
                selectTab: selectTab(_:),
                saveAPIKey: store.saveAPIKey,
                deleteAPIKey: store.deleteAPIKey
            )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            StxRule()
            workspace
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await Task.yield()
            await store.loadIfNeeded(sessions: env.store.sessions)
        }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in
            refreshLocalIfNeeded()
        }
        .onChange(of: store.selectedTab) { _, tab in
            if tab != .installed {
                Task { await store.refreshRemote() }
            }
        }
    }

    private var workspace: some View {
        GeometryReader { proxy in
            workspaceContent
                .onAppear {
                    updateWorkspaceLayout(width: proxy.size.width)
                }
                .onChange(of: proxy.size.width) { _, width in
                    updateWorkspaceLayout(width: width)
                }
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch workspaceLayout {
        case .sideBySide:
            sideBySideWorkspace
        case .stacked:
            stackedWorkspace
        }
    }

    private var sideBySideWorkspace: some View {
        HoverableSplitView(
            axis: .vertical,
            primaryFraction: 0.38,
            configuration: SkillsPaneMetrics.sideBySideSplitConfiguration
        ) {
            listColumn
                .frame(
                    minWidth: 0,
                    idealWidth: SkillsPaneMetrics.listIdealWidth,
                    maxWidth: SkillsPaneMetrics.listMaxWidth,
                    maxHeight: .infinity
                )
        } secondary: {
            detailPane
                .frame(
                    minWidth: 0,
                    idealWidth: SkillsPaneMetrics.detailIdealWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
        }
    }

    private var stackedWorkspace: some View {
        HoverableSplitView(
            axis: .horizontal,
            primaryFraction: 0.42,
            configuration: SkillsPaneMetrics.stackedSplitConfiguration
        ) {
            listColumn
                .frame(minHeight: SkillsPaneMetrics.listMinHeight, maxHeight: .infinity)
        } secondary: {
            detailPane
                .frame(minHeight: SkillsPaneMetrics.detailMinHeight, maxHeight: .infinity)
        }
    }

    private var listColumn: some View {
        SkillsListColumn(
            selectedTab: store.selectedTab,
            searchText: searchTextBinding,
            isLoading: store.isScanning || store.isRemoteLoading,
            localRows: store.visibleLocalRows,
            selectedLocalID: store.selectedLocalGroupID,
            remoteRows: store.discoverRows,
            selectedRemoteID: store.selectedRemoteSkillID,
            curatedOwners: store.curatedOwnerRows,
            hasAPIKey: store.hasAPIKey,
            remoteError: store.remoteError,
            selectLocal: store.selectLocalGroup(id:),
            selectRemote: store.selectRemoteSkill(_:),
            searchRemote: searchRemote
        )
    }

    private var detailPane: some View {
        SkillsDetailPane(
            selectedTab: store.selectedTab,
            selectedDetailTab: $store.selectedDetailTab,
            localDetail: store.selectedLocalDetailModel,
            localMarkdownDocument: store.selectedLocalMarkdownDocument,
            isLocalMarkdownLoading: store.isLocalMarkdownLoading,
            remoteDetail: store.selectedRemoteDetailModel,
            loadLocalMarkdownDocument: store.loadSelectedLocalMarkdownDocument,
            loadRemoteDetail: store.loadRemoteDetail(id:)
        )
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { store.searchText },
            set: { store.searchText = $0 }
        )
    }

    private func selectTab(_ tab: SkillsWorkspaceTab) {
        store.selectedTab = tab
    }

    private func refreshLocal() {
        Task {
            await store.reloadLocal(sessions: env.store.sessions)
        }
    }

    private func refreshRemote() {
        Task {
            await store.refreshRemote()
        }
    }

    private func searchRemote() {
        Task {
            await store.searchOrLoadTrending()
        }
    }

    private func refreshLocalIfNeeded() {
        Task {
            await store.reloadLocalIfProjectRootsChanged(sessions: env.store.sessions)
        }
    }

    private func updateWorkspaceLayout(width: CGFloat) {
        switch workspaceLayout {
        case .sideBySide where width < SkillsPaneMetrics.stackedEnterWidth:
            workspaceLayout = .stacked
        case .stacked where width > SkillsPaneMetrics.sideBySideEnterWidth:
            workspaceLayout = .sideBySide
        default:
            break
        }
    }
}

private struct SkillsHeader: View {
    let summaryText: String
    let isLoading: Bool
    let selectedTab: SkillsWorkspaceTab
    let refreshLocal: () -> Void
    let refreshRemote: () -> Void
    private let horizontalInset: CGFloat = 20

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SKILLS")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Text("Skills")
                    .font(.sora(24, weight: .semibold))
                    .lineLimit(1)
                Text("Browse local SKILL.md directories and inspect skills.sh metadata.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                summaryLabel
                loadingIndicator
                refreshButton
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }

    private var summaryLabel: some View {
        Text(summaryText)
            .font(.sora(11))
            .foregroundStyle(Color.stxMuted)
            .lineLimit(1)
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
        }
    }

    private var refreshButton: some View {
        Button {
            if selectedTab == .installed {
                refreshLocal()
            } else {
                refreshRemote()
            }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .controlSize(.small)
        .disabled(isLoading)
        .help("Refresh current Skills view")
    }
}

private struct SkillsWorkspaceBar: View {
    let selectedTab: SkillsWorkspaceTab
    let layout: SkillsWorkspaceLayout
    let providers: [SkillProviderDefinition]
    @Binding var selectedProviderID: String?
    @Binding var scopeFilter: SkillScopeFilter
    let hasAPIKey: Bool
    @Binding var apiKeyDraft: String
    let remoteError: String?
    let selectTab: (SkillsWorkspaceTab) -> Void
    let saveAPIKey: () -> Void
    let deleteAPIKey: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(SkillsWorkspaceTab.allCases) { tab in
                    Button {
                        selectTab(tab)
                    } label: {
                        Label(tab.title, systemImage: tab.symbol)
                            .font(.sora(11, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundStyle(selectedTab == tab ? Color.stxAccent : Color.stxMuted)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color.stxAccent.opacity(0.13))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
            }

            Spacer(minLength: 8)
            SkillsWorkspaceControls(
                selectedTab: selectedTab,
                layout: layout,
                providers: providers,
                selectedProviderID: $selectedProviderID,
                scopeFilter: $scopeFilter,
                hasAPIKey: hasAPIKey,
                apiKeyDraft: $apiKeyDraft,
                remoteError: remoteError,
                saveAPIKey: saveAPIKey,
                deleteAPIKey: deleteAPIKey
            )
        }
    }
}

private struct SkillsWorkspaceControls: View {
    let selectedTab: SkillsWorkspaceTab
    let layout: SkillsWorkspaceLayout
    let providers: [SkillProviderDefinition]
    @Binding var selectedProviderID: String?
    @Binding var scopeFilter: SkillScopeFilter
    let hasAPIKey: Bool
    @Binding var apiKeyDraft: String
    let remoteError: String?
    let saveAPIKey: () -> Void
    let deleteAPIKey: () -> Void
    @State private var showingFilters = false

    @ViewBuilder
    var body: some View {
        switch layout {
        case .sideBySide:
            inlineControls
        case .stacked:
            compactControls
        }
    }

    @ViewBuilder
    private var inlineControls: some View {
        switch selectedTab {
        case .installed:
            HStack(spacing: 8) {
                SkillsProviderPicker(providers: providers, selectedProviderID: $selectedProviderID)
                    .frame(width: 160)
                SkillsScopePicker(scopeFilter: $scopeFilter)
                    .frame(width: 126)
            }
        case .discover, .curated:
            SkillsAPIKeyButton(
                hasAPIKey: hasAPIKey,
                apiKeyDraft: $apiKeyDraft,
                remoteError: remoteError,
                showLabel: true,
                saveAPIKey: saveAPIKey,
                deleteAPIKey: deleteAPIKey
            )
        }
    }

    @ViewBuilder
    private var compactControls: some View {
        switch selectedTab {
        case .installed:
            Button {
                showingFilters.toggle()
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .controlSize(.small)
            .help("Filters")
            .popover(isPresented: $showingFilters, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("FILTERS")
                        .font(.sora(9, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(Color.stxMuted)
                    SkillsProviderPicker(providers: providers, selectedProviderID: $selectedProviderID)
                    SkillsScopePicker(scopeFilter: $scopeFilter)
                }
                .padding(14)
                .frame(width: 240)
            }
        case .discover, .curated:
            SkillsAPIKeyButton(
                hasAPIKey: hasAPIKey,
                apiKeyDraft: $apiKeyDraft,
                remoteError: remoteError,
                showLabel: false,
                saveAPIKey: saveAPIKey,
                deleteAPIKey: deleteAPIKey
            )
        }
    }
}

private struct SkillsProviderPicker: View {
    let providers: [SkillProviderDefinition]
    @Binding var selectedProviderID: String?

    var body: some View {
        AppSelect(
            .localized("Provider"),
            selection: providerBinding,
            options: [AppSelectOption(value: "all", title: .localized("All providers"), systemImage: "square.grid.2x2")]
                + providers.map { provider in
                    AppSelectOption(value: provider.id, title: .verbatim(provider.displayName), systemImage: provider.symbol)
                },
            width: 160,
            size: .small
        )
    }

    private var providerBinding: Binding<String> {
        Binding(
            get: { selectedProviderID ?? "all" },
            set: { selectedProviderID = $0 == "all" ? nil : $0 }
        )
    }
}

private struct SkillsScopePicker: View {
    @Binding var scopeFilter: SkillScopeFilter

    var body: some View {
        AppSelect(
            .localized("Scope"),
            selection: $scopeFilter,
            options: SkillScopeFilter.allCases.map { scope in
                AppSelectOption(value: scope, title: .localized(scope.title))
            },
            width: 126,
            size: .small
        )
    }
}

private struct SkillsAPIKeyButton: View {
    let hasAPIKey: Bool
    @Binding var apiKeyDraft: String
    let remoteError: String?
    let showLabel: Bool
    let saveAPIKey: () -> Void
    let deleteAPIKey: () -> Void
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            if showLabel {
                Label(hasAPIKey ? "API key saved" : "Set API key", systemImage: hasAPIKey ? "key.fill" : "key")
            } else {
                Image(systemName: hasAPIKey ? "key.fill" : "key")
            }
        }
        .controlSize(.small)
        .foregroundStyle(hasAPIKey ? Color.stxAccent : Color.stxMuted)
        .help(hasAPIKey ? "skills.sh API key saved" : "Set skills.sh API key")
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            SkillsAPIKeyPopover(
                hasAPIKey: hasAPIKey,
                apiKeyDraft: $apiKeyDraft,
                remoteError: remoteError,
                saveAPIKey: saveAPIKey,
                deleteAPIKey: deleteAPIKey
            )
                .padding(14)
                .frame(width: 300)
        }
    }
}

private struct SkillsAPIKeyPopover: View {
    let hasAPIKey: Bool
    @Binding var apiKeyDraft: String
    let remoteError: String?
    let saveAPIKey: () -> Void
    let deleteAPIKey: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: hasAPIKey ? "key.fill" : "key")
                    .foregroundStyle(hasAPIKey ? Color.stxAccent : Color.stxMuted)
                Text(hasAPIKey ? "API key saved" : "skills.sh API key")
                    .font(.sora(12, weight: .semibold))
            }

            SecureField("sk_live_...", text: $apiKeyDraft)
                .textFieldStyle(.roundedBorder)
                .font(.sora(11))
                .onSubmit { saveAPIKey() }

            HStack(spacing: 8) {
                Button("Save") {
                    saveAPIKey()
                }
                .controlSize(.small)
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if hasAPIKey {
                    Button("Clear") {
                        deleteAPIKey()
                    }
                    .controlSize(.small)
                }
            }

            if let remoteError {
                Text(remoteError)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Required for Discover and Curated.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
        }
    }
}

private struct SkillsListColumn: View {
    let selectedTab: SkillsWorkspaceTab
    @Binding var searchText: String
    let isLoading: Bool
    let localRows: [LocalSkillRowModel]
    let selectedLocalID: String?
    let remoteRows: [RemoteSkillRowModel]
    let selectedRemoteID: String?
    let curatedOwners: [CuratedSkillOwnerRowModel]
    let hasAPIKey: Bool
    let remoteError: String?
    let selectLocal: (String) -> Void
    let selectRemote: (RemoteSkillSummary) -> Void
    let searchRemote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            listHeader
                .padding(10)
            StxRule()
            content
        }
        .background(Color.primary.opacity(0.025))
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(selectedTab.title)
                    .font(.sora(14, weight: .semibold))
                Spacer(minLength: 8)
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.stxMuted)
                TextField(searchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.sora(11))
                    .onSubmit {
                        if selectedTab == .discover {
                            searchRemote()
                        }
                    }
                if selectedTab == .discover {
                    Button {
                        searchRemote()
                    } label: {
                        Image(systemName: "arrow.right")
                    }
                    .buttonStyle(.plain)
                    .help("Search skills.sh")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .installed:
            SkillsInstalledList(
                rows: localRows,
                selectedID: selectedLocalID,
                isScanning: isLoading
            ) { id in
                selectLocal(id)
            }
        case .discover:
            SkillsRemoteList(
                rows: remoteRows,
                selectedID: selectedRemoteID,
                hasAPIKey: hasAPIKey,
                remoteError: remoteError,
                missingKeyMessage: "Save a skills.sh API key from the top-right key control to browse the market.",
                emptyMessage: "Search skills.sh or refresh trending results."
            ) { skill in
                selectRemote(skill)
            }
        case .curated:
            SkillsCuratedList(
                owners: curatedOwners,
                selectedID: selectedRemoteID,
                hasAPIKey: hasAPIKey,
                remoteError: remoteError
            ) { skill in
                selectRemote(skill)
            }
        }
    }

    private var searchPlaceholder: String {
        switch selectedTab {
        case .installed: "Search local skills"
        case .discover: "Search skills.sh"
        case .curated: "Filter curated skills"
        }
    }
}

private struct SkillsInstalledList: View {
    let rows: [LocalSkillRowModel]
    let selectedID: String?
    let isScanning: Bool
    let select: (String) -> Void

    var body: some View {
        AppScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if rows.isEmpty {
                    SkillsEmptyState(
                        symbol: "sparkles",
                        title: isScanning ? "Scanning..." : "No skills found",
                        message: "Refresh or adjust filters to inspect local SKILL.md directories."
                    )
                } else {
                    ForEach(rows) { row in
                        SkillsLocalRow(
                            row: row,
                            isSelected: selectedID == row.id
                        ) {
                            select(row.id)
                        }
                    }
                }
            }
            .padding(10)
        }
    }
}

private struct SkillsRemoteList: View {
    let rows: [RemoteSkillRowModel]
    let selectedID: String?
    let hasAPIKey: Bool
    let remoteError: String?
    let missingKeyMessage: String
    let emptyMessage: String
    let select: (RemoteSkillSummary) -> Void

    var body: some View {
        AppScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if !hasAPIKey {
                    SkillsEmptyState(
                        symbol: "key",
                        title: "API key required",
                        message: missingKeyMessage
                    )
                } else if let remoteError {
                    SkillsEmptyState(symbol: "exclamationmark.triangle", title: "Could not load skills", message: remoteError)
                } else if rows.isEmpty {
                    SkillsEmptyState(symbol: "magnifyingglass", title: "No remote skills", message: emptyMessage)
                } else {
                    ForEach(rows) { row in
                        SkillsRemoteRow(
                            skill: row.skill,
                            state: row.installState,
                            isSelected: selectedID == row.skill.id
                        ) {
                            select(row.skill)
                        }
                    }
                }
            }
            .padding(10)
        }
    }
}

private struct SkillsCuratedList: View {
    let owners: [CuratedSkillOwnerRowModel]
    let selectedID: String?
    let hasAPIKey: Bool
    let remoteError: String?
    let select: (RemoteSkillSummary) -> Void

    var body: some View {
        AppScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !hasAPIKey {
                    SkillsEmptyState(
                        symbol: "key",
                        title: "API key required",
                        message: "Save a skills.sh API key from the top-right key control to browse curated skills."
                    )
                } else if let remoteError {
                    SkillsEmptyState(symbol: "exclamationmark.triangle", title: "Could not load curated skills", message: remoteError)
                } else if owners.isEmpty {
                    SkillsEmptyState(symbol: "sparkles", title: "No curated skills", message: "Refresh to load official skills from skills.sh.")
                } else {
                    ForEach(owners) { owner in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(owner.owner)
                                    .font(.sora(11, weight: .semibold))
                                if let total = owner.totalInstalls {
                                    Text("\(total) installs")
                                        .font(.sora(9))
                                        .foregroundStyle(Color.stxMuted)
                                }
                            }
                            ForEach(owner.skills) { skill in
                                SkillsRemoteRow(
                                    skill: skill.skill,
                                    state: skill.installState,
                                    isSelected: selectedID == skill.skill.id
                                ) {
                                    select(skill.skill)
                                }
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
    }
}

private struct SkillsDetailPane: View {
    let selectedTab: SkillsWorkspaceTab
    @Binding var selectedDetailTab: SkillsDetailTab
    let localDetail: LocalSkillDetailModel?
    let localMarkdownDocument: SkillMarkdownDocument?
    let isLocalMarkdownLoading: Bool
    let remoteDetail: RemoteSkillDetailModel?
    let loadLocalMarkdownDocument: () async -> Void
    let loadRemoteDetail: (String) async -> Void

    var body: some View {
        Group {
            detailContent
        }
        .background(Color.primary.opacity(0.015))
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .installed:
            if let detail = localDetail {
                SkillsInspectorShell(
                    selection: $selectedDetailTab,
                    symbol: "sparkles",
                    title: detail.title,
                    subtitle: detail.subtitle
                ) {
                    if let actions = detail.actions {
                        SkillsLocalActions(actions: actions)
                    }
                } content: {
                    SkillsLocalDetail(
                        selectedTab: selectedDetailTab,
                        detail: detail,
                        markdownDocument: localMarkdownDocument,
                        isMarkdownLoading: isLocalMarkdownLoading,
                        loadMarkdownDocument: loadLocalMarkdownDocument
                    )
                }
            } else {
                emptyInspector
            }
        case .discover, .curated:
            if let detail = remoteDetail {
                SkillsInspectorShell(
                    selection: $selectedDetailTab,
                    symbol: "bag",
                    title: detail.title,
                    subtitle: detail.subtitle
                ) {
                    SkillsRemoteActions(actions: detail.actions)
                } content: {
                    SkillsRemoteDetail(selectedTab: selectedDetailTab, detail: detail)
                }
                .task(id: detail.id) {
                    await loadRemoteDetail(detail.id)
                }
            } else {
                emptyInspector
            }
        }
    }

    private var emptyInspector: some View {
        SkillsInspectorShell(
            selection: $selectedDetailTab,
            symbol: "sidebar.right",
            title: "Inspector",
            subtitle: "Select a skill to inspect metadata, files, and SKILL.md.",
            showsTabs: false
        ) {
            EmptyView()
        } content: {
            SkillsEmptyDetail()
        }
    }
}

private struct SkillsInspectorShell<Actions: View, Content: View>: View {
    @Binding var selection: SkillsDetailTab
    let symbol: String
    let title: String
    let subtitle: String
    let showsTabs: Bool
    let actions: Actions
    let content: Content

    init(
        selection: Binding<SkillsDetailTab>,
        symbol: String,
        title: String,
        subtitle: String,
        showsTabs: Bool = true,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content
    ) {
        self._selection = selection
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.showsTabs = showsTabs
        self.actions = actions()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            if showsTabs {
                SkillsDetailTabs(selection: $selection)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                StxRule()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.stxAccent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sora(12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            actions
        }
        .frame(minHeight: 34)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct SkillsLocalDetail: View {
    let selectedTab: SkillsDetailTab
    let detail: LocalSkillDetailModel
    let markdownDocument: SkillMarkdownDocument?
    let isMarkdownLoading: Bool
    let loadMarkdownDocument: () async -> Void

    var body: some View {
        detailBody
    }

    @ViewBuilder
    private var detailBody: some View {
        switch selectedTab {
        case .overview:
            localOverview
        case .skill:
            if let document = markdownDocument {
                SkillMarkdownViewer(document: document)
                    .equatable()
            } else {
                SkillsLoadingState(message: isMarkdownLoading ? "Loading SKILL.md..." : "No SKILL.md snapshot available.")
                    .task(id: detail.id) {
                        await loadMarkdownDocument()
                    }
            }
        case .files:
            SkillFilesList(files: detail.files)
        case .market:
            SkillsEmptyState(
                symbol: "bag",
                title: "Market comparison",
                message: "Select a skills.sh result in Discover or Curated to inspect remote metadata and audits."
            )
            .padding(16)
        }
    }

    private var localOverview: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    SkillsMetricCard(title: "Copies", value: "\(detail.copyCount)")
                    SkillsMetricCard(title: "Files", value: "\(detail.fileCount)")
                    SkillsMetricCard(title: "Tokens", value: "\(detail.tokenCount)")
                }

                if !detail.primaryFacts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Primary Copy")
                            .font(.sora(12, weight: .semibold))
                        ForEach(detail.primaryFacts) { fact in
                            SkillsFactRow(fact.label, value: fact.value)
                        }
                    }
                    .mainWindowPanel(padding: 12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Installed Copies")
                        .font(.sora(12, weight: .semibold))
                    ForEach(detail.installedCopies) { copy in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: copy.providerSymbol)
                                .foregroundStyle(Color.stxMuted)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(copy.providerName)
                                        .font(.sora(11, weight: .semibold))
                                    SkillsBadge(text: copy.scopeName, color: Color.stxMuted)
                                    if copy.isSymlink {
                                        SkillsBadge(text: "Symlink", color: Color.stxAccent)
                                    }
                                }
                                Text(copy.displayPath)
                                    .font(.sora(9))
                                    .foregroundStyle(Color.stxMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(9)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                .mainWindowPanel(padding: 12)
            }
            .padding(14)
        }
    }
}

private struct SkillsRemoteDetail: View {
    let selectedTab: SkillsDetailTab
    let detail: RemoteSkillDetailModel

    var body: some View {
        detailBody
    }

    @ViewBuilder
    private var detailBody: some View {
        switch selectedTab {
        case .overview:
            remoteOverview
        case .skill:
            if let document = detail.markdownDocument {
                SkillMarkdownViewer(document: document)
                    .equatable()
            } else {
                SkillsLoadingState(message: detail.isDetailLoading ? "Loading SKILL.md..." : "No SKILL.md snapshot available.")
            }
        case .files:
            SkillFilesList(files: detail.files)
        case .market:
            auditView
        }
    }

    private var remoteOverview: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    SkillsMetricCard(title: "Installs", value: detail.installsText)
                    SkillsMetricCard(title: "Files", value: "\(detail.fileCount)")
                    SkillsMetricCard(title: "State", value: detail.installStateTitle)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Market Details")
                        .font(.sora(12, weight: .semibold))
                    ForEach(detail.facts) { fact in
                        SkillsFactRow(fact.label, value: fact.value)
                    }
                    if let command = detail.installCommand {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Install Command")
                                .font(.sora(9, weight: .semibold))
                                .foregroundStyle(Color.stxMuted)
                            Text(command)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .mainWindowPanel(padding: 12)
            }
            .padding(14)
        }
    }

    private var auditView: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !detail.audits.isEmpty {
                    ForEach(detail.audits) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(entry.provider)
                                    .font(.sora(12, weight: .semibold))
                                SkillsBadge(text: entry.status.uppercased(), color: auditColor(entry.status))
                                if let risk = entry.riskLevel {
                                    SkillsBadge(text: risk, color: auditColor(entry.status))
                                }
                                Spacer(minLength: 0)
                            }
                            if let summary = entry.summary {
                                Text(summary)
                                    .font(.sora(11))
                                    .foregroundStyle(Color.stxMuted)
                            }
                            if let auditedAtText = entry.auditedAtText {
                                Text(auditedAtText)
                                    .font(.sora(9))
                                    .foregroundStyle(Color.stxMuted)
                            }
                        }
                        .mainWindowPanel(padding: 12)
                    }
                } else {
                    SkillsEmptyState(
                        symbol: "checkmark.shield",
                        title: "No audit results",
                        message: "skills.sh returns audits after partner scans are available."
                    )
                }
            }
            .padding(14)
        }
    }

    private func auditColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "pass": Color.stxAccent
        case "warn": Color(red: 0.92, green: 0.58, blue: 0.16)
        case "fail": Color(red: 0.85, green: 0.22, blue: 0.18)
        default: Color.stxMuted
        }
    }
}

private struct SkillsLocalActions: View {
    let actions: LocalSkillActionModel

    var body: some View {
        actionButtons
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            SkillsToolbarButton("Copy Path", systemImage: "doc.on.doc", showLabel: false) {
                SkillsClipboard.copy(actions.folderPath)
            }
            SkillsToolbarButton("Reveal", systemImage: "finder", showLabel: false) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: actions.skillMarkdownPath)])
            }
            SkillsToolbarButton("Open", systemImage: "arrow.up.right.square", showLabel: false) {
                NSWorkspace.shared.open(URL(fileURLWithPath: actions.skillMarkdownPath))
            }
        }
    }
}

private struct SkillsRemoteActions: View {
    let actions: RemoteSkillActionModel

    var body: some View {
        actionButtons
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            SkillsToolbarButton("Copy Install", systemImage: "doc.on.doc", showLabel: false, disabled: actions.installCommand == nil) {
                if let command = actions.installCommand {
                    SkillsClipboard.copy(command)
                }
            }
            SkillsToolbarButton("Open", systemImage: "arrow.up.right.square", showLabel: false, disabled: remoteURL == nil) {
                if let remoteURL {
                    NSWorkspace.shared.open(remoteURL)
                }
            }
        }
    }

    private var remoteURL: URL? {
        actions.remoteURLString.flatMap { URL(string: $0) }
    }
}

private struct SkillsLocalRow: View {
    let row: LocalSkillRowModel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SkillsLocalRowContent(row: row, isSelected: isSelected)
                .equatable()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.name), \(row.copyCount) installed copies")
    }
}

private struct SkillsLocalRowContent: View, Equatable {
    let row: LocalSkillRowModel
    let isSelected: Bool

    nonisolated static func == (lhs: SkillsLocalRowContent, rhs: SkillsLocalRowContent) -> Bool {
        lhs.row == rhs.row && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(row.name)
                    .font(.sora(12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if row.copyCount > 1 {
                    SkillsBadge(text: "\(row.copyCount)", color: Color.stxAccent)
                }
            }
            Text(row.description)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(2)
            HStack(spacing: 5) {
                ForEach(row.providerBadges, id: \.self) { provider in
                    SkillsBadge(text: provider, color: Color.stxMuted)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.stxAccent.opacity(0.11) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? Color.stxAccent.opacity(0.32) : Color.clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
}

private struct SkillsRemoteRow: View {
    let skill: RemoteSkillSummary
    let state: SkillInstallState
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SkillsRemoteRowContent(skill: skill, state: state, isSelected: isSelected)
                .equatable()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(skill.name), \(state.title)")
    }
}

private struct SkillsRemoteRowContent: View, Equatable {
    let skill: RemoteSkillSummary
    let state: SkillInstallState
    let isSelected: Bool

    nonisolated static func == (lhs: SkillsRemoteRowContent, rhs: SkillsRemoteRowContent) -> Bool {
        lhs.skill == rhs.skill && lhs.state == rhs.state && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(skill.name)
                    .font(.sora(12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                SkillsBadge(text: state.title, color: stateColor)
            }
            Text(skill.displaySource)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                if let installs = skill.installs {
                    Label("\(installs)", systemImage: "arrow.down.circle")
                }
                if skill.isDuplicate {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
            }
            .font(.sora(9))
            .foregroundStyle(Color.stxMuted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.stxAccent.opacity(0.11) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? Color.stxAccent.opacity(0.32) : Color.clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    private var stateColor: Color {
        switch state {
        case .installed: Color.stxAccent
        case .possiblyInstalled, .outOfDate: Color(red: 0.92, green: 0.58, blue: 0.16)
        case .notInstalled: Color.stxMuted
        }
    }
}

private struct SkillsDetailTabs: View {
    @Binding var selection: SkillsDetailTab

    var body: some View {
        HStack(spacing: 14) {
            ForEach(SkillsDetailTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.title)
                        .font(.sora(11, weight: selection == tab ? .semibold : .medium))
                        .foregroundStyle(selection == tab ? Color.stxAccent : Color.stxMuted)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

private struct SkillMarkdownViewer: View, Equatable {
    let document: SkillMarkdownDocument

    nonisolated static func == (lhs: SkillMarkdownViewer, rhs: SkillMarkdownViewer) -> Bool {
        lhs.document.id == rhs.document.id && lhs.document.contentHash == rhs.document.contentHash
    }

    var body: some View {
        SkillMarkdownTextView(document: document)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.03))
    }
}

private struct SkillMarkdownTextView: NSViewRepresentable {
    let document: SkillMarkdownDocument

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.drawsBackground = false
        textView.allowsUndo = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.font = Self.editorFont
        textView.textColor = .labelColor
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        AppScrollbars.configure(scrollView)
        scrollView.documentView = textView
        context.coordinator.apply(document, to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        AppScrollbars.configure(scrollView)
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.apply(document, to: textView)
    }

    private static var editorFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }

    @MainActor
    final class Coordinator {
        private var appliedID: String?
        private var appliedContentHash: String?

        func apply(_ document: SkillMarkdownDocument, to textView: NSTextView) {
            guard appliedID != document.id || appliedContentHash != document.contentHash else { return }
            textView.string = document.text
            textView.font = SkillMarkdownTextView.editorFont
            textView.textColor = .labelColor
            textView.typingAttributes = [
                .font: SkillMarkdownTextView.editorFont,
                .foregroundColor: NSColor.labelColor,
            ]
            appliedID = document.id
            appliedContentHash = document.contentHash
        }
    }
}

private struct SkillFilesList: View {
    let files: [SkillFileRowModel]

    var body: some View {
        AppScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if files.isEmpty {
                    SkillsEmptyState(symbol: "folder", title: "No file snapshot", message: "No supporting files are available for this skill.")
                } else {
                    ForEach(files) { file in
                        HStack(spacing: 9) {
                            Image(systemName: file.path == "SKILL.md" ? "doc.text" : "doc")
                                .foregroundStyle(Color.stxMuted)
                                .frame(width: 18)
                            Text(file.path)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            if let byteCountText = file.byteCountText {
                                Text(byteCountText)
                                    .font(.sora(9))
                                    .foregroundStyle(Color.stxMuted)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(14)
        }
    }
}

private struct SkillsFactRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.sora(9, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.sora(10))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct SkillsMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.sora(8, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct SkillsBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.sora(8, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct SkillsMiniMetric: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.sora(10, weight: .semibold))
            Text(label)
                .font(.sora(10))
        }
    }
}

private struct SkillsToolbarButton: View {
    let title: String
    let systemImage: String
    let showLabel: Bool
    let disabled: Bool
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String,
        showLabel: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.showLabel = showLabel
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if showLabel {
                Label(title, systemImage: systemImage)
            } else {
                Image(systemName: systemImage)
            }
        }
        .controlSize(.small)
        .help(title)
        .disabled(disabled)
    }
}

private struct SkillsEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.stxMuted)
            Text(title)
                .font(.sora(13, weight: .semibold))
            Text(message)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SkillsLoadingState: View {
    let message: String

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SkillsEmptyDetail: View {
    var body: some View {
        SkillsEmptyState(
            symbol: "sparkles",
            title: "No skill selected",
            message: "Choose a local or market skill to inspect its SKILL.md, files, and metadata."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }
}

private enum SkillsClipboard {
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

#if DEBUG
#Preview("Skills") {
    SkillsWorkspaceView(store: AppEnvironment.preview().skills)
        .environment(AppEnvironment.preview())
        .frame(width: 1160, height: 760)
}
#endif
