import Foundation
import Testing
@testable import ClaudeStats

@Suite("LeaderboardLocalStore")
struct LeaderboardLocalStoreTests {
    @Test("Scores, history, profiles, and sync state round-trip through JSON")
    func roundTrip() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let savedAt = Date(timeIntervalSince1970: 1_768_200_000)
        let scoreKey = LeaderboardScoresCacheKey(metric: .tokensWithCache, period: .allTime, periodKey: "all", limit: 100)
        let score = LeaderboardScore(
            id: "score",
            userHash: "userhash",
            metric: .tokensWithCache,
            period: .allTime,
            periodKey: "all",
            score: 42,
            rank: 1,
            nickname: "Ada",
            avatarSeed: "avatar",
            historyStartMonthKey: "2026-05",
            favoriteModels: [
                LeaderboardFavoriteModel(rank: 1, model: "sonnet", tokens: 42),
            ],
            recentStatusID: LeaderboardRecentStatus.celebrating.rawValue,
            recentStatusUpdatedAt: savedAt,
            updatedAt: savedAt
        )
        let historyKey = LeaderboardHistoryCacheKey(
            userHash: "userhash",
            metric: .tokensWithCache,
            period: .day,
            windowKeys: ["2026-05-15", "2026-05-16"]
        )
        let historyPoint = LeaderboardScoreHistoryPoint(
            metric: .tokensWithCache,
            period: .day,
            window: LeaderboardPeriodCalculator.window(for: .day, periodKey: "2026-05-16")!,
            score: 42,
            updatedAt: savedAt
        )
        let profile = LeaderboardProfile(
            userHash: "userhash",
            nickname: "Ada",
            avatarSeed: "avatar",
            historyStartMonthKey: "2026-05",
            favoriteModels: [
                LeaderboardFavoriteModel(rank: 1, model: "sonnet", tokens: 42),
            ],
            recentStatusID: LeaderboardRecentStatus.celebrating.rawValue,
            recentStatusUpdatedAt: savedAt,
            updatedAt: savedAt
        )
        let syncState = LeaderboardLocalSyncState(
            lastFingerprint: "fingerprint",
            lastUploadedAt: savedAt,
            lastSubmittedPeriodKeys: ["allTime:all"]
        )
        let realtimeScope = LeaderboardRealtimeScope(metric: .tokensWithCache, period: .allTime, periodKey: "all")
        let realtimeState = LeaderboardRealtimeState(
            pendingScopes: [realtimeScope],
            lastNotificationAt: savedAt
        )

        await store.writeScores([score], for: scoreKey, savedAt: savedAt)
        await store.writeHistory([historyPoint], for: historyKey, savedAt: savedAt)
        await store.writeProfile(profile, savedAt: savedAt)
        await store.writeSyncState(syncState)
        await store.writeRealtimeState(realtimeState)

        #expect(score.withRank(2).recentStatusID == LeaderboardRecentStatus.celebrating.rawValue)
        #expect(score.withRank(2).recentStatusUpdatedAt == savedAt)
        #expect(await store.readScores(for: scoreKey)?.scores == [score])
        #expect(await store.readHistory(for: historyKey)?.points == [historyPoint])
        #expect(await store.readProfile(userHash: "userhash")?.profile == profile)
        #expect(await store.readSyncState() == syncState)
        #expect(await store.readRealtimeState() == realtimeState)
    }

    @Test("Schema, key, and JSON mismatches are ignored")
    func invalidFilesAreIgnored() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = LeaderboardScoresCacheKey(metric: .tokensWithCache, period: .allTime, periodKey: "all", limit: 100)
        let scoreURL = directory
            .appendingPathComponent("scores", isDirectory: true)
            .appendingPathComponent(key.digest)
            .appendingPathExtension("json")
        try FileManager.default.createDirectory(at: scoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        try Data("""
        {"key":{"limit":100,"metric":"tokensWithCache","period":"allTime","periodKey":"all"},"payload":[],"savedAt":1768200000,"schemaVersion":999}
        """.utf8).write(to: scoreURL)
        #expect(await store.readScores(for: key) == nil)

        try Data("""
        {"key":{"limit":100,"metric":"tokensWithCache","period":"allTime","periodKey":"other"},"payload":[],"savedAt":1768200000,"schemaVersion":1}
        """.utf8).write(to: scoreURL)
        #expect(await store.readScores(for: key) == nil)

        try Data("not-json".utf8).write(to: scoreURL)
        #expect(await store.readScores(for: key) == nil)
    }

    private func makeStore() -> (LeaderboardLocalStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeaderboardLocalStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (LeaderboardLocalStore(directory: directory), directory)
    }
}
