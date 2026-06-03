import Foundation

struct LeaderboardSharedPreferencesSnapshot: Codable, Equatable, Sendable {
    var leaderboardsEnabled: Bool
    var nickname: String
    var avatarSeed: String
    var profileUserHash: String
    var lastSyncedAt: Date?
    var lastSyncError: String
    var lastSubmittedPeriodKeys: [String]
}

final class LeaderboardSharedPreferencesStore: @unchecked Sendable {
    private let url: URL

    init(directory: URL? = nil) {
        let directory = directory ?? Self.defaultDirectory()
        self.url = directory.appendingPathComponent("shared-preferences.json", isDirectory: false)
    }

    func read() -> LeaderboardSharedPreferencesSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        do {
            return try decoder.decode(LeaderboardSharedPreferencesSnapshot.self, from: data)
        } catch {
            Log.network.error("Leaderboard shared preferences decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func write(_ snapshot: LeaderboardSharedPreferencesSnapshot) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.network.error("Leaderboard shared preferences write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("Leaderboards", isDirectory: true)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
