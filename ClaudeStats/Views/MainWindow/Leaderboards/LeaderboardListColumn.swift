import SwiftUI

struct LeaderboardListColumn: View {
    let metric: LeaderboardMetric
    let scores: [LeaderboardScore]
    let topScore: Int64
    let selectedScoreID: String?
    let currentUserHash: String?
    let usesFixedScoreListHeight: Bool
    let isLoadingScores: Bool
    let scoreError: String?
    let scoreEmptyMessage: String?
    let lastLoadedPeriodKey: String?
    let leaderboardsEnabled: Bool
    let onSelectScore: (LeaderboardScore) -> Void
    let onOpenSettings: () -> Void

    private var topThree: [(rank: Int, score: LeaderboardScore?)] {
        [
            (1, scores.indices.contains(0) ? scores[0] : nil),
            (2, scores.indices.contains(1) ? scores[1] : nil),
            (3, scores.indices.contains(2) ? scores[2] : nil),
        ]
    }

    private var remainingScores: [LeaderboardScore] {
        Array(scores.dropFirst(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if leaderboardsEnabled {
                podiumSection
                scoresPanel
            } else {
                disabledPanel
            }
        }
        .frame(maxHeight: usesFixedScoreListHeight ? .infinity : nil, alignment: .top)
    }

    @ViewBuilder
    private var podiumSection: some View {
        if let scoreError {
            LeaderboardNotice(message: scoreError)
        } else if scores.isEmpty && !isLoadingScores {
            LeaderboardNotice(message: scoreEmptyMessage ?? "No scores for this UTC period yet.")
        } else if !scores.isEmpty {
            VStack(spacing: 8) {
                ForEach(topThree, id: \.rank) { item in
                    LeaderboardPodiumCompactRow(
                        score: item.score,
                        fallbackRank: item.rank,
                        topScore: topScore,
                        isSelected: item.score?.id == selectedScoreID,
                        isCurrentUser: isCurrentUser(item.score),
                        onSelect: onSelectScore
                    )
                }
            }
        }
    }

    private var scoresPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("TOP 100")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                if let lastLoadedPeriodKey {
                    Text(lastLoadedPeriodKey)
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }
                Spacer(minLength: 8)
                Text(metric.displayName)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            .padding(.bottom, 10)

            if usesFixedScoreListHeight {
                AppScrollView {
                    scoreRows
                        .padding(.trailing, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                scoreRows
            }
        }
        .frame(maxWidth: .infinity, maxHeight: usesFixedScoreListHeight ? .infinity : nil, alignment: .topLeading)
        .mainWindowPanel(padding: 14)
        .frame(maxHeight: usesFixedScoreListHeight ? .infinity : nil, alignment: .top)
    }

    @ViewBuilder
    private var scoreRows: some View {
        if remainingScores.isEmpty {
            Text(scores.count <= 3 ? "The podium has everyone for this window." : "No additional ranks.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(remainingScores) { score in
                    LeaderboardScoreRow(
                        score: score,
                        formattedScore: LeaderboardFormat.score(score.score, metric: score.metric),
                        topScore: topScore,
                        isSelected: score.id == selectedScoreID,
                        isCurrentUser: isCurrentUser(score),
                        onSelect: onSelectScore
                    )
                    if score.id != remainingScores.last?.id {
                        StxRule()
                    }
                }
            }
        }
    }

    private var disabledPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: AppIcon.Workspace.leaderboards)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.stxAccent)
            Text("Leaderboards are off")
                .font(.sora(16, weight: .semibold))
            Text("Enable them in Features, choose a public nickname, then sync aggregate scores and a generated Beam avatar to CloudKit.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onOpenSettings) {
                BracketBox(spacing: 5) {
                    Label("OPEN FEATURES", systemImage: AppIcon.Settings.features)
                        .labelStyle(.titleAndIcon)
                        .font(.sora(10, weight: .medium))
                        .tracking(0.8)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxAccent)
        }
        .mainWindowPanel(padding: 16)
    }

    private func isCurrentUser(_ score: LeaderboardScore?) -> Bool {
        guard let score else { return false }
        return isCurrentUser(score)
    }

    private func isCurrentUser(_ score: LeaderboardScore) -> Bool {
        guard let currentUserHash else { return false }
        return score.userHash == currentUserHash
    }
}

private struct LeaderboardPodiumCompactRow: View {
    let score: LeaderboardScore?
    let fallbackRank: Int
    let topScore: Int64
    let isSelected: Bool
    let isCurrentUser: Bool
    let onSelect: (LeaderboardScore) -> Void

    var body: some View {
        if let score {
            Button {
                onSelect(score)
            } label: {
                rowContent(score: score)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rank \(score.rank ?? fallbackRank), \(score.nickname), \(LeaderboardFormat.score(score.score, metric: score.metric))")
        } else {
            waitingContent
        }
    }

    private func rowContent(score: LeaderboardScore) -> some View {
        HStack(spacing: 12) {
            rankBadge(score.rank ?? fallbackRank)
            LeaderboardAvatarStatusView(
                seed: LeaderboardFormat.avatarSeed(for: score),
                size: fallbackRank == 1 ? 44 : 38,
                statusID: score.recentStatusID
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(score.nickname)
                        .font(.sora(13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isCurrentUser {
                        youBadge
                    }
                }
                Text("Updated \(Format.relativeDate(score.updatedAt))")
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 5) {
                Text(LeaderboardFormat.score(score.score, metric: score.metric))
                    .font(.sora(fallbackRank == 1 ? 14 : 12, weight: .semibold).monospacedDigit())
                    .stxNumericValueTransition(value: LeaderboardFormat.score(score.score, metric: score.metric))
                    .foregroundStyle(fallbackRank == 1 ? Color.stxAccent : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                LeaderboardScoreBar(fraction: fraction(for: score), active: isCurrentUser || isSelected)
                    .frame(width: 74)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, fallbackRank == 1 ? 12 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(rowStroke, lineWidth: isSelected || isCurrentUser ? 1.5 : 1)
        )
    }

    private var waitingContent: some View {
        HStack(spacing: 12) {
            rankBadge(fallbackRank)
            Text("Waiting")
                .font(.sora(12, weight: .medium))
                .foregroundStyle(Color.stxMuted)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 10, fillOpacity: 0.65), padding: nil)
    }

    private var rowBackground: Color {
        if isSelected || isCurrentUser { return Color.stxAccent.opacity(0.08) }
        return fallbackRank == 1 ? AppSurface.panelFill : AppSurface.panelFill.opacity(0.78)
    }

    private var rowStroke: Color {
        if isSelected || isCurrentUser { return Color.stxAccent }
        return Color.stxStroke
    }

    private var youBadge: some View {
        Text("YOU")
            .font(.sora(8, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Color.stxAccent)
    }

    private func rankBadge(_ rank: Int) -> some View {
        Text("#\(rank)")
            .font(.sora(13, weight: .semibold).monospacedDigit())
            .stxNumericValueTransition(value: rank)
            .foregroundStyle(rank == 1 ? Color.stxAccent : Color.stxMuted)
            .frame(width: 36, alignment: .leading)
    }

    private func fraction(for score: LeaderboardScore) -> Double {
        guard topScore > 0 else { return 0 }
        return min(max(Double(score.score) / Double(topScore), 0), 1)
    }
}

private struct LeaderboardScoreRow: View {
    let score: LeaderboardScore
    let formattedScore: String
    let topScore: Int64
    let isSelected: Bool
    let isCurrentUser: Bool
    let onSelect: (LeaderboardScore) -> Void

    private var fraction: Double {
        guard topScore > 0 else { return 0 }
        return min(max(Double(score.score) / Double(topScore), 0), 1)
    }

    var body: some View {
        Button {
            onSelect(score)
        } label: {
            HStack(spacing: 10) {
                Text("#\(score.rank ?? 0)")
                    .font(.sora(11, weight: .semibold).monospacedDigit())
                    .stxNumericValueTransition(value: score.rank ?? 0)
                    .foregroundStyle(isCurrentUser || isSelected ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 38, alignment: .leading)
                LeaderboardAvatarStatusView(
                    seed: LeaderboardFormat.avatarSeed(for: score),
                    size: 28,
                    statusID: score.recentStatusID
                )
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(score.nickname)
                            .font(.sora(12, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if isCurrentUser {
                            Text("YOU")
                                .font(.sora(8, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(Color.stxAccent)
                        }
                    }
                    Text("Updated \(Format.relativeDate(score.updatedAt))")
                        .font(.sora(9))
                        .foregroundStyle(Color.stxMuted)
                }
                .frame(minWidth: 88, maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(formattedScore)
                        .font(.sora(12, weight: .semibold).monospacedDigit())
                        .stxNumericValueTransition(value: formattedScore)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    LeaderboardScoreBar(fraction: fraction, active: isCurrentUser || isSelected)
                        .frame(width: 70)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .background {
                if isCurrentUser || isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.stxAccent.opacity(0.08))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rank \(score.rank ?? 0), \(score.nickname), \(formattedScore)")
    }
}

struct LeaderboardScoreBar: View {
    let fraction: Double
    let active: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(active ? Color.stxAccent : Color.primary.opacity(0.38))
                    .frame(width: max(4, proxy.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}

private struct LeaderboardNotice: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.sora(12))
            .foregroundStyle(Color.stxMuted)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
            .appSurface(.compactCard(radius: 10))
    }
}
