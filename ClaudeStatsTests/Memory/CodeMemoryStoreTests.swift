import Foundation
import Testing
@testable import ClaudeStats

@Suite("Code Memory store")
struct CodeMemoryStoreTests {
    @MainActor
    @Test("Refresh loads sidecar health and projects from backend")
    func refreshLoadsSidecarState() async throws {
        let backend = FakeCodeMemoryBackend()
        let store = MemoryStore(codeBackend: backend)

        await store.refreshCodeMemoryStatus()

        #expect(store.codeHealth?.status == "ok")
        #expect(store.codeProjects.map(\.projectID) == ["claude-stats"])
        #expect(store.codeSelectedProjectID == "claude-stats")
    }

    @MainActor
    @Test("Search stores sidecar results")
    func searchStoresSidecarResults() async throws {
        let backend = FakeCodeMemoryBackend()
        let store = MemoryStore(codeBackend: backend)

        store.searchText = "run-debug"
        await store.performSearch()

        #expect(backend.searchQueries == ["run-debug"])
        #expect(store.codeSearchResults.first?.memory.title == "Use run-debug")
    }

    @MainActor
    @Test("Accepting a proposal drains projection jobs")
    func acceptingProposalDrainsProjectionJobs() async throws {
        let backend = FakeCodeMemoryBackend()
        let proposal = FakeCodeMemoryBackend.memory(id: "memory:proposal", status: "proposed")
        backend.proposalResponse = [proposal]
        let store = MemoryStore(codeBackend: backend)

        await store.acceptProposal(proposal)

        #expect(backend.acceptedMemoryIDs == ["memory:proposal"])
        #expect(backend.projectionDrainCount == 1)
        #expect(store.codeLastProjectionDrainResult?.delivered == 1)
    }
}

private final class FakeCodeMemoryBackend: CodeMemoryBackend, @unchecked Sendable {
    var searchQueries: [String] = []
    var acceptedMemoryIDs: [String] = []
    var projectionDrainCount = 0
    var proposalResponse: [CodeMemoryMemory] = []

    func health() async throws -> CodeMemoryHealth {
        CodeMemoryHealth(
            status: "ok",
            store: "/tmp/code-memory.sqlite3",
            eventCount: 1,
            memoryCount: 1,
            adapters: ["mem0": "disabled", "graphiti": "disabled"]
        )
    }

    func projects() async throws -> [CodeMemoryProject] {
        [CodeMemoryProject(projectID: "claude-stats", memoryCount: 1, updatedAt: nil)]
    }

    func search(query: String, projectID: String?, limit: Int) async throws -> CodeMemorySearchResponse {
        searchQueries.append(query)
        return CodeMemorySearchResponse(
            query: query,
            traceID: "run:test",
            results: [
                CodeMemorySearchResult(
                    rank: 1,
                    score: 1,
                    memory: Self.memory(id: "memory:test", status: "active"),
                    matchKind: "text"
                ),
            ]
        )
    }

    func proposals(projectID: String?, limit: Int) async throws -> [CodeMemoryMemory] {
        proposalResponse
    }

    func accept(memoryID: String) async throws {
        acceptedMemoryIDs.append(memoryID)
    }

    func drainProjections() async throws -> CodeMemoryProjectionDrainResponse {
        projectionDrainCount += 1
        return CodeMemoryProjectionDrainResponse(delivered: 1, failed: 0, remaining: 0)
    }

    func graph(projectID: String) async throws -> CodeMemoryGraph {
        CodeMemoryGraph(projectID: projectID, nodes: [], edges: [])
    }

    func trace(runID: String) async throws -> CodeMemoryRunTrace {
        CodeMemoryRunTrace(runID: runID, projectID: nil, timestamp: nil, request: nil, repoState: [:], memoryUsage: [])
    }

    func recordEvent(_ event: CodeMemoryEventInput) async throws {}

    static func memory(id: String, status: String) -> CodeMemoryMemory {
        CodeMemoryMemory(
            id: id,
            projectID: "claude-stats",
            type: "command",
            status: status,
            title: "Use run-debug",
            body: "After changing code, run bash scripts/run-debug.sh.",
            normalizedClaim: "run debug after code changes",
            confidence: 1,
            importance: 1,
            scopes: [],
            sourceRefs: [],
            metadata: nil,
            createdAt: 0,
            updatedAt: 0
        )
    }
}
