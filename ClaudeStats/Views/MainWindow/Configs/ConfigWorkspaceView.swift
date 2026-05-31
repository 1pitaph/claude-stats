import AppKit
import SwiftUI

struct ConfigWorkspaceView: View {
    @Bindable var store: ConfigWorkspaceStore
    @Binding var selectedProjectID: String
    @Binding var selectedDocumentID: String

    @Environment(AppEnvironment.self) private var env
    private let horizontalInset: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await store.loadIfNeeded(
                sessions: env.store.sessions,
                keyStorageMode: env.preferences.apiProviderKeyStorageMode
            )
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CONFIG")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Text(store.activeTitle)
                    .font(.sora(24, weight: .semibold))
                    .lineLimit(1)
                Text(store.activeDescription)
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                Text(summaryText)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                if store.isLoadingActiveSection {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    refreshActiveSection()
                } label: {
                    Label("Refresh", systemImage: AppIcon.Action.refresh)
                }
                .controlSize(.small)
                .disabled(store.isLoadingActiveSection)
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var content: some View {
        switch store.section {
        case .overview:
            ConfigOverviewView(store: store)
        case .files:
            ConfigFilesWorkspaceContent(
                store: store,
                selectedProjectID: $selectedProjectID,
                selectedDocumentID: $selectedDocumentID
            )
        case .providers:
            ConfigurationsView(showsHeader: false)
        case .profiles:
            ConfigProfilesBackupsView(store: store)
        case .diagnostics:
            ConfigDiagnosticsView(store: store)
        }
    }

    private var summaryText: String {
        let counts = store.counts
        return "\(counts.configFileCount) files · \(counts.providerCount) providers · \(counts.profileCount) profiles · \(counts.diagnosticCount) issues"
    }

    private func refreshActiveSection() {
        Task {
            await store.refreshActiveSection(
                sessions: env.store.sessions,
                keyStorageMode: env.preferences.apiProviderKeyStorageMode
            )
        }
    }
}

private struct ConfigFilesWorkspaceContent: View {
    @Bindable var store: ConfigWorkspaceStore
    @Binding var selectedProjectID: String
    @Binding var selectedDocumentID: String

    @Environment(AppEnvironment.self) private var env

    private var aiSection: AIConfigsSection {
        store.filesSection.aiConfigSection
    }

    var body: some View {
        Group {
            if store.filesSection == .skillFiles {
                ConfigSkillFilesView(store: store)
            } else {
                AIConfigsWorkspaceView(
                    section: aiSection,
                    searchText: store.filesSearchText,
                    selectedProjectID: $selectedProjectID,
                    selectedDocumentID: $selectedDocumentID,
                    relatedSkills: store.relatedPluginSkills(for:),
                    createMissingDocument: { document in
                        Task {
                            await store.createMissingDocument(document)
                            await store.aiConfigs.reload(sessions: env.store.sessions)
                        }
                    }
                )
            }
        }
        .task {
            await store.aiConfigs.loadIfNeeded(sessions: env.store.sessions)
            await store.skills.loadIfNeeded(sessions: env.store.sessions)
            syncSelection()
        }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in
            Task {
                await store.aiConfigs.reload(sessions: env.store.sessions)
                await store.skills.reloadLocal(sessions: env.store.sessions)
                syncSelection()
            }
        }
        .onChange(of: store.filesSection) { _, _ in syncSelection() }
        .onChange(of: store.filesSearchText) { _, _ in syncSelection() }
        .onChange(of: store.aiConfigs.snapshot) { _, _ in syncSelection() }
    }

    private func syncSelection() {
        guard store.filesSection != .skillFiles else { return }
        let projectID = store.aiConfigs.resolvedProjectID(
            current: selectedProjectID.isEmpty ? nil : selectedProjectID,
            section: aiSection,
            query: store.filesSearchText
        )
        selectedProjectID = projectID ?? ""

        let documentID = store.aiConfigs.resolvedDocumentID(
            current: selectedDocumentID.isEmpty ? nil : selectedDocumentID,
            projectID: projectID,
            section: aiSection,
            query: store.filesSearchText
        )
        selectedDocumentID = documentID ?? ""
    }
}

private struct ConfigOverviewView: View {
    @Bindable var store: ConfigWorkspaceStore

    var body: some View {
        CenteredPaneContainer(maxWidth: 980, topPadding: 18) {
            AppScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                        overviewCard(
                            title: "Files",
                            value: "\(store.counts.configFileCount)",
                            symbol: ConfigWorkspaceSection.files.symbol
                        ) {
                            store.select(.files)
                        }
                        overviewCard(
                            title: "Providers",
                            value: "\(store.counts.providerCount)",
                            symbol: ConfigWorkspaceSection.providers.symbol
                        ) {
                            store.select(.providers)
                        }
                        overviewCard(
                            title: "Profiles",
                            value: "\(store.counts.profileCount)",
                            symbol: ConfigWorkspaceSection.profiles.symbol
                        ) {
                            store.select(.profiles)
                        }
                        overviewCard(
                            title: "Diagnostics",
                            value: "\(store.counts.diagnosticCount)",
                            symbol: ConfigWorkspaceSection.diagnostics.symbol
                        ) {
                            store.select(.diagnostics)
                        }
                    }

                    fileBreakdown
                    diagnosticsPreview
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func overviewCard(title: String, value: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.stxAccent)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.sora(24, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                    Text(title)
                        .font(.sora(11, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: AppIcon.Navigation.disclosure)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .appSurface(.compactCard(radius: 8, cornerStyle: .circular, maxWidth: nil), padding: nil)
        }
        .buttonStyle(.plain)
    }

    private var fileBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Files")
                .font(.sora(15, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                ForEach(ConfigFilesSection.allCases) { section in
                    Button {
                        store.selectFileSection(section)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.stxAccent)
                                .frame(width: 18)
                            Text(section.title)
                                .font(.sora(12, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(store.fileCount(for: section))")
                                .font(.sora(11).monospacedDigit())
                                .foregroundStyle(Color.stxMuted)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var diagnosticsPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Diagnostics")
                    .font(.sora(15, weight: .semibold))
                Spacer(minLength: 8)
                Button {
                    store.select(.diagnostics)
                } label: {
                    Label("Open", systemImage: AppIcon.Navigation.forward)
                }
                .controlSize(.small)
            }

            let items = Array(store.diagnostics.prefix(4))
            if items.isEmpty {
                AIConfigsEmptyState(
                    title: "No diagnostics",
                    message: "Files, providers, skills, and CLI environment checks are clean.",
                    symbol: AppIcon.Status.success
                )
                .frame(minHeight: 140)
                .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        ConfigDiagnosticRow(item: item, isCompact: true) {
                            store.select(item.targetSection)
                            if let filesSection = item.targetFilesSection {
                                store.selectFileSection(filesSection)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ConfigSkillFilesView: View {
    @Bindable var store: ConfigWorkspaceStore

    var body: some View {
        AppScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if store.filteredSkillFiles.isEmpty {
                    AIConfigsEmptyState(
                        title: store.filesSearchText.isEmpty ? "No skill files" : "No matching skill files",
                        message: "Installed SKILL.md files will appear here as configuration inputs.",
                        symbol: AppIcon.Feature.ai
                    )
                    .frame(minHeight: 320)
                } else {
                    ForEach(store.filteredSkillFiles) { skill in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: AppIcon.Feature.ai)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.stxAccent)
                                .frame(width: 20)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(skill.name)
                                        .font(.sora(13, weight: .semibold))
                                    AIConfigsBadge(text: skill.providerName, color: Color.stxMuted)
                                    AIConfigsBadge(text: skill.scope.displayName, color: Color.stxMuted)
                                    Spacer(minLength: 8)
                                }
                                Text(skill.displayDescription)
                                    .font(.sora(11))
                                    .foregroundStyle(Color.stxMuted)
                                    .lineLimit(2)
                                Text(skill.skillMarkdownPath.memoryAbbreviatingHomeDirectory)
                                    .font(.sora(10).monospaced())
                                    .foregroundStyle(Color.stxMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: skill.skillMarkdownPath)])
                            } label: {
                                Image(systemName: AppIcon.Action.revealInFinder)
                            }
                            .controlSize(.small)
                            .help("Reveal SKILL.md")
                        }
                        .padding(12)
                        .appSurface(.compactCard(radius: 8, fillOpacity: 0.65, cornerStyle: .circular, maxWidth: nil), padding: nil)
                    }
                }
            }
            .padding(18)
        }
    }
}

private struct ConfigProfilesBackupsView: View {
    @Bindable var store: ConfigWorkspaceStore

    var body: some View {
        if let profiles = store.configurationProfiles {
            AppScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    profilesSection(profiles)
                    backupsSection(profiles)
                }
                .padding(18)
            }
            .task {
                await profiles.loadIfNeeded()
                await profiles.reloadBackups()
            }
        } else {
            AIConfigsEmptyState(title: "Profiles unavailable", message: "Configuration profile services are not attached.", symbol: AppIcon.Resource.archive)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func profilesSection(_ profiles: ConfigurationProfilesViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Profiles")
                    .font(.sora(15, weight: .semibold))
                Spacer(minLength: 8)
                if profiles.isLoading || profiles.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task { await profiles.reload() }
                } label: {
                    Label("Refresh", systemImage: AppIcon.Action.refresh)
                }
                .controlSize(.small)
            }

            if profiles.library.profiles.isEmpty {
                AIConfigsEmptyState(
                    title: "No profiles",
                    message: "Capture provider configuration profiles from the Providers page.",
                    symbol: AppIcon.Resource.archive
                )
                .frame(minHeight: 180)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(profiles.library.profiles) { profile in
                        ConfigProfileRow(profile: profile, status: profiles.status(for: profile)) {
                            Task { _ = await profiles.apply(profile) }
                        }
                    }
                }
            }
        }
    }

    private func backupsSection(_ profiles: ConfigurationProfilesViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backups")
                .font(.sora(15, weight: .semibold))

            if profiles.backups.isEmpty {
                AIConfigsEmptyState(
                    title: "No backups",
                    message: "Backups are created automatically before profile apply or direct file saves.",
                    symbol: AppIcon.Status.history
                )
                .frame(minHeight: 180)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(profiles.backups) { backup in
                        ConfigBackupRow(
                            backup: backup,
                            diffs: profiles.selectedBackupDiffs.filter { $0.id.hasPrefix(backup.directoryPath) },
                            loadDiff: { Task { await profiles.loadBackupDiff(backup) } },
                            restore: { Task { _ = await profiles.restoreBackup(backup) } },
                            reveal: {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: backup.directoryPath, isDirectory: true)])
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct ConfigProfileRow: View {
    let profile: ConfigProfile
    let status: ConfigProfileStatus
    let apply: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: profile.provider.iconSystemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(profile.provider.accentColor)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(profile.name)
                        .font(.sora(13, weight: .semibold))
                    AIConfigsBadge(text: profile.provider.shortName, color: profile.provider.accentColor)
                    AIConfigsBadge(text: status.displayName, color: status.isClean ? Color.stxAccent : Color.stxMuted)
                }
                Text(profile.scope.detail)
                    .font(.sora(10).monospaced())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(profile.files.count) files · updated \(Format.shortDate(profile.updatedAt))")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 8)
            Button(action: apply) {
                Label("Apply", systemImage: AppIcon.Action.downloadDocument)
            }
            .controlSize(.small)
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.65, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }
}

private struct ConfigBackupRow: View {
    let backup: ConfigurationBackupSummary
    let diffs: [ConfigurationBackupDiff]
    let loadDiff: () -> Void
    let restore: () -> Void
    let reveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: AppIcon.Status.history)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.stxAccent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(backup.profileName)
                        .font(.sora(13, weight: .semibold))
                    Text("\(backup.fileCount) files · \(Format.shortDate(backup.createdAt))")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
                Spacer(minLength: 8)
                Button(action: loadDiff) {
                    Label("Diff", systemImage: AppIcon.Resource.transcriptSearch)
                }
                .controlSize(.small)
                Button(action: restore) {
                    Label("Restore", systemImage: AppIcon.Action.undoCircle)
                }
                .controlSize(.small)
                Button(action: reveal) {
                    Image(systemName: AppIcon.Action.revealInFinder)
                }
                .controlSize(.small)
                .help("Reveal backup")
            }

            if !diffs.isEmpty {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(diffs) { diff in
                        HStack(spacing: 8) {
                            AIConfigsBadge(text: diff.status.rawValue, color: diff.status == .unchanged ? Color.stxMuted : Color(red: 0.92, green: 0.58, blue: 0.16))
                            Text(diff.targetPath.memoryAbbreviatingHomeDirectory)
                                .font(.sora(10).monospaced())
                                .foregroundStyle(Color.stxMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.65, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }
}

struct ConfigDiagnosticsView: View {
    @Bindable var store: ConfigWorkspaceStore

    var body: some View {
        AppScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if store.filteredDiagnostics.isEmpty {
                    AIConfigsEmptyState(
                        title: store.diagnosticsSearchText.isEmpty ? "No diagnostics" : "No matching diagnostics",
                        message: store.diagnosticsSearchText.isEmpty
                            ? "Files, providers, skills, and CLI environment checks are clean."
                            : "Adjust the diagnostics search query.",
                        symbol: store.diagnosticsSearchText.isEmpty ? "checkmark.circle" : "magnifyingglass"
                    )
                    .frame(minHeight: 320)
                } else {
                    ForEach(store.filteredDiagnostics) { item in
                        ConfigDiagnosticRow(item: item, isCompact: false) {
                            store.select(item.targetSection)
                            if let filesSection = item.targetFilesSection {
                                store.selectFileSection(filesSection)
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }
}

private struct ConfigDiagnosticRow: View {
    let item: ConfigDiagnosticItem
    let isCompact: Bool
    let openTarget: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.severity.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(item.severity.configColor)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(item.title)
                        .font(.sora(isCompact ? 11 : 13, weight: .semibold))
                        .lineLimit(1)
                    AIConfigsBadge(text: item.source.title, color: Color.stxMuted)
                    AIConfigsBadge(text: item.severity.title, color: item.severity.configColor)
                    Spacer(minLength: 8)
                }
                Text(item.message)
                    .font(.sora(isCompact ? 10 : 11))
                    .foregroundStyle(isCompact ? Color.stxMuted : .primary)
                    .lineLimit(isCompact ? 1 : 2)
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.sora(10).monospaced())
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)
            Button {
                openTarget()
            } label: {
                Image(systemName: AppIcon.Navigation.forward)
                    .frame(width: 22, height: 18)
            }
            .controlSize(.small)
            .help("Open related Config section")
        }
        .padding(isCompact ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.65, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }
}

private extension ConfigDiagnosticSeverity {
    var configColor: Color {
        switch self {
        case .info:
            Color.stxMuted
        case .warning:
            Color(red: 0.92, green: 0.58, blue: 0.16)
        case .error:
            Color(red: 0.85, green: 0.22, blue: 0.18)
        }
    }
}

#if DEBUG
#Preview("Config workspace") {
    @Previewable @State var projectID = ""
    @Previewable @State var documentID = ""
    let env = AppEnvironment.preview()

    return ConfigWorkspaceView(
        store: env.configWorkspace,
        selectedProjectID: $projectID,
        selectedDocumentID: $documentID
    )
    .environment(env)
    .frame(width: 980, height: 720)
    .background(Color.stxBackground)
}
#endif
