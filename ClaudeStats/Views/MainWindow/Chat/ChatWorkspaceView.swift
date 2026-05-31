import SwiftUI

struct ChatWorkspaceView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var store: ChatStore

    private struct RefreshKey: Equatable {
        let lastRefreshedAt: Date?
        let sourceIDs: String
    }

    private var refreshKey: RefreshKey {
        RefreshKey(
            lastRefreshedAt: env.store.lastRefreshedAt,
            sourceIDs: GitWorkspaceSourceCatalog.storageString(for: env.preferences.gitWorkspaceSourceIDs)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            chatContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: refreshKey) {
            await store.loadIfNeeded(defaultModelID: env.localAI.modelStore.selectedLLMModel.id)
            await store.refreshProjects(sessions: env.store.sessions, sourceIDs: env.preferences.gitWorkspaceSourceIDs)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CHAT")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Text(store.selectedConversation?.title ?? "Local LLM Chat")
                    .font(.sora(24, weight: .semibold))
                    .lineLimit(1)
                Text(headerSubtitle)
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if store.isRefreshingProjects {
                ProgressView()
                    .controlSize(.small)
                    .help("Refreshing Projects")
            }

            Button {
                Task {
                    await store.refreshProjects(sessions: env.store.sessions, sourceIDs: env.preferences.gitWorkspaceSourceIDs)
                }
            } label: {
                Label("Refresh", systemImage: AppIcon.Action.sync)
            }
            .controlSize(.small)
            .disabled(store.isRefreshingProjects)

            Button {
                openLocalAISettings()
            } label: {
                Label("Local AI", systemImage: AppIcon.Workspace.memory)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }

    private var headerSubtitle: String {
        let model = env.localAI.modelStore.selectedLLMModel.displayName
        if let project = store.selectedProject {
            return "\(model) · \(project.displayName) · \(project.branchLabel)"
        }
        return "\(model) · \(String(localized: "No project context"))"
    }

    @ViewBuilder
    private var chatContent: some View {
        Group {
            if store.hasMessages {
                VStack(spacing: 0) {
                    messages
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    bottomComposer
                }
            } else {
                centeredComposer
            }
        }
        .overlay(alignment: .top) {
            errorBanner
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.selectedConversation?.messages ?? []) { message in
                        ChatMessageBubble(message: message)
                            .id(message.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .onChange(of: store.selectedConversation?.messages.map(\.content) ?? []) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
            .onChange(of: store.selectedConversationID) { _, _ in
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = store.lastError {
            Text(error)
                .font(.sora(11))
                .foregroundStyle(Color.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AppSurface.panelFill, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.red.opacity(0.35), lineWidth: 1))
                .padding(.top, 10)
        }
    }

    private var centeredComposer: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            composerPanel
                .padding(.horizontal, 42)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomComposer: some View {
        VStack(spacing: 0) {
            StxRule()
            composerPanel
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
    }

    private var composerPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                composerEditor
                primaryToolbar
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(composerInputFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(composerInputStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)

            contextToolbar
                .padding(.horizontal, 26)
                .padding(.top, 12)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(composerShellFill, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var composerEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $store.draft)
                .font(.sora(15))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(height: 70)
                .disabled(store.isGenerating)

            if store.draft.isEmpty {
                Text("Ask anything")
                    .font(.sora(20, weight: .semibold))
                    .foregroundStyle(Color.stxMuted.opacity(0.46))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 7)
                    .allowsHitTesting(false)
            }
        }
    }

    private var primaryToolbar: some View {
        HStack(spacing: 10) {
            Button {
                store.newConversation(defaultModelID: env.localAI.modelStore.selectedLLMModel.id)
            } label: {
                Image(systemName: AppIcon.Action.add)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("New Chat")

            ChatComposerToolbarLabel(symbol: AppIcon.Action.hand, text: String(localized: "Read-only"), showsChevron: false)

            Spacer(minLength: 12)

            settingsMenu
            modelMenu

            Button {
                if store.isGenerating {
                    store.stopGenerating()
                } else {
                    store.send(
                        endpointProvider: env.localAI,
                        sessions: env.store.sessions,
                        sourceIDs: env.preferences.gitWorkspaceSourceIDs
                    )
                }
            } label: {
                Image(systemName: store.isGenerating ? AppIcon.Action.stop : AppIcon.Navigation.arrowUp)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(sendButtonFill, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!store.isGenerating && !canSend)
            .keyboardShortcut(.return, modifiers: [.command])
            .help(store.isGenerating ? "Stop" : "Send")
        }
    }

    private var contextToolbar: some View {
        HStack(spacing: 22) {
            projectMenu

            Button {
                openLocalAISettings()
            } label: {
                ChatComposerToolbarLabel(
                    symbol: AppIcon.Device.laptop,
                    text: String(localized: "Local mode"),
                    showsChevron: true,
                    maxTextWidth: 120
                )
            }
            .buttonStyle(.plain)
            .help("Local AI")

            if let project = store.selectedProject {
                ChatComposerToolbarLabel(
                    symbol: AppIcon.Workspace.git,
                    text: project.branchLabel,
                    showsChevron: true,
                    maxTextWidth: 160
                )
            }

            Spacer(minLength: 0)
        }
    }

    private var composerInputFill: Color {
        Color.stxDynamic(light: (0.985, 0.982, 0.976), dark: (0.12, 0.12, 0.13))
    }

    private var composerShellFill: Color {
        Color.stxDynamic(light: (0.91, 0.90, 0.875), dark: (0.075, 0.075, 0.082))
    }

    private var composerInputStroke: Color {
        Color.stxDynamic(light: (0.78, 0.77, 0.74), dark: (1, 1, 1)).opacity(0.48)
    }

    private var canSend: Bool {
        env.localAI.localLLMAvailable && !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendButtonFill: Color {
        if store.isGenerating { return Color.red.opacity(0.82) }
        return canSend ? Color.stxAccent : Color.gray.opacity(0.55)
    }

    private var projectMenu: some View {
        Menu {
            Button("No Project Context") {
                store.selectProject(nil)
            }
            if !store.projectOptions.isEmpty {
                Divider()
            }
            ForEach(store.projectOptions) { project in
                Button {
                    store.selectProject(project.id)
                } label: {
                    Label(project.displayName, systemImage: store.selectedProjectID == project.id ? "checkmark" : "folder")
                }
            }
        } label: {
            ChatComposerToolbarLabel(
                symbol: AppIcon.Resource.folder,
                text: store.selectedProject?.displayName ?? String(localized: "No Project"),
                showsChevron: true,
                maxTextWidth: 180
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var modelMenu: some View {
        Menu {
            ForEach(env.localAI.modelStore.llmModels) { model in
                Button {
                    env.localAI.modelStore.select(modelID: model.id, kind: .llm)
                } label: {
                    Label(model.displayName, systemImage: model.id == env.localAI.modelStore.selectedLLMModel.id ? "checkmark" : "cpu")
                }
                .disabled(env.localAI.modelStore.installState(for: model.id).phase != .installed)
            }
        } label: {
            ChatComposerToolbarLabel(
                symbol: nil,
                text: env.localAI.modelStore.selectedLLMModel.displayName,
                showsChevron: true,
                maxTextWidth: 160,
                prominence: .strong
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var settingsMenu: some View {
        Menu {
            Button("Temperature 0.2") { updateSettings(temperature: 0.2) }
            Button("Temperature 0.4") { updateSettings(temperature: 0.4) }
            Button("Temperature 0.7") { updateSettings(temperature: 0.7) }
            Divider()
            Button("512 tokens") { updateSettings(maxTokens: 512) }
            Button("768 tokens") { updateSettings(maxTokens: 768) }
            Button("1024 tokens") { updateSettings(maxTokens: 1024) }
        } label: {
            ChatComposerToolbarLabel(
                symbol: nil,
                text: settingsLabel,
                showsChevron: true,
                maxTextWidth: 112,
                prominence: .strong
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var settingsLabel: String {
        let settings = store.selectedConversation?.settings ?? .default
        return "\(String(format: "%.1f", settings.temperature)) · \(settings.maxTokens)"
    }

    private func updateSettings(temperature: Double? = nil, maxTokens: Int? = nil) {
        var settings = store.selectedConversation?.settings ?? .default
        if let temperature { settings.temperature = temperature }
        if let maxTokens { settings.maxTokens = maxTokens }
        store.updateSettings(settings)
    }

    private func openLocalAISettings() {
        NotificationCenter.default.post(name: .openSettingsInMainWindow, object: SettingsSection.localAI)
    }
}

private struct ChatMessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: isUser ? "person.crop.circle" : "cpu")
                        .font(.system(size: 11, weight: .semibold))
                    Text(message.role.displayName)
                        .font(.sora(11, weight: .semibold))
                }
                .foregroundStyle(isUser ? Color.white.opacity(0.82) : Color.stxMuted)

                Text(message.content.isEmpty ? "..." : message.content)
                    .font(.sora(13))
                    .foregroundStyle(isUser ? Color.white : Color.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: 680, alignment: .leading)
            .background(bubbleFill, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(bubbleStroke, lineWidth: 1))
            if !isUser { Spacer(minLength: 80) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var bubbleFill: Color {
        isUser ? Color.stxAccent.opacity(0.88) : Color.primary.opacity(0.055)
    }

    private var bubbleStroke: Color {
        isUser ? Color.white.opacity(0.16) : Color.stxStroke.opacity(0.75)
    }
}

private struct ChatComposerToolbarLabel: View {
    enum Prominence {
        case normal
        case strong
    }

    let symbol: String?
    let text: String
    var showsChevron = false
    var maxTextWidth: CGFloat?
    var prominence: Prominence = .normal

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
            }
            Text(text)
                .font(.sora(prominence == .strong ? 16 : 15, weight: prominence == .strong ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: maxTextWidth, alignment: .leading)
            if showsChevron {
                Image(systemName: AppIcon.Navigation.down)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundStyle(prominence == .strong ? Color.primary.opacity(0.82) : Color.stxMuted.opacity(0.82))
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("Chat workspace") {
    ChatWorkspaceView(store: AppEnvironment.preview().chat)
        .environment(AppEnvironment.preview())
        .frame(width: 900, height: 640)
        .background(Color.stxBackground)
}
#endif
