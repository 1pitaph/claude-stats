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

    @Test("HTTP client encodes path parameters once")
    func httpClientEncodesPathParametersOnce() async throws {
        MockCodeMemoryURLProtocol.capturedURLs = []
        MockCodeMemoryURLProtocol.handler = { request in
            MockCodeMemoryResponse(
                status: 200,
                headers: [:],
                data: Data(#"{"project_id":"/Users/1pitaph/dev/mac/claude-stats","nodes":[],"edges":[]}"#.utf8)
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockCodeMemoryURLProtocol.self]
        let client = CodeMemoryHTTPClient(
            baseURL: URL(string: "http://memory.test")!,
            session: URLSession(configuration: configuration)
        )

        _ = try await client.graph(projectID: "/Users/1pitaph/dev/mac/claude-stats")

        let url = try #require(MockCodeMemoryURLProtocol.capturedURLs.first)
        let encodedPath = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath)
        #expect(encodedPath.contains("/v1/projects/%2FUsers%2F1pitaph%2Fdev%2Fmac%2Fclaude-stats/graph"))
        #expect(!encodedPath.contains("%252FUsers"))
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(queryItems.contains { $0.name == "include_events" && $0.value == "false" })
        #expect(queryItems.contains { $0.name == "node_limit" && $0.value == "700" })
    }

    @Test("Code memory events decode dynamic before after and delta payloads")
    func codeMemoryEventsDecodeDynamicPayloads() throws {
        let data = """
        {
          "event_id": "event:update",
          "seq": 12,
          "timestamp": 42,
          "project_id": "claude-stats",
          "actor": {"kind": "human", "id": "tester"},
          "event_type": "updated",
          "memory_id": "memory:one",
          "before": {"title": "Old", "confidence": 0.7, "active": true},
          "after": {"title": "New", "status": "active", "nested": {"count": 2}},
          "delta": {"title": ["Old", "New"]},
          "source_refs": [],
          "hash": "h",
          "prev_hash": "p"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder.codeMemoryDecoder.decode(CodeMemoryEvent.self, from: data)

        #expect(event.before?.displayValue("title") == "Old")
        #expect(event.before?.displayValue("confidence") == "0.7")
        #expect(event.before?.displayValue("active") == "true")
        #expect(event.after?["nested"]?.objectValue?["count"]?.displayString == "2")
        #expect(event.delta?["title"]?.arrayValue?.map(\.displayString) == ["Old", "New"])
    }

    @Test("Kinds none hides every knowledge graph node")
    func kindsNoneHidesKnowledgeGraphNodes() {
        let nodes = [
            CodeMemoryGraphNode(id: "memory:one", kind: "memory", title: "One", type: nil, status: nil, seq: nil, body: nil, sourceRefs: nil, metadata: nil),
            CodeMemoryGraphNode(id: "episode:one", kind: "episode", title: "Episode", type: nil, status: nil, seq: nil, body: nil, sourceRefs: nil, metadata: nil),
        ]

        let none = MemoryKnowledgeGraphFilter.nodes(
            nodes,
            selectedKinds: [],
            showCanonical: true,
            showEpisodes: true,
            showEvents: true,
            showGraphiti: true,
            asOf: nil,
            searchText: ""
        )
        let all = MemoryKnowledgeGraphFilter.nodes(
            nodes,
            selectedKinds: Set(nodes.map(\.kind)),
            showCanonical: true,
            showEpisodes: true,
            showEvents: true,
            showGraphiti: true,
            asOf: nil,
            searchText: ""
        )

        #expect(none.isEmpty)
        #expect(all.count == 2)
    }

    @Test("Graph render limiter caps large graphs and keeps valid edges")
    func graphRenderLimiterCapsLargeGraphs() {
        let nodes = [
            CodeMemoryGraphNode(id: "project:p", kind: "project", title: "p", type: nil, status: nil, seq: nil, body: nil, sourceRefs: nil, metadata: nil),
        ] + (0..<240).map { index in
            CodeMemoryGraphNode(id: "memory:\(index)", kind: "memory", title: "Memory \(index)", type: nil, status: "active", seq: nil, body: nil, sourceRefs: nil, metadata: nil)
        }
        let edges = (0..<240).map { index in
            CodeMemoryGraphEdge(source: "memory:\(index)", target: "project:p", kind: "SCOPED_TO", primary: true, fact: nil, validAt: nil, invalidAt: nil, metadata: nil)
        }

        let render = MemoryGraphRenderLimiter.limit(
            nodes: nodes,
            edges: edges,
            maxNodes: 80,
            maxEdges: 90,
            selectedNodeID: nil,
            selectedEdgeID: nil
        )

        #expect(render.isLimited)
        #expect(render.nodes.count == 80)
        #expect(render.edges.count <= 90)
        #expect(render.nodes.contains { $0.id == "project:p" })
        let visibleNodeIDs = Set(render.nodes.map(\.id))
        #expect(render.edges.allSatisfy { visibleNodeIDs.contains($0.source) && visibleNodeIDs.contains($0.target) })
        #expect(render.usesCompactNodes)
        #expect(!render.showsEdgeHitTargets)
    }

    @Test("Graph edges keep legacy ids unless metadata differentiates duplicates")
    func graphEdgesKeepStableAndDistinctIDs() {
        let plain = CodeMemoryGraphEdge(source: "memory:one", target: "project:p", kind: "SCOPED_TO", primary: true, fact: nil, validAt: nil, invalidAt: nil, metadata: nil)
        let first = CodeMemoryGraphEdge(source: "memory:one", target: "project:p", kind: "SCOPED_TO", primary: nil, fact: nil, validAt: nil, invalidAt: nil, metadata: ["uuid": "one"])
        let second = CodeMemoryGraphEdge(source: "memory:one", target: "project:p", kind: "SCOPED_TO", primary: nil, fact: nil, validAt: nil, invalidAt: nil, metadata: ["uuid": "two"])

        #expect(plain.id == "memory:one-SCOPED_TO-project:p")
        #expect(first.id != second.id)
    }

    @Test("Graph response decodes truncation metadata")
    func graphResponseDecodesTruncationMetadata() throws {
        let data = """
        {
          "project_id": "p",
          "nodes": [],
          "edges": [],
          "truncated": true,
          "total_nodes": 1200,
          "total_edges": 2400,
          "visible_nodes": 700,
          "visible_edges": 1200,
          "node_limit": 700,
          "edge_limit": 1200
        }
        """.data(using: .utf8)!

        let graph = try JSONDecoder.codeMemoryDecoder.decode(CodeMemoryGraph.self, from: data)

        #expect(graph.truncated == true)
        #expect(graph.totalNodes == 1200)
        #expect(graph.edgeLimit == 1200)
    }

    @Test("Change graph builder creates event memory source nodes and change edges")
    func changeGraphBuilderCreatesChangeTopology() {
        let events = [
            Self.event(eventID: "event:1", seq: 1, eventType: "created", memoryID: "one", title: "One", sourceID: "src:1"),
            Self.event(eventID: "event:2", seq: 2, eventType: "updated", memoryID: "one", title: "One updated", sourceID: "src:2"),
        ]

        let graph = MemoryChangeGraphBuilder.build(projectID: "claude-stats", events: events)

        #expect(graph.nodes.contains { $0.id == "change:event:event:1" && $0.kind == "change_event" })
        #expect(graph.nodes.contains { $0.id == "memory:one" && $0.kind == "memory" })
        #expect(graph.nodes.contains { $0.kind == "source" })
        #expect(graph.edges.contains { $0.kind == "AFFECTS" })
        #expect(graph.edges.contains { $0.kind == "NEXT_EVENT" })
        #expect(graph.edges.contains { $0.kind == "FROM_SOURCE" })
    }

    @MainActor
    @Test("Memory history store loads without disturbing change event selection")
    func memoryHistoryStoreLoadsWithoutDisturbingSelection() async throws {
        let backend = FakeCodeMemoryBackend()
        backend.eventResponse = [
            Self.event(eventID: "event:1", seq: 1, eventType: "created", memoryID: "one", title: "One", sourceID: "src:1"),
        ]
        backend.historyResponses["one"] = CodeMemoryMemoryHistory(
            memoryID: "one",
            versions: [
                CodeMemoryMemoryVersion(
                    memoryID: "one",
                    version: 1,
                    eventID: "event:1",
                    eventType: "created",
                    projectID: "claude-stats",
                    timestamp: 1,
                    title: "One",
                    body: "Body",
                    type: "fact",
                    status: "active",
                    normalizedClaim: "one",
                    confidence: 1,
                    importance: 1,
                    sourceRefs: [],
                    metadata: nil,
                    validAt: nil,
                    invalidAt: nil,
                    reviewReason: nil,
                    extractedBy: "mem0",
                    createdAt: 1,
                    updatedAt: 1
                ),
            ],
            events: backend.eventResponse
        )
        let graphStore = MemoryGraphStore(backend: backend)

        await graphStore.loadChanges(projectID: "claude-stats")
        graphStore.selectChangeEvent("event:1")
        await graphStore.loadHistory(memoryID: "one")

        #expect(graphStore.selectedChangeEvent?.eventID == "event:1")
        #expect(graphStore.history(for: "one")?.versions.first?.version == 1)
        #expect(backend.historyMemoryIDs == ["one"])
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

    private static func event(
        eventID: String,
        seq: Int,
        eventType: String,
        memoryID: String,
        title: String,
        sourceID: String
    ) -> CodeMemoryEvent {
        CodeMemoryEvent(
            eventID: eventID,
            seq: seq,
            timestamp: Double(seq),
            projectID: "claude-stats",
            actor: ["kind": "human", "id": "tester"],
            eventType: eventType,
            memoryID: memoryID,
            before: seq == 1 ? nil : ["title": .string("One"), "status": .string("active")],
            after: ["title": .string(title), "body": .string("\(title) body"), "status": .string("active"), "type": .string("fact")],
            delta: nil,
            sourceRefs: [CodeMemorySourceRef(kind: "manual", sourceID: sourceID, quote: "\(title) quote")],
            hash: "h\(seq)",
            prevHash: seq == 1 ? nil : "h\(seq - 1)"
        )
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
    var eventResponse: [CodeMemoryEvent] = []
    var historyResponses: [String: CodeMemoryMemoryHistory] = [:]
    var historyMemoryIDs: [String] = []
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

    func events(projectID: String?, afterSeq: Int?, limit: Int) async throws -> [CodeMemoryEvent] {
        eventResponse
    }

    func memoryHistory(memoryID: String, limit: Int) async throws -> CodeMemoryMemoryHistory {
        historyMemoryIDs.append(memoryID)
        return historyResponses[memoryID] ?? CodeMemoryMemoryHistory(memoryID: memoryID, versions: [], events: [])
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

private struct MockCodeMemoryResponse: Sendable {
    var status: Int
    var headers: [String: String]
    var data: Data
}

private final class MockCodeMemoryURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> MockCodeMemoryResponse)?
    nonisolated(unsafe) static var capturedURLs: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let url = request.url {
            Self.capturedURLs.append(url)
        }
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let mock = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: mock.status,
                httpVersion: nil,
                headerFields: mock.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: mock.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
