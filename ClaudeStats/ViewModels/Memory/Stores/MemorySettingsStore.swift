import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class MemorySettingsStore {
    private(set) var health: CodeMemoryHealth?
    private(set) var outboxLastDrainResult: CodeMemoryOutboxDrainResult?
    private(set) var lastProjectionDrainResult: CodeMemoryProjectionDrainResponse?
    private(set) var lastReindexResult: CodeMemoryProjectionDrainResponse?
    private(set) var lastReinferResult: CodeMemoryReinferSourcesResponse?
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var setupMessage: String?

    @ObservationIgnored private let backend: any CodeMemoryBackend
    @ObservationIgnored private let outbox: CodeMemoryEventOutbox

    init(backend: any CodeMemoryBackend, outbox: CodeMemoryEventOutbox) {
        self.backend = backend
        self.outbox = outbox
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

    func startSidecar(localAIEnvironment: CodeMemoryLocalAIEnvironment? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        do {
            let configuration = CodeMemorySidecarConfiguration(localAI: localAIEnvironment)
            let pid = try CodeMemorySidecarManager(configuration: configuration).start(helperPath: CodeMemorySidecarManager.defaultHelperPath())
            setupMessage = "Started memoryd pid=\(pid)."
            lastError = nil
        } catch {
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

    func reindex(projectID: String?) async {
        guard !isLoading else { return }
        isLoading = true
        AppLivenessRescue.arm(reason: "code memory reindex")
        defer { isLoading = false }

        do {
            lastReindexResult = try await backend.reindex(projectID: projectID)
            lastError = nil
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
        AppLivenessRescue.arm(reason: includeFailed ? "code memory failed projection retry" : "code memory projection drain")
        defer { isLoading = false }

        do {
            lastProjectionDrainResult = try await backend.drainProjections(includeFailed: includeFailed)
            if lastProjectionDrainResult?.skipped == true {
                lastError = lastProjectionDrainResult?.message ?? "Projection drain skipped."
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
