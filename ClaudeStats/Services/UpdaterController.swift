import AppKit
import Sparkle

/// Owns Sparkle's standard updater for the lifetime of the app (created in
/// ``AppEnvironment``, started once AppKit has finished launching via
/// ``AppEnvironment/start()``).
///
/// Claude Stats runs as a menu-bar (`LSUIElement`) app, so it has no Dock icon
/// and its windows don't normally come to the front. While Sparkle's update
/// windows are on screen we route through ``DockVisibilityCoordinator`` to
/// promote the app to a regular, Dock-visible app, then release back to
/// `.accessory` when the update session ends — otherwise the "update available"
/// dialog can appear behind everything with no way to focus it. The coordinator
/// is ref-counted so this composes with other consumers (e.g. the main window).
final class UpdaterController: NSObject {
    static let updateAvailabilityDidChange = Notification.Name("ClaudeStats.updateAvailabilityDidChange")
    static let updateSettingsDidChange = Notification.Name("ClaudeStats.updateSettingsDidChange")

    enum UpdateState: Sendable, Equatable {
        case idle
        case available
        case downloading
        case readyToInstall
        case installing

        var showsUpdatePill: Bool {
            self != .idle
        }

        var canOpenUpdateUI: Bool {
            switch self {
            case .available, .readyToInstall, .installing:
                true
            case .idle, .downloading:
                false
            }
        }
    }

    private enum DefaultsKey {
        static let availableUpdateVersionString = "availableUpdateVersionString"
        static let availableUpdateDisplayVersionString = "availableUpdateDisplayVersionString"
        static let sparkleAutomaticallyUpdate = "SUAutomaticallyUpdate"
    }

    private var controller: SPUStandardUpdaterController?
    private var dockVisibilityAcquired = false
    private let defaults: UserDefaults
    private let hostBuildVersion: String?

    private(set) var updateState: UpdateState = .idle
    private(set) var updateAvailable = false
    private(set) var availableUpdateVersion: String?

    init(
        defaults: UserDefaults = .standard,
        hostBuildVersion: String? = UpdaterController.currentHostBuildVersion()
    ) {
        self.defaults = defaults
        self.hostBuildVersion = hostBuildVersion
        super.init()
        restorePersistedUpdateAvailability()
    }

    /// Create and start the Sparkle updater. Idempotent; safe to call once at
    /// launch. Kept out of `init` so `AppEnvironment.preview()` / tests can hold
    /// an `UpdaterController` without spinning up Sparkle.
    @MainActor
    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        syncUpdaterSettings()
        checkForUpdatesInBackgroundOnLaunchIfAllowed()
    }

    @MainActor
    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    @MainActor
    var automaticallyChecksForUpdates: Bool {
        controller?.updater.automaticallyChecksForUpdates
            ?? (Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool ?? false)
    }

    @MainActor
    var allowsAutomaticUpdates: Bool {
        controller?.updater.allowsAutomaticUpdates ?? automaticallyChecksForUpdates
    }

    @MainActor
    var automaticallyDownloadsUpdates: Bool {
        if let controller {
            return controller.updater.automaticallyDownloadsUpdates
        }
        if let stored = defaults.object(forKey: DefaultsKey.sparkleAutomaticallyUpdate) as? Bool {
            return stored
        }
        return Bundle.main.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool ?? false
    }

    @MainActor
    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard let controller else {
            defaults.set(enabled, forKey: DefaultsKey.sparkleAutomaticallyUpdate)
            syncUpdaterSettings()
            return
        }
        controller.updater.automaticallyDownloadsUpdates = enabled
        syncUpdaterSettings()
    }

    /// Trigger a user-initiated update check (e.g. from Settings ▸ About).
    /// Just brings the app forward; the Dock-policy flip happens once Sparkle
    /// is about to show its update UI.
    @MainActor
    func checkForUpdates() {
        if updateState.canOpenUpdateUI {
            acquireDockVisibilityForUpdateUI()
        }
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    private func markUpdateAvailable(_ item: SUAppcastItem, state: UpdateState = .available) {
        markUpdateAvailable(
            versionString: item.versionString,
            displayVersion: item.displayVersionString,
            state: state
        )
    }

    func markUpdateAvailable(version: String?) {
        markUpdateAvailable(versionString: version, displayVersion: version)
    }

    func markUpdateAvailable(
        versionString: String?,
        displayVersion: String?,
        state: UpdateState = .available
    ) {
        let normalizedVersionString = Self.normalizedVersion(versionString)
        let normalizedDisplayVersion = Self.normalizedVersion(displayVersion)
        let visibleVersion = normalizedDisplayVersion ?? normalizedVersionString

        if let normalizedVersionString {
            persistUpdateAvailability(
                versionString: normalizedVersionString,
                displayVersion: normalizedDisplayVersion
            )
        }

        Log.updater.info(
            "Update state \(String(describing: state), privacy: .public): display=\(visibleVersion ?? "unknown", privacy: .public), build=\(normalizedVersionString ?? "unknown", privacy: .public)"
        )
        setUpdateState(state, version: visibleVersion)
    }

    func clearUpdateAvailability(reason: String) {
        clearPersistedUpdateAvailability()
        Log.updater.info("Update pill cleared: \(reason, privacy: .public)")
        setUpdateState(.idle, version: nil)
    }

    func keepUpdateAvailabilityAfterCurrentSession() {
        Log.updater.debug("Keeping update pill visible after current session")
    }

    func finishUpdateSession() {
        Log.updater.debug("Update session finished; updateAvailable=\(self.updateAvailable, privacy: .public)")
        releaseDockVisibilityForUpdateUI()
    }

    func recordUserAttentionForUpdate() {
        Log.updater.debug("User gave attention to update UI; keeping update pill visible")
    }

    func recordUserUpdateChoice(_ choice: SPUUserUpdateChoice, state: SPUUserUpdateState? = nil) {
        switch choice.rawValue {
        case 0:
            clearUpdateAvailability(reason: "user skipped update")
        case 1:
            let nextState = state.map(updateState(for:)) ?? .installing
            Log.updater.info("User chose install; keeping update pill in \(String(describing: nextState), privacy: .public) state")
            setUpdateState(nextState, version: availableUpdateVersion)
        case 2:
            if let state {
                setUpdateState(updateState(for: state), version: availableUpdateVersion)
            }
            Log.updater.info("User dismissed update; keeping update pill visible")
        default:
            Log.updater.info("User made unknown update choice \(choice.rawValue, privacy: .public); keeping update pill visible")
        }
    }

    func recordNoUpdateFound() {
        clearUpdateAvailability(reason: "no valid update found")
    }

    func recordUpdateCheckFailure(_ error: any Error) {
        if isDefinitiveNoUpdate(error) {
            clearUpdateAvailability(reason: "definitive no-update result: \((error as NSError).localizedDescription)")
        } else {
            Log.updater.error("Update check failed transiently; keeping existing pill state: \((error as NSError).localizedDescription, privacy: .public)")
        }
    }

    private func setUpdateState(_ state: UpdateState, version: String?) {
        let available = state.showsUpdatePill
        let visibleVersion = available ? version : nil
        guard updateState != state || updateAvailable != available || availableUpdateVersion != visibleVersion else { return }
        updateState = state
        updateAvailable = available
        availableUpdateVersion = visibleVersion
        NotificationCenter.default.post(name: Self.updateAvailabilityDidChange, object: self)
    }

    @MainActor
    private func syncUpdaterSettings() {
        NotificationCenter.default.post(name: Self.updateSettingsDidChange, object: self)
    }

    @MainActor
    private func checkForUpdatesInBackgroundOnLaunchIfAllowed() {
        guard let updater = controller?.updater else {
            Log.updater.error("Skipping launch update check because Sparkle updater is not started")
            return
        }
        guard Self.shouldCheckForUpdatesOnLaunch(
            automaticallyChecksForUpdates: updater.automaticallyChecksForUpdates,
            sessionInProgress: updater.sessionInProgress
        ) else {
            Log.updater.info(
                "Skipping launch update check: automaticChecks=\(updater.automaticallyChecksForUpdates, privacy: .public), sessionInProgress=\(updater.sessionInProgress, privacy: .public)"
            )
            return
        }
        Log.updater.info("Starting launch background update check")
        updater.checkForUpdatesInBackground()
    }

    static func shouldCheckForUpdatesOnLaunch(
        automaticallyChecksForUpdates: Bool,
        sessionInProgress: Bool
    ) -> Bool {
        automaticallyChecksForUpdates && !sessionInProgress
    }

    private func acquireDockVisibilityForUpdateUI() {
        guard !dockVisibilityAcquired else { return }
        dockVisibilityAcquired = true
        MainActor.assumeIsolated { DockVisibilityCoordinator.shared.acquire() }
    }

    private func releaseDockVisibilityForUpdateUI() {
        guard dockVisibilityAcquired else { return }
        dockVisibilityAcquired = false
        MainActor.assumeIsolated { DockVisibilityCoordinator.shared.release() }
    }

    private func restorePersistedUpdateAvailability() {
        guard let versionString = Self.normalizedVersion(defaults.string(forKey: DefaultsKey.availableUpdateVersionString)) else {
            clearPersistedUpdateAvailability()
            return
        }

        guard isUpdateVersionNewerThanHost(versionString) else {
            clearPersistedUpdateAvailability()
            Log.updater.debug("Stored update build \(versionString, privacy: .public) is not newer than host build \(self.hostBuildVersion ?? "unknown", privacy: .public)")
            return
        }

        let displayVersion = Self.normalizedVersion(defaults.string(forKey: DefaultsKey.availableUpdateDisplayVersionString))
        updateAvailable = true
        availableUpdateVersion = displayVersion ?? versionString
        updateState = .available
        Log.updater.info(
            "Restored update pill from defaults: display=\(self.availableUpdateVersion ?? "unknown", privacy: .public), build=\(versionString, privacy: .public)"
        )
    }

    private func persistUpdateAvailability(versionString: String, displayVersion: String?) {
        defaults.set(versionString, forKey: DefaultsKey.availableUpdateVersionString)
        if let displayVersion {
            defaults.set(displayVersion, forKey: DefaultsKey.availableUpdateDisplayVersionString)
        } else {
            defaults.removeObject(forKey: DefaultsKey.availableUpdateDisplayVersionString)
        }
    }

    private func clearPersistedUpdateAvailability() {
        defaults.removeObject(forKey: DefaultsKey.availableUpdateVersionString)
        defaults.removeObject(forKey: DefaultsKey.availableUpdateDisplayVersionString)
    }

    private func isUpdateVersionNewerThanHost(_ updateVersion: String) -> Bool {
        guard let hostBuildVersion = Self.normalizedVersion(hostBuildVersion) else { return false }
        return SUStandardVersionComparator.default.compareVersion(
            updateVersion,
            toVersion: hostBuildVersion
        ) == .orderedDescending
    }

    private func isDefinitiveNoUpdate(_ error: any Error) -> Bool {
        let nsError = error as NSError
        guard let reason = nsError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber else { return false }
        // Sparkle reasons 1...5 are definitive "no installable update" results.
        // Reason 0 is unknown and may represent a transient failure.
        return (1...5).contains(reason.intValue)
    }

    private static func currentHostBuildVersion() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    private static func normalizedVersion(_ version: String?) -> String? {
        let trimmed = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func updateState(for userUpdateState: SPUUserUpdateState) -> UpdateState {
        switch userUpdateState.stage {
        case .notDownloaded:
            .available
        case .downloaded:
            .readyToInstall
        case .installing:
            .installing
        @unknown default:
            .available
        }
    }
}

extension UpdaterController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        markUpdateAvailable(item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        recordNoUpdateFound()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        recordUpdateCheckFailure(error)
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        recordUserUpdateChoice(choice, state: state)
    }

    @objc(updater:willDownloadUpdate:withRequest:)
    func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with request: NSMutableURLRequest
    ) {
        markUpdateAvailable(item, state: .downloading)
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        markUpdateAvailable(item, state: .readyToInstall)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        Log.updater.error("Update download failed: \((error as NSError).localizedDescription, privacy: .public)")
        markUpdateAvailable(item, state: .available)
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        Log.updater.info("User canceled update download; keeping update available")
        setUpdateState(.available, version: availableUpdateVersion)
    }

    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        markUpdateAvailable(item, state: .downloading)
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        markUpdateAvailable(item, state: .readyToInstall)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        markUpdateAvailable(item, state: .installing)
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        markUpdateAvailable(item, state: .readyToInstall)
        return false
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        recordUpdateCheckFailure(error)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        if let error {
            Log.updater.error("Update cycle finished with error: \((error as NSError).localizedDescription, privacy: .public)")
        } else {
            Log.updater.info("Update cycle finished successfully; updateState=\(String(describing: self.updateState), privacy: .public)")
        }
    }
}

extension UpdaterController: SPUStandardUserDriverDelegate {
    // Sparkle invokes user-driver callbacks on the main thread. Keep app-owned
    // state updates synchronous, and isolate only the AppKit dock-policy calls.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        markUpdateAvailable(update, state: updateState(for: state))
        if handleShowingUpdate {
            acquireDockVisibilityForUpdateUI()
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        recordUserAttentionForUpdate()
    }

    func standardUserDriverWillFinishUpdateSession() {
        finishUpdateSession()
    }
}
