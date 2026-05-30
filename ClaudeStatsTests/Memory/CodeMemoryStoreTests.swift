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
        #expect(store.codeLastTraceID == "run:test")
    }

    @MainActor
    @Test("Unified search keeps graph facts sources and trace id separate")
    func unifiedSearchKeepsGraphFactsSourcesAndTraceID() async throws {
        let backend = FakeCodeMemoryBackend()
        backend.unifiedSearchResponse = CodeMemoryUnifiedSearchResponse(
            query: "graph",
            traceID: "run:graph",
            memoryResults: [
                CodeMemorySearchResult(rank: 1, score: 1, memory: Self.memory(id: "memory:canonical", status: "active"), matchKind: "text"),
            ],
            graphResults: [
                CodeMemoryGraphFact(
                    id: "graphiti:edge",
                    projectID: "claude-stats",
                    title: "Graph fact",
                    fact: "A depends on B.",
                    relation: "DEPENDS_ON",
                    source: "A",
                    target: "B",
                    validAt: "2026-05-01T00:00:00+00:00",
                    invalidAt: nil,
                    score: 0.7,
                    sourceRefs: [CodeMemorySourceRef(kind: "graphiti", uri: "edge")],
                    metadata: ["adapter": "graphiti"],
                    evidence: nil
                ),
            ],
            sourceResults: [
                CodeMemoryEpisode(
                    id: "episode:source",
                    projectID: "claude-stats",
                    kind: "AGENTS.md",
                    title: "AGENTS.md",
                    uri: "file:///AGENTS.md",
                    path: "/repo/AGENTS.md",
                    contentHash: "abc",
                    excerpt: "Use run-debug.",
                    metadata: nil,
                    updatedAt: 0
                ),
            ]
        )
        let store = MemoryStore(codeBackend: backend)

        store.searchText = "graph"
        await store.performSearch()

        #expect(store.codeLastTraceID == "run:graph")
        #expect(store.codeSearchResults.count == 1)
        #expect(store.codeGraphResults.first?.id == "graphiti:edge")
        #expect(store.codeSourceResults.first?.id == "episode:source")
    }

    @MainActor
    @Test("Context pack uses query fallback and stores trace id")
    func contextPackUsesQueryFallbackAndStoresTraceID() async throws {
        let backend = FakeCodeMemoryBackend()
        backend.contextPackResponse = CodeMemoryContextPack(
            query: "run-debug",
            traceID: "run:context",
            context: CodeMemoryContextGroups(rules: [], facts: [Self.memory(id: "memory:context", status: "active")], risks: [], commands: [], decisions: [])
        )
        let store = MemoryStore(codeBackend: backend)

        store.searchText = "run-debug"
        await store.loadContextPack()

        #expect(backend.contextQueries == ["run-debug"])
        #expect(store.codeLastTraceID == "run:context")
        #expect(store.codeContextPack?.context.facts.first?.id == "memory:context")
    }

    @MainActor
    @Test("Transcript sync sends parsed conversation text instead of raw JSONL")
    func transcriptSyncUsesParsedConversationText() async throws {
        let backend = FakeCodeMemoryBackend()
        let store = MemoryStore(codeBackend: backend)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let raw = """
        {"timestamp":"2026-05-29T00:00:00.000Z","type":"session_meta","payload":{"id":"s","cwd":"/repo/claude-stats","base_instructions":{"text":"SECRET BASE INSTRUCTIONS"}}}
        {"timestamp":"2026-05-29T00:00:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"Remember to run tests."}}
        {"timestamp":"2026-05-29T00:00:02.000Z","type":"event_msg","payload":{"type":"agent_message","message":"I will run bash scripts/run-tests.sh."}}
        """
        try raw.write(to: url, atomically: true, encoding: .utf8)
        let session = Session(
            id: "codex::s",
            externalID: "s",
            provider: .codex,
            projectDirectoryName: "-repo-claude-stats",
            filePath: url.path,
            cwd: "/repo/claude-stats",
            lastModified: Date(timeIntervalSince1970: 0),
            fileSize: 1_024,
            stats: nil
        )

        await store.syncAvailableSources(sessions: [session], configProjects: [])

        #expect(backend.ingestedSources.count == 1)
        let source = try #require(backend.ingestedSources.first)
        #expect(source.kind == "codex_transcript")
        #expect(source.infer)
        #expect(source.body.contains("User: Remember to run tests."))
        #expect(source.body.contains("Assistant: I will run bash scripts/run-tests.sh."))
        #expect(!source.body.contains("session_meta"))
        #expect(!source.body.contains("SECRET BASE INSTRUCTIONS"))
    }

    @MainActor
    @Test("Config sync uses specific source-only kinds")
    func configSyncUsesSpecificSourceOnlyKinds() async throws {
        let backend = FakeCodeMemoryBackend()
        let store = MemoryStore(codeBackend: backend)
        let documents = [
            Self.configDocument(title: "config.toml", kind: .providerConfig, fileKind: .toml, path: "/repo/.codex/config.toml"),
            Self.configDocument(title: "installed_plugins.json", kind: .pluginConfig, fileKind: .json, path: "/repo/.claude/plugins/installed_plugins.json"),
            Self.configDocument(title: "repair-plan.md", kind: .plan, fileKind: .markdown, path: "/repo/.codex/plans/repair-plan.md"),
            Self.configDocument(title: "AGENTS.md", kind: .instruction, fileKind: .markdown, path: "/repo/AGENTS.md"),
            Self.configDocument(title: "other.json", kind: .other, fileKind: .json, path: "/repo/other.json"),
        ]
        let project = AIConfigProject(kind: .project, name: "repo", path: "/repo", documents: documents)

        await store.syncAvailableSources(sessions: [], configProjects: [project])

        let kindByTitle = Dictionary(uniqueKeysWithValues: backend.ingestedSources.map { ($0.title, $0.kind) })
        #expect(kindByTitle["config.toml"] == "provider_config")
        #expect(kindByTitle["installed_plugins.json"] == "plugin_config")
        #expect(kindByTitle["repair-plan.md"] == "plan")
        #expect(kindByTitle["AGENTS.md"] == "AGENTS.md")
        #expect(kindByTitle["other.json"] == "ai_config")
        #expect(backend.ingestedSources.first { $0.title == "AGENTS.md" }?.infer == true)
        #expect(backend.ingestedSources.filter { $0.title != "AGENTS.md" }.allSatisfy { !$0.infer })
    }

    @MainActor
    @Test("Settings reinfer sources calls backend and stores result")
    func reinferSourcesCallsBackendAndStoresResult() async throws {
        let backend = FakeCodeMemoryBackend()
        backend.reinferResponse = CodeMemoryReinferSourcesResponse(status: "ok", scanned: 4, attempted: 3, proposed: 2, skipped: 1, errors: [])
        let store = MemoryStore(codeBackend: backend)
        store.codeSelectedProjectID = "claude-stats"

        await store.reinferCodeMemorySources()

        #expect(backend.reinferProjectIDs == ["claude-stats"])
        #expect(store.codeLastReinferResult?.attempted == 3)
        #expect(store.codeLastReinferResult?.proposed == 2)
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

    @MainActor
    @Test("Review reject update deprecate and failed projection retry call backend")
    func reviewActionsAndFailedProjectionRetryCallBackend() async throws {
        let backend = FakeCodeMemoryBackend()
        let memory = FakeCodeMemoryBackend.memory(id: "memory:review", status: "proposed")
        let store = MemoryStore(codeBackend: backend)

        await store.rejectProposal(memory)
        await store.deprecateMemory(memory)
        await store.updateMemory(memory, with: CodeMemoryMemoryUpdate(title: "Updated", body: nil, type: nil, status: nil, confidence: nil, importance: nil, validAt: nil, invalidAt: nil, reviewReason: "manual_review", extractedBy: nil))
        await store.drainCodeMemoryProjections(includeFailed: true)

        #expect(backend.rejectedMemoryIDs == ["memory:review"])
        #expect(backend.deprecatedMemoryIDs == ["memory:review"])
        #expect(backend.updatedMemoryIDs == ["memory:review"])
        #expect(backend.drainIncludeFailed == [true])
    }

    @MainActor
    @Test("Graph store preserves stable node and edge selection")
    func graphStoreSelectionUsesStableIDs() async throws {
        let backend = FakeCodeMemoryBackend()
        backend.graphResponse = CodeMemoryGraph(
            projectID: "claude-stats",
            nodes: [
                CodeMemoryGraphNode(id: "project:claude-stats", kind: "project", title: "claude-stats", type: nil, status: nil, seq: nil, body: nil, sourceRefs: nil, metadata: nil),
                CodeMemoryGraphNode(id: "memory:one", kind: "memory", title: "One", type: "fact", status: "active", seq: nil, body: "Body", sourceRefs: nil, metadata: nil),
            ],
            edges: [
                CodeMemoryGraphEdge(source: "memory:one", target: "project:claude-stats", kind: "SCOPED_TO", primary: true, fact: nil, validAt: nil, invalidAt: nil, metadata: nil),
            ]
        )
        let graphStore = MemoryGraphStore(backend: backend)

        await graphStore.load(projectID: "claude-stats")
        graphStore.selectNode("memory:one")
        graphStore.selectEdge("memory:one-SCOPED_TO-project:claude-stats")

        #expect(graphStore.selectedNode == nil)
        #expect(graphStore.selectedEdge?.kind == "SCOPED_TO")
    }

    @Test("Typed source refs decode dynamic provenance metadata")
    func typedSourceRefsDecodeDynamicMetadata() throws {
        let data = """
        {
          "kind": "manual",
          "uri": "file:///AGENTS.md",
          "source_id": "src:1",
          "episode_id": "episode:src:1",
          "line_start": "3",
          "line_end": 8,
          "extra": 42
        }
        """.data(using: .utf8)!

        let ref = try JSONDecoder().decode(CodeMemorySourceRef.self, from: data)

        #expect(ref.kind == "manual")
        #expect(ref.sourceID == "src:1")
        #expect(ref.episodeID == "episode:src:1")
        #expect(ref.lineStart == 3)
        #expect(ref.lineEnd == 8)
        #expect(ref.metadata["extra"] == "42")
    }

    private static func memory(id: String, status: String) -> CodeMemoryMemory {
        FakeCodeMemoryBackend.memory(id: id, status: status)
    }

    private static func configDocument(
        title: String,
        kind: AIConfigDocumentKind,
        fileKind: ProviderConfigFileKind,
        path: String
    ) -> AIConfigDocument {
        AIConfigDocument(
            id: "doc:\(title)",
            provider: .codex,
            title: title,
            path: path,
            kind: kind,
            fileKind: fileKind,
            location: .project(path: "/repo"),
            exists: true,
            isExpected: false,
            fileSize: 32,
            modifiedAt: nil,
            contentPreview: "\(title) body",
            isPreviewTruncated: false,
            assignedProjectPath: "/repo",
            stats: .empty,
            diagnostics: []
        )
    }
}

private final class FakeCodeMemoryBackend: CodeMemoryBackend, @unchecked Sendable {
    var searchQueries: [String] = []
    var contextQueries: [String] = []
    var acceptedMemoryIDs: [String] = []
    var rejectedMemoryIDs: [String] = []
    var deprecatedMemoryIDs: [String] = []
    var updatedMemoryIDs: [String] = []
    var drainIncludeFailed: [Bool] = []
    var projectionDrainCount = 0
    var proposalResponse: [CodeMemoryMemory] = []
    var unifiedSearchResponse: CodeMemoryUnifiedSearchResponse?
    var contextPackResponse: CodeMemoryContextPack?
    var graphResponse: CodeMemoryGraph?
    var ingestedSources: [CodeMemorySourceInput] = []
    var reinferProjectIDs: [String?] = []
    var reinferResponse = CodeMemoryReinferSourcesResponse(status: "ok", scanned: 0, attempted: 0, proposed: 0, skipped: 0, errors: [])

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

    func unifiedSearch(query: String, filter: CodeMemoryQueryFilter) async throws -> CodeMemoryUnifiedSearchResponse {
        searchQueries.append(query)
        if let unifiedSearchResponse {
            return unifiedSearchResponse
        }
        let response = CodeMemorySearchResponse(
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
        return CodeMemoryUnifiedSearchResponse(query: response.query, traceID: response.traceID, memoryResults: response.results, graphResults: [], sourceResults: [])
    }

    func contextPack(query: String, projectID: String?, limit: Int) async throws -> CodeMemoryContextPack {
        contextQueries.append(query)
        if let contextPackResponse {
            return contextPackResponse
        }
        return CodeMemoryContextPack(
            query: query,
            traceID: "run:context",
            context: CodeMemoryContextGroups(rules: [], facts: [Self.memory(id: "memory:context", status: "active")], risks: [], commands: [], decisions: [])
        )
    }

    func proposals(projectID: String?, limit: Int) async throws -> [CodeMemoryMemory] {
        proposalResponse
    }

    func accept(memoryID: String) async throws {
        acceptedMemoryIDs.append(memoryID)
    }

    func reject(memoryID: String) async throws {
        rejectedMemoryIDs.append(memoryID)
    }

    func deprecate(memoryID: String) async throws {
        deprecatedMemoryIDs.append(memoryID)
    }

    func update(memoryID: String, memory: CodeMemoryMemoryUpdate) async throws {
        updatedMemoryIDs.append(memoryID)
    }

    func drainProjections() async throws -> CodeMemoryProjectionDrainResponse {
        projectionDrainCount += 1
        return CodeMemoryProjectionDrainResponse(delivered: 1, failed: 0, remaining: 0)
    }

    func drainProjections(includeFailed: Bool) async throws -> CodeMemoryProjectionDrainResponse {
        drainIncludeFailed.append(includeFailed)
        projectionDrainCount += 1
        return CodeMemoryProjectionDrainResponse(delivered: 1, failed: 0, remaining: 0)
    }

    func graph(projectID: String) async throws -> CodeMemoryGraph {
        graphResponse ?? CodeMemoryGraph(projectID: projectID, nodes: [], edges: [])
    }

    func trace(runID: String) async throws -> CodeMemoryRunTrace {
        CodeMemoryRunTrace(runID: runID, projectID: nil, timestamp: nil, request: nil, repoState: [:], memoryUsage: [])
    }

    func ingestSource(_ source: CodeMemorySourceInput) async throws -> CodeMemorySyncSourceResponse {
        ingestedSources.append(source)
        return CodeMemorySyncSourceResponse(status: "ok", created: [], proposed: [])
    }

    func reinferSources(projectID: String?) async throws -> CodeMemoryReinferSourcesResponse {
        reinferProjectIDs.append(projectID)
        return reinferResponse
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
