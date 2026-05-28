import Foundation

enum ConfigWorkspaceSection: String, CaseIterable, Identifiable, Sendable, Hashable {
    case overview
    case files
    case providers
    case profiles
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .files: "Files"
        case .providers: "Providers"
        case .profiles: "Profiles & Backups"
        case .diagnostics: "Diagnostics"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .files: "folder"
        case .providers: "slider.horizontal.3"
        case .profiles: "archivebox"
        case .diagnostics: "exclamationmark.triangle"
        }
    }

    var detailTitle: String {
        switch self {
        case .overview: "Config"
        case .files: "Files"
        case .providers: "Providers"
        case .profiles: "Profiles & Backups"
        case .diagnostics: "Diagnostics"
        }
    }

    var detailDescription: String {
        switch self {
        case .overview:
            "Review provider state, discovered config files, profiles, backups, and diagnostics."
        case .files:
            "Inspect instructions, provider files, plans, plugin manifests, and skill files."
        case .providers:
            "Edit API providers and check the local CLI environment."
        case .profiles:
            "Capture, apply, restore, and compare configuration profile backups."
        case .diagnostics:
            "Triage issues reported by files, providers, profiles, backups, skills, and the local CLI environment."
        }
    }

    init(storedRawValue: String) {
        self = ConfigWorkspaceSection(rawValue: storedRawValue) ?? .overview
    }
}

enum ConfigFilesSection: String, CaseIterable, Identifiable, Sendable, Hashable {
    case instructions
    case providerFiles
    case plans
    case pluginManifests
    case skillFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instructions: "Instructions"
        case .providerFiles: "Provider Files"
        case .plans: "Plans"
        case .pluginManifests: "Plugin Manifests"
        case .skillFiles: "Skill Files"
        }
    }

    var symbol: String {
        if self == .skillFiles { return "sparkles" }
        return aiConfigSection.symbol
    }

    var detailTitle: String {
        switch self {
        case .instructions: "Instructions"
        case .providerFiles: "Provider Files"
        case .plans: "Plans"
        case .pluginManifests: "Plugin Manifests"
        case .skillFiles: "Skill Files"
        }
    }

    var detailDescription: String {
        switch self {
        case .instructions:
            "Inspect global and project instruction files such as CLAUDE.md and AGENTS.md."
        case .providerFiles:
            "Inspect provider settings and local configuration files without editing them."
        case .plans:
            "Review discovered markdown plans and their best-effort project assignment."
        case .pluginManifests:
            "Inspect plugin manifest and configuration files discovered for AI tools."
        case .skillFiles:
            "Inspect installed SKILL.md files and related skill assets as configuration inputs."
        }
    }

    var aiConfigSection: AIConfigsSection {
        switch self {
        case .instructions: .instructions
        case .providerFiles: .provider
        case .plans: .plans
        case .pluginManifests: .plugins
        case .skillFiles: .plugins
        }
    }

    init(storedRawValue: String) {
        switch storedRawValue {
        case "instructions":
            self = .instructions
        case "provider", "providerFiles":
            self = .providerFiles
        case "plans":
            self = .plans
        case "plugins", "pluginManifests":
            self = .pluginManifests
        case "skills", "skillFiles":
            self = .skillFiles
        default:
            self = .instructions
        }
    }
}

enum ConfigDiagnosticSeverity: String, CaseIterable, Identifiable, Sendable, Hashable {
    case info
    case warning
    case error

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Error"
        }
    }

    var symbol: String {
        switch self {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    init(aiSeverity: AIConfigDiagnostic.Severity) {
        switch aiSeverity {
        case .info: self = .info
        case .warning: self = .warning
        case .error: self = .error
        }
    }
}

enum ConfigDiagnosticSource: String, CaseIterable, Identifiable, Sendable, Hashable {
    case files
    case providers
    case profiles
    case backups
    case skills
    case environment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: "Files"
        case .providers: "Providers"
        case .profiles: "Profiles"
        case .backups: "Backups"
        case .skills: "Skills"
        case .environment: "CLI Environment"
        }
    }
}

struct ConfigDiagnosticItem: Identifiable, Sendable, Hashable {
    let id: String
    let severity: ConfigDiagnosticSeverity
    let source: ConfigDiagnosticSource
    let title: String
    let message: String
    let detail: String?
    let targetSection: ConfigWorkspaceSection
    let targetFilesSection: ConfigFilesSection?
}

struct ConfigWorkspaceCounts: Sendable, Hashable {
    var providerCount: Int
    var configFileCount: Int
    var skillCount: Int
    var profileCount: Int
    var backupCount: Int
    var diagnosticCount: Int

    static let empty = ConfigWorkspaceCounts(
        providerCount: 0,
        configFileCount: 0,
        skillCount: 0,
        profileCount: 0,
        backupCount: 0,
        diagnosticCount: 0
    )
}

struct ConfigRelatedSkill: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let providerName: String
    let scopeName: String
    let pluginName: String?
    let path: String

    init(skill: LocalSkillItem) {
        id = skill.id
        name = skill.name
        providerName = skill.providerName
        scopeName = skill.scope.displayName
        pluginName = skill.plugin?.displayName
        path = skill.displayPath
    }
}
