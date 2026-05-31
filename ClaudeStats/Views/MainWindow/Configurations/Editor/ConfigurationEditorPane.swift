import AppKit
import SwiftUI

struct ConfigurationEditorPane: View {
    let profile: ConfigProfile?
    let status: ConfigProfileStatus
    let latestBackupURL: URL?
    let isWorking: Bool
    let editor: ConfigurationEditorViewModel
    let saveToProfile: () -> Void
    let saveToDisk: () -> Void
    let revert: () -> Void
    let applyProfile: () -> Void
    let duplicateProfile: () -> Void
    let deleteProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if editor.isOpen {
                ConfigurationEditorToolbar(
                    title: editor.title,
                    path: editor.path,
                    fileKind: editor.fileKind,
                    isDirty: editor.isDirty,
                    hasError: editor.diagnostics.contains { $0.severity == .error },
                    isWorking: isWorking || editor.isWorking,
                    saveToProfile: saveToProfile,
                    saveToDisk: saveToDisk,
                    revert: revert,
                    applyProfile: applyProfile,
                    openExternal: openExternal
                )
                StxRule()
                diagnostics
                editorSurface
                StxRule()
                ConfigurationEditorStatusBar(editor: editor, latestBackupURL: latestBackupURL)
            } else {
                ConfigurationProfileOverviewPane(
                    profile: profile,
                    status: status,
                    latestBackupURL: latestBackupURL,
                    isWorking: isWorking,
                    applyProfile: applyProfile,
                    duplicateProfile: duplicateProfile,
                    deleteProfile: deleteProfile,
                    revealBackup: revealBackup
                )
            }
        }
        .frame(minWidth: 360, maxWidth: .infinity, minHeight: 440, alignment: .topLeading)
        .appSurface(.compactCard(radius: 8, cornerStyle: .circular, maxWidth: nil))
    }

    @ViewBuilder
    private var diagnostics: some View {
        if editor.hasDiagnostics {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(editor.diagnostics) { diagnostic in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: diagnostic.severity == .error ? "exclamationmark.triangle.fill" : diagnostic.severity == .warning ? "exclamationmark.triangle" : "info.circle")
                            .foregroundStyle(diagnostic.severity == .error ? Color(red: 0.85, green: 0.22, blue: 0.18) : diagnostic.severity == .warning ? Color(red: 0.92, green: 0.58, blue: 0.16) : Color.stxMuted)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(diagnostic.message)
                                .font(.sora(10, weight: .medium))
                                .lineLimit(2)
                            if let location = diagnostic.locationDisplay {
                                Text(location)
                                    .font(.sora(9))
                                    .foregroundStyle(Color.stxMuted)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            StxRule()
        }
    }

    private var editorSurface: some View {
        ConfigurationTextEditor(
            text: Binding(
                get: { editor.draftContent },
                set: { editor.updateDraft($0) }
            ),
            fileKind: editor.fileKind,
            isEditable: !(isWorking || editor.isWorking),
            onCursorChange: { line, column in
                editor.updateCursor(line: line, column: column)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.035))
    }

    private func openExternal() {
        guard !editor.path.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: editor.path))
    }

    private func revealBackup() {
        guard let latestBackupURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([latestBackupURL])
    }
}

private struct ConfigurationEditorToolbar: View {
    let title: String
    let path: String
    let fileKind: ProviderConfigFileKind
    let isDirty: Bool
    let hasError: Bool
    let isWorking: Bool
    let saveToProfile: () -> Void
    let saveToDisk: () -> Void
    let revert: () -> Void
    let applyProfile: () -> Void
    let openExternal: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.sora(13, weight: .semibold))
                        .lineLimit(1)
                    EditorBadge(text: fileKind.displayName, color: Color.stxMuted)
                    if isDirty {
                        EditorBadge(text: "Unsaved", color: Color.stxAccent)
                    }
                    if hasError {
                        EditorBadge(text: "Syntax issue", color: Color(red: 0.85, green: 0.22, blue: 0.18))
                    }
                }
                Text(path)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            ViewThatFits(in: .horizontal) {
                actionButtons(showLabels: true)
                actionButtons(showLabels: false)
            }
        }
        .padding(14)
    }

    private func actionButtons(showLabels: Bool) -> some View {
        HStack(spacing: 8) {
            toolbarButton("Save to Profile", systemImage: AppIcon.Action.downloadTray, showLabels: showLabels, disabled: isWorking || !isDirty, action: saveToProfile)
            toolbarButton("Save to Disk", systemImage: AppIcon.Resource.externalDrive, showLabels: showLabels, disabled: isWorking, action: saveToDisk)
            toolbarButton("Revert", systemImage: AppIcon.Action.reset, showLabels: showLabels, disabled: isWorking || !isDirty, action: revert)
            toolbarButton("Apply Profile", systemImage: AppIcon.Settings.features, showLabels: showLabels, disabled: isWorking || isDirty, action: applyProfile)
            toolbarButton("Open External", systemImage: AppIcon.Action.openExternal, showLabels: showLabels, disabled: isWorking || path.isEmpty, action: openExternal)
        }
    }

    private func toolbarButton(
        _ title: String,
        systemImage: String,
        showLabels: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if showLabels {
                Label(title, systemImage: systemImage)
            } else {
                Image(systemName: systemImage)
            }
        }
        .help(title)
        .disabled(disabled)
    }

    private var iconName: String {
        switch fileKind {
        case .json:
            AppIcon.Code.braces
        case .markdown:
            AppIcon.Resource.documentText
        case .toml:
            AppIcon.Workspace.configs
        case .text:
            AppIcon.Resource.documentPlainText
        }
    }
}

private struct ConfigurationEditorStatusBar: View {
    let editor: ConfigurationEditorViewModel
    let latestBackupURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            Label("Line \(editor.cursorLine), column \(editor.cursorColumn)", systemImage: AppIcon.Text.cursor)
            Text("\(editor.draftCharacterCount) chars")
            if let diagnostic = editor.primaryDiagnostic {
                Text(diagnostic.severity == .error ? "Error" : diagnostic.severity == .warning ? "Warning" : "Info")
                    .foregroundStyle(diagnostic.severity == .error ? Color(red: 0.85, green: 0.22, blue: 0.18) : diagnostic.severity == .warning ? Color(red: 0.92, green: 0.58, blue: 0.16) : Color.stxMuted)
            } else {
                Text("Syntax OK")
                    .foregroundStyle(Color.stxAccent)
            }
            Spacer(minLength: 12)
            if let latestBackupURL {
                Text(latestBackupURL.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(latestBackupURL.path)
            }
        }
        .font(.sora(10))
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct ConfigurationProfileOverviewPane: View {
    let profile: ConfigProfile?
    let status: ConfigProfileStatus
    let latestBackupURL: URL?
    let isWorking: Bool
    let applyProfile: () -> Void
    let duplicateProfile: () -> Void
    let deleteProfile: () -> Void
    let revealBackup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let profile {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(profile.provider.monochromeAssetName)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(Color.stxAccent)
                        Text(profile.name)
                            .font(.sora(18, weight: .semibold))
                            .lineLimit(1)
                    }
                    Text(profile.scope.detail)
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                HStack(spacing: 8) {
                    EditorBadge(text: "\(profile.files.count) files", color: Color.stxMuted)
                    EditorBadge(text: status.displayName, color: status.isClean ? Color.stxAccent : Color(red: 0.92, green: 0.58, blue: 0.16))
                    if profile.lastAppliedAt != nil {
                        EditorBadge(text: "Applied", color: Color.stxAccent)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Created", value: profile.createdAt.formatted(date: .abbreviated, time: .shortened))
                    InfoRow(label: "Updated", value: profile.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    if let lastAppliedAt = profile.lastAppliedAt {
                        InfoRow(label: "Last Applied", value: lastAppliedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let latestBackupURL {
                        InfoRow(label: "Latest Backup", value: latestBackupURL.path)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    profileActions(axis: .horizontal)
                    profileActions(axis: .vertical)
                }
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("No profile selected")
                        .font(.sora(14, weight: .semibold))
                    Text("Capture the current configuration to start editing and switching profiles.")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func profileActions(axis: Axis) -> some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        layout {
            Button {
                applyProfile()
            } label: {
                Label("Apply Profile", systemImage: AppIcon.Settings.features)
            }
            .disabled(isWorking)
            Button {
                duplicateProfile()
            } label: {
                Label("Duplicate", systemImage: AppIcon.Action.duplicateNew)
            }
            .disabled(isWorking)
            Button(role: .destructive) {
                deleteProfile()
            } label: {
                Label("Delete", systemImage: AppIcon.Action.delete)
            }
            .disabled(isWorking)
            if latestBackupURL != nil {
                Button {
                    revealBackup()
                } label: {
                    Label("Reveal Backup", systemImage: AppIcon.Action.undoCircle)
                }
            }
        }
    }
}

private struct EditorBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.sora(9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.sora(10, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.sora(10))
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}
