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
}

private final class FakeCodeMemoryBackend: CodeMemoryBackend, @unchecked Sendable {
    var searchQueries: [String] = []

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
                    memory: CodeMemoryMemory(
                        id: "memory:test",
                        projectID: "claude-stats",
                        type: "command",
                        status: "active",
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
                    ),
                    matchKind: "text"
                ),
            ]
        )
    }

    func graph(projectID: String) async throws -> CodeMemoryGraph {
        CodeMemoryGraph(projectID: projectID, nodes: [], edges: [])
    }

    func trace(runID: String) async throws -> CodeMemoryRunTrace {
        CodeMemoryRunTrace(runID: runID, projectID: nil, timestamp: nil, request: nil, repoState: [:], memoryUsage: [])
    }

    func recordEvent(_ event: CodeMemoryEventInput) async throws {}
}
