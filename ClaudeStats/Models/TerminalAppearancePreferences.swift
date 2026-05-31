import Foundation

enum TerminalChromeMode: String, CaseIterable, Identifiable, Sendable {
    case tabsAndStatus
    case tabsOnly
    case statusOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tabsAndStatus: "Tabs + Status"
        case .tabsOnly: "Tabs only"
        case .statusOnly: "Status only"
        }
    }

    var description: String {
        switch self {
        case .tabsAndStatus: "Browser-style tabs at the top with a compact status bar below."
        case .tabsOnly: "Keep the terminal focused on the top tab strip."
        case .statusOnly: "Hide the tab strip and use the status bar controls."
        }
    }

    var symbol: String {
        switch self {
        case .tabsAndStatus: AppIcon.Terminal.topChrome
        case .tabsOnly: AppIcon.Terminal.topChrome
        case .statusOnly: AppIcon.Terminal.bottomChrome
        }
    }

    var showsTopTabs: Bool {
        self == .tabsAndStatus || self == .tabsOnly
    }

    var showsStatusBar: Bool {
        self == .tabsAndStatus || self == .statusOnly
    }
}

enum TerminalBackgroundStyle: String, CaseIterable, Identifiable, Sendable {
    case fluidGradient
    case solid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fluidGradient: "Fluid gradient"
        case .solid: "Solid"
        }
    }

    var description: String {
        switch self {
        case .fluidGradient: "A quiet animated gradient behind the terminal window."
        case .solid: "A minimal flat backdrop for maximum contrast."
        }
    }

    var symbol: String {
        switch self {
        case .fluidGradient: AppIcon.Terminal.fluidGradient
        case .solid: AppIcon.Terminal.solidBackground
        }
    }
}
