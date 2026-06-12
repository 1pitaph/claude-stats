import AppKit
import SwiftUI

struct LogsSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage(GitOperationLog.retentionDefaultsKey) private var gitOperationRetentionDays = GitOperationLog.defaultRetentionDays
    @AppStorage(GitCommitMessageDiagnosticsLog.retentionDefaultsKey) private var gitCommitMessageDiagnosticsRetentionDays = GitCommitMessageDiagnosticsLog.defaultRetentionDays

    var body: some View {
        #if !CLAUDE_STATS_LITE
        @Bindable var memorySettings = env.memory.settings
        #endif

        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            VStack(alignment: .leading, spacing: 28) {
                gitOperationLogGroup(refreshDate: context.date)
                gitCommitMessageDiagnosticsGroup(refreshDate: context.date)
                #if !CLAUDE_STATS_LITE
                memoryDiagnosticsGroup(refreshDate: context.date, retention: $memorySettings.diagnosticsRetention)
                trackEventLogGroup()
                #endif
            }
        }
    }

    private func gitOperationLogGroup(refreshDate: Date) -> some View {
        let readableLogPath = GitOperationLog.currentReadableLogURL(date: refreshDate).path
        let jsonLogPath = GitOperationLog.currentLogURL(date: refreshDate).path
        let sourceReadableLogPath = GitOperationLog.sourceRootLogDirectory()
            .map { GitOperationLog.currentReadableLogURL(directory: $0, date: refreshDate).path }
        let sourceSize = GitOperationLog.sourceRootLogDirectory().map {
            GitOperationLog.currentReadableLogSize(directory: $0, date: refreshDate) +
                GitOperationLog.currentLogSize(directory: $0, date: refreshDate)
        } ?? 0
        let size = GitOperationLog.currentReadableLogSize(date: refreshDate) +
            GitOperationLog.currentLogSize(date: refreshDate) +
            sourceSize

        return SettingGroup(
            title: "Git Operation Log",
            caption: "Stores commit and push failures, including git hook output, stdout, stderr, exit codes, and the repository path."
        ) {
            VStack(spacing: 0) {
                SettingRow(title: "Current log", description: readableLogPath.memoryAbbreviatingHomeDirectory) {
                    LogsSettingsCopyButton(value: readableLogPath, label: "Copy Log Path")
                }
                SettingRowDivider()
                SettingRow(title: "JSONL", description: jsonLogPath.memoryAbbreviatingHomeDirectory) {
                    LogsSettingsCopyButton(value: jsonLogPath, label: "Copy JSONL Path")
                }
                SettingRowDivider()
                if let sourceReadableLogPath {
                    SettingRow(title: "Code root mirror", description: sourceReadableLogPath.memoryAbbreviatingHomeDirectory) {
                        LogsSettingsCopyButton(value: sourceReadableLogPath, label: "Copy Code Root Log Path")
                    }
                    SettingRowDivider()
                }
                SettingRow(title: "Size", description: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) {
                    EmptyView()
                }
                SettingRowDivider()
                SettingRow(title: "Retention", description: "Old git operation log files are pruned on write and when this setting changes.") {
                    HStack(spacing: 8) {
                        AppSelect(
                            .localized("Retention"),
                            selection: gitOperationRetention,
                            options: GitOperationLogRetention.allCases.map {
                                AppSelectOption(value: $0, title: .localized($0.title))
                            },
                            width: 150,
                            size: .small,
                            onSelectionChange: { retention in
                                GitOperationLog.setConfiguredRetentionDays(retention.rawValue)
                            }
                        )
                        Button {
                            GitOperationLog.openCurrentLog()
                        } label: {
                            Label("Open Current Log", systemImage: AppIcon.Resource.transcriptSearch)
                        }
                        .controlSize(.small)

                        Button {
                            GitOperationLog.revealLogFolder()
                        } label: {
                            Label("Reveal Log Folder", systemImage: AppIcon.Resource.folder)
                        }
                        .controlSize(.small)

                        if sourceReadableLogPath != nil {
                            Button {
                                GitOperationLog.revealSourceRootLogFolder()
                            } label: {
                                Label("Reveal Code Logs", systemImage: AppIcon.Resource.folder)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .settingCard()
        }
    }

    private func gitCommitMessageDiagnosticsGroup(refreshDate: Date) -> some View {
        let readableLogPath = GitCommitMessageDiagnosticsLog.currentReadableLogURL(date: refreshDate).path
        let jsonLogPath = GitCommitMessageDiagnosticsLog.currentLogURL(date: refreshDate).path
        let sourceReadableLogPath = GitCommitMessageDiagnosticsLog.sourceRootLogDirectory()
            .map { GitCommitMessageDiagnosticsLog.currentReadableLogURL(directory: $0, date: refreshDate).path }
        let sourceSize = GitCommitMessageDiagnosticsLog.sourceRootLogDirectory().map {
            GitCommitMessageDiagnosticsLog.currentReadableLogSize(directory: $0, date: refreshDate) +
                GitCommitMessageDiagnosticsLog.currentLogSize(directory: $0, date: refreshDate)
        } ?? 0
        let size = GitCommitMessageDiagnosticsLog.currentReadableLogSize(date: refreshDate) +
            GitCommitMessageDiagnosticsLog.currentLogSize(date: refreshDate) +
            sourceSize

        return SettingGroup(
            title: "Git Commit Message Diagnostics Log",
            caption: "Stores redacted metadata for Git commit message generation, cache lookups, parse status, timings, and token counts."
        ) {
            VStack(spacing: 0) {
                SettingRow(title: "Current log", description: readableLogPath.memoryAbbreviatingHomeDirectory) {
                    LogsSettingsCopyButton(value: readableLogPath, label: "Copy Log Path")
                }
                SettingRowDivider()
                SettingRow(title: "JSONL", description: jsonLogPath.memoryAbbreviatingHomeDirectory) {
                    LogsSettingsCopyButton(value: jsonLogPath, label: "Copy JSONL Path")
                }
                SettingRowDivider()
                if let sourceReadableLogPath {
                    SettingRow(title: "Code root mirror", description: sourceReadableLogPath.memoryAbbreviatingHomeDirectory) {
                        LogsSettingsCopyButton(value: sourceReadableLogPath, label: "Copy Code Root Log Path")
                    }
                    SettingRowDivider()
                }
                SettingRow(title: "Size", description: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) {
                    EmptyView()
                }
                SettingRowDivider()
                SettingRow(title: "Retention", description: "Old git-commit-message log files are pruned on write and when this setting changes.") {
                    HStack(spacing: 8) {
                        AppSelect(
                            .localized("Retention"),
                            selection: gitCommitMessageDiagnosticsRetention,
                            options: GitCommitMessageDiagnosticsRetention.allCases.map {
                                AppSelectOption(value: $0, title: .localized($0.title))
                            },
                            width: 150,
                            size: .small,
                            onSelectionChange: { retention in
                                GitCommitMessageDiagnosticsLog.setConfiguredRetentionDays(retention.rawValue)
                            }
                        )
                        Button {
                            GitCommitMessageDiagnosticsLog.openCurrentLog()
                        } label: {
                            Label("Open Current Log", systemImage: AppIcon.Resource.transcriptSearch)
                        }
                        .controlSize(.small)

                        Button {
                            GitCommitMessageDiagnosticsLog.revealLogFolder()
                        } label: {
                            Label("Reveal Log Folder", systemImage: AppIcon.Resource.folder)
                        }
                        .controlSize(.small)

                        if sourceReadableLogPath != nil {
                            Button {
                                GitCommitMessageDiagnosticsLog.revealSourceRootLogFolder()
                            } label: {
                                Label("Reveal Code Logs", systemImage: AppIcon.Resource.folder)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .settingCard()
        }
    }

    private var gitOperationRetention: Binding<GitOperationLogRetention> {
        Binding {
            GitOperationLogRetention(rawValue: gitOperationRetentionDays) ?? .sevenDays
        } set: { retention in
            gitOperationRetentionDays = retention.rawValue
            GitOperationLog.setConfiguredRetentionDays(retention.rawValue)
        }
    }

    private var gitCommitMessageDiagnosticsRetention: Binding<GitCommitMessageDiagnosticsRetention> {
        Binding {
            GitCommitMessageDiagnosticsRetention(rawValue: gitCommitMessageDiagnosticsRetentionDays) ?? .threeDays
        } set: { retention in
            gitCommitMessageDiagnosticsRetentionDays = retention.rawValue
            GitCommitMessageDiagnosticsLog.setConfiguredRetentionDays(retention.rawValue)
        }
    }

    #if !CLAUDE_STATS_LITE
    private func memoryDiagnosticsGroup(
        refreshDate: Date,
        retention: Binding<MemoryDiagnosticsRetention>
    ) -> some View {
        let readableLogPath = MemoryDiagnosticsLog.currentReadableLogURL(date: refreshDate).path
        let jsonLogPath = MemoryDiagnosticsLog.currentLogURL(date: refreshDate).path
        let devReadableLogPath = MemoryDiagnosticsLog.devLogDirectory()
            .map { MemoryDiagnosticsLog.currentReadableLogURL(directory: $0, date: refreshDate).path }
        let devSize = MemoryDiagnosticsLog.devLogDirectory().map {
            fileSize(MemoryDiagnosticsLog.currentReadableLogURL(directory: $0, date: refreshDate).path) +
                fileSize(MemoryDiagnosticsLog.currentLogURL(directory: $0, date: refreshDate).path)
        } ?? 0
        let size = fileSize(readableLogPath) + fileSize(jsonLogPath) + devSize

        return SettingGroup(
            title: "Memory Diagnostics Log",
            caption: "Stores Code Memory capture, indexing, and inference diagnostics."
        ) {
            VStack(spacing: 0) {
                SettingRow(title: "Current log", description: readableLogPath.memoryAbbreviatingHomeDirectory) {
                    LogsSettingsCopyButton(value: readableLogPath, label: "Copy Log Path")
                }
                SettingRowDivider()
                SettingRow(title: "JSONL", description: jsonLogPath.memoryAbbreviatingHomeDirectory) {
                    LogsSettingsCopyButton(value: jsonLogPath, label: "Copy JSONL Path")
                }
                SettingRowDivider()
                if let devReadableLogPath {
                    SettingRow(title: "Dev mirror", description: devReadableLogPath.memoryAbbreviatingHomeDirectory) {
                        LogsSettingsCopyButton(value: devReadableLogPath, label: "Copy Dev Log Path")
                    }
                    SettingRowDivider()
                }
                SettingRow(title: "Size", description: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) {
                    EmptyView()
                }
                SettingRowDivider()
                SettingRow(title: "Retention", description: "Old memory-capture log files are pruned on write and when this setting changes.") {
                    HStack(spacing: 8) {
                        AppSelect(
                            .localized("Retention"),
                            selection: retention,
                            options: MemoryDiagnosticsRetention.allCases.map {
                                AppSelectOption(value: $0, title: .localized($0.title))
                            },
                            width: 150,
                            size: .small,
                            onSelectionChange: { selected in
                                Task { await env.memory.settings.configureDiagnosticsRetention(selected) }
                            }
                        )
                        Button {
                            MemoryDiagnosticsLog.openCurrentLog()
                        } label: {
                            Label("Open Current Log", systemImage: AppIcon.Resource.transcriptSearch)
                        }
                        .controlSize(.small)

                        Button {
                            MemoryDiagnosticsLog.revealLogFolder()
                        } label: {
                            Label("Reveal Log Folder", systemImage: AppIcon.Resource.folder)
                        }
                        .controlSize(.small)
                    }
                }
            }
            .settingCard()
        }
    }

    private func trackEventLogGroup() -> some View {
        let status = env.track.hookInstallationStatus
        let urls = TrackEventLogReader.defaultEventLogURLs()
        let primaryURL = status?.eventLogURL ?? urls.first
        let primaryPath = primaryURL?.path ?? ""
        let size = primaryPath.isEmpty ? 0 : fileSize(primaryPath)

        return SettingGroup(
            title: "Track Event Log",
            caption: "Stores Codex hook events used by the Track workspace."
        ) {
            VStack(spacing: 0) {
                SettingRow(
                    title: "Primary log",
                    description: primaryPath.isEmpty ? "Track event log path is not available." : primaryPath.memoryAbbreviatingHomeDirectory
                ) {
                    LogsSettingsCopyButton(value: primaryPath, label: "Copy Log Path")
                }
                SettingRowDivider()
                SettingRow(
                    title: "Status",
                    description: status?.eventLogExists == true ? "Receiving events" : "No events yet"
                ) {
                    StatusSeverityBadge(
                        label: status?.eventLogExists == true ? "active" : "waiting",
                        indicatorTint: status?.eventLogExists == true ? Color.stxAccent : Color.stxMuted
                    )
                }
                SettingRowDivider()
                SettingRow(title: "Size", description: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) {
                    EmptyView()
                }
                SettingRowDivider()
                SettingRow(title: "Actions", description: "Open the current Track event log or reveal it in Finder.") {
                    HStack(spacing: 8) {
                        Button {
                            if let primaryURL {
                                openLogFile(primaryURL)
                            }
                        } label: {
                            Label("Open Current Log", systemImage: AppIcon.Resource.transcriptSearch)
                        }
                        .controlSize(.small)
                        .disabled(primaryURL == nil)

                        Button {
                            if let primaryURL {
                                revealLogFile(primaryURL)
                            }
                        } label: {
                            Label("Reveal Log Folder", systemImage: AppIcon.Resource.folder)
                        }
                        .controlSize(.small)
                        .disabled(primaryURL == nil)
                    }
                }

                ForEach(Array(urls.dropFirst().enumerated()), id: \.offset) { _, url in
                    SettingRowDivider()
                    SettingRow(title: "Fallback log", description: url.path.memoryAbbreviatingHomeDirectory) {
                        LogsSettingsCopyButton(value: url.path, label: "Copy Path")
                    }
                }
            }
            .settingCard()
        }
    }
    #endif

    private func fileSize(_ path: String) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.intValue ?? 0
    }

    private func openLogFile(_ url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data().write(to: url, options: [.atomic])
        }
        NSWorkspace.shared.open(url)
    }

    private func revealLogFile(_ url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct LogsSettingsCopyButton: View {
    let value: String
    let label: String

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: {
            Label(label, systemImage: AppIcon.Resource.link)
        }
        .controlSize(.small)
        .disabled(value.isEmpty)
        .help(label)
    }
}

#if DEBUG
#Preview("Logs settings") {
    AppScrollView {
        VStack(alignment: .leading, spacing: 32) {
            Text("Logs")
                .font(.sora(28, weight: .semibold))
            LogsSettingsView()
        }
        .padding(20)
    }
    .frame(width: 860, height: 640)
    .background(Color.stxBackground)
}
#endif
