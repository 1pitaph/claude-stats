import SwiftUI

/// The AI coding tools Claude Stats can read. Provider-specific path and
/// transcript quirks live under `Providers/<Provider>/`.
///
/// `allCases` order is the canonical display order (used by the platform
/// switcher bar and the settings list).
enum ProviderKind: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case claude
    case codex
    case gemini
    case opencode
    case kiro
    case hermes
    case zcode

    var id: String { rawValue }

    /// Full name for tooltips and settings rows.
    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "OpenAI Codex"
        case .gemini: "Gemini"
        case .opencode: "OpenCode"
        case .kiro: "Kiro"
        case .hermes: "Hermes"
        case .zcode: "ZCode"
        }
    }

    /// Short name for the panel header (`"<shortName> STATS"`).
    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .opencode: "OpenCode"
        case .kiro: "Kiro"
        case .hermes: "Hermes"
        case .zcode: "ZCode"
        }
    }

    /// Name of the colour-logo image set in `Assets.xcassets/Providers/` — used
    /// in Settings.
    var assetName: String {
        switch self {
        case .claude: "claudecode-logo"
        case .codex: "codex-logo"
        case .gemini: "gemini-logo"
        case .opencode: "opencode-logo"
        case .kiro: "kiro-logo"
        case .hermes: "hermes-logo"
        case .zcode: "zcode-logo"
        }
    }

    /// Name of the monochrome (template-rendered) logo image set — used in the
    /// panel's platform switcher so all logos read uniformly.
    var monochromeAssetName: String {
        switch self {
        case .claude: "claudecode"
        case .codex: "codex"
        case .gemini: "gemini"
        case .opencode: "opencode"
        case .kiro: "kiro"
        case .hermes: "hermes"
        case .zcode: "zcode"
        }
    }

    /// SF Symbol used as a fallback if the logo asset is unavailable.
    var iconSystemName: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .gemini: "sparkle"
        case .opencode: "terminal"
        case .kiro: "shippingbox"
        case .hermes: "bolt.horizontal"
        case .zcode: "z.square"
        }
    }

    var accentColor: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.45, blue: 0.20)
        case .codex: Color(red: 0.10, green: 0.10, blue: 0.12)
        case .gemini: Color(red: 0.19, green: 0.53, blue: 1.0)
        case .opencode: Color(red: 0.05, green: 0.62, blue: 0.46)
        case .kiro: Color(red: 0.48, green: 0.34, blue: 0.95)
        case .hermes: Color(red: 0.18, green: 0.45, blue: 0.98)
        case .zcode: Color(red: 0.36, green: 0.70, blue: 0.92)
        }
    }
}
