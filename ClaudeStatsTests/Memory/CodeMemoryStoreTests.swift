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
    @Test("Legacy import maps SQLite records into backend import request")
    func legacyImportMapsRecords() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let storage = MemorySQLiteStore(url: root.appendingPathComponent("memory.sqlite3"))
        let source = MemorySource(
            id: MemoryDefaults.terminalSourceID,
            kind: .terminal,
            providerRaw: nil,
            title: "Terminal",
            path: root.path,
            isDefault: true
        )
        try await storage.upsertSources([source])
        let record = MemoryRecord(
            id: "terminal:test",
            sourceID: source.id,
            kind: .terminalRun,
            title: "bash scripts/run-debug.sh",
            cwd: root.path
        )
        let block = MemoryBlock(
            id: "terminal:test:stdout",
            recordID: record.id,
            sourceID: source.id,
            ordinal: 0,
            role: .stdout,
            text: "build ok",
            ref: MemoryRef.terminal(recordID: record.id, blockID: "stdout"),
            textHash: MemorySQLiteStore.textHash("build ok")
        )
        try await storage.upsertRecord(record, blocks: [block])

        let backend = FakeCodeMemoryBackend()
        let store = MemoryStore(
            storage: storage,
            sourceStore: MemorySourceFileStore(url: root.appendingPathComponent("sources.json")),
            codeBackend: backend
        )
        await store.importLegacyRecords(kind: .terminalRun)

        let request = try #require(backend.importRequests.first)
        #expect(request.records.count == 1)
        #expect(request.records.first?.title == "bash scripts/run-debug.sh")
        #expect(store.codeLastImportResult?.imported == 1)
    }
}

private final class FakeCodeMemoryBackend: CodeMemoryBackend, @unchecked Sendable {
    var importRequests: [CodeMemoryLegacyImportRequest] = []

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
        CodeMemorySearchResponse(query: query, traceID: "run:test", results: [])
    }

    func graph(projectID: String) async throws -> CodeMemoryGraph {
        CodeMemoryGraph(projectID: projectID, nodes: [], edges: [])
    }

    func trace(runID: String) async throws -> CodeMemoryRunTrace {
        CodeMemoryRunTrace(runID: runID, projectID: nil, timestamp: nil, request: nil, repoState: [:], memoryUsage: [])
    }

    func recordEvent(_ event: CodeMemoryEventInput) async throws {}

    func importLegacy(_ request: CodeMemoryLegacyImportRequest) async throws -> CodeMemoryLegacyImportResponse {
        importRequests.append(request)
        return CodeMemoryLegacyImportResponse(imported: request.records.count, skipped: 0)
    }
}
