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

struct UsageLimitForecast: Codable, Sendable, Hashable, Identifiable {
    let provider: ProviderKind
    let windowID: String
    let label: String
    let capturedAt: Date
    let currentUsedPercent: Double
    let resetAt: Date?
    let reachInterval: DateInterval?
    let medianReachAt: Date?
    let confidence: UsageLimitForecastConfidence
    let status: UsageLimitForecastStatus
    let diagnostics: [String]

    var id: String { "\(provider.rawValue)|\(windowID)" }

    func matches(provider: ProviderKind, window: UsageLimitWindow) -> Bool {
        self.provider == provider && windowID == window.id
    }
}

extension Array where Element == UsageLimitForecast {
    func forecast(for provider: ProviderKind, windowID: String) -> UsageLimitForecast? {
        first { $0.provider == provider && $0.windowID == windowID }
    }
}
