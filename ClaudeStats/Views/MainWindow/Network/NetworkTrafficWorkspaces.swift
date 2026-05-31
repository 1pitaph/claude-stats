import AppKit
import SwiftUI

private enum NetworkWorkspacePaneMetrics {
    static let webSocketSessionMinWidth: CGFloat = 220
    static let webSocketMessageMinWidth: CGFloat = 320
    static let webSocketInspectorMinWidth: CGFloat = 320
    static let webSocketDetailMinWidth = webSocketMessageMinWidth + webSocketInspectorMinWidth
    static let replaySessionMinWidth: CGFloat = 240
    static let replayEditorMinWidth: CGFloat = 360
    static let replayRequestEditorMinHeight: CGFloat = 260
    static let replayResultsMinHeight: CGFloat = 160
    static let interceptQueueMinWidth: CGFloat = 260
    static let interceptEditorMinWidth: CGFloat = 360
    static let automateEditorMinWidth: CGFloat = 320
    static let automateResultsMinWidth: CGFloat = 280

    static let webSocketOuterSplitConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: webSocketSessionMinWidth,
        secondaryMinimumPaneLength: webSocketDetailMinWidth
    )
    static let webSocketDetailSplitConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: webSocketMessageMinWidth,
        secondaryMinimumPaneLength: webSocketInspectorMinWidth
    )
    static let replayOuterSplitConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: replaySessionMinWidth,
        secondaryMinimumPaneLength: replayEditorMinWidth
    )
    static let replayEditorResultsSplitConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: replayRequestEditorMinHeight,
        secondaryMinimumPaneLength: replayResultsMinHeight
    )
    static let interceptOuterSplitConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: interceptQueueMinWidth,
        secondaryMinimumPaneLength: interceptEditorMinWidth
    )
    static let automateOuterSplitConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: automateEditorMinWidth,
        secondaryMinimumPaneLength: automateResultsMinWidth
    )
}

struct NetworkWebSocketWorkspace: View {
    @Bindable var store: NetworkDebuggerStore
    @State private var selectedInspector = WebSocketInspectorTab.overview

    var body: some View {
        HoverableSplitView(
            axis: .vertical,
            primaryFraction: 0.28,
            configuration: NetworkWorkspacePaneMetrics.webSocketOuterSplitConfiguration
        ) {
            sessionList
                .frame(
                    minWidth: 0,
                    idealWidth: 280,
                    maxWidth: .infinity
                )
        } secondary: {
            HoverableSplitView(
                axis: .vertical,
                primaryFraction: 0.48,
                configuration: NetworkWorkspacePaneMetrics.webSocketDetailSplitConfiguration
            ) {
                messageList
                    .frame(
                        minWidth: 0,
                        idealWidth: 420,
                        maxWidth: .infinity
                    )
            } secondary: {
                inspector
                    .frame(
                        minWidth: 0,
                        idealWidth: 420,
                        maxWidth: .infinity
                    )
            }
            .frame(minWidth: 0, maxWidth: .infinity)
        }
        .task {
            if let session = store.selectedWebSocketSession {
                store.selectWebSocketSession(session)
            }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspaceHeader("Connections", symbol: AppIcon.Network.webSocket)
            StxRule()
            AppScrollView {
                VStack(spacing: 6) {
                    ForEach(store.webSocketSessions) { session in
                        Button {
                            store.selectWebSocketSession(session)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("#\(session.number)")
                                        .font(.sora(10).monospacedDigit())
                                        .foregroundStyle(Color.stxMuted)
                                    Text(session.domain)
                                        .font(.sora(11, weight: .semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Circle()
                                        .fill(session.isActive ? Color.green : Color.stxMuted.opacity(0.45))
                                        .frame(width: 7, height: 7)
                                }
                                Text(session.url)
                                    .font(.sora(9))
                                    .foregroundStyle(Color.stxMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                HStack(spacing: 8) {
                                    Label("\(session.sentCount)", systemImage: AppIcon.Navigation.arrowUp)
                                    Label("\(session.receivedCount)", systemImage: AppIcon.Navigation.arrowDown)
                                    Spacer()
                                    Text(session.lastActivityAt.formatted(date: .omitted, time: .standard))
                                }
                                .font(.sora(9))
                                .foregroundStyle(Color.stxMuted)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                if store.selectedWebSocketSessionID == session.id {
                                    RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.10))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if store.webSocketSessions.isEmpty {
                        NetworkWorkspaceEmptyState("No WebSocket sessions captured yet.")
                    }
                }
                .padding(10)
            }
        }
        .background(Color.primary.opacity(0.025))
    }

    private var messageList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                workspaceHeader("Messages", symbol: AppIcon.Resource.textBubble)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                AppSelect(
                    .localized("Opcode"),
                    selection: $store.webSocketFilter.opcode,
                    options: NetworkWebSocketOpcodeFilter.allCases.map { filter in
                        AppSelectOption(value: filter, title: .localized(filter.title))
                    },
                    width: 110,
                    size: .small
                )
            }
            .padding(.trailing, 10)

            HStack {
                Image(systemName: AppIcon.Action.search)
                    .foregroundStyle(Color.stxMuted)
                TextField("Search payload", text: $store.webSocketFilter.query)
                    .textFieldStyle(.plain)
            }
            .font(.sora(11))
            .padding(8)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            webSocketDirectionTabs
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            StxRule()

            AppScrollView {
                VStack(spacing: 4) {
                    ForEach(store.filteredWebSocketMessages) { message in
                        Button {
                            store.selectedWebSocketMessageID = message.id
                        } label: {
                            HStack(spacing: 8) {
                                Text(message.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.sora(9).monospacedDigit())
                                    .foregroundStyle(Color.stxMuted)
                                    .frame(width: 74, alignment: .leading)
                                Text(message.displayDirection)
                                    .font(.sora(10, weight: .semibold))
                                    .foregroundStyle(message.direction == .sent ? Color.blue : Color.green)
                                    .frame(width: 62, alignment: .leading)
                                Text(message.opcode.uppercased())
                                    .font(.sora(9, weight: .semibold))
                                    .foregroundStyle(Color.stxMuted)
                                    .frame(width: 54, alignment: .leading)
                                Text(message.payloadText.isEmpty ? "\(message.payloadBytes) bytes" : message.payloadText)
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                if message.isInjected {
                                    Image(systemName: AppIcon.Action.sendFilled)
                                        .foregroundStyle(Color.stxAccent)
                                }
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 30)
                            .background {
                                if store.selectedWebSocketMessageID == message.id {
                                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.10))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if store.filteredWebSocketMessages.isEmpty {
                        NetworkWorkspaceEmptyState("No matching WebSocket messages.")
                    }
                }
                .padding(10)
            }
        }
        .background(Color.primary.opacity(0.025))
    }

    private var webSocketDirectionTabs: some View {
        FadingLine(fadeWidth: 24) {
            HStack(spacing: 14) {
                ForEach(NetworkWebSocketDirectionFilter.allCases) { filter in
                    webSocketTextTab(
                        title: filter.title,
                        isSelected: store.webSocketFilter.direction == filter
                    ) {
                        store.webSocketFilter.direction = filter
                    }
                }
            }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                workspaceHeader("Inspector", symbol: AppIcon.Navigation.sidebarRight)
                    .frame(minWidth: 0, idealWidth: 128, maxWidth: 128, alignment: .leading)
                FadingLine(fadeWidth: 28) {
                    HStack(spacing: 14) {
                        ForEach(WebSocketInspectorTab.allCases) { tab in
                            webSocketTextTab(
                                title: tab.title,
                                isSelected: selectedInspector == tab
                            ) {
                                selectedInspector = tab
                            }
                        }
                    }
                }
            }
            .padding(.trailing, 10)
            StxRule()
            AppScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let message = store.selectedWebSocketMessage {
                        Text(inspectorText(message))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.86))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        NetworkWorkspaceEmptyState("Select a WebSocket message.")
                    }
                }
                .padding(14)
            }
            StxRule()
            sendComposer
                .padding(12)
        }
        .background(Color.primary.opacity(0.025))
    }

    private var sendComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SEND MESSAGE")
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                Spacer()
                AppSelect(
                    .localized("Opcode"),
                    selection: $store.webSocketSendDraft.opcode,
                    options: [
                        AppSelectOption(value: "text", title: .localized("Text")),
                        AppSelectOption(value: "json", title: .localized("JSON")),
                        AppSelectOption(value: "binary", title: .localized("Binary")),
                    ],
                    width: 100,
                    size: .small
                )
                Button {
                    store.sendWebSocketMessage()
                } label: {
                    Label("Send", systemImage: AppIcon.Action.send)
                }
                .disabled(store.selectedWebSocketSession?.isActive != true || store.webSocketSendDraft.payloadText.isEmpty)
            }
            TextEditor(text: $store.webSocketSendDraft.payloadText)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 70)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            if store.selectedWebSocketSession?.isActive != true {
                FadingLineText(
                    "Closed sessions cannot send new WebSocket messages.",
                    font: .sora(10),
                    foregroundStyle: Color.stxMuted,
                    fadeWidth: 28
                )
            }
        }
    }

    private func inspectorText(_ message: NetworkWebSocketMessage) -> String {
        switch selectedInspector {
        case .overview:
            return [
                "Direction: \(message.displayDirection)",
                "Opcode: \(message.opcode)",
                "Bytes: \(message.payloadBytes)",
                "Final: \(message.isFinal ? "Yes" : "No")",
                "Injected: \(message.isInjected ? "Yes" : "No")",
                "Time: \(message.timestamp.formatted(date: .abbreviated, time: .standard))",
            ].joined(separator: "\n")
        case .json:
            return prettyJSON(message.payloadText).nonEmpty(or: "Payload is not valid JSON.")
        case .raw:
            return message.payloadText.nonEmpty(or: "\(message.payloadBytes) binary bytes")
        case .hex:
            return Data(message.payloadText.utf8).prefix(1024).enumerated().map { offset, byte in
                String(format: "%02X%@", byte, (offset + 1) % 16 == 0 ? "\n" : " ")
            }.joined()
        case .timing:
            return "Timestamp: \(message.timestamp.formatted(date: .complete, time: .standard))"
        }
    }
}

struct NetworkReplayWorkspace: View {
    @Bindable var store: NetworkDebuggerStore

    var body: some View {
        HoverableSplitView(
            axis: .vertical,
            primaryFraction: 0.28,
            configuration: NetworkWorkspacePaneMetrics.replayOuterSplitConfiguration
        ) {
            sessionList
                .frame(
                    minWidth: NetworkWorkspacePaneMetrics.replaySessionMinWidth,
                    idealWidth: 280,
                    maxWidth: .infinity
                )
        } secondary: {
            editor
                .frame(minWidth: NetworkWorkspacePaneMetrics.replayEditorMinWidth, maxWidth: .infinity)
        }
        .task {
            if store.replaySessions.isEmpty {
                store.createComposeSession()
            }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                workspaceHeader("Replay Sessions", symbol: AppIcon.Action.refresh)
                Spacer()
                Button {
                    store.createComposeSession()
                } label: {
                    Image(systemName: AppIcon.Action.add)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 12)
            StxRule()
            AppScrollView {
                VStack(spacing: 6) {
                    ForEach(store.replaySessions) { session in
                        Button {
                            store.selectedReplaySessionID = session.id
                            store.replayDraft = session.draft
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title)
                                    .font(.sora(11, weight: .semibold))
                                    .lineLimit(1)
                                Text(session.draft.url)
                                    .font(.sora(9))
                                    .foregroundStyle(Color.stxMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                HStack {
                                    Text(session.source.rawValue)
                                    Spacer()
                                    Text("\(session.results.count) runs")
                                }
                                .font(.sora(9))
                                .foregroundStyle(Color.stxMuted)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                if store.selectedReplaySessionID == session.id {
                                    RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.10))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
            StxRule()
            importCard
                .padding(10)
        }
        .background(Color.primary.opacity(0.025))
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IMPORT")
                .font(.sora(10, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            AppSelect(
                .localized("Format"),
                selection: $store.importRequestFormat,
                options: NetworkRequestImportFormat.allCases.map { format in
                    AppSelectOption(value: format, title: .localized(format.title))
                },
                width: 160,
                size: .small
            )
            TextEditor(text: $store.importRequestText)
                .font(.system(size: 10, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 70)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            Button {
                store.importRequestToReplay()
            } label: {
                Label("Import to Replay", systemImage: AppIcon.Action.importFile)
            }
            .disabled(store.importRequestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .font(.sora(11))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                workspaceHeader("Request Editor", symbol: AppIcon.Action.compose)
                Spacer()
                Button {
                    store.sendSelectedReplaySession()
                } label: {
                    Label("Send", systemImage: AppIcon.Action.send)
                }
                .disabled(store.selectedReplaySession == nil || store.isReplayWorking)
            }
            .padding(.trailing, 14)
            StxRule()
            if store.selectedReplaySession != nil {
                HoverableSplitView(
                    axis: .horizontal,
                    primaryFraction: 0.64,
                    configuration: NetworkWorkspacePaneMetrics.replayEditorResultsSplitConfiguration
                ) {
                    requestEditor
                        .frame(minHeight: NetworkWorkspacePaneMetrics.replayRequestEditorMinHeight, maxHeight: .infinity)
                } secondary: {
                    resultList
                        .frame(minHeight: NetworkWorkspacePaneMetrics.replayResultsMinHeight, maxHeight: .infinity)
                }
            } else {
                NetworkWorkspaceEmptyState("Create or import a replay session.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.primary.opacity(0.025))
    }

    private var requestEditor: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("Method", text: replayBinding(\.method))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                    TextField("URL", text: replayBinding(\.url))
                        .textFieldStyle(.roundedBorder)
                }

                Text("HEADERS")
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                ForEach(store.selectedReplaySession?.draft.headers ?? []) { header in
                    HStack(spacing: 8) {
                        TextField("Name", text: headerBinding(header.id, \.name))
                            .textFieldStyle(.roundedBorder)
                        TextField("Value", text: headerBinding(header.id, \.value))
                            .textFieldStyle(.roundedBorder)
                        Button {
                            removeHeader(header.id)
                        } label: {
                            Image(systemName: AppIcon.Action.removeCircle)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    addHeader()
                } label: {
                    Label("Add Header", systemImage: AppIcon.Action.addCircle)
                }
                .buttonStyle(.borderless)

                Text("BODY")
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                TextEditor(text: replayBinding(\.bodyText))
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(14)
        }
    }

    private var resultList: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("RESULTS")
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                ForEach(store.selectedReplaySession?.results ?? []) { result in
                    HStack(spacing: 8) {
                        Text(result.statusCode.map(String.init) ?? "ERR")
                            .font(.sora(11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(result.errorMessage == nil ? Color.green : Color.red)
                            .frame(width: 46, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.errorMessage ?? ByteCountFormatter.string(fromByteCount: Int64(result.responseBytes), countStyle: .file))
                                .font(.sora(10))
                                .lineLimit(1)
                            Text("\(Int((result.duration * 1000).rounded())) ms")
                                .font(.sora(9))
                                .foregroundStyle(Color.stxMuted)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                }
                if store.selectedReplaySession?.results.isEmpty != false {
                    NetworkWorkspaceEmptyState("Send the request to capture a replay result.")
                }
            }
            .padding(14)
        }
    }

    private func replayBinding<Value>(_ keyPath: WritableKeyPath<NetworkReplayDraft, Value>) -> Binding<Value> {
        Binding {
            store.selectedReplaySession?.draft[keyPath: keyPath] ?? NetworkReplayDraft(
                sourceFlowID: UUID(),
                method: "GET",
                url: "",
                headers: [],
                bodyText: "",
                contentType: nil
            )[keyPath: keyPath]
        } set: { value in
            store.updateSelectedReplayDraft { $0[keyPath: keyPath] = value }
        }
    }

    private func headerBinding(
        _ id: String,
        _ keyPath: WritableKeyPath<NetworkHeaderPair, String>
    ) -> Binding<String> {
        Binding {
            store.selectedReplaySession?.draft.headers.first { $0.id == id }?[keyPath: keyPath] ?? ""
        } set: { value in
            store.updateSelectedReplayDraft { draft in
                guard let index = draft.headers.firstIndex(where: { $0.id == id }) else { return }
                draft.headers[index][keyPath: keyPath] = value
            }
        }
    }

    private func addHeader() {
        store.updateSelectedReplayDraft {
            $0.headers.append(NetworkHeaderPair(name: "Header", value: ""))
        }
    }

    private func removeHeader(_ id: String) {
        store.updateSelectedReplayDraft {
            $0.headers.removeAll { $0.id == id }
        }
    }
}

struct NetworkInterceptWorkspace: View {
    @Bindable var store: NetworkDebuggerStore

    var body: some View {
        HoverableSplitView(
            axis: .vertical,
            primaryFraction: 0.32,
            configuration: NetworkWorkspacePaneMetrics.interceptOuterSplitConfiguration
        ) {
            queueList
                .frame(minWidth: 0, idealWidth: 320, maxWidth: .infinity)
        } secondary: {
            editor
                .frame(minWidth: 0, idealWidth: 520, maxWidth: .infinity)
        }
        .task {
            store.refreshInterceptQueue()
        }
    }

    private var queueList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                workspaceHeader("Intercept Queue", symbol: AppIcon.Action.pause)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                workspaceAdaptiveActionPair(
                    maxWidth: 260,
                    firstTitle: "Forward All",
                    firstSymbol: "play.fill",
                    firstDisabled: store.breakpoints.isEmpty,
                    firstAction: { store.forwardAllIntercepts() },
                    secondTitle: "Drop All",
                    secondSymbol: "xmark",
                    secondDisabled: store.breakpoints.isEmpty,
                    secondAction: { store.dropAllIntercepts() }
                )
            }
            .padding(.trailing, 12)
            StxRule()
            AppScrollView {
                VStack(spacing: 6) {
                    ForEach(store.breakpoints) { item in
                        Button {
                            store.selectedBreakpointID = item.id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.method.uppercased())
                                        .font(.sora(10, weight: .semibold))
                                    Text(item.phase.rawValue.capitalized)
                                        .font(.sora(9))
                                        .foregroundStyle(Color.stxMuted)
                                    Spacer()
                                    Text(item.createdAt.formatted(date: .omitted, time: .standard))
                                        .font(.sora(9).monospacedDigit())
                                        .foregroundStyle(Color.stxMuted)
                                }
                                Text(item.url)
                                    .font(.sora(10))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                if store.selectedBreakpointID == item.id {
                                    RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.10))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if store.breakpoints.isEmpty {
                        NetworkWorkspaceEmptyState("No intercepted requests are waiting.")
                    }
                }
                .padding(10)
            }
        }
        .background(Color.primary.opacity(0.025))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                workspaceHeader("Intercept Editor", symbol: AppIcon.Action.compose)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                workspaceAdaptiveActionPair(
                    maxWidth: 180,
                    firstTitle: "Forward",
                    firstSymbol: "play.fill",
                    firstDisabled: store.selectedBreakpointID == nil,
                    firstAction: { store.forwardSelectedIntercept() },
                    secondTitle: "Drop",
                    secondSymbol: "xmark",
                    secondDisabled: store.selectedBreakpointID == nil,
                    secondAction: { store.dropSelectedIntercept() }
                )
            }
            .padding(.trailing, 14)
            StxRule()
            if store.selectedBreakpointID != nil {
                AppScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("Method", text: interceptBinding(\.method))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 96)
                            TextField("URL", text: interceptBinding(\.url))
                                .textFieldStyle(.roundedBorder)
                        }
                        Text("HEADERS")
                            .font(.sora(10, weight: .semibold))
                            .foregroundStyle(Color.stxMuted)
                        ForEach(selectedIntercept?.headers ?? []) { header in
                            HStack {
                                Text(header.name)
                                    .font(.system(size: 10, design: .monospaced))
                                    .frame(width: 140, alignment: .leading)
                                Text(header.value)
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }
                        }
                        Text("BODY")
                            .font(.sora(10, weight: .semibold))
                            .foregroundStyle(Color.stxMuted)
                        TextEditor(text: interceptBinding(\.body))
                            .font(.system(size: 11, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 180)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(14)
                }
            } else {
                NetworkWorkspaceEmptyState("Select an intercepted request.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.primary.opacity(0.025))
    }

    private var selectedIntercept: NetworkBreakpointItem? {
        guard let id = store.selectedBreakpointID else { return nil }
        return store.breakpoints.first { $0.id == id }
    }

    private func interceptBinding(_ keyPath: WritableKeyPath<NetworkBreakpointItem, String>) -> Binding<String> {
        Binding {
            selectedIntercept?[keyPath: keyPath] ?? ""
        } set: { value in
            store.updateSelectedIntercept {
                $0[keyPath: keyPath] = value
            }
        }
    }
}

struct NetworkAutomateWorkspace: View {
    @Bindable var store: NetworkDebuggerStore

    var body: some View {
        HoverableSplitView(
            axis: .vertical,
            primaryFraction: 0.46,
            configuration: NetworkWorkspacePaneMetrics.automateOuterSplitConfiguration
        ) {
            editor
                .frame(minWidth: 0, idealWidth: 460, maxWidth: .infinity)
        } secondary: {
            results
                .frame(minWidth: 0, idealWidth: 360, maxWidth: .infinity)
        }
        .task {
            if store.automateDraft == nil, let flow = store.selectedFlow {
                store.sendFlowToAutomate(flow)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                workspaceHeader("Automate", symbol: AppIcon.Network.automate)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                workspaceActionStrip(maxWidth: 92) {
                    Button {
                        store.runAutomate()
                    } label: {
                        Label("Run", systemImage: AppIcon.Action.start)
                    }
                    .disabled(store.automateDraft == nil || store.isAutomateWorking)
                }
            }
            .padding(.trailing, 14)
            StxRule()

            AppScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.automateDraft != nil {
                        HStack {
                            TextField("Method", text: automateBinding(\.baseDraft.method))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 96)
                            TextField("URL", text: automateBinding(\.baseDraft.url))
                                .textFieldStyle(.roundedBorder)
                        }
                        Text("Use {{value}} in URL, headers, or body. Each line below creates one request.")
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                        TextEditor(text: firstVariableValuesBinding)
                            .font(.system(size: 11, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(height: 120)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        Stepper("Concurrency: \(store.automateDraft?.concurrencyLimit ?? 1)", value: concurrencyBinding, in: 1...8)
                            .font(.sora(11))
                        TextEditor(text: automateBinding(\.baseDraft.bodyText))
                            .font(.system(size: 11, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 160)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    } else {
                        NetworkWorkspaceEmptyState("Select a flow and send it to Automate.")
                    }
                }
                .padding(14)
            }
        }
        .background(Color.primary.opacity(0.025))
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspaceHeader("Results", symbol: AppIcon.Metric.chart)
            StxRule()
            AppScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.automateResults) { result in
                        HStack(spacing: 10) {
                            Text("#\(result.requestIndex + 1)")
                                .font(.sora(10).monospacedDigit())
                                .foregroundStyle(Color.stxMuted)
                                .frame(width: 42, alignment: .leading)
                            Text(result.statusCode.map(String.init) ?? "ERR")
                                .font(.sora(11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(result.errorMessage == nil ? Color.green : Color.red)
                                .frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.url)
                                    .font(.sora(10))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(result.errorMessage ?? "\(Int(((result.duration ?? 0) * 1000).rounded())) ms · \(ByteCountFormatter.string(fromByteCount: Int64(result.responseBytes), countStyle: .file))")
                                    .font(.sora(9))
                                    .foregroundStyle(Color.stxMuted)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                    }
                    if store.automateResults.isEmpty {
                        NetworkWorkspaceEmptyState("Run automate to see request results.")
                    }
                }
                .padding(14)
            }
        }
        .background(Color.primary.opacity(0.025))
    }

    private func automateBinding<Value>(_ keyPath: WritableKeyPath<NetworkAutomateDraft, Value>) -> Binding<Value> {
        Binding {
            store.automateDraft?[keyPath: keyPath] ?? NetworkAutomateDraft(
                baseDraft: NetworkReplayDraft(sourceFlowID: UUID(), method: "GET", url: "", headers: [], bodyText: "", contentType: nil)
            )[keyPath: keyPath]
        } set: { value in
            guard store.automateDraft != nil else { return }
            store.automateDraft?[keyPath: keyPath] = value
        }
    }

    private var firstVariableValuesBinding: Binding<String> {
        Binding {
            store.automateDraft?.variables.first?.valuesText ?? ""
        } set: { value in
            guard store.automateDraft != nil else { return }
            if store.automateDraft?.variables.isEmpty == true {
                store.automateDraft?.variables.append(NetworkAutomateVariable(name: "value", valuesText: value))
            } else {
                store.automateDraft?.variables[0].valuesText = value
            }
        }
    }

    private var concurrencyBinding: Binding<Int> {
        Binding {
            store.automateDraft?.concurrencyLimit ?? 1
        } set: { value in
            store.automateDraft?.concurrencyLimit = value
        }
    }
}

private enum WebSocketInspectorTab: String, CaseIterable, Identifiable {
    case overview
    case json
    case raw
    case hex
    case timing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .json: "JSON"
        case .raw: "Raw"
        case .hex: "Hex"
        case .timing: "Timing"
        }
    }
}

private struct NetworkWorkspaceEmptyState: View {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.sora(11))
            .foregroundStyle(Color.stxMuted)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
    }
}

@MainActor
private func workspaceHeader(_ title: String, symbol: String) -> some View {
    HStack(spacing: 8) {
        Image(systemName: symbol)
            .font(.sora(12, weight: .semibold))
            .foregroundStyle(.primary)
            .fixedSize()
        FadingLineText(
            title,
            font: .sora(12, weight: .semibold),
            foregroundStyle: .primary,
            fadeWidth: 28
        )
    }
    .frame(minHeight: 34)
    .padding(.horizontal, 12)
}

@MainActor
private func workspaceActionStrip<Content: View>(
    fadeWidth: CGFloat = 28,
    maxWidth: CGFloat,
    @ViewBuilder content: () -> Content
) -> some View {
    FadingLine(fadeWidth: fadeWidth) {
        HStack(spacing: 8) {
            content()
        }
    }
    .frame(minWidth: 0, idealWidth: maxWidth, maxWidth: maxWidth, alignment: .leading)
}

@MainActor
private func workspaceAdaptiveActionPair(
    maxWidth: CGFloat,
    firstTitle: String,
    firstSymbol: String,
    firstDisabled: Bool,
    firstAction: @escaping () -> Void,
    secondTitle: String,
    secondSymbol: String,
    secondDisabled: Bool,
    secondAction: @escaping () -> Void
) -> some View {
    ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
            workspaceAdaptiveActionButton(
                title: firstTitle,
                symbol: firstSymbol,
                showsTitle: true,
                isDisabled: firstDisabled,
                action: firstAction
            )
            workspaceAdaptiveActionButton(
                title: secondTitle,
                symbol: secondSymbol,
                showsTitle: true,
                isDisabled: secondDisabled,
                action: secondAction
            )
        }

        HStack(spacing: 8) {
            workspaceAdaptiveActionButton(
                title: firstTitle,
                symbol: firstSymbol,
                showsTitle: false,
                isDisabled: firstDisabled,
                action: firstAction
            )
            workspaceAdaptiveActionButton(
                title: secondTitle,
                symbol: secondSymbol,
                showsTitle: false,
                isDisabled: secondDisabled,
                action: secondAction
            )
        }
    }
    .frame(minWidth: 0, idealWidth: maxWidth, maxWidth: maxWidth, alignment: .trailing)
}

@MainActor
private func workspaceAdaptiveActionButton(
    title: String,
    symbol: String,
    showsTitle: Bool,
    isDisabled: Bool,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        if showsTitle {
            Label(title, systemImage: symbol)
        } else {
            Image(systemName: symbol)
                .frame(width: 18)
        }
    }
    .disabled(isDisabled)
    .help(title)
    .accessibilityLabel(Text(title))
}

@MainActor
private func webSocketTextTab(
    title: String,
    isSelected: Bool,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Text(title)
            .font(.sora(10, weight: .medium))
            .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
    }
    .buttonStyle(.plain)
    .help(title)
}

private func prettyJSON(_ text: String) -> String {
    guard let data = text.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let output = String(data: pretty, encoding: .utf8)
    else {
        return ""
    }
    return output
}

private extension String {
    func nonEmpty(or fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
