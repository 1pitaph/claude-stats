import SwiftUI

struct LeaderboardAvatarStatusView: View {
    let seed: String
    let size: CGFloat
    let statusID: String?
    var isEditable = false
    var isSaving = false
    var isDecorative = true
    var onSetStatus: (LeaderboardRecentStatus) -> Void = { _ in }
    var onClearStatus: () -> Void = {}

    @State private var isShowingPicker = false

    private var status: LeaderboardRecentStatus? {
        LeaderboardRecentStatus.normalizedID(statusID).flatMap(LeaderboardRecentStatus.init(rawValue:))
    }

    private var badgeSize: CGFloat {
        max(16, min(24, size * 0.38))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            BeamAvatarView(seed: seed, size: size, isDecorative: isDecorative)

            if isEditable {
                Button {
                    isShowingPicker.toggle()
                } label: {
                    LeaderboardStatusBadge(status: status, size: badgeSize, showsEmptyState: true)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .help(status.map { "Public status: \($0.label)" } ?? "Set public status")
                .accessibilityLabel("Set public leaderboard status")
                .accessibilityValue(status?.label ?? "No status")
                .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
                    LeaderboardRecentStatusPicker(
                        selectedStatusID: status?.rawValue,
                        isSaving: isSaving,
                        onSetStatus: { status in
                            isShowingPicker = false
                            onSetStatus(status)
                        },
                        onClearStatus: {
                            isShowingPicker = false
                            onClearStatus()
                        }
                    )
                    .frame(width: 220)
                }
            } else if status != nil {
                LeaderboardStatusBadge(status: status, size: badgeSize, showsEmptyState: false)
                    .accessibilityLabel(status.map { "Public status, \($0.label)" } ?? "No public status")
            }
        }
        .frame(width: size, height: size)
    }
}

private struct LeaderboardStatusBadge: View {
    let status: LeaderboardRecentStatus?
    let size: CGFloat
    let showsEmptyState: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(AppSurface.panelFill)
            Circle()
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)

            if let status {
                Image(systemName: status.symbolName)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(Color.stxAccent)
            } else if showsEmptyState {
                Image(systemName: "plus")
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(Color.stxAccent)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
    }
}

private struct LeaderboardRecentStatusPicker: View {
    let selectedStatusID: String?
    let isSaving: Bool
    let onSetStatus: (LeaderboardRecentStatus) -> Void
    let onClearStatus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PUBLIC STATUS")
                .font(.sora(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)

            VStack(spacing: 2) {
                ForEach(LeaderboardRecentStatus.allCases) { status in
                    Button {
                        onSetStatus(status)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: status.symbolName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.stxAccent)
                                .frame(width: 18)
                            Text(status.label)
                                .font(.sora(12, weight: .medium))
                            Spacer(minLength: 8)
                            if selectedStatusID == status.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.stxAccent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(
                        selectedStatusID == status.rawValue
                            ? Color.stxAccent.opacity(0.08)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                }
            }

            StxRule()

            Button {
                onClearStatus()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 18)
                    Text("Clear status")
                        .font(.sora(12, weight: .medium))
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSaving || selectedStatusID == nil)
            .foregroundStyle(selectedStatusID == nil ? Color.stxMuted : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .padding(12)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 18) {
        LeaderboardAvatarStatusView(seed: "ada", size: 58, statusID: LeaderboardRecentStatus.focused.rawValue)
        LeaderboardAvatarStatusView(seed: "grace", size: 58, statusID: nil, isEditable: true)
    }
    .padding(24)
    .background(Color.stxBackground)
}
#endif
