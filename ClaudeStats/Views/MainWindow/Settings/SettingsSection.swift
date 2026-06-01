import Foundation

/// Categories shown in the main window's "settings mode" sidebar. Each owns
/// the corresponding `*SettingsView` rendered in the detail panel.
enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case features
    case menuBar
    case notchIsland
    case platforms
    case tracking
    case dictionary
    case llm
    case localAI
    case leaderboards
    case github
    case linuxDo
    case systemMonitor
    case terminal
    case about

    static var availableCases: [SettingsSection] {
        allCases.filter { section in
            switch section {
            case .localAI:
                AppVariant.isEnabled(.localAI)
            default:
                true
            }
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:   L10n.string("settings.section.general", defaultValue: "General")
        case .features:  L10n.string("settings.section.features", defaultValue: "Features")
        case .menuBar:   L10n.string("settings.section.menu_bar", defaultValue: "Menu Bar")
        case .notchIsland: L10n.string("settings.section.notch_island", defaultValue: "Notch Island")
        case .platforms: L10n.string("settings.section.platforms", defaultValue: "Platforms")
        case .tracking:  L10n.string("settings.section.tracking", defaultValue: "Tracking")
        case .dictionary: "Dictionary"
        case .llm: "LLM"
        case .localAI: "Local AI"
        case .leaderboards: L10n.string("settings.section.leaderboards", defaultValue: "Leaderboards")
        case .github:    "GitHub"
        case .linuxDo:   "LinuxDo"
        case .systemMonitor: L10n.string("settings.section.system_monitor", defaultValue: "System Monitor")
        case .terminal:  L10n.string("settings.section.terminal", defaultValue: "Terminal")
        case .about:     L10n.string("settings.section.about", defaultValue: "About")
        }
    }

    var symbol: String {
        switch self {
        case .general:   AppIcon.Settings.general
        case .features:  AppIcon.Settings.features
        case .menuBar:   AppIcon.Settings.menuBar
        case .notchIsland: AppIcon.Settings.notchIsland
        case .platforms: AppIcon.Settings.platforms
        case .tracking:  AppIcon.Settings.tracking
        case .dictionary: AppIcon.Resource.dictionary
        case .llm: AppIcon.Settings.llm
        case .localAI: AppIcon.Workspace.memory
        case .leaderboards: AppIcon.Workspace.leaderboards
        case .github:    AppIcon.Git.code
        case .linuxDo:   AppIcon.Workspace.linuxDo
        case .systemMonitor: AppIcon.Workspace.system
        case .terminal:  AppIcon.Workspace.terminal
        case .about:     AppIcon.Settings.about
        }
    }

    var assetName: String? {
        switch self {
        case .linuxDo: "LinuxDoLogo"
        default: nil
        }
    }
}
