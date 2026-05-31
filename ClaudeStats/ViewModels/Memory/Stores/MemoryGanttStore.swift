import Foundation
import Observation

struct MemoryGanttItem: Identifiable, Equatable, Sendable {
    let memory: CodeMemoryMemory
    let start: Double
    let end: Double
    let isOpenEnded: Bool

    var id: String { memory.id }
    var duration: Double { max(0, end - start) }
    var status: String { memory.status }
    var title: String { memory.title }
    var type: String { memory.type }
}

struct MemoryGanttDomain: Equatable, Sendable {
    let start: Double
    let end: Double

    init?(items: [MemoryGanttItem]) {
        guard let first = items.first else { return nil }
        var minStart = first.start
        var maxEnd = first.end

        for item in items.dropFirst() {
            minStart = min(minStart, item.start)
            maxEnd = max(maxEnd, item.end)
        }

        if maxEnd <= minStart {
            start = minStart
            end = minStart + 86_400
        } else {
            let padding = max((maxEnd - minStart) * 0.04, 3_600)
            start = minStart - padding
            end = maxEnd + padding
        }
    }
}

@MainActor
@Observable
final class MemoryGanttStore {
    static let statuses = [
        "active",
        "proposed",
        "superseded",
        "deprecated",
        "conflicted",
        "retracted",
    ]

    private(set) var memories: [CodeMemoryMemory] = []
    private(set) var items: [MemoryGanttItem] = []
    private(set) var loadedProjectID: String?
    private(set) var loadedAt: Double?
    private(set) var isLoading = false
    private(set) var lastError: String?

    @ObservationIgnored private let backend: any CodeMemoryBackend
    @ObservationIgnored private let nowProvider: @MainActor @Sendable () -> Double

    init(
        backend: any CodeMemoryBackend,
        nowProvider: @escaping @MainActor @Sendable () -> Double = { Date().timeIntervalSince1970 }
    ) {
        self.backend = backend
        self.nowProvider = nowProvider
    }

    var openEndedCount: Int {
        items.filter(\.isOpenEnded).count
    }

    var domain: MemoryGanttDomain? {
        MemoryGanttDomain(items: items)
    }

    func refresh(projectID: String?) async {
        await load(projectID: projectID)
    }

    func load(projectID: String?) async {
        guard let projectID, !projectID.isEmpty else {
            clear()
            return
        }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        let now = nowProvider()

        do {
            var fetched: [CodeMemoryMemory] = []
            for status in Self.statuses {
                let memories = try await backend.memories(
                    filter: CodeMemoryQueryFilter(
                        projectID: projectID,
                        moduleID: nil,
                        statuses: [status],
                        includeGraphFacts: false,
                        limit: 1_000
                    )
                )
                fetched.append(contentsOf: memories)
            }

            let deduped = MemoryCanonicalDeduper.deduplicate(fetched)
            memories = deduped
            items = Self.sortedItems(for: deduped, now: now)
            loadedProjectID = projectID
            loadedAt = now
            lastError = nil
        } catch {
            memories = []
            items = []
            loadedProjectID = projectID
            loadedAt = now
            lastError = error.localizedDescription
        }
    }

    private func clear() {
        memories = []
        items = []
        loadedProjectID = nil
        loadedAt = nil
        lastError = nil
    }

    nonisolated private static func sortedItems(
        for memories: [CodeMemoryMemory],
        now: Double
    ) -> [MemoryGanttItem] {
        memories
            .map { memory in
                let start = memory.validAt ?? memory.createdAt
                let rawEnd = memory.invalidAt ?? now
                return MemoryGanttItem(
                    memory: memory,
                    start: start,
                    end: max(rawEnd, start),
                    isOpenEnded: memory.invalidAt == nil
                )
            }
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                if lhs.end != rhs.end { return lhs.end < rhs.end }
                if lhs.status != rhs.status { return lhs.status < rhs.status }
                if lhs.title != rhs.title { return lhs.title < rhs.title }
                return lhs.id < rhs.id
            }
    }
}
