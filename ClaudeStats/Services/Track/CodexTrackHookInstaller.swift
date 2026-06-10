import Foundation

struct CodexTrackHookInstallationStatus: Sendable, Hashable {
    let hookConfigURL: URL
    let codexConfigURL: URL
    let installedHookURL: URL
    let eventLogURL: URL
    let configuredEvents: Set<String>
    let missingEvents: Set<String>
    let hooksFeatureEnabled: Bool
    let helperInstalled: Bool
    let eventLogExists: Bool

    var isInstalled: Bool {
        helperInstalled && missingEvents.isEmpty && hooksFeatureEnabled
    }

    var statusTitle: String {
        if isInstalled { return "Installed" }
        if !helperInstalled { return "Helper missing" }
        if !hooksFeatureEnabled { return "Hooks disabled" }
        return "Needs repair"
    }

    var statusDetail: String {
        if isInstalled {
            return "Codex hooks are writing Track events to Claude Stats."
        }
        if !missingEvents.isEmpty {
            return "Missing \(missingEvents.sorted().joined(separator: ", ")) hooks."
        }
        if !hooksFeatureEnabled {
            return "Codex hooks are not enabled in config.toml."
        }
        return "Install the Track hook helper to capture subagents, tools, and approvals."
    }
}

struct CodexTrackHookInstallResult: Sendable, Hashable {
    let status: CodexTrackHookInstallationStatus
    let installedAt: Date
}

struct CodexTrackHookInstaller: @unchecked Sendable {
    var codexHome: URL
    var appSupportDirectory: URL
    var fileManager: FileManager
    var hookScriptBody: String

    static let requiredEvents: Set<String> = [
        "SessionStart",
        "UserPromptSubmit",
        "SubagentStart",
        "SubagentStop",
        "PreToolUse",
        "PermissionRequest",
        "PostToolUse",
        "Stop",
    ]

    init(
        codexHome: URL = CodexPaths.default.homeDirectory,
        appSupportDirectory: URL = CodexTrackHookInstaller.defaultAppSupportDirectory(),
        fileManager: FileManager = .default,
        hookScriptBody: String = CodexTrackHookInstaller.defaultHookScript
    ) {
        self.codexHome = codexHome
        self.appSupportDirectory = appSupportDirectory
        self.fileManager = fileManager
        self.hookScriptBody = hookScriptBody
    }

    var trackDirectory: URL {
        appSupportDirectory
            .appendingPathComponent("ClaudeStats", isDirectory: true)
            .appendingPathComponent("Track", isDirectory: true)
    }

    var eventLogURL: URL {
        trackDirectory.appendingPathComponent("events.jsonl", isDirectory: false)
    }

    var installedHookURL: URL {
        trackDirectory.appendingPathComponent("codex-track-hook.js", isDirectory: false)
    }

    var hookConfigURL: URL {
        codexHome.appendingPathComponent("hooks.json", isDirectory: false)
    }

    var codexConfigURL: URL {
        codexHome.appendingPathComponent("config.toml", isDirectory: false)
    }

    func status() -> CodexTrackHookInstallationStatus {
        let configuredEvents = configuredTrackHookEvents()
        return CodexTrackHookInstallationStatus(
            hookConfigURL: hookConfigURL,
            codexConfigURL: codexConfigURL,
            installedHookURL: installedHookURL,
            eventLogURL: eventLogURL,
            configuredEvents: configuredEvents,
            missingEvents: Self.requiredEvents.subtracting(configuredEvents),
            hooksFeatureEnabled: codexHooksFeatureEnabled(),
            helperInstalled: fileManager.fileExists(atPath: installedHookURL.path),
            eventLogExists: fileManager.fileExists(atPath: eventLogURL.path)
        )
    }

    func install(now: Date = .now) throws -> CodexTrackHookInstallResult {
        try fileManager.createDirectory(at: trackDirectory, withIntermediateDirectories: true)
        try hookScriptBody.data(using: .utf8)?.write(to: installedHookURL, options: [.atomic])
        try ensureHookConfig()
        try ensureCodexHooksFeatureEnabled()
        return CodexTrackHookInstallResult(status: status(), installedAt: now)
    }

    private func ensureHookConfig() throws {
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        var root = try readJSONObject(at: hookConfigURL) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in Self.requiredEvents.sorted() {
            var groups = hooks[event] as? [[String: Any]] ?? []
            if !groupsContainsTrackHook(groups) {
                groups.append([
                    "hooks": [[
                        "type": "command",
                        "command": hookCommand(),
                        "timeout": event == "PermissionRequest" ? 30 : 10,
                    ]],
                ])
            }
            hooks[event] = groups
        }
        root["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: hookConfigURL, options: [.atomic])
    }

    private func readJSONObject(at url: URL) throws -> [String: Any]? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func configuredTrackHookEvents() -> Set<String> {
        guard let root = try? readJSONObject(at: hookConfigURL),
              let hooks = root["hooks"] as? [String: Any] else { return [] }
        return Set(hooks.compactMap { event, value in
            guard let groups = value as? [[String: Any]],
                  groupsContainsTrackHook(groups) else { return nil }
            return event
        })
    }

    private func groupsContainsTrackHook(_ groups: [[String: Any]]) -> Bool {
        groups.contains { group in
            guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
            return hooks.contains { hook in
                guard let command = hook["command"] as? String else { return false }
                return command.contains("codex-track-hook.js") || command.contains("CLAUDE_STATS_TRACK_EVENT_LOG")
            }
        }
    }

    private func hookCommand() -> String {
        let eventLog = shellQuoted(eventLogURL.path)
        let script = shellQuoted(installedHookURL.path)
        return "CLAUDE_STATS_TRACK_EVENT_LOG=\(eventLog) /usr/bin/env node \(script)"
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func ensureCodexHooksFeatureEnabled() throws {
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: codexConfigURL, encoding: .utf8)) ?? ""
        let updated = Self.configByEnablingHooks(existing)
        guard updated != existing else { return }
        try updated.data(using: .utf8)?.write(to: codexConfigURL, options: [.atomic])
    }

    private func codexHooksFeatureEnabled() -> Bool {
        guard let content = try? String(contentsOf: codexConfigURL, encoding: .utf8) else { return false }
        return Self.configHasHooksEnabled(content)
    }

    static func configHasHooksEnabled(_ content: String) -> Bool {
        var currentSection: String?
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripTOMLComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast())
                continue
            }
            guard currentSection == "features",
                  let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces).lowercased()
            if key == "hooks" { return value == "true" }
        }
        return false
    }

    static func configByEnablingHooks(_ content: String) -> String {
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var featuresStart: Int?
        var featuresEnd = lines.count
        var hooksLine: Int?

        for index in lines.indices {
            let stripped = stripTOMLComment(lines[index]).trimmingCharacters(in: .whitespaces)
            guard !stripped.isEmpty else { continue }
            if stripped.hasPrefix("[") && stripped.hasSuffix("]") {
                let section = String(stripped.dropFirst().dropLast())
                if section == "features" {
                    featuresStart = index
                    featuresEnd = lines.count
                } else if featuresStart != nil && hooksLine == nil {
                    featuresEnd = min(featuresEnd, index)
                    break
                }
                continue
            }
            guard featuresStart != nil,
                  let equals = stripped.firstIndex(of: "=") else { continue }
            let key = stripped[..<equals].trimmingCharacters(in: .whitespaces)
            if key == "hooks" {
                hooksLine = index
                break
            }
        }

        if let hooksLine {
            lines[hooksLine] = "hooks = true"
        } else if let featuresStart {
            lines.insert("hooks = true", at: featuresStart + 1)
        } else {
            if !lines.isEmpty, lines.last != "" { lines.append("") }
            lines.append("[features]")
            lines.append("hooks = true")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    private static func stripTOMLComment(_ line: String) -> String {
        var inString = false
        var escaped = false
        var result = ""
        for character in line {
            if escaped {
                result.append(character)
                escaped = false
                continue
            }
            if character == "\\" && inString {
                result.append(character)
                escaped = true
                continue
            }
            if character == "\"" {
                result.append(character)
                inString.toggle()
                continue
            }
            if character == "#", !inString { break }
            result.append(character)
        }
        return result
    }

    private static func defaultAppSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
    }
}

extension CodexTrackHookInstaller {
    static let defaultHookScript = #"""
#!/usr/bin/env node
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");

function readStdin() {
  return new Promise((resolve) => {
    let body = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => { body += chunk; });
    process.stdin.on("end", () => resolve(body));
  });
}

function parseJSON(raw) {
  try { return JSON.parse(raw || "{}"); } catch { return {}; }
}

function firstString(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
}

function eventLogPath() {
  if (process.env.CLAUDE_STATS_TRACK_EVENT_LOG) return process.env.CLAUDE_STATS_TRACK_EVENT_LOG;
  if (process.platform === "darwin") {
    return path.join(os.homedir(), "Library", "Application Support", "ClaudeStats", "Track", "events.jsonl");
  }
  return path.join(os.homedir(), ".claude-stats", "track", "events.jsonl");
}

function sessionIdFromTranscript(transcriptPath) {
  if (typeof transcriptPath !== "string" || !transcriptPath.trim()) return "";
  const fileName = path.basename(transcriptPath.replace(/\\/g, "/"));
  const match = fileName.match(/^rollout-.+-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$/i);
  return match ? match[1] : "";
}

function normalizeSessionId(value, transcriptPath) {
  const raw = firstString(sessionIdFromTranscript(transcriptPath), value, "default");
  return raw.startsWith("codex:") ? raw.slice("codex:".length) : raw;
}

function readSessionMeta(transcriptPath) {
  if (typeof transcriptPath !== "string" || !transcriptPath.trim()) return {};
  try {
    const fd = fs.openSync(transcriptPath, "r");
    try {
      const buf = Buffer.alloc(65536);
      const bytes = fs.readSync(fd, buf, 0, buf.length, 0);
      const firstLine = buf.subarray(0, bytes).toString("utf8").split("\n")[0];
      const parsed = parseJSON(firstLine);
      return parsed && parsed.type === "session_meta" && parsed.payload && typeof parsed.payload === "object"
        ? parsed.payload
        : {};
    } finally {
      fs.closeSync(fd);
    }
  } catch {
    return {};
  }
}

function normalizeRole(value) {
  if (typeof value !== "string") return "";
  const role = value.trim().toLowerCase();
  if (["subagent", "child", "delegate", "delegated", "explorer", "worker"].includes(role)) return "subagent";
  if (["root", "main", "primary", "cli", "codex-cli", "codex-tui"].includes(role)) return "root";
  return "";
}

function roleFromSource(source) {
  if (source && typeof source === "object" && !Array.isArray(source)) {
    if (Object.prototype.hasOwnProperty.call(source, "subagent")) {
      return source.subagent === false || source.subagent === null ? "root" : "subagent";
    }
    return normalizeRole(source.role || source.type || source.kind);
  }
  return normalizeRole(source);
}

function pickParentId(payload, meta) {
  return firstString(
    payload.parent_session_id,
    payload.parentSessionId,
    payload.parentSessionID,
    payload.parent_thread_id,
    payload.parentThreadId,
    meta.parent_session_id,
    meta.parentSessionId,
    meta.parent_thread_id,
    meta.parentThreadId
  );
}

function pickAgentType(payload, meta) {
  return firstString(
    payload.agent_type,
    payload.agentType,
    meta.agent_type,
    meta.agentType,
    normalizeRole(payload.codex_session_role),
    normalizeRole(payload.agent_role),
    roleFromSource(payload.source),
    normalizeRole(meta.codex_session_role),
    normalizeRole(meta.agent_role),
    roleFromSource(meta.source)
  );
}

function normalizeEvent(payload) {
  const hookName = firstString(payload.hook_event_name, payload.hookEventName, payload.eventName, payload.type, "StatusChanged");
  const meta = readSessionMeta(payload.transcript_path);
  const sessionID = normalizeSessionId(payload.session_id || payload.sessionID, payload.transcript_path);
  const parentSessionID = pickParentId(payload, meta);
  const agentType = pickAgentType(payload, meta);
  const toolInput = payload.tool_input && typeof payload.tool_input === "object" ? payload.tool_input : undefined;
  const out = {
    received_at: new Date().toISOString(),
    source: "hook",
    session_id: sessionID,
    hook_event_name: hookName,
  };

  const stringFields = {
    parent_session_id: parentSessionID,
    turn_id: firstString(payload.turn_id, payload.turnID),
    agent_id: firstString(payload.agent_id, payload.agentID, meta.agent_id, meta.agentID),
    agent_type: agentType,
    tool_use_id: firstString(payload.tool_use_id, payload.toolUseId, payload.toolUseID),
    approval_id: firstString(payload.approval_id, payload.approvalID),
    tool_name: firstString(payload.tool_name, payload.toolName),
    permission_mode: firstString(payload.permission_mode, payload.permissionMode),
    cwd: firstString(payload.cwd, meta.cwd),
    transcript_path: firstString(payload.transcript_path),
    status: firstString(payload.status),
    decision: firstString(payload.decision, payload.behavior),
    message: firstString(payload.message),
    summary: firstString(payload.summary),
  };
  for (const [key, value] of Object.entries(stringFields)) {
    if (value) out[key] = value;
  }
  if (toolInput) out.tool_input = toolInput;
  if (payload.error !== undefined) out.error = payload.error;
  return out;
}

async function main() {
  const payload = parseJSON(await readStdin());
  try {
    const line = JSON.stringify(normalizeEvent(payload)) + "\n";
    const target = eventLogPath();
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.appendFileSync(target, line, "utf8");
  } catch {
    // Hooks should never break Codex execution.
  }

  if (payload && (payload.hook_event_name === "PermissionRequest" || payload.hookEventName === "PermissionRequest")) {
    process.stdout.write("{}\n");
  }
}

main().then(() => process.exit(0)).catch(() => process.exit(0));
"""#
}
