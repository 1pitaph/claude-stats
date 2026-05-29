import Foundation

enum SessionsDestination: Hashable, Sendable {
    case overview
    case analysis
    case session(String)

    static let overviewRawValue = "overview"
    static let analysisRawValue = "analysis"
    private static let sessionPrefix = "session:"

    init(rawValue: String) {
        if rawValue == Self.analysisRawValue {
            self = .analysis
        } else if rawValue.hasPrefix(Self.sessionPrefix) {
            let id = String(rawValue.dropFirst(Self.sessionPrefix.count))
            self = id.isEmpty ? .overview : .session(id)
        } else {
            self = .overview
        }
    }

    var rawValue: String {
        switch self {
        case .overview:
            Self.overviewRawValue
        case .analysis:
            Self.analysisRawValue
        case .session(let id):
            Self.sessionPrefix + id
        }
    }
}
