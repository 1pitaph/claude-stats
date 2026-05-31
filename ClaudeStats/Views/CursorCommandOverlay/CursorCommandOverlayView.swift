import AppKit
import SwiftUI

struct CursorCommandOverlayView: View {
    let state: CursorCommandOverlayState
    let onToggleExpanded: () -> Void
    let onCollapse: () -> Void
    let onCopyCommand: (String) -> Void

    var body: some View {
        Group {
            if state.isExpanded {
                expandedPanel
            } else {
                collapsedPill
            }
        }
        .stxFont(12)
    }

    private var collapsedPill: some View {
        Button(action: onToggleExpanded) {
            Image(systemName: AppIcon.Runtime.terminalFilled)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: CursorCommandOverlayGeometry.collapsedSize.width, height: CursorCommandOverlayGeometry.collapsedSize.height)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .help("Recent session commands")
        .accessibilityLabel("Recent session commands")
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: AppIcon.Runtime.terminalFilled)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.stxAccent)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Recent Session Commands")
                        .font(.sora(13, weight: .semibold))
                    Text("Last 5 active sessions")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }

                Spacer(minLength: 8)

                Button(action: onCollapse) {
                    Image(systemName: AppIcon.Action.close)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Collapse")
                .accessibilityLabel("Collapse")
            }

            if state.isLoading {
                loadingView
            } else if let error = state.lastError {
                emptyMessage(error, symbol: AppIcon.Status.warning)
            } else if state.summaries.isEmpty {
                emptyMessage("No recent sessions found.", symbol: AppIcon.Status.clock)
            } else {
                AppScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(state.summaries) { summary in
                            sessionSection(summary)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(maxHeight: 374)
            }
        }
        .padding(12)
        .frame(width: CursorCommandOverlayGeometry.expandedWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Reading executed commands...")
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
            Spacer(minLength: 0)
        }
        .frame(height: 92)
    }

    private func emptyMessage(_ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.stxMuted)
                .frame(width: 20, height: 20)
            Text(text)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 92, alignment: .top)
    }

    private func sessionSection(_ summary: SessionCommandSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: summary.provider.iconSystemName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(summary.provider.accentColor)
                    .frame(width: 16)

                Text(summary.sessionTitle)
                    .font(.sora(11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(relativeDate(summary.lastActivity))
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Text("\(summary.projectName) - \(summary.provider.shortName)")
                .font(.sora(9))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)

            if summary.commands.isEmpty {
                Text("No executed terminal commands.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(summary.commands) { command in
                        commandRow(command)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.5)
                .offset(y: 6)
        }
    }

    private func commandRow(_ command: SessionCommandCount) -> some View {
        HStack(spacing: 8) {
            Text(command.command)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("x\(command.count)")
                .font(.sora(9, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 28, alignment: .trailing)

            Button {
                onCopyCommand(command.command)
            } label: {
                Image(systemName: state.copiedCommand == command.command ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Copy command")
            .accessibilityLabel("Copy command")
        }
        .padding(.vertical, 3)
        .padding(.leading, 7)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
