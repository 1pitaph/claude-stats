import Foundation
import Testing
@testable import ClaudeStats

@Suite("Project launch scanner")
struct ProjectLaunchScannerTests {
    @Test("Electron package uses the declared package manager and dev script")
    func detectsElectronPackage() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try TempDir.write(
            #"{"name":"desktop","packageManager":"pnpm@10.0.0","scripts":{"dev":"electron ."},"devDependencies":{"electron":"^40"}}"#,
            to: root.appendingPathComponent("package.json")
        )
        try TempDir.write("lockfileVersion: '9.0'\n", to: root.appendingPathComponent("pnpm-lock.yaml"))

        let project = try #require(ProjectLaunchScanner().scanProject(at: root.path))
        let action = try #require(project.primaryAction)

        #expect(action.kind == .electron)
        #expect(action.command.arguments == ["pnpm", "run", "dev"])
        #expect(action.lifecycle == .longRunning)
        #expect(project.recommendedActionIDs == [action.id])
    }

    @Test("Web and Docker are combined into the recommended launch set")
    func combinesWebAndDocker() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try TempDir.write(
            #"{"scripts":{"dev":"vite"},"devDependencies":{"vite":"^7"}}"#,
            to: root.appendingPathComponent("package.json")
        )
        try TempDir.write("services:\n  db:\n    image: postgres\n", to: root.appendingPathComponent("compose.yml"))

        let project = try #require(ProjectLaunchScanner().scanProject(at: root.path))
        let docker = try #require(project.actions.first { $0.kind == .docker })
        let web = try #require(project.actions.first { $0.kind == .web })

        #expect(project.recommendedActionIDs == [docker.id, web.id])
        #expect(docker.command.arguments == ["docker", "compose", "-f", "compose.yml", "up"])
        #expect(docker.stopCommand?.arguments == ["docker", "compose", "-f", "compose.yml", "down"])
    }

    @Test("Explicit debug script outranks Xcode and remains the sole recommendation")
    func explicitScriptOutranksXcode() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try TempDir.write("#!/usr/bin/env bash\n", to: root.appendingPathComponent("scripts/run-debug.sh"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Demo.xcodeproj", isDirectory: true),
            withIntermediateDirectories: true
        )

        let project = try #require(ProjectLaunchScanner().scanProject(at: root.path))
        let primary = try #require(project.primaryAction)

        #expect(primary.kind == .script)
        #expect(primary.command.arguments == ["scripts/run-debug.sh"])
        #expect(project.actions.contains { $0.kind == .xcode })
        #expect(project.recommendedActionIDs == [primary.id])
    }

    @Test("Package workspaces are scanned without walking dependency directories")
    func scansPackageWorkspaces() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try TempDir.write(
            #"{"private":true,"workspaces":["apps/*"]}"#,
            to: root.appendingPathComponent("package.json")
        )
        try TempDir.write(
            #"{"name":"storefront","scripts":{"dev":"vite"},"devDependencies":{"vite":"^7"}}"#,
            to: root.appendingPathComponent("apps/storefront/package.json")
        )
        try TempDir.write(
            #"{"scripts":{"dev":"vite"}}"#,
            to: root.appendingPathComponent("node_modules/ignored/package.json")
        )

        let project = try #require(ProjectLaunchScanner().scanProject(at: root.path))

        #expect(project.actions.contains { $0.workingDirectory.hasSuffix("apps/storefront") })
        #expect(!project.actions.contains { $0.workingDirectory.contains("node_modules") })
    }

    @Test("Known repositories remain visible when no launch method is detected")
    func keepsUnknownProjects() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try #require(ProjectLaunchScanner().scanProject(at: root.path))

        #expect(project.actions.isEmpty)
        #expect(project.primaryActionID == nil)
        #expect(project.recommendedActionIDs.isEmpty)
    }
}
