import Foundation
import Observation

@MainActor
@Observable
final class UsageLimitStore {
    private(set) var reports: [ProviderKind: UsageLimitReport] = [:]
    private(set) var forecasts: [String: UsageLimitForecast] = [:]
    private(set) var loadingProviders: Set<ProviderKind> = []
    private(set) var actionMessages: [ProviderKind: String] = [:]
    private(set) var claudeDesktopPermissionIssue: ClaudeDesktopUsagePermissionIssue?
    private(set) var claudeDesktopAccessibilityRecheckPending = false
    private(set) var claudeDesktopScreenRecordingRecheckPending = false

    @ObservationIgnored private let registry: ProviderRegistry
    @ObservationIgnored private let historyStore: UsageLimitHistoryStore
    @ObservationIgnored private let forecastService: UsageLimitForecastService
    @ObservationIgnored private let claudeBridgeInstaller: any ClaudeUsageLimitBridgeInstalling
    @ObservationIgnored private let claudeDesktopCaptureService: any ClaudeDesktopUsageCapturing
    @ObservationIgnored private let claudeDesktopAccessibilityPermissionChecker: any ClaudeDesktopAccessibilityPermissionChecking
    @ObservationIgnored private let claudeDesktopScreenRecordingPermissionChecker: any ClaudeDesktopScreenRecordingPermissionChecking

    init(
        registry: ProviderRegistry,
        historyStore: UsageLimitHistoryStore = UsageLimitHistoryStore(),
        forecastService: UsageLimitForecastService = UsageLimitForecastService(),
        claudeBridgeInstaller: any ClaudeUsageLimitBridgeInstalling = ClaudeUsageLimitBridgeInstaller(),
        claudeDesktopCaptureService: any ClaudeDesktopUsageCapturing = ClaudeDesktopUsageCaptureService(),
        claudeDesktopAccessibilityPermissionChecker: any ClaudeDesktopAccessibilityPermissionChecking = SystemClaudeDesktopAccessibilityPermissionChecker(),
        claudeDesktopScreenRecordingPermissionChecker: any ClaudeDesktopScreenRecordingPermissionChecking = SystemClaudeDesktopScreenRecordingPermissionChecker()
    ) {
        self.registry = registry
        self.historyStore = historyStore
        self.forecastService = forecastService
        self.claudeBridgeInstaller = claudeBridgeInstaller
        self.claudeDesktopCaptureService = claudeDesktopCaptureService
        self.claudeDesktopAccessibilityPermissionChecker = claudeDesktopAccessibilityPermissionChecker
        self.claudeDesktopScreenRecordingPermissionChecker = claudeDesktopScreenRecordingPermissionChecker
    }

    func report(for provider: ProviderKind) -> UsageLimitReport? {
        reports[provider]
    }

    func forecast(for provider: ProviderKind, windowID: String) -> UsageLimitForecast? {
        forecasts["\(provider.rawValue)|\(windowID)"]
    }

    func forecasts(for provider: ProviderKind) -> [UsageLimitForecast] {
        forecasts.values
            .filter { $0.provider == provider }
            .sorted { $0.id < $1.id }
    }

    func isLoading(_ provider: ProviderKind) -> Bool {
        loadingProviders.contains(provider)
    }

    func actionMessage(for provider: ProviderKind) -> String? {
        actionMessages[provider]
    }

    func refresh(provider: ProviderKind, force: Bool = false, now: Date = .now) async {
        guard provider.supportsUsageLimits else { return }
        guard force || reports[provider] == nil else { return }
        guard !loadingProviders.contains(provider) else { return }
        loadingProviders.insert(provider)
        defer { loadingProviders.remove(provider) }

        guard let source = registry.provider(for: provider) else {
            reports[provider] = .unsupported(provider: provider)
            return
        }
        let report = await source.usageLimitReport(now: now)
        reports[provider] = report
        if report.status == .fresh {
            let historySince = now.addingTimeInterval(-7 * 86_400)
            let providerHistory = await source.usageLimitHistory(since: historySince, now: now)
            recordUsageLimitHistory(report: report, providerHistory: providerHistory, now: now)
        }
    }

    func refreshSupportedProviders(force: Bool = false, now: Date = .now) async {
        for provider in ProviderKind.allCases where provider.supportsUsageLimits {
            await refresh(provider: provider, force: force, now: now)
        }
    }

    func refreshForecasts(sessions: [Session], now: Date = .now) async {
        let reports = Array(reports.values)
        let history = historyStore.load()
        let forecastService = self.forecastService
        let updated = await Task.detached(priority: .userInitiated) {
            forecastService.forecasts(
                sessions: sessions,
                reports: reports,
                history: history,
                now: now
            )
        }.value
        forecasts = Dictionary(uniqueKeysWithValues: updated.map { ($0.id, $0) })
    }

    func installClaudeBridge() {
        do {
            let configuration = try claudeBridgeInstaller.install()
            actionMessages[.claude] = "Bridge installed. Paste the settings snippet into \(configuration.settingsURL.path)."
        } catch {
            actionMessages[.claude] = "Could not install bridge: \(error.localizedDescription)"
        }
    }

    func captureClaudeDesktopUsage(trigger: ClaudeDesktopUsageCaptureTrigger) async {
        guard !loadingProviders.contains(.claude) else { return }
        loadingProviders.insert(.claude)
        let outcome = await claudeDesktopCaptureService.capture(trigger: trigger)
        loadingProviders.remove(.claude)

        switch outcome {
        case .captured:
            clearClaudeDesktopPermissionState()
            if trigger.shouldShowUserMessage {
                actionMessages[.claude] = "Claude Desktop usage captured."
            }
            await refresh(provider: .claude, force: true)
        case .skipped:
            if trigger.shouldShowUserMessage {
                actionMessages[.claude] = "Open Claude Desktop, then try reading usage again."
            }
        case .failed(let error):
            claudeDesktopPermissionIssue = error.permissionIssue
            if trigger.shouldShowUserMessage, let permissionIssue = error.permissionIssue {
                beginClaudeDesktopPermissionRecheck(for: permissionIssue)
            }
            if trigger.shouldShowUserMessage {
                actionMessages[.claude] = error.localizedDescription
            }
        }
    }

    func beginClaudeDesktopAccessibilityPermissionRecheck() {
        claudeDesktopAccessibilityRecheckPending = true
    }

    func beginClaudeDesktopScreenRecordingPermissionRecheck() {
        claudeDesktopScreenRecordingRecheckPending = true
    }

    func runPendingClaudeDesktopPermissionRechecks(
        maxAttempts: Int = 8,
        intervalNanoseconds: UInt64 = 500_000_000
    ) async {
        await runPendingClaudeDesktopAccessibilityPermissionRecheck(
            maxAttempts: maxAttempts,
            intervalNanoseconds: intervalNanoseconds
        )
        await runPendingClaudeDesktopScreenRecordingPermissionRecheck(
            maxAttempts: maxAttempts,
            intervalNanoseconds: intervalNanoseconds
        )
    }

    func runPendingClaudeDesktopAccessibilityPermissionRecheck(
        maxAttempts: Int = 8,
        intervalNanoseconds: UInt64 = 500_000_000
    ) async {
        guard claudeDesktopAccessibilityRecheckPending else { return }

        for attempt in 0..<max(1, maxAttempts) {
            guard !Task.isCancelled else { return }
            if claudeDesktopAccessibilityPermissionChecker.isTrusted(prompt: false) {
                claudeDesktopAccessibilityRecheckPending = false
                clearClaudeDesktopPermissionState()
                await captureClaudeDesktopUsage(trigger: .permissionRecheck)
                return
            }

            guard attempt < maxAttempts - 1 else { break }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }

        ClaudeDesktopAccessibilityPermissionDiagnostics.logNotTrusted(context: "post-settings recheck")
    }

    func runPendingClaudeDesktopScreenRecordingPermissionRecheck(
        maxAttempts: Int = 8,
        intervalNanoseconds: UInt64 = 500_000_000
    ) async {
        guard claudeDesktopScreenRecordingRecheckPending else { return }

        for attempt in 0..<max(1, maxAttempts) {
            guard !Task.isCancelled else { return }
            if claudeDesktopScreenRecordingPermissionChecker.hasAccess(prompt: false) {
                claudeDesktopScreenRecordingRecheckPending = false
                clearClaudeDesktopPermissionState()
                await captureClaudeDesktopUsage(trigger: .permissionRecheck)
                return
            }

            guard attempt < maxAttempts - 1 else { break }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }

    func claudeSettingsSnippet() -> String {
        claudeBridgeInstaller.settingsSnippet()
    }

    func claudeSettingsURL() -> URL {
        claudeBridgeInstaller.settingsURL
    }

    func recordActionMessage(_ message: String, for provider: ProviderKind) {
        actionMessages[provider] = message
    }

    private func clearClaudeDesktopPermissionState() {
        claudeDesktopPermissionIssue = nil
        claudeDesktopAccessibilityRecheckPending = false
        claudeDesktopScreenRecordingRecheckPending = false
        if isClaudeDesktopPermissionActionMessage(actionMessages[.claude]) {
            actionMessages[.claude] = nil
        }
    }

    private func beginClaudeDesktopPermissionRecheck(for issue: ClaudeDesktopUsagePermissionIssue) {
        switch issue {
        case .accessibility:
            beginClaudeDesktopAccessibilityPermissionRecheck()
        case .screenRecording:
            beginClaudeDesktopScreenRecordingPermissionRecheck()
        }
    }

    private func recordUsageLimitHistory(
        report: UsageLimitReport,
        providerHistory: [UsageLimitHistoryEntry],
        now: Date
    ) {
        do {
            if !providerHistory.isEmpty {
                _ = try historyStore.append(entries: providerHistory, now: now)
            }
            _ = try historyStore.append(report: report, now: now)
        } catch {
            Log.app.error("Could not persist usage-limit history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func isClaudeDesktopPermissionActionMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        let permissionMessages = [
            ClaudeDesktopUsageCaptureError.accessibilityPermissionRequired.localizedDescription,
            ClaudeDesktopUsageCaptureError.screenRecordingPermissionRequired.localizedDescription,
        ]
        return permissionMessages.contains(message)
    }
}
