import Foundation

enum AppFeature: CaseIterable, Sendable, Hashable {
    case sessions
    case memory
    case localAI
    case linuxDo
    case warp
    case config
    case ops
    case network
    case notchIsland
    case dictionary
    case git
    case dailyReport
    case leaderboards
}

enum AppVariant {
    #if CLAUDE_STATS_LITE
    static let isLite = true
    static let productName = "Claude Stats Lite"
    #else
    static let isLite = false
    static let productName = "Claude Stats"
    #endif

    static func isEnabled(_ feature: AppFeature) -> Bool {
        #if CLAUDE_STATS_LITE
        switch feature {
        case .sessions, .memory, .localAI, .linuxDo, .warp, .config, .ops, .network, .notchIsland, .dictionary:
            return false
        case .git, .dailyReport:
            return true
        case .leaderboards:
            return true
        }
        #else
        return true
        #endif
    }
}
