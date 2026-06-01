import CryptoKit
import Foundation

struct DailyReportGitDaySummaryCacheKey: Hashable, Sendable {
    var repoKey: String
    var projectID: String
    var day: Date
    var contentHash: String
    var inputMode: DailyReportGitSummaryInputMode
    var language: String
    var endpointIdentity: String
    var promptVersion: String

    var filename: String {
        let raw = [
            repoKey,
            projectID,
            "\(day.timeIntervalSinceReferenceDate)",
            contentHash,
            inputMode.rawValue,
            language,
            endpointIdentity,
            promptVersion,
        ].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".json"
    }
}

actor DailyReportGitDaySummaryCache {
    private let rootDirectory: URL

    init(rootDirectory: URL = DailyReportGitDaySummaryCache.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
    }

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("DailyReport", isDirectory: true)
            .appendingPathComponent("GitSummaryCache", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
    }

    func read(_ key: DailyReportGitDaySummaryCacheKey) async -> DailyReportGitDayLLMSummary? {
        let url = rootDirectory.appendingPathComponent(key.filename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try Self.decoder.decode(DailyReportGitDayLLMSummary.self, from: data)
        } catch {
            Log.git.debug("Daily report git summary cache read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func write(_ summary: DailyReportGitDayLLMSummary, for key: DailyReportGitDaySummaryCacheKey) async {
        do {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            var stored = summary
            stored.isCached = false
            let data = try Self.encoder.encode(stored)
            try data.write(to: rootDirectory.appendingPathComponent(key.filename, isDirectory: false), options: .atomic)
        } catch {
            Log.git.debug("Daily report git summary cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
