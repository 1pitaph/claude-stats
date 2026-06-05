import Foundation
import Observation

@MainActor
@Observable
final class ClaudeStatusViewModel {
    static let refreshInterval: TimeInterval = 5 * 60

    private(set) var snapshot: ClaudeStatusSnapshot?
    private(set) var isLoading = false
    private(set) var isStale = false
    private(set) var lastError: String?
    private(set) var uptimeSnapshot: ClaudeStatusUptimeSnapshot?
    private(set) var isUptimeStale = false
    private(set) var uptimeLastError: String?
    private(set) var notificationAuthorization: ClaudeStatusNotificationAuthorizationStatus = .notDetermined
    private(set) var isRequestingNotificationAuthorization = false
    @ObservationIgnored var onRefresh: (() -> Void)?

    var availableComponents: [ClaudeStatusComponent] {
        let components = snapshot?.components ?? []
        return components.isEmpty ? ClaudeStatusComponentCatalog.fallbackComponents : components
    }

    var visibleComponents: [ClaudeStatusComponent] {
        guard let snapshot else { return [] }
        return visibleComponents(from: snapshot.components)
    }

    var visibleUptimeRows: [ClaudeStatusUptimeRow] {
        visibleComponents.map { component in
            ClaudeStatusUptimeRow(
                component: component,
                history: uptimeSnapshot?.history(for: component)
            )
        }
    }

    var notificationPermissionDenied: Bool {
        notificationAuthorization == .denied
    }

    var statusPageURL: URL {
        URL(string: "https://status.claude.com/")!
    }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let client: any ClaudeStatusFetching
    @ObservationIgnored private let cache: any ClaudeStatusCaching
    @ObservationIgnored private let uptimeClient: any ClaudeStatusUptimeFetching
    @ObservationIgnored private let uptimeCache: any ClaudeStatusUptimeCaching
    @ObservationIgnored private let notifications: any ClaudeStatusNotificationServicing
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(
        preferences: Preferences,
        client: any ClaudeStatusFetching = ClaudeStatusClient(),
        cache: any ClaudeStatusCaching = ClaudeStatusCache(),
        uptimeClient: any ClaudeStatusUptimeFetching = ClaudeStatusUptimeClient(),
        uptimeCache: any ClaudeStatusUptimeCaching = ClaudeStatusUptimeCache(),
        notifications: any ClaudeStatusNotificationServicing = ClaudeStatusNotificationService()
    ) {
        self.preferences = preferences
        self.client = client
        self.cache = cache
        self.uptimeClient = uptimeClient
        self.uptimeCache = uptimeCache
        self.notifications = notifications
    }

    deinit {
        refreshTask?.cancel()
    }

    func start() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await refreshNotificationAuthorizationStatus()
            loadCachedSnapshot()
            loadCachedUptimeSnapshot()
            while !Task.isCancelled {
                if shouldRefresh {
                    await refreshIfNeeded()
                }
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshNotificationAuthorizationStatus() async {
        notificationAuthorization = await notifications.authorizationStatus()
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        if !enabled {
            preferences.claudeStatusNotificationsEnabled = false
            preferences.claudeStatusLastNotificationFingerprint = ""
            return
        }

        isRequestingNotificationAuthorization = true
        let status = await notifications.requestAuthorization()
        notificationAuthorization = status
        isRequestingNotificationAuthorization = false
        preferences.claudeStatusNotificationsEnabled = status.canSendNotifications
        if status.canSendNotifications {
            await refresh(force: true)
        }
    }

    func refreshIfNeeded(now: Date = .now) async {
        var summaryNeedsRefresh = true
        if let cached = cache.read(ttl: ClaudeStatusCache.defaultTTL, now: now), !cached.isStale {
            snapshot = cached.snapshot
            isStale = false
            lastError = nil
            summaryNeedsRefresh = false
        }

        var uptimeNeedsRefresh = true
        if let cached = uptimeCache.read(ttl: ClaudeStatusUptimeCache.defaultTTL, now: now), !cached.isStale {
            uptimeSnapshot = cached.snapshot
            isUptimeStale = false
            uptimeLastError = nil
            uptimeNeedsRefresh = false
        }

        if summaryNeedsRefresh {
            await refreshSummary(force: false, now: now)
        }
        if uptimeNeedsRefresh {
            await refreshUptime(force: false, now: now)
        }
    }

    func refresh(force: Bool = true, now: Date = .now) async {
        await refreshSummary(force: force, now: now)
        await refreshUptime(force: force, now: now)
    }

    private func refreshSummary(force: Bool = true, now: Date = .now) async {
        if !force,
           let cached = cache.read(ttl: ClaudeStatusCache.defaultTTL, now: now),
           !cached.isStale {
            snapshot = cached.snapshot
            isStale = false
            lastError = nil
            return
        }

        if snapshot == nil { isLoading = true }
        defer { isLoading = false }

        do {
            let fresh = try await client.fetchSummary(now: now)
            snapshot = fresh
            isStale = false
            lastError = nil
            do {
                try cache.write(fresh)
            } catch {
                Log.app.error("Claude Status cache write failed: \(error.localizedDescription, privacy: .public)")
            }
            await handleNotifications(for: fresh)
            onRefresh?()
        } catch {
            lastError = userFacingMessage(error)
            if let cached = cache.read(ttl: ClaudeStatusCache.defaultTTL, now: now) {
                snapshot = cached.snapshot
                isStale = true
            }
        }
    }

    private func refreshUptime(force: Bool = true, now: Date = .now) async {
        if !force,
           let cached = uptimeCache.read(ttl: ClaudeStatusUptimeCache.defaultTTL, now: now),
           !cached.isStale {
            uptimeSnapshot = cached.snapshot
            isUptimeStale = false
            uptimeLastError = nil
            return
        }

        do {
            let fresh = try await uptimeClient.fetchUptimeHistories(now: now)
            uptimeSnapshot = fresh
            isUptimeStale = false
            uptimeLastError = nil
            do {
                try uptimeCache.write(fresh)
            } catch {
                Log.app.error("Claude Status uptime cache write failed: \(error.localizedDescription, privacy: .public)")
            }
            onRefresh?()
        } catch {
            uptimeLastError = userFacingMessage(error)
            if let cached = uptimeCache.read(ttl: ClaudeStatusUptimeCache.defaultTTL, now: now) {
                uptimeSnapshot = cached.snapshot
                isUptimeStale = true
            }
        }
    }

    func isComponentVisible(_ component: ClaudeStatusComponent) -> Bool {
        visibleComponentIDs(for: availableComponents).contains(component.id)
    }

    func canHideComponent(_ component: ClaudeStatusComponent) -> Bool {
        let visibleIDs = visibleComponentIDs(for: availableComponents)
        return !(visibleIDs.count == 1 && visibleIDs.contains(component.id))
    }

    func setComponentVisibility(_ component: ClaudeStatusComponent, isVisible: Bool) {
        var ids = preferences.claudeStatusVisibleComponentIDs
        if isVisible {
            ids.insert(component.id)
        } else {
            ids.subtract(ClaudeStatusComponentCatalog.equivalentIDs(for: component))
        }
        if ids.isEmpty {
            ids.insert(component.id)
        }
        preferences.claudeStatusVisibleComponentIDs = ids

        if snapshot?.components.first(where: { $0.id == component.id }) != nil {
            Task {
                await handleNotificationsForCurrentSnapshot()
                await refreshUptimeIfNeeded()
            }
        }
    }

    func visibleComponents(from components: [ClaudeStatusComponent]) -> [ClaudeStatusComponent] {
        ClaudeStatusComponentCatalog.visibleComponents(
            from: components,
            storedIDs: preferences.claudeStatusVisibleComponentIDs
        )
    }

    private var shouldRefresh: Bool {
        preferences.selectedProvider == .claude || preferences.claudeStatusNotificationsEnabled
    }

    private func loadCachedSnapshot(now: Date = .now) {
        guard let cached = cache.read(ttl: ClaudeStatusCache.defaultTTL, now: now) else { return }
        snapshot = cached.snapshot
        isStale = cached.isStale
    }

    private func loadCachedUptimeSnapshot(now: Date = .now) {
        guard let cached = uptimeCache.read(ttl: ClaudeStatusUptimeCache.defaultTTL, now: now) else { return }
        uptimeSnapshot = cached.snapshot
        isUptimeStale = cached.isStale
    }

    private func refreshUptimeIfNeeded(now: Date = .now) async {
        guard shouldRefresh else { return }
        guard uptimeSnapshot == nil || visibleUptimeRows.contains(where: { $0.history == nil }) else { return }
        await refreshUptime(force: false, now: now)
    }

    private func visibleComponentIDs(for components: [ClaudeStatusComponent]) -> Set<String> {
        ClaudeStatusComponentCatalog.visibleComponentIDs(
            from: preferences.claudeStatusVisibleComponentIDs,
            components: components
        )
    }

    private func handleNotificationsForCurrentSnapshot() async {
        guard let snapshot else { return }
        await handleNotifications(for: snapshot)
    }

    private func handleNotifications(for snapshot: ClaudeStatusSnapshot) async {
        let problemComponents = visibleComponents(from: snapshot.components)
            .filter { !$0.isOperational }
        guard !problemComponents.isEmpty else {
            preferences.claudeStatusLastNotificationFingerprint = ""
            return
        }
        guard preferences.claudeStatusNotificationsEnabled else { return }

        let fingerprint = Self.notificationFingerprint(for: problemComponents)
        guard fingerprint != preferences.claudeStatusLastNotificationFingerprint else { return }

        let status = await notifications.authorizationStatus()
        notificationAuthorization = status
        guard status.canSendNotifications else { return }

        do {
            try await notifications.sendStatusAlert(
                title: Self.notificationTitle(for: problemComponents),
                body: Self.notificationBody(for: problemComponents, snapshot: snapshot),
                identifier: "claude-status-\(fingerprint)"
            )
            preferences.claudeStatusLastNotificationFingerprint = fingerprint
        } catch {
            Log.app.error("Claude Status notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func userFacingMessage(_ error: Error) -> String {
        if let clientError = error as? ClaudeStatusClient.ClientError {
            return clientError.description
        }
        return error.localizedDescription
    }

    private static func notificationFingerprint(for components: [ClaudeStatusComponent]) -> String {
        components
            .sorted { $0.id < $1.id }
            .map { "\($0.id):\($0.status.rawStatus)" }
            .joined(separator: "|")
    }

    private static func notificationTitle(for components: [ClaudeStatusComponent]) -> String {
        if components.count == 1, let component = components.first {
            return "\(component.name) is \(component.status.displayName)"
        }
        return "\(components.count) Claude services need attention"
    }

    private static func notificationBody(for components: [ClaudeStatusComponent], snapshot: ClaudeStatusSnapshot) -> String {
        let componentSummary = components
            .map { "\($0.name): \($0.status.displayName)" }
            .joined(separator: "; ")
        if let incident = snapshot.activeIncident {
            return "\(componentSummary). \(incident.name)"
        }
        return componentSummary
    }
}
