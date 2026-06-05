import Foundation
import Observation

@MainActor
@Observable
final class OpenAIStatusViewModel {
    static let refreshInterval: TimeInterval = 5 * 60

    private(set) var snapshot: OpenAIStatusSnapshot?
    private(set) var isLoading = false
    private(set) var isStale = false
    private(set) var lastError: String?
    private(set) var uptimeSnapshot: OpenAIStatusUptimeSnapshot?
    private(set) var isUptimeStale = false
    private(set) var uptimeLastError: String?
    private(set) var notificationAuthorization: ClaudeStatusNotificationAuthorizationStatus = .notDetermined
    private(set) var isRequestingNotificationAuthorization = false
    @ObservationIgnored var onRefresh: (() -> Void)?

    var availableGroups: [OpenAIStatusGroup] {
        guard let snapshot else { return OpenAIStatusGroupCatalog.fallbackGroups }
        let groups = groups(for: snapshot)
        return groups.isEmpty ? OpenAIStatusGroupCatalog.fallbackGroups : groups
    }

    var visibleGroups: [OpenAIStatusGroup] {
        guard snapshot != nil else { return [] }
        return visibleGroups(from: availableGroups)
    }

    var visibleUptimeRows: [OpenAIStatusUptimeRow] {
        visibleGroups.map { group in
            OpenAIStatusUptimeRow(
                group: group,
                history: uptimeSnapshot?.history(for: group)
            )
        }
    }

    var notificationPermissionDenied: Bool {
        notificationAuthorization == .denied
    }

    var statusPageURL: URL {
        URL(string: "https://status.openai.com/")!
    }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let client: any OpenAIStatusFetching
    @ObservationIgnored private let cache: any OpenAIStatusCaching
    @ObservationIgnored private let uptimeClient: any OpenAIStatusUptimeFetching
    @ObservationIgnored private let uptimeCache: any OpenAIStatusUptimeCaching
    @ObservationIgnored private let notifications: any ClaudeStatusNotificationServicing
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(
        preferences: Preferences,
        client: any OpenAIStatusFetching = OpenAIStatusClient(),
        cache: any OpenAIStatusCaching = OpenAIStatusCache(),
        uptimeClient: any OpenAIStatusUptimeFetching = OpenAIStatusUptimeClient(),
        uptimeCache: any OpenAIStatusUptimeCaching = OpenAIStatusUptimeCache(),
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
            preferences.openAIStatusNotificationsEnabled = false
            preferences.openAIStatusLastNotificationFingerprint = ""
            return
        }

        isRequestingNotificationAuthorization = true
        let status = await notifications.requestAuthorization()
        notificationAuthorization = status
        isRequestingNotificationAuthorization = false
        preferences.openAIStatusNotificationsEnabled = status.canSendNotifications
        if status.canSendNotifications {
            await refresh(force: true)
        }
    }

    func refreshIfNeeded(now: Date = .now) async {
        var summaryNeedsRefresh = true
        if let cached = cache.read(ttl: OpenAIStatusCache.defaultTTL, now: now), !cached.isStale {
            snapshot = cached.snapshot
            isStale = false
            lastError = nil
            summaryNeedsRefresh = false
        }

        var uptimeNeedsRefresh = true
        if let cached = uptimeCache.read(ttl: OpenAIStatusUptimeCache.defaultTTL, now: now), !cached.isStale {
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
           let cached = cache.read(ttl: OpenAIStatusCache.defaultTTL, now: now),
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
                Log.app.error("OpenAI Status cache write failed: \(error.localizedDescription, privacy: .public)")
            }
            await handleNotifications(for: fresh)
            onRefresh?()
        } catch {
            lastError = userFacingMessage(error)
            if let cached = cache.read(ttl: OpenAIStatusCache.defaultTTL, now: now) {
                snapshot = cached.snapshot
                isStale = true
            }
        }
    }

    private func refreshUptime(force: Bool = true, now: Date = .now) async {
        if !force,
           let cached = uptimeCache.read(ttl: OpenAIStatusUptimeCache.defaultTTL, now: now),
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
                Log.app.error("OpenAI Status uptime cache write failed: \(error.localizedDescription, privacy: .public)")
            }
            onRefresh?()
        } catch {
            uptimeLastError = userFacingMessage(error)
            if let cached = uptimeCache.read(ttl: OpenAIStatusUptimeCache.defaultTTL, now: now) {
                uptimeSnapshot = cached.snapshot
                isUptimeStale = true
            }
        }
    }

    func isGroupVisible(_ group: OpenAIStatusGroup) -> Bool {
        visibleGroupIDs(for: availableGroups).contains(group.id)
    }

    func canHideGroup(_ group: OpenAIStatusGroup) -> Bool {
        let visibleIDs = visibleGroupIDs(for: availableGroups)
        return !(visibleIDs.count == 1 && visibleIDs.contains(group.id))
    }

    func setGroupVisibility(_ group: OpenAIStatusGroup, isVisible: Bool) {
        var ids = preferences.openAIStatusVisibleGroupIDs
        if isVisible {
            ids.insert(group.id)
        } else {
            ids.subtract(OpenAIStatusGroupCatalog.equivalentIDs(for: group))
        }
        if ids.isEmpty {
            ids.insert(group.id)
        }
        preferences.openAIStatusVisibleGroupIDs = ids

        if snapshot != nil {
            Task {
                await handleNotificationsForCurrentSnapshot()
                await refreshUptimeIfNeeded()
            }
        }
    }

    func visibleGroups(from groups: [OpenAIStatusGroup]) -> [OpenAIStatusGroup] {
        OpenAIStatusGroupCatalog.visibleGroups(
            from: groups,
            storedIDs: preferences.openAIStatusVisibleGroupIDs
        )
    }

    private var shouldRefresh: Bool {
        preferences.selectedProvider == .codex || preferences.openAIStatusNotificationsEnabled
    }

    private func loadCachedSnapshot(now: Date = .now) {
        guard let cached = cache.read(ttl: OpenAIStatusCache.defaultTTL, now: now) else { return }
        snapshot = cached.snapshot
        isStale = cached.isStale
    }

    private func loadCachedUptimeSnapshot(now: Date = .now) {
        guard let cached = uptimeCache.read(ttl: OpenAIStatusUptimeCache.defaultTTL, now: now) else { return }
        uptimeSnapshot = cached.snapshot
        isUptimeStale = cached.isStale
    }

    private func refreshUptimeIfNeeded(now: Date = .now) async {
        guard shouldRefresh else { return }
        guard uptimeSnapshot == nil || visibleUptimeRows.contains(where: { $0.history == nil }) else { return }
        await refreshUptime(force: false, now: now)
    }

    private func visibleGroupIDs(for groups: [OpenAIStatusGroup]) -> Set<String> {
        OpenAIStatusGroupCatalog.visibleGroupIDs(
            from: preferences.openAIStatusVisibleGroupIDs,
            groups: groups
        )
    }

    private func groups(for snapshot: OpenAIStatusSnapshot) -> [OpenAIStatusGroup] {
        OpenAIStatusGroupCatalog.groups(
            from: snapshot.components,
            definitions: uptimeSnapshot?.groupDefinitions ?? OpenAIStatusGroupCatalog.defaultGroupDefinitions
        )
    }

    private func handleNotificationsForCurrentSnapshot() async {
        guard let snapshot else { return }
        await handleNotifications(for: snapshot)
    }

    private func handleNotifications(for snapshot: OpenAIStatusSnapshot) async {
        let problemGroups = visibleGroups(from: groups(for: snapshot))
            .filter { !$0.isOperational }
        guard !problemGroups.isEmpty else {
            preferences.openAIStatusLastNotificationFingerprint = ""
            return
        }
        guard preferences.openAIStatusNotificationsEnabled else { return }

        let fingerprint = Self.notificationFingerprint(for: problemGroups)
        guard fingerprint != preferences.openAIStatusLastNotificationFingerprint else { return }

        let status = await notifications.authorizationStatus()
        notificationAuthorization = status
        guard status.canSendNotifications else { return }

        do {
            try await notifications.sendStatusAlert(
                title: Self.notificationTitle(for: problemGroups),
                body: Self.notificationBody(for: problemGroups, snapshot: snapshot),
                identifier: "openai-status-\(fingerprint)"
            )
            preferences.openAIStatusLastNotificationFingerprint = fingerprint
        } catch {
            Log.app.error("OpenAI Status notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func userFacingMessage(_ error: Error) -> String {
        if let clientError = error as? OpenAIStatusClient.ClientError {
            return clientError.description
        }
        return error.localizedDescription
    }

    private static func notificationFingerprint(for groups: [OpenAIStatusGroup]) -> String {
        groups
            .sorted { $0.id < $1.id }
            .map { "\($0.id):\($0.status.rawStatus)" }
            .joined(separator: "|")
    }

    private static func notificationTitle(for groups: [OpenAIStatusGroup]) -> String {
        if groups.count == 1, let group = groups.first {
            return "\(group.name) is \(group.status.displayName)"
        }
        return "\(groups.count) OpenAI services need attention"
    }

    private static func notificationBody(for groups: [OpenAIStatusGroup], snapshot: OpenAIStatusSnapshot) -> String {
        let groupSummary = groups
            .map { "\($0.name): \($0.status.displayName)" }
            .joined(separator: "; ")
        if let incident = snapshot.activeIncident {
            return "\(groupSummary). \(incident.name)"
        }
        return groupSummary
    }
}
