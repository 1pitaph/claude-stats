import AppKit
import SwiftUI

struct AIConfigDocumentInspector: View {
    let document: AIConfigDocument?
    var relatedSkills: [ConfigRelatedSkill] = []
    var createMissingDocument: (AIConfigDocument) -> Void = { _ in }
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let document {
                previewToolbar(document)
                StxRule()
                if !document.diagnostics.isEmpty {
                    diagnostics(document.diagnostics)
                    StxRule()
                }
                if document.kind == .pluginConfig, !relatedSkills.isEmpty {
                    relatedSkillsSection
                    StxRule()
                }
                previewBody(document)
                StxRule()
                previewStatus(document)
            } else {
                AIConfigsEmptyState(
                    title: "Select a file",
                    message: "Choose a config file to inspect its read-only preview and diagnostics."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appSurface(.plainFill)
    }

    private func previewToolbar(_ document: AIConfigDocument) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: document.kind.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(document.title)
                        .font(.sora(13, weight: .semibold))
                        .lineLimit(1)
                    AIConfigsBadge(text: document.fileKind.displayName, color: Color.stxMuted)
                    AIConfigsBadge(text: document.provider.shortName, color: document.provider.accentColor)
                    if !document.exists {
                        AIConfigsBadge(text: "Missing", color: Color.stxMuted)
                    }
                }
                Text(document.displayPath)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            ViewThatFits(in: .horizontal) {
                actionButtons(document, showLabels: true)
                actionButtons(document, showLabels: false)
            }
        }
        .padding(14)
    }

    private func actionButtons(_ document: AIConfigDocument, showLabels: Bool) -> some View {
        HStack(spacing: 8) {
            toolbarButton("Open", systemImage: "arrow.up.right.square", showLabels: showLabels, disabled: !document.exists) {
                NSWorkspace.shared.open(URL(fileURLWithPath: document.path))
            }
            toolbarButton("Reveal", systemImage: "finder", showLabels: showLabels, disabled: !document.exists) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: document.path)])
            }
            toolbarButton("Reveal Parent", systemImage: "folder", showLabels: showLabels, disabled: document.exists) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: document.path).deletingLastPathComponent()])
            }
            toolbarButton("Copy Template", systemImage: "doc.on.doc", showLabels: showLabels, disabled: document.templateContent == nil) {
                if let template = document.templateContent {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(template, forType: .string)
                }
            }
            toolbarButton("Create File", systemImage: "plus", showLabels: showLabels, disabled: !document.canCreateFromTemplate) {
                createMissingDocument(document)
            }
            toolbarButton("Refresh", systemImage: "arrow.clockwise", showLabels: showLabels, disabled: false, action: refresh)
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
        .controlSize(.small)
        .help(title)
        .disabled(disabled)
    }

    private func diagnostics(_ diagnostics: [AIConfigDiagnostic]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(diagnostics) { diagnostic in
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
    }

    private var relatedSkillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                Text("Related skills")
                    .font(.sora(11, weight: .semibold))
                Spacer(minLength: 8)
                Text("\(relatedSkills.count)")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }

            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(relatedSkills) { skill in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.stxAccent)
                            .frame(width: 14)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(skill.name)
                                    .font(.sora(10, weight: .semibold))
                                    .lineLimit(1)
                                AIConfigsBadge(text: skill.providerName, color: Color.stxMuted)
                                AIConfigsBadge(text: skill.scopeName, color: Color.stxMuted)
                            }
                            Text(skill.pluginName ?? skill.path)
                                .font(.sora(9))
                                .foregroundStyle(Color.stxMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func previewBody(_ document: AIConfigDocument) -> some View {
        if !document.exists {
            VStack(alignment: .leading, spacing: 12) {
                Text("This expected file is not present.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                if let template = document.templateContent {
                    Text("Template Preview")
                        .font(.sora(11, weight: .semibold))
                    ConfigurationTextEditor(
                        text: .constant(template),
                        fileKind: document.fileKind,
                        isEditable: false,
                        onCursorChange: { _, _ in }
                    )
                    .frame(minHeight: 220)
                    .background(Color.primary.opacity(0.035))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if document.isPreviewTruncated {
            Text("Preview skipped because this file is larger than \(Format.bytes(AIConfigScanner.previewByteLimit)).")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let content = document.contentPreview {
            ConfigurationTextEditor(
                text: .constant(content),
                fileKind: document.fileKind,
                isEditable: false,
                onCursorChange: { _, _ in }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.035))
        } else {
            Text("No preview available.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func previewStatus(_ document: AIConfigDocument) -> some View {
        HStack(spacing: 12) {
            if let fileSize = document.fileSize {
                Text(Format.bytes(Int(fileSize)))
            }
            if let modifiedAt = document.modifiedAt {
                Text(Format.shortDate(modifiedAt))
            }
            if document.fileKind == .markdown {
                Text("\(document.stats.headingCount) headings")
                Text("\(document.stats.uncheckedTaskCount) open tasks")
            }
            Spacer(minLength: 12)
            if document.diagnostics.isEmpty {
                Text(document.exists ? (document.fileKind == .text ? "Not validated" : "Syntax OK") : "Missing")
                    .foregroundStyle(document.exists && document.fileKind != .text ? Color.stxAccent : Color.stxMuted)
            } else {
                Text("\(document.diagnostics.count) diagnostics")
            }
        }
        .font(.sora(10))
        .foregroundStyle(Color.stxMuted)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
