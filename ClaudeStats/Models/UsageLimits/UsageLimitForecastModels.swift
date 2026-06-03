import Foundation

enum UsageLimitForecastStatus: String, Codable, Sendable, Hashable {
    case collecting
    case forecast
    case willNotReachBeforeReset
    case limitReached
    case unavailable
}

enum UsageLimitForecastConfidence: String, Codable, Sendable, Hashable {
    case low
    case medium
    case high
}

enum UsageLimitForecastHorizon: String, Codable, Sendable, Hashable {
    case fiveHour
    case sevenDay

    var displayText: String {
        switch self {
        case .fiveHour:
            "5h"
        case .sevenDay:
            "7d"
        }
    }
}

struct UsageLimitForecast: Codable, Sendable, Hashable, Identifiable {
    let provider: ProviderKind
    let windowID: String
    let label: String
    let horizon: UsageLimitForecastHorizon
    let capturedAt: Date
    let currentUsedPercent: Double
    let resetAt: Date?
    let reachInterval: DateInterval?
    let medianReachAt: Date?
    let confidence: UsageLimitForecastConfidence
    let status: UsageLimitForecastStatus
    let diagnostics: [String]

    var id: String { "\(provider.rawValue)|\(windowID)" }

    init(
        provider: ProviderKind,
        windowID: String,
        label: String,
        horizon: UsageLimitForecastHorizon = .sevenDay,
        capturedAt: Date,
        currentUsedPercent: Double,
        resetAt: Date?,
        reachInterval: DateInterval?,
        medianReachAt: Date?,
        confidence: UsageLimitForecastConfidence,
        status: UsageLimitForecastStatus,
        diagnostics: [String]
    ) {
        self.provider = provider
        self.windowID = windowID
        self.label = label
        self.horizon = horizon
        self.capturedAt = capturedAt
        self.currentUsedPercent = currentUsedPercent
        self.resetAt = resetAt
        self.reachInterval = reachInterval
        self.medianReachAt = medianReachAt
        self.confidence = confidence
        self.status = status
        self.diagnostics = diagnostics
    }

    func matches(provider: ProviderKind, window: UsageLimitWindow) -> Bool {
        self.provider == provider && windowID == window.id
    }
}

extension Array where Element == UsageLimitForecast {
    func forecast(for provider: ProviderKind, windowID: String) -> UsageLimitForecast? {
        first { $0.provider == provider && $0.windowID == windowID }
    }
}
