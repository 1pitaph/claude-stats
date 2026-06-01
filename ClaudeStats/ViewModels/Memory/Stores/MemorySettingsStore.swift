import AppKit
import Foundation
import Observation

enum MemoryDiagnosticsRetention: Int, CaseIterable, Identifiable, Sendable, Hashable {
    case threeDays = 3
    case sevenDays = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .threeDays: "最近 3 天"
        case .sevenDays: "最近 7 天"
        }
    }
}

@MainActor
@Observable
final class MemorySettingsStore {
    private static let diagnosticsRetentionDefaultsKey = "memory.diagnostics.retentionDays"

    private(set) var health: CodeMemoryHealth?
    private(set) var outboxLastDrainResult: CodeMemoryOutboxDrainResult?
    private(set) var lastProjectionDrainResult: CodeMemoryProjectionDrainResponse?
    private(set) var lastReindexResult: CodeMemoryProjectionDrainResponse?
    private(set) var lastReinferResult: CodeMemoryReinferSourcesResponse?
    private(set) var lastDiagnosticsConfigurationResult: CodeMemoryDiagnosticsConfigurationResponse?
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var setupMessage: String?
    var diagnosticsRetention: MemoryDiagnosticsRetention {
        didSet {
            defaults.set(diagnosticsRetention.rawValue, forKey: Self.diagnosticsRetentionDefaultsKey)
            MemoryDiagnosticsLog.prune(retentionDays: diagnosticsRetention.rawValue)
        }
    }

    @ObservationIgnored private let backend: any CodeMemoryBackend
    @ObservationIgnored private let outbox: CodeMemoryEventOutbox
    @ObservationIgnored private let defaults: UserDefaults

    init(backend: any CodeMemoryBackend, outbox: CodeMemoryEventOutbox, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.outbox = outbox
        self.defaults = defaults
        self.diagnosticsRetention = MemoryDiagnosticsRetention(rawValue: defaults.integer(forKey: Self.diagnosticsRetentionDefaultsKey)) ?? .threeDays
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            health = try await backend.health()
            if let apiVersion = health?.apiVersion, apiVersion < CodeMemorySidecarManager.requiredAPIVersion {
                lastError = "Code Memory sidecar is out of date: API v\(apiVersion), app requires v\(CodeMemorySidecarManager.requiredAPIVersion). Restart memoryd."
            } else {
                lastError = nil
            }
        } catch {
            health = nil
            lastError = "Code Memory sidecar is unavailable: \(error.localizedDescription)"
        }
    }

    func configureDiagnosticsRetention(_ retention: MemoryDiagnosticsRetention) async {
        diagnosticsRetention = retention
        MemoryDiagnosticsLog.record(
            "swift.diagnostics.retention.request",
            retentionDays: diagnosticsRetention.rawValue,
            fields: ["retention_days": "\(retention.rawValue)"]
        )
        do {
            lastDiagnosticsConfigurationResult = try await backend.configureDiagnostics(retentionDays: retention.rawValue)
            lastError = nil
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startSidecar(
        localAIEnvironment: CodeMemoryLocalAIEnvironment? = nil,
        modelRuntimeConfig: CodeMemoryModelRuntimeConfig? = nil
    ) async {
        guard !isLoading else { return }
        isLoading = true
        do {
            let configuration = CodeMemorySidecarConfiguration(
                localAI: localAIEnvironment,
                modelRuntimeConfig: modelRuntimeConfig,
                diagnosticsRetentionDays: diagnosticsRetention.rawValue
            )
            let pid = try CodeMemorySidecarManager(configuration: configuration).start(helperPath: CodeMemorySidecarManager.defaultHelperPath())
            MemoryDiagnosticsLog.record(
                "swift.sidecar.start",
                retentionDays: diagnosticsRetention.rawValue,
                fields: [
                    "pid": "\(pid)",
                    "adapters_enabled": "\((modelRuntimeConfig?.adaptersEnabled ?? localAIEnvironment?.adaptersEnabled) ?? false)",
                    "retention_days": "\(diagnosticsRetention.rawValue)",
                ]
            )
            setupMessage = "Started memoryd pid=\(pid)."
            lastError = nil
        } catch {
            MemoryDiagnosticsLog.record(
                "swift.sidecar.start.error",
                level: "error",
                retentionDays: diagnosticsRetention.rawValue,
                fields: ["error": error.localizedDescription]
            )
            setupMessage = error.localizedDescription
            lastError = error.localizedDescription
            isLoading = false
            return
        }

        isLoading = false
        try? await Task.sleep(nanoseconds: 300_000_000)
        outboxLastDrainResult = await outbox.drain()
        await refresh()
    }

    func stopSidecar() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let stopped = try CodeMemorySidecarManager().stop()
            setupMessage = stopped ? "Stopped memoryd." : "memoryd was not running."
            health = nil
            lastError = nil
        } catch {
            setupMessage = error.localizedDescription
            lastError = error.localizedDescription
        }
    }

    func reindex(projectID: String?, drain: Bool = false, drainLimit: Int? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        AppLivenessRescue.arm(reason: drain ? "code memory graphiti reindex drain" : "code memory reindex")
        defer { isLoading = false }

        do {
            lastReindexResult = try await backend.reindex(projectID: projectID, drain: drain, drainLimit: drainLimit)
            if lastReindexResult?.skipped == true {
                lastError = lastReindexResult?.message ?? "Graphiti reindex skipped."
            } else {
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reinferSources(projectID: String?) async {
        guard !isLoading else { return }
        isLoading = true
        AppLivenessRescue.arm(reason: "code memory source reinfer")
        defer { isLoading = false }

        do {
            lastReinferResult = try await backend.reinferSources(projectID: projectID)
            if let errors = lastReinferResult?.errors, !errors.isEmpty {
                lastError = "Source reinfer completed with \(errors.count) adapter error(s)."
            } else {
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func drainProjections(includeFailed: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        AppLivenessRescue.arm(reason: includeFailed ? "code memory failed capture retry" : "code memory capture drain")
        defer { isLoading = false }

        do {
            lastProjectionDrainResult = try await backend.drainProjections(includeFailed: includeFailed)
            if lastProjectionDrainResult?.skipped == true {
                lastError = lastProjectionDrainResult?.message ?? "Mem0 capture drain skipped."
            } else {
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func installShell(shell: MemoryShell, helperPath: String) {
        do {
            let backup = try MemoryShellIntegrationManager().install(shell: shell, helperPath: helperPath)
            setupMessage = backup.map { "Installed \(shell.rawValue); backup at \($0.path.memoryAbbreviatingHomeDirectory)." }
                ?? "\(shell.rawValue) integration is already installed."
            lastError = nil
        } catch {
            setupMessage = error.localizedDescription
            lastError = error.localizedDescription
        }
    }

    func uninstallShell(shell: MemoryShell) {
        do {
            let backup = try MemoryShellIntegrationManager().uninstall(shell: shell)
            setupMessage = backup.map { "Uninstalled \(shell.rawValue); backup at \($0.path.memoryAbbreviatingHomeDirectory)." }
                ?? "\(shell.rawValue) integration was not installed."
            lastError = nil
        } catch {
            setupMessage = error.localizedDescription
            lastError = error.localizedDescription
        }
    }
}
