import Foundation
import Testing
@testable import ClaudeStats

@Suite("Memory knowledge graph readiness")
struct MemoryKnowledgeGraphReadinessTests {
    @Test("Disabled Graphiti with unrunnable settings is not configured")
    func disabledGraphitiWithUnrunnableSettingsIsNotConfigured() {
        let readiness = MemoryKnowledgeGraphReadiness.evaluate(
            projectID: "claude-stats",
            health: Self.health(graphiti: "disabled: memory model adapters are disabled"),
            graph: Self.emptyGraph(),
            presentation: Self.emptyPresentation(),
            hasRunnableAdapters: false,
            settingsReadiness: "Online extraction is off",
            lastError: nil,
            lastReindexResult: nil,
            lastDrainResult: nil
        )

        #expect(readiness.state == .notConfigured)
        #expect(readiness.actions == [.openSettings])
        #expect(!readiness.actions.contains(.reindexDrain))
        #expect(readiness.message.contains("Online extraction is off"))
    }

    @Test("Disabled Graphiti with runnable settings needs restart")
    func disabledGraphitiWithRunnableSettingsNeedsRestart() {
        let readiness = MemoryKnowledgeGraphReadiness.evaluate(
            projectID: "claude-stats",
            health: Self.health(graphiti: "disabled: memory model adapters are disabled"),
            graph: Self.emptyGraph(),
            presentation: Self.emptyPresentation(),
            hasRunnableAdapters: true,
            settingsReadiness: "Ready",
            lastError: nil,
            lastReindexResult: nil,
            lastDrainResult: nil
        )

        #expect(readiness.state == .needsRestart)
        #expect(readiness.actions == [.applyRestart, .openSettings])
    }

    @Test("Queued or failed projection jobs require projection actions")
    func queuedOrFailedProjectionJobsRequireProjectionActions() {
        let readiness = MemoryKnowledgeGraphReadiness.evaluate(
            projectID: "claude-stats",
            health: Self.health(graphiti: "enabled: fake", pending: 2, failed: 1),
            graph: Self.emptyGraph(),
            presentation: Self.emptyPresentation(),
            hasRunnableAdapters: true,
            settingsReadiness: "Ready",
            lastError: nil,
            lastReindexResult: nil,
            lastDrainResult: nil
        )

        #expect(readiness.state == .needsProjection)
        #expect(readiness.actions == [.reindexDrain, .retryFailed, .refresh])
    }

    @Test("Projection blockers are surfaced before empty graph guidance")
    func projectionBlockersAreSurfaced() {
        let result = CodeMemoryProjectionDrainResponse(
            delivered: 0,
            failed: 0,
            remaining: 3,
            pending: 3,
            failedTotal: 0,
            skipped: true,
            message: "Graphiti projection skipped because graphiti is unavailable.",
            blockers: ["graphiti": "endpoint unavailable"]
        )

        let readiness = MemoryKnowledgeGraphReadiness.evaluate(
            projectID: "claude-stats",
            health: Self.health(graphiti: "enabled: fake"),
            graph: Self.emptyGraph(),
            presentation: Self.emptyPresentation(),
            hasRunnableAdapters: true,
            settingsReadiness: "Ready",
            lastError: nil,
            lastReindexResult: result,
            lastDrainResult: nil
        )

        #expect(readiness.state == .blocked)
        #expect(readiness.message.contains("endpoint unavailable"))
        #expect(readiness.actions.contains(.reindexDrain))
    }

    @Test("Graphiti entity and fact presentation is ready")
    func graphitiEntityAndFactPresentationIsReady() {
        let graph = Self.readyGraph()
        let presentation = MemoryKnowledgeGraphPresentation.build(graph: graph, factVisibility: .active, searchText: "")

        let readiness = MemoryKnowledgeGraphReadiness.evaluate(
            projectID: "claude-stats",
            health: Self.health(graphiti: "enabled: fake"),
            graph: graph,
            presentation: presentation,
            hasRunnableAdapters: true,
            settingsReadiness: "Ready",
            lastError: nil,
            lastReindexResult: nil,
            lastDrainResult: nil
        )

        #expect(readiness.state == .ready)
        #expect(readiness.actions.isEmpty)
    }

    private static func health(graphiti: String, pending: Int = 0, failed: Int = 0) -> CodeMemoryHealth {
        CodeMemoryHealth(
            status: "ok",
            store: "/tmp/code-memory.sqlite3",
            eventCount: 0,
            memoryCount: 0,
            projectionPending: pending,
            projectionFailed: failed,
            adapters: ["graphiti": graphiti]
        )
    }

    private static func emptyGraph() -> CodeMemoryGraph {
        CodeMemoryGraph(projectID: "claude-stats", nodes: [], edges: [])
    }

    private static func emptyPresentation() -> MemoryKnowledgeGraphPresentation {
        MemoryKnowledgeGraphPresentation.build(graph: emptyGraph(), factVisibility: .active, searchText: "")
    }

    private static func readyGraph() -> CodeMemoryGraph {
        CodeMemoryGraph(
            projectID: "claude-stats",
            nodes: [
                CodeMemoryGraphNode(id: "graphiti:entity:a", kind: "graphiti_entity", title: "A", type: nil, status: nil, seq: nil, body: "A summary", sourceRefs: nil, metadata: ["adapter": "graphiti"]),
                CodeMemoryGraphNode(id: "graphiti:entity:b", kind: "graphiti_entity", title: "B", type: nil, status: nil, seq: nil, body: "B summary", sourceRefs: nil, metadata: ["adapter": "graphiti"]),
            ],
            edges: [
                CodeMemoryGraphEdge(
                    source: "graphiti:entity:a",
                    target: "graphiti:entity:b",
                    kind: "RELATES_TO",
                    primary: nil,
                    fact: "A relates to B.",
                    validAt: nil,
                    invalidAt: nil,
                    metadata: ["adapter": "graphiti"]
                ),
            ]
        )
    }
}
