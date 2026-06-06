import Foundation
import Sparkle
import Testing
@testable import ClaudeStats

@Suite("Updater Controller")
@MainActor
struct UpdaterControllerTests {
    @Test("Delegated gentle reminder keeps update pill visible after session ends")
    func delegatedGentleReminderPersistsAfterSession() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let updater = UpdaterController(defaults: defaults, hostBuildVersion: "39")

        updater.markUpdateAvailable(versionString: "40", displayVersion: "1.4.8")
        updater.keepUpdateAvailabilityAfterCurrentSession()
        updater.finishUpdateSession()

        #expect(updater.updateAvailable == true)
        #expect(updater.updateState == .available)
        #expect(updater.availableUpdateVersion == "1.4.8")
    }

    @Test("User attention keeps update pill visible")
    func userAttentionKeepsAvailability() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let updater = UpdaterController(defaults: defaults, hostBuildVersion: "39")

        updater.markUpdateAvailable(versionString: "40", displayVersion: "1.4.8")
        updater.recordUserAttentionForUpdate()

        #expect(updater.updateAvailable == true)
        #expect(updater.updateState == .available)
        #expect(updater.availableUpdateVersion == "1.4.8")
    }

    @Test("Dismiss keeps update pill visible")
    func dismissKeepsAvailability() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let updater = UpdaterController(defaults: defaults, hostBuildVersion: "39")

        updater.markUpdateAvailable(versionString: "40", displayVersion: "1.4.8")
        updater.recordUserUpdateChoice(SPUUserUpdateChoice(rawValue: 2)!)

        #expect(updater.updateAvailable == true)
        #expect(updater.updateState == .available)
        #expect(updater.availableUpdateVersion == "1.4.8")
    }

    @Test("Skip clears update pill, install keeps it visible")
    func skipClearsInstallKeepsAvailability() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let updater = UpdaterController(defaults: defaults, hostBuildVersion: "39")

        updater.markUpdateAvailable(versionString: "40", displayVersion: "1.4.8")
        updater.recordUserUpdateChoice(SPUUserUpdateChoice(rawValue: 0)!)
        #expect(updater.updateAvailable == false)
        #expect(updater.availableUpdateVersion == nil)

        updater.markUpdateAvailable(versionString: "40", displayVersion: "1.4.8")
        updater.recordUserUpdateChoice(SPUUserUpdateChoice(rawValue: 1)!)
        #expect(updater.updateAvailable == true)
        #expect(updater.updateState == .installing)
        #expect(updater.availableUpdateVersion == "1.4.8")
    }

    @Test("Downloading state shows but disables update pill")
    func downloadingStateKeepsDisabledPill() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let updater = UpdaterController(defaults: defaults, hostBuildVersion: "39")

        updater.markUpdateAvailable(versionString: "40", displayVersion: "1.4.8", state: .downloading)

        #expect(updater.updateAvailable == true)
        #expect(updater.updateState == .downloading)
        #expect(updater.updateState.showsUpdatePill == true)
        #expect(updater.updateState.canOpenUpdateUI == false)
        #expect(updater.availableUpdateVersion == "1.4.8")
    }

    @Test("Ready to install state can open Sparkle UI")
    func readyToInstallStateCanOpenUpdateUI() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let updater = UpdaterController(defaults: defaults, hostBuildVersion: "39")

        updater.markUpdateAvailable(versionString: "40", displayVersion: "1.4.8", state: .readyToInstall)

        #expect(updater.updateAvailable == true)
        #expect(updater.updateState == .readyToInstall)
        #expect(updater.updateState.showsUpdatePill == true)
        #expect(updater.updateState.canOpenUpdateUI == true)
        #expect(updater.availableUpdateVersion == "1.4.8")
    }

    @Test("Transient feed error keeps existing update pill")
    func transientErrorKeepsAvailability() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let updater = UpdaterController(defaults: defaults, hostBuildVersion: "39")

        updater.markUpdateAvailable(versionString: "40", displayVersion: "1.4.8")
        updater.recordUpdateCheckFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed))

        #expect(updater.updateAvailable == true)
        #expect(updater.updateState == .available)
        #expect(updater.availableUpdateVersion == "1.4.8")
    }

    @Test("No update clears update pill")
    func noUpdateClearsAvailability() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let updater = UpdaterController(defaults: defaults, hostBuildVersion: "39")

        updater.markUpdateAvailable(versionString: "40", displayVersion: "1.4.8")
        updater.recordNoUpdateFound()

        #expect(updater.updateAvailable == false)
        #expect(updater.updateState == .idle)
        #expect(updater.availableUpdateVersion == nil)
    }

    @Test("Persisted newer update restores pill on launch")
    func persistedNewerUpdateRestoresAvailability() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = UpdaterController(defaults: defaults, hostBuildVersion: "39")
        first.markUpdateAvailable(versionString: "40", displayVersion: "1.4.8")

        let restored = UpdaterController(defaults: defaults, hostBuildVersion: "39")
        #expect(restored.updateAvailable == true)
        #expect(restored.updateState == .available)
        #expect(restored.availableUpdateVersion == "1.4.8")
    }

    @Test("Persisted current or older update is cleared on launch")
    func persistedCurrentUpdateClearsAvailability() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = UpdaterController(defaults: defaults, hostBuildVersion: "39")
        first.markUpdateAvailable(versionString: "40", displayVersion: "1.4.8")

        let restored = UpdaterController(defaults: defaults, hostBuildVersion: "40")
        #expect(restored.updateAvailable == false)
        #expect(restored.updateState == .idle)
        #expect(restored.availableUpdateVersion == nil)
    }

    @Test("Launch background check only runs when automatic checks are enabled")
    func launchBackgroundCheckGateRequiresAutomaticChecks() {
        #expect(UpdaterController.shouldCheckForUpdatesOnLaunch(
            automaticallyChecksForUpdates: true,
            sessionInProgress: false
        ) == true)
        #expect(UpdaterController.shouldCheckForUpdatesOnLaunch(
            automaticallyChecksForUpdates: false,
            sessionInProgress: false
        ) == false)
        #expect(UpdaterController.shouldCheckForUpdatesOnLaunch(
            automaticallyChecksForUpdates: true,
            sessionInProgress: true
        ) == false)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "ClaudeStatsTests.UpdaterController.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
