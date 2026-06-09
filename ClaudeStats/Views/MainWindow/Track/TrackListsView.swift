import SwiftUI

struct TrackApprovalListView: View {
    let items: [TrackApprovalItem]

    var body: some View {
        if items.isEmpty {
            TrackListEmptyState(title: "No Approvals", symbol: AppIcon.Track.approvals)
        } else {
            AppScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        TrackApprovalRow(item: item)
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct TrackApprovalRow: View {
    let item: TrackApprovalItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TrackListIcon(symbol: AppIcon.Track.approvals, color: item.status.trackColor)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.sora(13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    Text(Format.shortTime(item.requestedAt))
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }

                Text(item.detail)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    TrackStatusBadge(status: item.status)
                    TrackSourceBadge(source: item.source, confidence: item.confidence)
                    if let toolName = item.toolName {
                        TrackSmallToken(toolName)
                    }
                    if let resolvedAt = item.resolvedAt {
                        TrackSmallToken("Resolved \(Format.shortTime(resolvedAt))")
                    }
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.55)))
    }
}

struct TrackToolListView: View {
    let items: [TrackToolItem]

    var body: some View {
        if items.isEmpty {
            TrackListEmptyState(title: "No Tool Activity", symbol: AppIcon.Track.tools)
        } else {
            AppScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        TrackToolRow(item: item)
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct TrackToolRow: View {
    let item: TrackToolItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TrackListIcon(symbol: item.status.symbol, color: item.status.trackColor)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.sora(13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    Text(Format.shortTime(item.startedAt))
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }

                Text(item.detail)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    TrackStatusBadge(status: item.status)
                    TrackSourceBadge(source: item.source, confidence: item.confidence)
                    if let toolName = item.toolName {
                        TrackSmallToken(toolName)
                    }
                    if let endedAt = item.endedAt {
                        TrackSmallToken("Ended \(Format.shortTime(endedAt))")
                    }
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.55)))
    }
}

struct TrackEventListView: View {
    let events: [TrackEvent]

    var body: some View {
        if events.isEmpty {
            TrackListEmptyState(title: "No Events", symbol: AppIcon.Track.events)
        } else {
            AppScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(events) { event in
                        TrackEventRow(event: event)
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct TrackEventRow: View {
    let event: TrackEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TrackListIcon(symbol: event.kind.symbol, color: event.kind.statusColor)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.kind.title)
                        .font(.sora(12, weight: .semibold))
                    Text(event.source.title)
                        .font(.sora(10, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                    Spacer(minLength: 8)
                    Text(Format.shortTime(event.timestamp))
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }

                Text(event.summary)
                    .font(.sora(11))
                    .lineLimit(2)

                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    TrackSourceBadge(source: event.source, confidence: event.confidence)
                    if let toolName = event.toolName {
                        TrackSmallToken(toolName)
                    }
                    if let agentType = event.agentType {
                        TrackSmallToken(agentType)
                    }
                    TrackSmallToken(event.sessionID)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.45)))
    }
}

private struct TrackListIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct TrackSmallToken: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.sora(9, weight: .medium))
            .foregroundStyle(Color.stxMuted)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct TrackListEmptyState: View {
    let title: String
    let symbol: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension TrackEventKind {
    var symbol: String {
        switch self {
        case .approvalRequested, .approvalAllowed, .approvalDenied, .questionAsked, .questionReplied:
            AppIcon.Track.approvals
        case .toolRequested, .toolStarted, .toolSucceeded, .toolFailed:
            AppIcon.Track.tools
        case .subagentStarted, .subagentStopped:
            "person.crop.circle.badge.gearshape"
        case .sessionStarted, .sessionStopped:
            AppIcon.Resource.transcriptSearch
        case .turnStarted, .transcriptActivity, .statusChanged:
            AppIcon.Track.flow
        case .error:
            "exclamationmark.triangle"
        }
    }

    var statusColor: Color {
        switch self {
        case .approvalRequested, .questionAsked:
            TrackStatus.waitingApproval.trackColor
        case .toolRequested, .toolStarted:
            TrackStatus.usingTool.trackColor
        case .toolFailed, .error:
            TrackStatus.failed.trackColor
        case .approvalDenied:
            TrackStatus.denied.trackColor
        case .approvalAllowed, .questionReplied:
            TrackStatus.approved.trackColor
        case .sessionStopped, .subagentStopped, .toolSucceeded:
            TrackStatus.completed.trackColor
        case .sessionStarted, .turnStarted, .subagentStarted:
            TrackStatus.running.trackColor
        case .statusChanged:
            TrackStatus.maybeRunning.trackColor
        case .transcriptActivity:
            TrackStatus.recentlyActive.trackColor
        }
    }
}
