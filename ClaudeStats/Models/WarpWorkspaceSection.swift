import Foundation

enum WarpWorkspaceSection: String, CaseIterable, Identifiable, Sendable, Hashable {
    case sessions
    case agents
    case files
    case settings

    var id: String { rawValue }

    init(storedRawValue: String) {
        self = WarpWorkspaceSection(rawValue: storedRawValue) ?? .sessions
    }

    var title: String {
        switch self {
        case .sessions: "Sessions"
        case .agents: "Agents"
        case .files: "Files"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .sessions: AppIcon.Workspace.warp
        case .agents: AppIcon.Feature.ai
        case .files: AppIcon.Resource.folder
        case .settings: AppIcon.Workspace.settings
        }
    }

    var detailTitle: String {
        switch self {
        case .sessions: "Warp sessions"
        case .agents: "Agent panel"
        case .files: "Project files"
        case .settings: "Warp settings"
        }
    }

    var detailDescription: String {
        switch self {
        case .sessions:
            "Run the embedded Warp runtime inside the Claude Stats window."
        case .agents:
            "Prepare Warp ADE agent surfaces while the bridge is still being built."
        case .files:
            "Reserve space for Warp file tree, diffs, and code review workflows."
        case .settings:
            "Inspect runtime readiness and future Warp-specific controls."
        }
    }
}
