import AppKit
import SwiftUI

struct ConfigurationsView: View {
    var showsHeader = true

    @Environment(AppEnvironment.self) private var env

    private let workspaceMaxWidth: CGFloat = 980
    private let railColumnWidth: CGFloat = 78
    private let providerColumnWidth: CGFloat = 330
    private let columnSpacing: CGFloat = 14
    private let railMinimumHeight: CGFloat = 144
    private let editorModeContentHeight: CGFloat = 176

    @State private var editorMode: APIProviderEditorMode = .fields
    @State private var cursorLine = 1
    @State private var cursorColumn = 1
    @State private var showEnvironmentCleanupConfirmation = false

    var body: some View {
        @Bindable var vm = env.apiProviders
        let environmentVM = env.cliEnvironment

        CenteredPaneContainer(maxWidth: workspaceMaxWidth, topPadding: showsHeader ? 36 : 18) {
            VStack(alignment: .leading, spacing: 18) {
                if showsHeader {
                    header(vm: vm)
                }
                WorkspaceColumnsLayout(
                    railWidth: railColumnWidth,
                    listWidth: providerColumnWidth,
                    detailMinWidth: providerColumnWidth,
                    spacing: columnSpacing
                ) {
                    cliRail(vm: vm)
                    providersColumn(vm: vm)
                    editorColumn(vm: vm)
                }
                .frame(maxWidth: .infinity, alignment: .top)

                CLIEnvironmentSection(
                    vm: environmentVM,
                    requestDelete: { showEnvironmentCleanupConfirmation = true },
                    copyText: copyToClipboard,
                    openURL: openExternalURL
                )
            }
        }
        .task {
            await vm.loadIfNeeded(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
            await environmentVM.loadIfNeeded()
        }
        .onChange(of: env.preferences.apiProviderKeyStorageMode) { _, newMode in
            Task { await vm.reload(keyStorageMode: newMode) }
        }
        .alert("Configuration Error", isPresented: errorBinding) {
            Button("OK") { vm.clearError() }
        } message: {
            Text(vm.lastError ?? "")
        }
        .alert("Delete Environment Variables?", isPresented: $showEnvironmentCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await env.cliEnvironment.deleteSelectedConflicts() }
            }
        } message: {
            Text("Selected shell config lines will be backed up first, then removed. Process environment variables and read-only files are skipped.")
        }
    }

    private func header(vm: APIProviderSwitcherViewModel) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API Provider Switcher")
                    .font(.sora(28, weight: .semibold))
                HStack(spacing: 8) {
                    Text(vm.selectedCLI.displayName)
                    Text("·")
                    Text(env.preferences.apiProviderKeyStorageMode.displayName)
                }
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 12)
            if vm.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func cliRail(vm: APIProviderSwitcherViewModel) -> some View {
        AppScrollView {
            VStack(spacing: 10) {
                ForEach(APIProviderCLI.allCases) { cli in
                    Button {
                        editorMode = .fields
                        vm.selectCLI(cli, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                    } label: {
                        Image(cli.assetName)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(vm.selectedCLI == cli ? Color.stxAccent : Color.stxMuted)
                            .frame(width: 54, height: 54)
                            .background {
                                if vm.selectedCLI == cli {
                                    RoundedRectangle(cornerRadius: 8).fill(Color.stxAccent.opacity(0.14))
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(vm.selectedCLI == cli ? Color.stxAccent.opacity(0.4) : Color.clear, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(cli.displayName)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(width: railColumnWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .appSurface(.compactCard(radius: 8, cornerStyle: .circular, maxWidth: nil))
    }

    private func providersColumn(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Providers")
                    .font(.sora(15, weight: .semibold))
                Spacer(minLength: 8)
                Button {
                    Task { await vm.importCurrent(keyStorageMode: env.preferences.apiProviderKeyStorageMode) }
                } label: {
                    Label("Import Current", systemImage: AppIcon.Action.importFile)
                }
                .controlSize(.small)
                .disabled(vm.isWorking)
                Menu {
                    Button {
                        Task { await vm.addProvider(keyStorageMode: env.preferences.apiProviderKeyStorageMode) }
                    } label: {
                        Label("Provider", systemImage: AppIcon.Action.add)
                    }
                    Button {
                        Task { await vm.addUniversalProvider(keyStorageMode: env.preferences.apiProviderKeyStorageMode) }
                    } label: {
                        Label("Universal Provider", systemImage: AppIcon.Network.webSocket)
                    }
                } label: {
                    Image(systemName: AppIcon.Action.add)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.button)
                .controlSize(.small)
                .disabled(vm.isWorking)
                .help("New provider")
            }

            AppScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 0) {
                        let providers = vm.providers(for: vm.selectedCLI)
                        if providers.isEmpty {
                            Text("No providers")
                                .font(.sora(12))
                                .foregroundStyle(Color.stxMuted)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(providers) { provider in
                                APIProviderListRow(
                                    provider: provider,
                                    isSelected: vm.selectedProviderID == provider.id,
                                    isActive: vm.isActive(provider)
                                ) {
                                    editorMode = .fields
                                    vm.selectProvider(provider, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                                }
                                if provider.id != providers.last?.id {
                                    StxRule().padding(.leading, 12)
                                }
                            }
                        }
                    }
                    .appSurface(.compactCard(radius: 8, cornerStyle: .circular))

                    if let result = vm.latestApplyResult {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last backup")
                                .font(.sora(10, weight: .semibold))
                                .foregroundStyle(Color.stxMuted)
                            Text(result.backupDirectory.path)
                                .font(.sora(10).monospaced())
                                .foregroundStyle(Color.stxMuted)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular), padding: nil)
                    }
                }
                .padding(.trailing, 2)
            }
        }
        .frame(minWidth: providerColumnWidth, maxWidth: .infinity, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func editorColumn(vm: APIProviderSwitcherViewModel) -> some View {
        editorPanel(vm: vm)
            .frame(minWidth: providerColumnWidth, maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func editorPanel(vm: APIProviderSwitcherViewModel) -> some View {
        if vm.draftProviderID == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("No provider selected")
                    .font(.sora(16, weight: .semibold))
                Text("Create or import a provider.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: railMinimumHeight, alignment: .topLeading)
            .appSurface(.compactCard(radius: 8, cornerStyle: .circular, maxWidth: nil))
        } else {
            VStack(alignment: .leading, spacing: 14) {
                editorHeader(vm: vm)
                Picker("", selection: $editorMode) {
                    ForEach(APIProviderEditorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)

                if editorMode == .fields {
                    providerFields(vm: vm)
                        .frame(height: editorModeContentHeight, alignment: .top)
                } else {
                    rawEditor(vm: vm)
                        .frame(height: editorModeContentHeight, alignment: .top)
                }

                editorActions(vm: vm)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: railMinimumHeight, alignment: .topLeading)
            .appSurface(.compactCard(radius: 8, cornerStyle: .circular, maxWidth: nil))
        }
    }

    private func editorHeader(vm: APIProviderSwitcherViewModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(vm.draftCLI.assetName)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.stxAccent)
            VStack(alignment: .leading, spacing: 7) {
                Text(vm.draftName.isEmpty ? "Provider" : vm.draftName)
                    .font(.sora(18, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    APIProviderBadge(title: vm.draftOrigin?.displayName ?? "Provider")
                    APIProviderBadge(title: vm.draftCategory.displayName)
                    if let provider = vm.selectedProvider, vm.isActive(provider) {
                        APIProviderBadge(title: "Active", tint: Color.stxAccent)
                    }
                    if vm.draftIsDirty {
                        APIProviderBadge(title: "Unsaved", tint: .orange)
                    }
                }
            }
            Spacer(minLength: 12)
        }
    }

    private func providerFields(vm: APIProviderSwitcherViewModel) -> some View {
        @Bindable var bindableVM = vm
        let isOfficial = bindableVM.draftOrigin?.kind == .official
        let isUniversal = bindableVM.draftOrigin?.kind == .universal

        return VStack(alignment: .leading, spacing: 12) {
            APIProviderFieldRow(title: "Name") {
                TextField("Provider name", text: $bindableVM.draftName)
                    .textFieldStyle(.roundedBorder)
            }
            APIProviderFieldRow(title: "Category") {
                AppSelect(
                    .localized("Category"),
                    selection: $bindableVM.draftCategory,
                    options: APIProviderCategory.allCases.map { category in
                        AppSelectOption(value: category, title: .localized(category.displayName))
                    },
                    width: 180
                )
                .disabled(isUniversal)
            }
            APIProviderFieldRow(title: "Base URL") {
                TextField("https://api.example.com", text: $bindableVM.draftBaseURL)
                    .textFieldStyle(.roundedBorder)
            }
            APIProviderFieldRow(title: "API Key") {
                SecureField("API key", text: $bindableVM.draftAPIKey)
                    .textFieldStyle(.roundedBorder)
            }
            APIProviderFieldRow(title: "Model") {
                TextField(bindableVM.draftCLI == .claude ? "claude-compatible model" : "gpt-compatible model", text: $bindableVM.draftModel)
                    .textFieldStyle(.roundedBorder)
            }
        }
            .disabled(isOfficial || bindableVM.isWorking)
    }

    private func rawEditor(vm: APIProviderSwitcherViewModel) -> some View {
        @Bindable var bindableVM = vm
        let isEditable = bindableVM.canSaveSelectedProvider && !bindableVM.isWorking

        return VStack(alignment: .leading, spacing: 8) {
            ConfigurationTextEditor(
                text: $bindableVM.draftRawConfig,
                fileKind: bindableVM.draftCLI == .claude ? .json : .toml,
                isEditable: isEditable
            ) { line, column in
                cursorLine = line
                cursorColumn = column
            }
            .frame(maxHeight: .infinity)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))

            HStack(spacing: 8) {
                Text(bindableVM.draftCLI == .claude ? "settings.json" : "config.toml")
                Text("·")
                Text("\(cursorLine):\(cursorColumn)")
                Spacer(minLength: 8)
            }
            .font(.sora(10).monospacedDigit())
            .foregroundStyle(Color.stxMuted)
        }
    }

    private func editorActions(vm: APIProviderSwitcherViewModel) -> some View {
        ViewThatFits(in: .horizontal) {
            editorActionButtons(vm: vm, showLabels: true)
            editorActionButtons(vm: vm, showLabels: false)
        }
        .controlSize(.small)
    }

    private func editorActionButtons(vm: APIProviderSwitcherViewModel, showLabels: Bool) -> some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                Task { await vm.deleteSelectedProvider(keyStorageMode: env.preferences.apiProviderKeyStorageMode) }
            } label: {
                actionLabel("Delete", systemImage: AppIcon.Action.delete, showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .disabled(!vm.canDeleteSelectedProvider || vm.isWorking)
            .help("Delete")

            Spacer(minLength: 12)

            Button {
                vm.resetDraft(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
            } label: {
                actionLabel("Revert", systemImage: AppIcon.Action.undo, showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .disabled(!vm.draftIsDirty || vm.isWorking)
            .help("Revert")

            Button {
                Task {
                    await vm.saveDraft(rawMode: editorMode == .raw, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                }
            } label: {
                actionLabel("Save Provider", systemImage: AppIcon.Action.importFile, showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .disabled(!vm.canSaveSelectedProvider || !vm.draftIsDirty || vm.isWorking)
            .help("Save Provider")

            Button {
                Task {
                    await vm.enableSelectedProvider(rawMode: editorMode == .raw, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                }
            } label: {
                actionLabel("Enable Provider", systemImage: AppIcon.Metric.boltFilled, showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .buttonStyle(.borderedProminent)
            .disabled(vm.selectedProvider == nil || vm.isWorking)
            .help("Enable Provider")
        }
    }

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String, showLabels: Bool) -> some View {
        if showLabels {
            Label(title, systemImage: systemImage)
        } else {
            Image(systemName: systemImage)
                .frame(width: 22, height: 18)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { env.apiProviders.lastError != nil },
            set: { newValue in
                if !newValue { env.apiProviders.clearError() }
            }
        )
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func openExternalURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

private enum APIProviderEditorMode: String, CaseIterable, Identifiable {
    case fields
    case raw

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fields: "Fields"
        case .raw: "Raw"
        }
    }
}

private struct APIProviderListRow: View {
    let provider: CLIAPIProvider
    let isSelected: Bool
    let isActive: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(provider.cli.assetName)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    Text(provider.name)
                        .font(.sora(12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if isActive {
                        Circle()
                            .fill(Color.stxAccent)
                            .frame(width: 7, height: 7)
                    }
                }

                HStack(spacing: 6) {
                    APIProviderBadge(title: provider.origin.displayName)
                    if provider.category != .official && provider.category != .imported {
                        APIProviderBadge(title: provider.category.displayName)
                    }
                    Spacer(minLength: 6)
                }

                HStack(spacing: 6) {
                    Text(provider.baseURL.isEmpty ? "Official endpoint" : provider.baseURL)
                        .lineLimit(1)
                    if !provider.model.isEmpty {
                        Text("·")
                        Text(provider.model).lineLimit(1)
                    }
                }
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7).fill(Color.stxAccent.opacity(0.10))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct APIProviderFieldRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.sora(11, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 86, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct APIProviderBadge: View {
    let title: String
    var tint: Color = Color.stxMuted

    var body: some View {
        Text(title)
            .font(.sora(9, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.2), lineWidth: 1))
    }
}

private struct CLIEnvironmentSection: View {
    @Bindable var vm: CLIEnvironmentViewModel
    let requestDelete: () -> Void
    let copyText: (String) -> Void
    let openURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Local environment check")
                    .font(.sora(15, weight: .semibold))
                if vm.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer(minLength: 12)
                Button {
                    Task { await vm.refresh() }
                } label: {
                    Label(vm.isLoading ? "Refreshing" : "Refresh", systemImage: AppIcon.Action.refresh)
                }
                .controlSize(.small)
                .disabled(vm.isLoading || vm.isCleaning)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 300), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(APIProviderCLI.allCases) { cli in
                    CLIEnvironmentStatusCard(
                        cli: cli,
                        status: vm.status(for: cli),
                        isLoading: vm.isLoading,
                        copyText: copyText,
                        openURL: openURL
                    )
                }
            }

            CLIEnvironmentConflictPanel(
                vm: vm,
                requestDelete: requestDelete,
                copyText: copyText
            )

            if let lastError = vm.lastError {
                HStack(spacing: 8) {
                    Image(systemName: AppIcon.Status.warning)
                    Text(lastError)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Dismiss") {
                        vm.clearError()
                    }
                    .controlSize(.small)
                }
                .font(.sora(11))
                .foregroundStyle(.orange)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
            }
        }
        .padding(.top, 2)
    }
}

private struct CLIEnvironmentStatusCard: View {
    let cli: APIProviderCLI
    let status: CLIToolStatus?
    let isLoading: Bool
    let copyText: (String) -> Void
    let openURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: AppIcon.Runtime.terminal)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                Text(cli.shortName)
                    .font(.sora(18, weight: .semibold))
                    .lineLimit(1)
                APIProviderBadge(title: CLIEnvironmentType.macOS.displayName)
                Spacer(minLength: 8)
                statusAccessory
            }

            Text(detailText)
                .font(.sora(14).monospaced())
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(status?.diagnostic ?? status?.displayValue ?? "")

            HStack(spacing: 8) {
                if let status, status.isOutdated, let latestVersion = status.latestVersion {
                    APIProviderBadge(title: "Latest \(latestVersion)", tint: .orange)
                }
                Spacer(minLength: 8)
                if needsInstallActions {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            Button {
                                copyText(cli.installCommand)
                            } label: {
                                Label("Copy Install", systemImage: AppIcon.Action.copy)
                            }
                            Button {
                                openURL(cli.installURL)
                            } label: {
                                Label("Install Page", systemImage: AppIcon.Action.openExternal)
                            }
                        }
                        HStack(spacing: 8) {
                            Button {
                                copyText(cli.installCommand)
                            } label: {
                                Image(systemName: AppIcon.Action.copy)
                                    .frame(width: 22, height: 18)
                            }
                            .help("Copy Install")
                            Button {
                                openURL(cli.installURL)
                            } label: {
                                Image(systemName: AppIcon.Action.openExternal)
                                    .frame(width: 22, height: 18)
                            }
                            .help("Install Page")
                        }
                    }
                    .controlSize(.small)
                }
            }
            .frame(minHeight: 24)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .appSurface(.compactCard(radius: 8, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    @ViewBuilder
    private var statusAccessory: some View {
        if isLoading && status == nil {
            ProgressView()
                .controlSize(.small)
        } else if status?.isInstalled == true {
            Image(systemName: AppIcon.Status.success)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(status?.isOutdated == true ? .orange : Color(red: 0.0, green: 0.65, blue: 0.38))
        } else {
            Image(systemName: AppIcon.Status.error)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.orange)
        }
    }

    private var detailText: String {
        if isLoading && status == nil {
            return "checking..."
        }
        return status?.displayValue ?? "not installed or not executable"
    }

    private var needsInstallActions: Bool {
        guard !isLoading else { return false }
        guard let status else { return true }
        return !status.isInstalled || status.isOutdated
    }

}

private struct CLIEnvironmentConflictPanel: View {
    @Bindable var vm: CLIEnvironmentViewModel
    let requestDelete: () -> Void
    let copyText: (String) -> Void

    var body: some View {
        if vm.conflicts.isEmpty {
            cleanPanel
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: AppIcon.Status.warning)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Environment variable conflicts")
                            .font(.sora(13, weight: .semibold))
                        Text("\(vm.conflicts.count) ANTHROPIC / OPENAI variable\(vm.conflicts.count == 1 ? "" : "s") found in your local environment.")
                            .font(.sora(11))
                            .foregroundStyle(Color.stxMuted)
                    }
                    Spacer(minLength: 8)
                    Button {
                        vm.selectAllDeletableConflicts()
                    } label: {
                        Label("Select All", systemImage: AppIcon.AIConfig.plan)
                    }
                    .controlSize(.small)
                    .disabled(vm.isCleaning || vm.conflicts.allSatisfy { !$0.isDeletable })

                    Button(role: .destructive) {
                        requestDelete()
                    } label: {
                        Label("Delete Selected", systemImage: AppIcon.Action.delete)
                    }
                    .controlSize(.small)
                    .disabled(vm.selectedDeletableCount == 0 || vm.isCleaning)
                }

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(vm.conflicts) { conflict in
                        CLIEnvironmentConflictRow(
                            conflict: conflict,
                            isSelected: vm.isSelected(conflict),
                            isRevealed: vm.isRevealed(conflict),
                            toggleSelection: { vm.toggleSelection(conflict) },
                            toggleReveal: { vm.toggleReveal(conflict) },
                            copyText: copyText
                        )
                    }
                }

                if let result = vm.latestCleanupResult {
                    cleanupResult(result)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
        }
    }

    private var cleanPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: AppIcon.Status.success)
                .foregroundStyle(Color(red: 0.0, green: 0.65, blue: 0.38))
            VStack(alignment: .leading, spacing: 2) {
                Text("No environment conflicts")
                    .font(.sora(13, weight: .semibold))
                Text("No ANTHROPIC or OPENAI overrides were found in process or shell config files.")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.65, cornerStyle: .circular), padding: nil)
    }

    private func cleanupResult(_ result: CLIEnvironmentCleanupResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last cleanup backup")
                .font(.sora(10, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            Text(result.backupDirectory.path)
                .font(.sora(10).monospaced())
                .foregroundStyle(Color.stxMuted)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if !result.skippedConflicts.isEmpty {
                Text("\(result.skippedConflicts.count) item\(result.skippedConflicts.count == 1 ? "" : "s") skipped")
                    .font(.sora(10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular), padding: nil)
    }
}

private struct CLIEnvironmentConflictRow: View {
    let conflict: CLIEnvironmentConflict
    let isSelected: Bool
    let isRevealed: Bool
    let toggleSelection: () -> Void
    let toggleReveal: () -> Void
    let copyText: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: toggleSelection) {
                Image(systemName: conflict.isDeletable ? (isSelected ? "checkmark.square.fill" : "square") : "lock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(conflict.isDeletable ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(!conflict.isDeletable)
            .help(conflict.isDeletable ? "Select for deletion" : "This source cannot be edited from here")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(conflict.cli.assetName)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Color.stxMuted)
                    Text(conflict.varName)
                        .font(.sora(12, weight: .semibold))
                        .lineLimit(1)
                    APIProviderBadge(title: conflict.cli.shortName)
                    Spacer(minLength: 8)
                }

                HStack(spacing: 6) {
                    Text("Value:")
                    Text(isRevealed ? conflict.varValue : conflict.maskedValue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        toggleReveal()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .frame(width: 18, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help(isRevealed ? "Hide value" : "Reveal value")
                }
                .font(.sora(10).monospaced())
                .foregroundStyle(Color.stxMuted)

                HStack(spacing: 6) {
                    Text(conflict.sourceDescription)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button {
                        copyText(conflict.varName)
                    } label: {
                        Image(systemName: AppIcon.Action.copy)
                            .frame(width: 18, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Copy variable")
                    Button {
                        copyText(conflict.sourceDescription)
                    } label: {
                        Image(systemName: AppIcon.Layout.route)
                            .frame(width: 18, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Copy source")
                }
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.75, cornerStyle: .circular), padding: nil)
    }
}

#if DEBUG
#Preview {
    ConfigurationsView()
        .environment(AppEnvironment.preview())
        .frame(width: 1180, height: 780)
}
#endif
