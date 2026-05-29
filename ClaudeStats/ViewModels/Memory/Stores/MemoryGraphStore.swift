import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class MemoryGraphStore {
    var searchText = ""
    var selectedNodeID: String?
    var selectedEdgeID: String?
    var selectedKinds: Set<String> = []
    var showCanonical = true
    var showEpisodes = true
    var showEvents = true
    var showGraphiti = true
    var asOf: Double?
    var zoom: Double = 1
    var pan = CGSize.zero
    private(set) var graph: CodeMemoryGraph?
    private(set) var isLoading = false
    private(set) var lastError: String?

    @ObservationIgnored private let backend: any CodeMemoryBackend

    init(backend: any CodeMemoryBackend) {
        self.backend = backend
    }

    var nodeKinds: [String] {
        guard let graph else { return [] }
        return Array(Set(graph.nodes.map(\.kind))).sorted()
    }

    var selectedNode: CodeMemoryGraphNode? {
        guard let selectedNodeID else { return nil }
        return graph?.nodes.first { $0.id == selectedNodeID }
    }

    var selectedEdge: CodeMemoryGraphEdge? {
        guard let selectedEdgeID else { return nil }
        return graph?.edges.first { $0.id == selectedEdgeID }
    }

    func load(projectID: String?) async {
        guard let projectID, !projectID.isEmpty else {
            graph = nil
            selectedNodeID = nil
            selectedEdgeID = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            graph = try await backend.graph(projectID: projectID)
            selectedKinds = Set(nodeKinds)
            selectedNodeID = selectedNodeID.flatMap { id in graph?.nodes.contains { $0.id == id } == true ? id : nil }
            selectedEdgeID = selectedEdgeID.flatMap { id in graph?.edges.contains { $0.id == id } == true ? id : nil }
            lastError = nil
        } catch {
            graph = nil
            selectedNodeID = nil
            selectedEdgeID = nil
            lastError = error.localizedDescription
        }
    }

    func selectNode(_ id: String?) {
        selectedNodeID = id
        selectedEdgeID = nil
    }

    func selectEdge(_ id: String?) {
        selectedEdgeID = id
        selectedNodeID = nil
    }

    func resetViewport() {
        zoom = 1
        pan = .zero
    }
}
