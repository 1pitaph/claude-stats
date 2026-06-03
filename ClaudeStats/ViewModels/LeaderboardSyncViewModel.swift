import Foundation
import Observation

@MainActor
@Observable
final class LeaderboardSyncViewModel {
    enum SyncStatus: Sendable, Equatable {
        case disabled
        case idle
        case needsNickname
        case checkingAccount
        case syncing
        case synced(Date)
        case failed(String)

        var displayText: String {
            switch self {
            case .disabled: "Disabled"
            case .idle: "Ready"
            case .needsNickname: "Choose a nickname"
            case .checkingAccount: "Checking iCloud…"
            case .syncing: "Syncing…"
            case .synced(let date): "Synced \(Format.relativeDate(date))"
            case .failed(let reason): reason
            }
        }
    }

    private(set) var syncStatus: SyncStatus = .disabled
    private(set) var accountState: LeaderboardCloudAccountState = .unknown
    private(set) var scores: [LeaderboardScore] = []
    private(set) var isLoadingScores = false
    private(set) var scoreError: String?
    private(set) var scoreEmptyMessage: String?
    private(set) var lastLoadedPeriodKey: String?
    private(set) var currentUserHash: String?
    private(set) var isSavingProfile = false
    private(set) var selectedUserHistory: [LeaderboardScoreHistoryPoint] = []
    private(set) var isLoadingSelectedUserHistory = false
    private(set) var selectedUserHistoryError: String?
    private(set) var realtimeStatus: LeaderboardRealtimeStatus = .inactive

    var avatarSeed: String {
        preferences.leaderboardAvatarSeed.isEmpty
            ? LeaderboardAvatarSeed.fallback
            : preferences.leaderboardAvatarSeed
    }

    var currentUserScore: LeaderboardScore? {
        guard let currentUserHash else { return nil }
        return scores.first { $0.userHash == currentUserHash }
    }

    var currentUserFavoriteModels: [LeaderboardFavoriteModel] {
        builder.favoriteModels(sessions: store.sessions)
    }

    var leaderboardStatusText: String {
        guard leaderboardsFeatureIsActive else { return SyncStatus.disabled.displayText }
        return syncStatus.displayText
    }

    var leaderboardRealtimeStatusText: String {
        guard leaderboardsFeatureIsActive else { return SyncStatus.disabled.displayText }
        switch realtimeStatus {
        case .inactive, .live, .pending, .historicalCache, .unavailable:
            return realtimeStatus.displayText
        }
    }

    private let preferences: Preferences
    private let store: SessionStore
    private let client: any LeaderboardCloudServicing
    private let localStore: any LeaderboardLocalStoring
    private let builder: LeaderboardScoreBuilder
    private let refreshBeforeSync: Bool
    private let scoreCacheTTL: TimeInterval
    private let silentSyncDebounceInterval: TimeInterval
    private let silentSyncMinimumInterval: TimeInterval
    private let realtime: LeaderboardRealtimeCoordinator
    private let syncLease: any LeaderboardSyncLeasing
    private let syncLeasePolicy: LeaderboardSyncLeasePolicy
    private let remoteNotificationRegistrar: (any LeaderboardRemoteNotificationRegistering)?
    private let realtimeRefreshDebounceInterval: TimeInterval
    private var syncTask: Task<Void, Never>?
    private var silentSyncTask: Task<Void, Never>?
    private var realtimeRefreshTask: Task<Void, Never>?
    private var visibleScoreQuery: VisibleScoreQuery?
    private var visibleHistoryQuery: VisibleHistoryQuery?
    private var activeRealtimeScope: LeaderboardRealtimeScope?

    private static let defaultScoreCacheTTL: TimeInterval = 60 * 60
    private static let defaultSilentSyncDebounceInterval: TimeInterval = 60
    private static let defaultSilentSyncMinimumInterval: TimeInterval = 5 * 60
    private static let defaultRealtimeRefreshDebounceInterval: TimeInterval = 2

    private var leaderboardsFeatureIsActive: Bool {
        AppVariant.isEnabled(.leaderboards) && preferences.leaderboardsEnabled
    }

    private struct VisibleScoreQuery: Sendable {
        let metric: LeaderboardMetric
        let period: LeaderboardPeriod
        let now: Date
        let allowsRecentDayFallback: Bool
    }

    private struct VisibleHistoryQuery: Sendable {
        let userHash: String
        let metric: LeaderboardMetric
        let period: LeaderboardPeriod
        let historyStartMonthKey: String?
        let now: Date
    }

    init(preferences: Preferences,
         store: SessionStore,
         client: any LeaderboardCloudServicing = CloudKitLeaderboardClient(),
         localStore: any LeaderboardLocalStoring = LeaderboardLocalStore(),
         builder: LeaderboardScoreBuilder = LeaderboardScoreBuilder(),
         refreshBeforeSync: Bool = true,
         scoreCacheTTL: TimeInterval = LeaderboardSyncViewModel.defaultScoreCacheTTL,
         silentSyncDebounceInterval: TimeInterval = LeaderboardSyncViewModel.defaultSilentSyncDebounceInterval,
         silentSyncMinimumInterval: TimeInterval = LeaderboardSyncViewModel.defaultSilentSyncMinimumInterval,
         realtimeCoordinator: LeaderboardRealtimeCoordinator? = nil,
         syncLease: any LeaderboardSyncLeasing = CloudKitLeaderboardSyncLeaseClient(),
         syncLeasePolicy: LeaderboardSyncLeasePolicy = .currentApp(),
         remoteNotificationRegistrar: (any LeaderboardRemoteNotificationRegistering)? = nil,
         realtimeRefreshDebounceInterval: TimeInterval = LeaderboardSyncViewModel.defaultRealtimeRefreshDebounceInterval) {
        self.preferences = preferences
        self.store = store
        self.client = client
        self.localStore = localStore
        self.builder = builder
        self.refreshBeforeSync = refreshBeforeSync
        self.scoreCacheTTL = scoreCacheTTL
        self.silentSyncDebounceInterval = silentSyncDebounceInterval
        self.silentSyncMinimumInterval = silentSyncMinimumInterval
        self.realtime = realtimeCoordinator ?? LeaderboardRealtimeCoordinator(localStore: localStore)
        self.syncLease = syncLease
        self.syncLeasePolicy = syncLeasePolicy
        self.remoteNotificationRegistrar = remoteNotificationRegistrar
        self.realtimeRefreshDebounceInterval = realtimeRefreshDebounceInterval
        let storedUserHash = preferences.leaderboardProfileUserHash.trimmingCharacters(in: .whitespacesAndNewlines)
        currentUserHash = storedUserHash.isEmpty ? nil : storedUserHash
        syncStatus = leaderboardsFeatureIsActive ? .idle : .disabled
    }

    func start() {
        syncTask?.cancel()
        guard AppVariant.isEnabled(.leaderboards) else {
            syncStatus = .disabled
            accountState = .unknown
            return
        }
        if preferences.leaderboardsEnabled {
            remoteNotificationRegistrar?.registerForLeaderboardRemoteNotifications()
        }
        syncTask = Task { [weak self] in
            await self?.syncSilentlyIfNeeded()
        }
    }

    func stop() {
        syncTask?.cancel()
        syncTask = nil
        silentSyncTask?.cancel()
        silentSyncTask = nil
        realtimeRefreshTask?.cancel()
        realtimeRefreshTask = nil
    }

    func scheduleSilentSyncAfterDataRefresh() {
        guard leaderboardsFeatureIsActive else { return }
        scheduleSilentSync(after: silentSyncDebounceInterval)
    }

    func activateRealtime(scope: LeaderboardRealtimeScope?) async {
        guard leaderboardsFeatureIsActive else {
            realtimeStatus = .inactive
            activeRealtimeScope = nil
            return
        }

        activeRealtimeScope = scope
        if scope != nil {
            remoteNotificationRegistrar?.registerForLeaderboardRemoteNotifications()
        }
        realtimeStatus = await realtime.activate(scope: scope)
        await refreshIfPendingRealtimeChanges()
    }

    func deactivateRealtime() {
        activeRealtimeScope = nil
        realtimeStatus = .inactive
        realtimeRefreshTask?.cancel()
        realtimeRefreshTask = nil
        Task { [realtime] in
            await realtime.deactivate()
        }
    }

    func handleRealtimeNotification(_ notification: LeaderboardRealtimeNotification) {
        guard leaderboardsFeatureIsActive else { return }
        Task { [weak self] in
            guard let self else { return }
            let decision = await realtime.handle(notification)
            await applyRealtimeDecision(decision)
        }
    }

    func handleRemoteNotificationRegistrationFailure(_ error: Error) {
        Log.network.error("Leaderboard remote notification registration failed: \(error.localizedDescription, privacy: .public)")
        if activeRealtimeScope != nil {
            realtimeStatus = .unavailable(error.localizedDescription)
        }
    }

    func refreshIfPendingRealtimeChanges() async {
        guard leaderboardsFeatureIsActive,
              let scope = activeRealtimeScope,
              await realtime.consumePending(for: scope) else {
            return
        }
        realtimeStatus = .pending
        await refreshVisibleScoresFromRealtime(scope: scope)
    }

    func checkAccountStatus() async {
        guard leaderboardsFeatureIsActive else {
            syncStatus = .disabled
            accountState = .unknown
            return
        }
        ensureLocalAvatarSeed()
        syncStatus = .checkingAccount
        accountState = await client.accountState()
        if accountState == .available {
            do {
                try await reconcileCurrentUserProfile()
            } catch {
                let reason = userFacingMessage(error)
                preferences.leaderboardLastSyncError = reason
                syncStatus = .failed(reason)
                return
            }
        }
        syncStatus = statusAfterAccountCheck()
    }

    func syncNow() async {
        await syncIfDue(force: true)
    }

    func syncIfDue(force: Bool) async {
        await submitCurrentScores(force: force, showsStatus: true, refreshStoreBeforeSubmit: true)
    }

    func syncAndRefreshScores(metric: LeaderboardMetric,
                              period: LeaderboardPeriod,
                              now: Date = .now,
                              allowsRecentDayFallback: Bool = true) async {
        await submitCurrentScores(
            force: true,
            showsStatus: true,
            refreshStoreBeforeSubmit: true,
            refreshVisibleAfterSync: false
        )
        await loadScores(
            metric: metric,
            period: period,
            now: now,
            allowsRecentDayFallback: allowsRecentDayFallback,
            forceRefresh: true
        )
        if let query = visibleHistoryQuery {
            await loadScoreHistory(
                userHash: query.userHash,
                metric: query.metric,
                period: query.period,
                historyStartMonthKey: query.historyStartMonthKey,
                forceRefresh: true,
                now: query.now
            )
        }
    }

    func loadScores(metric: LeaderboardMetric,
                    period: LeaderboardPeriod,
                    now: Date = .now,
                    allowsRecentDayFallback: Bool = true,
                    forceRefresh: Bool = false) async {
        guard leaderboardsFeatureIsActive else {
            scores = []
            lastLoadedPeriodKey = nil
            scoreError = nil
            scoreEmptyMessage = nil
            return
        }

        visibleScoreQuery = VisibleScoreQuery(
            metric: metric,
            period: period,
            now: now,
            allowsRecentDayFallback: allowsRecentDayFallback
        )
        ensureLocalAvatarSeed()
        let requestedWindow = LeaderboardPeriodCalculator.window(for: period, now: now)
        let windows = scoreLookupWindows(
            for: period,
            now: now,
            allowsRecentDayFallback: allowsRecentDayFallback
        )
        lastLoadedPeriodKey = requestedWindow.periodKey
        scoreError = nil
        scoreEmptyMessage = nil

        let cached = await cachedScores(metric: metric, period: period, windows: windows)
        if let cached {
            applyCachedScores(
                cached,
                requestedPeriod: period,
                allowsRecentDayFallback: windows.count > 1
            )
        }
        let shouldRefresh = forceRefresh || cached.map { !cacheIsFresh($0.savedAt) } ?? true
        guard shouldRefresh else { return }

        isLoadingScores = true
        defer { isLoadingScores = false }
        await fetchScoresFromCloud(
            metric: metric,
            period: period,
            windows: windows,
            requestedWindow: requestedWindow
        )
    }

    func loadScoreHistory(userHash: String,
                          metric: LeaderboardMetric,
                          period: LeaderboardPeriod,
                          historyStartMonthKey: String? = nil,
                          forceRefresh: Bool = false,
                          now: Date = .now) async {
        guard leaderboardsFeatureIsActive else {
            clearSelectedUserHistory()
            return
        }
        visibleHistoryQuery = VisibleHistoryQuery(
            userHash: userHash,
            metric: metric,
            period: period,
            historyStartMonthKey: historyStartMonthKey,
            now: now
        )
        selectedUserHistoryError = nil
        if userHash == currentUserHash {
            let points = builder.historyPoints(
                sessions: store.sessions,
                metric: metric,
                period: period,
                includeActivity: includeActivityHistory,
                now: now
            )
            selectedUserHistory = points
            isLoadingSelectedUserHistory = false
            return
        }

        let historyStart = await remoteHistoryStartDate(
            userHash: userHash,
            period: period,
            preferredMonthKey: historyStartMonthKey
        )
        if selectedUserHistoryError != nil {
            selectedUserHistory = []
            isLoadingSelectedUserHistory = false
            return
        }

        let windows = LeaderboardPeriodCalculator.historyScope(for: period, now: now, historyStart: historyStart)
        guard !windows.isEmpty else {
            selectedUserHistory = []
            isLoadingSelectedUserHistory = false
            return
        }

        let cacheKey = LeaderboardHistoryCacheKey(
            userHash: userHash,
            metric: metric,
            period: period,
            windowKeys: windows.map(\.periodKey)
        )
        let cached = await localStore.readHistory(for: cacheKey)
        if let cached {
            selectedUserHistory = cached.points
            selectedUserHistoryError = nil
        }
        let shouldRefresh = forceRefresh || cached.map { !cacheIsFresh($0.savedAt) } ?? true
        guard shouldRefresh else { return }

        isLoadingSelectedUserHistory = true
        defer { isLoadingSelectedUserHistory = false }

        do {
            let points = try await client.fetchScoreHistory(
                userHash: userHash,
                metric: metric,
                period: period,
                windows: windows
            )
            guard !Task.isCancelled else { return }
            selectedUserHistory = points
            await localStore.writeHistory(points, for: cacheKey, savedAt: Date())
        } catch is CancellationError {
            return
        } catch let error as LeaderboardCloudError {
            if cached == nil {
                selectedUserHistory = []
                selectedUserHistoryError = error.description
            } else {
                Log.network.error("Leaderboard history refresh failed: \(error.description, privacy: .public)")
            }
        } catch {
            if cached == nil {
                selectedUserHistory = []
                selectedUserHistoryError = error.localizedDescription
            } else {
                Log.network.error("Leaderboard history refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func applyRealtimeDecision(_ decision: LeaderboardRealtimeDecision) async {
        switch decision {
        case .ignored:
            return
        case .markedGlobalPending:
            if let activeRealtimeScope {
                realtimeStatus = await realtime.currentStatus(for: activeRealtimeScope)
            }
        case .markedPending:
            if let activeRealtimeScope {
                realtimeStatus = await realtime.currentStatus(for: activeRealtimeScope)
            }
        case .refresh(let scope):
            scheduleRealtimeRefresh(for: scope)
        }
    }

    private func scheduleRealtimeRefresh(for scope: LeaderboardRealtimeScope) {
        guard activeRealtimeScope == scope else { return }
        realtimeStatus = .pending
        realtimeRefreshTask?.cancel()
        realtimeRefreshTask = Task { [weak self] in
            guard let self else { return }
            if realtimeRefreshDebounceInterval > 0 {
                try? await Task.sleep(for: .seconds(realtimeRefreshDebounceInterval))
            }
            guard !Task.isCancelled else { return }
            await refreshVisibleScoresFromRealtime(scope: scope)
        }
    }

    private func refreshVisibleScoresFromRealtime(scope: LeaderboardRealtimeScope) async {
        guard let query = visibleScoreQuery,
              activeRealtimeScope == scope,
              visibleScoreQuery(query, matches: scope) else {
            return
        }

        await loadScores(
            metric: query.metric,
            period: query.period,
            now: query.now,
            allowsRecentDayFallback: query.allowsRecentDayFallback,
            forceRefresh: true
        )

        guard activeRealtimeScope == scope else { return }
        realtimeStatus = await realtime.currentStatus(for: scope)
    }

    private func visibleScoreQuery(_ query: VisibleScoreQuery, matches scope: LeaderboardRealtimeScope) -> Bool {
        let window = LeaderboardPeriodCalculator.window(for: query.period, now: query.now)
        return query.metric == scope.metric
            && query.period == scope.period
            && window.periodKey == scope.periodKey
    }

    private func syncSilentlyIfNeeded() async {
        await submitCurrentScores(force: false, showsStatus: false, refreshStoreBeforeSubmit: false)
    }

    private func submitCurrentScores(force: Bool,
                                     showsStatus: Bool,
                                     refreshStoreBeforeSubmit: Bool,
                                     refreshVisibleAfterSync: Bool = true) async {
        guard leaderboardsFeatureIsActive else {
            if showsStatus { syncStatus = .disabled }
            return
        }
        ensureLocalAvatarSeed()
        let nickname = preferences.leaderboardNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty else {
            if showsStatus { syncStatus = .needsNickname }
            return
        }

        if showsStatus {
            syncStatus = .checkingAccount
            accountState = await client.accountState()
            guard accountState == .available else {
                let reason = accountState.displayText
                preferences.leaderboardLastSyncError = reason
                syncStatus = .failed(reason)
                return
            }
            do {
                try await reconcileCurrentUserProfile()
            } catch {
                let reason = userFacingMessage(error)
                preferences.leaderboardLastSyncError = reason
                syncStatus = .failed(reason)
                return
            }
        }

        if showsStatus { syncStatus = .syncing }
        if refreshBeforeSync && refreshStoreBeforeSubmit {
            await store.refresh()
        }
        let now = Date()
        let includeActivity = preferences.aiActivityAnalysisEnabled && ScreenTimeService.canRead()
        let submissions = builder.submissions(
            sessions: store.sessions,
            nickname: nickname,
            includeActivity: includeActivity,
            now: now
        )
        let historySubmissions = builder.historySubmissions(
            sessions: store.sessions,
            includeActivity: includeActivity,
            now: now
        )
        guard !submissions.isEmpty || !historySubmissions.isEmpty else {
            let reason = "No leaderboard scores to submit yet."
            if showsStatus {
                preferences.leaderboardLastSyncError = reason
                syncStatus = .failed(reason)
            }
            return
        }
        let draft = profileDraft(nickname: nickname)
        let fingerprint = LeaderboardSyncFingerprint.make(
            profile: draft,
            submissions: submissions,
            historySubmissions: historySubmissions
        )
        let syncState = await localStore.readSyncState()
        if !force {
            guard syncState.lastFingerprint != fingerprint else {
                if showsStatus, let last = syncState.lastUploadedAt ?? preferences.leaderboardLastSyncedAt {
                    syncStatus = .synced(last)
                }
                return
            }
            if let lastUploadedAt = syncState.lastUploadedAt,
               now.timeIntervalSince(lastUploadedAt) < silentSyncMinimumInterval {
                scheduleSilentSync(after: silentSyncMinimumInterval - now.timeIntervalSince(lastUploadedAt))
                if showsStatus {
                    syncStatus = .synced(lastUploadedAt)
                }
                return
            }
        }

        do {
            if !showsStatus && !force {
                let userHash = try await client.currentUserHash()
                let decision = try await syncLease.acquire(syncLeasePolicy.request(userHash: userHash, now: now))
                guard case .acquired = decision else {
                    Log.network.debug("Leaderboard automatic sync skipped because another app variant holds the sync lease.")
                    return
                }
            }
            let profile = try await client.submit(
                submissions,
                historySubmissions: historySubmissions,
                profile: draft
            )
            remember(profile: profile)
            await localStore.writeProfile(profile, savedAt: now)
            let submittedPeriodKeys = submissions
                .map { "\($0.period.rawValue):\($0.periodKey)" }
                .uniqued()
                .sorted()
            await localStore.writeSyncState(LeaderboardLocalSyncState(
                lastFingerprint: fingerprint,
                lastUploadedAt: now,
                lastSubmittedPeriodKeys: submittedPeriodKeys
            ))
            let syncedAt = now
            preferences.leaderboardLastSyncedAt = syncedAt
            preferences.leaderboardLastSyncError = ""
            preferences.leaderboardLastSubmittedPeriodKeys = submittedPeriodKeys
            syncStatus = .synced(syncedAt)
            if refreshVisibleAfterSync {
                await refreshVisibleLeaderboardAfterSync()
            }
        } catch let error as LeaderboardCloudError {
            if showsStatus {
                preferences.leaderboardLastSyncError = error.description
                syncStatus = .failed(error.description)
            }
            Log.network.error("Leaderboard sync failed: \(error.description, privacy: .public)")
        } catch {
            let reason = error.localizedDescription
            if showsStatus {
                preferences.leaderboardLastSyncError = reason
                syncStatus = .failed(reason)
            }
            Log.network.error("Leaderboard sync failed: \(reason, privacy: .public)")
        }
    }

    func clearSelectedUserHistory() {
        selectedUserHistory = []
        selectedUserHistoryError = nil
        isLoadingSelectedUserHistory = false
    }

    private var includeActivityHistory: Bool {
        preferences.aiActivityAnalysisEnabled && ScreenTimeService.canRead()
    }

    func randomizeAvatar() async {
        let previous = ensureLocalAvatarSeed()
        var next = LeaderboardAvatarSeed.random()
        while next == previous {
            next = LeaderboardAvatarSeed.random()
        }
        preferences.leaderboardAvatarSeed = next

        guard leaderboardsFeatureIsActive else {
            syncStatus = .disabled
            return
        }
        await saveCurrentProfileIfPossible()
    }

    private func scheduleSilentSync(after delay: TimeInterval) {
        silentSyncTask?.cancel()
        silentSyncTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            await self?.syncSilentlyIfNeeded()
        }
    }

    private func cacheIsFresh(_ savedAt: Date) -> Bool {
        Date().timeIntervalSince(savedAt) < scoreCacheTTL
    }

    private func scoreLookupWindows(for period: LeaderboardPeriod,
                                    now: Date,
                                    allowsRecentDayFallback: Bool) -> [LeaderboardPeriodWindow] {
        guard period == .day, allowsRecentDayFallback else {
            return [LeaderboardPeriodCalculator.window(for: period, now: now)]
        }
        return (0..<7).map { dayOffset in
            LeaderboardPeriodCalculator.window(
                for: .day,
                now: now.addingTimeInterval(TimeInterval(-dayOffset * 86_400))
            )
        }
    }

    private func cachedScores(metric: LeaderboardMetric,
                              period: LeaderboardPeriod,
                              windows: [LeaderboardPeriodWindow]) async -> LeaderboardCachedScores? {
        var firstEmptyCache: LeaderboardCachedScores?
        for window in windows {
            let key = LeaderboardScoresCacheKey(
                metric: metric,
                period: period,
                periodKey: window.periodKey,
                limit: 100
            )
            guard let cached = await localStore.readScores(for: key) else { continue }
            if !cached.scores.isEmpty {
                return cached
            }
            if firstEmptyCache == nil {
                firstEmptyCache = cached
            }
        }
        return firstEmptyCache
    }

    private func applyCachedScores(_ cached: LeaderboardCachedScores,
                                   requestedPeriod: LeaderboardPeriod,
                                   allowsRecentDayFallback: Bool) {
        scores = scoresWithContiguousRanks(cached.scores)
        lastLoadedPeriodKey = cached.key.periodKey
        scoreError = nil
        scoreEmptyMessage = cached.scores.isEmpty
            ? emptyScoresMessage(
                for: requestedPeriod,
                allowsRecentDayFallback: allowsRecentDayFallback
            )
            : nil
    }

    private func fetchScoresFromCloud(metric: LeaderboardMetric,
                                      period: LeaderboardPeriod,
                                      windows: [LeaderboardPeriodWindow],
                                      requestedWindow: LeaderboardPeriodWindow) async {
        let hadDisplayableScores = !scores.isEmpty
        do {
            for window in windows {
                let fetched = try await client.fetchScores(
                    metric: metric,
                    period: period,
                    periodKey: window.periodKey,
                    limit: 100
                )
                let key = LeaderboardScoresCacheKey(
                    metric: metric,
                    period: period,
                    periodKey: window.periodKey,
                    limit: 100
                )
                let displayScores = scoresWithContiguousRanks(fetched)
                await localStore.writeScores(displayScores, for: key, savedAt: Date())
                await cacheProfiles(from: displayScores)
                if !fetched.isEmpty {
                    scores = displayScores
                    lastLoadedPeriodKey = window.periodKey
                    scoreError = nil
                    scoreEmptyMessage = nil
                    return
                }
            }
            scores = []
            lastLoadedPeriodKey = requestedWindow.periodKey
            scoreError = nil
            scoreEmptyMessage = emptyScoresMessage(
                for: period,
                allowsRecentDayFallback: windows.count > 1
            )
        } catch let error as LeaderboardCloudError {
            handleScoreRefreshError(error.description, hadDisplayableScores: hadDisplayableScores)
        } catch {
            handleScoreRefreshError(error.localizedDescription, hadDisplayableScores: hadDisplayableScores)
        }
    }

    private func handleScoreRefreshError(_ reason: String, hadDisplayableScores: Bool) {
        scoreEmptyMessage = nil
        if hadDisplayableScores {
            Log.network.error("Leaderboard score refresh failed: \(reason, privacy: .public)")
        } else {
            scores = []
            scoreError = reason
        }
    }

    private func scoresWithContiguousRanks(_ scores: [LeaderboardScore]) -> [LeaderboardScore] {
        scores.enumerated().map { index, score in
            score.withRank(index + 1)
        }
    }

    private func cacheProfiles(from scores: [LeaderboardScore]) async {
        for score in scores {
            guard let userHash = score.userHash else { continue }
            await localStore.writeProfile(LeaderboardProfile(
                userHash: userHash,
                nickname: score.nickname,
                avatarSeed: score.avatarSeed,
                historyStartMonthKey: score.historyStartMonthKey,
                favoriteModels: score.favoriteModels,
                updatedAt: score.updatedAt
            ), savedAt: Date())
        }
    }

    private func remoteHistoryStartDate(userHash: String,
                                        period: LeaderboardPeriod,
                                        preferredMonthKey: String?) async -> Date? {
        guard period == .allTime else { return nil }
        if let preferredMonthKey,
           let window = LeaderboardPeriodCalculator.window(for: .month, periodKey: preferredMonthKey) {
            return window.startUTC
        }
        if let cached = await localStore.readProfile(userHash: userHash),
           let monthKey = cached.profile.historyStartMonthKey,
           let window = LeaderboardPeriodCalculator.window(for: .month, periodKey: monthKey) {
            return window.startUTC
        }
        do {
            guard let profile = try await client.fetchProfile(userHash: userHash),
                  let monthKey = profile.historyStartMonthKey,
                  let window = LeaderboardPeriodCalculator.window(for: .month, periodKey: monthKey) else {
                selectedUserHistoryError = "This user has not uploaded local history yet."
                return nil
            }
            await localStore.writeProfile(
                LeaderboardProfile(
                    userHash: userHash,
                    nickname: profile.nickname,
                    avatarSeed: profile.avatarSeed,
                    historyStartMonthKey: profile.historyStartMonthKey,
                    favoriteModels: profile.favoriteModels,
                    updatedAt: profile.updatedAt
                ),
                savedAt: Date()
            )
            return window.startUTC
        } catch let error as LeaderboardCloudError {
            selectedUserHistoryError = error.description
            return nil
        } catch {
            selectedUserHistoryError = error.localizedDescription
            return nil
        }
    }

    private func refreshVisibleLeaderboardAfterSync() async {
        if let query = visibleScoreQuery {
            await loadScores(
                metric: query.metric,
                period: query.period,
                now: query.now,
                allowsRecentDayFallback: query.allowsRecentDayFallback,
                forceRefresh: true
            )
        }
        if let query = visibleHistoryQuery {
            await loadScoreHistory(
                userHash: query.userHash,
                metric: query.metric,
                period: query.period,
                historyStartMonthKey: query.historyStartMonthKey,
                forceRefresh: true,
                now: query.now
            )
        }
    }

    private func emptyScoresMessage(for period: LeaderboardPeriod,
                                    allowsRecentDayFallback: Bool) -> String {
        switch period {
        case .day:
            return allowsRecentDayFallback
                ? "No daily scores in the last 7 UTC days yet."
                : "No scores for this UTC day yet."
        case .week, .month, .allTime:
            return "No scores for this UTC period yet."
        }
    }

    @discardableResult
    private func ensureLocalAvatarSeed() -> String {
        let trimmed = preferences.leaderboardAvatarSeed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let seed = LeaderboardAvatarSeed.random()
            preferences.leaderboardAvatarSeed = seed
            return seed
        }
        return trimmed
    }

    private func reconcileCurrentUserProfileIfPossible() async {
        guard leaderboardsFeatureIsActive else { return }
        do {
            try await reconcileCurrentUserProfile()
        } catch {
            Log.network.debug("Leaderboard profile reconcile skipped: \(self.userFacingMessage(error), privacy: .public)")
        }
    }

    private func reconcileCurrentUserProfile() async throws {
        let userHash = try await client.currentUserHash()
        currentUserHash = userHash

        let storedUserHash = preferences.leaderboardProfileUserHash.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsRemoteProfile = storedUserHash != userHash
            || preferences.leaderboardAvatarSeed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard needsRemoteProfile else { return }

        preferences.leaderboardProfileUserHash = userHash
        if let profile = try await client.fetchProfile(userHash: userHash) {
            let merged = LeaderboardProfileMergePolicy.merge(
                local: profileDraft(nickname: preferences.leaderboardNickname.trimmingCharacters(in: .whitespacesAndNewlines)),
                remote: profile,
                prefersRemoteAvatarSeed: storedUserHash != userHash
            )
            await localStore.writeProfile(
                LeaderboardProfile(
                    userHash: userHash,
                    nickname: merged.draft.nickname,
                    avatarSeed: merged.draft.avatarSeed,
                    historyStartMonthKey: merged.draft.historyStartMonthKey,
                    favoriteModels: merged.draft.favoriteModels,
                    updatedAt: merged.draft.updatedAt
                ),
                savedAt: Date()
            )
            if merged.shouldUpdateLocalNickname {
                preferences.leaderboardNickname = merged.draft.nickname
            }
            if merged.shouldUpdateLocalAvatarSeed {
                preferences.leaderboardAvatarSeed = merged.draft.avatarSeed
            }
            return
        }
        preferences.leaderboardAvatarSeed = LeaderboardAvatarSeed.random()
    }

    private func saveCurrentProfileIfPossible() async {
        guard leaderboardsFeatureIsActive else {
            syncStatus = .disabled
            return
        }
        guard !isSavingProfile else { return }

        let nickname = preferences.leaderboardNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty else {
            syncStatus = .needsNickname
            return
        }

        isSavingProfile = true
        defer { isSavingProfile = false }

        syncStatus = .checkingAccount
        accountState = await client.accountState()
        guard accountState == .available else {
            let reason = accountState.displayText
            preferences.leaderboardLastSyncError = reason
            syncStatus = .failed(reason)
            return
        }

        syncStatus = .syncing
        do {
            let profile = try await client.saveProfile(profileDraft(nickname: nickname))
            remember(profile: profile)
            await localStore.writeProfile(profile, savedAt: Date())
            preferences.leaderboardLastSyncError = ""
            syncStatus = statusAfterAccountCheck()
        } catch {
            let reason = userFacingMessage(error)
            preferences.leaderboardLastSyncError = reason
            syncStatus = .failed(reason)
            Log.network.error("Leaderboard profile save failed: \(reason, privacy: .public)")
        }
    }

    private func remember(profile: LeaderboardProfile) {
        currentUserHash = profile.userHash
        preferences.leaderboardProfileUserHash = profile.userHash
        let nickname = profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if preferences.leaderboardNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !nickname.isEmpty {
            preferences.leaderboardNickname = nickname
        }
        if let avatarSeed = profile.avatarSeed,
           !avatarSeed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preferences.leaderboardAvatarSeed = avatarSeed
        }
    }

    private func profileDraft(nickname: String) -> LeaderboardProfileDraft {
        LeaderboardProfileDraft(
            nickname: nickname,
            avatarSeed: ensureLocalAvatarSeed(),
            historyStartMonthKey: builder.historyStartMonthKey(sessions: store.sessions),
            favoriteModels: builder.favoriteModels(sessions: store.sessions)
        )
    }

    private func statusAfterAccountCheck() -> SyncStatus {
        if preferences.leaderboardNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .needsNickname
        }
        if let last = preferences.leaderboardLastSyncedAt {
            return .synced(last)
        }
        return accountState == .available ? .idle : .failed(accountState.displayText)
    }

    private func userFacingMessage(_ error: Error) -> String {
        if let error = error as? LeaderboardCloudError {
            return error.description
        }
        return error.localizedDescription
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
