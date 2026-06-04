import AppKit
import SwiftUI

struct AppLLMSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage(GitCommitMessageDiagnosticsLog.retentionDefaultsKey) private var gitCommitMessageDiagnosticsRetentionDays = GitCommitMessageDiagnosticsLog.defaultRetentionDays

    var body: some View {
        @Bindable var llm = env.appLLMSettings
        #if !CLAUDE_STATS_LITE
        @Bindable var localAI = env.localAI
        #endif

        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(
                title: "LLM Mode",
                caption: "Used by AI-powered features such as Git commit messages. Generation is still manual, so nothing is sent until you click Generate."
            ) {
                VStack(spacing: 0) {
                    SettingRow(title: "Mode", description: "Choose the default model source.") {
                        AppSelect(
                            .localized("Mode"),
                            selection: $llm.mode,
                            options: AppLLMMode.availableCases.map { AppSelectOption(value: $0, title: .localized($0.title)) },
                            width: 190,
                            size: .small
                        )
                    }
                    SettingRowDivider()
                    SettingRow(title: "Git commit message", description: "Choose automatic routing or force a single LLM call.") {
                        AppSelect(
                            .localized("Git commit message"),
                            selection: $llm.gitCommitMessageAlgorithmPreference,
                            options: GitCommitMessageAlgorithmPreference.allCases.map {
                                AppSelectOption(value: $0, title: .localized($0.title), subtitle: .verbatim($0.subtitle))
                            },
                            width: 230,
                            size: .small,
                            onSelectionChange: { preference in
                                Task { await llm.saveGitCommitMessageAlgorithmPreference(preference) }
                            }
                        )
                        .disabled(llm.isLoading)
                    }
                    SettingRowDivider()
                    SettingRow(title: "Status", description: "Current readiness for generation.") {
                        #if CLAUDE_STATS_LITE
                        let readiness = llm.readinessSummary()
                        #else
                        let readiness = llm.readinessSummary(localAI: env.localAI)
                        #endif
                        StatusSeverityBadge(
                            label: readiness,
                            indicatorTint: readiness == "Ready" ? Color.stxAccent : Color.orange
                        )
                    }
                }
                .settingCard()
            }

            #if CLAUDE_STATS_LITE
            onlineProviderGroup(llm: llm)
            #else
            if llm.mode == .online {
                onlineProviderGroup(llm: llm)
            } else {
                localProviderGroup(llm: llm, localAI: localAI)
            }
            #endif

            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                gitCommitMessageDiagnosticsGroup(refreshDate: context.date)
            }

            if let message = llm.setupMessage {
                Text(message)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .padding(12)
                    .settingCard()
            }

            if let error = llm.lastError {
                Text(error)
                    .font(.sora(11))
                    .foregroundStyle(Color.red)
                    .padding(12)
                    .settingCard()
            }
        }
        .task {
            await env.appLLMSettings.loadIfNeeded()
        }
    }

    private func onlineProviderGroup(llm: AppLLMSettingsStore) -> some View {
        @Bindable var llm = llm
        return SettingGroup(title: "Online API", caption: "OpenAI-compatible, OpenAI Responses, and Anthropic Messages endpoints are supported.") {
            VStack(spacing: 0) {
                SettingRow(title: "Protocol", description: "Select the request format used for this provider.") {
                    AppSelect(
                        .localized("Protocol"),
                        selection: $llm.selectedProtocol,
                        options: AppLLMProtocol.allCases.map {
                            AppSelectOption(value: $0, title: .localized($0.title), subtitle: .verbatim($0.subtitle))
                        },
                        width: 240,
                        size: .small,
                        onSelectionChange: { llm.selectProtocol($0) }
                    )
                }
                SettingRowDivider()
                SettingRow(title: "Name") {
                    TextField("Provider", text: $llm.providerName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
                SettingRowDivider()
                SettingRow(title: "Base URL") {
                    TextField("https://api.openai.com/v1", text: $llm.providerBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }
                SettingRowDivider()
                SettingRow(title: "Model") {
                    TextField("gpt-5-mini", text: $llm.providerModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
                SettingRowDivider()
                SettingRow(title: "API Key", description: "Stored in Keychain; raw keys are not written into settings JSON.") {
                    SecureField("sk-...", text: $llm.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }
                SettingRowDivider()
                SettingRow(title: "Save provider") {
                    Button {
                        Task { await llm.saveDraft() }
                    } label: {
                        Label("Save", systemImage: AppIcon.Action.confirm)
                    }
                    .controlSize(.small)
                    .disabled(llm.isLoading)
                }
            }
            .settingCard()
        }
    }

    private func gitCommitMessageDiagnosticsGroup(refreshDate: Date) -> some View {
        let readableLogPath = GitCommitMessageDiagnosticsLog.currentReadableLogURL(date: refreshDate).path
        let jsonLogPath = GitCommitMessageDiagnosticsLog.currentLogURL(date: refreshDate).path
        let sourceReadableLogPath = GitCommitMessageDiagnosticsLog.sourceRootLogDirectory()
            .map { GitCommitMessageDiagnosticsLog.currentReadableLogURL(directory: $0, date: refreshDate).path }
        let sourceSize = GitCommitMessageDiagnosticsLog.sourceRootLogDirectory().map {
            GitCommitMessageDiagnosticsLog.currentReadableLogSize(directory: $0, date: refreshDate) +
                GitCommitMessageDiagnosticsLog.currentLogSize(directory: $0, date: refreshDate)
        } ?? 0
        let size = GitCommitMessageDiagnosticsLog.currentReadableLogSize(date: refreshDate) +
            GitCommitMessageDiagnosticsLog.currentLogSize(date: refreshDate) +
            sourceSize
        return SettingGroup(
            title: "Git Commit Message Diagnostics Log",
            caption: "Writes redacted metadata for Git commit message LLM calls, cache lookups, parse status, timings, and token counts."
        ) {
            VStack(spacing: 0) {
                SettingRow(title: "Current log", description: readableLogPath.memoryAbbreviatingHomeDirectory) {
                    GitCommitMessageDiagnosticsCopyButton(value: readableLogPath, label: "Copy Log Path")
                }
                SettingRowDivider()
                SettingRow(title: "JSONL", description: jsonLogPath.memoryAbbreviatingHomeDirectory) {
                    GitCommitMessageDiagnosticsCopyButton(value: jsonLogPath, label: "Copy JSONL Path")
                }
                SettingRowDivider()
                if let sourceReadableLogPath {
                    SettingRow(title: "Code root mirror", description: sourceReadableLogPath.memoryAbbreviatingHomeDirectory) {
                        GitCommitMessageDiagnosticsCopyButton(value: sourceReadableLogPath, label: "Copy Code Root Log Path")
                    }
                    SettingRowDivider()
                }
                SettingRow(title: "Size", description: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) {
                    EmptyView()
                }
                SettingRowDivider()
                SettingRow(title: "Retention", description: "Old git-commit-message log files are pruned on write and when this setting changes.") {
                    HStack(spacing: 8) {
                        AppSelect(
                            .localized("Retention"),
                            selection: gitCommitMessageDiagnosticsRetention,
                            options: GitCommitMessageDiagnosticsRetention.allCases.map {
                                AppSelectOption(value: $0, title: .localized($0.title))
                            },
                            width: 150,
                            size: .small,
                            onSelectionChange: { retention in
                                GitCommitMessageDiagnosticsLog.setConfiguredRetentionDays(retention.rawValue)
                            }
                        )
                        Button {
                            GitCommitMessageDiagnosticsLog.openCurrentLog()
                        } label: {
                            Label("Open Current Log", systemImage: AppIcon.Resource.transcriptSearch)
                        }
                        .controlSize(.small)

                        Button {
                            GitCommitMessageDiagnosticsLog.revealLogFolder()
                        } label: {
                            Label("Reveal Log Folder", systemImage: AppIcon.Resource.folder)
                        }
                        .controlSize(.small)

                        if sourceReadableLogPath != nil {
                            Button {
                                GitCommitMessageDiagnosticsLog.revealSourceRootLogFolder()
                            } label: {
                                Label("Reveal Code Logs", systemImage: AppIcon.Resource.folder)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .settingCard()
        }
    }

    private var gitCommitMessageDiagnosticsRetention: Binding<GitCommitMessageDiagnosticsRetention> {
        Binding {
            GitCommitMessageDiagnosticsRetention(rawValue: gitCommitMessageDiagnosticsRetentionDays) ?? .threeDays
        } set: { retention in
            gitCommitMessageDiagnosticsRetentionDays = retention.rawValue
            GitCommitMessageDiagnosticsLog.setConfiguredRetentionDays(retention.rawValue)
        }
    }

    #if !CLAUDE_STATS_LITE
    private func localProviderGroup(llm: AppLLMSettingsStore, localAI: LocalAIStore) -> some View {
        @Bindable var llm = llm
        @Bindable var localAI = localAI
        return SettingGroup(title: "Local LLM", caption: "Uses the app's loopback OpenAI-compatible endpoint and selected local LLM model.") {
            VStack(spacing: 0) {
                SettingRow(title: "Local API", description: "Endpoint used for local generation.") {
                    HStack(spacing: 8) {
                        Text(localAI.localAPIStatusText)
                            .font(.sora(10).monospaced())
                            .foregroundStyle(localAI.localAPIEndpoint == nil ? Color.stxMuted : Color.green)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 260, alignment: .trailing)
                        Button {
                            localAI.startOpenAICompatibleServer()
                        } label: {
                            Label("Start", systemImage: AppIcon.Action.start)
                        }
                        .controlSize(.small)
                        Button {
                            localAI.stopOpenAICompatibleServer()
                        } label: {
                            Label("Stop", systemImage: AppIcon.Action.stop)
                        }
                        .controlSize(.small)
                        .disabled(localAI.localAPIEndpoint == nil)
                    }
                }
                SettingRowDivider()
                SettingRow(title: "Selected model") {
                    HStack(spacing: 6) {
                        StatusSeverityBadge(
                            label: localAI.localLLMAvailable ? localAI.modelStore.selectedLLMModel.displayName : "LLM missing",
                            indicatorTint: localAI.localLLMAvailable ? Color.stxAccent : Color.orange
                        )
                        StatusSeverityBadge(
                            label: localAI.semanticSearchAvailable ? "Embedding ready" : "Embedding missing",
                            indicatorTint: localAI.semanticSearchAvailable ? Color.stxAccent : Color.orange
                        )
                    }
                }
                SettingRowDivider()
                SettingRow(title: "Save mode") {
                    Button {
                        Task { await llm.useLocalModeAndSave() }
                    } label: {
                        Label("Save", systemImage: AppIcon.Action.confirm)
                    }
                    .controlSize(.small)
                    .disabled(llm.isLoading)
                }
            }
            .settingCard()
        }
    }
    #endif
}

private struct GitCommitMessageDiagnosticsCopyButton: View {
    let value: String
    let label: String

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: {
            Label(label, systemImage: AppIcon.Resource.link)
        }
        .controlSize(.small)
        .disabled(value.isEmpty)
        .help(label)
    }
}

#if DEBUG
#Preview("LLM settings") {
    AppScrollView {
        VStack(alignment: .leading, spacing: 32) {
            Text("LLM")
                .font(.sora(28, weight: .semibold))
            AppLLMSettingsView()
        }
        .padding(20)
    }
    .environment(AppEnvironment.preview())
    .frame(width: 860, height: 640)
    .background(Color.stxBackground)
}
#endif
