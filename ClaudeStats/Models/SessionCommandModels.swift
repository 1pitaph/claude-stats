import Foundation

struct SessionCommandEvent: Sendable, Hashable {
    let command: String
    let timestamp: Date?

    init(command: String, timestamp: Date?) {
        self.command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timestamp = timestamp
    }
}

struct SessionCommandCount: Sendable, Hashable, Identifiable {
    var id: String { command }

    let command: String
    let count: Int
    let lastUsedAt: Date?
}

struct SessionCommandSummary: Sendable, Hashable, Identifiable {
    var id: String { sessionID }

    let sessionID: String
    let sessionTitle: String
    let projectName: String
    let provider: ProviderKind
    let lastActivity: Date
    let commands: [SessionCommandCount]
}

enum SessionCommandSummaryBuilder {
    static func recentSessions(_ sessions: [Session], limit: Int) -> [Session] {
        Array(sessions.sorted { lhs, rhs in
            let lhsActivity = lhs.stats?.lastActivity ?? lhs.lastModified
            let rhsActivity = rhs.stats?.lastActivity ?? rhs.lastModified
            if lhsActivity != rhsActivity {
                return lhsActivity > rhsActivity
            }
            return lhs.id < rhs.id
        }.prefix(max(0, limit)))
    }

    static func summary(
        for session: Session,
        events: [SessionCommandEvent],
        commandLimit: Int
    ) -> SessionCommandSummary {
        SessionCommandSummary(
            sessionID: session.id,
            sessionTitle: session.stats?.title ?? session.projectDisplayName,
            projectName: session.projectDisplayName,
            provider: session.provider,
            lastActivity: session.stats?.lastActivity ?? session.lastModified,
            commands: topCommands(from: events, limit: commandLimit)
        )
    }

    static func topCommands(from events: [SessionCommandEvent], limit: Int) -> [SessionCommandCount] {
        struct MutableCommandStats {
            var count = 0
            var lastUsedAt: Date?
        }

        var byCommand: [String: MutableCommandStats] = [:]
        for event in events {
            let command = event.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { continue }
            var stats = byCommand[command] ?? MutableCommandStats()
            stats.count += 1
            if let timestamp = event.timestamp,
               stats.lastUsedAt == nil || timestamp > stats.lastUsedAt! {
                stats.lastUsedAt = timestamp
            }
            byCommand[command] = stats
        }

        return Array(byCommand.map { command, stats in
            SessionCommandCount(command: command, count: stats.count, lastUsedAt: stats.lastUsedAt)
        }.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            let lhsDate = lhs.lastUsedAt ?? .distantPast
            let rhsDate = rhs.lastUsedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.command.localizedCaseInsensitiveCompare(rhs.command) == .orderedAscending
        }.prefix(max(0, limit)))
    }
}
