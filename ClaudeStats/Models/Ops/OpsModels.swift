import Foundation

enum OpsSection: String, CaseIterable, Identifiable, Sendable, Hashable {
    case ports
    case processes
    case brew
    case environment
    case cleanup
    case diagnostics

    var id: String { rawValue }

    init(storedRawValue: String) {
        self = OpsSection(rawValue: storedRawValue) ?? .ports
    }

    var title: String {
        switch self {
        case .ports: "Ports"
        case .processes: "Processes"
        case .brew: "Brew"
        case .environment: "Environment"
        case .cleanup: "Cleanup"
        case .diagnostics: "Diagnostics"
        }
    }

    var symbol: String {
        switch self {
        case .ports: AppIcon.Ops.ports
        case .processes: AppIcon.Ops.processes
        case .brew: AppIcon.Ops.brew
        case .environment: AppIcon.Ops.environment
        case .cleanup: AppIcon.Ops.cleanup
        case .diagnostics: AppIcon.Ops.diagnostics
        }
    }

    var detailTitle: String {
        switch self {
        case .ports: "Listening ports"
        case .processes: "Process monitor"
        case .brew: "Homebrew"
        case .environment: "Environment"
        case .cleanup: "Cleanup"
        case .diagnostics: "Diagnostics"
        }
    }

    var detailDescription: String {
        switch self {
        case .ports:
            "Find occupied local ports, inspect owning processes, and close them safely."
        case .processes:
            "Monitor development processes, resource usage, launch commands, and ownership."
        case .brew:
            "Review installed packages, outdated formulae, services, and doctor output."
        case .environment:
            "Check common developer tools, resolved paths, and installed versions."
        case .cleanup:
            "Scan development caches, estimate reclaimable space, and remove selected safe targets."
        case .diagnostics:
            "Inspect proxy, hosts, DNS, response headers, and TLS certificate expiry."
        }
    }
}

enum OpsProtection: Sendable, Hashable {
    case allowed
    case protected(reason: String)

    var reason: String? {
        if case .protected(let reason) = self { return reason }
        return nil
    }
}

struct OpsPortItem: Identifiable, Sendable, Hashable {
    var id: String
    var pid: Int32
    var processIdentity = OpsProcessIdentity(pid: 0, ppid: 0, user: "", executablePath: "", commandFingerprint: "", startTime: nil)
    var processName: String
    var user: String
    var protocolName: String
    var localAddress: String
    var port: Int
    var commandLine: String
    var executablePath: String?
    var protection: OpsProtection

    var localhostURL: String {
        "http://localhost:\(port)"
    }

    var displayAddress: String {
        localAddress.isEmpty ? "*:\(port)" : "\(localAddress):\(port)"
    }
}

struct OpsProcessItem: Identifiable, Sendable, Hashable {
    var id: Int32 { pid }

    var pid: Int32
    var ppid: Int32
    var user: String
    var cpuPercent: Double
    var memoryPercent: Double
    var elapsed: String
    var startTime: String? = nil
    var executablePath: String
    var commandLine: String
    var protection: OpsProtection

    var identity: OpsProcessIdentity {
        OpsProcessIdentity(
            pid: pid,
            ppid: ppid,
            user: user,
            executablePath: executablePath,
            commandFingerprint: OpsProcessIdentity.fingerprint(commandLine),
            startTime: startTime
        )
    }

    var displayName: String {
        let name = URL(fileURLWithPath: executablePath).lastPathComponent
        if !name.isEmpty { return name }
        return commandLine.split(separator: " ").first.map(String.init) ?? "Process \(pid)"
    }

    var isDeveloperProcess: Bool {
        let text = "\(displayName) \(commandLine)".lowercased()
        let markers = [
            "node", "vite", "next", "bun", "deno", "python", "ruby",
            "swift", "xcodebuild", "docker", "pnpm", "npm", "yarn",
            "cargo", "go", "gradle", "java", "uvicorn", "rails",
        ]
        return markers.contains { text.contains($0) }
    }
}

struct OpsProcessIdentity: Sendable, Hashable {
    var pid: Int32
    var ppid: Int32
    var user: String
    var executablePath: String
    var commandFingerprint: String
    var startTime: String?

    static func fingerprint(_ commandLine: String) -> String {
        String(commandLine.prefix(500))
    }
}

enum OpsProcessSort: String, CaseIterable, Identifiable, Sendable, Hashable {
    case developer
    case cpu
    case memory
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .developer: "Dev"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .name: "Name"
        }
    }
}

enum OpsBrewPackageKind: String, Sendable, Hashable {
    case formula
    case cask
}

struct OpsBrewPackage: Identifiable, Sendable, Hashable {
    var id: String { "\(kind.rawValue):\(name)" }
    var name: String
    var installedVersion: String
    var latestVersion: String?
    var kind: OpsBrewPackageKind

    var isOutdated: Bool {
        guard let latestVersion, !latestVersion.isEmpty else { return false }
        return latestVersion != installedVersion
    }
}

struct OpsBrewServiceItem: Identifiable, Sendable, Hashable {
    var id: String { name }
    var name: String
    var status: String
    var user: String
    var file: String?
}

struct OpsBrewSnapshot: Sendable, Hashable {
    var brewPath: String?
    var packages: [OpsBrewPackage]
    var services: [OpsBrewServiceItem]
    var doctorOutput: String
    var lastCommandOutput: String?
    var errors: [String] = []

    static let missing = OpsBrewSnapshot(
        brewPath: nil,
        packages: [],
        services: [],
        doctorOutput: "Homebrew was not found in /opt/homebrew/bin, /usr/local/bin, or PATH.",
        lastCommandOutput: nil,
        errors: ["Homebrew was not found in a trusted location."]
    )
}

enum OpsEnvironmentStatus: Sendable, Hashable {
    case available
    case missing
    case error(String)

    var title: String {
        switch self {
        case .available: "Available"
        case .missing: "Missing"
        case .error: "Error"
        }
    }
}

struct OpsEnvironmentTool: Identifiable, Sendable, Hashable {
    var id: String { command }
    var name: String
    var command: String
    var resolvedPath: String?
    var version: String?
    var status: OpsEnvironmentStatus
    var detail: String?
    var isTrustedPath: Bool
}

enum OpsCleanupKind: String, CaseIterable, Identifiable, Sendable, Hashable {
    case xcodeDerivedData
    case swiftPackageCache
    case npmCache
    case pnpmStore
    case yarnCache
    case homebrewCache
    case dockerSystem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xcodeDerivedData: "Xcode DerivedData"
        case .swiftPackageCache: "SwiftPM cache"
        case .npmCache: "npm cache"
        case .pnpmStore: "pnpm store"
        case .yarnCache: "Yarn cache"
        case .homebrewCache: "Homebrew cache"
        case .dockerSystem: "Docker system"
        }
    }

    var symbol: String {
        switch self {
        case .xcodeDerivedData: AppIcon.Ops.xcode
        case .swiftPackageCache: AppIcon.Ops.swiftPackage
        case .npmCache: AppIcon.Ops.npm
        case .pnpmStore: AppIcon.Ops.pnpm
        case .yarnCache: AppIcon.Ops.yarn
        case .homebrewCache: AppIcon.Ops.homebrew
        case .dockerSystem: AppIcon.Ops.docker
        }
    }
}

struct OpsCleanupItem: Identifiable, Sendable, Hashable {
    var id: OpsCleanupKind { kind }
    var kind: OpsCleanupKind
    var path: String?
    var sizeBytes: Int64?
    var isAvailable: Bool
    var detail: String

    var isActionable: Bool {
        isAvailable
    }
}

struct OpsCleanupResult: Sendable, Hashable {
    var removedKinds: Set<OpsCleanupKind>
    var skippedKinds: [OpsCleanupKind: String]
    var commandOutput: String?
}

struct OpsHostEntry: Identifiable, Sendable, Hashable {
    var id: String { "\(lineNumber):\(rawLine)" }
    var lineNumber: Int
    var rawLine: String
}

struct OpsDiagnosticsSnapshot: Sendable, Hashable {
    var proxySummary: String
    var dnsSummary: String
    var hostsEntries: [OpsHostEntry]
    var errors: [String] = []
}

struct OpsURLDiagnosticResult: Sendable, Hashable {
    var url: String
    var headerText: String
    var tlsExpiration: Date?
    var errorMessage: String?
}

enum OpsPendingAction: Sendable, Hashable {
    case terminate(target: OpsProcessIdentity, displayName: String, signal: Int32)
    case brew(OpsBrewAction)
    case cleanup(kinds: Set<OpsCleanupKind>)
}

enum OpsBrewServiceAction: String, CaseIterable, Identifiable, Sendable, Hashable {
    case start
    case stop
    case restart

    var id: String { rawValue }
}

enum OpsBrewAction: Sendable, Hashable {
    case install(String)
    case uninstall(String)
    case upgrade(String)
    case cleanup
    case service(OpsBrewServiceAction, String)

    var arguments: [String] {
        switch self {
        case .install(let token):
            ["install", token]
        case .uninstall(let token):
            ["uninstall", token]
        case .upgrade(let token):
            ["upgrade", token]
        case .cleanup:
            ["cleanup"]
        case .service(let action, let name):
            ["services", action.rawValue, name]
        }
    }

    var commandSummary: String {
        "brew \(arguments.joined(separator: " "))"
    }
}

struct OpsConfirmation: Identifiable, Sendable, Hashable {
    var id = UUID()
    var title: String
    var message: String
    var commandSummary: String
    var action: OpsPendingAction
}

struct OpsTerminationOutcome: Sendable, Hashable {
    var pid: Int32
    var signal: Int32
    var isStillRunning: Bool
}
