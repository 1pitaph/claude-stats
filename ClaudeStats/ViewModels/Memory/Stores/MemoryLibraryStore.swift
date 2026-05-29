import Foundation
import Observation

@MainActor
@Observable
final class MemoryLibraryStore {
    var selectedModuleID: String?
    var statusFilter = "active"
    private(set) var projects: [CodeMemoryProject] = []
    private(set) var modules: [CodeMemoryModule] = []
    private(set) var memories: [CodeMemoryMemory] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    @ObservationIgnored private let backend: any CodeMemoryBackend

    init(backend: any CodeMemoryBackend) {
        self.backend = backend
    }

    func load(projectID: String?) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            projects = try await backend.projects()
            let resolvedProjectID = projectID ?? projects.first?.projectID
            modules = try await backend.modules(projectID: resolvedProjectID)
            memories = try await backend.memories(
                filter: CodeMemoryQueryFilter(
                    projectID: resolvedProjectID,
                    moduleID: selectedModuleID,
                    statuses: [statusFilter],
                    includeGraphFacts: false,
                    limit: 250
                )
            )
            lastError = nil
        } catch {
            projects = []
            modules = []
            memories = []
            lastError = error.localizedDescription
        }
    }

    func loadModules(projectID: String?) async {
        do {
            modules = try await backend.modules(projectID: projectID)
            lastError = nil
        } catch {
            modules = []
            lastError = error.localizedDescription
        }
    }

    func loadMemories(projectID: String?) async {
        do {
            memories = try await backend.memories(
                filter: CodeMemoryQueryFilter(
                    projectID: projectID,
                    moduleID: selectedModuleID,
                    statuses: [statusFilter],
                    includeGraphFacts: false,
                    limit: 250
                )
            )
            lastError = nil
        } catch {
            memories = []
            lastError = error.localizedDescription
        }
    }
}
