import AppKit
import Foundation
import Observation
import RockxyBackendEmbed

@MainActor
protocol NetworkHelperManaging: AnyObject {
    func refreshPassiveStatus() -> RockxyHelperSnapshot
    func refreshStatus() async -> RockxyHelperSnapshot
    func install() async throws -> RockxyHelperSnapshot
    func update() async throws -> RockxyHelperSnapshot
    func retryConnection() async -> RockxyHelperSnapshot
    func reinstall() async throws -> RockxyHelperSnapshot
    func openSystemSettingsLoginItems()
}

extension RockxyHelperController: NetworkHelperManaging {}

struct NetworkTrafficSnapshot: Sendable {
    struct Key: Sendable, Equatable {
        let flowsVersion: Int
        let filter: NetworkTrafficFilter
    }

    let key: Key
    let filteredFlows: [NetworkFlow]
    let httpTrafficFlows: [NetworkFlow]
    let apps: [NetworkTrafficFilterGroup]
    let domains: [NetworkTrafficFilterGroup]
    let methods: [NetworkTrafficFilterGroup]
    let pinnedCount: Int
    let savedCount: Int
    let statusCounts: [NetworkTrafficStatusFilter: Int]
    let protocolCounts: [NetworkFlowProtocol: Int]

    var visibleCount: Int { filteredFlows.count }

    init(key: Key, flows: [NetworkFlow]) {
        let normalizedQuery = key.filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredFlows = flows.filter { Self.matches($0, filter: key.filter, normalizedQuery: normalizedQuery) }
        self.key = key
        self.filteredFlows = filteredFlows
        self.httpTrafficFlows = filteredFlows.filter { $0.flowProtocol != .webSocket }
        self.apps = Self.groupedFilters(
            flows.map { $0.clientName.isEmpty ? "Proxy Client" : $0.clientName },
            symbol: AppIcon.App.generic
        )
        self.domains = Self.groupedFilters(flows.map(\.domainDisplay), symbol: AppIcon.Network.domain)
        self.methods = Self.groupedFilters(flows.map(\.methodDisplay), symbol: AppIcon.Navigation.forwardCircle)
        self.pinnedCount = flows.lazy.filter { $0.isPinned }.count
        self.savedCount = flows.lazy.filter { $0.isSaved }.count
        self.statusCounts = Dictionary(
            uniqueKeysWithValues: NetworkTrafficStatusFilter.allCases.map { status in
                (status, flows.lazy.filter(status.matches).count)
            }
        )
        self.protocolCounts = Dictionary(
            uniqueKeysWithValues: NetworkFlowProtocol.allCases.map { proto in
                (proto, flows.lazy.filter { $0.flowProtocol == proto }.count)
            }
        )
    }

    private static func matches(_ flow: NetworkFlow, filter: NetworkTrafficFilter, normalizedQuery: String) -> Bool {
        if filter.pinnedOnly, !flow.isPinned { return false }
        if filter.savedOnly, !flow.isSaved { return false }
        if !filter.protocols.isEmpty, !filter.protocols.contains(flow.flowProtocol) { return false }
        if !filter.apps.isEmpty, !filter.apps.contains(flow.clientName.isEmpty ? "Proxy Client" : flow.clientName) { return false }
        if !filter.domains.isEmpty, !filter.domains.contains(flow.domainDisplay) { return false }
        if !filter.methods.isEmpty, !filter.methods.contains(flow.methodDisplay) { return false }
        if !filter.statuses.isEmpty, !filter.statuses.contains(where: { $0.matches(flow) }) { return false }

        guard !normalizedQuery.isEmpty else { return true }
        return flow.request.url.localizedCaseInsensitiveContains(normalizedQuery)
            || flow.request.method.localizedCaseInsensitiveContains(normalizedQuery)
            || flow.clientName.localizedCaseInsensitiveContains(normalizedQuery)
            || flow.statusDisplay.localizedCaseInsensitiveContains(normalizedQuery)
            || flow.domainDisplay.localizedCaseInsensitiveContains(normalizedQuery)
            || (flow.matchedRuleName?.localizedCaseInsensitiveContains(normalizedQuery) ?? false)
    }

    private static func groupedFilters(_ values: [String], symbol: String) -> [NetworkTrafficFilterGroup] {
        let counts = Dictionary(grouping: values.filter { !$0.isEmpty }, by: { $0 })
            .mapValues(\.count)
        return counts
            .map { NetworkTrafficFilterGroup(id: $0.key, title: $0.key, symbol: symbol, count: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.count > $1.count
            }
    }
}

@MainActor
@Observable
final class NetworkDebuggerStore: @unchecked Sendable {
    var selectedSection: NetworkSection = .traffic
    var captureStatus: NetworkCaptureStatus = .stopped
    var systemProxyStatus: NetworkSystemProxyStatus = .idle
    var helperState: NetworkHelperState = .empty
    var certificateState: NetworkCertificateState = .empty
    var flows: [NetworkFlow] = [] {
        didSet { markFlowsChanged() }
    }
    var selectedFlowID: UUID?
    var selectedRequestTab: NetworkInspectorTab = .header
    var selectedResponseTab: NetworkInspectorTab = .body
    var selectedTrafficWorkspace: NetworkTrafficWorkspace = .httpTraffic
    var trafficSidebarLayer: NetworkTrafficSidebarLayer = .sections
    var trafficFilter = NetworkTrafficFilter()
    var webSocketFilter = NetworkWebSocketMessageFilter()
    var selectedWebSocketSessionID: UUID?
    var selectedWebSocketMessageID: UUID?
    var webSocketSendDraft = NetworkWebSocketSendDraft()
    var isSystemProxyWorking = false
    var isHelperWorking = false
    var isUpstreamProxyWorking = false
    var isCertificateWorking = false
    var isRulesWorking = false
    var isPluginsWorking = false
    var isReplayWorking = false
    var isAutomateWorking = false
    var upstreamProxyConfirmation: NetworkUpstreamProxyConfirmation?
    var upstreamProxyTestResult: NetworkUpstreamProxyTestResult?
    var upstreamRouteProbeResult: NetworkRouteProbeResult?
    var upstreamProxyStatusMessage: String?
    var upstreamEnvironments: [NetworkUpstreamEnvironment] = [.default]
    var selectedUpstreamEnvironmentID: UUID = NetworkUpstreamEnvironment.default.id
    var selectedUpstreamProfileID: UUID?
    var selectedUpstreamRouteRuleID: UUID?
    var rules: [NetworkRuleDraft] = []
    var selectedRuleID: UUID?
    var ruleMatchResult: NetworkRuleMatchSnapshot?
    var ruleStatusMessage: String?
    var plugins: [NetworkPluginItem] = []
    var pluginStatusMessage: String?
    var breakpoints: [NetworkBreakpointItem] = []
    var selectedBreakpointID: UUID?
    var replayDraft: NetworkReplayDraft?
    var replaySessions: [NetworkReplaySession] = []
    var selectedReplaySessionID: UUID?
    var importRequestText = ""
    var importRequestFormat: NetworkRequestImportFormat = .curl
    var automateDraft: NetworkAutomateDraft?
    var automateResults: [NetworkAutomateRunResult] = []
    var manualUpstreamProxyPassword = ""

    private let proxyBackend: any NetworkProxyBackend
    private let systemProxyService: any NetworkSystemProxyManaging
    private let helperController: any NetworkHelperManaging
    private let certificateService = NetworkCertificateService()
    private let requestOperationService = NetworkRequestOperationService()
    private let upstreamEnvironmentStore = NetworkUpstreamEnvironmentStore()
    private weak var preferences: Preferences?
    private var autoEnabledSystemProxyForCurrentCapture = false
    @ObservationIgnored private var flowsVersion = 0
    @ObservationIgnored private var cachedTrafficSnapshotKey: NetworkTrafficSnapshot.Key?
    @ObservationIgnored private var cachedTrafficSnapshot: NetworkTrafficSnapshot?

    init(
        preferences: Preferences? = nil,
        proxyBackend: any NetworkProxyBackend = RockxyNetworkProxyBackend(),
        systemProxyService: any NetworkSystemProxyManaging = NetworkSystemProxyService(),
        helperController: any NetworkHelperManaging = RockxyHelperController.shared
    ) {
        self.preferences = preferences
        self.proxyBackend = proxyBackend
        self.systemProxyService = systemProxyService
        self.helperController = helperController
    }

    var selectedFlow: NetworkFlow? {
        guard let selectedFlowID else { return flows.first }
        return flows.first { $0.id == selectedFlowID } ?? flows.first
    }

    var trafficSnapshot: NetworkTrafficSnapshot {
        let key = NetworkTrafficSnapshot.Key(flowsVersion: flowsVersion, filter: trafficFilter)
        if cachedTrafficSnapshotKey == key, let cachedTrafficSnapshot {
            return cachedTrafficSnapshot
        }
        let snapshot = NetworkTrafficSnapshot(key: key, flows: flows)
        cachedTrafficSnapshotKey = key
        cachedTrafficSnapshot = snapshot
        return snapshot
    }

    var filteredFlows: [NetworkFlow] {
        trafficSnapshot.filteredFlows
    }

    var httpTrafficFlows: [NetworkFlow] {
        trafficSnapshot.httpTrafficFlows
    }

    var webSocketSessions: [NetworkWebSocketSession] {
        flows
            .filter { $0.flowProtocol == .webSocket || !$0.webSocketFrames.isEmpty }
            .map(Self.webSocketSession(from:))
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    var selectedWebSocketSession: NetworkWebSocketSession? {
        guard let selectedWebSocketSessionID else { return webSocketSessions.first }
        return webSocketSessions.first { $0.id == selectedWebSocketSessionID } ?? webSocketSessions.first
    }

    var selectedWebSocketMessage: NetworkWebSocketMessage? {
        guard let session = selectedWebSocketSession else { return nil }
        guard let selectedWebSocketMessageID else { return session.messages.first }
        return session.messages.first { $0.id == selectedWebSocketMessageID } ?? session.messages.first
    }

    var filteredWebSocketMessages: [NetworkWebSocketMessage] {
        guard let session = selectedWebSocketSession else { return [] }
        return session.messages.filter { message in
            if webSocketFilter.direction != .all {
                if webSocketFilter.direction == .sent, message.direction != .sent { return false }
                if webSocketFilter.direction == .received, message.direction != .received { return false }
            }
            if webSocketFilter.opcode != .all,
               !message.opcode.localizedCaseInsensitiveContains(webSocketFilter.opcode.rawValue)
            {
                return false
            }
            let query = webSocketFilter.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return message.payloadText.localizedCaseInsensitiveContains(query)
                || message.opcode.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedReplaySession: NetworkReplaySession? {
        guard let selectedReplaySessionID else { return replaySessions.first }
        return replaySessions.first { $0.id == selectedReplaySessionID } ?? replaySessions.first
    }

    var selectedUpstreamEnvironment: NetworkUpstreamEnvironment {
        upstreamEnvironments.first { $0.id == selectedUpstreamEnvironmentID } ?? upstreamEnvironments.first ?? .default
    }

    var selectedUpstreamProfile: NetworkUpstreamProfile? {
        selectedUpstreamEnvironment.profiles.first { $0.id == selectedUpstreamProfileID }
            ?? selectedUpstreamEnvironment.profiles.first { $0.id == selectedUpstreamEnvironment.selectedProfileID }
            ?? selectedUpstreamEnvironment.profiles.first
    }

    var selectedUpstreamRouteRule: NetworkUpstreamRouteRule? {
        guard let selectedUpstreamRouteRuleID else {
            return selectedUpstreamEnvironment.routeRules.first
        }
        return selectedUpstreamEnvironment.routeRules.first { $0.id == selectedUpstreamRouteRuleID }
            ?? selectedUpstreamEnvironment.routeRules.first
    }

    var selectedRule: NetworkRuleDraft? {
        guard let selectedRuleID else { return rules.first }
        return rules.first { $0.id == selectedRuleID } ?? rules.first
    }

    var trafficApps: [NetworkTrafficFilterGroup] {
        trafficSnapshot.apps
    }

    var trafficDomains: [NetworkTrafficFilterGroup] {
        trafficSnapshot.domains
    }

    var trafficMethods: [NetworkTrafficFilterGroup] {
        trafficSnapshot.methods
    }

    var pinnedTrafficCount: Int {
        trafficSnapshot.pinnedCount
    }

    var savedTrafficCount: Int {
        trafficSnapshot.savedCount
    }

    func statusCount(for status: NetworkTrafficStatusFilter) -> Int {
        trafficSnapshot.statusCounts[status, default: 0]
    }

    func protocolCount(for proto: NetworkFlowProtocol) -> Int {
        trafficSnapshot.protocolCounts[proto, default: 0]
    }

    var visibleTrafficCount: Int {
        trafficSnapshot.visibleCount
    }

    var listeningEndpoint: NetworkProxyEndpoint? {
        if case .listening(let endpoint) = captureStatus { return endpoint }
        return nil
    }

    var autoEnableSystemProxyOnStart: Bool {
        get { preferences?.networkAutoEnableSystemProxyOnStart ?? false }
        set { preferences?.networkAutoEnableSystemProxyOnStart = newValue }
    }

    var searchText: String {
        get { trafficFilter.query }
        set { trafficFilter.query = newValue }
    }

    var selectedProtocol: NetworkFlowProtocol? {
        get { trafficFilter.protocols.count == 1 ? trafficFilter.protocols.first : nil }
        set {
            if let newValue {
                trafficFilter.protocols = [newValue]
            } else {
                trafficFilter.protocols = []
            }
        }
    }

    var upstreamProxyMode: NetworkUpstreamProxyMode {
        get { preferences?.networkUpstreamProxyMode ?? .automatic }
        set {
            let oldValue = upstreamProxyMode
            preferences?.networkUpstreamProxyMode = newValue
            guard oldValue != newValue else { return }
            upstreamProxyTestResult = nil
            upstreamRouteProbeResult = nil
            if newValue == .off {
                systemProxyStatus.upstreamProxySummary = nil
            }
            applyCurrentUpstreamProxy()
        }
    }

    var askBeforeChainingExistingSystemProxy: Bool {
        get { preferences?.networkAskBeforeChainingExistingSystemProxy ?? false }
        set { preferences?.networkAskBeforeChainingExistingSystemProxy = newValue }
    }

    var manualUpstreamProxyProtocol: NetworkUpstreamProxyProtocol {
        get { preferences?.networkManualUpstreamProxyProtocol ?? .http }
        set { preferences?.networkManualUpstreamProxyProtocol = newValue }
    }

    var manualUpstreamProxyHost: String {
        get { preferences?.networkManualUpstreamProxyHost ?? "" }
        set { preferences?.networkManualUpstreamProxyHost = newValue }
    }

    var manualUpstreamProxyPortText: String {
        get { "\(preferences?.networkManualUpstreamProxyPort ?? 6_152)" }
        set {
            let filtered = newValue.filter(\.isNumber)
            preferences?.networkManualUpstreamProxyPort = min(max(Int(filtered) ?? 0, 0), 65_535)
        }
    }

    var manualUpstreamProxyPACURL: String {
        get { preferences?.networkManualUpstreamProxyPACURL ?? "" }
        set { preferences?.networkManualUpstreamProxyPACURL = newValue }
    }

    var manualUpstreamProxyUsername: String {
        get { preferences?.networkManualUpstreamProxyUsername ?? "" }
        set { preferences?.networkManualUpstreamProxyUsername = newValue }
    }

    var manualUpstreamProxyIncludeHosts: String {
        get { preferences?.networkManualUpstreamProxyIncludeHosts ?? "" }
        set { preferences?.networkManualUpstreamProxyIncludeHosts = newValue }
    }

    var manualUpstreamProxyExcludeHosts: String {
        get { preferences?.networkManualUpstreamProxyExcludeHosts ?? "" }
        set { preferences?.networkManualUpstreamProxyExcludeHosts = newValue }
    }

    var manualUpstreamBypassLocalhost: Bool {
        get { preferences?.networkManualUpstreamBypassLocalhost ?? true }
        set { preferences?.networkManualUpstreamBypassLocalhost = newValue }
    }

    var manualUpstreamDNSOverSOCKS: Bool {
        get { preferences?.networkManualUpstreamDNSOverSOCKS ?? true }
        set { preferences?.networkManualUpstreamDNSOverSOCKS = newValue }
    }

    var statusMessage: String {
        switch captureStatus {
        case .stopped: "Proxy stopped"
        case .starting: "Starting proxy..."
        case .listening(let endpoint): "Listening on \(endpoint.displayName)"
        case .failed(let message): message
        }
    }

    func startCapture() {
        guard !captureStatus.isListening, captureStatus != .starting else { return }
        captureStatus = .starting
        autoEnabledSystemProxyForCurrentCapture = false
        Task { @MainActor in
            do {
                let endpoint = try await proxyBackend.start(preferredPorts: 9090...9099) { [weak self] event in
                    Task { @MainActor in
                        self?.apply(event)
                    }
                }
                captureStatus = .listening(endpoint)
                do {
                    try await applyResolvedUpstreamProxy(for: endpoint, statusPrefix: "Applied upstream")
                } catch {
                    upstreamProxyStatusMessage = error.localizedDescription
                }
                if preferences?.networkAutoEnableSystemProxyOnStart == true {
                    enableSystemProxy(autoTriggered: true)
                }
            } catch {
                captureStatus = .failed(error.localizedDescription)
            }
        }
    }

    func stopCapture() {
        let shouldRestoreAutoProxy = autoEnabledSystemProxyForCurrentCapture
        autoEnabledSystemProxyForCurrentCapture = false
        Task { @concurrent in
            await proxyBackend.stop()
        }
        captureStatus = .stopped
        if shouldRestoreAutoProxy {
            disableSystemProxy()
        }
    }

    func clearFlows() {
        flows.removeAll()
        selectedFlowID = nil
        selectedWebSocketSessionID = nil
        selectedWebSocketMessageID = nil
    }

    func resetTrafficFilters() {
        trafficFilter = NetworkTrafficFilter()
    }

    func togglePinnedFilter() {
        trafficFilter.pinnedOnly.toggle()
        if trafficFilter.pinnedOnly {
            trafficFilter.savedOnly = false
        }
    }

    func toggleSavedFilter() {
        trafficFilter.savedOnly.toggle()
        if trafficFilter.savedOnly {
            trafficFilter.pinnedOnly = false
        }
    }

    func toggleAppFilter(_ app: String) {
        toggle(app, in: &trafficFilter.apps)
    }

    func toggleDomainFilter(_ domain: String) {
        toggle(domain, in: &trafficFilter.domains)
    }

    func toggleMethodFilter(_ method: String) {
        toggle(method, in: &trafficFilter.methods)
    }

    func toggleStatusFilter(_ status: NetworkTrafficStatusFilter) {
        toggle(status, in: &trafficFilter.statuses)
    }

    func toggleProtocolFilter(_ proto: NetworkFlowProtocol) {
        toggle(proto, in: &trafficFilter.protocols)
    }

    func togglePinned(for id: UUID) {
        updateFlow(id: id) { $0.isPinned.toggle() }
    }

    func toggleSaved(for id: UUID) {
        updateFlow(id: id) { $0.isSaved.toggle() }
    }

    func setComment(for id: UUID, text: String) {
        updateFlow(id: id) { $0.comment = text }
    }

    func deleteFlow(_ id: UUID) {
        flows.removeAll { $0.id == id }
        if selectedFlowID == id {
            selectedFlowID = flows.first?.id
        }
    }

    func copyFlow(_ flow: NetworkFlow, format: NetworkRequestExportFormat) {
        requestOperationService.copyToPasteboard(requestOperationService.export(flow, format: format))
    }

    func exportVisibleFlows(format: NetworkRequestExportFormat) {
        requestOperationService.copyToPasteboard(requestOperationService.export(filteredFlows, format: format))
    }

    func duplicateFlowToReplay(_ flow: NetworkFlow) {
        prepareReplay(for: flow)
    }

    func prepareReplay(for flow: NetworkFlow) {
        let session = requestOperationService.replayDraft(from: flow)
        upsertReplaySession(session)
        replayDraft = session.draft
        selectedTrafficWorkspace = .replay
    }

    func createComposeSession() {
        let session = requestOperationService.composeSession()
        upsertReplaySession(session)
        replayDraft = session.draft
        selectedTrafficWorkspace = .replay
    }

    func importRequestToReplay() {
        do {
            let session = try requestOperationService.importRequest(importRequestText, format: importRequestFormat)
            upsertReplaySession(session)
            replayDraft = session.draft
            selectedTrafficWorkspace = .replay
        } catch {
            upstreamProxyStatusMessage = error.localizedDescription
        }
    }

    func cancelReplay() {
        replayDraft = nil
    }

    func performReplay() {
        guard let draft = replayDraft else { return }
        isReplayWorking = true
        Task { @MainActor in
            do {
                let flow = try await proxyBackend.replay(draft)
                insertCapturedFlow(flow)
                appendReplayResult(flow, draftID: draft.id, errorMessage: nil)
                replayDraft = nil
            } catch {
                upstreamProxyStatusMessage = error.localizedDescription
                appendReplayResult(nil, draftID: draft.id, errorMessage: error.localizedDescription)
            }
            isReplayWorking = false
        }
    }

    func sendSelectedReplaySession() {
        guard let session = selectedReplaySession else { return }
        replayDraft = session.draft
        performReplay()
    }

    func updateSelectedReplayDraft(_ transform: (inout NetworkReplayDraft) -> Void) {
        guard let session = selectedReplaySession,
              let index = replaySessions.firstIndex(where: { $0.id == session.id })
        else { return }
        transform(&replaySessions[index].draft)
        replayDraft = replaySessions[index].draft
    }

    func sendFlowToAutomate(_ flow: NetworkFlow) {
        automateDraft = NetworkAutomateDraft(baseDraft: requestOperationService.replayDraft(from: flow).draft)
        automateResults = []
        selectedTrafficWorkspace = .automate
    }

    func runAutomate() {
        guard let draft = automateDraft else { return }
        isAutomateWorking = true
        automateResults = []
        Task { @MainActor in
            let started = Date()
            let results = await proxyBackend.batchReplay(
                draft.expandedDrafts,
                concurrencyLimit: draft.concurrencyLimit
            )
            for result in results {
                if var flow = result.flow {
                    flow.operationSource = .automate
                    flow.isReplay = true
                    insertCapturedFlow(flow)
                    automateResults.append(NetworkAutomateRunResult(
                        requestIndex: result.index,
                        flowID: flow.id,
                        url: flow.request.url,
                        statusCode: flow.response.statusCode,
                        duration: flow.duration,
                        responseBytes: flow.responseBytes,
                        errorMessage: nil
                    ))
                } else {
                    let expanded = draft.expandedDrafts
                    automateResults.append(NetworkAutomateRunResult(
                        requestIndex: result.index,
                        flowID: nil,
                        url: expanded.indices.contains(result.index) ? expanded[result.index].url : draft.baseDraft.url,
                        statusCode: nil,
                        duration: Date().timeIntervalSince(started),
                        responseBytes: 0,
                        errorMessage: result.errorMessage
                    ))
                }
            }
            isAutomateWorking = false
        }
    }

    func refreshInterceptQueue() {
        refreshBreakpoints()
    }

    func updateSelectedIntercept(_ transform: (inout NetworkBreakpointItem) -> Void) {
        guard let selectedBreakpointID,
              let index = breakpoints.firstIndex(where: { $0.id == selectedBreakpointID })
        else { return }
        transform(&breakpoints[index])
        let item = breakpoints[index]
        Task { @MainActor in
            await proxyBackend.updateInterceptedFlow(item)
        }
    }

    func forwardSelectedIntercept() {
        guard let selectedBreakpointID else { return }
        Task { @MainActor in
            await proxyBackend.forwardInterceptedFlow(id: selectedBreakpointID)
            refreshBreakpoints()
        }
    }

    func dropSelectedIntercept() {
        guard let selectedBreakpointID else { return }
        Task { @MainActor in
            await proxyBackend.dropInterceptedFlow(id: selectedBreakpointID)
            refreshBreakpoints()
        }
    }

    func forwardAllIntercepts() {
        Task { @MainActor in
            await proxyBackend.resolveAllBreakpoints(decision: .execute)
            refreshBreakpoints()
        }
    }

    func dropAllIntercepts() {
        Task { @MainActor in
            await proxyBackend.resolveAllBreakpoints(decision: .abort)
            refreshBreakpoints()
        }
    }

    func selectWebSocketSession(_ session: NetworkWebSocketSession) {
        selectedWebSocketSessionID = session.id
        selectedWebSocketMessageID = session.messages.first?.id
        webSocketSendDraft.sessionID = session.id
    }

    func sendWebSocketMessage() {
        guard let session = selectedWebSocketSession else { return }
        webSocketSendDraft.sessionID = session.id
        Task { @MainActor in
            do {
                let message = try await proxyBackend.sendWebSocketMessage(webSocketSendDraft)
                appendWebSocketMessage(message, toFlowID: session.flowID)
                selectedWebSocketMessageID = message.id
                webSocketSendDraft.payloadText = ""
            } catch {
                upstreamProxyStatusMessage = error.localizedDescription
            }
        }
    }

    func refreshHelperStatus() {
        isHelperWorking = true
        Task { @MainActor in
            let snapshot = await helperController.refreshStatus()
            helperState = Self.helperState(from: snapshot)
            isHelperWorking = false
        }
    }

    func refreshPassiveHelperStatus() {
        isHelperWorking = true
        let snapshot = helperController.refreshPassiveStatus()
        helperState = Self.helperState(from: snapshot)
        isHelperWorking = false
    }

    func performHelperAction() {
        guard let action = helperState.action else { return }
        performHelperAction(action)
    }

    func performHelperAction(_ action: NetworkHelperAction) {
        isHelperWorking = true
        Task { @MainActor in
            do {
                let snapshot: RockxyHelperSnapshot
                switch action {
                case .install:
                    snapshot = try await helperController.install()
                case .check:
                    snapshot = await helperController.refreshStatus()
                case .update:
                    snapshot = try await helperController.update()
                case .retry:
                    snapshot = await helperController.retryConnection()
                case .reinstall:
                    snapshot = try await helperController.reinstall()
                case .openSettings:
                    helperController.openSystemSettingsLoginItems()
                    snapshot = helperController.refreshPassiveStatus()
                }
                helperState = Self.helperState(from: snapshot)
            } catch {
                helperState.detailMessage = error.localizedDescription
            }
            isHelperWorking = false
        }
    }

    func refreshRules() {
        isRulesWorking = true
        Task { @MainActor in
            rules = await proxyBackend.rules()
            selectedRuleID = selectedRuleID ?? rules.first?.id
            isRulesWorking = false
        }
    }

    func createRule(kind: NetworkRuleActionKind = .block) {
        var rule = NetworkRuleDraft()
        rule.name = "New \(kind.title) Rule"
        rule.action.kind = kind
        rules.append(rule)
        selectedRuleID = rule.id
    }

    func createRule(from flow: NetworkFlow, kind: NetworkRuleActionKind) {
        var rule = NetworkRuleDraft()
        rule.name = "\(kind.title) \(flow.domainDisplay)"
        rule.urlPattern = ".*\(NSRegularExpression.escapedPattern(for: flow.domainDisplay)).*"
        rule.method = NetworkRuleMatchMethod(rawValue: flow.methodDisplay) ?? .any
        rule.action.kind = kind
        rules.append(rule)
        selectedRuleID = rule.id
    }

    func updateSelectedRule(_ transform: (inout NetworkRuleDraft) -> Void) {
        guard let rule = selectedRule, let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        transform(&rules[index])
    }

    func saveSelectedRule() {
        guard let rule = selectedRule else { return }
        isRulesWorking = true
        Task { @MainActor in
            do {
                try await proxyBackend.saveRule(rule)
                rules = await proxyBackend.rules()
                selectedRuleID = rule.id
                ruleStatusMessage = "Saved \(rule.name)"
            } catch {
                ruleStatusMessage = error.localizedDescription
            }
            isRulesWorking = false
        }
    }

    func duplicateSelectedRule() {
        guard var rule = selectedRule else { return }
        rule.id = UUID()
        rule.name += " Copy"
        rule.isEnabled = false
        rules.append(rule)
        selectedRuleID = rule.id
    }

    func deleteSelectedRule() {
        guard let rule = selectedRule else { return }
        isRulesWorking = true
        Task { @MainActor in
            do {
                try await proxyBackend.deleteRule(id: rule.id)
                rules.removeAll { $0.id == rule.id }
                selectedRuleID = rules.first?.id
                ruleStatusMessage = "Deleted \(rule.name)"
            } catch {
                ruleStatusMessage = error.localizedDescription
            }
            isRulesWorking = false
        }
    }

    func setRuleEnabled(_ rule: NetworkRuleDraft, enabled: Bool) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index].isEnabled = enabled
        }
        Task { @MainActor in
            do {
                try await proxyBackend.setRuleEnabled(id: rule.id, enabled: enabled)
            } catch {
                ruleStatusMessage = error.localizedDescription
            }
        }
    }

    func moveSelectedRuleUp() {
        moveSelectedRule(offset: -1)
    }

    func moveSelectedRuleDown() {
        moveSelectedRule(offset: 1)
    }

    func testSelectedRuleAgainstSelectedFlow() {
        guard let rule = selectedRule else { return }
        let flow = selectedFlow
        let url = flow.flatMap { URL(string: $0.request.url) } ?? URL(string: "https://example.com/")!
        let method = flow?.request.method ?? "GET"
        let headers = flow?.request.headers ?? []
        Task { @MainActor in
            ruleMatchResult = await proxyBackend.testRule(rule, sampleURL: url, method: method, headers: headers)
        }
    }

    func exportRulesToPasteboard() {
        Task { @MainActor in
            do {
                let data = try await proxyBackend.exportRulesData()
                if let text = String(data: data, encoding: .utf8) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    ruleStatusMessage = "Rules copied to clipboard"
                }
            } catch {
                ruleStatusMessage = error.localizedDescription
            }
        }
    }

    func importRulesFromPasteboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              let data = text.data(using: .utf8)
        else {
            ruleStatusMessage = "Clipboard does not contain rule JSON."
            return
        }
        Task { @MainActor in
            do {
                try await proxyBackend.importRulesData(data)
                rules = await proxyBackend.rules()
                ruleStatusMessage = "Imported \(rules.count) rules"
            } catch {
                ruleStatusMessage = error.localizedDescription
            }
        }
    }

    func refreshPlugins() {
        isPluginsWorking = true
        Task { @MainActor in
            plugins = await proxyBackend.plugins()
            isPluginsWorking = false
        }
    }

    func installPlugin(at path: String) {
        isPluginsWorking = true
        Task { @MainActor in
            do {
                try await proxyBackend.installPlugin(at: path)
                plugins = await proxyBackend.plugins()
                pluginStatusMessage = "Installed plugin"
            } catch {
                pluginStatusMessage = error.localizedDescription
            }
            isPluginsWorking = false
        }
    }

    func setPluginEnabled(_ plugin: NetworkPluginItem, enabled: Bool) {
        Task { @MainActor in
            do {
                try await proxyBackend.setPluginEnabled(id: plugin.id, enabled: enabled)
                plugins = await proxyBackend.plugins()
            } catch {
                pluginStatusMessage = error.localizedDescription
            }
        }
    }

    func reloadPlugin(_ plugin: NetworkPluginItem) {
        Task { @MainActor in
            do {
                try await proxyBackend.reloadPlugin(id: plugin.id)
                plugins = await proxyBackend.plugins()
            } catch {
                pluginStatusMessage = error.localizedDescription
            }
        }
    }

    func deletePlugin(_ plugin: NetworkPluginItem) {
        Task { @MainActor in
            do {
                try await proxyBackend.deletePlugin(id: plugin.id)
                plugins = await proxyBackend.plugins()
            } catch {
                pluginStatusMessage = error.localizedDescription
            }
        }
    }

    func refreshBreakpoints() {
        Task { @MainActor in
            breakpoints = await proxyBackend.breakpoints()
            selectedBreakpointID = selectedBreakpointID ?? breakpoints.first?.id
        }
    }

    func updateBreakpoint(_ item: NetworkBreakpointItem) {
        if let index = breakpoints.firstIndex(where: { $0.id == item.id }) {
            breakpoints[index] = item
        }
        Task { @MainActor in
            await proxyBackend.updateBreakpoint(item)
        }
    }

    func resolveBreakpoint(_ item: NetworkBreakpointItem, decision: NetworkBreakpointDecision) {
        Task { @MainActor in
            await proxyBackend.resolveBreakpoint(id: item.id, decision: decision)
            breakpoints = await proxyBackend.breakpoints()
            selectedBreakpointID = breakpoints.first?.id
        }
    }

    func enableSystemProxy() {
        enableSystemProxy(autoTriggered: false)
    }

    private func enableSystemProxy(autoTriggered: Bool) {
        guard let endpoint = listeningEndpoint else {
            captureStatus = .failed("Start the local proxy before enabling system proxy.")
            return
        }
        guard !systemProxyStatus.isEnabled else { return }
        isSystemProxyWorking = true
        Task { @MainActor in
            do {
                let handoff = try await upstreamProxySettingsBeforeSystemProxy(
                    endpoint: endpoint,
                    autoTriggered: autoTriggered
                )
                if let confirmation = handoff.confirmation {
                    upstreamProxyConfirmation = confirmation
                    isSystemProxyWorking = false
                    return
                }
                try await applyUpstreamAndEnableSystemProxy(
                    endpoint: endpoint,
                    autoTriggered: autoTriggered,
                    settings: handoff.settings
                )
            } catch {
                systemProxyStatus.lastError = error.localizedDescription
                isSystemProxyWorking = false
            }
        }
    }

    func disableSystemProxy() {
        let services = systemProxyStatus.managedServices
        isSystemProxyWorking = true
        Task { @concurrent in
            do {
                let status = try await systemProxyService.disable(services: services)
                await MainActor.run {
                    systemProxyStatus = status
                    isSystemProxyWorking = false
                }
            } catch {
                await MainActor.run {
                    systemProxyStatus.lastError = error.localizedDescription
                    isSystemProxyWorking = false
                }
            }
        }
    }

    func confirmUpstreamProxyChaining() {
        guard let confirmation = upstreamProxyConfirmation else { return }
        upstreamProxyConfirmation = nil
        isSystemProxyWorking = true
        Task { @MainActor in
            do {
                try await applyUpstreamAndEnableSystemProxy(
                    endpoint: confirmation.endpoint,
                    autoTriggered: confirmation.autoTriggered,
                    settings: confirmation.settings
                )
            } catch {
                systemProxyStatus.lastError = error.localizedDescription
                isSystemProxyWorking = false
            }
        }
    }

    func cancelUpstreamProxyChaining() {
        upstreamProxyConfirmation = nil
        upstreamProxyStatusMessage = "Existing system proxy was left unchanged."
        isSystemProxyWorking = false
    }

    func testUpstreamProxy() {
        upstreamProxyTestResult = nil
        upstreamRouteProbeResult = nil
        upstreamProxyStatusMessage = nil
        isUpstreamProxyWorking = true
        Task { @MainActor in
            do {
                let endpoint = listeningEndpoint ?? NetworkProxyEndpoint(host: "127.0.0.1", port: 9_090)
                let settings = try await resolvedUpstreamProxySettings(endpoint: endpoint)
                let result = await proxyBackend.testUpstreamProxy(settings)
                upstreamProxyTestResult = result
                upstreamRouteProbeResult = Self.routeProbeResult(
                    from: result,
                    targetURL: "https://example.com/",
                    profileID: selectedUpstreamProfile?.id
                )
                upstreamProxyStatusMessage = result.errorMessage ?? result.routeSummary
            } catch {
                upstreamProxyTestResult = NetworkUpstreamProxyTestResult(
                    isReachable: false,
                    routeSummary: "Failed",
                    errorMessage: error.localizedDescription,
                    probeSteps: []
                )
                upstreamProxyStatusMessage = error.localizedDescription
            }
            isUpstreamProxyWorking = false
        }
    }

    func applyCurrentUpstreamProxy() {
        upstreamProxyTestResult = nil
        upstreamProxyStatusMessage = nil
        isUpstreamProxyWorking = true
        Task { @MainActor in
            do {
                let endpoint = listeningEndpoint ?? NetworkProxyEndpoint(host: "127.0.0.1", port: 9_090)
                try await applyResolvedUpstreamProxy(for: endpoint, statusPrefix: "Applied upstream")
            } catch {
                upstreamProxyStatusMessage = error.localizedDescription
            }
            isUpstreamProxyWorking = false
        }
    }

    func loadUpstreamEnvironments() {
        Task { @MainActor in
            let environments = await upstreamEnvironmentStore.load()
            upstreamEnvironments = environments
            selectedUpstreamEnvironmentID = environments.first(where: \.isDefault)?.id ?? environments.first?.id ?? NetworkUpstreamEnvironment.default.id
            selectedUpstreamProfileID = selectedUpstreamEnvironment.selectedProfileID
            selectedUpstreamRouteRuleID = selectedUpstreamEnvironment.routeRules.first?.id
        }
    }

    func saveUpstreamEnvironments() {
        Task { @MainActor in
            do {
                try await upstreamEnvironmentStore.save(upstreamEnvironments)
                upstreamProxyStatusMessage = "Saved upstream environments"
            } catch {
                upstreamProxyStatusMessage = error.localizedDescription
            }
        }
    }

    func createUpstreamEnvironment() {
        var environment = NetworkUpstreamEnvironment.default
        environment.id = UUID()
        environment.name = "Environment \(upstreamEnvironments.count + 1)"
        environment.isDefault = false
        upstreamEnvironments.append(environment)
        selectedUpstreamEnvironmentID = environment.id
        selectedUpstreamProfileID = environment.selectedProfileID
        saveUpstreamEnvironments()
    }

    func duplicateSelectedUpstreamEnvironment() {
        var copy = selectedUpstreamEnvironment
        copy.id = UUID()
        copy.name += " Copy"
        copy.isDefault = false
        upstreamEnvironments.append(copy)
        selectedUpstreamEnvironmentID = copy.id
        selectedUpstreamProfileID = copy.selectedProfileID
        saveUpstreamEnvironments()
    }

    func updateSelectedUpstreamEnvironmentName(_ name: String) {
        var environment = selectedUpstreamEnvironment
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        environment.name = trimmed.isEmpty ? "Environment" : trimmed
        replaceUpstreamEnvironment(environment)
    }

    func selectUpstreamProfile(_ id: UUID?) {
        selectedUpstreamProfileID = id
        guard let id else { return }
        var environment = selectedUpstreamEnvironment
        environment.selectedProfileID = id
        replaceUpstreamEnvironment(environment)
    }

    func createManualUpstreamProfileFromCurrentFields() {
        var environment = selectedUpstreamEnvironment
        var settings = manualUpstreamProxySettings()
        var profile = NetworkUpstreamProfile(
            name: settings.isEnabled ? settings.summary : "Manual Profile",
            settings: settings,
            credentialRef: nil,
            isAutoDetected: false
        )
        if settings.isEnabled,
           !manualUpstreamProxyPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            do {
                var credential = try upstreamEnvironmentStore.savePassword(manualUpstreamProxyPassword, for: profile.id)
                credential.username = manualUpstreamProxyUsername
                profile.credentialRef = credential
                for index in settings.proxies.indices {
                    settings.proxies[index].username = manualUpstreamProxyUsername.nilIfBlank
                    settings.proxies[index].password = nil
                }
                profile.settings = settings
                manualUpstreamProxyPassword = ""
            } catch {
                upstreamProxyStatusMessage = error.localizedDescription
                return
            }
        }
        environment.profiles.append(profile)
        environment.selectedProfileID = profile.id
        replaceUpstreamEnvironment(environment)
        selectedUpstreamProfileID = profile.id
        saveUpstreamEnvironments()
    }

    func saveDetectedSystemProxyAsProfile() {
        guard let endpoint = listeningEndpoint else {
            upstreamProxyStatusMessage = "Start capture before detecting a system proxy."
            return
        }
        Task { @MainActor in
            do {
                guard let settings = try await systemProxyService.detectedUpstreamProxy(excluding: endpoint) else {
                    upstreamProxyStatusMessage = "No existing system proxy detected."
                    return
                }
                var environment = selectedUpstreamEnvironment
                let profile = NetworkUpstreamProfile(
                    name: "Detected \(settings.summary)",
                    settings: settings,
                    isAutoDetected: true
                )
                environment.profiles.append(profile)
                environment.selectedProfileID = profile.id
                replaceUpstreamEnvironment(environment)
                selectedUpstreamProfileID = profile.id
                try await upstreamEnvironmentStore.save(upstreamEnvironments)
                upstreamProxyStatusMessage = "Saved detected route: \(settings.summary)"
            } catch {
                upstreamProxyStatusMessage = error.localizedDescription
            }
        }
    }

    func createUpstreamRouteRule() {
        var environment = selectedUpstreamEnvironment
        var rule = NetworkUpstreamRouteRule()
        rule.profileID = selectedUpstreamProfile?.id ?? environment.selectedProfileID
        environment.routeRules.append(rule)
        replaceUpstreamEnvironment(environment)
        selectedUpstreamRouteRuleID = rule.id
        saveUpstreamEnvironments()
    }

    func updateSelectedUpstreamRouteRule(_ transform: (inout NetworkUpstreamRouteRule) -> Void) {
        guard let selectedUpstreamRouteRule else { return }
        var environment = selectedUpstreamEnvironment
        guard let index = environment.routeRules.firstIndex(where: { $0.id == selectedUpstreamRouteRule.id }) else { return }
        transform(&environment.routeRules[index])
        replaceUpstreamEnvironment(environment)
    }

    func deleteSelectedUpstreamRouteRule() {
        guard let selectedUpstreamRouteRuleID else { return }
        var environment = selectedUpstreamEnvironment
        environment.routeRules.removeAll { $0.id == selectedUpstreamRouteRuleID }
        replaceUpstreamEnvironment(environment)
        self.selectedUpstreamRouteRuleID = environment.routeRules.first?.id
        saveUpstreamEnvironments()
    }

    func moveSelectedUpstreamRouteRule(offset: Int) {
        guard let selectedUpstreamRouteRuleID else { return }
        var environment = selectedUpstreamEnvironment
        guard let source = environment.routeRules.firstIndex(where: { $0.id == selectedUpstreamRouteRuleID }) else { return }
        let destination = max(0, min(environment.routeRules.count - 1, source + offset))
        guard source != destination else { return }
        let rule = environment.routeRules.remove(at: source)
        environment.routeRules.insert(rule, at: destination)
        replaceUpstreamEnvironment(environment)
        saveUpstreamEnvironments()
    }

    func generateRootCA() {
        isCertificateWorking = true
        let currentState = certificateState
        Task { @concurrent in
            do {
                let state = try await certificateService.generateRootCA(preserving: currentState)
                await MainActor.run {
                    certificateState = state
                    isCertificateWorking = false
                }
            } catch {
                await MainActor.run {
                    certificateState.statusMessage = error.localizedDescription
                    isCertificateWorking = false
                }
            }
        }
    }

    func trustRootCA() {
        guard certificateState.rootCAPath != nil else {
            certificateState.statusMessage = "Generate a Root CA first."
            return
        }
        isCertificateWorking = true
        let currentState = certificateState
        Task { @concurrent in
            do {
                let state = try await certificateService.trustRootCA(preserving: currentState)
                await MainActor.run {
                    certificateState = state
                    isCertificateWorking = false
                }
            } catch {
                await MainActor.run {
                    certificateState.statusMessage = error.localizedDescription
                    isCertificateWorking = false
                }
            }
        }
    }

    func addSSLHost(_ host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !certificateState.sslHostAllowlist.contains(trimmed) else { return }
        certificateState.sslHostAllowlist.append(trimmed)
    }

    func removeSSLHost(_ host: String) {
        certificateState.sslHostAllowlist.removeAll { $0 == host }
    }

    private func apply(_ event: NetworkProxyEvent) {
        switch event {
        case .started(let endpoint):
            captureStatus = .listening(endpoint)
            Log.network.info("Network proxy listening on \(endpoint.displayName, privacy: .public)")
        case .stopped:
            if captureStatus.isListening { captureStatus = .stopped }
        case .flowCreated(let flow):
            insertCapturedFlow(flow)
        case .flowUpdated(let flow):
            if let index = flows.firstIndex(where: { $0.id == flow.id }) {
                flows[index] = flow
            } else {
                insertCapturedFlow(flow)
            }
        case .flowCompleted(let flow):
            insertCapturedFlow(flow)
        case .webSocketMessageAppended(let flowID, let message):
            appendWebSocketMessage(message, toFlowID: flowID)
        case .interceptQueued(let item):
            if !breakpoints.contains(where: { $0.id == item.id }) {
                breakpoints.insert(item, at: 0)
            }
            selectedBreakpointID = selectedBreakpointID ?? item.id
            selectedTrafficWorkspace = .intercept
        case .interceptResolved(let id):
            breakpoints.removeAll { $0.id == id }
            if selectedBreakpointID == id {
                selectedBreakpointID = breakpoints.first?.id
            }
        case .replayCompleted(let flow):
            insertCapturedFlow(flow)
        case .upstreamRouteChanged(let summary):
            systemProxyStatus.upstreamProxySummary = summary
        case .failed(let message):
            captureStatus = .failed(message)
            Log.network.error("Network proxy failed: \(message, privacy: .public)")
        }
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func markFlowsChanged() {
        flowsVersion &+= 1
        cachedTrafficSnapshotKey = nil
        cachedTrafficSnapshot = nil
    }

    private func updateFlow(id: UUID, _ transform: (inout NetworkFlow) -> Void) {
        guard let index = flows.firstIndex(where: { $0.id == id }) else { return }
        transform(&flows[index])
    }

    private func insertCapturedFlow(_ flow: NetworkFlow) {
        if let index = flows.firstIndex(where: { $0.id == flow.id }) {
            flows[index] = flow
        } else {
            flows.insert(flow, at: 0)
        }
        if selectedFlowID == nil || flow.operationSource != .capture {
            selectedFlowID = flow.id
        }
        if flow.flowProtocol == .webSocket, selectedWebSocketSessionID == nil {
            selectedWebSocketSessionID = flow.id
        }
    }

    private func upsertReplaySession(_ session: NetworkReplaySession) {
        if let index = replaySessions.firstIndex(where: { $0.id == session.id }) {
            replaySessions[index] = session
        } else {
            replaySessions.insert(session, at: 0)
        }
        selectedReplaySessionID = session.id
    }

    private func appendReplayResult(_ flow: NetworkFlow?, draftID: UUID, errorMessage: String?) {
        guard let index = replaySessions.firstIndex(where: { $0.draft.id == draftID }) else { return }
        let now = Date()
        let result = NetworkReplayRunResult(
            flowID: flow?.id ?? UUID(),
            startedAt: flow?.createdAt ?? now,
            completedAt: flow?.completedAt ?? now,
            statusCode: flow?.response.statusCode,
            duration: flow?.duration ?? 0,
            responseBytes: flow?.responseBytes ?? 0,
            errorMessage: errorMessage
        )
        replaySessions[index].results.insert(result, at: 0)
        selectedReplaySessionID = replaySessions[index].id
    }

    private func appendWebSocketMessage(_ message: NetworkWebSocketMessage, toFlowID flowID: UUID) {
        guard let index = flows.firstIndex(where: { $0.id == flowID }) else { return }
        flows[index].webSocketFrames.append(NetworkWebSocketFrame(
            id: message.id,
            timestamp: message.timestamp,
            direction: message.direction,
            opcode: message.opcode,
            payloadText: message.payloadText,
            payloadBytes: message.payloadBytes,
            isFinal: true,
            isDropped: message.isDropped,
            isEdited: message.isEdited,
            isInjected: message.isInjected
        ))
    }

    private func moveSelectedRule(offset: Int) {
        guard let selectedRuleID,
              let source = rules.firstIndex(where: { $0.id == selectedRuleID })
        else { return }
        let destination = max(0, min(rules.count - 1, source + offset))
        guard source != destination else { return }
        let rule = rules.remove(at: source)
        rules.insert(rule, at: destination)
        for index in rules.indices {
            rules[index].priority = index
        }
        Task { @MainActor in
            let nextID = destination + 1 < rules.count ? rules[destination + 1].id : nil
            do {
                try await proxyBackend.moveRule(id: selectedRuleID, before: nextID)
            } catch {
                ruleStatusMessage = error.localizedDescription
            }
        }
    }

    private func upstreamProxySettingsBeforeSystemProxy(
        endpoint: NetworkProxyEndpoint,
        autoTriggered: Bool
    ) async throws -> (settings: NetworkUpstreamProxySettings, confirmation: NetworkUpstreamProxyConfirmation?) {
        let settings = try await resolvedUpstreamProxySettings(endpoint: endpoint)
        if upstreamProxyMode == .automatic,
           askBeforeChainingExistingSystemProxy,
           settings.isEnabled
        {
            return (
                settings,
                NetworkUpstreamProxyConfirmation(
                    endpoint: endpoint,
                    autoTriggered: autoTriggered,
                    settings: settings
                )
            )
        }
        return (settings, nil)
    }

    private func applyUpstreamAndEnableSystemProxy(
        endpoint: NetworkProxyEndpoint,
        autoTriggered: Bool,
        settings: NetworkUpstreamProxySettings
    ) async throws {
        await applyUpstreamProxySettings(settings, statusPrefix: "Chaining through")
        var status = try await systemProxyService.enable(endpoint: endpoint)
        status.upstreamProxySummary = settings.isEnabled ? settings.summary : nil
        systemProxyStatus = status
        if autoTriggered, status.isEnabled {
            autoEnabledSystemProxyForCurrentCapture = true
        }
        isSystemProxyWorking = false
    }

    private func applyResolvedUpstreamProxy(
        for endpoint: NetworkProxyEndpoint,
        statusPrefix: String
    ) async throws {
        let settings = try await resolvedUpstreamProxySettings(endpoint: endpoint)
        await applyUpstreamProxySettings(settings, statusPrefix: statusPrefix)
    }

    private func applyUpstreamProxySettings(
        _ settings: NetworkUpstreamProxySettings,
        statusPrefix: String
    ) async {
        await proxyBackend.updateUpstreamProxy(settings)
        systemProxyStatus.upstreamProxySummary = settings.isEnabled ? settings.summary : nil
        upstreamProxyStatusMessage = settings.isEnabled
            ? "\(statusPrefix) \(settings.summary)"
            : "Upstream disabled. Rockxy will connect directly."
    }

    private func resolvedUpstreamProxySettings(endpoint: NetworkProxyEndpoint) async throws -> NetworkUpstreamProxySettings {
        switch upstreamProxyMode {
        case .off:
            return .disabled
        case .manual:
            return try await Self.loadPACScriptIfNeeded(manualUpstreamProxySettings())
        case .automatic:
            guard let detected = try await systemProxyService.detectedUpstreamProxy(excluding: endpoint) else {
                return .disabled
            }
            return try await Self.loadPACScriptIfNeeded(detected)
        }
    }

    private func materializedSettings(for profile: NetworkUpstreamProfile) throws -> NetworkUpstreamProxySettings {
        var settings = profile.settings
        guard let credentialRef = profile.credentialRef,
              let password = try upstreamEnvironmentStore.password(for: credentialRef)
        else { return settings }
        for index in settings.proxies.indices {
            settings.proxies[index].username = credentialRef.username.nilIfBlank ?? settings.proxies[index].username
            settings.proxies[index].password = password
        }
        return settings
    }

    private func manualUpstreamProxySettings() -> NetworkUpstreamProxySettings {
        let proto = manualUpstreamProxyProtocol
        let includeHosts = Self.hostPatternList(from: manualUpstreamProxyIncludeHosts)
        let excludeHosts = Self.hostPatternList(from: manualUpstreamProxyExcludeHosts)
        let portValue = preferences?.networkManualUpstreamProxyPort ?? 0
        let port = UInt16(exactly: portValue)
        let trimmedHost = manualUpstreamProxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPACURL = manualUpstreamProxyPACURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if proto == .pac {
            guard let url = URL(string: trimmedPACURL), !trimmedPACURL.isEmpty else {
                return .disabled
            }
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
                includeHosts: includeHosts,
                excludeHosts: excludeHosts,
                bypassLocalhost: manualUpstreamBypassLocalhost,
                dnsOverSocks: manualUpstreamDNSOverSOCKS
            )
        }

        guard !trimmedHost.isEmpty, let port else {
            return .disabled
        }

        return NetworkUpstreamProxySettings(
            isEnabled: true,
            proxies: [
                NetworkUpstreamProxyServerSettings(
                    proto: proto,
                    host: trimmedHost,
                    port: port,
                    username: manualUpstreamProxyUsername.nilIfBlank,
                    password: manualUpstreamProxyPassword.nilIfBlank
                ),
            ],
            includeHosts: includeHosts,
            excludeHosts: excludeHosts,
            bypassLocalhost: manualUpstreamBypassLocalhost,
            dnsOverSocks: manualUpstreamDNSOverSOCKS
        )
    }

    private static func hostPatternList(from text: String) -> [String] {
        text
            .split { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func loadPACScriptIfNeeded(_ settings: NetworkUpstreamProxySettings) async throws -> NetworkUpstreamProxySettings {
        var settings = settings
        for index in settings.proxies.indices where settings.proxies[index].proto == .pac {
            guard settings.proxies[index].pacScript?.isEmpty != false,
                  let url = settings.proxies[index].pacURL
            else { continue }
            settings.proxies[index].pacScript = try await Task.detached(priority: .utility) {
                if url.isFileURL {
                    return try String(contentsOf: url, encoding: .utf8)
                }
                let data = try Data(contentsOf: url)
                return String(data: data, encoding: .utf8) ?? ""
            }.value
        }
        return settings
    }

    private func replaceUpstreamEnvironment(_ environment: NetworkUpstreamEnvironment) {
        if let index = upstreamEnvironments.firstIndex(where: { $0.id == environment.id }) {
            upstreamEnvironments[index] = environment
        } else {
            upstreamEnvironments.append(environment)
        }
    }

    private static func routeProbeResult(
        from result: NetworkUpstreamProxyTestResult,
        targetURL: String,
        profileID: UUID?
    ) -> NetworkRouteProbeResult {
        let fallbackSteps: [NetworkRouteProbeStep] = [
            NetworkRouteProbeStep(
                title: "Route resolution",
                status: result.errorMessage == nil ? .success : .failure,
                detail: result.routeSummary,
                latencyMs: nil
            ),
            NetworkRouteProbeStep(
                title: "Connectivity",
                status: result.isReachable ? .success : .failure,
                detail: result.errorMessage ?? "Route can be used by the proxy engine.",
                latencyMs: nil
            ),
        ]
        return NetworkRouteProbeResult(
            profileID: profileID,
            startedAt: .now,
            targetURL: targetURL,
            selectedRoute: result.routeSummary,
            isReachable: result.isReachable,
            steps: result.probeSteps.isEmpty ? fallbackSteps : result.probeSteps,
            errorMessage: result.errorMessage
        )
    }

    private static func webSocketSession(from flow: NetworkFlow) -> NetworkWebSocketSession {
        let sessionID = flow.id
        return NetworkWebSocketSession(
            id: sessionID,
            flowID: flow.id,
            number: flow.number,
            url: flow.request.url,
            domain: flow.domainDisplay,
            clientName: flow.clientName,
            startedAt: flow.createdAt,
            completedAt: flow.completedAt,
            state: flow.state,
            requestHeaders: flow.request.headers,
            messages: flow.webSocketFrames.map { frame in
                NetworkWebSocketMessage(
                    id: frame.id,
                    sessionID: sessionID,
                    flowID: flow.id,
                    timestamp: frame.timestamp,
                    direction: frame.direction,
                    opcode: frame.opcode,
                    payloadText: frame.payloadText,
                    payloadBytes: frame.payloadBytes,
                    isFinal: frame.isFinal,
                    isDropped: frame.isDropped,
                    isEdited: frame.isEdited,
                    isInjected: frame.isInjected
                )
            }
        )
    }

    static func helperState(from snapshot: RockxyHelperSnapshot) -> NetworkHelperState {
        NetworkHelperState(
            statusID: snapshot.status.rawValue,
            statusMessage: snapshot.statusMessage,
            detailMessage: snapshot.lastErrorMessage,
            action: snapshot.action.map(NetworkHelperAction.init),
            isReachable: snapshot.isReachable,
            canUsePrivilegedHelper: snapshot.canUsePrivilegedHelper,
            registrationStatus: snapshot.registrationStatus,
            installedVersion: snapshot.installedVersion,
            installedBuild: snapshot.installedBuild,
            installedProtocolVersion: snapshot.installedProtocolVersion,
            bundledVersion: snapshot.bundledVersion,
            bundledBuild: snapshot.bundledBuild,
            expectedProtocolVersion: snapshot.expectedProtocolVersion
        )
    }
}

private extension NetworkHelperAction {
    init(_ action: RockxyHelperAction) {
        switch action {
        case .install:
            self = .install
        case .check:
            self = .check
        case .update:
            self = .update
        case .retry:
            self = .retry
        case .reinstall:
            self = .reinstall
        case .openSettings:
            self = .openSettings
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
