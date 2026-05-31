import Foundation

enum NetworkTrafficWorkspace: String, CaseIterable, Identifiable, Sendable, Hashable {
    case httpTraffic
    case webSocket
    case replay
    case intercept
    case automate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .httpTraffic: "HTTP Traffic"
        case .webSocket: "WebSocket"
        case .replay: "Replay"
        case .intercept: "Intercept"
        case .automate: "Automate"
        }
    }

    var symbol: String {
        switch self {
        case .httpTraffic: AppIcon.Network.traffic
        case .webSocket: AppIcon.Network.webSocket
        case .replay: AppIcon.Network.replay
        case .intercept: AppIcon.Action.pause
        case .automate: AppIcon.Network.automate
        }
    }
}

enum NetworkFlowOperationSource: String, Sendable, Hashable {
    case capture = "Capture"
    case replay = "Replay"
    case compose = "Compose"
    case automate = "Automate"
    case interceptModified = "Intercept Modified"
}

enum NetworkRequestExportFormat: String, CaseIterable, Identifiable, Sendable, Hashable {
    case har
    case curl
    case rawRequest
    case rawResponse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .har: "HAR"
        case .curl: "cURL"
        case .rawRequest: "Raw Request"
        case .rawResponse: "Raw Response"
        }
    }
}

enum NetworkRequestImportFormat: String, CaseIterable, Identifiable, Sendable, Hashable {
    case curl
    case rawHTTP

    var id: String { rawValue }

    var title: String {
        switch self {
        case .curl: "cURL"
        case .rawHTTP: "Raw HTTP"
        }
    }
}

enum NetworkReplaySessionSource: String, Sendable, Hashable {
    case flow = "Flow"
    case compose = "Compose"
    case importText = "Import"
}

struct NetworkReplaySession: Identifiable, Sendable, Hashable {
    var id: UUID = UUID()
    var title: String
    var source: NetworkReplaySessionSource
    var createdAt: Date = .now
    var originalFlowID: UUID?
    var draft: NetworkReplayDraft
    var results: [NetworkReplayRunResult] = []

    var latestResult: NetworkReplayRunResult? { results.first }
}

struct NetworkReplayRunResult: Identifiable, Sendable, Hashable {
    var id: UUID = UUID()
    var flowID: UUID
    var startedAt: Date
    var completedAt: Date
    var statusCode: Int?
    var duration: TimeInterval
    var responseBytes: Int
    var errorMessage: String?
}

struct NetworkBatchReplayItemResult: Identifiable, Sendable, Hashable {
    var id: UUID = UUID()
    var index: Int
    var flow: NetworkFlow?
    var errorMessage: String?

    var isSuccess: Bool { flow != nil }
}

struct NetworkAutomateVariable: Identifiable, Sendable, Hashable {
    var id: UUID = UUID()
    var name: String
    var valuesText: String

    var values: [String] {
        valuesText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct NetworkAutomateDraft: Sendable, Hashable {
    var baseDraft: NetworkReplayDraft
    var variables: [NetworkAutomateVariable] = [
        NetworkAutomateVariable(name: "value", valuesText: "one\ntwo\nthree"),
    ]
    var concurrencyLimit: Int = 1

    var expandedDrafts: [NetworkReplayDraft] {
        guard let variable = variables.first, !variable.name.isEmpty else {
            return [baseDraft]
        }
        let token = "{{\(variable.name)}}"
        let values = variable.values
        guard !values.isEmpty else { return [baseDraft] }
        return values.map { value in
            var draft = baseDraft
            draft.id = UUID()
            draft.url = draft.url.replacingOccurrences(of: token, with: value)
            draft.bodyText = draft.bodyText.replacingOccurrences(of: token, with: value)
            draft.headers = draft.headers.map {
                NetworkHeaderPair(
                    name: $0.name.replacingOccurrences(of: token, with: value),
                    value: $0.value.replacingOccurrences(of: token, with: value)
                )
            }
            return draft
        }
    }
}

struct NetworkAutomateRunResult: Identifiable, Sendable, Hashable {
    var id: UUID = UUID()
    var requestIndex: Int
    var flowID: UUID?
    var url: String
    var statusCode: Int?
    var duration: TimeInterval?
    var responseBytes: Int
    var errorMessage: String?
}

enum NetworkWebSocketDirectionFilter: String, CaseIterable, Identifiable, Sendable, Hashable {
    case all
    case sent
    case received

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .sent: "Sent"
        case .received: "Received"
        }
    }
}

enum NetworkWebSocketOpcodeFilter: String, CaseIterable, Identifiable, Sendable, Hashable {
    case all
    case text
    case binary
    case ping
    case pong
    case close

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .binary: "Binary"
        case .ping: "Ping"
        case .pong: "Pong"
        case .close: "Close"
        }
    }
}

struct NetworkWebSocketMessageFilter: Sendable, Equatable {
    var query = ""
    var direction: NetworkWebSocketDirectionFilter = .all
    var opcode: NetworkWebSocketOpcodeFilter = .all
}

struct NetworkWebSocketSession: Identifiable, Sendable, Hashable {
    var id: UUID
    var flowID: UUID
    var number: Int
    var url: String
    var domain: String
    var clientName: String
    var startedAt: Date
    var completedAt: Date?
    var state: NetworkFlowState
    var requestHeaders: [NetworkHeaderPair]
    var messages: [NetworkWebSocketMessage]

    var isActive: Bool { state == .active }
    var sentCount: Int { messages.filter { $0.direction == .sent }.count }
    var receivedCount: Int { messages.filter { $0.direction == .received }.count }
    var lastActivityAt: Date { messages.last?.timestamp ?? completedAt ?? startedAt }
}

struct NetworkWebSocketMessage: Identifiable, Sendable, Hashable {
    var id: UUID
    var sessionID: UUID
    var flowID: UUID
    var timestamp: Date
    var direction: NetworkWebSocketFrameDirection
    var opcode: String
    var payloadText: String
    var payloadBytes: Int
    var isFinal: Bool
    var isDropped: Bool = false
    var isEdited: Bool = false
    var isInjected: Bool = false

    var displayDirection: String { direction.title }
}

struct NetworkWebSocketSendDraft: Sendable, Hashable {
    var sessionID: UUID?
    var opcode: String = "text"
    var payloadText: String = ""
}

struct NetworkRouteProbeStep: Identifiable, Sendable, Hashable {
    var id: UUID = UUID()
    var title: String
    var status: NetworkRouteProbeStepStatus
    var detail: String
    var latencyMs: Double?
}

enum NetworkRouteProbeStepStatus: String, Sendable, Hashable {
    case pending
    case success
    case warning
    case failure
    case skipped
}

struct NetworkRouteProbeResult: Identifiable, Sendable, Hashable {
    var id: UUID = UUID()
    var profileID: UUID?
    var startedAt: Date
    var targetURL: String
    var selectedRoute: String
    var isReachable: Bool
    var steps: [NetworkRouteProbeStep]
    var errorMessage: String?
}

struct NetworkUpstreamCredentialRef: Identifiable, Sendable, Hashable, Codable {
    var id: UUID = UUID()
    var username: String = ""
    var keychainService: String = "com.claudestats.network.upstream"
    var keychainAccount: String = ""

    var hasUsername: Bool { !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasSecretReference: Bool { !keychainAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct NetworkUpstreamProfile: Identifiable, Sendable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var settings: NetworkUpstreamProxySettings
    var credentialRef: NetworkUpstreamCredentialRef?
    var isAutoDetected: Bool = false
    var lastTestedAt: Date?
    var lastProbeSummary: String?

    var summary: String { settings.summary }

    static let direct = NetworkUpstreamProfile(
        name: "Direct",
        settings: .disabled
    )
}

enum NetworkUpstreamRouteMatchScheme: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case any
    case http
    case https
    case websocket

    var id: String { rawValue }
}

struct NetworkUpstreamRouteRule: Identifiable, Sendable, Hashable, Codable {
    var id: UUID = UUID()
    var isEnabled = true
    var hostPattern: String = "*"
    var scheme: NetworkUpstreamRouteMatchScheme = .any
    var profileID: UUID?
    var fallbackProfileIDs: [UUID] = []
    var bypassLocalhost = true

    var title: String {
        "\(scheme.rawValue.uppercased()) \(hostPattern)"
    }
}

struct NetworkUpstreamEnvironment: Identifiable, Sendable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var isDefault = false
    var profiles: [NetworkUpstreamProfile]
    var routeRules: [NetworkUpstreamRouteRule]
    var selectedProfileID: UUID?
    var askBeforeChainingExistingSystemProxy = false

    static let `default` = NetworkUpstreamEnvironment(
        name: "Default",
        isDefault: true,
        profiles: [.direct],
        routeRules: [],
        selectedProfileID: NetworkUpstreamProfile.direct.id
    )

    var selectedProfile: NetworkUpstreamProfile {
        profiles.first { $0.id == selectedProfileID } ?? profiles.first ?? .direct
    }
}
