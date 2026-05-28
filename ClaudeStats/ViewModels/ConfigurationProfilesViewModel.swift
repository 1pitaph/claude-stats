import Foundation
import Observation

@MainActor
@Observable
final class ConfigurationProfilesViewModel {
    private(set) var library = ConfigurationProfileLibrary()
    private(set) var statuses: [UUID: ConfigProfileStatus] = [:]
    private(set) var profilesByProvider: [ProviderKind: [ConfigProfile]] = [:]
    private(set) var activeProfileByProvider: [ProviderKind: ConfigProfile] = [:]
    private(set) var scopeOptionsByProvider: [ProviderKind: [ConfigProfileScope]] = [:]
    private(set) var backups: [ConfigurationBackupSummary] = []
    private(set) var selectedBackupDiffs: [ConfigurationBackupDiff] = []
    private(set) var isLoading = false
    private(set) var isWorking = false
    private(set) var lastError: String?

    @ObservationIgnored private let store: ConfigurationProfileStore
    @ObservationIgnored private let editorService: ConfigurationEditorService
    @ObservationIgnored private let registry: ProviderRegistry
    @ObservationIgnored private var hasLoaded = false

    init(
        store: ConfigurationProfileStore = ConfigurationProfileStore(),
        registry: ProviderRegistry,
        editorService: ConfigurationEditorService? = nil
    ) {
        self.store = store
        self.editorService = editorService ?? ConfigurationEditorService(profileStore: store)
        self.registry = registry
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            library = try await store.loadLibrary()
            sanitizeActiveProfiles()
            rebuildProfileCaches()
            hasLoaded = true
            await refreshStatuses()
            await reloadBackups()
        } catch {
            lastError = error.localizedDescription
            Log.app.error("Failed to load configuration profiles: \(error.localizedDescription, privacy: .public)")
        }
    }

    func profiles(for provider: ProviderKind) -> [ConfigProfile] {
        profilesByProvider[provider] ?? []
    }

    func activeProfile(for provider: ProviderKind) -> ConfigProfile? {
        activeProfileByProvider[provider]
    }

    func status(for profile: ConfigProfile) -> ConfigProfileStatus {
        statuses[profile.id] ?? .unknown
    }

    func latestBackupURL(for profile: ConfigProfile) -> URL? {
        guard let path = library.latestBackupDirectoryByProfileID[profile.id] else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func reloadBackups() async {
        do {
            backups = try await store.listBackups()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadBackupDiff(_ backup: ConfigurationBackupSummary) async {
        do {
            selectedBackupDiffs = try await store.diffBackup(backup)
            lastError = nil
        } catch {
            selectedBackupDiffs = []
            lastError = error.localizedDescription
        }
    }

    func restoreBackup(_ backup: ConfigurationBackupSummary) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await store.restoreBackup(backup)
            await refreshStatuses()
            await reloadBackups()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func profile(id: UUID) -> ConfigProfile? {
        library.profiles.first { $0.id == id }
    }

    func snapshot(profileID: UUID, snapshotID: UUID) -> ConfigFileSnapshot? {
        library.profiles
            .first { $0.id == profileID }?
            .files
            .first { $0.id == snapshotID }
    }

    func scopeOptions(for provider: ProviderKind) -> [ConfigProfileScope] {
        scopeOptionsByProvider[provider] ?? [.global]
    }

    func refreshScopeOptions(from sessions: [Session]) async {
        let next = await Task.detached(priority: .utility) {
            Self.makeScopeOptions(from: sessions)
        }.value
        if next != scopeOptionsByProvider {
            scopeOptionsByProvider = next
        }
    }

    func locations(for provider: ProviderKind, scope: ConfigProfileScope) -> [ProviderConfigLocation] {
        guard let provider = registry.provider(for: provider) else { return [] }
        switch scope {
        case .global:
            return provider.globalConfigurationLocations()
        case .project(let path):
            let projectURL = URL(fileURLWithPath: path, isDirectory: true)
            return provider.globalConfigurationLocations() + provider.projectConfigurationLocations(for: projectURL)
        }
    }

    func defaultProfileName(provider: ProviderKind, scope: ConfigProfileScope) -> String {
        switch scope {
        case .global:
            "\(provider.shortName) Global"
        case .project:
            "\(provider.shortName) \(scope.displayName)"
        }
    }

    func captureCurrent(name: String, provider: ProviderKind, scope: ConfigProfileScope) async -> ConfigProfile? {
        let locations = locations(for: provider, scope: scope)
        guard !locations.isEmpty else {
            lastError = "No configuration locations are available for \(provider.displayName)."
            return nil
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let profile = try await store.captureProfile(name: name, provider: provider, scope: scope, locations: locations)
            library.profiles.append(profile)
            library.activeProfileIDsByProvider[provider] = profile.id
            try await persist()
            await refreshStatuses()
            return profile
        } catch {
            lastError = error.localizedDescription
            Log.app.error("Failed to capture configuration profile: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func apply(_ profile: ConfigProfile) async -> Bool {
        isWorking = true
        defer { isWorking = false }

        do {
            let result = try await store.apply(profile)
            updateProfile(profile.id) { updated in
                updated.lastAppliedAt = result.appliedAt
                updated.updatedAt = result.appliedAt
            }
            library.activeProfileIDsByProvider[profile.provider] = profile.id
            library.latestBackupDirectoryByProfileID[profile.id] = result.backupDirectory.path
            try await persist()
            await refreshStatuses()
            return true
        } catch {
            lastError = error.localizedDescription
            Log.app.error("Failed to apply configuration profile: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func duplicate(_ profile: ConfigProfile) async -> ConfigProfile? {
        isWorking = true
        defer { isWorking = false }

        var copy = profile
        copy = ConfigProfile(
            provider: profile.provider,
            scope: profile.scope,
            name: "\(profile.name) Copy",
            files: profile.files,
            createdAt: .now,
            updatedAt: .now
        )
        library.profiles.append(copy)

        do {
            try await persist()
            await refreshStatuses()
            return copy
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func delete(_ profile: ConfigProfile) async {
        isWorking = true
        defer { isWorking = false }

        library.profiles.removeAll { $0.id == profile.id }
        library.latestBackupDirectoryByProfileID.removeValue(forKey: profile.id)
        if library.activeProfileIDsByProvider[profile.provider] == profile.id {
            library.activeProfileIDsByProvider.removeValue(forKey: profile.provider)
        }
        statuses.removeValue(forKey: profile.id)

        do {
            try await persist()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveSnapshotToProfile(profileID: UUID, snapshotID: UUID, content: String) async -> ConfigProfile? {
        guard let profile = profile(id: profileID) else {
            lastError = ConfigurationProfileStoreError.profileNotFound.localizedDescription
            return nil
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let updatedProfile = try editorService.profileByUpdatingSnapshot(
                profile,
                snapshotID: snapshotID,
                content: content
            )
            replaceProfile(updatedProfile)
            try await persist()
            await refreshStatuses()
            return updatedProfile
        } catch {
            lastError = error.localizedDescription
            Log.app.error("Failed to save configuration snapshot: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func saveSnapshotToDisk(profileID: UUID, snapshotID: UUID, content: String) async -> ConfigurationEditorDiskSaveResult? {
        guard let profile = profile(id: profileID) else {
            lastError = ConfigurationProfileStoreError.profileNotFound.localizedDescription
            return nil
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let result = try await editorService.saveSnapshotToDisk(
                profile: profile,
                snapshotID: snapshotID,
                content: content
            )
            replaceProfile(result.updatedProfile)
            library.latestBackupDirectoryByProfileID[profileID] = result.backupDirectory.path
            try await persist()
            await refreshStatuses()
            return result
        } catch {
            lastError = error.localizedDescription
            Log.app.error("Failed to save configuration file to disk: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func refreshStatuses() async {
        var refreshed: [UUID: ConfigProfileStatus] = [:]
        for profile in library.profiles {
            refreshed[profile.id] = await store.status(for: profile)
        }
        statuses = refreshed
    }

    func clearError() {
        lastError = nil
    }

    private func persist() async throws {
        sanitizeActiveProfiles()
        rebuildProfileCaches()
        try await store.saveLibrary(library)
    }

    private func sanitizeActiveProfiles() {
        let validIDs = Set(library.profiles.map(\.id))
        library.activeProfileIDsByProvider = library.activeProfileIDsByProvider.filter { _, id in
            validIDs.contains(id)
        }
    }

    private func updateProfile(_ id: UUID, mutate: (inout ConfigProfile) -> Void) {
        guard let index = library.profiles.firstIndex(where: { $0.id == id }) else { return }
        mutate(&library.profiles[index])
    }

    private func replaceProfile(_ profile: ConfigProfile) {
        guard let index = library.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        library.profiles[index] = profile
    }

    private func rebuildProfileCaches() {
        profilesByProvider = Dictionary(
            uniqueKeysWithValues: ProviderKind.allCases.map { provider in
                let profiles = library.profiles
                    .filter { $0.provider == provider }
                    .sorted {
                        if $0.updatedAt == $1.updatedAt {
                            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                        }
                        return $0.updatedAt > $1.updatedAt
                    }
                return (provider, profiles)
            }
        )

        activeProfileByProvider = Dictionary(
            uniqueKeysWithValues: ProviderKind.allCases.compactMap { provider in
                guard let id = library.activeProfileIDsByProvider[provider],
                      let profile = profilesByProvider[provider]?.first(where: { $0.id == id }) else {
                    return nil
                }
                return (provider, profile)
            }
        )
    }

    private nonisolated static func makeScopeOptions(from sessions: [Session]) -> [ProviderKind: [ConfigProfileScope]] {
        var next = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.map { ($0, [ConfigProfileScope.global]) })
        var seenByProvider = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.map { ($0, Set<String>()) })

        for session in sessions {
            guard let cwd = session.cwd, !cwd.isEmpty else { continue }
            if seenByProvider[session.provider, default: []].insert(cwd).inserted {
                next[session.provider, default: [.global]].append(.project(path: cwd))
            }
        }

        return next
    }
}
