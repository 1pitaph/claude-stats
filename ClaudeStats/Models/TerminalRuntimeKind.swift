import Foundation

enum TerminalRuntimeKind: String, CaseIterable, Identifiable, Sendable {
    case warp
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .warp: "Warp"
        case .disabled: "Disabled"
        }
    }

    var description: String {
        switch self {
        case .warp: "Use the experimental embedded Warp ADE bridge."
        case .disabled: "Hide the embedded terminal runtime."
        }
    }

    var symbol: String {
        switch self {
        case .warp: "terminal"
        case .disabled: "nosign"
        }
    }
}
