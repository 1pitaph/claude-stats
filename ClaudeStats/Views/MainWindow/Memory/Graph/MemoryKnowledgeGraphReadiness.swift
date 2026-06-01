import Foundation

struct MemoryKnowledgeGraphReadiness: Sendable, Hashable {
    enum State: String, Sendable, Hashable {
        case error
        case ready
        case notConfigured
        case needsRestart
        case blocked
        case needsProjection
        case empty
    }

    enum Action: String, CaseIterable, Identifiable, Sendable, Hashable {
        case refresh
        case openSettings
        case applyRestart
        case reindexDrain
        case retryFailed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .refresh: "Refresh"
            case .openSettings: "Open Memory Settings"
            case .applyRestart: "Apply & Restart Memory Engine"
            case .reindexDrain: "Reindex & Drain Graphiti"
            case .retryFailed: "Retry Failed"
            }
        }
    }

    var state: State
    var title: String
    var message: String
    var actions: [Action]
    var diagnostics: [MemoryKnowledgeGraphReadinessDiagnostic]

    static func evaluate(
        projectID: String?,
        health: CodeMemoryHealth?,
        graph: CodeMemoryGraph?,
        presentation: MemoryKnowledgeGraphPresentation?,
        hasRunnableAdapters: Bool,
        settingsReadiness: String,
        lastError: String?,
        lastReindexResult: CodeMemoryProjectionDrainResponse?,
        lastDrainResult: CodeMemoryProjectionDrainResponse?
    ) -> MemoryKnowledgeGraphReadiness {
        let graphitiStatus = health?.adapters["graphiti"]
        let normalizedStatus = (graphitiStatus ?? "").lowercased()
        let pending = health?.projectionPending ?? 0
        let failed = health?.projectionFailed ?? 0
        let blocker = blockerSummary(lastReindexResult) ?? blockerSummary(lastDrainResult)
        let latestMessage = lastReindexResult?.message ?? lastDrainResult?.message
        let diagnostics = diagnostics(
            projectID: projectID,
            graphitiStatus: graphitiStatus,
            settingsReadiness: settingsReadiness,
            graph: graph,
            presentation: presentation,
            pending: pending,
            failed: failed,
            blocker: blocker,
            message: latestMessage
        )

        if let lastError, !lastError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return MemoryKnowledgeGraphReadiness(
                state: .error,
                title: "Graphiti knowledge graph could not load",
                message: lastError,
                actions: [.refresh],
                diagnostics: diagnostics
            )
        }

        if let presentation,
           !presentation.isKnowledgeEmpty,
           !presentation.nodes.isEmpty,
           !presentation.edges.isEmpty {
            return MemoryKnowledgeGraphReadiness(
                state: .ready,
                title: "Graphiti knowledge graph is ready",
                message: presentation.summary,
                actions: [],
                diagnostics: diagnostics
            )
        }

        if normalizedStatus.contains("disabled") {
            if hasRunnableAdapters {
                return MemoryKnowledgeGraphReadiness(
                    state: .needsRestart,
                    title: "Graphiti is configured but the memory engine needs restart",
                    message: "Current Memory LLM settings can run adapters, but the running sidecar still reports Graphiti disabled. Apply the current settings and restart the memory engine.",
                    actions: [.applyRestart, .openSettings],
                    diagnostics: diagnostics
                )
            }
            return MemoryKnowledgeGraphReadiness(
                state: .notConfigured,
                title: "Graphiti knowledge graph is not configured",
                message: "Graphiti adapters are disabled because Memory model extraction is not ready: \(settingsReadiness). Open Memory Settings to enable extraction and configure the missing model pieces.",
                actions: [.openSettings],
                diagnostics: diagnostics
            )
        }

        if let blocker {
            return MemoryKnowledgeGraphReadiness(
                state: .blocked,
                title: "Graphiti projection is blocked",
                message: "Graphiti cannot project memory facts yet: \(blocker)",
                actions: failed > 0 ? [.retryFailed, .openSettings, .refresh] : [.reindexDrain, .openSettings, .refresh],
                diagnostics: diagnostics
            )
        }

        if normalizedStatus.isEmpty, health != nil {
            return MemoryKnowledgeGraphReadiness(
                state: .blocked,
                title: "Graphiti adapter is not reporting health",
                message: "The memory engine is running, but no Graphiti adapter status was reported. Open Memory Settings to verify the model runtime configuration.",
                actions: [.openSettings, .refresh],
                diagnostics: diagnostics
            )
        }

        if normalizedStatus.hasPrefix("unavailable")
            || normalizedStatus.hasPrefix("error")
            || normalizedStatus.contains("endpoint unavailable")
            || normalizedStatus.contains("not configured") {
            return MemoryKnowledgeGraphReadiness(
                state: .blocked,
                title: "Graphiti projection is unavailable",
                message: "Graphiti reported \(graphitiStatus ?? "an unavailable adapter"). Fix the model endpoint or adapter configuration, then retry failed projection jobs.",
                actions: failed > 0 ? [.retryFailed, .openSettings, .refresh] : [.openSettings, .refresh],
                diagnostics: diagnostics
            )
        }

        if pending > 0 || failed > 0 {
            var actions: [Action] = [.reindexDrain]
            if failed > 0 {
                actions.append(.retryFailed)
            }
            actions.append(.refresh)
            return MemoryKnowledgeGraphReadiness(
                state: .needsProjection,
                title: "Graphiti facts are queued for projection",
                message: "Graphiti has \(pending) pending and \(failed) failed projection job(s). Reindex and drain to generate entity and fact relationships for this project.",
                actions: actions,
                diagnostics: diagnostics
            )
        }

        return MemoryKnowledgeGraphReadiness(
            state: .empty,
            title: "Graphiti knowledge graph is empty",
            message: "Graphiti is available, but no entity or fact relationships have been projected for this project yet. Reindex and drain canonical memories to build the knowledge graph.",
            actions: [.reindexDrain, .refresh],
            diagnostics: diagnostics
        )
    }

    private static func blockerSummary(_ result: CodeMemoryProjectionDrainResponse?) -> String? {
        guard let result else { return nil }
        if let blockers = result.blockers, !blockers.isEmpty {
            return blockers
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
        }
        if result.skipped == true,
           let message = result.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }
        return nil
    }

    private static func diagnostics(
        projectID: String?,
        graphitiStatus: String?,
        settingsReadiness: String,
        graph: CodeMemoryGraph?,
        presentation: MemoryKnowledgeGraphPresentation?,
        pending: Int,
        failed: Int,
        blocker: String?,
        message: String?
    ) -> [MemoryKnowledgeGraphReadinessDiagnostic] {
        var diagnostics: [MemoryKnowledgeGraphReadinessDiagnostic] = []
        if let projectID, !projectID.isEmpty {
            diagnostics.append(.init(label: "project", value: projectID.memoryAbbreviatingHomeDirectory))
        }
        if let graphitiStatus, !graphitiStatus.isEmpty {
            diagnostics.append(.init(label: "graphiti", value: graphitiStatus))
        }
        diagnostics.append(.init(label: "settings", value: settingsReadiness))
        diagnostics.append(.init(label: "queue", value: "\(pending) pending, \(failed) failed"))
        if let graph {
            diagnostics.append(.init(label: "raw graph", value: "\(graph.nodes.count) nodes, \(graph.edges.count) edges returned"))
        }
        if let presentation {
            diagnostics.append(.init(label: "knowledge", value: "\(presentation.totalEntityCount) Graphiti entities, \(presentation.totalFactCount) fact edges"))
        }
        if let blocker, !blocker.isEmpty {
            diagnostics.append(.init(label: "blocker", value: blocker))
        } else if let message, !message.isEmpty {
            diagnostics.append(.init(label: "last action", value: message))
        }
        return diagnostics
    }
}

struct MemoryKnowledgeGraphReadinessDiagnostic: Identifiable, Sendable, Hashable {
    let label: String
    let value: String

    var id: String { "\(label):\(value)" }
}
