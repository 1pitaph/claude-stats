import Foundation

struct ProjectLaunchScanner: Sendable {
    func scan(repositories: [GitRepo]) -> [ProjectLaunchDescriptor] {
        scan(rootPaths: repositories.map(\.rootPath))
    }

    func scan(rootPaths: [String]) -> [ProjectLaunchDescriptor] {
        let standardizedRoots = Set(rootPaths.map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path
        })
        return standardizedRoots
            .compactMap(scanProject(at:))
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func scanProject(at rootPath: String) -> ProjectLaunchDescriptor? {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        var candidates: [Candidate] = []
        candidates += scriptCandidates(in: root)

        let packageRoots = packageDirectories(in: root)
        for packageRoot in packageRoots {
            candidates += packageCandidates(in: packageRoot, projectRoot: root)
        }

        let componentRoots = Set([root] + packageRoots)
        for componentRoot in componentRoots {
            candidates += dockerCandidates(in: componentRoot, projectRoot: root)
        }

        candidates += makeCandidates(in: root)
        candidates += justCandidates(in: root)
        candidates += cargoCandidates(in: root)
        candidates += pythonCandidates(in: root)
        candidates += xcodeCandidates(in: root)

        let actions = deduplicated(candidates)
            .sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            .map(\.action)
        let primary = actions.first
        let recommendedIDs = recommendedActionIDs(actions: actions, primary: primary)
        let name = root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent

        return ProjectLaunchDescriptor(
            id: root.path,
            name: name,
            rootPath: root.path,
            actions: actions,
            primaryActionID: primary?.id,
            recommendedActionIDs: recommendedIDs
        )
    }

    private func recommendedActionIDs(
        actions: [ProjectLaunchAction],
        primary: ProjectLaunchAction?
    ) -> [ProjectLaunchAction.ID] {
        guard let primary else { return [] }
        guard [.electron, .web, .node].contains(primary.kind),
              let docker = actions.first(where: { $0.kind == .docker }) else {
            return [primary.id]
        }
        return [docker.id, primary.id]
    }

    // MARK: - Explicit scripts

    private func scriptCandidates(in root: URL) -> [Candidate] {
        let definitions: [(path: String, title: String, lifecycle: ProjectLaunchLifecycle, priority: Int)] = [
            ("scripts/run-debug.sh", "Debug App", .oneShot, 120),
            ("scripts/dev.sh", "Development", .longRunning, 116),
            ("scripts/start.sh", "Start", .longRunning, 112),
            ("run-debug.sh", "Debug App", .oneShot, 110),
            ("dev.sh", "Development", .longRunning, 106),
            ("start.sh", "Start", .longRunning, 102),
        ]

        return definitions.compactMap { definition in
            let url = root.appendingPathComponent(definition.path, isDirectory: false)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return candidate(
                projectRoot: root,
                componentRoot: root,
                key: "script:\(definition.path)",
                title: definition.title,
                detail: definition.path,
                kind: .script,
                command: ProjectLaunchCommand(executablePath: "/bin/bash", arguments: [definition.path]),
                lifecycle: definition.lifecycle,
                confidence: .certain,
                sourcePath: definition.path,
                priority: definition.priority
            )
        }
    }

    // MARK: - JavaScript / Electron

    private func packageDirectories(in root: URL) -> [URL] {
        let rootManifest = root.appendingPathComponent("package.json", isDirectory: false)
        var directories: [URL] = []
        var workspacePatterns: [String] = []
        if FileManager.default.fileExists(atPath: rootManifest.path) {
            directories.append(root)
            workspacePatterns += packageWorkspacePatterns(at: rootManifest)
        }
        workspacePatterns += pnpmWorkspacePatterns(in: root)

        if workspacePatterns.isEmpty,
           !directories.contains(root) {
            workspacePatterns = ["apps/*", "packages/*", "frontend", "backend", "client", "server", "web", "desktop"]
        }

        for pattern in workspacePatterns.prefix(40) {
            directories += expandWorkspacePattern(pattern, relativeTo: root)
        }

        var seen = Set<String>()
        return directories
            .map(\.standardizedFileURL)
            .filter { directory in
                let manifest = directory.appendingPathComponent("package.json", isDirectory: false)
                return FileManager.default.fileExists(atPath: manifest.path) && seen.insert(directory.path).inserted
            }
            .prefix(50)
            .map { $0 }
    }

    private func packageWorkspacePatterns(at manifestURL: URL) -> [String] {
        guard let data = try? Data(contentsOf: manifestURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        if let values = object["workspaces"] as? [String] {
            return values
        }
        if let workspaces = object["workspaces"] as? [String: Any],
           let packages = workspaces["packages"] as? [String] {
            return packages
        }
        return []
    }

    private func pnpmWorkspacePatterns(in root: URL) -> [String] {
        let url = root.appendingPathComponent("pnpm-workspace.yaml", isDirectory: false)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("-") else { return nil }
            let value = line.dropFirst().trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            return value.isEmpty || value.hasPrefix("!") ? nil : value
        }
    }

    private func expandWorkspacePattern(_ rawPattern: String, relativeTo root: URL) -> [URL] {
        let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty, !pattern.hasPrefix("!"), !pattern.hasPrefix("/") else { return [] }
        let components = pattern.split(separator: "/").map(String.init)
        guard !components.isEmpty, components.count <= 4 else { return [] }

        var current = [root]
        for component in components {
            if component == "*" || component == "**" {
                current = current.flatMap { directory in
                    (try? FileManager.default.contentsOfDirectory(
                        at: directory,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ))?.filter {
                        let name = $0.lastPathComponent
                        guard !Self.ignoredDirectoryNames.contains(name) else { return false }
                        return (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                    } ?? []
                }
            } else if component.contains("*") {
                let regex = wildcardRegex(component)
                current = current.flatMap { directory in
                    (try? FileManager.default.contentsOfDirectory(
                        at: directory,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ))?.filter {
                        regex.firstMatch(
                            in: $0.lastPathComponent,
                            range: NSRange($0.lastPathComponent.startIndex..., in: $0.lastPathComponent)
                        ) != nil
                            && (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                    } ?? []
                }
            } else {
                current = current.map { $0.appendingPathComponent(component, isDirectory: true) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
            }
        }
        return current
    }

    private func wildcardRegex(_ component: String) -> NSRegularExpression {
        let escaped = NSRegularExpression.escapedPattern(for: component)
            .replacingOccurrences(of: "\\*", with: ".*")
        return (try? NSRegularExpression(pattern: "^\(escaped)$"))
            ?? (try! NSRegularExpression(pattern: "a^"))
    }

    private func packageCandidates(in componentRoot: URL, projectRoot: URL) -> [Candidate] {
        let manifestURL = componentRoot.appendingPathComponent("package.json", isDirectory: false)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PackageManifest.self, from: data),
              !manifest.scripts.isEmpty else {
            return []
        }

        let packageManager = detectPackageManager(manifest: manifest, directory: componentRoot)
        let dependencyNames = Set(manifest.dependencies.keys).union(manifest.devDependencies.keys)
        let hasElectron = dependencyNames.contains("electron")
            || dependencyNames.contains("electron-builder")
            || dependencyNames.contains("@electron-forge/cli")
        let hasWebFramework = !dependencyNames.intersection(Self.webFrameworkPackages).isEmpty
        let relativeComponent = relativePath(componentRoot, to: projectRoot)
        let componentLabel = relativeComponent == "."
            ? (manifest.name ?? projectRoot.lastPathComponent)
            : (manifest.name ?? relativeComponent)

        var selectedScriptNames: [String] = []
        let specializedElectron = ["electron:dev", "dev:electron", "desktop:dev", "dev:desktop", "electron", "desktop"]
            .first { manifest.scripts[$0] != nil }
        if let specializedElectron {
            selectedScriptNames.append(specializedElectron)
        }
        if let general = ["dev", "start", "serve", "preview"].first(where: { manifest.scripts[$0] != nil }),
           general != specializedElectron {
            selectedScriptNames.append(general)
        }

        return selectedScriptNames.enumerated().compactMap { index, scriptName in
            guard let script = manifest.scripts[scriptName] else { return nil }
            let scriptSuggestsElectron = scriptName.localizedCaseInsensitiveContains("electron")
                || scriptName.localizedCaseInsensitiveContains("desktop")
                || script.localizedCaseInsensitiveContains("electron")
            let kind: ProjectLaunchKind
            if scriptSuggestsElectron || (hasElectron && specializedElectron == nil) {
                kind = .electron
            } else if hasWebFramework || scriptName == "dev" || scriptName == "serve" || scriptName == "preview" {
                kind = .web
            } else {
                kind = .node
            }

            let title = relativeComponent == "."
                ? kind.title
                : "\(kind.title) · \(componentLabel)"
            return candidate(
                projectRoot: projectRoot,
                componentRoot: componentRoot,
                key: "package:\(relativeComponent):\(scriptName)",
                title: title,
                detail: "\(packageManager) run \(scriptName)",
                kind: kind,
                command: ProjectLaunchCommand(
                    executablePath: "/usr/bin/env",
                    arguments: [packageManager, "run", scriptName]
                ),
                lifecycle: .longRunning,
                confidence: .high,
                sourcePath: relativePath(manifestURL, to: projectRoot),
                priority: 94 - index
            )
        }
    }

    private func detectPackageManager(manifest: PackageManifest, directory: URL) -> String {
        if let explicit = manifest.packageManager?.split(separator: "@").first,
           !explicit.isEmpty {
            return String(explicit)
        }
        let markers: [(String, String)] = [
            ("bun.lock", "bun"),
            ("bun.lockb", "bun"),
            ("pnpm-lock.yaml", "pnpm"),
            ("yarn.lock", "yarn"),
            ("package-lock.json", "npm"),
            ("npm-shrinkwrap.json", "npm"),
        ]
        for marker in markers where FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(marker.0, isDirectory: false).path
        ) {
            return marker.1
        }
        return "npm"
    }

    // MARK: - Docker

    private func dockerCandidates(in componentRoot: URL, projectRoot: URL) -> [Candidate] {
        let filenames = ["compose.yaml", "compose.yml", "docker-compose.yml", "docker-compose.yaml"]
        guard let filename = filenames.first(where: {
            FileManager.default.fileExists(atPath: componentRoot.appendingPathComponent($0, isDirectory: false).path)
        }) else { return [] }
        let relativeComponent = relativePath(componentRoot, to: projectRoot)
        let title = relativeComponent == "." ? "Docker" : "Docker · \(relativeComponent)"
        return [candidate(
            projectRoot: projectRoot,
            componentRoot: componentRoot,
            key: "docker:\(relativeComponent):\(filename)",
            title: title,
            detail: filename,
            kind: .docker,
            command: ProjectLaunchCommand(
                executablePath: "/usr/bin/env",
                arguments: ["docker", "compose", "-f", filename, "up"]
            ),
            stopCommand: ProjectLaunchCommand(
                executablePath: "/usr/bin/env",
                arguments: ["docker", "compose", "-f", filename, "down"]
            ),
            lifecycle: .longRunning,
            confidence: .high,
            sourcePath: relativePath(componentRoot.appendingPathComponent(filename), to: projectRoot),
            priority: 88
        )]
    }

    // MARK: - Conventional build tools

    private func makeCandidates(in root: URL) -> [Candidate] {
        let url = root.appendingPathComponent("Makefile", isDirectory: false)
        guard let target = firstTarget(in: url, candidates: ["dev", "run", "start", "serve"]) else { return [] }
        return [candidate(
            projectRoot: root,
            componentRoot: root,
            key: "make:\(target)",
            title: "Make · \(target)",
            detail: "make \(target)",
            kind: .make,
            command: ProjectLaunchCommand(executablePath: "/usr/bin/make", arguments: [target]),
            lifecycle: .longRunning,
            confidence: .medium,
            sourcePath: "Makefile",
            priority: 76
        )]
    }

    private func justCandidates(in root: URL) -> [Candidate] {
        let url = root.appendingPathComponent("Justfile", isDirectory: false)
        guard let target = firstTarget(in: url, candidates: ["dev", "run", "start", "serve"]) else { return [] }
        return [candidate(
            projectRoot: root,
            componentRoot: root,
            key: "just:\(target)",
            title: "Just · \(target)",
            detail: "just \(target)",
            kind: .just,
            command: ProjectLaunchCommand(executablePath: "/usr/bin/env", arguments: ["just", target]),
            lifecycle: .longRunning,
            confidence: .medium,
            sourcePath: "Justfile",
            priority: 75
        )]
    }

    private func firstTarget(in url: URL, candidates: [String]) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let targets = Set(text.split(separator: "\n").compactMap { rawLine -> String? in
            let line = String(rawLine)
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains(" "), !name.hasPrefix(".") else { return nil }
            return name
        })
        return candidates.first { targets.contains($0) }
    }

    private func cargoCandidates(in root: URL) -> [Candidate] {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Cargo.toml").path) else { return [] }
        return [candidate(
            projectRoot: root,
            componentRoot: root,
            key: "cargo:run",
            title: "Rust",
            detail: "cargo run",
            kind: .rust,
            command: ProjectLaunchCommand(executablePath: "/usr/bin/env", arguments: ["cargo", "run"]),
            lifecycle: .longRunning,
            confidence: .high,
            sourcePath: "Cargo.toml",
            priority: 84
        )]
    }

    private func pythonCandidates(in root: URL) -> [Candidate] {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("manage.py").path) else { return [] }
        return [candidate(
            projectRoot: root,
            componentRoot: root,
            key: "django:runserver",
            title: "Django",
            detail: "python3 manage.py runserver",
            kind: .python,
            command: ProjectLaunchCommand(
                executablePath: "/usr/bin/env",
                arguments: ["python3", "manage.py", "runserver"]
            ),
            lifecycle: .longRunning,
            confidence: .high,
            sourcePath: "manage.py",
            priority: 84
        )]
    }

    private func xcodeCandidates(in root: URL) -> [Candidate] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let workspace = contents
            .filter { $0.pathExtension == "xcworkspace" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
        let project = contents
            .filter { $0.pathExtension == "xcodeproj" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
        guard let selected = workspace ?? project else { return [] }
        return [candidate(
            projectRoot: root,
            componentRoot: root,
            key: "xcode:\(selected.lastPathComponent)",
            title: "Open in Xcode",
            detail: selected.lastPathComponent,
            kind: .xcode,
            command: ProjectLaunchCommand(executablePath: "/usr/bin/open", arguments: [selected.path]),
            lifecycle: .oneShot,
            confidence: .medium,
            sourcePath: selected.lastPathComponent,
            priority: 42
        )]
    }

    // MARK: - Candidate construction

    private func candidate(
        projectRoot: URL,
        componentRoot: URL,
        key: String,
        title: String,
        detail: String,
        kind: ProjectLaunchKind,
        command: ProjectLaunchCommand,
        stopCommand: ProjectLaunchCommand? = nil,
        lifecycle: ProjectLaunchLifecycle,
        confidence: ProjectLaunchConfidence,
        sourcePath: String,
        priority: Int
    ) -> Candidate {
        let id = "\(projectRoot.path)|\(key)"
        return Candidate(action: ProjectLaunchAction(
            id: id,
            title: title,
            detail: detail,
            kind: kind,
            workingDirectory: componentRoot.path,
            command: command,
            stopCommand: stopCommand,
            lifecycle: lifecycle,
            confidence: confidence,
            sourcePath: sourcePath,
            priority: priority
        ))
    }

    private func deduplicated(_ candidates: [Candidate]) -> [Candidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            let action = candidate.action
            let key = "\(action.workingDirectory)|\(action.command.executablePath)|\(action.command.arguments.joined(separator: "\u{1f}"))"
            return seen.insert(key).inserted
        }
    }

    private func relativePath(_ url: URL, to root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path != rootPath else { return "." }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    private struct Candidate {
        let action: ProjectLaunchAction
        var priority: Int { action.priority }
        var title: String { action.title }
    }

    private struct PackageManifest: Decodable {
        var name: String?
        var scripts: [String: String] = [:]
        var dependencies: [String: String] = [:]
        var devDependencies: [String: String] = [:]
        var packageManager: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case scripts
            case dependencies
            case devDependencies
            case packageManager
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            scripts = try container.decodeIfPresent([String: String].self, forKey: .scripts) ?? [:]
            dependencies = try container.decodeIfPresent([String: String].self, forKey: .dependencies) ?? [:]
            devDependencies = try container.decodeIfPresent([String: String].self, forKey: .devDependencies) ?? [:]
            packageManager = try container.decodeIfPresent(String.self, forKey: .packageManager)
        }
    }

    private static let ignoredDirectoryNames: Set<String> = [
        ".git", ".build", ".swiftpm", "node_modules", "vendor", "dist", "build", "DerivedData", "Pods"
    ]

    private static let webFrameworkPackages: Set<String> = [
        "vite", "next", "nuxt", "astro", "react-scripts", "@angular/core", "@sveltejs/kit", "gatsby"
    ]
}
