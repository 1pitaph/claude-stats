import Foundation

enum ProjectLaunchKind: String, Codable, CaseIterable, Sendable, Hashable {
    case script
    case electron
    case web
    case node
    case docker
    case xcode
    case rust
    case python
    case make
    case just

    var title: String {
        switch self {
        case .script: "Script"
        case .electron: "Electron"
        case .web: "Web"
        case .node: "Node.js"
        case .docker: "Docker"
        case .xcode: "Xcode"
        case .rust: "Rust"
        case .python: "Python"
        case .make: "Make"
        case .just: "Just"
        }
    }

    var symbol: String {
        switch self {
        case .script: AppIcon.Runtime.terminal
        case .electron: "app.dashed"
        case .web: "globe"
        case .node: "server.rack"
        case .docker: "shippingbox"
        case .xcode: "hammer"
        case .rust: "gearshape.2"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .make: "wrench.adjustable"
        case .just: "bolt"
        }
    }
}

enum ProjectLaunchLifecycle: String, Codable, Sendable, Hashable {
    case longRunning
    case oneShot
}

enum ProjectLaunchConfidence: Int, Codable, Sendable, Hashable, Comparable {
    case medium = 1
    case high = 2
    case certain = 3

    static func < (lhs: ProjectLaunchConfidence, rhs: ProjectLaunchConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .medium: "Inferred"
        case .high: "Detected"
        case .certain: "Project script"
        }
    }
}

struct ProjectLaunchCommand: Codable, Sendable, Hashable {
    let executablePath: String
    let arguments: [String]

    var displayString: String {
        let executable = executablePath == "/usr/bin/env"
            ? nil
            : URL(fileURLWithPath: executablePath).lastPathComponent
        return ([executable].compactMap { $0 } + arguments)
            .map(Self.shellQuoted)
            .joined(separator: " ")
    }

    private static func shellQuoted(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-=/:.,@")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct ProjectLaunchAction: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let detail: String
    let kind: ProjectLaunchKind
    let workingDirectory: String
    let command: ProjectLaunchCommand
    let stopCommand: ProjectLaunchCommand?
    let lifecycle: ProjectLaunchLifecycle
    let confidence: ProjectLaunchConfidence
    let sourcePath: String
    let priority: Int

    var displayCommand: String { command.displayString }
}

struct ProjectLaunchDescriptor: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let rootPath: String
    let actions: [ProjectLaunchAction]
    let primaryActionID: ProjectLaunchAction.ID?
    let recommendedActionIDs: [ProjectLaunchAction.ID]

    var primaryAction: ProjectLaunchAction? {
        guard let primaryActionID else { return nil }
        return actions.first { $0.id == primaryActionID }
    }

    var recommendedActions: [ProjectLaunchAction] {
        let byID = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        return recommendedActionIDs.compactMap { byID[$0] }
    }

    var isLaunchable: Bool { !actions.isEmpty }
}

struct ProjectLaunchSnapshot: Sendable, Hashable {
    let projects: [ProjectLaunchDescriptor]
    let scannedAt: Date?
    let sourcePathCount: Int
    let gitAvailable: Bool

    static let empty = ProjectLaunchSnapshot(
        projects: [],
        scannedAt: nil,
        sourcePathCount: 0,
        gitAvailable: true
    )
}

enum ProjectLaunchPhase: String, Sendable, Hashable {
    case stopped
    case starting
    case running
    case stopping
    case failed

    var isActive: Bool {
        switch self {
        case .starting, .running, .stopping: true
        case .stopped, .failed: false
        }
    }
}

struct ProjectLaunchRuntimeState: Sendable, Hashable {
    var phase: ProjectLaunchPhase = .stopped
    var pid: Int32?
    var startedAt: Date?
    var lastExitCode: Int32?
    var lastError: String?

    static let stopped = ProjectLaunchRuntimeState()
}

enum ProjectLaunchLogStream: String, Sendable, Hashable {
    case system
    case stdout
    case stderr
}

struct ProjectLaunchLogEntry: Identifiable, Sendable, Hashable {
    let id: UUID
    let date: Date
    let stream: ProjectLaunchLogStream
    let text: String

    init(id: UUID = UUID(), date: Date = .now, stream: ProjectLaunchLogStream, text: String) {
        self.id = id
        self.date = date
        self.stream = stream
        self.text = text
    }
}
