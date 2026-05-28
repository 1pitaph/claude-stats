import Foundation

enum ConfigurationEditorServiceError: LocalizedError, Sendable {
    case snapshotNotFound

    var errorDescription: String? {
        switch self {
        case .snapshotNotFound:
            "The selected configuration file could not be found in this profile."
        }
    }
}

struct ConfigurationEditorDiagnostic: Identifiable, Sendable, Hashable {
    enum Severity: String, Sendable, Hashable {
        case info
        case warning
        case error
    }

    let id: String
    let severity: Severity
    let message: String
    let line: Int?
    let column: Int?

    var locationDisplay: String? {
        guard let line else { return nil }
        if let column {
            return "Line \(line), column \(column)"
        }
        return "Line \(line)"
    }
}

struct ConfigurationEditorDiskSaveResult: Sendable, Hashable {
    let updatedProfile: ConfigProfile
    let backupDirectory: URL
    let savedAt: Date
}

struct ConfigurationEditorService: Sendable {
    let profileStore: ConfigurationProfileStore

    init(profileStore: ConfigurationProfileStore = ConfigurationProfileStore()) {
        self.profileStore = profileStore
    }

    func profileByUpdatingSnapshot(
        _ profile: ConfigProfile,
        snapshotID: UUID,
        content: String,
        updatedAt: Date = .now
    ) throws -> ConfigProfile {
        var updatedProfile = profile
        guard let index = updatedProfile.files.firstIndex(where: { $0.id == snapshotID }) else {
            throw ConfigurationEditorServiceError.snapshotNotFound
        }

        updatedProfile.files[index].content = content
        updatedProfile.files[index].contentHash = ConfigurationProfileStore.hash(content)
        updatedProfile.files[index].capturedAt = updatedAt
        updatedProfile.updatedAt = updatedAt
        return updatedProfile
    }

    func saveSnapshotToDisk(
        profile: ConfigProfile,
        snapshotID: UUID,
        content: String
    ) async throws -> ConfigurationEditorDiskSaveResult {
        let updatedAt = Date()
        let updatedProfile = try profileByUpdatingSnapshot(
            profile,
            snapshotID: snapshotID,
            content: content,
            updatedAt: updatedAt
        )
        guard let snapshot = updatedProfile.files.first(where: { $0.id == snapshotID }) else {
            throw ConfigurationEditorServiceError.snapshotNotFound
        }

        let singleFileProfile = ConfigProfile(
            id: updatedProfile.id,
            provider: updatedProfile.provider,
            scope: updatedProfile.scope,
            name: updatedProfile.name,
            files: [snapshot],
            createdAt: updatedProfile.createdAt,
            updatedAt: updatedProfile.updatedAt,
            lastAppliedAt: updatedProfile.lastAppliedAt
        )
        let result = try await profileStore.apply(singleFileProfile)
        return ConfigurationEditorDiskSaveResult(
            updatedProfile: updatedProfile,
            backupDirectory: result.backupDirectory,
            savedAt: result.appliedAt
        )
    }

    func diagnostics(for content: String, kind: ProviderConfigFileKind) async -> [ConfigurationEditorDiagnostic] {
        await Task.detached(priority: .utility) {
            Self.diagnosticsSync(for: content, kind: kind)
        }.value
    }

    static func diagnosticsSync(for content: String, kind: ProviderConfigFileKind) -> [ConfigurationEditorDiagnostic] {
        switch kind {
        case .json:
            jsonDiagnostics(for: content)
        case .markdown:
            markdownDiagnostics(for: content)
        case .toml:
            tomlDiagnostics(for: content)
        case .text:
            []
        }
    }

    private static func jsonDiagnostics(for content: String) -> [ConfigurationEditorDiagnostic] {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        do {
            _ = try JSONSerialization.jsonObject(with: Data(content.utf8), options: [.fragmentsAllowed])
            return []
        } catch {
            let location = jsonErrorLocation(from: error.localizedDescription)
            let message = error.localizedDescription
            return [
                ConfigurationEditorDiagnostic(
                    id: "json:\(location.line ?? 0):\(location.column ?? 0):\(message)",
                    severity: .error,
                    message: message,
                    line: location.line,
                    column: location.column
                ),
            ]
        }
    }

    private static func markdownDiagnostics(for content: String) -> [ConfigurationEditorDiagnostic] {
        var fenceCount = 0
        var lastFenceLine: Int?

        for (offset, line) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if String(line).trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                fenceCount += 1
                lastFenceLine = offset + 1
            }
        }

        guard !fenceCount.isMultiple(of: 2), let lastFenceLine else { return [] }
        return [
            ConfigurationEditorDiagnostic(
                id: "markdown:fence:\(lastFenceLine)",
                severity: .warning,
                message: "Code fence is not closed.",
                line: lastFenceLine,
                column: nil
            ),
        ]
    }

    private static func tomlDiagnostics(for content: String) -> [ConfigurationEditorDiagnostic] {
        guard content.utf8.count <= AIConfigScanner.previewByteLimit else {
            return [
                ConfigurationEditorDiagnostic(
                    id: "toml:large",
                    severity: .warning,
                    message: "Large TOML file skipped for syntax diagnostics.",
                    line: nil,
                    column: nil
                ),
            ]
        }

        var diagnostics: [ConfigurationEditorDiagnostic] = []
        var currentSection: String?
        let allowedTopLevelKeys: Set<String> = [
            "model", "model_provider", "model_reasoning_effort", "model_reasoning_summary",
            "approval_policy", "sandbox_mode", "notify", "hide_agent_reasoning",
            "network_access", "cwd", "tools", "shell_environment_policy",
        ]

        for (offset, rawLine) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = offset + 1
            let line = stripTOMLComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[") {
                guard line.hasSuffix("]"), line.count > 2 else {
                    diagnostics.append(
                        ConfigurationEditorDiagnostic(
                            id: "toml:section:\(lineNumber)",
                            severity: .error,
                            message: "TOML section header is not closed.",
                            line: lineNumber,
                            column: line.firstIndex(of: "[").map { line.distance(from: line.startIndex, to: $0) + 1 }
                        )
                    )
                    continue
                }
                currentSection = String(line.dropFirst().dropLast())
                continue
            }

            guard let equals = line.firstIndex(of: "=") else {
                diagnostics.append(
                    ConfigurationEditorDiagnostic(
                        id: "toml:assignment:\(lineNumber)",
                        severity: .error,
                        message: "TOML key/value lines must contain '='.",
                        line: lineNumber,
                        column: nil
                    )
                )
                continue
            }

            let key = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if key.isEmpty {
                diagnostics.append(
                    ConfigurationEditorDiagnostic(
                        id: "toml:key:\(lineNumber)",
                        severity: .error,
                        message: "TOML key is empty.",
                        line: lineNumber,
                        column: 1
                    )
                )
            }
            if value.isEmpty {
                diagnostics.append(
                    ConfigurationEditorDiagnostic(
                        id: "toml:value:\(lineNumber)",
                        severity: .error,
                        message: "TOML value is empty.",
                        line: lineNumber,
                        column: line.distance(from: line.startIndex, to: equals) + 2
                    )
                )
            } else if let message = tomlValueProblem(value) {
                diagnostics.append(
                    ConfigurationEditorDiagnostic(
                        id: "toml:value:\(lineNumber):\(message)",
                        severity: .error,
                        message: message,
                        line: lineNumber,
                        column: line.distance(from: line.startIndex, to: equals) + 2
                    )
                )
            }

            if currentSection == nil, !key.isEmpty, !allowedTopLevelKeys.contains(key) {
                diagnostics.append(
                    ConfigurationEditorDiagnostic(
                        id: "toml:unknown:\(lineNumber):\(key)",
                        severity: .info,
                        message: "Unknown top-level TOML key '\(key)'.",
                        line: lineNumber,
                        column: 1
                    )
                )
            }
        }
        return diagnostics
    }

    private static func stripTOMLComment(_ line: String) -> String {
        var inString = false
        var escaped = false
        var result = ""
        for character in line {
            if character == "\\" && inString {
                escaped.toggle()
                result.append(character)
                continue
            }
            if character == "\"", !escaped {
                inString.toggle()
            }
            escaped = false
            if character == "#", !inString {
                break
            }
            result.append(character)
        }
        return result
    }

    private static func tomlValueProblem(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\"") {
            return stringIsClosed(trimmed) ? nil : "TOML string is not closed."
        }
        if trimmed.hasPrefix("[") && !trimmed.hasSuffix("]") {
            return "TOML array is not closed."
        }
        if trimmed.hasPrefix("{") && !trimmed.hasSuffix("}") {
            return "TOML inline table is not closed."
        }
        return nil
    }

    private static func stringIsClosed(_ value: String) -> Bool {
        var escaped = false
        for character in value.dropFirst() {
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if character == "\"" {
                return true
            }
        }
        return false
    }

    private static func jsonErrorLocation(from message: String) -> (line: Int?, column: Int?) {
        guard let regex = try? NSRegularExpression(pattern: #"line\s+(\d+),\s+column\s+(\d+)"#, options: [.caseInsensitive]) else {
            return (nil, nil)
        }
        let nsMessage = message as NSString
        let range = NSRange(location: 0, length: nsMessage.length)
        guard let match = regex.firstMatch(in: message, range: range), match.numberOfRanges >= 3 else {
            return (nil, nil)
        }
        let line = Int(nsMessage.substring(with: match.range(at: 1)))
        let column = Int(nsMessage.substring(with: match.range(at: 2)))
        return (line, column)
    }
}
