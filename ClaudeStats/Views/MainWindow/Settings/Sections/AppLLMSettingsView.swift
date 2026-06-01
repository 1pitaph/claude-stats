import SwiftUI

struct AppLLMSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var llm = env.appLLMSettings
        #if !CLAUDE_STATS_LITE
        @Bindable var localAI = env.localAI
        #endif

        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(
                title: "LLM Mode",
                caption: "Used by AI-powered features such as Git summaries. Generation is still manual, so nothing is sent until you click Generate."
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
