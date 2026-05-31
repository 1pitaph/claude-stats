import CryptoKit
import Foundation

struct GitSummaryCacheKey: Hashable, Sendable {
    var repoKey: String
    var targetKind: String
    var targetID: String
    var diffHash: String
    var language: String
    var modelID: String
    var promptVersion: String
    var algorithmVersion: String

    var filename: String {
        let raw = [
            repoKey,
            targetKind,
            targetID,
            diffHash,
            language,
            modelID,
            promptVersion,
            algorithmVersion,
        ].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".json"
    }
}

actor GitSummaryCache {
    private let rootDirectory: URL

    init(rootDirectory: URL = GitSummaryCache.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
    }

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("GitSummaryCache", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
    }

    func read(_ key: GitSummaryCacheKey) async -> GitAISummaryResult? {
        let url = rootDirectory.appendingPathComponent(key.filename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try Self.decoder.decode(GitAISummaryResult.self, from: data)
        } catch {
            Log.git.debug("Git summary cache read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func write(_ result: GitAISummaryResult, for key: GitSummaryCacheKey) async {
        do {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            var cached = result
            cached.isCached = false
            let data = try Self.encoder.encode(cached)
            try data.write(to: rootDirectory.appendingPathComponent(key.filename, isDirectory: false), options: .atomic)
        } catch {
            Log.git.debug("Git summary cache write failed: \(error.localizedDescription, privacy: .public)")
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
