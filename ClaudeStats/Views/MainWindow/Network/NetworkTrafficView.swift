import AppKit
import SwiftUI

struct NetworkTrafficView: View {
    @Bindable var store: NetworkDebuggerStore
    @Bindable var preferences: Preferences

    var body: some View {
        VStack(spacing: 0) {
            NetworkTrafficWorkspaceBar(store: store)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            StxRule()
            workspaceContent
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch store.selectedTrafficWorkspace {
        case .httpTraffic:
            GeometryReader { proxy in
                switch preferences.networkTrafficLayoutMode.resolved(
                    width: Double(proxy.size.width),
                    breakpoint: preferences.networkTrafficAutoBreakpoint
                ) {
                case .sideBySide:
                    sideBySideLayout
                case .stacked:
                    stackedLayout
                }
            }
        case .webSocket:
            NetworkWebSocketWorkspace(store: store)
        case .replay:
            NetworkReplayWorkspace(store: store)
        case .intercept:
            NetworkInterceptWorkspace(store: store)
        case .automate:
            NetworkAutomateWorkspace(store: store)
        }
    }

    private var sideBySideLayout: some View {
        HoverableSplitView(
            axis: .vertical,
            primaryFraction: 0.64,
            configuration: NetworkTrafficPaneMetrics.sideBySideSplitConfiguration
        ) {
            trafficTable
                .frame(
                    minWidth: NetworkTrafficPaneMetrics.tableMinWidth,
                    idealWidth: 720,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
        } secondary: {
            inspector(.vertical)
                .frame(
                    minWidth: NetworkTrafficPaneMetrics.inspectorMinWidth,
                    idealWidth: 430,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
        }
    }

    private var stackedLayout: some View {
        GeometryReader { proxy in
            HoverableSplitView(
                axis: .horizontal,
                primaryFraction: 0.46,
                configuration: NetworkTrafficPaneMetrics.stackedSplitConfiguration(for: proxy.size.height)
            ) {
                trafficTable
                    .frame(minHeight: 0, maxHeight: .infinity)
            } secondary: {
                inspector(.horizontal)
                    .frame(
                        minHeight: 0,
                        idealHeight: 340,
                        maxHeight: .infinity
                    )
            }
        }
    }

    private var trafficTable: some View {
        NetworkTrafficTable(store: store)
            .frame(maxHeight: .infinity)
    }

    private func inspector(_ arrangement: NetworkInspectorPaneArrangement) -> some View {
        NetworkFlowInspector(store: store, arrangement: arrangement)
    }
}

private enum NetworkInspectorPaneArrangement {
    case vertical
    case horizontal
}

private enum NetworkTrafficPaneMetrics {
    static let tableMinWidth: CGFloat = 420
    static let inspectorMinWidth: CGFloat = 360
    static let tableMinHeight: CGFloat = 220
    static let inspectorMinHeight: CGFloat = 280
    static let tableHeaderSafeMinHeight: CGFloat = 72
    static let requestPayloadMinHeight: CGFloat = 170
    static let responsePayloadMinHeight: CGFloat = 170
    static let payloadMinWidth: CGFloat = 260

    static let sideBySideSplitConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: tableMinWidth,
        secondaryMinimumPaneLength: inspectorMinWidth
    )
    static let stackedSplitConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: tableMinHeight,
        secondaryMinimumPaneLength: inspectorMinHeight
    )
    static func stackedSplitConfiguration(for availableHeight: CGFloat) -> HoverableSplitViewConfiguration {
        guard availableHeight.isFinite, availableHeight > 0 else {
            return stackedSplitConfiguration
        }

        if availableHeight <= tableHeaderSafeMinHeight {
            return HoverableSplitViewConfiguration(
                primaryMinimumPaneLength: availableHeight,
                secondaryMinimumPaneLength: 0
            )
        }

        let desiredTableExtra = max(tableMinHeight - tableHeaderSafeMinHeight, 0)
        let desiredFlexibleHeight = desiredTableExtra + inspectorMinHeight
        let availableFlexibleHeight = availableHeight - tableHeaderSafeMinHeight
        let scale = min(availableFlexibleHeight / desiredFlexibleHeight, 1)

        return HoverableSplitViewConfiguration(
            primaryMinimumPaneLength: tableHeaderSafeMinHeight + desiredTableExtra * scale,
            secondaryMinimumPaneLength: inspectorMinHeight * scale
        )
    }
    static let verticalInspectorSplitConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: requestPayloadMinHeight,
        secondaryMinimumPaneLength: responsePayloadMinHeight
    )
    static let horizontalInspectorSplitConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: payloadMinWidth,
        secondaryMinimumPaneLength: payloadMinWidth
    )
}

private struct NetworkTrafficWorkspaceBar: View {
    @Bindable var store: NetworkDebuggerStore

    var body: some View {
        HStack(spacing: 6) {
            ForEach(NetworkTrafficWorkspace.allCases) { workspace in
                Button {
                    store.selectedTrafficWorkspace = workspace
                    if workspace == .intercept {
                        store.refreshInterceptQueue()
                    }
                } label: {
                    Label(workspace.title, systemImage: workspace.symbol)
                        .font(.sora(11, weight: store.selectedTrafficWorkspace == workspace ? .semibold : .medium))
                        .foregroundStyle(store.selectedTrafficWorkspace == workspace ? Color.stxAccent : Color.stxMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background {
                            if store.selectedTrafficWorkspace == workspace {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.stxAccent.opacity(0.13))
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(workspace.title)
            }

            Spacer(minLength: 8)

            if store.selectedTrafficWorkspace == .replay {
                Button {
                    store.createComposeSession()
                } label: {
                    Label("Compose", systemImage: AppIcon.Action.add)
                }
                .controlSize(.small)
            } else if store.selectedTrafficWorkspace == .automate, let flow = store.selectedFlow {
                Button {
                    store.sendFlowToAutomate(flow)
                } label: {
                    Label("Use Selected", systemImage: AppIcon.Action.send)
                }
                .controlSize(.small)
            }
        }
    }
}

struct NetworkTrafficLayoutControls: View {
    @Bindable var preferences: Preferences
    @State private var showingAutoSettings = false

    var body: some View {
        PillSegmentedBar(
            NetworkTrafficLayoutMode.allCases,
            selection: $preferences.networkTrafficLayoutMode,
            help: { $0.help },
            accessibilityLabel: { $0.title },
            onSelect: { mode in
                showingAutoSettings = mode == .automatic
            }
        ) { mode, _ in
            Image(systemName: mode.symbol)
                .frame(width: 26)
        }
        .popover(isPresented: $showingAutoSettings, arrowEdge: .bottom) {
            NetworkTrafficAutoLayoutPopover(preferences: preferences)
                .padding(14)
                .frame(width: 260)
        }
    }
}

private struct NetworkTrafficAutoLayoutPopover: View {
    @Bindable var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("AUTO BREAKPOINT")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.stxMuted)

                Spacer(minLength: 8)

                Text("\(Int(preferences.networkTrafficAutoBreakpoint.rounded())) pt")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.primary.opacity(0.82))
            }

            Slider(
                value: $preferences.networkTrafficAutoBreakpoint,
                in: NetworkTrafficLayoutConstants.minimumAutoBreakpoint...NetworkTrafficLayoutConstants.maximumAutoBreakpoint,
                step: NetworkTrafficLayoutConstants.autoBreakpointStep
            )
            .controlSize(.small)

            HStack(spacing: 8) {
                Text("\(Int(NetworkTrafficLayoutConstants.minimumAutoBreakpoint))")
                Spacer()
                Text("\(Int(NetworkTrafficLayoutConstants.maximumAutoBreakpoint))")
            }
            .font(.sora(9).monospacedDigit())
            .foregroundStyle(Color.stxMuted.opacity(0.8))

            Button {
                preferences.resetNetworkTrafficAutoBreakpoint()
            } label: {
                Label("Reset to 900 pt", systemImage: AppIcon.Action.reset)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }
}

private struct NetworkTrafficTable: View {
    @Bindable var store: NetworkDebuggerStore

    var body: some View {
        let snapshot = store.trafficSnapshot
        ZStack {
            NetworkNativeTrafficTable(
                flows: snapshot.httpTrafficFlows,
                filter: snapshot.key.filter,
                selectedFlowID: selectedFlowID
            )
            .background(Color.primary.opacity(0.025))

            if snapshot.httpTrafficFlows.isEmpty {
                NetworkInlineEmptyState(store.flows.isEmpty ? "Start capture to see traffic." : "No matching traffic.")
                    .padding(.top, 24)
                    .allowsHitTesting(false)
            }
        }
    }

    private var selectedFlowID: Binding<UUID?> {
        Binding {
            store.selectedFlowID
        } set: { id in
            store.selectedFlowID = id
        }
    }
}

private struct NetworkNativeTrafficTable: NSViewRepresentable {
    var flows: [NetworkFlow]
    var filter: NetworkTrafficFilter
    @Binding var selectedFlowID: UUID?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.headerView = NetworkTrafficHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.style = .fullWidth

        for column in NetworkTrafficColumn.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.title
            let headerCell = NetworkTrafficHeaderCell(title: column.title, alignment: column.alignment)
            tableColumn.headerCell = headerCell
            tableColumn.width = column.idealWidth
            tableColumn.minWidth = column.minWidth
            tableColumn.maxWidth = column.maxWidth
            tableColumn.resizingMask = .userResizingMask
            tableView.addTableColumn(tableColumn)
        }

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        AppScrollbars.configure(scrollView, axes: [.vertical, .horizontal])
        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.applySelection()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let previousParent = context.coordinator.parent
        context.coordinator.parent = self
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        AppScrollbars.configure(scrollView, axes: [.vertical, .horizontal])
        context.coordinator.tableView = tableView
        context.coordinator.applyHeaderLayout()
        context.coordinator.applyFlowChanges(from: previousParent, to: self)
        context.coordinator.applySelection()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NetworkNativeTrafficTable
        weak var tableView: NSTableView?
        private var isApplyingSelection = false

        init(parent: NetworkNativeTrafficTable) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.flows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.flows.count,
                  let column = NetworkTrafficColumn(identifier: tableColumn?.identifier) else {
                return nil
            }

            let cell = reusableCell(in: tableView, for: column)
            configure(cell, column: column, flow: parent.flows[row])
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection,
                  let tableView = notification.object as? NSTableView else {
                return
            }

            let row = tableView.selectedRow
            guard row >= 0, row < parent.flows.count else {
                parent.selectedFlowID = nil
                return
            }
            parent.selectedFlowID = parent.flows[row].id
        }

        func applySelection() {
            guard let tableView else { return }
            isApplyingSelection = true
            defer { isApplyingSelection = false }

            guard let selectedFlowID = parent.selectedFlowID,
                  let row = parent.flows.firstIndex(where: { $0.id == selectedFlowID }) else {
                tableView.deselectAll(nil)
                return
            }

            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        func applyFlowChanges(from previous: NetworkNativeTrafficTable, to next: NetworkNativeTrafficTable) {
            guard let tableView else { return }
            guard tableView.numberOfRows == previous.flows.count, previous.filter == next.filter else {
                tableView.reloadData()
                return
            }

            let oldIDs = previous.flows.map(\.id)
            let newIDs = next.flows.map(\.id)
            guard oldIDs != newIDs else {
                reloadChangedRows(previous: previous.flows, next: next.flows)
                return
            }

            let oldIDSet = Set(oldIDs)
            let newIDSet = Set(newIDs)
            let oldSharedOrder = oldIDs.filter(newIDSet.contains)
            let newSharedOrder = newIDs.filter(oldIDSet.contains)
            guard oldSharedOrder == newSharedOrder else {
                tableView.reloadData()
                return
            }

            let removedRows = oldIDs.enumerated().compactMap { index, id in
                newIDSet.contains(id) ? nil : index
            }
            let insertedRows = newIDs.enumerated().compactMap { index, id in
                oldIDSet.contains(id) ? nil : index
            }

            if removedRows.isEmpty, insertedRows.isEmpty {
                tableView.reloadData()
                return
            }

            tableView.beginUpdates()
            if !removedRows.isEmpty {
                tableView.removeRows(at: IndexSet(removedRows.sorted(by: >)), withAnimation: [])
            }
            if !insertedRows.isEmpty {
                tableView.insertRows(at: IndexSet(insertedRows.sorted()), withAnimation: [])
            }
            tableView.endUpdates()

            guard tableView.numberOfRows == next.flows.count else {
                tableView.reloadData()
                return
            }
            reloadChangedRows(previous: previous.flows, next: next.flows)
        }

        func applyHeaderLayout() {
            guard let headerView = tableView?.headerView else { return }
            let targetHeight = NetworkTrafficTableMetrics.headerHeight
            guard abs(headerView.frame.height - targetHeight) > 0.5 else { return }
            headerView.frame.size.height = targetHeight
            headerView.needsDisplay = true
        }

        private func reloadChangedRows(previous: [NetworkFlow], next: [NetworkFlow]) {
            guard let tableView, !next.isEmpty else { return }
            let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
            let rows = next.enumerated().compactMap { index, flow in
                previousByID[flow.id] == flow ? nil : index
            }
            guard !rows.isEmpty else { return }
            tableView.reloadData(
                forRowIndexes: IndexSet(rows.filter { $0 < tableView.numberOfRows }),
                columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
            )
        }

        private func reusableCell(in tableView: NSTableView, for column: NetworkTrafficColumn) -> NSTableCellView {
            if column == .client {
                if let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? NetworkClientTableCellView {
                    return cell
                }
                let cell = NetworkClientTableCellView()
                cell.identifier = column.identifier
                return cell
            }

            if let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView {
                return cell
            }

            let cell = NSTableCellView()
            cell.identifier = column.identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.isSelectable = false
            textField.usesSingleLineMode = true
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: column.horizontalInset),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -column.horizontalInset),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])

            return cell
        }

        private func configure(_ cell: NSTableCellView, column: NetworkTrafficColumn, flow: NetworkFlow) {
            if column == .client, let clientCell = cell as? NetworkClientTableCellView {
                clientCell.configure(
                    clientName: flow.clientName,
                    font: column.font(for: flow),
                    textColor: column.textColor(for: flow)
                )
                return
            }

            guard let textField = cell.textField else { return }
            textField.stringValue = column.value(for: flow)
            textField.alignment = column.alignment
            textField.font = column.font(for: flow)
            textField.textColor = column.textColor(for: flow)
            textField.lineBreakMode = column == .url ? .byTruncatingMiddle : .byTruncatingTail
        }
    }
}

private final class NetworkClientTableCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let fallbackView = NSView()
    private let initialsLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }

    func configure(clientName: String, font: NSFont, textColor: NSColor) {
        let displayName = clientName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty(or: "Proxy Client")
        nameLabel.stringValue = displayName
        nameLabel.font = font
        nameLabel.textColor = textColor
        toolTip = "Client: \(displayName)"

        if let icon = NetworkClientIconProvider.icon(for: displayName) {
            iconView.image = icon
            iconView.isHidden = false
            fallbackView.isHidden = true
        } else {
            iconView.image = nil
            iconView.isHidden = true
            fallbackView.isHidden = false
            fallbackView.layer?.backgroundColor = NetworkClientIconProvider.badgeColor(for: displayName).cgColor
            initialsLabel.stringValue = NetworkClientIconProvider.initials(for: displayName)
        }
    }

    private func configureLayout() {
        textField = nameLabel
        imageView = iconView

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        fallbackView.translatesAutoresizingMaskIntoConstraints = false
        fallbackView.wantsLayer = true
        fallbackView.layer?.cornerRadius = 4
        addSubview(fallbackView)

        initialsLabel.translatesAutoresizingMaskIntoConstraints = false
        initialsLabel.font = .systemFont(ofSize: 7, weight: .bold)
        initialsLabel.textColor = .white
        initialsLabel.alignment = .center
        fallbackView.addSubview(initialsLabel)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.isSelectable = false
        nameLabel.usesSingleLineMode = true
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            fallbackView.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
            fallbackView.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            fallbackView.widthAnchor.constraint(equalTo: iconView.widthAnchor),
            fallbackView.heightAnchor.constraint(equalTo: iconView.heightAnchor),

            initialsLabel.leadingAnchor.constraint(equalTo: fallbackView.leadingAnchor),
            initialsLabel.trailingAnchor.constraint(equalTo: fallbackView.trailingAnchor),
            initialsLabel.topAnchor.constraint(equalTo: fallbackView.topAnchor),
            initialsLabel.bottomAnchor.constraint(equalTo: fallbackView.bottomAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

@MainActor
private enum NetworkClientIconProvider {
    private static var appIconCache: [String: NSImage] = [:]

    private static let bundleIDByAppName: [String: String] = [
        "Arc": "company.thebrowser.Browser",
        "Brave Browser": "com.brave.Browser",
        "Discord": "com.hnc.Discord",
        "Figma": "com.figma.Desktop",
        "Firefox": "org.mozilla.firefox",
        "Google Chrome": "com.google.Chrome",
        "Google Drive": "com.google.drivefs",
        "Lark": "com.larksuite.lark",
        "Microsoft Edge": "com.microsoft.edgemac",
        "NetEase Music": "com.netease.163music",
        "Opera": "com.operasoftware.Opera",
        "Postman": "com.postmanlabs.mac",
        "Safari": "com.apple.Safari",
        "Slack": "com.tinyspeck.slackmacgap",
        "Spotify": "com.spotify.client",
        "Telegram": "ru.keepcoder.Telegram",
        "Visual Studio Code": "com.microsoft.VSCode",
        "Xcode": "com.apple.dt.Xcode",
    ]

    private static let badgePalette: [NSColor] = [
        colorFromHex(0x4285F4),
        colorFromHex(0x10A380),
        colorFromHex(0xD9544F),
        colorFromHex(0x9C59B5),
        colorFromHex(0xE67D21),
        colorFromHex(0x667F99),
    ]

    static func icon(for appName: String) -> NSImage? {
        let normalizedName = normalized(appName)
        guard !normalizedName.isEmpty else {
            return nil
        }
        if let cached = appIconCache[normalizedName] {
            return cached
        }

        if let runningIcon = runningApplicationIcon(for: normalizedName) {
            appIconCache[normalizedName] = runningIcon
            return runningIcon
        }

        if let bundleID = bundleIDByAppName[normalizedName],
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            let icon = sizedIcon(forFile: appURL.path)
            appIconCache[normalizedName] = icon
            return icon
        }

        for candidate in appPathCandidates(for: normalizedName) where FileManager.default.fileExists(atPath: candidate) {
            let icon = sizedIcon(forFile: candidate)
            appIconCache[normalizedName] = icon
            return icon
        }

        return nil
    }

    static func badgeColor(for appName: String) -> NSColor {
        let hash = normalized(appName).unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return badgePalette[abs(hash) % badgePalette.count]
    }

    static func initials(for appName: String) -> String {
        let words = normalized(appName)
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
        let letters = words.prefix(2).compactMap(\.first)
        if letters.isEmpty, let first = appName.first {
            return String(first).uppercased()
        }
        return letters.map { String($0).uppercased() }.joined()
    }

    private static func runningApplicationIcon(for appName: String) -> NSImage? {
        let app = NSWorkspace.shared.runningApplications.first { runningApp in
            runningApp.localizedName == appName
                || runningApp.bundleIdentifier == appName
                || runningApp.localizedName == baseAppName(for: appName)
        }
        guard let icon = app?.icon else {
            return nil
        }
        icon.size = NSSize(width: 16, height: 16)
        icon.isTemplate = false
        return icon
    }

    private static func appPathCandidates(for appName: String) -> [String] {
        let baseName = baseAppName(for: appName)
        return [
            "/Applications/\(appName).app",
            "/Applications/\(baseName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/\(baseName).app",
            "/Applications/Utilities/\(appName).app",
            "/Applications/Utilities/\(baseName).app",
        ]
    }

    private static func sizedIcon(forFile path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        icon.isTemplate = false
        return icon
    }

    private static func normalized(_ appName: String) -> String {
        appName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func baseAppName(for appName: String) -> String {
        let suffixes = [" Helper", " Helper (Renderer)", " Helper (GPU)", " Helper (Plugin)"]
        for suffix in suffixes where appName.hasSuffix(suffix) {
            return String(appName.dropLast(suffix.count))
        }
        return appName
    }

    private static func colorFromHex(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private enum NetworkTrafficTableMetrics {
    static let headerHeight: CGFloat = 30
    static let headerHorizontalInset: CGFloat = 6
    static let headerBaselineOffset: CGFloat = -0.5
}

private final class NetworkTrafficHeaderView: NSTableHeaderView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: NetworkTrafficTableMetrics.headerHeight))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        frame.size.height = NetworkTrafficTableMetrics.headerHeight
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NetworkTrafficTableMetrics.headerHeight)
    }

    override func layout() {
        super.layout()
        if abs(frame.height - NetworkTrafficTableMetrics.headerHeight) > 0.5 {
            frame.size.height = NetworkTrafficTableMetrics.headerHeight
        }
    }

    override func headerRect(ofColumn column: Int) -> NSRect {
        var rect = super.headerRect(ofColumn: column)
        rect.size.height = NetworkTrafficTableMetrics.headerHeight
        return rect
    }
}

private final class NetworkTrafficHeaderCell: NSTableHeaderCell {
    init(title: String, alignment: NSTextAlignment) {
        super.init(textCell: title)
        configure(alignment: alignment)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        configure(alignment: alignment)
    }

    private func configure(alignment: NSTextAlignment) {
        font = .networkTableSora(size: 13, weight: .semibold)
        textColor = .labelColor
        self.alignment = alignment
        lineBreakMode = .byTruncatingTail
        usesSingleLineMode = true
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard !stringValue.isEmpty else { return }
        let resolvedFont = font ?? .networkTableSora(size: 13, weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = lineBreakMode

        let attributes: [NSAttributedString.Key: Any] = [
            .font: resolvedFont,
            .foregroundColor: textColor ?? NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]
        let attributedTitle = NSAttributedString(string: stringValue, attributes: attributes)
        let textHeight = ceil(resolvedFont.ascender - resolvedFont.descender + resolvedFont.leading)
        var textRect = cellFrame.insetBy(dx: NetworkTrafficTableMetrics.headerHorizontalInset, dy: 0)
        textRect.origin.y = max(
            cellFrame.minY + 2,
            floor(cellFrame.midY - textHeight / 2 + NetworkTrafficTableMetrics.headerBaselineOffset)
        )
        textRect.size.height = textHeight
        attributedTitle.draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
    }
}

private enum NetworkTrafficColumn: String, CaseIterable {
    case state
    case number
    case url
    case client
    case upstream
    case method
    case status
    case time
    case duration
    case request
    case response
    case ssl
    case edited
    case tools

    init?(identifier: NSUserInterfaceItemIdentifier?) {
        guard let identifier, let column = Self(rawValue: identifier.rawValue) else { return nil }
        self = column
    }

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(rawValue)
    }

    var title: String {
        switch self {
        case .state: ""
        case .number: "#"
        case .url: "URL"
        case .client: "Client"
        case .upstream: "Upstream"
        case .method: "Method"
        case .status: "Status"
        case .time: "Time"
        case .duration: "Duration"
        case .request: "Request"
        case .response: "Response"
        case .ssl: "SSL"
        case .edited: "Edited"
        case .tools: "Tools"
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .state: 20
        case .number: 42
        case .url: 260
        case .client: 120
        case .upstream: 96
        case .method: 72
        case .status: 70
        case .time: 102
        case .duration: 82
        case .request: 86
        case .response: 90
        case .ssl: 48
        case .edited: 54
        case .tools: 54
        }
    }

    var idealWidth: CGFloat {
        switch self {
        case .state: 20
        case .number: 50
        case .url: 430
        case .client: 155
        case .upstream: 128
        case .method: 86
        case .status: 82
        case .time: 116
        case .duration: 94
        case .request: 100
        case .response: 104
        case .ssl: 58
        case .edited: 64
        case .tools: 64
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .url: 920
        case .client: 260
        case .upstream: 180
        case .time: 150
        case .duration, .request, .response: 150
        case .method, .status: 120
        case .number: 70
        case .state: 20
        case .ssl: 78
        case .edited, .tools: 84
        }
    }

    var horizontalInset: CGFloat {
        switch self {
        case .state: 5
        default: 6
        }
    }

    var alignment: NSTextAlignment {
        switch self {
        case .url, .client, .upstream:
            .left
        default:
            .center
        }
    }

    func value(for flow: NetworkFlow) -> String {
        switch self {
        case .state:
            "●"
        case .number:
            "\(flow.number)"
        case .url:
            flow.urlDisplay
        case .client:
            flow.clientName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty(or: "Proxy Client")
        case .upstream:
            flow.upstreamProxy.kind
        case .method:
            flow.request.method
        case .status:
            flow.statusDisplay
        case .time:
            flow.createdAt.formatted(date: .omitted, time: .standard)
        case .duration:
            duration(flow)
        case .request:
            bytes(flow.requestBytes)
        case .response:
            bytes(flow.responseBytes)
        case .ssl:
            flow.isSSLIntercepted ? "MITM" : "TLS"
        case .edited:
            flow.isEdited ? "Yes" : "-"
        case .tools:
            "..."
        }
    }

    func font(for flow: NetworkFlow) -> NSFont {
        switch self {
        case .method, .status:
            .networkTableSora(size: 11, weight: .semibold)
        case .state:
            .networkTableSora(size: 12, weight: .medium)
        default:
            .networkTableSora(size: 11, weight: .regular)
        }
    }

    func textColor(for flow: NetworkFlow) -> NSColor {
        switch self {
        case .state:
            switch flow.state {
            case .active: .systemYellow
            case .completed: .systemGreen
            case .failed: .systemRed
            }
        case .status:
            statusColor(for: flow)
        case .ssl, .edited, .tools, .upstream:
            .secondaryLabelColor
        default:
            .labelColor
        }
    }

    private func statusColor(for flow: NetworkFlow) -> NSColor {
        guard let status = flow.response.statusCode else {
            return flow.state == .failed ? .systemRed : .systemYellow
        }
        if status < 300 { return .systemGreen }
        if status < 400 { return .systemYellow }
        return .systemRed
    }

    private func duration(_ flow: NetworkFlow) -> String {
        if flow.duration < 1 { return "\(Int((flow.duration * 1000).rounded())) ms" }
        return String(format: "%.2f s", flow.duration)
    }

    private func bytes(_ value: Int) -> String {
        guard value > 0 else { return "-" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}

private struct NetworkFlowInspector: View {
    @Bindable var store: NetworkDebuggerStore
    let arrangement: NetworkInspectorPaneArrangement

    var body: some View {
        Group {
            switch arrangement {
            case .vertical:
                HoverableSplitView(
                    axis: .horizontal,
                    primaryFraction: 0.48,
                    configuration: NetworkTrafficPaneMetrics.verticalInspectorSplitConfiguration
                ) {
                    payloadPane(.request)
                        .frame(
                            minHeight: NetworkTrafficPaneMetrics.requestPayloadMinHeight,
                            idealHeight: 240,
                            maxHeight: .infinity
                        )
                } secondary: {
                    payloadPane(.response)
                        .frame(
                            minHeight: NetworkTrafficPaneMetrics.responsePayloadMinHeight,
                            idealHeight: 260,
                            maxHeight: .infinity
                        )
                }
            case .horizontal:
                HoverableSplitView(
                    axis: .vertical,
                    configuration: NetworkTrafficPaneMetrics.horizontalInspectorSplitConfiguration
                ) {
                    payloadPane(.request)
                        .frame(
                            minWidth: NetworkTrafficPaneMetrics.payloadMinWidth,
                            idealWidth: 420,
                            maxWidth: .infinity
                        )
                } secondary: {
                    payloadPane(.response)
                        .frame(
                            minWidth: NetworkTrafficPaneMetrics.payloadMinWidth,
                            idealWidth: 420,
                            maxWidth: .infinity
                        )
                }
            }
        }
        .background(Color.primary.opacity(0.025))
    }

    private func payloadPane(_ side: NetworkInspectorSide) -> some View {
        NetworkPayloadPane(store: store, side: side)
    }
}

private struct NetworkPayloadPane: View {
    @Bindable var store: NetworkDebuggerStore
    let side: NetworkInspectorSide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader
            StxRule()
            paneBody
        }
        .background(Color.primary.opacity(0.025))
    }

    private var paneHeader: some View {
        HStack(spacing: 8) {
            Text(side.title.uppercased())
                .font(.sora(11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let flow = store.selectedFlow {
                headerBadge(flow)
                if side == .request {
                    Text(flow.upstreamProxy.summary)
                        .font(.sora(10, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }
                Text("#\(flow.number)")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                if side == .request {
                    actionButton(flow.isPinned ? "pin.slash" : "pin") {
                        store.togglePinned(for: flow.id)
                    }
                    actionButton(flow.isSaved ? "tray.and.arrow.up.fill" : "tray.and.arrow.down") {
                        store.toggleSaved(for: flow.id)
                    }
                    actionButton("arrow.clockwise") {
                        store.prepareReplay(for: flow)
                    }
                    .disabled(flow.request.body.isTruncated)
                    actionButton("doc.on.doc") {
                        copy(content(for: flow))
                    }
                    Menu {
                        Button("Copy URL") {
                            copy(flow.request.url)
                        }
                        Button("Copy Headers") {
                            copy(flow.request.headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n"))
                        }
                        Button("Copy Body") {
                            copy(flow.request.body.text)
                        }
                        Divider()
                        Button("Copy as cURL") {
                            store.copyFlow(flow, format: .curl)
                        }
                        Button("Export HAR") {
                            store.copyFlow(flow, format: .har)
                        }
                        Button("Export Raw Request") {
                            store.copyFlow(flow, format: .rawRequest)
                        }
                        Button("Export Raw Response") {
                            store.copyFlow(flow, format: .rawResponse)
                        }
                        Divider()
                        Button("Duplicate to Replay") {
                            store.duplicateFlowToReplay(flow)
                        }
                        Button("Send to Automate") {
                            store.sendFlowToAutomate(flow)
                        }
                        Button("Create Block Rule") {
                            store.createRule(from: flow, kind: .block)
                            store.selectedSection = .rules
                        }
                        Button("Create Breakpoint") {
                            store.createRule(from: flow, kind: .breakpoint)
                            store.selectedSection = .rules
                        }
                        Divider()
                        Button("Delete Flow", role: .destructive) {
                            store.deleteFlow(flow.id)
                        }
                    } label: {
                        Image(systemName: AppIcon.Action.more)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.stxMuted)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 22, height: 22)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func actionButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var paneBody: some View {
        if let flow = store.selectedFlow {
            AppScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    payloadCard(flow)
                }
                .padding(14)
            }
        } else {
            NetworkInlineEmptyState("Start capture or select a request.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func payloadCard(_ flow: NetworkFlow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("PAYLOAD")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.stxMuted)

                Spacer(minLength: 8)

                ForEach(NetworkInspectorTab.allCases) { tab in
                    Button {
                        selectedTab.wrappedValue = tab
                    } label: {
                        Text(tab.title)
                            .font(.sora(10, weight: selectedTab.wrappedValue == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab.wrappedValue == tab ? Color.stxAccent : Color.stxMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            StxRule()

            if selectedTab.wrappedValue == .overview, side == .request {
                commentEditor(for: flow)
                StxRule()
            }

            payloadContentView(flow)

            if payloadBody(for: flow).isTruncated {
                StxRule()
                Text("Body truncated at capture limit.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .padding(12)
            }
        }
        .networkInspectorCard()
    }

    private var selectedTab: Binding<NetworkInspectorTab> {
        Binding {
            side == .request ? store.selectedRequestTab : store.selectedResponseTab
        } set: { tab in
            if side == .request {
                store.selectedRequestTab = tab
            } else {
                store.selectedResponseTab = tab
            }
        }
    }

    @ViewBuilder
    private func headerBadge(_ flow: NetworkFlow) -> some View {
        switch side {
        case .request:
            methodBadge(flow.request.method)
        case .response:
            statusBadge(flow)
        }
    }

    private func methodBadge(_ method: String) -> some View {
        Text(method)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.78))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.08), in: Capsule())
    }

    private func statusBadge(_ flow: NetworkFlow) -> some View {
        Text(flow.statusDisplay)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(statusColor(flow))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(flow).opacity(0.14), in: Capsule())
    }

    private func content(for flow: NetworkFlow) -> String {
        switch selectedTab.wrappedValue {
        case .overview:
            return overview(for: flow)
        case .header:
            return headers(for: flow).map { "\($0.name): \($0.value)" }.joined(separator: "\n").nonEmpty(or: "No headers")
        case .query:
            return queryString(for: flow).nonEmpty(or: "No query parameters")
        case .cookies:
            return cookies(for: flow).nonEmpty(or: "No cookies")
        case .form:
            return formBody(for: flow).nonEmpty(or: "No form body")
        case .body:
            return payloadBody(for: flow).text.nonEmpty(or: "No body")
        case .preview:
            return previewText(for: flow)
        case .raw:
            return raw(for: flow)
        case .json:
            return prettyJSON(payloadBody(for: flow).text).nonEmpty(or: "No JSON body")
        case .webSocket:
            return webSocketFrames(for: flow).nonEmpty(or: "No WebSocket frames")
        case .timing:
            return timing(for: flow)
        }
    }

    private func commentEditor(for flow: NetworkFlow) -> some View {
        HStack(spacing: 8) {
            Label("Comment", systemImage: AppIcon.Resource.textBubble)
                .font(.sora(10, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            TextField("Add a note for this flow", text: Binding {
                store.flows.first { $0.id == flow.id }?.comment ?? ""
            } set: { value in
                store.setComment(for: flow.id, text: value)
            })
            .textFieldStyle(.roundedBorder)
        }
        .padding(12)
    }

    @ViewBuilder
    private func payloadContentView(_ flow: NetworkFlow) -> some View {
        if selectedTab.wrappedValue == .preview,
           let data = payloadBody(for: flow).data,
           let contentType = payloadBody(for: flow).contentType?.lowercased(),
           contentType.hasPrefix("image/"),
           let image = NSImage(data: data)
        {
            VStack(alignment: .leading, spacing: 10) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 260, alignment: .leading)
                Text(previewText(for: flow))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.84))
                    .textSelection(.enabled)
            }
            .padding(12)
        } else {
            Text(content(for: flow))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.84))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    private func headers(for flow: NetworkFlow) -> [NetworkHeaderPair] {
        side == .request ? flow.request.headers : flow.response.headers
    }

    private func payloadBody(for flow: NetworkFlow) -> NetworkBody {
        side == .request ? flow.request.body : flow.response.body
    }

    private func queryString(for flow: NetworkFlow) -> String {
        guard side == .request,
              let components = URLComponents(string: flow.request.url),
              let items = components.queryItems,
              !items.isEmpty else { return "" }
        return items.map { "\($0.name): \($0.value ?? "")" }.joined(separator: "\n")
    }

    private func overview(for flow: NetworkFlow) -> String {
        [
            "URL: \(flow.request.url)",
            "Method: \(flow.request.method)",
            "Status: \(flow.statusDisplay)",
            "Protocol: \(flow.flowProtocol.rawValue)",
            "Client: \(flow.clientName)",
            "Domain: \(flow.domainDisplay)",
            "Upstream: \(flow.upstreamProxy.summary)",
            "Rule: \(flow.matchedRuleName ?? "-")",
            "Source: \(flow.operationSource.rawValue)",
            "Comment: \(flow.comment.isEmpty ? "-" : flow.comment)",
            "Duration: \(duration(flow))",
            "Request: \(bytes(flow.requestBytes))",
            "Response: \(bytes(flow.responseBytes))",
        ].joined(separator: "\n")
    }

    private func cookies(for flow: NetworkFlow) -> String {
        let relevantHeaders = side == .request
            ? flow.request.headers.filter { $0.name.caseInsensitiveCompare("Cookie") == .orderedSame }
            : flow.response.headers.filter { $0.name.caseInsensitiveCompare("Set-Cookie") == .orderedSame }
        return relevantHeaders
            .flatMap { header in
                header.value.split(separator: side == .request ? ";" : ",").map {
                    String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func formBody(for flow: NetworkFlow) -> String {
        let body = payloadBody(for: flow)
        let contentType = body.contentType?.lowercased() ?? ""
        guard contentType.contains("application/x-www-form-urlencoded") else {
            return ""
        }
        var components = URLComponents()
        components.percentEncodedQuery = body.text
        return (components.queryItems ?? [])
            .map { "\($0.name): \($0.value ?? "")" }
            .joined(separator: "\n")
    }

    private func previewText(for flow: NetworkFlow) -> String {
        let body = payloadBody(for: flow)
        let type = body.contentType ?? "unknown"
        if body.bytes == 0 { return "No preview" }
        if type.lowercased().contains("json") {
            return prettyJSON(body.text).nonEmpty(or: body.text)
        }
        if type.lowercased().hasPrefix("image/") {
            return "\(type), \(bytes(body.bytes))"
        }
        if body.text.hasPrefix("<") {
            return body.text
        }
        if body.data != nil, body.text.hasPrefix("<\(body.bytes) binary") {
            return hexDump(body.data ?? Data())
        }
        return body.text
    }

    private func webSocketFrames(for flow: NetworkFlow) -> String {
        flow.webSocketFrames.map { frame in
            "[\(frame.timestamp.formatted(date: .omitted, time: .standard))] \(frame.direction.title) \(frame.opcode) \(bytes(frame.payloadBytes))\n\(frame.payloadText)"
        }.joined(separator: "\n\n")
    }

    private func timing(for flow: NetworkFlow) -> String {
        [
            "Started: \(flow.createdAt.formatted(date: .abbreviated, time: .standard))",
            "Completed: \(flow.completedAt?.formatted(date: .abbreviated, time: .standard) ?? "-")",
            "Duration: \(duration(flow))",
        ].joined(separator: "\n")
    }

    private func raw(for flow: NetworkFlow) -> String {
        if side == .request {
            let head = "\(flow.request.method) \(flow.request.url) \(flow.request.httpVersion)"
            return ([head] + flow.request.headers.map { "\($0.name): \($0.value)" }).joined(separator: "\n")
                + "\n\n"
                + flow.request.body.text
        }
        let head = "HTTP \(flow.response.statusCode.map(String.init) ?? "-") \(flow.response.reason)"
        return ([head] + flow.response.headers.map { "\($0.name): \($0.value)" }).joined(separator: "\n")
            + "\n\n"
            + flow.response.body.text
    }

    private func statusColor(_ flow: NetworkFlow) -> Color {
        guard let status = flow.response.statusCode else {
            return flow.state == .failed ? .red : .yellow
        }
        if status < 300 { return .green }
        if status < 400 { return .yellow }
        return .red
    }

    private func duration(_ flow: NetworkFlow) -> String {
        if flow.duration < 1 { return "\(Int((flow.duration * 1000).rounded())) ms" }
        return String(format: "%.2f s", flow.duration)
    }

    private func bytes(_ value: Int) -> String {
        guard value > 0 else { return "-" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    private func prettyJSON(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let output = String(data: pretty, encoding: .utf8) else {
            return ""
        }
        return output
    }

    private func hexDump(_ data: Data) -> String {
        data.prefix(512).enumerated().map { offset, byte in
            let separator = (offset + 1) % 16 == 0 ? "\n" : " "
            return String(format: "%02X%@", byte, separator)
        }.joined()
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func curl(for flow: NetworkFlow) -> String {
        var parts = ["curl", "-X", shellQuote(flow.request.method), shellQuote(flow.request.url)]
        for header in flow.request.headers {
            parts += ["-H", shellQuote("\(header.name): \(header.value)")]
        }
        if !flow.request.body.text.isEmpty {
            parts += ["--data-raw", shellQuote(flow.request.body.text)]
        }
        return parts.joined(separator: " ")
    }

    private func har(for flow: NetworkFlow) -> String {
        let object: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": ["name": "Claude Stats", "version": "1.0"],
                "entries": [[
                    "startedDateTime": ISO8601DateFormatter().string(from: flow.createdAt),
                    "time": flow.duration * 1_000,
                    "request": [
                        "method": flow.request.method,
                        "url": flow.request.url,
                        "httpVersion": flow.request.httpVersion,
                        "headers": flow.request.headers.map { ["name": $0.name, "value": $0.value] },
                        "queryString": [],
                        "headersSize": -1,
                        "bodySize": flow.requestBytes,
                    ],
                    "response": [
                        "status": flow.response.statusCode ?? 0,
                        "statusText": flow.response.reason,
                        "httpVersion": "HTTP/1.1",
                        "headers": flow.response.headers.map { ["name": $0.name, "value": $0.value] },
                        "content": [
                            "size": flow.responseBytes,
                            "mimeType": flow.response.body.contentType ?? "",
                            "text": flow.response.body.text,
                        ],
                        "redirectURL": "",
                        "headersSize": -1,
                        "bodySize": flow.responseBytes,
                    ],
                ]],
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private func shellQuote(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private struct NetworkReplayEditor: View {
    @Bindable var store: NetworkDebuggerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Edit and Resend", systemImage: AppIcon.Action.refresh)
                    .font(.sora(15, weight: .semibold))
                Spacer()
                Button("Cancel") {
                    store.cancelReplay()
                }
                Button("Send") {
                    store.performReplay()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(store.isReplayWorking)
            }

            if store.replayDraft != nil {
                HStack(spacing: 8) {
                    TextField("Method", text: replayBinding(\.method))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                    TextField("URL", text: replayBinding(\.url))
                        .textFieldStyle(.roundedBorder)
                }

                Text("HEADERS")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.stxMuted)

                AppScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.replayDraft?.headers ?? []) { header in
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
                    }
                }
                .frame(height: 150)

                Text("BODY")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.stxMuted)

                TextEditor(text: replayBinding(\.bodyText))
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(18)
    }

    private func replayBinding<Value>(_ keyPath: WritableKeyPath<NetworkReplayDraft, Value>) -> Binding<Value> {
        Binding {
            store.replayDraft?[keyPath: keyPath] ?? NetworkReplayDraft(
                sourceFlowID: UUID(),
                method: "GET",
                url: "",
                headers: [],
                bodyText: "",
                contentType: nil
            )[keyPath: keyPath]
        } set: { value in
            guard store.replayDraft != nil else { return }
            store.replayDraft?[keyPath: keyPath] = value
        }
    }

    private func headerBinding(
        _ id: String,
        _ keyPath: WritableKeyPath<NetworkHeaderPair, String>
    ) -> Binding<String> {
        Binding {
            store.replayDraft?.headers.first { $0.id == id }?[keyPath: keyPath] ?? ""
        } set: { value in
            guard let index = store.replayDraft?.headers.firstIndex(where: { $0.id == id }) else { return }
            store.replayDraft?.headers[index][keyPath: keyPath] = value
        }
    }

    private func addHeader() {
        store.replayDraft?.headers.append(NetworkHeaderPair(name: "Header", value: ""))
    }

    private func removeHeader(_ id: String) {
        store.replayDraft?.headers.removeAll { $0.id == id }
    }
}

private struct NetworkInlineEmptyState: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.sora(10))
            .foregroundStyle(Color.stxMuted.opacity(0.8))
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
    }
}

private extension View {
    func networkInspectorCard() -> some View {
        appSurface(.compactCard(radius: 10, maxWidth: nil))
    }
}

private extension NSFont {
    static func networkTableSora(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: Theme.fontFamily,
            .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}

private extension String {
    func nonEmpty(or fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
