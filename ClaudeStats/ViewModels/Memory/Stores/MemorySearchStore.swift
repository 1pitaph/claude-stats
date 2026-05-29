import Foundation
import Observation

@MainActor
@Observable
final class MemorySearchStore {
    var query = ""
    var contextQuery = ""
    private(set) var memoryResults: [CodeMemorySearchResult] = []
    private(set) var graphResults: [CodeMemoryGraphFact] = []
    private(set) var sourceResults: [CodeMemoryEpisode] = []
    private(set) var contextPack: CodeMemoryContextPack?
    private(set) var events: [CodeMemoryEvent] = []
    private(set) var trace: CodeMemoryRunTrace?
    private(set) var lastTraceID: String?
    private(set) var isSearching = false
    private(set) var isLoading = false
    private(set) var lastError: String?

    @ObservationIgnored private let backend: any CodeMemoryBackend

    init(backend: any CodeMemoryBackend) {
        self.backend = backend
    }

    func performSearch(projectID: String?) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear()
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let filter = CodeMemoryQueryFilter(
                projectID: projectID,
                statuses: ["active"],
                includeGraphFacts: true,
                limit: 30
            )
            let response = try await backend.unifiedSearch(query: trimmed, filter: filter)
            memoryResults = response.memoryResults
            graphResults = response.graphResults
            sourceResults = response.sourceResults
            lastTraceID = response.traceID
            lastError = nil
        } catch {
            memoryResults = []
            graphResults = []
            sourceResults = []
            lastError = error.localizedDescription
        }
    }

    func loadContextPack(projectID: String?) async {
        let trimmed = (contextQuery.isEmpty ? query : contextQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            contextPack = try await backend.contextPack(query: trimmed, projectID: projectID, limit: 12)
            lastTraceID = contextPack?.traceID
            lastError = nil
        } catch {
            contextPack = nil
            lastError = error.localizedDescription
        }
    }

    func loadEvents(projectID: String?) async {
        isLoading = true
        defer { isLoading = false }

        do {
            events = try await backend.events(projectID: projectID, afterSeq: nil, limit: 100)
            lastError = nil
        } catch {
            events = []
            lastError = error.localizedDescription
        }
    }

    func loadTrace(runID: String) async {
        let trimmed = runID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            trace = try await backend.trace(runID: trimmed)
            lastError = nil
        } catch {
            trace = nil
            lastError = error.localizedDescription
        }
    }

    func clear() {
        memoryResults = []
        graphResults = []
        sourceResults = []
        lastTraceID = nil
    }
}
