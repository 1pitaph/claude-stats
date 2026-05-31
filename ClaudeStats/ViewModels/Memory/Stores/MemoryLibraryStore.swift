import Foundation
import Observation

@MainActor
@Observable
final class MemoryLibraryStore {
    private static let projectSortModeDefaultsKey = "memory.projectSortMode"

    var selectedModuleID: String?
    var statusFilter = "active"
    var projectSortMode: MemoryProjectSortMode {
        didSet {
            defaults.set(projectSortMode.rawValue, forKey: Self.projectSortModeDefaultsKey)
        }
    }
    private(set) var projects: [CodeMemoryProject] = []
    private(set) var modules: [CodeMemoryModule] = []
    private(set) var memories: [CodeMemoryMemory] = []
    private(set) var isLoading = false
    private(set) var isLoadingProjectSortMetadata = false
    private(set) var lastError: String?

    @ObservationIgnored private let backend: any CodeMemoryBackend
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let projectSortMetadataResolver: any MemoryProjectSortMetadataResolving
    private var projectSortMetadata: MemoryProjectSortMetadata = .empty

    init(
        backend: any CodeMemoryBackend,
        defaults: UserDefaults = .standard,
        projectSortMetadataResolver: any MemoryProjectSortMetadataResolving = MemoryProjectSortMetadataResolver()
    ) {
        self.backend = backend
        self.defaults = defaults
        self.projectSortMetadataResolver = projectSortMetadataResolver
        self.projectSortMode = MemoryProjectSortMode(rawValue: defaults.string(forKey: Self.projectSortModeDefaultsKey) ?? "")
            ?? .recentGitCommit
    }

    var sortedProjects: [CodeMemoryProject] {
        MemoryProjectSorter.sorted(
            projects: projects,
            mode: projectSortMode,
            metadata: projectSortMetadata
        )
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

    func loadProjects() async {
        do {
            projects = try await backend.projects()
            lastError = nil
        } catch {
            projects = []
            modules = []
            memories = []
            lastError = error.localizedDescription
        }
    }

    func loadProjectContent(projectID: String?) async {
        do {
            modules = try await backend.modules(projectID: projectID)
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
            modules = []
            memories = []
            lastError = error.localizedDescription
        }
    }

    func refreshProjectSortMetadata(sessions: [Session]) async {
        guard !projects.isEmpty else {
            projectSortMetadata = .empty
            return
        }
        isLoadingProjectSortMetadata = true
        defer { isLoadingProjectSortMetadata = false }
        projectSortMetadata = await projectSortMetadataResolver.metadata(
            projects: projects,
            sessions: sessions
        )
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
