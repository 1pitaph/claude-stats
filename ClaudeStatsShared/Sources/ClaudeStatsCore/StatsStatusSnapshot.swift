import Foundation
import Observation

public enum StatsStatusProviderID: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case openAI = "openai"
    case claude

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .claude: "Claude"
        }
    }

    public var statusTitle: String {
        "\(displayName) Status"
    }
}

public enum StatsStatusSeverity: Codable, Equatable, Hashable, Sendable, Comparable {
    case operational
    case degradedPerformance
    case partialOutage
    case majorOutage
    case fullOutage
    case underMaintenance
    case unknown(String)

    public init(rawStatus: String) {
        switch rawStatus {
        case "operational":
            self = .operational
        case "degraded_performance":
            self = .degradedPerformance
        case "partial_outage":
            self = .partialOutage
        case "major_outage":
            self = .majorOutage
        case "full_outage":
            self = .fullOutage
        case "under_maintenance":
            self = .underMaintenance
        default:
            self = .unknown(rawStatus)
        }
    }

    public var rawStatus: String {
        switch self {
        case .operational: "operational"
        case .degradedPerformance: "degraded_performance"
        case .partialOutage: "partial_outage"
        case .majorOutage: "major_outage"
        case .fullOutage: "full_outage"
        case .underMaintenance: "under_maintenance"
        case .unknown(let raw): raw
        }
    }

    public var displayName: String {
        switch self {
        case .operational: "Operational"
        case .degradedPerformance: "Degraded Performance"
        case .partialOutage: "Partial Outage"
        case .majorOutage: "Major Outage"
        case .fullOutage: "Full Outage"
        case .underMaintenance: "Under Maintenance"
        case .unknown: "Unknown"
        }
    }

    public var isOperational: Bool {
        self == .operational
    }

    private var rank: Int {
        switch self {
        case .operational: 0
        case .underMaintenance: 1
        case .degradedPerformance: 2
        case .partialOutage: 3
        case .majorOutage: 4
        case .fullOutage: 5
        case .unknown: 6
        }
    }

    public static func < (lhs: StatsStatusSeverity, rhs: StatsStatusSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.init(rawStatus: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawStatus)
    }
}

public struct StatsStatusRollup: Codable, Hashable, Sendable {
    public var severity: StatsStatusSeverity
    public var description: String

    public init(severity: StatsStatusSeverity = .unknown("unknown"), description: String = "Unknown") {
        self.severity = severity
        self.description = description
    }
}

public struct StatsStatusItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var status: StatsStatusSeverity
    public var updatedAt: Date?
    public var position: Int

    public init(
        id: String,
        name: String,
        status: StatsStatusSeverity,
        updatedAt: Date? = nil,
        position: Int = 0
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.updatedAt = updatedAt
        self.position = position
    }
}

public struct StatsStatusIncident: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var status: String
    public var impact: StatsStatusSeverity
    public var shortlink: URL?
    public var startedAt: Date?
    public var updatedAt: Date?

    public init(
        id: String,
        name: String,
        status: String,
        impact: StatsStatusSeverity,
        shortlink: URL? = nil,
        startedAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.impact = impact
        self.shortlink = shortlink
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

public struct StatsStatusUptimeEvent: Codable, Hashable, Sendable {
    public var name: String
    public var code: String
    public var permalink: URL?

    public init(name: String, code: String, permalink: URL? = nil) {
        self.name = name
        self.code = code
        self.permalink = permalink
    }
}

public struct StatsStatusUptimeDay: Codable, Identifiable, Hashable, Sendable {
    public var date: Date
    public var degradedPerformanceSeconds: Int
    public var partialOutageSeconds: Int
    public var majorOutageSeconds: Int
    public var fullOutageSeconds: Int
    public var relatedEvents: [StatsStatusUptimeEvent]
    public var barFillHex: String?

    public var id: Date { date }

    public init(
        date: Date,
        degradedPerformanceSeconds: Int = 0,
        partialOutageSeconds: Int = 0,
        majorOutageSeconds: Int = 0,
        fullOutageSeconds: Int = 0,
        relatedEvents: [StatsStatusUptimeEvent] = [],
        barFillHex: String? = nil
    ) {
        self.date = date
        self.degradedPerformanceSeconds = max(0, degradedPerformanceSeconds)
        self.partialOutageSeconds = max(0, partialOutageSeconds)
        self.majorOutageSeconds = max(0, majorOutageSeconds)
        self.fullOutageSeconds = max(0, fullOutageSeconds)
        self.relatedEvents = relatedEvents
        self.barFillHex = barFillHex
    }

    public var outageSeconds: Int {
        degradedPerformanceSeconds + partialOutageSeconds + majorOutageSeconds + fullOutageSeconds
    }

    public var hasOutage: Bool {
        outageSeconds > 0
    }
}

public enum StatsStatusUptimeWindow {
    public static let dayCount = 90
    public static let secondsPerDay = 24 * 60 * 60
}

public struct StatsStatusUptimeHistory: Codable, Identifiable, Hashable, Sendable {
    public var itemID: String
    public var itemName: String
    public var startDate: Date?
    public var days: [StatsStatusUptimeDay]
    public var sourceUptimePercent: Double?

    public var id: String { itemID }

    public init(
        itemID: String,
        itemName: String,
        startDate: Date? = nil,
        days: [StatsStatusUptimeDay] = [],
        sourceUptimePercent: Double? = nil
    ) {
        self.itemID = itemID
        self.itemName = itemName
        self.startDate = startDate
        self.days = days
        self.sourceUptimePercent = sourceUptimePercent
    }

    public func recentDays(count: Int = StatsStatusUptimeWindow.dayCount) -> [StatsStatusUptimeDay] {
        guard days.count > count else { return days }
        return Array(days.suffix(count))
    }

    public func uptimePercent(recentDayCount: Int = StatsStatusUptimeWindow.dayCount) -> Double? {
        if let sourceUptimePercent {
            return sourceUptimePercent
        }

        let window = recentDays(count: recentDayCount)
        let validDays = window.filter { day in
            guard let startDate else { return true }
            return day.date >= startDate
        }
        guard !validDays.isEmpty else { return nil }

        let totalSeconds = validDays.count * StatsStatusUptimeWindow.secondsPerDay
        let downtimeSeconds = validDays.reduce(0) { total, day in
            total + min(StatsStatusUptimeWindow.secondsPerDay, day.outageSeconds)
        }
        guard totalSeconds > 0 else { return nil }

        let uptimeRatio = 1 - (Double(downtimeSeconds) / Double(totalSeconds))
        return max(0, min(1, uptimeRatio)) * 100
    }
}

public struct StatsStatusProviderSnapshot: Codable, Identifiable, Hashable, Sendable {
    public var providerID: StatsStatusProviderID
    public var providerName: String
    public var statusPageURL: URL?
    public var pageName: String
    public var pageUpdatedAt: Date?
    public var rollup: StatsStatusRollup
    public var items: [StatsStatusItem]
    public var defaultVisibleItemIDs: Set<String>
    public var uptimeHistories: [StatsStatusUptimeHistory]
    public var incidents: [StatsStatusIncident]
    public var fetchedAt: Date
    public var isSummaryStale: Bool
    public var summaryError: String?
    public var isUptimeStale: Bool
    public var uptimeError: String?

    public var id: String { providerID.rawValue }

    public init(
        providerID: StatsStatusProviderID,
        providerName: String,
        statusPageURL: URL? = nil,
        pageName: String = "",
        pageUpdatedAt: Date? = nil,
        rollup: StatsStatusRollup = StatsStatusRollup(),
        items: [StatsStatusItem] = [],
        defaultVisibleItemIDs: Set<String> = [],
        uptimeHistories: [StatsStatusUptimeHistory] = [],
        incidents: [StatsStatusIncident] = [],
        fetchedAt: Date = Date(timeIntervalSince1970: 0),
        isSummaryStale: Bool = false,
        summaryError: String? = nil,
        isUptimeStale: Bool = false,
        uptimeError: String? = nil
    ) {
        self.providerID = providerID
        self.providerName = providerName
        self.statusPageURL = statusPageURL
        self.pageName = pageName
        self.pageUpdatedAt = pageUpdatedAt
        self.rollup = rollup
        self.items = items.sorted { lhs, rhs in
            if lhs.position == rhs.position { return lhs.name < rhs.name }
            return lhs.position < rhs.position
        }
        self.defaultVisibleItemIDs = defaultVisibleItemIDs
        self.uptimeHistories = uptimeHistories
        self.incidents = incidents
        self.fetchedAt = fetchedAt
        self.isSummaryStale = isSummaryStale
        self.summaryError = summaryError
        self.isUptimeStale = isUptimeStale
        self.uptimeError = uptimeError
    }

    public var updatedAt: Date {
        pageUpdatedAt ?? fetchedAt
    }

    public func uptimeHistory(for item: StatsStatusItem) -> StatsStatusUptimeHistory? {
        uptimeHistories.first { $0.itemID == item.id }
            ?? uptimeHistories.first { $0.itemName == item.name }
    }
}

public struct StatsStatusSummary: Codable, Hashable, Sendable {
    public var providers: [StatsStatusProviderSnapshot]

    public init(providers: [StatsStatusProviderSnapshot] = []) {
        self.providers = providers
    }

    public static let empty = StatsStatusSummary()

    public func provider(_ providerID: StatsStatusProviderID) -> StatsStatusProviderSnapshot? {
        providers.first { $0.providerID == providerID }
    }
}

@MainActor
@Observable
public final class StatsStatusDisplayPreferencesStore {
    public var selectedProviderID: StatsStatusProviderID {
        didSet {
            defaults.set(selectedProviderID.rawValue, forKey: Self.selectedProviderKey)
        }
    }

    public private(set) var visibleOpenAIItemIDs: Set<String> {
        didSet { save(visibleOpenAIItemIDs, forKey: Self.visibleOpenAIItemIDsKey) }
    }

    public private(set) var visibleClaudeItemIDs: Set<String> {
        didSet { save(visibleClaudeItemIDs, forKey: Self.visibleClaudeItemIDsKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedProvider = defaults.string(forKey: Self.selectedProviderKey) ?? ""
        self.selectedProviderID = StatsStatusProviderID(rawValue: storedProvider) ?? .openAI
        self.visibleOpenAIItemIDs = Self.loadSet(defaults: defaults, key: Self.visibleOpenAIItemIDsKey)
        self.visibleClaudeItemIDs = Self.loadSet(defaults: defaults, key: Self.visibleClaudeItemIDsKey)
    }

    public func visibleItemIDs(for provider: StatsStatusProviderSnapshot) -> Set<String> {
        effectiveVisibleItemIDs(
            storedIDs: storedVisibleItemIDs(for: provider.providerID),
            provider: provider
        )
    }

    public func visibleItems(for provider: StatsStatusProviderSnapshot) -> [StatsStatusItem] {
        let visibleIDs = visibleItemIDs(for: provider)
        return provider.items.filter { visibleIDs.contains($0.id) }
    }

    public func isItemVisible(_ item: StatsStatusItem, in provider: StatsStatusProviderSnapshot) -> Bool {
        visibleItemIDs(for: provider).contains(item.id)
    }

    public func canHideItem(_ item: StatsStatusItem, in provider: StatsStatusProviderSnapshot) -> Bool {
        let visibleIDs = visibleItemIDs(for: provider)
        return !(visibleIDs.count == 1 && visibleIDs.contains(item.id))
    }

    public func setItemVisibility(_ item: StatsStatusItem, in provider: StatsStatusProviderSnapshot, isVisible: Bool) {
        var ids = visibleItemIDs(for: provider)
        if isVisible {
            ids.insert(item.id)
        } else {
            guard !(ids.count == 1 && ids.contains(item.id)) else { return }
            ids.remove(item.id)
        }
        setStoredVisibleItemIDs(ids, for: provider.providerID)
    }

    private func effectiveVisibleItemIDs(
        storedIDs: Set<String>,
        provider: StatsStatusProviderSnapshot
    ) -> Set<String> {
        let availableIDs = Set(provider.items.map(\.id))
        guard !availableIDs.isEmpty else { return [] }

        var visible = storedIDs.intersection(availableIDs)
        if visible.isEmpty {
            visible = provider.defaultVisibleItemIDs.intersection(availableIDs)
        }
        if visible.isEmpty, let first = provider.items.first {
            visible.insert(first.id)
        }
        return visible
    }

    private func storedVisibleItemIDs(for providerID: StatsStatusProviderID) -> Set<String> {
        switch providerID {
        case .openAI: visibleOpenAIItemIDs
        case .claude: visibleClaudeItemIDs
        }
    }

    private func setStoredVisibleItemIDs(_ ids: Set<String>, for providerID: StatsStatusProviderID) {
        switch providerID {
        case .openAI:
            visibleOpenAIItemIDs = ids
        case .claude:
            visibleClaudeItemIDs = ids
        }
    }

    private func save(_ ids: Set<String>, forKey key: String) {
        defaults.set(ids.sorted(), forKey: key)
    }

    private static func loadSet(defaults: UserDefaults, key: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    private static let selectedProviderKey = "iOS.status.selectedProvider"
    private static let visibleOpenAIItemIDsKey = "iOS.status.visibleOpenAIItemIDs"
    private static let visibleClaudeItemIDsKey = "iOS.status.visibleClaudeItemIDs"
}
