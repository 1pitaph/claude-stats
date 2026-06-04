import Foundation

public enum StatsSnapshotSchema {
    public static let currentVersion = 2
}

public enum StatsPeriodIdentifier: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case today
    case last7Days
    case last30Days
    case allTime

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .today: "Today"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        case .allTime: "All time"
        }
    }
}

public enum StatsBucketGranularity: String, Codable, Sendable, Hashable {
    case period
    case hour
    case day
}

public struct StatsTokenUsage: Codable, Hashable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheCreation5mTokens: Int
    public var cacheCreation1hTokens: Int

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheCreation5mTokens: Int = 0,
        cacheCreation1hTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreation5mTokens = cacheCreation5mTokens
        self.cacheCreation1hTokens = cacheCreation1hTokens
    }

    public static let zero = StatsTokenUsage()

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreation5mTokens + cacheCreation1hTokens
    }
}

public struct StatsUsageBucket: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var period: StatsPeriodIdentifier
    public var providerID: String?
    public var providerName: String?
    public var granularity: StatsBucketGranularity
    public var start: Date
    public var end: Date?
    public var sessionCount: Int
    public var messageCount: Int
    public var usage: StatsTokenUsage
    public var estimatedCost: Double

    public init(
        id: String,
        period: StatsPeriodIdentifier,
        providerID: String? = nil,
        providerName: String? = nil,
        granularity: StatsBucketGranularity,
        start: Date,
        end: Date? = nil,
        sessionCount: Int = 0,
        messageCount: Int = 0,
        usage: StatsTokenUsage = .zero,
        estimatedCost: Double = 0
    ) {
        self.id = id
        self.period = period
        self.providerID = providerID
        self.providerName = providerName
        self.granularity = granularity
        self.start = start
        self.end = end
        self.sessionCount = sessionCount
        self.messageCount = messageCount
        self.usage = usage
        self.estimatedCost = estimatedCost
    }
}

public struct StatsModelBreakdown: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var period: StatsPeriodIdentifier
    public var providerID: String?
    public var providerName: String?
    public var model: String
    public var messageCount: Int
    public var usage: StatsTokenUsage
    public var estimatedCost: Double

    public init(
        id: String,
        period: StatsPeriodIdentifier,
        providerID: String? = nil,
        providerName: String? = nil,
        model: String,
        messageCount: Int,
        usage: StatsTokenUsage,
        estimatedCost: Double
    ) {
        self.id = id
        self.period = period
        self.providerID = providerID
        self.providerName = providerName
        self.model = model
        self.messageCount = messageCount
        self.usage = usage
        self.estimatedCost = estimatedCost
    }
}

public struct StatsUsageLimitSnapshot: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var providerID: String
    public var providerName: String
    public var status: String
    public var capturedAt: Date?
    public var sourceLabel: String?
    public var message: String?
    public var windows: [StatsUsageLimitWindow]

    public init(
        id: String,
        providerID: String,
        providerName: String,
        status: String,
        capturedAt: Date? = nil,
        sourceLabel: String? = nil,
        message: String? = nil,
        windows: [StatsUsageLimitWindow] = []
    ) {
        self.id = id
        self.providerID = providerID
        self.providerName = providerName
        self.status = status
        self.capturedAt = capturedAt
        self.sourceLabel = sourceLabel
        self.message = message
        self.windows = windows
    }
}

public struct StatsUsageLimitWindow: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var usedPercent: Double
    public var resetAt: Date?
    public var windowMinutes: Int?

    public init(
        id: String,
        label: String,
        usedPercent: Double,
        resetAt: Date? = nil,
        windowMinutes: Int? = nil
    ) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.windowMinutes = windowMinutes
    }
}

public struct StatsDailyReport: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var day: Date
    public var sessionCount: Int
    public var messageCount: Int
    public var totalTokens: Int
    public var estimatedCost: Double
    public var projectCount: Int
    public var commitCount: Int

    public init(
        id: String,
        day: Date,
        sessionCount: Int,
        messageCount: Int,
        totalTokens: Int,
        estimatedCost: Double,
        projectCount: Int,
        commitCount: Int = 0
    ) {
        self.id = id
        self.day = day
        self.sessionCount = sessionCount
        self.messageCount = messageCount
        self.totalTokens = totalTokens
        self.estimatedCost = estimatedCost
        self.projectCount = projectCount
        self.commitCount = commitCount
    }
}

public struct StatsGanttTimeline: Codable, Hashable, Sendable {
    public var periodStart: Date?
    public var periodEnd: Date?
    public var segments: [StatsGanttSegment]

    public init(periodStart: Date? = nil, periodEnd: Date? = nil, segments: [StatsGanttSegment] = []) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.segments = segments
    }
}

public struct StatsGanttSegment: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var providerID: String
    public var start: Date
    public var end: Date
    public var tokenCount: Int

    public init(id: String, label: String, providerID: String, start: Date, end: Date, tokenCount: Int) {
        self.id = id
        self.label = label
        self.providerID = providerID
        self.start = start
        self.end = end
        self.tokenCount = tokenCount
    }
}

public struct StatsGitActivitySummary: Codable, Hashable, Sendable {
    public var totalRepositories: Int
    public var totalCommits: Int
    public var totalInsertions: Int
    public var totalDeletions: Int
    public var totalFilesChanged: Int
    public var rows: [StatsGitRepositoryRow]

    public init(
        totalRepositories: Int = 0,
        totalCommits: Int = 0,
        totalInsertions: Int = 0,
        totalDeletions: Int = 0,
        totalFilesChanged: Int = 0,
        rows: [StatsGitRepositoryRow] = []
    ) {
        self.totalRepositories = totalRepositories
        self.totalCommits = totalCommits
        self.totalInsertions = totalInsertions
        self.totalDeletions = totalDeletions
        self.totalFilesChanged = totalFilesChanged
        self.rows = rows
    }
}

public struct StatsGitRepositoryRow: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var commitCount: Int
    public var churn: Int

    public init(id: String, label: String, commitCount: Int, churn: Int) {
        self.id = id
        self.label = label
        self.commitCount = commitCount
        self.churn = churn
    }
}

public struct StatsLeaderboardSummary: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var statusText: String
    public var accountText: String
    public var realtimeStatusText: String?
    public var lastLoadedPeriodKey: String?
    public var localScores: [StatsLeaderboardLocalScore]
    public var visibleRows: [StatsLeaderboardRow]
    public var favoriteModels: [StatsLeaderboardFavoriteModel]
    public var errorMessage: String?
    public var emptyMessage: String?

    public init(
        isEnabled: Bool = false,
        statusText: String = "Disabled",
        accountText: String = "Not checked",
        realtimeStatusText: String? = nil,
        lastLoadedPeriodKey: String? = nil,
        localScores: [StatsLeaderboardLocalScore] = [],
        visibleRows: [StatsLeaderboardRow] = [],
        favoriteModels: [StatsLeaderboardFavoriteModel] = [],
        errorMessage: String? = nil,
        emptyMessage: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.statusText = statusText
        self.accountText = accountText
        self.realtimeStatusText = realtimeStatusText
        self.lastLoadedPeriodKey = lastLoadedPeriodKey
        self.localScores = localScores
        self.visibleRows = visibleRows
        self.favoriteModels = favoriteModels
        self.errorMessage = errorMessage
        self.emptyMessage = emptyMessage
    }
}

public struct StatsLeaderboardLocalScore: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var metricID: String
    public var metricName: String
    public var periodID: String
    public var periodName: String
    public var periodKey: String
    public var score: Int64
    public var updatedAt: Date

    public init(
        id: String,
        metricID: String,
        metricName: String,
        periodID: String,
        periodName: String,
        periodKey: String,
        score: Int64,
        updatedAt: Date
    ) {
        self.id = id
        self.metricID = metricID
        self.metricName = metricName
        self.periodID = periodID
        self.periodName = periodName
        self.periodKey = periodKey
        self.score = score
        self.updatedAt = updatedAt
    }
}

public struct StatsLeaderboardRow: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var rank: Int
    public var displayName: String
    public var metricID: String
    public var metricName: String
    public var periodID: String
    public var periodName: String
    public var periodKey: String
    public var score: Int64
    public var isCurrentUser: Bool
    public var updatedAt: Date

    public init(
        id: String,
        rank: Int,
        displayName: String,
        metricID: String,
        metricName: String,
        periodID: String,
        periodName: String,
        periodKey: String,
        score: Int64,
        isCurrentUser: Bool = false,
        updatedAt: Date
    ) {
        self.id = id
        self.rank = rank
        self.displayName = displayName
        self.metricID = metricID
        self.metricName = metricName
        self.periodID = periodID
        self.periodName = periodName
        self.periodKey = periodKey
        self.score = score
        self.isCurrentUser = isCurrentUser
        self.updatedAt = updatedAt
    }
}

public struct StatsLeaderboardFavoriteModel: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var rank: Int
    public var model: String
    public var tokens: Int64

    public init(id: String, rank: Int, model: String, tokens: Int64) {
        self.id = id
        self.rank = rank
        self.model = model
        self.tokens = tokens
    }
}

public struct StatsActivitySummary: Codable, Hashable, Sendable {
    public var sourceLabel: String
    public var hasFocusData: Bool
    public var totalAISeconds: TimeInterval
    public var totalCodingSurfaceSeconds: TimeInterval
    public var totalOverlapSeconds: TimeInterval
    public var totalCLIHostSeconds: TimeInterval
    public var totalCLIAIOverlapSeconds: TimeInterval
    public var activeDayCount: Int
    public var days: [StatsActivityDay]

    public init(
        sourceLabel: String = "No synced activity data",
        hasFocusData: Bool = false,
        totalAISeconds: TimeInterval = 0,
        totalCodingSurfaceSeconds: TimeInterval = 0,
        totalOverlapSeconds: TimeInterval = 0,
        totalCLIHostSeconds: TimeInterval = 0,
        totalCLIAIOverlapSeconds: TimeInterval = 0,
        activeDayCount: Int = 0,
        days: [StatsActivityDay] = []
    ) {
        self.sourceLabel = sourceLabel
        self.hasFocusData = hasFocusData
        self.totalAISeconds = totalAISeconds
        self.totalCodingSurfaceSeconds = totalCodingSurfaceSeconds
        self.totalOverlapSeconds = totalOverlapSeconds
        self.totalCLIHostSeconds = totalCLIHostSeconds
        self.totalCLIAIOverlapSeconds = totalCLIAIOverlapSeconds
        self.activeDayCount = activeDayCount
        self.days = days
    }
}

public struct StatsActivityDay: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var day: Date
    public var aiSeconds: TimeInterval
    public var codingSurfaceSeconds: TimeInterval
    public var overlapSeconds: TimeInterval
    public var cliHostSeconds: TimeInterval
    public var cliAIOverlapSeconds: TimeInterval
    public var sessionCount: Int
    public var messageCount: Int
    public var totalTokens: Int
    public var burstCount: Int

    public init(
        id: String,
        day: Date,
        aiSeconds: TimeInterval = 0,
        codingSurfaceSeconds: TimeInterval = 0,
        overlapSeconds: TimeInterval = 0,
        cliHostSeconds: TimeInterval = 0,
        cliAIOverlapSeconds: TimeInterval = 0,
        sessionCount: Int = 0,
        messageCount: Int = 0,
        totalTokens: Int = 0,
        burstCount: Int = 0
    ) {
        self.id = id
        self.day = day
        self.aiSeconds = aiSeconds
        self.codingSurfaceSeconds = codingSurfaceSeconds
        self.overlapSeconds = overlapSeconds
        self.cliHostSeconds = cliHostSeconds
        self.cliAIOverlapSeconds = cliAIOverlapSeconds
        self.sessionCount = sessionCount
        self.messageCount = messageCount
        self.totalTokens = totalTokens
        self.burstCount = burstCount
    }
}

public struct StatsDashboardSummary: Codable, Hashable, Sendable {
    public var totalTokens: Int
    public var totalCost: Double
    public var sessionCount: Int
    public var messageCount: Int
    public var activeProjectCount: Int
    public var latestActivityAt: Date?
    public var providerSummaries: [StatsProviderSummary]

    public init(
        totalTokens: Int = 0,
        totalCost: Double = 0,
        sessionCount: Int = 0,
        messageCount: Int = 0,
        activeProjectCount: Int = 0,
        latestActivityAt: Date? = nil,
        providerSummaries: [StatsProviderSummary] = []
    ) {
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.sessionCount = sessionCount
        self.messageCount = messageCount
        self.activeProjectCount = activeProjectCount
        self.latestActivityAt = latestActivityAt
        self.providerSummaries = providerSummaries
    }
}

public struct StatsProviderSummary: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var sessionCount: Int
    public var totalTokens: Int
    public var estimatedCost: Double

    public init(id: String, name: String, sessionCount: Int, totalTokens: Int, estimatedCost: Double) {
        self.id = id
        self.name = name
        self.sessionCount = sessionCount
        self.totalTokens = totalTokens
        self.estimatedCost = estimatedCost
    }
}

public struct StatsSnapshot: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "latest" }
    public var schemaVersion: Int
    public var generatedAt: Date
    public var appVersion: String
    public var usageBuckets: [StatsUsageBucket]
    public var modelBreakdowns: [StatsModelBreakdown]
    public var usageLimitSnapshots: [StatsUsageLimitSnapshot]
    public var dailyReports: [StatsDailyReport]
    public var ganttTimeline: StatsGanttTimeline
    public var gitActivitySummary: StatsGitActivitySummary
    public var leaderboardSummary: StatsLeaderboardSummary
    public var activitySummary: StatsActivitySummary
    public var dashboardSummary: StatsDashboardSummary

    public init(
        schemaVersion: Int = StatsSnapshotSchema.currentVersion,
        generatedAt: Date,
        appVersion: String,
        usageBuckets: [StatsUsageBucket] = [],
        modelBreakdowns: [StatsModelBreakdown] = [],
        usageLimitSnapshots: [StatsUsageLimitSnapshot] = [],
        dailyReports: [StatsDailyReport] = [],
        ganttTimeline: StatsGanttTimeline = StatsGanttTimeline(),
        gitActivitySummary: StatsGitActivitySummary = StatsGitActivitySummary(),
        leaderboardSummary: StatsLeaderboardSummary = StatsLeaderboardSummary(),
        activitySummary: StatsActivitySummary = StatsActivitySummary(),
        dashboardSummary: StatsDashboardSummary = StatsDashboardSummary()
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.usageBuckets = usageBuckets
        self.modelBreakdowns = modelBreakdowns
        self.usageLimitSnapshots = usageLimitSnapshots
        self.dailyReports = dailyReports
        self.ganttTimeline = ganttTimeline
        self.gitActivitySummary = gitActivitySummary
        self.leaderboardSummary = leaderboardSummary
        self.activitySummary = activitySummary
        self.dashboardSummary = dashboardSummary
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case appVersion
        case usageBuckets
        case modelBreakdowns
        case usageLimitSnapshots
        case dailyReports
        case ganttTimeline
        case gitActivitySummary
        case leaderboardSummary
        case activitySummary
        case dashboardSummary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? StatsSnapshotSchema.currentVersion
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date(timeIntervalSince1970: 0)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "Unknown"
        usageBuckets = try container.decodeIfPresent([StatsUsageBucket].self, forKey: .usageBuckets) ?? []
        modelBreakdowns = try container.decodeIfPresent([StatsModelBreakdown].self, forKey: .modelBreakdowns) ?? []
        usageLimitSnapshots = try container.decodeIfPresent([StatsUsageLimitSnapshot].self, forKey: .usageLimitSnapshots) ?? []
        dailyReports = try container.decodeIfPresent([StatsDailyReport].self, forKey: .dailyReports) ?? []
        ganttTimeline = try container.decodeIfPresent(StatsGanttTimeline.self, forKey: .ganttTimeline) ?? StatsGanttTimeline()
        gitActivitySummary = try container.decodeIfPresent(StatsGitActivitySummary.self, forKey: .gitActivitySummary) ?? StatsGitActivitySummary()
        leaderboardSummary = try container.decodeIfPresent(StatsLeaderboardSummary.self, forKey: .leaderboardSummary) ?? StatsLeaderboardSummary()
        activitySummary = try container.decodeIfPresent(StatsActivitySummary.self, forKey: .activitySummary) ?? StatsActivitySummary()
        dashboardSummary = try container.decodeIfPresent(StatsDashboardSummary.self, forKey: .dashboardSummary) ?? StatsDashboardSummary()
    }

    public static func empty(appVersion: String = "Unknown", generatedAt: Date = .now) -> StatsSnapshot {
        StatsSnapshot(generatedAt: generatedAt, appVersion: appVersion)
    }
}
