import Foundation
import Testing
@testable import ClaudeStats

@MainActor
@Suite("LeaderboardSyncViewModel")
struct LeaderboardSyncViewModelTests {
    @Test("Disabled leaderboards do not submit")
    func disabledDoesNotSubmit() async {
        let fixture = makeFixture(enabled: false)

        await fixture.viewModel.syncNow()

        #expect(await fixture.client.submittedCount() == 0)
        #expect(fixture.viewModel.syncStatus == .disabled)
    }

    @Test("Missing iCloud account records a user-facing error")
    func missingAccountFails() async {
        let fixture = makeFixture(enabled: true)
        await fixture.client.setAccountState(.noAccount)

        await fixture.viewModel.syncNow()

        #expect(await fixture.client.submittedCount() == 0)
        #expect(fixture.preferences.leaderboardLastSyncError == "Sign in to iCloud")
        if case .failed(let reason) = fixture.viewModel.syncStatus {
            #expect(reason == "Sign in to iCloud")
        } else {
            Issue.record("Expected failed status")
        }
    }

    @Test("Silent sync skips unchanged fingerprints unless forced")
    func fingerprintSkipsUnchangedSilentSync() async {
        let fixture = makeFixture(enabled: true)

        await fixture.viewModel.syncNow()
        await fixture.client.clearSubmissions()

        await fixture.viewModel.syncIfDue(force: false)
        #expect(await fixture.client.submittedCount() == 0)

        await fixture.viewModel.syncNow()
        #expect(await fixture.client.submittedCount() == 8)
        #expect(await fixture.client.submittedHistoryCount() > 0)
        #expect(fixture.preferences.leaderboardLastSubmittedPeriodKeys.contains("allTime:all"))
    }

    @Test("Sync profile includes the current user's top models")
    func syncProfileIncludesFavoriteModels() async {
        let now = dateUTC(2026, 5, 16, 8)
        let fixture = makeFixture(enabled: true, sessions: [
            session("sonnet", provider: .claude, at: now, tokens: 300, modelName: "sonnet"),
            session("opus", provider: .codex, at: now, tokens: 100, modelName: "opus"),
        ])

        await fixture.viewModel.syncNow()

        let savedProfile = await fixture.client.lastSavedProfile()
        #expect(savedProfile?.favoriteModels?.map(\.model) == ["sonnet", "opus"])
        #expect(savedProfile?.favoriteModels?.map(\.tokens) == [300, 100])
    }

    @Test("Current user favorite models are computed locally")
    func currentUserFavoriteModelsUseLocalSessions() async {
        let now = dateUTC(2026, 5, 16, 8)
        let fixture = makeFixture(enabled: true, sessions: [
            session("a", provider: .claude, at: now, tokens: 10, modelName: "haiku"),
            session("b", provider: .claude, at: now, tokens: 40, modelName: "sonnet"),
        ])

        #expect(fixture.viewModel.currentUserFavoriteModels.map(\.model) == ["sonnet", "haiku"])
    }

    @Test("Setting recent status saves profile and updates visible current user score")
    func setRecentStatusUpdatesVisibleScore() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        let periodKey = LeaderboardPeriodCalculator.window(for: .day, now: now).periodKey
        await fixture.client.setScores([
            periodKey: [
                LeaderboardScore(
                    id: "score",
                    userHash: "userhash",
                    metric: .tokensWithCache,
                    period: .day,
                    periodKey: periodKey,
                    score: 42,
                    rank: 1,
                    nickname: "Ada",
                    avatarSeed: "avatar-ada",
                    updatedAt: now
                ),
            ],
        ])

        await fixture.viewModel.loadScores(
            metric: .tokensWithCache,
            period: .day,
            now: now,
            allowsRecentDayFallback: false
        )
        await fixture.viewModel.setRecentStatus(.focused)

        #expect(fixture.preferences.leaderboardRecentStatusID == "focused")
        #expect(fixture.preferences.leaderboardRecentStatusUpdatedAt != nil)
        let savedStatusProfile = await fixture.client.lastSavedProfile()
        #expect(savedStatusProfile?.recentStatusID == "focused")
        #expect(fixture.viewModel.scores.first?.recentStatusID == "focused")

        await fixture.viewModel.clearRecentStatus()

        #expect(fixture.preferences.leaderboardRecentStatusID == "")
        #expect(fixture.preferences.leaderboardRecentStatusUpdatedAt != nil)
        let clearedStatusProfile = await fixture.client.lastSavedProfile()
        #expect(clearedStatusProfile?.recentStatusID == nil)
        #expect(fixture.viewModel.scores.first?.recentStatusID == nil)
    }

    @Test("Setting recent status updates visible score before profile save succeeds")
    func setRecentStatusUpdatesVisibleScoreBeforeSaveSucceeds() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        let periodKey = LeaderboardPeriodCalculator.window(for: .day, now: now).periodKey
        await fixture.client.setScores([
            periodKey: [
                LeaderboardScore(
                    id: "score",
                    userHash: "userhash",
                    metric: .tokensWithCache,
                    period: .day,
                    periodKey: periodKey,
                    score: 42,
                    rank: 1,
                    nickname: "Ada",
                    avatarSeed: "avatar-ada",
                    updatedAt: now
                ),
            ],
        ])

        await fixture.viewModel.loadScores(
            metric: .tokensWithCache,
            period: .day,
            now: now,
            allowsRecentDayFallback: false
        )
        await fixture.viewModel.setRecentStatus(.focused)
        await fixture.client.setAccountState(.noAccount)

        await fixture.viewModel.setRecentStatus(.shipping)

        #expect(fixture.preferences.leaderboardRecentStatusID == "shipping")
        #expect(fixture.viewModel.scores.first?.recentStatusID == "shipping")
        #expect(await fixture.client.lastSavedProfile()?.recentStatusID == "focused")
        #expect(fixture.preferences.leaderboardLastSyncError == "Sign in to iCloud")
    }


    @Test("Silent sync respects the minimum upload interval")
    func silentSyncMinimumInterval() async {
        let fixture = makeFixture(enabled: true, silentSyncMinimumInterval: 1_800)
        await fixture.localStore.writeSyncState(LeaderboardLocalSyncState(
            lastFingerprint: "old",
            lastUploadedAt: Date(),
            lastSubmittedPeriodKeys: []
        ))

        await fixture.viewModel.syncIfDue(force: false)

        #expect(await fixture.client.submittedCount() == 0)
    }

    @Test("Daily scores fall back to the most recent UTC day with results")
    func dailyScoresFallbackToRecentDay() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        let previousDayKey = LeaderboardPeriodCalculator.window(
            for: .day,
            now: now.addingTimeInterval(-86_400)
        ).periodKey
        await fixture.client.setScores([
            previousDayKey: [
                LeaderboardScore(
                    id: "score",
                    userHash: "userhash",
                    metric: .tokensWithCache,
                    period: .day,
                    periodKey: previousDayKey,
                    score: 42,
                    rank: 1,
                    nickname: "Ada",
                    avatarSeed: "avatar-ada",
                    updatedAt: now
                ),
            ],
        ])

        await fixture.viewModel.loadScores(metric: .tokensWithCache, period: .day, now: now)

        #expect(fixture.viewModel.lastLoadedPeriodKey == previousDayKey)
        #expect(fixture.viewModel.scores.count == 1)
        #expect(fixture.viewModel.scoreEmptyMessage == nil)
        #expect(await fixture.client.fetchedPeriodKeys() == ["2026-05-16", "2026-05-15"])
    }

    @Test("Daily scores can load the selected UTC day without recent fallback")
    func dailyScoresLoadSelectedDayWithoutFallback() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        let previousDay = now.addingTimeInterval(-86_400)
        let previousDayKey = LeaderboardPeriodCalculator.window(for: .day, now: previousDay).periodKey
        await fixture.client.setScores([
            previousDayKey: [
                LeaderboardScore(
                    id: "score",
                    userHash: "userhash",
                    metric: .tokensWithCache,
                    period: .day,
                    periodKey: previousDayKey,
                    score: 42,
                    rank: 1,
                    nickname: "Ada",
                    avatarSeed: "avatar-ada",
                    updatedAt: now
                ),
            ],
        ])

        await fixture.viewModel.loadScores(
            metric: .tokensWithCache,
            period: .day,
            now: now,
            allowsRecentDayFallback: false
        )

        #expect(fixture.viewModel.lastLoadedPeriodKey == "2026-05-16")
        #expect(fixture.viewModel.scores.isEmpty)
        #expect(fixture.viewModel.scoreEmptyMessage == "No scores for this UTC day yet.")
        #expect(await fixture.client.fetchedPeriodKeys() == ["2026-05-16"])
    }

    @Test("Fresh cached scores render without hitting CloudKit")
    func freshCachedScoresRenderWithoutCloudKit() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        let periodKey = LeaderboardPeriodCalculator.window(for: .allTime, now: now).periodKey
        let cached = [
            score(id: "cached", userHash: "cachedhash", rank: 1, nickname: "Cached", value: 99, now: now),
        ]
        await fixture.localStore.writeScores(
            cached,
            for: LeaderboardScoresCacheKey(metric: .tokensWithCache, period: .allTime, periodKey: periodKey, limit: 100),
            savedAt: Date()
        )

        await fixture.viewModel.loadScores(metric: .tokensWithCache, period: .allTime, now: now)

        #expect(fixture.viewModel.scores == cached)
        #expect(await fixture.client.fetchedPeriodKeys().isEmpty)
    }

    @Test("Fresh cached scores normalize skipped ranks without hitting CloudKit")
    func freshCachedScoresNormalizeSkippedRanks() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        let periodKey = LeaderboardPeriodCalculator.window(for: .day, now: now).periodKey
        await fixture.localStore.writeScores(
            [
                score(id: "cached-a", userHash: "cached-a", rank: 2, nickname: "Cached A", value: 300, now: now),
                score(id: "cached-b", userHash: "cached-b", rank: 6, nickname: "Cached B", value: 200, now: now),
            ],
            for: LeaderboardScoresCacheKey(metric: .tokensWithCache, period: .day, periodKey: periodKey, limit: 100),
            savedAt: Date()
        )

        await fixture.viewModel.loadScores(metric: .tokensWithCache, period: .day, now: now)

        #expect(fixture.viewModel.scores.map(\.id) == ["cached-a", "cached-b"])
        #expect(fixture.viewModel.scores.compactMap(\.rank) == [1, 2])
        #expect(await fixture.client.fetchedPeriodKeys().isEmpty)
    }

    @Test("Stale cached scores stay visible while CloudKit refreshes")
    func staleCachedScoresRefreshFromCloudKit() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        let key = LeaderboardScoresCacheKey(metric: .tokensWithCache, period: .allTime, periodKey: "all", limit: 100)
        await fixture.localStore.writeScores(
            [score(id: "cached", userHash: "cachedhash", rank: 1, nickname: "Cached", value: 99, now: now)],
            for: key,
            savedAt: Date().addingTimeInterval(-7_200)
        )
        await fixture.client.setScores([
            "all": [
                score(id: "fresh", userHash: "freshhash", rank: 1, nickname: "Fresh", value: 200, now: now),
            ],
        ])

        await fixture.viewModel.loadScores(metric: .tokensWithCache, period: .allTime, now: now)

        #expect(fixture.viewModel.scores.first?.id == "fresh")
        #expect(await fixture.client.fetchedPeriodKeys() == ["all"])
    }

    @Test("Force refresh bypasses a fresh score cache")
    func forceRefreshBypassesFreshCache() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        await fixture.localStore.writeScores(
            [score(id: "cached", userHash: "cachedhash", rank: 1, nickname: "Cached", value: 99, now: now)],
            for: LeaderboardScoresCacheKey(metric: .tokensWithCache, period: .allTime, periodKey: "all", limit: 100),
            savedAt: Date()
        )
        await fixture.client.setScores([
            "all": [
                score(id: "fresh", userHash: "freshhash", rank: 1, nickname: "Fresh", value: 200, now: now),
            ],
        ])

        await fixture.viewModel.loadScores(metric: .tokensWithCache, period: .allTime, now: now, forceRefresh: true)

        #expect(fixture.viewModel.scores.first?.id == "fresh")
        #expect(await fixture.client.fetchedPeriodKeys() == ["all"])
    }

    @Test("Combined leaderboard refresh uploads current scores and reloads visible scores")
    func combinedRefreshUploadsAndFetches() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        await fixture.client.setScores([
            "all": [
                score(id: "fresh", userHash: "freshhash", rank: 1, nickname: "Fresh", value: 200, now: now),
            ],
        ])

        await fixture.viewModel.syncAndRefreshScores(metric: .tokensWithCache, period: .allTime, now: now)

        #expect(await fixture.client.submittedCount() > 0)
        #expect(await fixture.client.submittedHistoryCount() > 0)
        #expect(fixture.viewModel.scores.first?.id == "fresh")
        #expect(await fixture.client.fetchedPeriodKeys() == ["all"])
    }

    @Test("Global realtime notification debounces then force-refreshes visible scores")
    func globalRealtimeNotificationRefreshesVisibleScores() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        let scope = LeaderboardRealtimeScope.liveScope(metric: .tokensWithCache, period: .allTime, now: now)
        await fixture.client.setScores([
            "all": [
                score(id: "initial", userHash: "initialhash", rank: 1, nickname: "Initial", value: 100, now: now),
            ],
        ])

        await fixture.viewModel.loadScores(metric: .tokensWithCache, period: .allTime, now: now)
        await fixture.viewModel.activateRealtime(scope: scope)
        await fixture.client.setScores([
            "all": [
                score(id: "fresh", userHash: "freshhash", rank: 1, nickname: "Fresh", value: 300, now: now),
            ],
        ])

        fixture.viewModel.handleRealtimeNotification(LeaderboardRealtimeNotification(
            subscriptionID: LeaderboardRealtimeNotification.globalSubscriptionID,
            receivedAt: now
        ))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(fixture.viewModel.realtimeStatus == .live)
        #expect(fixture.viewModel.scores.first?.id == "fresh")
        #expect(await fixture.client.fetchedPeriodKeys() == ["all", "all"])
        #expect(await fixture.realtimeCloud.ensureCount() == 1)
        #expect(await fixture.realtimeCloud.cleanupKeepIDs() == [[LeaderboardRealtimeNotification.globalSubscriptionID]])
    }

    @Test("Legacy non-current realtime notification only marks scoped pending")
    func legacyNonCurrentRealtimeNotificationMarksPending() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        let currentScope = LeaderboardRealtimeScope.liveScope(metric: .tokensWithCache, period: .allTime, now: now)
        let pendingScope = LeaderboardRealtimeScope.liveScope(metric: .tokensWithCache, period: .day, now: now)

        await fixture.viewModel.loadScores(metric: .tokensWithCache, period: .allTime, now: now)
        await fixture.client.clearFetches()
        await fixture.viewModel.activateRealtime(scope: currentScope)

        fixture.viewModel.handleRealtimeNotification(LeaderboardRealtimeNotification(subscriptionID: pendingScope.subscriptionID, receivedAt: now))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(fixture.viewModel.realtimeStatus == .live)
        #expect(await fixture.client.fetchedPeriodKeys().isEmpty)
        #expect(await fixture.localStore.readRealtimeState().pendingScopes == [pendingScope])
    }

    @Test("Global realtime notification while inactive refreshes on next activation")
    func inactiveGlobalRealtimeNotificationRefreshesOnNextActivation() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        let scope = LeaderboardRealtimeScope.liveScope(metric: .tokensWithCache, period: .allTime, now: now)
        await fixture.client.setScores([
            "all": [
                score(id: "initial", userHash: "initialhash", rank: 1, nickname: "Initial", value: 100, now: now),
            ],
        ])

        await fixture.viewModel.loadScores(metric: .tokensWithCache, period: .allTime, now: now)
        await fixture.client.clearFetches()
        fixture.viewModel.handleRealtimeNotification(LeaderboardRealtimeNotification(
            subscriptionID: LeaderboardRealtimeNotification.globalSubscriptionID,
            receivedAt: now
        ))
        try? await Task.sleep(for: .milliseconds(50))

        let pendingState = await fixture.localStore.readRealtimeState()
        #expect(pendingState.hasPendingGlobalChange)
        #expect(await fixture.client.fetchedPeriodKeys().isEmpty)

        await fixture.client.setScores([
            "all": [
                score(id: "fresh", userHash: "freshhash", rank: 1, nickname: "Fresh", value: 300, now: now),
            ],
        ])
        await fixture.viewModel.activateRealtime(scope: scope)

        #expect(fixture.viewModel.realtimeStatus == .live)
        #expect(fixture.viewModel.scores.first?.id == "fresh")
        #expect(await fixture.client.fetchedPeriodKeys() == ["all"])
        #expect(!(await fixture.localStore.readRealtimeState()).hasPendingGlobalChange)
    }

    @Test("Historical day does not register a realtime subscription")
    func historicalDayUsesCacheStatus() async {
        let fixture = makeFixture(enabled: true)
        let current = dateUTC(2026, 5, 16, 8)
        let historicalWindow = LeaderboardPeriodCalculator.window(
            for: .day,
            now: current.addingTimeInterval(-2 * 86_400)
        )
        let scope = LeaderboardRealtimeScope.liveScope(
            metric: .tokensWithCache,
            period: .day,
            requestedWindow: historicalWindow,
            now: current
        )

        await fixture.viewModel.activateRealtime(scope: scope)

        #expect(scope == nil)
        #expect(fixture.viewModel.realtimeStatus == .historicalCache)
        #expect(await fixture.realtimeCloud.ensureCount() == 0)
    }

    @Test("Realtime registration failure does not block manual refresh")
    func realtimeFailureDoesNotBlockManualRefresh() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        let scope = LeaderboardRealtimeScope.liveScope(metric: .tokensWithCache, period: .allTime, now: now)
        await fixture.realtimeCloud.setEnsureError(LeaderboardCloudError.missingEntitlement("Missing push entitlement."))
        await fixture.client.setScores([
            "all": [
                score(id: "fresh", userHash: "freshhash", rank: 1, nickname: "Fresh", value: 300, now: now),
            ],
        ])

        await fixture.viewModel.activateRealtime(scope: scope)
        await fixture.viewModel.syncAndRefreshScores(metric: .tokensWithCache, period: .allTime, now: now)

        if case .unavailable = fixture.viewModel.realtimeStatus {
            #expect(true)
        } else {
            Issue.record("Expected realtime unavailable status")
        }
        #expect(await fixture.client.submittedCount() > 0)
        #expect(fixture.viewModel.scores.first?.id == "fresh")
    }

    @Test("Sync and realtime status text stay separate")
    func syncAndRealtimeStatusTextStaySeparate() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        let scope = LeaderboardRealtimeScope.liveScope(metric: .tokensWithCache, period: .allTime, now: now)
        await fixture.realtimeCloud.setEnsureError(LeaderboardCloudError.missingEntitlement("Missing push entitlement."))

        await fixture.viewModel.activateRealtime(scope: scope)

        #expect(fixture.viewModel.leaderboardStatusText == "Ready")
        #expect(fixture.viewModel.leaderboardRealtimeStatusText == "Live unavailable")
    }

    @Test("CloudKit score failure keeps cached scores visible")
    func scoreFailureKeepsCachedScoresVisible() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        let cached = [score(id: "cached", userHash: "cachedhash", rank: 1, nickname: "Cached", value: 99, now: now)]
        await fixture.localStore.writeScores(
            cached,
            for: LeaderboardScoresCacheKey(metric: .tokensWithCache, period: .allTime, periodKey: "all", limit: 100),
            savedAt: Date().addingTimeInterval(-7_200)
        )
        await fixture.client.setFetchScoresError(LeaderboardCloudError.cloudKit("Network unavailable."))

        await fixture.viewModel.loadScores(metric: .tokensWithCache, period: .allTime, now: now)

        #expect(fixture.viewModel.scores == cached)
        #expect(fixture.viewModel.scoreError == nil)
    }

    @Test("Daily scores show a recent-days empty message when no fallback exists")
    func dailyScoresEmptyMessage() async {
        let fixture = makeFixture(enabled: true)

        await fixture.viewModel.loadScores(metric: .tokensWithCache, period: .day, now: dateUTC(2026, 5, 16, 8))

        #expect(fixture.viewModel.lastLoadedPeriodKey == "2026-05-16")
        #expect(fixture.viewModel.scores.isEmpty)
        #expect(fixture.viewModel.scoreEmptyMessage == "No daily scores in the last 7 UTC days yet.")
        #expect(await fixture.client.fetchedPeriodKeys().count == 7)
    }

    @Test("Enabled leaderboards generate a local avatar seed and bind the iCloud user hash")
    func enabledGeneratesAvatarSeedAndBindsUserHash() async {
        let fixture = makeFixture(enabled: true)

        await fixture.viewModel.checkAccountStatus()

        #expect(fixture.preferences.leaderboardAvatarSeed.isEmpty == false)
        #expect(fixture.preferences.leaderboardProfileUserHash == "userhash")
        #expect(fixture.viewModel.currentUserHash == "userhash")
    }

    @Test("Remote profile fills an empty local nickname")
    func remoteProfileFillsEmptyNickname() async {
        let fixture = makeFixture(enabled: true)
        fixture.preferences.leaderboardNickname = ""
        await fixture.client.setProfile(
            userHash: "userhash",
            nickname: "Remote Ada",
            avatarSeed: "avatar-remote",
            historyStartMonthKey: "2026-05"
        )

        await fixture.viewModel.checkAccountStatus()

        #expect(fixture.preferences.leaderboardNickname == "Remote Ada")
        #expect(fixture.preferences.leaderboardAvatarSeed == "avatar-remote")
        #expect(fixture.viewModel.syncStatus == .idle)
    }

    @Test("Local profile nickname wins over a remote nickname")
    func localNicknameWinsOverRemoteNickname() async {
        let fixture = makeFixture(enabled: true)
        fixture.preferences.leaderboardNickname = "Local Ada"
        await fixture.client.setProfile(
            userHash: "userhash",
            nickname: "Remote Ada",
            avatarSeed: "avatar-remote",
            historyStartMonthKey: "2026-05"
        )

        await fixture.viewModel.checkAccountStatus()

        #expect(fixture.preferences.leaderboardNickname == "Local Ada")
        #expect(fixture.preferences.leaderboardAvatarSeed == "avatar-remote")
    }

    @Test("Silent automatic sync skips upload when another variant holds the lease")
    func silentSyncSkipsWhenLeaseIsDenied() async {
        let fixture = makeFixture(enabled: true)
        let now = Date()
        await fixture.syncLease.setDecision(.denied(active: LeaderboardSyncLease(
            userHash: "userhash",
            ownerID: "full-owner",
            variant: .full,
            priority: 100,
            acquiredAt: now,
            expiresAt: now.addingTimeInterval(120)
        )))

        fixture.viewModel.start()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(await fixture.syncLease.requestCount() == 1)
        #expect(await fixture.client.submittedCount() == 0)
    }

    @Test("Randomizing avatar updates local seed and immediately saves the profile when available")
    func randomizeAvatarSavesProfile() async {
        let fixture = makeFixture(enabled: true)
        fixture.preferences.leaderboardAvatarSeed = "avatar-old"

        await fixture.viewModel.randomizeAvatar()

        #expect(fixture.preferences.leaderboardAvatarSeed != "avatar-old")
        #expect(await fixture.client.savedProfileCount() == 1)
        #expect(await fixture.client.lastSavedProfile()?.avatarSeed == fixture.preferences.leaderboardAvatarSeed)
        #expect(fixture.preferences.leaderboardProfileUserHash == "userhash")
    }

    @Test("Randomizing avatar with unavailable iCloud keeps the local seed for a later sync")
    func randomizeAvatarUnavailableICloudStaysLocal() async {
        let fixture = makeFixture(enabled: true)
        fixture.preferences.leaderboardAvatarSeed = "avatar-old"
        await fixture.client.setAccountState(.noAccount)

        await fixture.viewModel.randomizeAvatar()

        #expect(fixture.preferences.leaderboardAvatarSeed != "avatar-old")
        #expect(await fixture.client.savedProfileCount() == 0)
        #expect(fixture.preferences.leaderboardLastSyncError == "Sign in to iCloud")
    }

    @Test("Randomizing avatar without a nickname stays local and asks for a nickname")
    func randomizeAvatarWithoutNicknameStaysLocal() async {
        let fixture = makeFixture(enabled: true)
        fixture.preferences.leaderboardNickname = ""
        fixture.preferences.leaderboardAvatarSeed = "avatar-old"

        await fixture.viewModel.randomizeAvatar()

        #expect(fixture.preferences.leaderboardAvatarSeed != "avatar-old")
        #expect(await fixture.client.savedProfileCount() == 0)
        #expect(fixture.viewModel.syncStatus == .needsNickname)
    }

    @Test("Current user score is matched by iCloud user hash instead of nickname")
    func currentUserScoreUsesUserHash() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        await fixture.viewModel.checkAccountStatus()
        await fixture.client.setScores([
            "all": [
                score(id: "score-a", userHash: "otherhash", rank: 1, nickname: "Ada", value: 200, now: now),
                score(id: "score-b", userHash: "userhash", rank: 2, nickname: "Not Ada", value: 150, now: now),
            ],
        ])

        await fixture.viewModel.loadScores(metric: .tokensWithCache, period: .allTime, now: now)

        #expect(fixture.viewModel.currentUserScore?.rank == 2)
        #expect(fixture.viewModel.currentUserScore?.nickname == "Not Ada")
    }

    @Test("Remote daily history fetches 7 windows oldest to current")
    func remoteDailyHistoryWindowOrder() async {
        let fixture = makeFixture(enabled: true)

        await fixture.viewModel.loadScoreHistory(
            userHash: "otherhash",
            metric: .tokensWithCache,
            period: .day,
            now: dateUTC(2026, 5, 16, 8)
        )

        #expect(await fixture.client.fetchedHistoryPeriodKeys() == [
            "2026-05-10",
            "2026-05-11",
            "2026-05-12",
            "2026-05-13",
            "2026-05-14",
            "2026-05-15",
            "2026-05-16",
        ])
        #expect(fixture.viewModel.selectedUserHistory.count == 7)
    }

    @Test("Remote history fills missing records with zero")
    func remoteHistoryFillsMissingRecordsWithZero() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        await fixture.client.setHistory([
            "2026-05-15": 42_000,
        ])

        await fixture.viewModel.loadScoreHistory(
            userHash: "otherhash",
            metric: .tokensWithCache,
            period: .day,
            now: now
        )

        let valuesByKey = Dictionary(uniqueKeysWithValues: fixture.viewModel.selectedUserHistory.map { ($0.periodKey, $0.score) })
        #expect(valuesByKey["2026-05-14"] == 0)
        #expect(valuesByKey["2026-05-15"] == 42_000)
        #expect(valuesByKey["2026-05-16"] == 0)
    }

    @Test("Current user history is computed locally without CloudKit history fetch")
    func currentUserHistoryUsesLocalTimeline() async {
        let now = dateUTC(2026, 5, 16, 8)
        let sessions = [
            session(
                "timeline",
                provider: .claude,
                at: now,
                tokens: 0,
                timeline: [
                    ModelBucket(model: "model", start: dateUTC(2026, 5, 15, 22), usage: TokenUsage(inputTokens: 100)),
                    ModelBucket(model: "model", start: dateUTC(2026, 5, 16, 1), usage: TokenUsage(inputTokens: 250)),
                ]
            )
        ]
        let fixture = makeFixture(enabled: true, sessions: sessions)
        await fixture.viewModel.checkAccountStatus()

        await fixture.viewModel.loadScoreHistory(
            userHash: "userhash",
            metric: .tokensWithCache,
            period: .day,
            now: now
        )

        #expect(await fixture.client.fetchedHistoryPeriodKeys().isEmpty)
        let valuesByKey = Dictionary(uniqueKeysWithValues: fixture.viewModel.selectedUserHistory.map { ($0.periodKey, $0.score) })
        #expect(valuesByKey["2026-05-15"] == 100)
        #expect(valuesByKey["2026-05-16"] == 250)
    }

    @Test("Remote all-time history uses profile start month")
    func remoteAllTimeHistoryUsesProfileStartMonth() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        await fixture.client.setProfile(userHash: "otherhash", historyStartMonthKey: "2026-03")
        await fixture.client.setHistory([
            "2026-03": 10,
            "2026-05": 30,
        ])

        await fixture.viewModel.loadScoreHistory(
            userHash: "otherhash",
            metric: .tokensWithCache,
            period: .allTime,
            now: now
        )

        #expect(await fixture.client.fetchedHistoryPeriodKeys() == ["2026-03", "2026-04", "2026-05"])
        let valuesByKey = Dictionary(uniqueKeysWithValues: fixture.viewModel.selectedUserHistory.map { ($0.periodKey, $0.score) })
        #expect(valuesByKey["2026-03"] == 10)
        #expect(valuesByKey["2026-04"] == 0)
        #expect(valuesByKey["2026-05"] == 30)
    }

    @Test("Remote all-time history reports missing profile metadata")
    func remoteAllTimeHistoryWithoutMetadataShowsUnavailable() async {
        let fixture = makeFixture(enabled: true)

        await fixture.viewModel.loadScoreHistory(
            userHash: "otherhash",
            metric: .tokensWithCache,
            period: .allTime,
            now: dateUTC(2026, 5, 16, 8)
        )

        #expect(await fixture.client.fetchedHistoryPeriodKeys().isEmpty)
        #expect(fixture.viewModel.selectedUserHistoryError == "This user has not uploaded local history yet.")
    }

    @Test("Selection resolver keeps preferred user before falling back")
    func selectionResolverKeepsPreferredUserBeforeFallback() {
        let now = dateUTC(2026, 5, 16, 8)
        let scores = [
            score(id: "score-a", userHash: "otherhash", rank: 1, nickname: "Ada", value: 200, now: now),
            score(id: "score-b", userHash: "userhash", rank: 2, nickname: "Not Ada", value: 150, now: now),
        ]

        #expect(LeaderboardSelectionResolver.selectedScore(
            preferredUserHash: "otherhash",
            currentUserHash: "userhash",
            scores: scores
        )?.userHash == "otherhash")
        #expect(LeaderboardSelectionResolver.selectedScore(
            preferredUserHash: "missing",
            currentUserHash: "userhash",
            scores: scores
        )?.userHash == "userhash")
        #expect(LeaderboardSelectionResolver.selectedScore(
            preferredUserHash: "missing",
            currentUserHash: "also-missing",
            scores: scores
        )?.userHash == "otherhash")
    }

    private func makeFixture(enabled: Bool,
                             sessions: [Session]? = nil,
                             scoreCacheTTL: TimeInterval = 3_600,
                             silentSyncDebounceInterval: TimeInterval = 0,
                             silentSyncMinimumInterval: TimeInterval = 0,
                             realtimeRefreshDebounceInterval: TimeInterval = 0) -> Fixture {
        let suiteName = "com.claudestats.tests.leaderboards.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = Preferences(defaults: defaults)
        preferences.leaderboardsEnabled = enabled
        preferences.leaderboardNickname = "Ada"

        let store = SessionStore(registry: ProviderRegistry(pricing: TestPricing.table), pricing: TestPricing.table)
        let now = Date()
        store.loadPreviewSessions(sessions ?? [
            session("a", provider: .claude, at: now, tokens: 100),
            session("b", provider: .codex, at: now.addingTimeInterval(60), tokens: 200),
        ])
        let client = FakeLeaderboardClient()
        let localStore = FakeLeaderboardLocalStore()
        let realtimeCloud = FakeLeaderboardRealtimeCloudService()
        let syncLease = FakeLeaderboardSyncLease()
        let notificationRegistrar = FakeLeaderboardRemoteNotificationRegistrar()
        let viewModel = LeaderboardSyncViewModel(
            preferences: preferences,
            store: store,
            client: client,
            localStore: localStore,
            refreshBeforeSync: false,
            scoreCacheTTL: scoreCacheTTL,
            silentSyncDebounceInterval: silentSyncDebounceInterval,
            silentSyncMinimumInterval: silentSyncMinimumInterval,
            realtimeCoordinator: LeaderboardRealtimeCoordinator(cloud: realtimeCloud, localStore: localStore),
            syncLease: syncLease,
            syncLeasePolicy: LeaderboardSyncLeasePolicy(
                variant: .full,
                ownerID: "test-owner",
                priority: 100,
                duration: 120
            ),
            remoteNotificationRegistrar: notificationRegistrar,
            realtimeRefreshDebounceInterval: realtimeRefreshDebounceInterval
        )
        return Fixture(
            preferences: preferences,
            viewModel: viewModel,
            client: client,
            localStore: localStore,
            realtimeCloud: realtimeCloud,
            syncLease: syncLease,
            notificationRegistrar: notificationRegistrar
        )
    }

    private func session(_ id: String,
                         provider: ProviderKind,
                         at date: Date,
                         tokens: Int,
                         modelName: String = "model",
                         timeline: [ModelBucket] = []) -> Session {
        let usage = TokenUsage(inputTokens: tokens, outputTokens: 0, cacheReadTokens: 0,
                               cacheCreation5mTokens: 0, cacheCreation1hTokens: 0)
        let stats = SessionStats(
            title: id,
            messageCount: 1,
            firstActivity: date,
            lastActivity: date,
            models: [ModelUsage(model: modelName, messageCount: 1, usage: usage, pricing: TestPricing.table)],
            timeline: timeline
        )
        return Session(id: id, externalID: id, provider: provider, projectDirectoryName: "-p",
                       filePath: "/\(id).jsonl", cwd: nil, lastModified: date, fileSize: 1, stats: stats)
    }

    private func dateUTC(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func score(id: String,
                       userHash: String,
                       rank: Int,
                       nickname: String,
                       value: Int64,
                       metric: LeaderboardMetric = .tokensWithCache,
                       period: LeaderboardPeriod = .allTime,
                       periodKey: String = "all",
                       now: Date) -> LeaderboardScore {
        LeaderboardScore(
            id: id,
            userHash: userHash,
            metric: metric,
            period: period,
            periodKey: periodKey,
            score: value,
            rank: rank,
            nickname: nickname,
            avatarSeed: "avatar-\(id)",
            updatedAt: now
        )
    }

    private struct Fixture {
        let preferences: Preferences
        let viewModel: LeaderboardSyncViewModel
        let client: FakeLeaderboardClient
        let localStore: FakeLeaderboardLocalStore
        let realtimeCloud: FakeLeaderboardRealtimeCloudService
        let syncLease: FakeLeaderboardSyncLease
        let notificationRegistrar: FakeLeaderboardRemoteNotificationRegistrar
    }
}

private actor FakeLeaderboardClient: LeaderboardCloudServicing {
    private var state: LeaderboardCloudAccountState = .available
    private var userHash = "userhash"
    private var submitted: [LeaderboardSubmission] = []
    private var submittedHistory: [LeaderboardHistorySubmission] = []
    private var savedProfiles: [LeaderboardProfile] = []
    private var profilesByHash: [String: LeaderboardProfile] = [:]
    private var scoresByPeriodKey: [String: [LeaderboardScore]] = [:]
    private var historyByPeriodKey: [String: Int64] = [:]
    private var fetchedKeys: [String] = []
    private var fetchedHistoryKeys: [String] = []
    private var fetchScoresError: LeaderboardCloudError?

    func setAccountState(_ state: LeaderboardCloudAccountState) {
        self.state = state
    }

    func submittedCount() -> Int {
        submitted.count
    }

    func submittedHistoryCount() -> Int {
        submittedHistory.count
    }

    func clearSubmissions() {
        submitted = []
        submittedHistory = []
        savedProfiles = []
    }

    func savedProfileCount() -> Int {
        savedProfiles.count
    }

    func lastSavedProfile() -> LeaderboardProfile? {
        savedProfiles.last
    }

    func setScores(_ scoresByPeriodKey: [String: [LeaderboardScore]]) {
        self.scoresByPeriodKey = scoresByPeriodKey
    }

    func setFetchScoresError(_ error: LeaderboardCloudError?) {
        fetchScoresError = error
    }

    func setHistory(_ historyByPeriodKey: [String: Int64]) {
        self.historyByPeriodKey = historyByPeriodKey
    }

    func setProfile(userHash: String,
                    nickname: String = "Remote User",
                    avatarSeed: String? = nil,
                    historyStartMonthKey: String?) {
        profilesByHash[userHash] = LeaderboardProfile(
            userHash: userHash,
            nickname: nickname,
            avatarSeed: avatarSeed ?? "avatar-\(userHash)",
            historyStartMonthKey: historyStartMonthKey,
            recentStatusID: nil,
            recentStatusUpdatedAt: nil,
            updatedAt: Date()
        )
    }

    func fetchedPeriodKeys() -> [String] {
        fetchedKeys
    }

    func fetchedHistoryPeriodKeys() -> [String] {
        fetchedHistoryKeys
    }

    func clearFetches() {
        fetchedKeys = []
        fetchedHistoryKeys = []
    }

    func accountState() async -> LeaderboardCloudAccountState {
        state
    }

    func currentUserHash() async throws -> String {
        switch state {
        case .available:
            return userHash
        case .noAccount:
            throw LeaderboardCloudError.noAccount
        case .restricted:
            throw LeaderboardCloudError.restricted
        case .unknown, .unavailable:
            throw LeaderboardCloudError.cloudKit(state.displayText)
        }
    }

    func saveProfile(_ profile: LeaderboardProfileDraft) async throws -> LeaderboardProfile {
        let saved = LeaderboardProfile(
            userHash: try await currentUserHash(),
            nickname: profile.nickname,
            avatarSeed: profile.avatarSeed,
            historyStartMonthKey: profile.historyStartMonthKey,
            favoriteModels: profile.favoriteModels,
            recentStatusID: profile.recentStatusID,
            recentStatusUpdatedAt: profile.recentStatusUpdatedAt,
            updatedAt: profile.updatedAt
        )
        savedProfiles.append(saved)
        profilesByHash[saved.userHash] = saved
        return saved
    }

    func fetchProfile(userHash: String) async throws -> LeaderboardProfile? {
        profilesByHash[userHash]
    }

    func submit(_ submissions: [LeaderboardSubmission],
                historySubmissions: [LeaderboardHistorySubmission],
                profile: LeaderboardProfileDraft) async throws -> LeaderboardProfile {
        submitted.append(contentsOf: submissions)
        submittedHistory.append(contentsOf: historySubmissions)
        return try await saveProfile(profile)
    }

    func fetchScores(metric: LeaderboardMetric,
                     period: LeaderboardPeriod,
                     periodKey: String,
                     limit: Int) async throws -> [LeaderboardScore] {
        if let fetchScoresError {
            throw fetchScoresError
        }
        fetchedKeys.append(periodKey)
        return scoresByPeriodKey[periodKey] ?? []
    }

    func fetchScoreHistory(userHash: String,
                           metric: LeaderboardMetric,
                           period: LeaderboardPeriod,
                           windows: [LeaderboardPeriodWindow]) async throws -> [LeaderboardScoreHistoryPoint] {
        fetchedHistoryKeys.append(contentsOf: windows.map(\.periodKey))
        return windows.map { window in
            return LeaderboardScoreHistoryPoint(
                metric: metric,
                period: window.period,
                window: window,
                score: historyByPeriodKey[window.periodKey] ?? 0,
                updatedAt: nil
            )
        }
    }
}

private actor FakeLeaderboardSyncLease: LeaderboardSyncLeasing {
    private var nextDecision: LeaderboardSyncLeaseDecision?
    private var requests: [LeaderboardSyncLeaseRequest] = []

    func setDecision(_ decision: LeaderboardSyncLeaseDecision?) {
        nextDecision = decision
    }

    func requestCount() -> Int {
        requests.count
    }

    func acquire(_ request: LeaderboardSyncLeaseRequest) async throws -> LeaderboardSyncLeaseDecision {
        requests.append(request)
        return nextDecision ?? .acquired(request.lease)
    }
}

private actor FakeLeaderboardLocalStore: LeaderboardLocalStoring {
    private var scoresByKey: [LeaderboardScoresCacheKey: LeaderboardCachedScores] = [:]
    private var historyByKey: [LeaderboardHistoryCacheKey: LeaderboardCachedHistory] = [:]
    private var profilesByHash: [String: LeaderboardCachedProfile] = [:]
    private var syncState: LeaderboardLocalSyncState = .empty
    private var realtimeState: LeaderboardRealtimeState = .empty

    func readScores(for key: LeaderboardScoresCacheKey) async -> LeaderboardCachedScores? {
        scoresByKey[key]
    }

    func writeScores(_ scores: [LeaderboardScore], for key: LeaderboardScoresCacheKey, savedAt: Date) async {
        scoresByKey[key] = LeaderboardCachedScores(key: key, savedAt: savedAt, scores: scores)
    }

    func readHistory(for key: LeaderboardHistoryCacheKey) async -> LeaderboardCachedHistory? {
        historyByKey[key]
    }

    func writeHistory(_ points: [LeaderboardScoreHistoryPoint], for key: LeaderboardHistoryCacheKey, savedAt: Date) async {
        historyByKey[key] = LeaderboardCachedHistory(key: key, savedAt: savedAt, points: points)
    }

    func readProfile(userHash: String) async -> LeaderboardCachedProfile? {
        profilesByHash[userHash]
    }

    func writeProfile(_ profile: LeaderboardProfile, savedAt: Date) async {
        let key = LeaderboardProfileCacheKey(userHash: profile.userHash)
        profilesByHash[profile.userHash] = LeaderboardCachedProfile(key: key, savedAt: savedAt, profile: profile)
    }

    func readSyncState() async -> LeaderboardLocalSyncState {
        syncState
    }

    func writeSyncState(_ state: LeaderboardLocalSyncState) async {
        syncState = state
    }

    func readRealtimeState() async -> LeaderboardRealtimeState {
        realtimeState
    }

    func writeRealtimeState(_ state: LeaderboardRealtimeState) async {
        realtimeState = state
    }
}

private actor FakeLeaderboardRealtimeCloudService: LeaderboardRealtimeCloudServicing {
    private var ensuredCount = 0
    private var cleanupIDs: [Set<String>] = []
    private var ensureError: Error?

    func setEnsureError(_ error: Error?) {
        ensureError = error
    }

    func ensureCount() -> Int {
        ensuredCount
    }

    func cleanupKeepIDs() -> [Set<String>] {
        cleanupIDs
    }

    func ensureSubscription() async throws {
        if let ensureError {
            throw ensureError
        }
        ensuredCount += 1
    }

    func deleteManagedSubscriptions(except subscriptionIDs: Set<String>) async {
        cleanupIDs.append(subscriptionIDs)
    }
}

@MainActor
private final class FakeLeaderboardRemoteNotificationRegistrar: LeaderboardRemoteNotificationRegistering {
    private(set) var registrationCount = 0

    func registerForLeaderboardRemoteNotifications() {
        registrationCount += 1
    }
}
