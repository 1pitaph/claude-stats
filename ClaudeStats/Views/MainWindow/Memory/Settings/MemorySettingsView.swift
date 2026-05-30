import SwiftUI

struct MemorySettingsView: View {
    @Bindable var store: MemoryStore
    @Environment(AppEnvironment.self) private var env

    private var helperPath: String {
        CodeMemorySidecarManager.defaultHelperPath()
    }

    private var startCommand: String {
        CodeMemorySidecarManager.shellCommand(arguments: ["memoryd", "start"])
    }

    var body: some View {
        CenteredPaneContainer(maxWidth: 940, topPadding: 18) {
            AppScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sidecarCard
                    projectionCard
                    adaptersCard
                    shellCard
                    runtimeContextCard
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var sidecarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sidecar")
                .font(.sora(15, weight: .semibold))
            fact("endpoint", "http://127.0.0.1:8765")
            fact("status", store.codeHealth?.status ?? "offline")
            fact("store", store.codeHealth?.store?.memoryAbbreviatingHomeDirectory ?? "-")
            fact("active", "\(store.codeHealth?.memoryCount ?? 0)")
            fact("total", "\(store.codeHealth?.totalMemoryCount ?? store.codeHealth?.memoryCount ?? 0)")
            fact("events", "\(store.codeHealth?.eventCount ?? 0)")
            fact("helper", helperPath.memoryAbbreviatingHomeDirectory)
            fact("command", startCommand)

            HStack(spacing: 8) {
                Button {
                    Task {
                        env.localAI.restartOpenAICompatibleServerIfNeeded()
                        await store.startCodeMemorySidecar(localAIEnvironment: env.localAI.localAIEnvironment())
                    }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .controlSize(.small)
                .disabled(store.isCodeMemoryLoading)

                Button {
                    Task { await store.stopCodeMemorySidecar() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .controlSize(.small)
                .disabled(store.isCodeMemoryLoading)

                Button {
                    Task { await store.refreshCodeMemoryStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(store.isCodeMemoryLoading)

                MemoryCopyButton(value: startCommand, label: "Copy Command")
            }

            if let message = store.setupMessage {
                Text(message)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private var projectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mem0 Capture")
                .font(.sora(15, weight: .semibold))
            HStack(spacing: 10) {
                AIConfigsMiniStat(value: "\(store.codeHealth?.capturePending ?? store.codeHealth?.projectionPending ?? 0)", label: "pending")
                AIConfigsMiniStat(value: "\(store.codeHealth?.captureFailed ?? store.codeHealth?.projectionFailed ?? 0)", label: "failed")
                AIConfigsMiniStat(value: "\(store.codeHealth?.migrationPending ?? 0)", label: "migration")
                if let result = store.codeLastProjectionDrainResult {
                    AIConfigsMiniStat(value: "\(result.delivered ?? 0)", label: "delivered")
                    AIConfigsMiniStat(value: "\(result.remaining ?? 0)", label: "remaining")
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await store.drainCodeMemoryProjections() }
                } label: {
                    Label("Drain Pending", systemImage: "tray.and.arrow.up")
                }
                .controlSize(.small)
                .disabled(store.isCodeMemoryLoading || store.codeHealth == nil)

                Button {
                    Task { await store.drainCodeMemoryProjections(includeFailed: true) }
                } label: {
                    Label("Retry Failed", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.small)
                .disabled(store.isCodeMemoryLoading || store.codeHealth == nil)

                Button {
                    Task { await store.reindexCodeMemory() }
                } label: {
                    Label("Refresh Cache", systemImage: "arrow.triangle.2.circlepath")
                }
                .controlSize(.small)
                .disabled(store.isCodeMemoryLoading || store.codeHealth == nil)

                Button {
                    Task { await store.reinferCodeMemorySources() }
                } label: {
                    Label("Recapture Sources", systemImage: "sparkles")
                }
                .controlSize(.small)
                .disabled(store.isCodeMemoryLoading || store.codeHealth == nil)
            }

            if let result = store.codeLastProjectionDrainResult {
                Text(projectionDrainSummary(result))
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
            if let result = store.codeLastReindexResult {
                Text(reindexSummary(result))
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
            if let result = store.codeLastReinferResult {
                Text(reinferSummary(result))
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
        }
        .padding(16)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private var adaptersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Adapters")
                .font(.sora(15, weight: .semibold))
            if let adapters = store.codeHealth?.adapters, !adapters.isEmpty {
                ForEach(adapters.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack(spacing: 10) {
                        Text(key)
                            .font(.sora(11, weight: .medium))
                            .frame(width: 130, alignment: .leading)
                        AIConfigsBadge(text: value, color: value == "ok" ? Color.stxAccent : Color.stxMuted)
                        Spacer(minLength: 0)
                    }
                }
            } else {
                MemoryMutedLine(text: "No adapter status.")
            }
        }
        .padding(16)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private var shellCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shell Capture")
                .font(.sora(15, weight: .semibold))
            ForEach(MemoryShell.allCases) { shell in
                let status = MemoryShellIntegrationManager().status(shell: shell)
                HStack(spacing: 10) {
                    Image(systemName: status.isInstalled ? "checkmark.circle" : "circle")
                        .foregroundStyle(status.isInstalled ? Color.stxAccent : Color.stxMuted)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(shell.rawValue)
                            .font(.sora(12, weight: .semibold))
                        Text(status.rcPath.memoryAbbreviatingHomeDirectory)
                            .font(.sora(10).monospaced())
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button {
                        store.installShell(shell: shell, helperPath: helperPath)
                    } label: {
                        Label("Install", systemImage: "square.and.arrow.down")
                    }
                    .controlSize(.small)
                    Button {
                        store.uninstallShell(shell: shell)
                    } label: {
                        Label("Uninstall", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
            }
            if let result = store.codeOutboxLastDrainResult {
                Text("Outbox: \(result.delivered) delivered, \(result.remaining) pending")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
        }
        .padding(16)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private var runtimeContextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Runtime Context")
                .font(.sora(15, weight: .semibold))
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Color.stxAccent)
                Text("Prompt injection is off")
                    .font(.sora(12, weight: .semibold))
                Spacer(minLength: 0)
                AIConfigsBadge(text: "preview only", color: Color.stxMuted)
            }
            MemoryMutedLine(text: "Context packs can be previewed in Search; chat requests do not include memory automatically.")
        }
        .padding(16)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.sora(11, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.sora(11).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func reindexSummary(_ result: CodeMemoryProjectionDrainResponse) -> String {
        if let drained = result.drained {
            return "Reindex: \(result.enqueued ?? 0) enqueued, \(drained.delivered ?? 0) delivered, \(drained.failed ?? 0) failed"
        }
        return "Reindex queued: \(result.enqueued ?? 0) enqueued, \(result.remaining ?? 0) pending/failed"
    }

    private func reinferSummary(_ result: CodeMemoryReinferSourcesResponse) -> String {
        let errorSuffix = result.errors.isEmpty ? "" : ", \(result.errors.count) adapter errors"
        return "Recapture: \(result.scanned) scanned, \(result.attempted) attempted, \(result.created) created, \(result.skipped) skipped\(errorSuffix)"
    }

    private func projectionDrainSummary(_ result: CodeMemoryProjectionDrainResponse) -> String {
        if result.skipped == true {
            let blockers = result.blockers?.keys.sorted().joined(separator: ", ") ?? "adapters"
            return "Capture drain skipped: \(blockers) unavailable, \(result.remaining ?? 0) remaining"
        }
        return result.message ?? "Capture: \(result.delivered ?? 0) delivered, \(result.failed ?? 0) failed, \(result.remaining ?? 0) remaining"
    }
}
