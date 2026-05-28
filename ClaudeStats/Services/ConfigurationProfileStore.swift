import CryptoKit
import Foundation

enum ConfigurationProfileStoreError: LocalizedError, Sendable {
    case noFilesFound
    case profileNotFound
    case invalidBackupDirectory

    var errorDescription: String? {
        switch self {
        case .noFilesFound:
            "No existing configuration files were found for this scope."
        case .profileNotFound:
            "The selected configuration profile could not be found."
        case .invalidBackupDirectory:
            "The backup directory could not be created."
        }
    }
}

struct ConfigurationApplyResult: Sendable, Hashable {
    let backupDirectory: URL
    let appliedAt: Date
}

struct ConfigurationBackupSummary: Identifiable, Sendable, Hashable {
    let id: String
    let profileID: UUID
    let profileName: String
    let createdAt: Date
    let directoryPath: String
    let fileCount: Int
}

struct ConfigurationBackupDiff: Identifiable, Sendable, Hashable {
    enum Status: String, Sendable, Hashable {
        case unchanged
        case changed
        case missingOnDisk
        case createdAfterBackup
    }

    let id: String
    let targetPath: String
    let backupPath: String?
    let status: Status
}

/// Handles all disk I/O for configuration profiles. Views and view models keep
/// the user's intent; this store owns persistence, backup creation, hashing,
/// and atomic writes.
struct ConfigurationProfileStore: Sendable {
    let rootDirectory: URL

    private var libraryURL: URL {
        rootDirectory.appendingPathComponent("profiles.json", isDirectory: false)
    }

    private var backupsDirectory: URL {
        rootDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    init(rootDirectory: URL = Self.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
    }

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("ConfigurationProfiles", isDirectory: true)
    }

    func loadLibrary() async throws -> ConfigurationProfileLibrary {
        let url = libraryURL
        return try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return ConfigurationProfileLibrary()
            }
            let data = try Data(contentsOf: url)
            return try JSONDecoder.profileDecoder.decode(ConfigurationProfileLibrary.self, from: data)
        }.value
    }

    func saveLibrary(_ library: ConfigurationProfileLibrary) async throws {
        let rootDirectory = rootDirectory
        let url = libraryURL
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder.profileEncoder.encode(library)
            try data.write(to: url, options: .atomic)
        }.value
    }

    func captureProfile(
        name: String,
        provider: ProviderKind,
        scope: ConfigProfileScope,
        locations: [ProviderConfigLocation]
    ) async throws -> ConfigProfile {
        try await Task.detached(priority: .utility) {
            let snapshots = try locations.compactMap { location -> ConfigFileSnapshot? in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: location.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else {
                    return nil
                }
                let content = try String(contentsOf: location.url, encoding: .utf8)
                return ConfigFileSnapshot(
                    title: location.title,
                    path: location.path,
                    fileKind: location.fileKind,
                    content: content,
                    contentHash: Self.hash(content)
                )
            }
            guard !snapshots.isEmpty else { throw ConfigurationProfileStoreError.noFilesFound }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let profileName = trimmed.isEmpty ? "\(provider.shortName) Profile" : trimmed
            return ConfigProfile(provider: provider, scope: scope, name: profileName, files: snapshots)
        }.value
    }

    func apply(_ profile: ConfigProfile) async throws -> ConfigurationApplyResult {
        let backupsDirectory = backupsDirectory
        return try await Task.detached(priority: .utility) {
            let appliedAt = Date()
            let backupDirectory = backupsDirectory
                .appendingPathComponent(Self.backupDirectoryName(profile: profile, date: appliedAt), isDirectory: true)

            try Self.createBackup(for: profile, backupDirectory: backupDirectory, createdAt: appliedAt)
            try Self.writeSnapshots(profile.files)

            return ConfigurationApplyResult(backupDirectory: backupDirectory, appliedAt: appliedAt)
        }.value
    }

    func status(for profile: ConfigProfile) async -> ConfigProfileStatus {
        await Task.detached(priority: .utility) {
            Self.statusSync(for: profile)
        }.value
    }

    func listBackups() async throws -> [ConfigurationBackupSummary] {
        let backupsDirectory = backupsDirectory
        return try await Task.detached(priority: .utility) {
            guard let directories = try? FileManager.default.contentsOfDirectory(
                at: backupsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            return directories.compactMap { directory -> ConfigurationBackupSummary? in
                guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                    return nil
                }
                let manifestURL = directory.appendingPathComponent("manifest.json", isDirectory: false)
                guard let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? JSONDecoder.profileDecoder.decode(BackupManifest.self, from: data) else {
                    return nil
                }
                return ConfigurationBackupSummary(
                    id: directory.path,
                    profileID: manifest.profileID,
                    profileName: manifest.profileName,
                    createdAt: manifest.createdAt,
                    directoryPath: directory.path,
                    fileCount: manifest.files.count
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
        }.value
    }

    func diffBackup(_ backup: ConfigurationBackupSummary) async throws -> [ConfigurationBackupDiff] {
        try await Task.detached(priority: .utility) {
            let manifest = try Self.readBackupManifest(directory: URL(fileURLWithPath: backup.directoryPath, isDirectory: true))
            return manifest.files.map { entry in
                let targetURL = URL(fileURLWithPath: entry.targetPath)
                let targetExists = FileManager.default.fileExists(atPath: targetURL.path)
                let status: ConfigurationBackupDiff.Status
                if let backupPath = entry.backupPath {
                    let backupURL = URL(fileURLWithPath: backupPath)
                    let backupData = try? Data(contentsOf: backupURL)
                    let targetData = try? Data(contentsOf: targetURL)
                    if !targetExists {
                        status = .missingOnDisk
                    } else if backupData == targetData {
                        status = .unchanged
                    } else {
                        status = .changed
                    }
                } else {
                    status = targetExists ? .createdAfterBackup : .unchanged
                }
                return ConfigurationBackupDiff(
                    id: "\(backup.directoryPath):\(entry.targetPath)",
                    targetPath: entry.targetPath,
                    backupPath: entry.backupPath,
                    status: status
                )
            }
        }.value
    }

    func restoreBackup(_ backup: ConfigurationBackupSummary) async throws -> ConfigurationApplyResult {
        try await Task.detached(priority: .utility) {
            let restoredAt = Date()
            let directory = URL(fileURLWithPath: backup.directoryPath, isDirectory: true)
            let manifest = try Self.readBackupManifest(directory: directory)
            for entry in manifest.files {
                let targetURL = URL(fileURLWithPath: entry.targetPath)
                if let backupPath = entry.backupPath {
                    try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: targetURL.path) {
                        try FileManager.default.removeItem(at: targetURL)
                    }
                    try FileManager.default.copyItem(at: URL(fileURLWithPath: backupPath), to: targetURL)
                } else if FileManager.default.fileExists(atPath: targetURL.path) {
                    try FileManager.default.removeItem(at: targetURL)
                }
            }
            return ConfigurationApplyResult(backupDirectory: directory, appliedAt: restoredAt)
        }.value
    }

    static func hash(_ content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func statusSync(for profile: ConfigProfile) -> ConfigProfileStatus {
        guard !profile.files.isEmpty else { return .empty }

        var missingCount = 0
        var modifiedCount = 0

        for snapshot in profile.files {
            let url = URL(fileURLWithPath: snapshot.path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: snapshot.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  let content = try? String(contentsOf: url, encoding: .utf8) else {
                missingCount += 1
                continue
            }
            if hash(content) != snapshot.contentHash {
                modifiedCount += 1
            }
        }

        if missingCount > 0 { return .missing(missingCount) }
        if modifiedCount > 0 { return .modified(modifiedCount) }
        return .clean
    }

    private static func createBackup(for profile: ConfigProfile, backupDirectory: URL, createdAt: Date) throws {
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        guard directoryExists(backupDirectory) else {
            throw ConfigurationProfileStoreError.invalidBackupDirectory
        }

        var entries: [BackupManifest.Entry] = []
        for (index, snapshot) in profile.files.enumerated() {
            let sourceURL = URL(fileURLWithPath: snapshot.path)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) && !isDirectory.boolValue
            if exists {
                let backupURL = backupDirectory.appendingPathComponent(backupFileName(for: snapshot, index: index), isDirectory: false)
                try FileManager.default.copyItem(at: sourceURL, to: backupURL)
                entries.append(BackupManifest.Entry(targetPath: snapshot.path, backupPath: backupURL.path, existed: true))
            } else {
                entries.append(BackupManifest.Entry(targetPath: snapshot.path, backupPath: nil, existed: false))
            }
        }

        let manifest = BackupManifest(profileID: profile.id, profileName: profile.name, createdAt: createdAt, files: entries)
        let data = try JSONEncoder.profileEncoder.encode(manifest)
        try data.write(to: backupDirectory.appendingPathComponent("manifest.json", isDirectory: false), options: .atomic)
    }

    private static func writeSnapshots(_ snapshots: [ConfigFileSnapshot]) throws {
        for snapshot in snapshots {
            let url = URL(fileURLWithPath: snapshot.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(snapshot.content.utf8).write(to: url, options: .atomic)
        }
    }

    private static func backupDirectoryName(profile: ConfigProfile, date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        return "\(stamp)-\(profile.id.uuidString)"
    }

    private static func backupFileName(for snapshot: ConfigFileSnapshot, index: Int) -> String {
        let original = URL(fileURLWithPath: snapshot.path).lastPathComponent
        let suffix = original.isEmpty ? "config" : original
        return "\(index)-\(suffix)"
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func readBackupManifest(directory: URL) throws -> BackupManifest {
        let manifestURL = directory.appendingPathComponent("manifest.json", isDirectory: false)
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder.profileDecoder.decode(BackupManifest.self, from: data)
    }

    private struct BackupManifest: Codable, Sendable {
        struct Entry: Codable, Sendable {
            let targetPath: String
            let backupPath: String?
            let existed: Bool
        }

        let profileID: UUID
        let profileName: String
        let createdAt: Date
        let files: [Entry]
    }
}

private extension JSONEncoder {
    static var profileEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var profileDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
