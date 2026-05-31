import AppKit
import SwiftUI

struct OpsPortsView: View {
    @Bindable var store: OpsStore

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width < 820 {
                HoverableSplitView(
                    axis: .horizontal,
                    primaryFraction: 0.50,
                    configuration: HoverableSplitViewConfiguration(primaryMinimumPaneLength: 220, secondaryMinimumPaneLength: 260)
                ) {
                    portsTable
                } secondary: {
                    portInspector
                }
            } else {
                HoverableSplitView(
                    axis: .vertical,
                    primaryFraction: 0.62,
                    configuration: HoverableSplitViewConfiguration(primaryMinimumPaneLength: 420, secondaryMinimumPaneLength: 320)
                ) {
                    portsTable
                } secondary: {
                    portInspector
                }
            }
        }
    }

    private var portsTable: some View {
        VStack(spacing: 0) {
            OpsTableToolbar(
                searchText: $store.portQuery,
                placeholder: "Search ports, process, user",
                refresh: { store.refresh(.ports) }
            )
            StxRule()
            ZStack {
                OpsNativePortTable(
                    rows: store.visiblePortRows,
                    rowsVersion: store.portProjectionGeneration,
                    selectedID: Binding(
                        get: { store.selectedPortID },
                        set: { store.selectedPortID = $0 }
                    )
                )
                .background(Color.primary.opacity(0.025))

                if store.visiblePortRows.isEmpty {
                    OpsInlineEmptyState(store.ports.isEmpty ? "No listening ports." : "No matching ports.")
                        .padding(.top, 24)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var portInspector: some View {
        OpsInspectorContainer {
            if let port = store.selectedPortRow {
                OpsInspectorTitle(symbol: OpsSection.ports.symbol, title: port.portText, subtitle: port.processName)

                OpsInspectorGroup("Connection") {
                    OpsKeyValue("Address", port.displayAddress)
                    OpsKeyValue("Protocol", port.protocolName)
                    OpsKeyValue("URL", port.localhostURL)
                }

                OpsInspectorGroup("Process") {
                    OpsKeyValue("PID", port.pidText)
                    OpsKeyValue("User", port.user)
                    OpsKeyValue("Executable", port.executablePath ?? "--")
                    OpsCodeBlock(port.commandLine)
                }

                HStack(spacing: 8) {
                    Button {
                        store.copyToClipboard(port.localhostURL)
                    } label: {
                        Label("Copy URL", systemImage: AppIcon.Action.copy)
                    }
                    .controlSize(.small)

                    Button {
                        store.copyToClipboard("kill -TERM \(port.item.pid)")
                    } label: {
                        Label("Copy Kill", systemImage: AppIcon.Runtime.terminal)
                    }
                    .controlSize(.small)

                    Spacer()

                    Button(role: .destructive) {
                        store.requestTerminate(port.item)
                    } label: {
                        Label("End", systemImage: AppIcon.Status.failure)
                    }
                    .controlSize(.small)
                    .disabled(port.protectionReason != nil || !store.canRunAction)
                    .help(port.protectionReason ?? "End process")
                }
            } else {
                OpsInlineEmptyState("Select a port.")
            }
        }
    }
}

struct OpsProcessesView: View {
    @Bindable var store: OpsStore

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width < 860 {
                HoverableSplitView(
                    axis: .horizontal,
                    primaryFraction: 0.52,
                    configuration: HoverableSplitViewConfiguration(primaryMinimumPaneLength: 240, secondaryMinimumPaneLength: 260)
                ) {
                    processesTable
                } secondary: {
                    processInspector
                }
            } else {
                HoverableSplitView(
                    axis: .vertical,
                    primaryFraction: 0.62,
                    configuration: HoverableSplitViewConfiguration(primaryMinimumPaneLength: 460, secondaryMinimumPaneLength: 340)
                ) {
                    processesTable
                } secondary: {
                    processInspector
                }
            }
        }
    }

    private var processesTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                OpsSearchField(text: $store.processQuery, placeholder: "Search processes")

                Picker("Sort", selection: $store.processSort) {
                    ForEach(OpsProcessSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)

                Button {
                    store.refresh(.processes)
                } label: {
                    Image(systemName: AppIcon.Action.refresh)
                }
                .buttonStyle(.bordered)
                .help("Refresh")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            StxRule()
            ZStack {
                OpsNativeProcessTable(
                    rows: store.visibleProcessRows,
                    rowsVersion: store.processProjectionGeneration,
                    selectedID: Binding(
                        get: { store.selectedProcessID },
                        set: { store.selectedProcessID = $0 }
                    )
                )
                .background(Color.primary.opacity(0.025))

                if store.visibleProcessRows.isEmpty {
                    OpsInlineEmptyState(store.processes.isEmpty ? "No processes." : "No matching processes.")
                        .padding(.top, 24)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var processInspector: some View {
        OpsInspectorContainer {
            if let process = store.selectedProcessRow {
                OpsInspectorTitle(symbol: OpsSection.processes.symbol, title: process.displayName, subtitle: "PID \(process.pidText)")

                OpsInspectorGroup("Usage") {
                    OpsKeyValue("CPU", "\(process.cpuText)%")
                    OpsKeyValue("Memory", "\(process.memoryText)%")
                    OpsKeyValue("Elapsed", process.elapsed)
                    OpsKeyValue("Developer", process.isDeveloperProcess ? "Yes" : "No")
                }

                OpsInspectorGroup("Process") {
                    OpsKeyValue("User", process.user)
                    OpsKeyValue("Parent PID", process.ppidText)
                    OpsKeyValue("Executable", process.executablePath)
                    OpsCodeBlock(process.commandLine)
                }

                HStack(spacing: 8) {
                    Button {
                        store.copyToClipboard(process.commandLine)
                    } label: {
                        Label("Copy Command", systemImage: AppIcon.Action.copy)
                    }
                    .controlSize(.small)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: process.executablePath)])
                    } label: {
                        Label("Reveal", systemImage: AppIcon.Resource.folder)
                    }
                    .controlSize(.small)
                    .disabled(!process.canRevealExecutable)

                    Spacer()

                    Button(role: .destructive) {
                        store.requestTerminate(process.item)
                    } label: {
                        Label("End", systemImage: AppIcon.Status.failure)
                    }
                    .controlSize(.small)
                    .disabled(process.protectionReason != nil || !store.canRunAction)
                    .help(process.protectionReason ?? "End process")
                }
            } else {
                OpsInlineEmptyState("Select a process.")
            }
        }
    }
}

struct OpsBrewView: View {
    @Bindable var store: OpsStore
    @State private var installText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                OpsSearchField(text: $store.brewQuery, placeholder: "Search packages")
                Button {
                    store.refresh(.brew)
                } label: {
                    Label("Refresh", systemImage: AppIcon.Action.refresh)
                }
                .controlSize(.small)
            }

            OpsCard {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Homebrew")
                            .font(.sora(14, weight: .semibold))
                        Text(store.brewSnapshot.brewPath ?? "Not found")
                            .font(.sora(11))
                            .foregroundStyle(Color.stxMuted)
                    }
                    Spacer()
                    Button {
                        store.requestBrewCleanup()
                    } label: {
                        Label("Cleanup", systemImage: AppIcon.Feature.ai)
                    }
                    .controlSize(.small)
                    .disabled(store.brewSnapshot.brewPath == nil || !store.canRunAction)
                }
            }

            if !store.brewSnapshot.errors.isEmpty {
                OpsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Command errors")
                            .font(.sora(13, weight: .semibold))
                        OpsCodeBlock(store.brewSnapshot.errors.joined(separator: "\n"))
                    }
                }
            }

            if let output = store.lastActionOutput, !output.isEmpty {
                OpsActionOutputCard(output: output) {
                    store.clearActionOutput()
                }
            }

            OpsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Install")
                        .font(.sora(13, weight: .semibold))
                    HStack(spacing: 8) {
                        TextField("package-name", text: $installText)
                            .textFieldStyle(.roundedBorder)
                            .font(.sora(12))
                        Button {
                            store.requestBrewInstall(installText)
                        } label: {
                            Label("Install", systemImage: AppIcon.Action.add)
                        }
                        .controlSize(.small)
                        .disabled(store.brewSnapshot.brewPath == nil || !store.canRunAction || installText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            OpsCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Packages")
                            .font(.sora(13, weight: .semibold))
                        Spacer()
                        Text("\(store.filteredBrewPackages.count)")
                            .font(.sora(11).monospacedDigit())
                            .foregroundStyle(Color.stxMuted)
                    }

                    if store.filteredBrewPackages.isEmpty {
                        OpsInlineEmptyState("No packages.")
                    } else {
                        LazyVStack(spacing: 0) {
	                            ForEach(store.filteredBrewPackages) { package in
                                OpsBrewPackageRow(package: package, isSelected: store.selectedBrewPackage?.id == package.id, actionsDisabled: !store.canRunAction) {
                                    store.selectBrewPackage(package)
                                } upgrade: {
                                    store.requestBrewUpgrade(package)
                                } uninstall: {
                                    store.requestBrewUninstall(package)
                                }
                            }
                        }
                    }
                }
            }

            OpsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Services")
                        .font(.sora(13, weight: .semibold))
                    if store.brewSnapshot.services.isEmpty {
                        OpsInlineEmptyState("No Homebrew services.")
                    } else {
                        LazyVStack(spacing: 0) {
	                            ForEach(store.brewSnapshot.services) { service in
                                OpsBrewServiceRow(service: service, actionsDisabled: !store.canRunAction) { action in
                                    store.requestBrewService(service.name, action: action)
                                }
                            }
                        }
                    }
                }
            }

            OpsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Doctor")
                        .font(.sora(13, weight: .semibold))
                    OpsCodeBlock(store.brewSnapshot.doctorOutput)
                }
            }
        }
    }
}

struct OpsEnvironmentView: View {
    @Bindable var store: OpsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Developer tools")
                    .font(.sora(14, weight: .semibold))
                Spacer()
                Button {
                    store.refresh(.environment)
                } label: {
                    Label("Refresh", systemImage: AppIcon.Action.refresh)
                }
                .controlSize(.small)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                ForEach(store.environmentTools) { tool in
                    OpsEnvironmentToolCard(tool: tool)
                }
            }
        }
    }
}

struct OpsCleanupView: View {
    @Bindable var store: OpsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Reclaimable development caches")
                    .font(.sora(14, weight: .semibold))
                Spacer()
                Button {
                    store.refresh(.cleanup)
                } label: {
                    Label("Scan", systemImage: AppIcon.Action.refresh)
                }
                .controlSize(.small)
                Button(role: .destructive) {
                    store.requestCleanupSelected()
                } label: {
                    Label("Clean Selected", systemImage: AppIcon.Action.delete)
                }
                .controlSize(.small)
                .disabled(store.selectedCleanupKinds.isEmpty || !store.canRunAction)
            }

            if let output = store.lastActionOutput, !output.isEmpty {
                OpsActionOutputCard(output: output) {
                    store.clearActionOutput()
                }
            }

            LazyVStack(spacing: 10) {
                ForEach(store.cleanupItems) { item in
                    OpsCleanupRow(
                        item: item,
                        isSelected: store.selectedCleanupKinds.contains(item.kind)
                    ) {
                        store.toggleCleanupSelection(item)
                    }
                }
            }
        }
    }
}

struct OpsDiagnosticsView: View {
    @Bindable var store: OpsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("System diagnostics")
                    .font(.sora(14, weight: .semibold))
                Spacer()
                Button {
                    store.refresh(.diagnostics)
                } label: {
                    Label("Refresh", systemImage: AppIcon.Action.refresh)
                }
                .controlSize(.small)
            }

            OpsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("URL check")
                        .font(.sora(13, weight: .semibold))
                    HStack(spacing: 8) {
                        TextField("https://example.com", text: $store.urlInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.sora(12))
                            .onSubmit { store.runURLDiagnostics() }
                        Button {
                            store.runURLDiagnostics()
                        } label: {
                            Label("Run", systemImage: AppIcon.Action.play)
                        }
                        .controlSize(.small)
                        .disabled(!store.canRunAction || store.urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let result = store.urlDiagnosticResult {
                        if let error = result.errorMessage {
                            Text(error)
                                .font(.sora(11))
                                .foregroundStyle(Color.red)
                        }
                        if let expiration = result.tlsExpiration {
                            OpsKeyValue("TLS expires", expiration.formatted(date: .abbreviated, time: .shortened))
                        }
                        if !result.headerText.isEmpty {
                            OpsCodeBlock(result.headerText)
                        }
                    }
                }
            }

            OpsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Proxy")
                        .font(.sora(13, weight: .semibold))
                    OpsCodeBlock(store.diagnostics.proxySummary)
                }
            }

            if !store.diagnostics.errors.isEmpty {
                OpsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Command errors")
                            .font(.sora(13, weight: .semibold))
                        OpsCodeBlock(store.diagnostics.errors.joined(separator: "\n"))
                    }
                }
            }

            OpsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("DNS")
                        .font(.sora(13, weight: .semibold))
                    OpsCodeBlock(store.diagnostics.dnsSummary)
                }
            }

            OpsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hosts")
                        .font(.sora(13, weight: .semibold))
                    if store.diagnostics.hostsEntries.isEmpty {
                        OpsInlineEmptyState("No active hosts entries.")
                    } else {
                        ForEach(store.diagnostics.hostsEntries.prefix(40)) { entry in
                            HStack(spacing: 10) {
                                Text("\(entry.lineNumber)")
                                    .font(.sora(10).monospacedDigit())
                                    .foregroundStyle(Color.stxMuted)
                                    .frame(width: 34, alignment: .trailing)
                                Text(entry.rawLine)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct OpsTableToolbar: View {
    @Binding var searchText: String
    let placeholder: String
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            OpsSearchField(text: $searchText, placeholder: placeholder)
            Button(action: refresh) {
                Label("Refresh", systemImage: AppIcon.Action.refresh)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct OpsSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: AppIcon.Action.search)
                .font(.system(size: 11))
                .foregroundStyle(Color.stxMuted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.sora(11))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: AppIcon.Action.clear)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
    }
}

private struct OpsPortHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Port").frame(width: 58, alignment: .trailing)
            Text("Process").frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
            Text("User").frame(width: 80, alignment: .leading)
            Text("PID").frame(width: 62, alignment: .trailing)
        }
        .font(.sora(10, weight: .semibold))
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Color.primary.opacity(0.025))
    }
}

private struct OpsPortRow: View {
    let item: OpsPortItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("\(item.port)")
                    .font(.sora(12).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.stxAccent : .primary)
                    .frame(width: 58, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.processName)
                        .font(.sora(12, weight: .medium))
                        .lineLimit(1)
                    Text(item.displayAddress)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }
                .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
                Text(item.user.isEmpty ? "--" : item.user)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .frame(width: 80, alignment: .leading)
                Text("\(item.pid)")
                    .font(.sora(11).monospacedDigit())
                    .foregroundStyle(item.protection.reason == nil ? Color.stxMuted : Color.orange)
                    .frame(width: 62, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.10))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
    }
}

private struct OpsProcessHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("PID").frame(width: 62, alignment: .trailing)
            Text("Process").frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            Text("CPU").frame(width: 58, alignment: .trailing)
            Text("MEM").frame(width: 58, alignment: .trailing)
            Text("User").frame(width: 80, alignment: .leading)
        }
        .font(.sora(10, weight: .semibold))
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Color.primary.opacity(0.025))
    }
}

private struct OpsProcessRow: View {
    let item: OpsProcessItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("\(item.pid)")
                    .font(.sora(11).monospacedDigit())
                    .foregroundStyle(item.protection.reason == nil ? Color.stxMuted : Color.orange)
                    .frame(width: 62, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.displayName)
                            .font(.sora(12, weight: .medium))
                            .lineLimit(1)
                        if item.isDeveloperProcess {
                            OpsMiniBadge("dev")
                        }
                    }
                    Text(item.commandLine)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }
                .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                Text(String(format: "%.1f", item.cpuPercent))
                    .font(.sora(11).monospacedDigit())
                    .frame(width: 58, alignment: .trailing)
                Text(String(format: "%.1f", item.memoryPercent))
                    .font(.sora(11).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                    .frame(width: 58, alignment: .trailing)
                Text(item.user)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .frame(width: 80, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.10))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
    }
}

private struct OpsBrewPackageRow: View {
    let package: OpsBrewPackage
    let isSelected: Bool
    let actionsDisabled: Bool
    let select: () -> Void
    let upgrade: () -> Void
    let uninstall: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: select) {
                HStack(spacing: 10) {
                    Image(systemName: package.kind == .formula ? "shippingbox" : "app.dashed")
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(package.name)
                            .font(.sora(12, weight: .medium))
                        Text(package.installedVersion)
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                    }
                    Spacer()
                    if package.isOutdated {
                        OpsMiniBadge(package.latestVersion ?? "update")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: upgrade) {
                Image(systemName: AppIcon.Navigation.upCircle)
            }
            .buttonStyle(.plain)
            .disabled(!package.isOutdated || actionsDisabled)
            .help("Upgrade")

            Button(role: .destructive, action: uninstall) {
                Image(systemName: AppIcon.Action.delete)
            }
            .buttonStyle(.plain)
            .disabled(actionsDisabled)
            .help("Uninstall")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.10))
            }
        }
    }
}

private struct OpsBrewServiceRow: View {
    let service: OpsBrewServiceItem
    let actionsDisabled: Bool
    let action: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(service.status == "started" ? Color.green : Color.stxMuted.opacity(0.35))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.sora(12, weight: .medium))
                Text("\(service.status)\(service.user.isEmpty ? "" : " - \(service.user)")")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer()
            Button("Start") { action("start") }.controlSize(.small).disabled(actionsDisabled)
            Button("Stop") { action("stop") }.controlSize(.small).disabled(actionsDisabled)
            Button("Restart") { action("restart") }.controlSize(.small).disabled(actionsDisabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

private struct OpsEnvironmentToolCard: View {
    let tool: OpsEnvironmentTool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                    .frame(width: 18)
                Text(tool.name)
                    .font(.sora(13, weight: .semibold))
                Spacer()
                Text(tool.status.title)
                    .font(.sora(10, weight: .medium))
                    .foregroundStyle(statusColor)
            }
            Text(tool.version ?? tool.detail ?? "Not installed")
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(2)
            if let path = tool.resolvedPath {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.stxMuted.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if tool.resolvedPath != nil, !tool.isTrustedPath {
                Text("Non-standard PATH")
                    .font(.sora(10, weight: .medium))
                    .foregroundStyle(Color.orange)
            }
        }
        .mainWindowPanel(padding: 12)
    }

    private var statusSymbol: String {
        switch tool.status {
        case .available: AppIcon.Status.successFilled
        case .missing: AppIcon.Action.removeCircle
        case .error: AppIcon.Status.warningFilled
        }
    }

    private var statusColor: Color {
        switch tool.status {
        case .available: Color.green
        case .missing: Color.stxMuted
        case .error: Color.orange
        }
    }
}

private struct OpsCleanupRow: View {
    let item: OpsCleanupItem
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 18)
                Image(systemName: item.kind.symbol)
                    .foregroundStyle(Color.stxMuted)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.kind.title)
                        .font(.sora(13, weight: .semibold))
                    Text(item.path ?? item.detail)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(item.sizeBytes.map(opsBytes) ?? (item.isAvailable ? "Available" : "Missing"))
                    .font(.sora(11).monospacedDigit())
                    .foregroundStyle(item.isAvailable ? .primary : Color.stxMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isActionable)
        .mainWindowPanel(padding: 12)
    }
}

private struct OpsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content.mainWindowPanel(padding: 14)
    }
}

private struct OpsActionOutputCard: View {
    let output: String
    let clear: () -> Void

    var body: some View {
        OpsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Last action")
                        .font(.sora(13, weight: .semibold))
                    Spacer()
                    Button {
                        clear()
                    } label: {
                        Image(systemName: AppIcon.Action.cancel)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
                OpsCodeBlock(output)
            }
        }
    }
}

private struct OpsInspectorContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct OpsInspectorTitle: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.stxAccent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sora(18, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
        }
    }
}

private struct OpsInspectorGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.sora(11, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
                .tracking(0.6)
            content
        }
        .mainWindowPanel(padding: 12)
    }
}

private struct OpsKeyValue: View {
    let key: String
    let value: String

    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.sora(11))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

private struct OpsCodeBlock: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text.isEmpty ? "--" : text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.86))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct OpsInlineEmptyState: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.sora(12))
            .foregroundStyle(Color.stxMuted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(18)
    }
}

private struct OpsMiniBadge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.sora(9, weight: .semibold))
            .foregroundStyle(Color.stxAccent)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.stxAccent.opacity(0.12), in: Capsule())
    }
}

private func opsBytes(_ count: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: count)
}
