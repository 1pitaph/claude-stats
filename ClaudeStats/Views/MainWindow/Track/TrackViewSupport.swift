import SwiftUI

extension TrackStatus {
    var trackColor: Color {
        switch self {
        case .running:
            Color(red: 0.20, green: 0.52, blue: 0.95)
        case .usingTool:
            Color(red: 0.12, green: 0.65, blue: 0.72)
        case .waitingApproval:
            Color(red: 0.95, green: 0.62, blue: 0.14)
        case .approved, .completed:
            Color(red: 0.18, green: 0.62, blue: 0.36)
        case .denied, .failed:
            Color(red: 0.86, green: 0.24, blue: 0.22)
        case .recentlyActive:
            Color.stxAccent
        case .maybeRunning:
            Color(red: 0.62, green: 0.52, blue: 0.92)
        case .unknown:
            Color.stxMuted
        }
    }

    var symbol: String {
        switch self {
        case .running: AppIcon.Action.play
        case .usingTool: AppIcon.Track.tools
        case .waitingApproval: AppIcon.Track.approvals
        case .approved: AppIcon.Status.success
        case .denied: AppIcon.Status.failure
        case .completed: AppIcon.Status.successFilled
        case .failed: AppIcon.Status.failureFilled
        case .recentlyActive: AppIcon.Status.history
        case .maybeRunning: AppIcon.Status.clockWarning
        case .unknown: AppIcon.Status.unknown
        }
    }
}

extension TrackNodeKind {
    var symbol: String {
        switch self {
        case .session: AppIcon.Resource.conversation
        case .turn: AppIcon.Resource.textBubble
        case .subagent: AppIcon.Workspace.track
        case .tool: AppIcon.Track.tools
        case .approval: AppIcon.Track.approvals
        case .result: AppIcon.Status.success
        }
    }
}

struct TrackStatusBadge: View {
    let status: TrackStatus
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.symbol)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            Text(status.title)
                .font(.sora(compact ? 9 : 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(status.trackColor)
        .padding(.horizontal, compact ? 6 : 8)
        .frame(height: compact ? 20 : 24)
        .background(status.trackColor.opacity(0.12), in: Capsule())
    }
}

struct TrackSourceBadge: View {
    let source: TrackEventSource
    let confidence: TrackConfidence

    var body: some View {
        Text("\(source.title) · \(confidence.titleShort)")
            .font(.sora(9, weight: .medium))
            .foregroundStyle(Color.stxMuted)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Color.primary.opacity(0.055), in: Capsule())
    }
}
