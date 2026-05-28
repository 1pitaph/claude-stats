import AppKit
import SwiftUI

struct LinuxDoUserProfilePopover: View {
    let fallbackUsername: String
    let fallbackDisplayName: String
    let fallbackAvatarURL: URL?
    let state: LinuxDoUserProfileState
    let postsInTopic: Int
    let onRetry: () -> Void

    var body: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let error = state.error {
                    LinuxDoUserProfileErrorView(message: error, onRetry: onRetry)
                }

                if state.isLoading && state.profile == nil {
                    loadingView
                }

                if let profile = state.profile {
                    profileContent(profile)
                }
            }
            .padding(16)
        }
        .frame(width: 380)
        .frame(maxHeight: 480)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: state.profile?.avatarURL ?? fallbackAvatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.stxMuted)
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.stxAccent.opacity(0.24), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(state.profile?.displayName ?? fallbackDisplayName)
                        .font(.sora(18, weight: .semibold))
                        .lineLimit(1)
                    if state.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text("@\(state.profile?.username ?? fallbackUsername)")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)

                if let title = state.profile?.title, !title.isEmpty {
                    Text(title)
                        .font(.sora(11, weight: .medium))
                        .foregroundStyle(Color.stxAccent)
                        .lineLimit(1)
                }

                roleChips
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var roleChips: some View {
        if let profile = state.profile,
           profile.isAdmin || profile.isModerator || profile.trustLevel != nil {
            HStack(spacing: 6) {
                if profile.isAdmin {
                    LinuxDoUserProfileChip(title: "Admin", systemImage: "crown.fill", isProminent: true)
                }
                if profile.isModerator {
                    LinuxDoUserProfileChip(title: "Moderator", systemImage: "shield.fill", isProminent: true)
                }
                if let trustLevel = profile.trustLevel {
                    LinuxDoUserProfileChip(title: "\(String(localized: "Trust Level")) \(trustLevel)", systemImage: "checkmark.seal.fill")
                }
            }
        }
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading profile")
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
        }
        .padding(.vertical, 8)
    }

    private func profileContent(_ profile: LinuxDoUserProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !profile.plainBioExcerpt.isEmpty {
                Text(profile.plainBioExcerpt)
                    .font(.sora(12))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            metadataRows(profile)

            LinuxDoUserProfileStatsGrid(items: statItems(for: profile))

            if !profile.groups.isEmpty {
                chipSection(title: "Groups", systemImage: "person.3.fill") {
                    ForEach(profile.groups.prefix(12)) { group in
                        LinuxDoUserProfileChip(title: group.fullName ?? group.name, systemImage: "person.2")
                    }
                }
            }

            if !profile.badges.isEmpty {
                chipSection(title: "Badges", systemImage: "seal.fill") {
                    ForEach(profile.badges.prefix(16)) { badge in
                        LinuxDoUserBadgeChip(badge: badge)
                    }
                }
            }

            if let profileURL = profile.profileURL {
                Link(destination: profileURL) {
                    Label("Open Profile", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
            }
        }
    }

    private func metadataRows(_ profile: LinuxDoUserProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let location = profile.location, !location.isEmpty {
                LinuxDoUserProfileInfoRow(systemImage: "location.fill", title: "Location", value: location)
            }
            if let website = profile.website, let url = websiteURL(from: website) {
                Link(destination: url) {
                    Label(websiteDisplayText(website), systemImage: "link")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxAccent)
                        .lineLimit(1)
                }
            }
            if let createdAt = profile.createdAt {
                LinuxDoUserProfileInfoRow(systemImage: "calendar", title: "Joined", value: Format.shortDate(createdAt))
            }
            if let lastSeenAt = profile.lastSeenAt {
                LinuxDoUserProfileInfoRow(systemImage: "clock", title: "Last Seen", value: Format.relativeDate(lastSeenAt))
            }
            if let primaryGroup = profile.primaryGroupName, !primaryGroup.isEmpty {
                LinuxDoUserProfileInfoRow(systemImage: "person.2.fill", title: "Primary Group", value: primaryGroup)
            }
            if let flairName = profile.flairName, !flairName.isEmpty {
                LinuxDoUserProfileInfoRow(systemImage: "sparkles", title: "Flair", value: flairName)
            }
        }
    }

    private func statItems(for profile: LinuxDoUserProfile) -> [LinuxDoUserProfileStatItem] {
        var items = [
            LinuxDoUserProfileStatItem(title: "Posts in Topic", value: formatCount(postsInTopic), systemImage: "number"),
        ]
        appendCount(profile.stats.postCount, title: "Posts", systemImage: "text.bubble", to: &items)
        appendCount(profile.stats.topicCount, title: "Topics", systemImage: "rectangle.stack", to: &items)
        appendCount(profile.stats.likesReceived, title: "Likes", systemImage: "heart", to: &items)
        appendCount(profile.stats.solutionsCount, title: "Solutions", systemImage: "checkmark.square", to: &items)
        appendCount(profile.stats.profileViewCount, title: "Profile Views", systemImage: "eye", to: &items)
        if let readTime = profile.stats.readTimeSeconds, readTime > 0 {
            items.append(LinuxDoUserProfileStatItem(title: "Read Time", value: Format.duration(TimeInterval(readTime)), systemImage: "clock"))
        }
        return items
    }

    private func appendCount(
        _ value: Int?,
        title: String,
        systemImage: String,
        to items: inout [LinuxDoUserProfileStatItem]
    ) {
        guard let value else { return }
        items.append(LinuxDoUserProfileStatItem(title: title, value: formatCount(value), systemImage: systemImage))
    }

    private func chipSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(LocalizedStringKey(title))
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.sora(11, weight: .semibold))
            .foregroundStyle(Color.stxMuted)
            FlowLikeChipWrap {
                content()
            }
        }
    }

    private func formatCount(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func websiteURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }

    private func websiteDisplayText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
    }
}

private struct LinuxDoUserProfileErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.sora(11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct LinuxDoUserProfileInfoRow: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 14)
                .foregroundStyle(Color.stxMuted)
            Text(LocalizedStringKey(title))
                .font(.sora(10, weight: .medium))
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(11))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

private struct LinuxDoUserProfileStatItem: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let systemImage: String
}

private struct LinuxDoUserProfileStatsGrid: View {
    let items: [LinuxDoUserProfileStatItem]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 106), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(LocalizedStringKey(item.title))
                    } icon: {
                        Image(systemName: item.systemImage)
                    }
                    .font(.sora(9, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    Text(item.value)
                        .font(.sora(14, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}

private struct LinuxDoUserProfileChip: View {
    let title: String
    var systemImage: String? = nil
    var isProminent = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(LocalizedStringKey(title))
                .font(.sora(10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isProminent ? Color.stxAccent : Color.primary.opacity(0.78))
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background((isProminent ? Color.stxAccent.opacity(0.12) : Color.primary.opacity(0.055)), in: Capsule())
    }
}

private struct LinuxDoUserBadgeChip: View {
    let badge: LinuxDoUserBadge

    var body: some View {
        HStack(spacing: 5) {
            if let imageURL = badge.imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "seal")
                }
                .frame(width: 14, height: 14)
            } else {
                Image(systemName: "seal")
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(badge.name)
                .font(.sora(10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Color.primary.opacity(0.78))
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Color.primary.opacity(0.055), in: Capsule())
    }
}

private struct FlowLikeChipWrap<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                content
            }
            VStack(alignment: .leading, spacing: 6) {
                content
            }
        }
    }
}
