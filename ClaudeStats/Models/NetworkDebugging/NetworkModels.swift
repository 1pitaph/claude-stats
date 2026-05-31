import Foundation

enum NetworkSection: String, CaseIterable, Identifiable, Sendable, Hashable {
    case traffic
    case proxy
    case certificates
    case rules

    var id: String { rawValue }

    init(storedRawValue: String) {
        switch storedRawValue {
        case "setup", "helper", "upstream":
            self = .proxy
        default:
            self = NetworkSection(rawValue: storedRawValue) ?? .traffic
        }
    }

    var title: String {
        switch self {
        case .traffic: "Traffic"
        case .proxy: "Proxy"
        case .certificates: "Certificates"
        case .rules: "Rules"
        }
    }

    var symbol: String {
        switch self {
        case .traffic: AppIcon.Network.traffic
        case .proxy: AppIcon.Network.proxy
        case .certificates: AppIcon.Network.certificates
        case .rules: AppIcon.Network.rules
        }
    }
}

enum NetworkTrafficSidebarLayer: String, Sendable {
    case sections
    case filters
}

enum NetworkResolvedTrafficLayout: String, Sendable, Equatable {
    case stacked
    case sideBySide
}

enum NetworkTrafficLayoutConstants {
    static let defaultAutoBreakpoint: Double = 900
    static let minimumAutoBreakpoint: Double = 640
    static let maximumAutoBreakpoint: Double = 1600
    static let autoBreakpointStep: Double = 20

    static func clampedAutoBreakpoint(_ value: Double) -> Double {
        guard value.isFinite else { return defaultAutoBreakpoint }
        return min(max(value, minimumAutoBreakpoint), maximumAutoBreakpoint)
    }
}

enum NetworkTrafficLayoutMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case stacked
    case sideBySide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Auto"
        case .stacked: "Top Bottom"
        case .sideBySide: "Left Right"
        }
    }

    var symbol: String {
        switch self {
        case .automatic: AppIcon.Workspace.dashboard
        case .stacked: AppIcon.Layout.stacked
        case .sideBySide: AppIcon.Layout.sideBySide
        }
    }

    var help: String {
        switch self {
        case .automatic: "Automatically arrange traffic and payload panes"
        case .stacked: "Place traffic above Request and Response panes"
        case .sideBySide: "Place traffic beside Request and Response panes"
        }
    }

    func resolved(width: Double, breakpoint: Double) -> NetworkResolvedTrafficLayout {
        switch self {
        case .automatic:
            let clampedBreakpoint = NetworkTrafficLayoutConstants.clampedAutoBreakpoint(breakpoint)
            return width < clampedBreakpoint ? .stacked : .sideBySide
        case .stacked:
            return .stacked
        case .sideBySide:
            return .sideBySide
        }
    }
}

enum NetworkInspectorSide: String, CaseIterable, Identifiable, Sendable, Hashable {
    case request
    case response

    var id: String { rawValue }

    var title: String {
        switch self {
        case .request: "Request"
        case .response: "Response"
        }
    }
}

enum NetworkInspectorTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case header
    case query
    case cookies
    case form
    case body
    case preview
    case raw
    case json
    case webSocket
    case timing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .header: "Header"
        case .query: "Query"
        case .cookies: "Cookies"
        case .form: "Form"
        case .body: "Body"
        case .preview: "Preview"
        case .raw: "Raw"
        case .json: "JSON"
        case .webSocket: "Frames"
        case .timing: "Timing"
        }
    }
}

enum NetworkFlowProtocol: String, CaseIterable, Identifiable, Sendable, Hashable {
    case http = "HTTP"
    case https = "HTTPS"
    case webSocket = "WebSocket"
    case tunnel = "Tunnel"

    var id: String { rawValue }
}

enum NetworkFlowState: String, Sendable, Hashable {
    case active
    case completed
    case failed
}

enum NetworkTrafficStatusFilter: String, CaseIterable, Identifiable, Sendable, Hashable {
    case informational
    case success
    case redirect
    case clientError
    case serverError
    case active
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .informational: "1xx"
        case .success: "2xx"
        case .redirect: "3xx"
        case .clientError: "4xx"
        case .serverError: "5xx"
        case .active: "Active"
        case .failed: "Failed"
        }
    }

    func matches(_ flow: NetworkFlow) -> Bool {
        switch self {
        case .active:
            return flow.state == .active
        case .failed:
            return flow.state == .failed
        case .informational:
            return (flow.response.statusCode ?? -1) >= 100 && (flow.response.statusCode ?? -1) < 200
        case .success:
            return (flow.response.statusCode ?? -1) >= 200 && (flow.response.statusCode ?? -1) < 300
        case .redirect:
            return (flow.response.statusCode ?? -1) >= 300 && (flow.response.statusCode ?? -1) < 400
        case .clientError:
            return (flow.response.statusCode ?? -1) >= 400 && (flow.response.statusCode ?? -1) < 500
        case .serverError:
            return (flow.response.statusCode ?? -1) >= 500 && (flow.response.statusCode ?? -1) < 600
        }
    }
}

struct NetworkTrafficFilter: Sendable, Equatable {
    var query: String = ""
    var protocols: Set<NetworkFlowProtocol> = []
    var apps: Set<String> = []
    var domains: Set<String> = []
    var methods: Set<String> = []
    var statuses: Set<NetworkTrafficStatusFilter> = []
    var pinnedOnly = false
    var savedOnly = false

    var isEmpty: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && protocols.isEmpty
            && apps.isEmpty
            && domains.isEmpty
            && methods.isEmpty
            && statuses.isEmpty
            && !pinnedOnly
            && !savedOnly
    }
}

struct NetworkTrafficFilterGroup: Identifiable, Sendable, Hashable {
    var id: String
    var title: String
    var symbol: String
    var count: Int
}

enum NetworkUpstreamProxyMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case manual
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            "Auto"
        case .manual:
            "Manual"
        case .off:
            "Off"
        }
    }
}

enum NetworkUpstreamProxyProtocol: String, CaseIterable, Identifiable, Sendable, Codable {
    case http
    case https
    case socks5
    case pac

    var id: String { rawValue }

    var title: String {
        switch self {
        case .http:
            "HTTP"
        case .https:
            "HTTPS"
        case .socks5:
            "SOCKS5"
        case .pac:
            "PAC"
        }
    }
}

struct NetworkUpstreamProxyServerSettings: Sendable, Hashable, Codable {
    var proto: NetworkUpstreamProxyProtocol
    var host: String
    var port: UInt16
    var username: String?
    var password: String?
    var pacURL: URL?
    var pacScript: String?

    var displayName: String {
        switch proto {
        case .pac:
            pacURL?.absoluteString ?? "PAC"
        default:
            "\(proto.title) \(host):\(port)"
        }
    }
}

struct NetworkUpstreamProxySettings: Sendable, Hashable, Codable {
    var isEnabled: Bool
    var proxies: [NetworkUpstreamProxyServerSettings]
    var includeHosts: [String]
    var excludeHosts: [String]
    var bypassLocalhost: Bool
    var dnsOverSocks: Bool

    static let disabled = NetworkUpstreamProxySettings(
        isEnabled: false,
        proxies: [],
        includeHosts: [],
        excludeHosts: [],
        bypassLocalhost: true,
        dnsOverSocks: true
    )

    var summary: String {
        guard isEnabled, let first = proxies.first else { return "Direct" }
        if proxies.count == 1 { return first.displayName }
        return "\(first.displayName) + \(proxies.count - 1)"
    }
}

struct NetworkUpstreamProxyTestResult: Sendable, Equatable {
    var isReachable: Bool
    var routeSummary: String
    var errorMessage: String?
    var probeSteps: [NetworkRouteProbeStep] = []
}

struct NetworkFlowUpstreamProxy: Sendable, Hashable {
    var kind: String
    var summary: String

    static let direct = NetworkFlowUpstreamProxy(kind: "Direct", summary: "Direct")
}

enum NetworkClientAttribution: String, Sendable, Hashable {
    case process
    case userAgent
    case unresolved
}

struct NetworkHeaderPair: Identifiable, Sendable, Hashable {
    let id: String
    var name: String
    var value: String

    init(name: String, value: String) {
        self.id = "\(name.lowercased()):\(value)"
        self.name = name
        self.value = value
    }
}

struct NetworkBody: Sendable, Hashable {
    var bytes: Int
    var text: String
    var isTruncated: Bool
    var contentType: String?
    var data: Data?

    init(bytes: Int, text: String, isTruncated: Bool, contentType: String?, data: Data? = nil) {
        self.bytes = bytes
        self.text = text
        self.isTruncated = isTruncated
        self.contentType = contentType
        self.data = data
    }

    static let empty = NetworkBody(bytes: 0, text: "", isTruncated: false, contentType: nil, data: nil)
}

struct NetworkCookie: Identifiable, Sendable, Hashable {
    let id: String
    var name: String
    var value: String
    var attributes: [String: String]

    init(name: String, value: String, attributes: [String: String] = [:]) {
        self.id = "\(name)=\(value)"
        self.name = name
        self.value = value
        self.attributes = attributes
    }
}

struct NetworkRequestCapture: Sendable, Hashable {
    var method: String
    var url: String
    var httpVersion: String
    var headers: [NetworkHeaderPair]
    var body: NetworkBody

    var host: String {
        if let url = URL(string: url), let host = url.host { return host }
        return header(named: "Host") ?? ""
    }

    func header(named name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

struct NetworkResponseCapture: Sendable, Hashable {
    var statusCode: Int?
    var reason: String
    var headers: [NetworkHeaderPair]
    var body: NetworkBody

    static let empty = NetworkResponseCapture(statusCode: nil, reason: "", headers: [], body: .empty)
}

enum NetworkWebSocketFrameDirection: String, Sendable, Hashable {
    case sent
    case received

    var title: String {
        switch self {
        case .sent: "Sent"
        case .received: "Received"
        }
    }
}

struct NetworkWebSocketFrame: Identifiable, Sendable, Hashable {
    var id: UUID
    var timestamp: Date
    var direction: NetworkWebSocketFrameDirection
    var opcode: String
    var payloadText: String
    var payloadBytes: Int
    var isFinal: Bool
    var isDropped: Bool = false
    var isEdited: Bool = false
    var isInjected: Bool = false
}

struct NetworkFlowTiming: Sendable, Hashable {
    var startedAt: Date
    var completedAt: Date?
    var duration: TimeInterval
}

struct NetworkFlow: Identifiable, Sendable, Hashable {
    var id: UUID
    var number: Int
    var createdAt: Date
    var completedAt: Date?
    var clientName: String
    var sourcePort: UInt16? = nil
    var clientAttribution: NetworkClientAttribution = .unresolved
    var flowProtocol: NetworkFlowProtocol
    var state: NetworkFlowState
    var request: NetworkRequestCapture
    var response: NetworkResponseCapture
    var requestBytes: Int
    var responseBytes: Int
    var isSSLIntercepted: Bool
    var isEdited: Bool
    var errorDescription: String?
    var upstreamProxy: NetworkFlowUpstreamProxy = .direct
    var establishmentDuration: TimeInterval?
    var matchedRuleName: String?
    var matchedRuleSummary: String?
    var matchedRulePattern: String?
    var webSocketFrames: [NetworkWebSocketFrame] = []
    var isPinned: Bool = false
    var isSaved: Bool = false
    var isReplay: Bool = false
    var comment: String = ""
    var operationSource: NetworkFlowOperationSource = .capture

    var duration: TimeInterval {
        (completedAt ?? Date()).timeIntervalSince(createdAt)
    }

    var statusDisplay: String {
        if let code = response.statusCode { return "\(code)" }
        if state == .active { return "Active" }
        if state == .failed { return "Failed" }
        return "-"
    }

    var urlDisplay: String { request.url }

    var domainDisplay: String {
        if let host = URL(string: request.url)?.host, !host.isEmpty { return host }
        return request.host.isEmpty ? "Unknown" : request.host
    }

    var methodDisplay: String { request.method.uppercased() }

    var timing: NetworkFlowTiming {
        NetworkFlowTiming(startedAt: createdAt, completedAt: completedAt, duration: duration)
    }

    static func placeholder(now: Date = .now) -> [NetworkFlow] {
        [
            NetworkFlow(
                id: UUID(),
                number: 1,
                createdAt: now.addingTimeInterval(-18),
                completedAt: now.addingTimeInterval(-17.76),
                clientName: "Preview",
                flowProtocol: .http,
                state: .completed,
                request: NetworkRequestCapture(
                    method: "GET",
                    url: "http://httpbin.org/json",
                    httpVersion: "HTTP/1.1",
                    headers: [
                        NetworkHeaderPair(name: "Host", value: "httpbin.org"),
                        NetworkHeaderPair(name: "User-Agent", value: "Claude Stats Network"),
                        NetworkHeaderPair(name: "Accept", value: "application/json"),
                    ],
                    body: .empty
                ),
                response: NetworkResponseCapture(
                    statusCode: 200,
                    reason: "OK",
                    headers: [
                        NetworkHeaderPair(name: "Content-Type", value: "application/json"),
                        NetworkHeaderPair(name: "Server", value: "preview"),
                    ],
                    body: NetworkBody(bytes: 44, text: "{\n  \"slideshow\": {\n    \"title\": \"Sample\"\n  }\n}", isTruncated: false, contentType: "application/json")
                ),
                requestBytes: 112,
                responseBytes: 276,
                isSSLIntercepted: false,
                isEdited: false,
                errorDescription: nil
            ),
            NetworkFlow(
                id: UUID(),
                number: 2,
                createdAt: now.addingTimeInterval(-11),
                completedAt: now.addingTimeInterval(-10.91),
                clientName: "curl",
                flowProtocol: .tunnel,
                state: .completed,
                request: NetworkRequestCapture(
                    method: "CONNECT",
                    url: "https://api.openai.com:443",
                    httpVersion: "HTTP/1.1",
                    headers: [NetworkHeaderPair(name: "Host", value: "api.openai.com:443")],
                    body: .empty
                ),
                response: NetworkResponseCapture(statusCode: 200, reason: "Connection Established", headers: [], body: .empty),
                requestBytes: 0,
                responseBytes: 0,
                isSSLIntercepted: false,
                isEdited: false,
                errorDescription: nil
            ),
        ]
    }
}

enum NetworkRuleActionKind: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case block
    case mapLocal
    case mapRemote
    case modifyHeaders
    case throttle
    case networkCondition
    case breakpoint
    case script

    var id: String { rawValue }

    var title: String {
        switch self {
        case .block: "Block"
        case .mapLocal: "Map Local"
        case .mapRemote: "Map Remote"
        case .modifyHeaders: "Modify Headers"
        case .throttle: "Throttle"
        case .networkCondition: "Network Condition"
        case .breakpoint: "Breakpoint"
        case .script: "Script"
        }
    }
}

enum NetworkRuleMatchMethod: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case any = "ANY"
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"

    var id: String { rawValue }
}

enum NetworkHeaderOperationKind: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case add
    case remove
    case replace

    var id: String { rawValue }
}

enum NetworkHeaderOperationPhase: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case request
    case response
    case both

    var id: String { rawValue }
}

struct NetworkHeaderOperationDraft: Identifiable, Sendable, Hashable, Codable {
    var id: UUID = UUID()
    var kind: NetworkHeaderOperationKind = .add
    var phase: NetworkHeaderOperationPhase = .request
    var name: String = ""
    var value: String = ""
}

enum NetworkBreakpointPhase: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case request
    case response
    case both

    var id: String { rawValue }
}

enum NetworkScriptRuleMode: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case transform
    case mock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transform: "Transform"
        case .mock: "Mock"
        }
    }
}

enum NetworkBreakpointDecision: String, CaseIterable, Identifiable, Sendable, Hashable {
    case execute
    case abort
    case cancel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .execute: "Continue"
        case .abort: "Drop"
        case .cancel: "Cancel"
        }
    }
}

struct NetworkRuleActionDraft: Sendable, Hashable, Codable {
    var kind: NetworkRuleActionKind = .block
    var blockStatusCode: Int = 403
    var mapLocalPath: String = ""
    var mapLocalStatusCode: Int = 200
    var mapLocalIsDirectory = false
    var mapRemoteScheme: String = "https"
    var mapRemoteHost: String = ""
    var mapRemotePortText: String = ""
    var mapRemotePath: String = ""
    var mapRemoteQuery: String = ""
    var mapRemotePreserveHostHeader = false
    var headerOperations: [NetworkHeaderOperationDraft] = [NetworkHeaderOperationDraft()]
    var throttleDelayMs: Int = 500
    var networkConditionName: String = "Slow 3G"
    var networkConditionDelayMs: Int = 1_000
    var breakpointPhase: NetworkBreakpointPhase = .both
    var scriptMode: NetworkScriptRuleMode = .transform
    var scriptSource: String = """
function onRequest(ctx) {
  return ctx;
}
"""
    var scriptRunOnRequest = true
    var scriptRunOnResponse = true
}

struct NetworkRuleDraft: Identifiable, Sendable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String = "New Rule"
    var isEnabled = true
    var urlPattern: String = ".*"
    var method: NetworkRuleMatchMethod = .any
    var headerName: String = ""
    var headerValue: String = ""
    var priority: Int = 0
    var action: NetworkRuleActionDraft = NetworkRuleActionDraft()
    var lastError: String?

    var summary: String {
        "\(action.kind.title) · \(method.rawValue) · \(urlPattern)"
    }
}

struct NetworkRuleMatchSnapshot: Sendable, Equatable {
    var matches: Bool
    var message: String
}

struct NetworkBreakpointItem: Identifiable, Sendable, Hashable {
    var id: UUID
    var phase: NetworkBreakpointPhase
    var method: String
    var url: String
    var headers: [NetworkHeaderPair]
    var body: String
    var statusCode: Int?
    var createdAt: Date

    var title: String {
        "\(method.uppercased()) \(URL(string: url)?.host ?? url)"
    }
}

enum NetworkPluginStatus: String, Sendable, Hashable {
    case active
    case disabled
    case loading
    case error
}

struct NetworkPluginItem: Identifiable, Sendable, Hashable {
    var id: String
    var name: String
    var version: String
    var author: String
    var summary: String
    var bundlePath: String
    var isEnabled: Bool
    var status: NetworkPluginStatus
    var statusMessage: String
    var lastError: String?
    var configurationFields: [String: String]
}

struct NetworkReplayDraft: Identifiable, Sendable, Hashable {
    var id = UUID()
    var sourceFlowID: UUID
    var method: String
    var url: String
    var headers: [NetworkHeaderPair]
    var bodyText: String
    var contentType: String?
}

struct NetworkPayloadRenderResult: Sendable, Hashable {
    var title: String
    var text: String
    var isBinary: Bool
    var imageData: Data?
    var errorMessage: String?
}

struct NetworkProxyEndpoint: Sendable, Hashable {
    var host: String
    var port: UInt16

    var displayName: String { "\(host):\(port)" }
}

enum NetworkCaptureStatus: Sendable, Equatable {
    case stopped
    case starting
    case listening(NetworkProxyEndpoint)
    case failed(String)

    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

struct NetworkSystemProxyStatus: Sendable, Equatable {
    var isEnabled: Bool
    var managedServices: [String]
    var lastError: String?
    var upstreamProxySummary: String? = nil

    static let idle = NetworkSystemProxyStatus(isEnabled: false, managedServices: [], lastError: nil)
}

struct NetworkProxyComponentSnapshot: Sendable, Equatable {
    var isEnabled: Bool
    var server: String
    var port: UInt16?
    var authenticated: Bool
}

struct NetworkServiceProxySnapshot: Sendable, Equatable {
    var serviceName: String
    var web: NetworkProxyComponentSnapshot
    var secureWeb: NetworkProxyComponentSnapshot
    var socks: NetworkProxyComponentSnapshot
    var autoProxyURL: String?
    var autoProxyEnabled: Bool
    var bypassDomains: [String]
}

struct NetworkSystemProxySnapshot: Sendable, Equatable {
    var services: [NetworkServiceProxySnapshot]

    var serviceNames: [String] {
        services.map(\.serviceName)
    }

    func upstreamProxy(excluding endpoint: NetworkProxyEndpoint) -> NetworkUpstreamProxySettings? {
        for service in services {
            if service.autoProxyEnabled,
               let urlString = service.autoProxyURL,
               let url = URL(string: urlString)
            {
                return NetworkUpstreamProxySettings(
                    isEnabled: true,
                    proxies: [
                        NetworkUpstreamProxyServerSettings(
                            proto: .pac,
                            host: "",
                            port: 0,
                            pacURL: url
                        ),
                    ],
                    includeHosts: [],
                    excludeHosts: service.bypassDomains,
                    bypassLocalhost: true,
                    dnsOverSocks: true
                )
            }

            if let socks = service.socks.enabledServer(excluding: endpoint) {
                return NetworkUpstreamProxySettings(
                    isEnabled: true,
                    proxies: [
                        NetworkUpstreamProxyServerSettings(
                            proto: .socks5,
                            host: socks.server,
                            port: socks.port
                        ),
                    ],
                    includeHosts: [],
                    excludeHosts: service.bypassDomains,
                    bypassLocalhost: true,
                    dnsOverSocks: true
                )
            }

            if let web = service.web.enabledServer(excluding: endpoint) {
                return NetworkUpstreamProxySettings(
                    isEnabled: true,
                    proxies: [
                        NetworkUpstreamProxyServerSettings(
                            proto: .http,
                            host: web.server,
                            port: web.port
                        ),
                    ],
                    includeHosts: [],
                    excludeHosts: service.bypassDomains,
                    bypassLocalhost: true,
                    dnsOverSocks: true
                )
            }

            if let secureWeb = service.secureWeb.enabledServer(excluding: endpoint) {
                return NetworkUpstreamProxySettings(
                    isEnabled: true,
                    proxies: [
                        NetworkUpstreamProxyServerSettings(
                            proto: .http,
                            host: secureWeb.server,
                            port: secureWeb.port
                        ),
                    ],
                    includeHosts: [],
                    excludeHosts: service.bypassDomains,
                    bypassLocalhost: true,
                    dnsOverSocks: true
                )
            }
        }
        return nil
    }
}

struct NetworkUpstreamProxyConfirmation: Identifiable, Sendable, Equatable {
    let id = UUID()
    var endpoint: NetworkProxyEndpoint
    var autoTriggered: Bool
    var settings: NetworkUpstreamProxySettings

    var summary: String { settings.summary }
}

private extension NetworkProxyComponentSnapshot {
    func enabledServer(excluding endpoint: NetworkProxyEndpoint) -> (server: String, port: UInt16)? {
        guard isEnabled,
              let port,
              !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        let normalizedServer = server.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        let normalizedEndpoint = endpoint.host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        let sameHost = normalizedServer == normalizedEndpoint
            || (Self.isLocalhost(normalizedServer) && Self.isLocalhost(normalizedEndpoint))
        guard !(sameHost && port == endpoint.port) else { return nil }
        return (server, port)
    }

    static func isLocalhost(_ host: String) -> Bool {
        host == "localhost" || host == "::1" || host == "127.0.0.1" || host.hasPrefix("127.")
    }
}

enum NetworkHelperAction: String, Sendable, Equatable {
    case install
    case check
    case update
    case retry
    case reinstall
    case openSettings

    var title: String {
        switch self {
        case .install:
            "Install"
        case .check:
            "Check"
        case .update:
            "Update"
        case .retry:
            "Retry"
        case .reinstall:
            "Reinstall"
        case .openSettings:
            "Open Settings"
        }
    }
}

struct NetworkHelperState: Sendable, Equatable {
    var statusID: String
    var statusMessage: String
    var detailMessage: String?
    var action: NetworkHelperAction?
    var isReachable: Bool
    var canUsePrivilegedHelper: Bool
    var registrationStatus: String
    var installedVersion: String?
    var installedBuild: Int?
    var installedProtocolVersion: Int?
    var bundledVersion: String
    var bundledBuild: Int
    var expectedProtocolVersion: Int

    static let empty = NetworkHelperState(
        statusID: "unknown",
        statusMessage: "Checking helper...",
        detailMessage: nil,
        action: nil,
        isReachable: false,
        canUsePrivilegedHelper: false,
        registrationStatus: "Unknown",
        installedVersion: nil,
        installedBuild: nil,
        installedProtocolVersion: nil,
        bundledVersion: "Unknown",
        bundledBuild: 0,
        expectedProtocolVersion: 0
    )
}

struct NetworkCertificateState: Sendable, Equatable {
    var rootCAPath: String?
    var isTrusted: Bool
    var isMITMEnabled: Bool
    var sslHostAllowlist: [String]
    var statusMessage: String?

    static let empty = NetworkCertificateState(
        rootCAPath: nil,
        isTrusted: false,
        isMITMEnabled: false,
        sslHostAllowlist: [],
        statusMessage: nil
    )
}
