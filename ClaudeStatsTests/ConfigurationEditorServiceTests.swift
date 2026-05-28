import Foundation
import Testing
@testable import ClaudeStats

@Suite("Configuration editor service")
struct ConfigurationEditorServiceTests {
    @Test("Saving a snapshot to the profile does not write the target file")
    func updatingSnapshotLeavesDiskUntouched() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let target = temp.appendingPathComponent("settings.json", isDirectory: false)
        let original = #"{"mode":"disk"}"#
        try original.write(to: target, atomically: true, encoding: .utf8)

        let snapshot = makeSnapshot(url: target, content: #"{"mode":"profile"}"#)
        let profile = ConfigProfile(provider: .claude, scope: .global, name: "Test", files: [snapshot])
        let service = ConfigurationEditorService()

        let updated = try service.profileByUpdatingSnapshot(
            profile,
            snapshotID: snapshot.id,
            content: #"{"mode":"draft"}"#
        )

        #expect(updated.files.first?.content == #"{"mode":"draft"}"#)
        #expect(updated.files.first?.contentHash == ConfigurationProfileStore.hash(#"{"mode":"draft"}"#))
        #expect(try String(contentsOf: target, encoding: .utf8) == original)
    }

    @Test("Saving a snapshot to disk creates a backup before writing")
    func saveSnapshotToDiskCreatesBackup() async throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let target = temp.appendingPathComponent("settings.json", isDirectory: false)
        let original = #"{"mode":"disk"}"#
        let draft = #"{"mode":"draft"}"#
        try original.write(to: target, atomically: true, encoding: .utf8)

        let snapshot = makeSnapshot(url: target, content: #"{"mode":"profile"}"#)
        let profile = ConfigProfile(provider: .claude, scope: .global, name: "Test", files: [snapshot])
        let store = ConfigurationProfileStore(rootDirectory: temp.appendingPathComponent("Profiles", isDirectory: true))
        let service = ConfigurationEditorService(profileStore: store)

        let result = try await service.saveSnapshotToDisk(profile: profile, snapshotID: snapshot.id, content: draft)

        #expect(try String(contentsOf: target, encoding: .utf8) == draft)
        #expect(result.updatedProfile.files.first?.content == draft)
        #expect(FileManager.default.fileExists(atPath: result.backupDirectory.appendingPathComponent("manifest.json").path))
        #expect(try String(contentsOf: result.backupDirectory.appendingPathComponent("0-settings.json"), encoding: .utf8) == original)
    }

    @Test("Invalid JSON returns a diagnostic but remains editable")
    func invalidJSONDiagnostics() throws {
        let diagnostics = ConfigurationEditorService.diagnosticsSync(for: #"{"mode":"draft""#, kind: .json)

        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.severity == .error)
        #expect(diagnostics.first?.message.isEmpty == false)
    }

    @Test("TOML diagnostics report syntax and unknown keys")
    func tomlDiagnostics() throws {
        let valid = ConfigurationEditorService.diagnosticsSync(
            for: "model = \"gpt-5.3-codex\"\napproval_policy = \"on-request\"\n",
            kind: .toml
        )
        #expect(valid.isEmpty)

        let invalid = ConfigurationEditorService.diagnosticsSync(for: "model = \"unterminated\n", kind: .toml)
        #expect(invalid.contains { $0.severity == .error })

        let unknown = ConfigurationEditorService.diagnosticsSync(for: "surprise = true\n", kind: .toml)
        #expect(unknown.contains { $0.severity == .info })
    }

    @Test("Missing snapshot fails without writing")
    func missingSnapshotFails() async throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let target = temp.appendingPathComponent("settings.json", isDirectory: false)
        let original = #"{"mode":"disk"}"#
        try original.write(to: target, atomically: true, encoding: .utf8)

        let snapshot = makeSnapshot(url: target, content: #"{"mode":"profile"}"#)
        let profile = ConfigProfile(provider: .claude, scope: .global, name: "Test", files: [snapshot])
        let store = ConfigurationProfileStore(rootDirectory: temp.appendingPathComponent("Profiles", isDirectory: true))
        let service = ConfigurationEditorService(profileStore: store)

        var didThrow = false
        do {
            _ = try await service.saveSnapshotToDisk(profile: profile, snapshotID: UUID(), content: #"{"mode":"draft"}"#)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(try String(contentsOf: target, encoding: .utf8) == original)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigurationEditorServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSnapshot(url: URL, content: String) -> ConfigFileSnapshot {
        ConfigFileSnapshot(
            title: url.lastPathComponent,
            path: url.path,
            fileKind: .json,
            content: content,
            contentHash: ConfigurationProfileStore.hash(content)
        )
    }
}
