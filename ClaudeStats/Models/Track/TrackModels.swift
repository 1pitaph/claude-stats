import Foundation

enum TrackSection: String, CaseIterable, Identifiable, Sendable, Hashable {
    case flow
    case approvals
    case tools
    case events

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flow: "Flow"
        case .approvals: "Approvals"
        case .tools: "Tool Use"
        case .events: "Events"
        }
    }

    var symbol: String {
        switch self {
        case .flow: AppIcon.Track.flow
        case .approvals: AppIcon.Track.approvals
        case .tools: AppIcon.Track.tools
        case .events: AppIcon.Track.events
        }
    }

    var detailTitle: String {
        switch self {
        case .flow: "Agent flow"
        case .approvals: "Approval queue"
        case .tools: "Tool activity"
        case .events: "Event stream"
        }
    }

    var detailDescription: String {
        switch self {
        case .flow:
            "Track parent sessions, subagents, tool calls, and approval gates as a connected execution graph."
        case .approvals:
            "Review tool calls that are waiting for user permission or recently resolved."
        case .tools:
            "Inspect recent tool use, inferred commands, and completion status across active sessions."
        case .events:
            "Audit raw Track events from hooks, app-server signals, and transcript fallbacks."
        }
    }
}

enum TrackEventSource: String, Codable, Sendable, Hashable {
    case hook
    case appServer
    case transcript
    case process
    case notification

    var title: String {
        switch self {
        case .hook: "Hook"
        case .appServer: "App Server"
        case .transcript: "Transcript"
        case .process: "Process"
        case .notification: "Notification"
        }
    }

    var confidence: TrackConfidence {
        switch self {
        case .hook, .appServer: .high
        case .transcript: .medium
        case .process, .notification: .low
        }
    }
}

enum TrackConfidence: String, Codable, Sendable, Hashable, Comparable {
    case low
    case medium
    case high

    static func < (lhs: TrackConfidence, rhs: TrackConfidence) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    var title: String {
        switch self {
        case .low: "Low confidence"
        case .medium: "Medium confidence"
        case .high: "High confidence"
        }
    }
}

enum TrackEventKind: String, Codable, Sendable, Hashable {
    case sessionStarted
    case sessionStopped
    case turnStarted
    case subagentStarted
    case subagentStopped
    case toolRequested
    case toolStarted
    case toolSucceeded
    case toolFailed
    case approvalRequested
    case approvalAllowed
    case approvalDenied
    case questionAsked
    case questionReplied
    case statusChanged
    case transcriptActivity
    case error

    var title: String {
        switch self {
        case .sessionStarted: "Session started"
        case .sessionStopped: "Session stopped"
        case .turnStarted: "Turn started"
        case .subagentStarted: "Subagent started"
        case .subagentStopped: "Subagent stopped"
        case .toolRequested: "Tool requested"
        case .toolStarted: "Tool started"
        case .toolSucceeded: "Tool succeeded"
        case .toolFailed: "Tool failed"
        case .approvalRequested: "Approval requested"
        case .approvalAllowed: "Approval allowed"
        case .approvalDenied: "Approval denied"
        case .questionAsked: "Question asked"
        case .questionReplied: "Question replied"
        case .statusChanged: "Status changed"
        case .transcriptActivity: "Transcript activity"
        case .error: "Error"
        }
    }
}

enum TrackStatus: String, Codable, Sendable, Hashable {
    case running
    case usingTool
    case waitingApproval
    case approved
    case denied
    case completed
    case failed
    case recentlyActive
    case maybeRunning
    case unknown

    var title: String {
        switch self {
        case .running: "Running"
        case .usingTool: "Using tool"
        case .waitingApproval: "Waiting approval"
        case .approved: "Approved"
        case .denied: "Denied"
        case .completed: "Completed"
        case .failed: "Failed"
        case .recentlyActive: "Recently active"
        case .maybeRunning: "Maybe running"
        case .unknown: "Unknown"
        }
    }

    var priority: Int {
        switch self {
        case .waitingApproval: 90
        case .usingTool: 80
        case .running: 70
        case .maybeRunning: 60
        case .recentlyActive: 50
        case .failed: 45
        case .denied: 40
        case .approved: 30
        case .completed: 20
        case .unknown: 0
        }
    }
}

enum TrackNodeKind: String, Codable, Sendable, Hashable {
    case session
    case turn
    case subagent
    case tool
    case approval
    case result

    var title: String {
        switch self {
        case .session: "Session"
        case .turn: "Turn"
        case .subagent: "Subagent"
        case .tool: "Tool"
        case .approval: "Approval"
        case .result: "Result"
        }
    }
}

struct TrackEvent: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var timestamp: Date
    var source: TrackEventSource
    var kind: TrackEventKind
    var provider: ProviderKind?
    var sessionID: String
    var parentSessionID: String?
    var turnID: String?
    var agentID: String?
    var agentType: String?
    var toolUseID: String?
    var approvalID: String?
    var toolName: String?
    var permissionMode: String?
    var cwd: String?
    var transcriptPath: String?
    var summary: String
    var detail: String?
    var confidence: TrackConfidence
}

struct TrackNode: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var kind: TrackNodeKind
    var title: String
    var subtitle: String
    var status: TrackStatus
    var source: TrackEventSource
    var confidence: TrackConfidence
    var startedAt: Date?
    var endedAt: Date?
    var provider: ProviderKind?
    var eventIDs: [TrackEvent.ID]
    var metadata: [String: String] = [:]
}

struct TrackEdge: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(from)->\(to)" }
    var from: TrackNode.ID
    var to: TrackNode.ID
    var source: TrackEventSource
    var confidence: TrackConfidence
}

struct TrackApprovalItem: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var runID: TrackRun.ID
    var nodeID: TrackNode.ID
    var sessionID: String
    var title: String
    var detail: String
    var toolName: String?
    var status: TrackStatus
    var requestedAt: Date
    var resolvedAt: Date?
    var source: TrackEventSource
    var confidence: TrackConfidence
}

struct TrackToolItem: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var runID: TrackRun.ID
    var nodeID: TrackNode.ID
    var sessionID: String
    var title: String
    var detail: String
    var toolName: String?
    var status: TrackStatus
    var startedAt: Date
    var endedAt: Date?
    var source: TrackEventSource
    var confidence: TrackConfidence
}

struct TrackRun: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var provider: ProviderKind?
    var sessionID: String
    var title: String
    var projectName: String
    var cwd: String?
    var status: TrackStatus
    var confidence: TrackConfidence
    var startedAt: Date?
    var updatedAt: Date
    var nodes: [TrackNode]
    var edges: [TrackEdge]
    var events: [TrackEvent]
    var approvals: [TrackApprovalItem]
    var tools: [TrackToolItem]

    var pendingApprovalCount: Int {
        approvals.filter { $0.status == .waitingApproval }.count
    }

    var toolCount: Int { tools.count }

    var subagentCount: Int {
        nodes.filter { $0.kind == .subagent }.count
    }
}

struct TrackSnapshot: Codable, Sendable, Hashable {
    var runs: [TrackRun]
    var events: [TrackEvent]
    var approvals: [TrackApprovalItem]
    var tools: [TrackToolItem]
    var loadedAt: Date
    var eventLogURLs: [URL]

    static let empty = TrackSnapshot(runs: [], events: [], approvals: [], tools: [], loadedAt: .distantPast, eventLogURLs: [])

    var activeCount: Int {
        runs.filter { [.running, .usingTool, .waitingApproval, .maybeRunning, .recentlyActive].contains($0.status) }.count
    }

    var pendingApprovalCount: Int {
        approvals.filter { $0.status == .waitingApproval }.count
    }

    var highConfidenceEventCount: Int {
        events.filter { $0.confidence == .high }.count
    }
}

enum TrackJSONValue: Decodable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: TrackJSONValue])
    case array([TrackJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: TrackJSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([TrackJSONValue].self))
        }
    }

    var compactDescription: String {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            if value.rounded() == value { "\(Int(value))" }
            else { "\(value)" }
        case .bool(let value):
            value ? "true" : "false"
        case .null:
            "null"
        case .array(let values):
            "[" + values.map(\.compactDescription).joined(separator: ", ") + "]"
        case .object(let object):
            object
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.compactDescription)" }
                .joined(separator: ", ")
        }
    }
}
