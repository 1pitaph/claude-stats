import Foundation

struct CodexUsageLimitLoader: Sendable {
    let paths: CodexPaths

    static let snapshotTTL: TimeInterval = 30 * 60
    private static let maxCandidateFiles = 64
    private static let resourceKeys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]

    func report(now: Date = .now, fileManager: FileManager = .default) -> UsageLimitReport {
        guard fileManager.fileExists(atPath: paths.sessionsDirectory.path) else {
            return .waitingForNextResponse(
                provider: .codex,
                snapshot: nil,
                message: "Codex usage limits will appear after the next Codex response."
            )
        }

        do {
            guard let snapshot = try latestSnapshot(fileManager: fileManager) else {
                return .waitingForNextResponse(
                    provider: .codex,
                    snapshot: nil,
                    message: "Waiting for a Codex response with usage-limit data."
                )
            }
            guard snapshot.isFresh(now: now, ttl: Self.snapshotTTL) else {
                return .cached(provider: .codex, snapshot: snapshot)
            }
            return .fresh(provider: .codex, snapshot: snapshot)
        } catch {
            return .unavailable(provider: .codex, message: "Could not read Codex usage limits: \(error.localizedDescription)")
        }
    }

    func history(since: Date, now: Date = .now, fileManager: FileManager = .default) -> [UsageLimitHistoryEntry] {
        guard fileManager.fileExists(atPath: paths.sessionsDirectory.path) else { return [] }
        do {
            return try rolloutCandidates(fileManager: fileManager)
                .flatMap { candidate in
                    try snapshots(in: candidate.url, fallbackCapturedAt: candidate.modifiedAt)
                }
                .filter { $0.capturedAt >= since && $0.capturedAt <= now.addingTimeInterval(60) }
                .flatMap { snapshot in
                    UsageLimitHistoryStore.entries(from: snapshot).filter { entry in
                        guard let resetAt = entry.resetAt else { return false }
                        return resetAt > entry.capturedAt
                    }
                }
                .sorted { $0.capturedAt < $1.capturedAt }
        } catch {
            return []
        }
    }

    private func latestSnapshot(fileManager: FileManager) throws -> UsageLimitSnapshot? {
        for candidate in try rolloutCandidates(fileManager: fileManager).prefix(Self.maxCandidateFiles) {
            if let snapshot = try latestSnapshot(in: candidate.url, fallbackCapturedAt: candidate.modifiedAt) {
                return snapshot
            }
        }
        return nil
    }

    private func rolloutCandidates(fileManager: FileManager) throws -> [Candidate] {
        guard let enumerator = fileManager.enumerator(
            at: paths.sessionsDirectory,
            includingPropertiesForKeys: Self.resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var out: [Candidate] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-") {
            let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys))
            guard values?.isRegularFile == true else { continue }
            out.append(Candidate(url: url, modifiedAt: values?.contentModificationDate ?? .distantPast))
        }
        return out.sorted { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt {
                return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedDescending
            }
            return lhs.modifiedAt > rhs.modifiedAt
        }
    }

    private func latestSnapshot(in url: URL, fallbackCapturedAt: Date) throws -> UsageLimitSnapshot? {
        try snapshots(in: url, fallbackCapturedAt: fallbackCapturedAt).last
    }

    private func snapshots(in url: URL, fallbackCapturedAt: Date) throws -> [UsageLimitSnapshot] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        var snapshots: [UsageLimitSnapshot] = []
        for lineBytes in data.split(separator: 0x0A /* \n */, omittingEmptySubsequences: true) {
            guard let line = try? decoder.decode(CodexUsageLimitLine.self, from: Data(lineBytes)),
                  line.type == "event_msg",
                  line.payload?.type == "token_count",
                  let rateLimits = line.payload?.rateLimits,
                  let snapshot = rateLimits.snapshot(
                    capturedAt: UsageLimitDateParser.date(from: line.timestamp ?? "") ?? fallbackCapturedAt,
                    sourcePath: url.path
                  ) else {
                continue
            }
            snapshots.append(snapshot)
        }
        return snapshots
    }

    private struct Candidate {
        let url: URL
        let modifiedAt: Date
    }
}

private struct CodexUsageLimitLine: Decodable {
    let timestamp: String?
    let type: String?
    let payload: Payload?

    struct Payload: Decodable {
        let type: String?
        let rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case type
            case rateLimits = "rate_limits"
        }
    }

    struct RateLimits: Decodable {
        let limitID: String?
        let planType: String?
        let primary: Window?
        let secondary: Window?

        enum CodingKeys: String, CodingKey {
            case limitID = "limit_id"
            case planType = "plan_type"
            case primary
            case secondary
        }

        func snapshot(capturedAt: Date, sourcePath: String) -> UsageLimitSnapshot? {
            let windows = [
                primary?.window(id: "primary"),
                secondary?.window(id: "secondary"),
            ].compactMap { $0 }
            guard !windows.isEmpty else { return nil }
            return UsageLimitSnapshot(
                provider: .codex,
                windows: windows,
                capturedAt: capturedAt,
                sourceLabel: "Codex rollout",
                sourcePath: sourcePath,
                planType: planType,
                limitID: limitID
            )
        }
    }

    struct Window: Decodable {
        let usedPercent: Double?
        let resetAt: Date?
        let windowMinutes: Int?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "resets_at"
            case windowMinutes = "window_minutes"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercent = UsageLimitDecoding.decodeDouble(container, forKey: .usedPercent)
            resetAt = UsageLimitDecoding.decodeDate(container, forKey: .resetAt)
            windowMinutes = UsageLimitDecoding.decodeInt(container, forKey: .windowMinutes)
        }

        func window(id: String) -> UsageLimitWindow? {
            guard let usedPercent else { return nil }
            return UsageLimitWindow(
                id: id,
                label: Self.label(forMinutes: windowMinutes),
                usedPercent: usedPercent,
                resetAt: resetAt,
                windowMinutes: windowMinutes
            )
        }

        private static func label(forMinutes minutes: Int?) -> String {
            switch minutes {
            case 300:
                "5h"
            case 10_080:
                "7d"
            case let minutes?:
                compactDuration(minutes: minutes)
            case nil:
                "Limit"
            }
        }

        private static func compactDuration(minutes: Int) -> String {
            let days = minutes / 1_440
            let hours = (minutes % 1_440) / 60
            let remainder = minutes % 60
            if days > 0, hours == 0, remainder == 0 { return "\(days)d" }
            if days > 0, hours > 0 { return "\(days)d \(hours)h" }
            if hours > 0, remainder == 0 { return "\(hours)h" }
            if hours > 0 { return "\(hours)h \(remainder)m" }
            return "\(minutes)m"
        }
    }
}
