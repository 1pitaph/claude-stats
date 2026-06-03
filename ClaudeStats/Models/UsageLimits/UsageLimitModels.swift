import Foundation

enum UsageLimitStatus: String, Codable, Sendable, Hashable {
    case fresh
    case cached
    case setupRequired
    case waitingForNextResponse
    case unavailable
    case unsupported
}

struct UsageLimitReport: Codable, Sendable, Hashable {
    let provider: ProviderKind
    let status: UsageLimitStatus
    let snapshot: UsageLimitSnapshot?
    let message: String?

    var lastCapturedAt: Date? { snapshot?.capturedAt }

    static func fresh(provider: ProviderKind, snapshot: UsageLimitSnapshot) -> UsageLimitReport {
        UsageLimitReport(provider: provider, status: .fresh, snapshot: snapshot, message: nil)
    }

    static func cached(provider: ProviderKind, snapshot: UsageLimitSnapshot) -> UsageLimitReport {
        UsageLimitReport(provider: provider, status: .cached, snapshot: snapshot, message: nil)
    }

    static func setupRequired(provider: ProviderKind, message: String) -> UsageLimitReport {
        UsageLimitReport(provider: provider, status: .setupRequired, snapshot: nil, message: message)
    }

    static func waitingForNextResponse(provider: ProviderKind, snapshot: UsageLimitSnapshot?, message: String) -> UsageLimitReport {
        UsageLimitReport(provider: provider, status: .waitingForNextResponse, snapshot: snapshot, message: message)
    }

    static func unavailable(provider: ProviderKind, message: String) -> UsageLimitReport {
        UsageLimitReport(provider: provider, status: .unavailable, snapshot: nil, message: message)
    }

    static func unsupported(provider: ProviderKind) -> UsageLimitReport {
        UsageLimitReport(provider: provider, status: .unsupported, snapshot: nil, message: nil)
    }
}

struct UsageLimitSnapshot: Codable, Sendable, Hashable {
    let provider: ProviderKind
    let windows: [UsageLimitWindow]
    let capturedAt: Date
    let sourceLabel: String
    let sourcePath: String?
    let planType: String?
    let limitID: String?

    var isEmpty: Bool { windows.isEmpty }

    func isFresh(now: Date, ttl: TimeInterval) -> Bool {
        guard now.timeIntervalSince(capturedAt) <= ttl else { return false }
        return windows.allSatisfy { window in
            guard let resetAt = window.resetAt else { return true }
            return resetAt > now
        }
    }
}

struct UsageLimitWindow: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetAt: Date?
    let windowMinutes: Int?

    var clampedUsedPercent: Double {
        min(100, max(0, usedPercent))
    }

    var remainingPercent: Double {
        100 - clampedUsedPercent
    }

    func forecastHorizon(for provider: ProviderKind) -> UsageLimitForecastHorizon? {
        switch provider {
        case .codex:
            switch (id, windowMinutes) {
            case ("primary", UsageLimitWindowCatalog.fiveHourWindowMinutes):
                .fiveHour
            case ("secondary", UsageLimitWindowCatalog.sevenDayWindowMinutes):
                .sevenDay
            default:
                nil
            }
        case .claude:
            switch (id, windowMinutes) {
            case ("five_hour", UsageLimitWindowCatalog.fiveHourWindowMinutes):
                .fiveHour
            case ("seven_day", UsageLimitWindowCatalog.sevenDayWindowMinutes):
                .sevenDay
            default:
                nil
            }
        case .gemini, .kimi, .minimax:
            nil
        }
    }

    func isCoreSevenDayLimit(for provider: ProviderKind) -> Bool {
        forecastHorizon(for: provider) == .sevenDay
    }
}

struct UsageLimitWindowMetadata: Sendable, Hashable {
    let id: String
    let label: String
    let minutes: Int
}

enum UsageLimitWindowCatalog {
    static let fiveHourWindowMinutes = 300
    static let sevenDayWindowMinutes = 10_080

    static let claudeCoreWindowIDs: Set<String> = ["five_hour", "seven_day"]
    static let claudeDefaultVisibleWindowIDs: Set<String> = claudeCoreWindowIDs
    static let claudeOptionalWindowIDs: [String] = ["weekly_claude_design", "sonnet_only"]

    static let claudeWindowDefinitions: [UsageLimitWindowMetadata] = [
        UsageLimitWindowMetadata(id: "five_hour", label: "5h", minutes: fiveHourWindowMinutes),
        UsageLimitWindowMetadata(id: "seven_day", label: "7d", minutes: sevenDayWindowMinutes),
        UsageLimitWindowMetadata(id: "weekly_claude_design", label: "Claude Design", minutes: sevenDayWindowMinutes),
        UsageLimitWindowMetadata(id: "sonnet_only", label: "Sonnet", minutes: sevenDayWindowMinutes),
    ]

    private static let claudeOrderByID = Dictionary(
        uniqueKeysWithValues: claudeWindowDefinitions.enumerated().map { ($0.element.id, $0.offset) }
    )
    private static let claudeKnownWindowIDs = Set(claudeWindowDefinitions.map(\.id))

    static func isClaudeCoreComplete(_ windows: [UsageLimitWindow]) -> Bool {
        claudeCoreWindowIDs.isSubset(of: Set(windows.map(\.id)))
    }

    static func orderedClaudeWindows(_ windows: [UsageLimitWindow]) -> [UsageLimitWindow] {
        windows.sorted { lhs, rhs in
            let lhsOrder = claudeOrderByID[lhs.id] ?? Int.max
            let rhsOrder = claudeOrderByID[rhs.id] ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    static func visibleClaudeWindows(
        _ windows: [UsageLimitWindow],
        visibleWindowIDs: Set<String>
    ) -> [UsageLimitWindow] {
        let normalizedVisibleIDs = normalizedClaudeVisibleWindowIDs(visibleWindowIDs)
        return orderedClaudeWindows(windows).filter { normalizedVisibleIDs.contains($0.id) }
    }

    static func normalizedClaudeVisibleWindowIDs(_ ids: Set<String>) -> Set<String> {
        let knownIDs = ids.intersection(claudeKnownWindowIDs)
        return knownIDs.union(claudeCoreWindowIDs)
    }

    static func claudeMetadata(for id: String) -> UsageLimitWindowMetadata? {
        claudeWindowDefinitions.first { $0.id == id }
    }
}

extension ProviderKind {
    var supportsUsageLimits: Bool {
        switch self {
        case .claude, .codex:
            true
        case .gemini, .kimi, .minimax:
            false
        }
    }
}
