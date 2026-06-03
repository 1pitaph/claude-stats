import Foundation

struct UsageLimitHistoryEntry: Codable, Sendable, Hashable, Identifiable {
    let provider: ProviderKind
    let windowID: String
    let label: String
    let usedPercent: Double
    let resetAt: Date?
    let windowMinutes: Int?
    let capturedAt: Date
    let sourceLabel: String
    let sourcePath: String?
    let planType: String?
    let limitID: String?

    var id: String {
        [
            provider.rawValue,
            windowID,
            Self.timeID(capturedAt),
            resetAt.map(Self.timeID) ?? "none",
            String(Int((usedPercent * 100).rounded())),
        ]
        .joined(separator: "|")
    }

    var windowKey: String { "\(provider.rawValue)|\(windowID)" }

    init(
        provider: ProviderKind,
        window: UsageLimitWindow,
        capturedAt: Date,
        sourceLabel: String,
        sourcePath: String?,
        planType: String?,
        limitID: String?
    ) {
        self.provider = provider
        self.windowID = window.id
        self.label = window.label
        self.usedPercent = window.clampedUsedPercent
        self.resetAt = window.resetAt
        self.windowMinutes = window.windowMinutes
        self.capturedAt = capturedAt
        self.sourceLabel = sourceLabel
        self.sourcePath = sourcePath
        self.planType = planType
        self.limitID = limitID
    }

    func matches(_ provider: ProviderKind, windowID: String) -> Bool {
        self.provider == provider && self.windowID == windowID
    }

    private static func timeID(_ date: Date) -> String {
        String(Int((date.timeIntervalSinceReferenceDate * 1_000).rounded()))
    }
}

struct UsageLimitHistoryStore: Sendable {
    static let defaultRetention: TimeInterval = 14 * 86_400

    let url: URL
    let retention: TimeInterval

    init(
        url: URL = UsageLimitCachePaths.historyURL(),
        retention: TimeInterval = Self.defaultRetention
    ) {
        self.url = url
        self.retention = retention
    }

    func load() -> [UsageLimitHistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([UsageLimitHistoryEntry].self, from: data)) ?? []
    }

    @discardableResult
    func append(report: UsageLimitReport, now: Date = .now) throws -> [UsageLimitHistoryEntry] {
        guard report.status == .fresh, let snapshot = report.snapshot else {
            return load()
        }
        return try append(entries: Self.entries(from: snapshot), now: now)
    }

    @discardableResult
    func append(entries newEntries: [UsageLimitHistoryEntry], now: Date = .now) throws -> [UsageLimitHistoryEntry] {
        guard !newEntries.isEmpty else {
            let retained = retainedEntries(load(), now: now)
            try save(retained)
            return retained
        }

        let merged = retainedEntries(load() + newEntries, now: now)
        try save(merged)
        return merged
    }

    static func entries(from snapshot: UsageLimitSnapshot) -> [UsageLimitHistoryEntry] {
        snapshot.windows
            .filter { $0.forecastHorizon(for: snapshot.provider) != nil }
            .map {
                UsageLimitHistoryEntry(
                    provider: snapshot.provider,
                    window: $0,
                    capturedAt: snapshot.capturedAt,
                    sourceLabel: snapshot.sourceLabel,
                    sourcePath: snapshot.sourcePath,
                    planType: snapshot.planType,
                    limitID: snapshot.limitID
                )
            }
    }

    private func retainedEntries(_ entries: [UsageLimitHistoryEntry], now: Date) -> [UsageLimitHistoryEntry] {
        let cutoff = now.addingTimeInterval(-retention)
        var byID: [String: UsageLimitHistoryEntry] = [:]
        for entry in entries where entry.capturedAt >= cutoff {
            byID[entry.id] = entry
        }
        return byID.values.sorted {
            if $0.capturedAt != $1.capturedAt { return $0.capturedAt < $1.capturedAt }
            if $0.provider != $1.provider { return $0.provider.rawValue < $1.provider.rawValue }
            return $0.windowID < $1.windowID
        }
    }

    private func save(_ entries: [UsageLimitHistoryEntry]) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: url, options: [.atomic])
    }
}
