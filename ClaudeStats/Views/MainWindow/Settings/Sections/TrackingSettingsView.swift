import SwiftUI
import AppKit

struct TrackingSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var fullDiskAccessOK = ScreenTimeService.canRead()
    @State private var newCodingSurfaceBundleID = ""
    @State private var newCLIHostBundleID = ""
    var onSelectSection: (SettingsSection) -> Void = { _ in }

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            aiActivityGroup(prefs: prefs)
            #if !CLAUDE_STATS_LITE
            trackIntegrationGroup
            #endif
            gitTrackingGroup(prefs: prefs)
        }
        #if !CLAUDE_STATS_LITE
        .task {
            await env.track.refreshHookInstallationStatus()
        }
        #endif
    }

    // MARK: - AI activity

    @ViewBuilder
    private func aiActivityGroup(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        SettingGroup(
            title: "AI Activity Analysis",
            caption: "Adds an Activity tab that compares coding surfaces, CLI hosts, and AI activity. Reading Screen Time requires Full Disk Access."
        ) {
            if !prefs.aiActivityAnalysisEnabled {
                FeatureDisabledNotice(
                    featureName: "AI Activity Analysis",
                    message: "Turn it on in Features to edit Screen Time access and coding surface settings."
                ) {
                    onSelectSection(.features)
                }
            }

            VStack(spacing: 0) {
                fullDiskAccessRow
            }
            .settingCard()
            .disabledSettingsBlock(!prefs.aiActivityAnalysisEnabled)

            activitySurfaceListCard(prefs: prefs)
                .disabledSettingsBlock(!prefs.aiActivityAnalysisEnabled)
        }
    }

    private var fullDiskAccessRow: some View {
        SettingRow(title: "Full Disk Access",
                   description: "Required so Claude Stats can read the local Screen Time database.") {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(fullDiskAccessOK ? "Granted" : "Not granted"))
                    .font(.sora(12))
                    .foregroundStyle(fullDiskAccessOK ? Color.stxMuted : Color.stxAccent)
                if !fullDiskAccessOK {
                    Button("Open Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Button("Re-check") { fullDiskAccessOK = ScreenTimeService.canRead() }
            }
        }
    }

    private func activitySurfaceListCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Coding surfaces")
                    .font(.sora(13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            SettingRowDivider()

            surfaceSection(
                title: "GUI coding surfaces",
                caption: "GUI coding apps plus Codex and Claude.",
                defaults: ActivitySurfaceCatalog.codingSurfaceDefaults,
                removedIDs: $prefs.codingSurfaceBundleIDsRemoved,
                addedIDs: $prefs.codingSurfaceBundleIDsAdded,
                newBundleID: $newCodingSurfaceBundleID,
                placeholder: "Add GUI bundle id"
            )

            SettingRowDivider()

            surfaceSection(
                title: "CLI hosts",
                caption: "Terminal apps shown separately from AI-assisted coding.",
                defaults: ActivitySurfaceCatalog.cliHostDefaults,
                removedIDs: $prefs.cliHostBundleIDsRemoved,
                addedIDs: $prefs.cliHostBundleIDsAdded,
                newBundleID: $newCLIHostBundleID,
                placeholder: "Add terminal bundle id"
            )
        }
        .settingCard()
    }

    private func surfaceSection(
        title: String,
        caption: String,
        defaults: [ActivitySurfaceCatalog.App],
        removedIDs: Binding<[String]>,
        addedIDs: Binding<[String]>,
        newBundleID: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.sora(12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(caption)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ForEach(defaults) { app in
                let binding = Binding(
                    get: { !removedIDs.wrappedValue.contains(app.bundleID) },
                    set: { included in
                        if included {
                            removedIDs.wrappedValue.removeAll { $0 == app.bundleID }
                        } else if !removedIDs.wrappedValue.contains(app.bundleID) {
                            removedIDs.wrappedValue.append(app.bundleID)
                        }
                    }
                )
                surfaceRow(name: app.name, subtitle: app.bundleID, isOn: binding)
                SettingRowDivider()
            }

            ForEach(addedIDs.wrappedValue, id: \.self) { id in
                customSurfaceRow(bundleID: id) {
                    addedIDs.wrappedValue.removeAll { $0 == id }
                }
                SettingRowDivider()
            }

            HStack(spacing: 8) {
                TextField(placeholder, text: newBundleID)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let id = newBundleID.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !id.isEmpty,
                          !addedIDs.wrappedValue.contains(id),
                          !defaults.contains(where: { $0.bundleID == id }) else { return }
                    addedIDs.wrappedValue.append(id)
                    newBundleID.wrappedValue = ""
                }
                .disabled(newBundleID.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func surfaceRow(name: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.sora(13, weight: .medium))
                Text(subtitle).font(.sora(11)).foregroundStyle(Color.stxMuted)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.appSwitch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func customSurfaceRow(bundleID: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(bundleID).font(.sora(13, weight: .medium))
                Text("Custom").font(.sora(11)).foregroundStyle(Color.stxMuted)
            }
            Spacer()
            Button("Remove", action: remove)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Track

    #if !CLAUDE_STATS_LITE
    private var trackIntegrationGroup: some View {
        SettingGroup(
            title: "Track",
            caption: "Captures Codex subagents, tool use, and approval gates through Codex hooks, then enriches the graph with transcript metadata."
        ) {
            VStack(spacing: 0) {
                let status = env.track.hookInstallationStatus
                SettingRow(
                    title: "Codex hook writer",
                    description: status?.statusDetail ?? "Install the Track hook helper to capture structured Codex runtime events."
                ) {
                    HStack(spacing: 8) {
                        Text(status?.statusTitle ?? "Unknown")
                            .font(.sora(12, weight: .semibold))
                            .foregroundStyle(status?.isInstalled == true ? Color.stxMuted : Color.stxAccent)
                        Button(env.track.isInstallingHookIntegration ? "Installing…" : "Install / Repair") {
                            Task {
                                await env.track.installCodexHookIntegration()
                                await env.refreshTrack()
                            }
                        }
                        .disabled(env.track.isInstallingHookIntegration)
                    }
                }

                SettingRowDivider()

                SettingRow(
                    title: "Event log",
                    description: status?.eventLogURL.path.memoryAbbreviatingHomeDirectory ?? "Claude Stats Track event log path."
                ) {
                    Text(status?.eventLogExists == true ? "Receiving events" : "No events yet")
                        .font(.sora(12, weight: .semibold))
                        .foregroundStyle(Color.stxMuted)
                }

                SettingRowDivider()

                SettingRow(
                    title: "Registered hooks",
                    description: registeredHookDescription(status)
                ) {
                    Text("\(status?.configuredEvents.count ?? 0)/\(CodexTrackHookInstaller.requiredEvents.count)")
                        .font(.sora(12, weight: .semibold))
                        .foregroundStyle(Color.stxMuted)
                }
            }
            .settingCard()
        }
    }

    private func registeredHookDescription(_ status: CodexTrackHookInstallationStatus?) -> String {
        guard let status else { return "Codex hook registration has not been checked yet." }
        guard !status.missingEvents.isEmpty else {
            return "Session, turn, subagent, tool, approval, and stop hooks are registered."
        }
        return "Missing: \(status.missingEvents.sorted().joined(separator: ", "))"
    }
    #endif

    // MARK: - Git tracking

    @ViewBuilder
    private func gitTrackingGroup(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        SettingGroup(
            title: "Git Tracking",
            caption: "Reads commit history from repositories opened or used by configured AI coding tools via the `git` command."
        ) {
            if !prefs.gitTrackingEnabled {
                FeatureDisabledNotice(
                    featureName: "Git Tracking",
                    message: "Turn it on in Features to edit git workspace behavior."
                ) {
                    onSelectSection(.features)
                }
            }

            repositorySourcesCard(prefs: prefs)
                .disabledSettingsBlock(!prefs.gitTrackingEnabled)

            VStack(spacing: 0) {
                SettingRow(title: "Open git view in") {
                    AppSelect(
                        .localized("Open git view in"),
                        selection: $prefs.gitOpensInWindow,
                        options: [
                            AppSelectOption(value: false, title: .localized("Panel tab")),
                            AppSelectOption(value: true, title: .localized("Separate window")),
                        ],
                        width: 180
                    )
                }
                SettingRowDivider()
                SettingRow(
                    title: "Diff block granularity",
                    description: "Fine separates mixed changes into modified, inserted, and deleted bands; Coarse keeps each change region as one block."
                ) {
                    Picker("", selection: $prefs.gitDiffBlockGranularity) {
                        ForEach(GitDiffBlockGranularity.allCases) { granularity in
                            Text(granularity.displayName).tag(granularity)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 180)
                }
                SettingRowDivider()
                SettingRow(
                    title: "Language engine",
                    description: "Language detection uses GitHub Linguist; scc supplies line counts."
                ) {
                    Text("GitHub Linguist + scc")
                        .font(.sora(12, weight: .semibold))
                        .foregroundStyle(Color.stxMuted)
                }
                SettingRowDivider()
                SettingRow(
                    title: "Statistics scope",
                    description: "HEAD counts committed code; Working Tree includes local uncommitted files."
                ) {
                    Picker("", selection: $prefs.gitStatsScope) {
                        ForEach(GitStatsScope.allCases) { scope in
                            Text(scope.label).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 220)
                }
            }
            .settingCard()
            .disabledSettingsBlock(!prefs.gitTrackingEnabled)
        }
    }

    private func repositorySourcesCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Repository sources")
                    .font(.sora(13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            SettingRowDivider()

            gitWorkspaceSourceSection(
                title: "Session sources",
                caption: "Transcript working directories.",
                sources: GitWorkspaceSourceCatalog.sessionSources,
                prefs: prefs
            )

            SettingRowDivider()

            gitWorkspaceSourceSection(
                title: "AI editor workspace history",
                caption: "Workspace folders remembered by each editor.",
                sources: GitWorkspaceSourceCatalog.editorSources,
                prefs: prefs
            )
        }
        .settingCard()
    }

    private func gitWorkspaceSourceSection(
        title: String,
        caption: String,
        sources: [GitWorkspaceSourceDescriptor],
        prefs: Preferences
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.sora(12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(caption)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            let rows = Array(sources.enumerated())
            ForEach(rows, id: \.element.id) { index, source in
                if index > 0 { SettingRowDivider() }
                gitWorkspaceSourceRow(source, prefs: prefs)
            }
        }
    }

    private func gitWorkspaceSourceRow(_ source: GitWorkspaceSourceDescriptor, prefs: Preferences) -> some View {
        let isOn = prefs.gitWorkspaceSourceIDs.contains(source.id)
        let isLastEnabled = isOn && prefs.gitWorkspaceSourceIDs.count == 1
        return HStack(spacing: 12) {
            Image(source.assetName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .opacity(isOn ? 1 : 0.45)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.sora(13, weight: .medium))
                Text(source.detail)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: Binding(
                get: { prefs.gitWorkspaceSourceIDs.contains(source.id) },
                set: { enabled in
                    var ids = prefs.gitWorkspaceSourceIDs
                    if enabled {
                        ids.insert(source.id)
                    } else {
                        ids.remove(source.id)
                    }
                    prefs.gitWorkspaceSourceIDs = ids
                }
            ))
            .labelsHidden()
            .toggleStyle(.appSwitch)
            .disabled(isLastEnabled)
            .help(isLastEnabled ? "At least one repository source must stay enabled." : source.detail)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#if DEBUG
#Preview {
    TrackingSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 720)
}
#endif
