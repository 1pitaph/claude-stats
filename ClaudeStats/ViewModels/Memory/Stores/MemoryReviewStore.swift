import Foundation
import Observation

@MainActor
@Observable
final class MemoryReviewStore {
    private(set) var proposals: [CodeMemoryMemory] = []
    private(set) var conflicts: [CodeMemoryMemory] = []
    private(set) var lowConfidence: [CodeMemoryMemory] = []
    private(set) var graphFacts: [CodeMemoryGraphFact] = []
    private(set) var lastProjectionDrainResult: CodeMemoryProjectionDrainResponse?
    private(set) var isLoading = false
    private(set) var lastError: String?

    @ObservationIgnored private let backend: any CodeMemoryBackend

    init(backend: any CodeMemoryBackend) {
        self.backend = backend
    }

    var totalCount: Int {
        proposals.count + conflicts.count + lowConfidence.count + graphFacts.count
    }

    func load(projectID: String?) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await backend.reviewItems(projectID: projectID, limit: 100)
            proposals = response.proposals
            conflicts = response.conflicts
            lowConfidence = response.lowConfidence
            graphFacts = response.graphFacts
            lastError = nil
        } catch {
            proposals = []
            conflicts = []
            lowConfidence = []
            graphFacts = []
            lastError = error.localizedDescription
        }
    }

    func accept(_ memory: CodeMemoryMemory) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await backend.accept(memoryID: memory.id)
            lastProjectionDrainResult = try await backend.drainProjections()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reject(_ memory: CodeMemoryMemory) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await backend.reject(memoryID: memory.id)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deprecate(_ memory: CodeMemoryMemory) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await backend.deprecate(memoryID: memory.id)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func update(_ memory: CodeMemoryMemory, with update: CodeMemoryMemoryUpdate) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await backend.update(memoryID: memory.id, memory: update)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func promote(_ fact: CodeMemoryGraphFact) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let memory = try await backend.promoteGraphFact(fact)
            proposals.insert(memory, at: 0)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
