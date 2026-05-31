import AppKit
import SwiftUI

private enum LinuxDoDetailLayout {
    static let contentLeading: CGFloat = 84
    static let contentTrailing: CGFloat = 24
    static let contentMaxWidth: CGFloat = 848
    static let avatarColumnWidth: CGFloat = 48
    static let avatarSpacing: CGFloat = 14
    static let readingPositionDebounceNanoseconds: UInt64 = 400_000_000
    static var postRowLeading: CGFloat { contentLeading - avatarColumnWidth - avatarSpacing }
    static var headerLeading: CGFloat { postRowLeading }
    static var headerMaxWidth: CGFloat { contentMaxWidth + avatarColumnWidth + avatarSpacing }
    static var totalMaxWidth: CGFloat { contentLeading + contentMaxWidth + contentTrailing }
}

struct LinuxDoTopicDetailView: View {
    @Bindable var store: LinuxDoStore
    @State private var visiblePostNumber = 1
    @State private var navigatorMode: LinuxDoReadingNavigatorMode = .hidden
    @State private var lastRecordedPostNumber = 1
    @State private var pendingReadingPosition: LinuxDoPendingReadingPosition?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let topicID = store.selectedTopicID, let state = store.topicStates[topicID] {
                detail(state: state, topicID: topicID)
            } else {
                ContentUnavailableView {
                    Label("Select a Topic", systemImage: AppIcon.Resource.textBubble)
                } description: {
                    Text("Choose a LinuxDo topic to read it here.")
                }
                .font(.sora(12))
            }
        }
    }

    @ViewBuilder
    private func detail(state: LinuxDoTopicDetailState, topicID: Int) -> some View {
        if state.isLoading && state.detail == nil {
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else if let detail = state.detail {
            let totalFloors = totalFloors(for: detail)
            VStack(alignment: .leading, spacing: 0) {
                header(detail: detail, state: state, topicID: topicID, totalFloors: totalFloors)
                StxRule()
                GeometryReader { geometry in
                    let resolvedNavigatorMode = LinuxDoReadingNavigatorLayout.mode(
                        width: geometry.size.width,
                        totalFloors: totalFloors,
                        currentMode: navigatorMode
                    )
                    ZStack(alignment: .topTrailing) {
                        topicScroll(detail: detail, state: state, topicID: topicID)

                        readingNavigator(
                            mode: resolvedNavigatorMode,
                            currentFloor: visiblePostNumber,
                            totalFloors: totalFloors,
                            loadedFloors: detail.posts.map(\.postNumber),
                            continueFloor: validReadingPosition(topicID: topicID, totalFloors: totalFloors)?.postNumber,
                            isLoading: state.isJumping || state.isLoadingMore,
                            topicID: topicID
                        )
                    }
                    .onChange(of: geometry.size.width, initial: true) { _, width in
                        updateNavigatorMode(width: width, totalFloors: totalFloors)
                    }
                    .onChange(of: totalFloors, initial: true) { _, floors in
                        updateNavigatorMode(width: geometry.size.width, totalFloors: floors)
                    }
                }
            }
            .task(id: pendingReadingPosition) {
                guard pendingReadingPosition != nil else { return }
                try? await Task.sleep(nanoseconds: LinuxDoDetailLayout.readingPositionDebounceNanoseconds)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    flushPendingReadingPosition()
                }
            }
            .onChange(of: topicID, initial: true) { _, newTopicID in
                flushPendingReadingPosition()
                resetReadingState(topicID: newTopicID)
            }
            .onDisappear {
                flushPendingReadingPosition()
            }
        } else {
            ContentUnavailableView {
                Label("Topic Unavailable", systemImage: AppIcon.Status.warning)
            } description: {
                Text(state.error ?? "Linux.do did not return this topic.")
            }
            .font(.sora(12))
        }
    }

    private func topicScroll(detail: LinuxDoTopicDetail, state: LinuxDoTopicDetailState, topicID: Int) -> some View {
        ScrollViewReader { proxy in
            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(detailAlertMessages(for: state), id: \.self) { message in
                        LinuxDoInlineError(message: message)
                            .padding(.leading, LinuxDoDetailLayout.contentLeading)
                            .padding(.trailing, LinuxDoDetailLayout.contentTrailing)
                            .padding(.top, 14)
                    }
                    ForEach(detail.posts) { post in
                        LinuxDoPostView(
                            post: post,
                            contentBlocks: store.contentBlocks(for: post),
                            contentBlocksForReply: { store.contentBlocks(for: $0) },
                            isTopicOwner: post.postNumber == 1,
                            profileState: store.userProfileState(username: post.username),
                            postsInTopic: postCount(for: post.username, in: detail),
                            repliesState: state.replyStates[post.id] ?? LinuxDoPostRepliesState(),
                            replyComposer: state.replyComposers[post.id] ?? LinuxDoComposerState(),
                            replyDraft: Binding(
                                get: { store.topicStates[topicID]?.replyComposers[post.id]?.raw ?? "" },
                                set: { store.setReplyDraft(topicID: topicID, postID: post.id, raw: $0) }
                            ),
                            emojiURL: { store.emojiURL(for: $0) },
                            isLikePending: state.pendingLikePostIDs.contains(post.id),
                            isReactionPending: state.pendingReactionPostIDs.contains(post.id),
                            canWrite: store.canWriteForum,
                            onLoadProfile: { Task { await store.loadUserProfile(username: post.username) } },
                            onRetryProfile: { Task { await store.loadUserProfile(username: post.username, force: true) } },
                            onToggleReplies: { store.toggleReplies(topicID: topicID, postID: post.id) },
                            onBeginReply: { store.beginReply(topicID: topicID, postID: post.id) },
                            onCancelReply: { store.cancelReply(topicID: topicID, postID: post.id) },
                            onSubmitReply: { Task { await store.submitReply(topicID: topicID, postID: post.id) } },
                            onToggleLike: { Task { await store.toggleLike(topicID: topicID, postID: post.id) } },
                            onToggleReaction: { reactionID in Task { await store.toggleReaction(topicID: topicID, postID: post.id, reactionID: reactionID) } },
                            onOpenInBrowser: {
                                if let url = post.postURL ?? detail.topicURL {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        )
                            .padding(.leading, LinuxDoDetailLayout.postRowLeading)
                            .padding(.trailing, LinuxDoDetailLayout.contentTrailing)
                            .id(post.id)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: LinuxDoPostVisibilityPreference.self,
                                        value: LinuxDoPostVisibility(
                                            id: post.id,
                                            postNumber: post.postNumber,
                                            minY: geometry.frame(in: .named("linuxdo-topic-scroll")).minY
                                        )
                                    )
                                }
                            }
                            .onAppear {
                                if post.id == detail.posts.last?.id, state.hasMorePosts {
                                    Task { await store.loadMorePosts(topicID: topicID) }
                                }
                            }
                    }
                    if state.hasMorePosts {
                        Button {
                            Task { await store.loadMorePosts(topicID: topicID) }
                        } label: {
                            if state.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Load More Posts", systemImage: AppIcon.Action.download)
                            }
                        }
                        .frame(maxWidth: LinuxDoDetailLayout.contentMaxWidth)
                        .padding(.leading, LinuxDoDetailLayout.contentLeading)
                        .padding(.trailing, LinuxDoDetailLayout.contentTrailing)
                        .padding(.vertical, 18)
                    }
                }
                .frame(maxWidth: LinuxDoDetailLayout.totalMaxWidth, alignment: .leading)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .coordinateSpace(name: "linuxdo-topic-scroll")
            .onPreferenceChange(LinuxDoPostVisibilityPreference.self) { visible in
                updateVisiblePost(visible, topicID: topicID)
            }
            .onChange(of: state.scrollTargetPostID, initial: true) { _, postID in
                guard let postID else { return }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(postID, anchor: .top)
                    }
                    store.consumeScrollTarget(topicID: topicID, postID: postID)
                }
            }
        }
    }

    @ViewBuilder
    private func readingNavigator(
        mode: LinuxDoReadingNavigatorMode,
        currentFloor: Int,
        totalFloors: Int,
        loadedFloors: [Int],
        continueFloor: Int?,
        isLoading: Bool,
        topicID: Int
    ) -> some View {
        LinuxDoReadingNavigator(
            mode: mode,
            currentFloor: currentFloor,
            totalFloors: totalFloors,
            loadedFloors: loadedFloors,
            continueFloor: continueFloor,
            isLoading: isLoading
        ) { floor in
            Task { await store.jumpToPostNumber(topicID: topicID, postNumber: floor) }
        }
        .padding(.top, mode == .rail ? LinuxDoReadingNavigatorLayout.railTopInset : 0)
        .padding(.trailing, mode == .rail
            ? LinuxDoReadingNavigatorLayout.railTrailingInset
            : LinuxDoReadingNavigatorLayout.compactTrailingInset
        )
        .padding(.bottom, mode == .compact ? LinuxDoReadingNavigatorLayout.compactBottomInset : 0)
        .frame(
            maxWidth: .infinity,
            maxHeight: mode == .compact ? .infinity : nil,
            alignment: navigatorAlignment(for: mode)
        )
    }

    private func updateVisiblePost(_ visible: LinuxDoPostVisibility?, topicID: Int) {
        guard let visible else { return }
        let nextPostNumber = max(1, visible.postNumber)
        guard nextPostNumber != visiblePostNumber else { return }
        visiblePostNumber = nextPostNumber
        if nextPostNumber > max(1, lastRecordedPostNumber) {
            lastRecordedPostNumber = nextPostNumber
            pendingReadingPosition = LinuxDoPendingReadingPosition(
                topicID: topicID,
                postID: visible.id,
                postNumber: nextPostNumber
            )
        }
    }

    private func detailAlertMessages(for state: LinuxDoTopicDetailState) -> [String] {
        var messages: [String] = []
        if let error = state.error, !error.isEmpty {
            messages.append(error)
        }
        if let warning = state.timelineWarning, !warning.isEmpty, !messages.contains(warning) {
            messages.append(warning)
        }
        return messages
    }

    private func updateNavigatorMode(width: CGFloat, totalFloors: Int) {
        let nextMode = LinuxDoReadingNavigatorLayout.mode(
            width: width,
            totalFloors: totalFloors,
            currentMode: navigatorMode
        )
        guard nextMode != navigatorMode else { return }
        navigatorMode = nextMode
    }

    private func resetReadingState(topicID: Int) {
        visiblePostNumber = 1
        lastRecordedPostNumber = store.readingPosition(for: topicID)?.postNumber ?? 1
        pendingReadingPosition = nil
    }

    private func flushPendingReadingPosition() {
        guard let pendingReadingPosition else { return }
        self.pendingReadingPosition = nil
        store.recordReadingPosition(
            topicID: pendingReadingPosition.topicID,
            postID: pendingReadingPosition.postID,
            postNumber: pendingReadingPosition.postNumber
        )
    }

    private func header(
        detail: LinuxDoTopicDetail,
        state: LinuxDoTopicDetailState,
        topicID: Int,
        totalFloors: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.displayTitle)
                .font(.sora(18, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Label("\(detail.postsCount)", systemImage: AppIcon.Resource.textBubble)
                Label("\(detail.posts.count) loaded", systemImage: AppIcon.Action.downloadTray)
                if state.isStale {
                    Label("Stale", systemImage: AppIcon.Status.clockWarning)
                }
                if state.isJumping {
                    Label("Jumping", systemImage: AppIcon.Navigation.verticalResize)
                }
                if let position = visibleContinuePosition(topicID: topicID, totalFloors: totalFloors) {
                    Button {
                        Task { await store.continueReading(topicID: topicID) }
                    } label: {
                        Label("Continue #\(position.postNumber)", systemImage: AppIcon.Action.downloadToLine)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.stxAccent)
                    .help("Continue reading from #\(position.postNumber)")
                }
            }
            .font(.sora(10).monospacedDigit())
            .foregroundStyle(Color.stxMuted)

            if !detail.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(detail.tags.prefix(6), id: \.self) { tag in
                        Text(tag)
                            .font(.sora(9, weight: .medium))
                            .foregroundStyle(Color.stxAccent)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(Color.stxAccent.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: LinuxDoDetailLayout.headerMaxWidth, alignment: .leading)
        .padding(.leading, LinuxDoDetailLayout.headerLeading)
        .padding(.trailing, LinuxDoDetailLayout.contentTrailing)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func totalFloors(for detail: LinuxDoTopicDetail) -> Int {
        max(detail.stream.count, detail.postsCount, detail.posts.count)
    }

    private func postCount(for username: String, in detail: LinuxDoTopicDetail) -> Int {
        let normalized = username.lowercased()
        return detail.posts.reduce(0) { count, post in
            post.username.lowercased() == normalized ? count + 1 : count
        }
    }

    private func navigatorAlignment(for mode: LinuxDoReadingNavigatorMode) -> Alignment {
        switch mode {
        case .rail, .hidden:
            .topTrailing
        case .compact:
            .bottomTrailing
        }
    }

    private func validReadingPosition(topicID: Int, totalFloors: Int) -> LinuxDoReadingPosition? {
        guard let position = store.readingPosition(for: topicID),
              (2...max(2, totalFloors)).contains(position.postNumber),
              position.postNumber <= totalFloors else {
            return nil
        }
        return position
    }

    private func visibleContinuePosition(topicID: Int, totalFloors: Int) -> LinuxDoReadingPosition? {
        guard let position = validReadingPosition(topicID: topicID, totalFloors: totalFloors),
              visiblePostNumber + 1 < position.postNumber else {
            return nil
        }
        return position
    }
}

private struct LinuxDoPostView: View {
    let post: LinuxDoPost
    let contentBlocks: [LinuxDoContentBlock]
    let contentBlocksForReply: (LinuxDoPost) -> [LinuxDoContentBlock]
    let isTopicOwner: Bool
    let profileState: LinuxDoUserProfileState
    let postsInTopic: Int
    let repliesState: LinuxDoPostRepliesState
    let replyComposer: LinuxDoComposerState
    @Binding var replyDraft: String
    let emojiURL: (String) -> URL?
    let isLikePending: Bool
    let isReactionPending: Bool
    let canWrite: Bool
    let onLoadProfile: () -> Void
    let onRetryProfile: () -> Void
    let onToggleReplies: () -> Void
    let onBeginReply: () -> Void
    let onCancelReply: () -> Void
    let onSubmitReply: () -> Void
    let onToggleLike: () -> Void
    let onToggleReaction: (String) -> Void
    let onOpenInBrowser: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LinuxDoPostAvatarColumn(
                post: post,
                isTopicOwner: isTopicOwner,
                profileState: profileState,
                postsInTopic: postsInTopic,
                onLoadProfile: onLoadProfile,
                onRetryProfile: onRetryProfile
            )

            VStack(alignment: .leading, spacing: 11) {
                LinuxDoPostHeader(post: post, isTopicOwner: isTopicOwner)

                LinuxDoPostBody(contentBlocks: contentBlocks)

                LinuxDoReactionChipRow(
                    reactions: post.visibleReactions,
                    currentUserReaction: post.currentUserReaction,
                    emojiURL: emojiURL,
                    isPending: isReactionPending,
                    onToggleReaction: onToggleReaction
                )

                LinuxDoPostActionBar(
                    post: post,
                    repliesState: repliesState,
                    isLikePending: isLikePending,
                    isReactionPending: isReactionPending,
                    canWrite: canWrite,
                    emojiURL: emojiURL,
                    onToggleReplies: onToggleReplies,
                    onBeginReply: onBeginReply,
                    onToggleLike: onToggleLike,
                    onToggleReaction: onToggleReaction,
                    onOpenInBrowser: onOpenInBrowser
                )

                LinuxDoPostReplyPreviewList(
                    repliesState: repliesState,
                    contentBlocks: contentBlocksForReply
                )

                if replyComposer.isPresented {
                    LinuxDoComposer(
                        title: "Reply to #\(post.postNumber)",
                        placeholder: "Write a reply",
                        raw: $replyDraft,
                        isSubmitting: replyComposer.isSubmitting,
                        error: replyComposer.error,
                        canSubmit: replyComposer.canSubmitReply,
                        submitTitle: "Reply",
                        onCancel: onCancelReply,
                        onSubmit: onSubmitReply
                    )
                }
            }
            .frame(maxWidth: LinuxDoDetailLayout.contentMaxWidth, alignment: .leading)
            .padding(.bottom, 16)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
        }
        .padding(.top, 18)
    }
}

private struct LinuxDoPostAvatarColumn: View {
    let post: LinuxDoPost
    let isTopicOwner: Bool
    let profileState: LinuxDoUserProfileState
    let postsInTopic: Int
    let onLoadProfile: () -> Void
    let onRetryProfile: () -> Void
    @State private var isShowingProfile = false

    var body: some View {
        VStack(spacing: 8) {
            Button {
                isShowingProfile = true
                onLoadProfile()
            } label: {
                avatar
            }
            .buttonStyle(.plain)
            .help("User Profile")
            .accessibilityLabel("User Profile")
            .popover(isPresented: $isShowingProfile, arrowEdge: .trailing) {
                LinuxDoUserProfilePopover(
                    fallbackUsername: post.username,
                    fallbackDisplayName: post.displayAuthorName,
                    fallbackAvatarURL: post.avatarURL,
                    state: profileState,
                    postsInTopic: postsInTopic,
                    onRetry: onRetryProfile
                )
            }

            Text("#\(post.postNumber)")
                .font(.sora(9).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
        }
        .frame(width: 48)
    }

    private var avatar: some View {
        AsyncImage(url: post.avatarURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: AppIcon.People.profileFilled)
                .foregroundStyle(Color.stxMuted)
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.stxAccent.opacity(isTopicOwner ? 0.45 : 0.18), lineWidth: 1))
    }
}

private struct LinuxDoPostHeader: View {
    let post: LinuxDoPost
    let isTopicOwner: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(post.displayAuthorName)
                .font(.sora(12, weight: .semibold))
            if isTopicOwner {
                Text("OP")
                    .font(.sora(8, weight: .bold))
                    .foregroundStyle(Color.stxAccent)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(Color.stxAccent.opacity(0.12), in: Capsule())
            }
            if let replyTo = post.replyToPostNumber {
                Text("replying to #\(replyTo)")
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 0)
            Text(post.createdAt.map { Format.relativeDate($0) } ?? "Unknown time")
                .font(.sora(9))
                .foregroundStyle(Color.stxMuted)
        }
    }
}

private struct LinuxDoPostBody: View {
    let contentBlocks: [LinuxDoContentBlock]

    var body: some View {
        LinuxDoRichContentList(blocks: contentBlocks, context: .post)
    }
}

private enum LinuxDoRichContentContext: Equatable {
    case post
    case quote(depth: Int)

    var quoteDepth: Int {
        switch self {
        case .post: 0
        case .quote(let depth): depth
        }
    }

    var nestedQuoteContext: LinuxDoRichContentContext {
        .quote(depth: quoteDepth + 1)
    }

    var imageMaxHeight: CGFloat {
        switch self {
        case .post: 460
        case .quote: 160
        }
    }

    var bodyFontSize: CGFloat {
        switch self {
        case .post: 12
        case .quote: 11
        }
    }
}

private struct LinuxDoReactionChipRow: View {
    let reactions: [LinuxDoReaction]
    let currentUserReaction: String?
    let emojiURL: (String) -> URL?
    let isPending: Bool
    let onToggleReaction: (String) -> Void

    var body: some View {
        if !reactions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(reactions) { reaction in
                        Button {
                            onToggleReaction(reaction.id)
                        } label: {
                            HStack(spacing: 5) {
                                LinuxDoReactionGlyph(
                                    reactionID: reaction.id,
                                    displayText: reaction.displayText,
                                    imageURL: emojiURL(reaction.id),
                                    size: 18
                                )
                                Text("\(reaction.count)")
                                    .font(.sora(10, weight: .semibold).monospacedDigit())
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(chipBackground(for: reaction), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isPending)
                        .help("React with \(reaction.id)")
                    }
                }
            }
        }
    }

    private func chipBackground(for reaction: LinuxDoReaction) -> Color {
        currentUserReaction == reaction.id ? Color.stxAccent.opacity(0.18) : Color.primary.opacity(0.055)
    }
}

private struct LinuxDoPostActionBar: View {
    let post: LinuxDoPost
    let repliesState: LinuxDoPostRepliesState
    let isLikePending: Bool
    let isReactionPending: Bool
    let canWrite: Bool
    let emojiURL: (String) -> URL?
    let onToggleReplies: () -> Void
    let onBeginReply: () -> Void
    let onToggleLike: () -> Void
    let onToggleReaction: (String) -> Void
    let onOpenInBrowser: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleLike) {
                Label("\(post.effectiveLikeCount)", systemImage: post.isLikedByCurrentUser ? AppIcon.LinuxDo.likeFilled : AppIcon.LinuxDo.like)
                    .foregroundStyle(post.isLikedByCurrentUser ? .red : Color.stxMuted)
            }
            .disabled(!canWrite || isLikePending || !post.canToggleLike)
            .help(canWrite ? "Like" : "Sign in with a browser session to like")

            Button(action: onBeginReply) {
                Label("Reply", systemImage: AppIcon.Action.reply)
            }
            .disabled(!canWrite)
            .help(canWrite ? "Reply" : "Sign in with a browser session to reply")

            if post.replyCount > 0 || repliesState.hasLoaded {
                Button(action: onToggleReplies) {
                    Label(
                        repliesState.isExpanded ? "Hide \(max(post.replyCount, repliesState.replies.count))" : "\(max(post.replyCount, repliesState.replies.count)) replies",
                        systemImage: repliesState.isExpanded ? "chevron.up" : "chevron.down"
                    )
                }
                .disabled(repliesState.isLoading)
                .help(repliesState.isExpanded ? "Hide replies" : "Show replies")
            }

            Menu {
                ForEach(LinuxDoReactionCatalog.defaultReactionIDs, id: \.self) { reactionID in
                    Button {
                        onToggleReaction(reactionID)
                    } label: {
                        HStack {
                            LinuxDoReactionGlyph(
                                reactionID: reactionID,
                                displayText: LinuxDoReactionCatalog.displayText(for: reactionID),
                                imageURL: emojiURL(reactionID),
                                size: 16
                            )
                            Text(reactionID)
                        }
                    }
                }
            } label: {
                Image(systemName: AppIcon.People.smile)
                    .frame(width: 18, height: 18)
            }
            .disabled(!canWrite || isReactionPending)
            .help(canWrite ? "Add reaction" : "Sign in with a browser session to react")

            if post.reads > 0 {
                Label("\(post.reads)", systemImage: AppIcon.Status.visible)
                    .foregroundStyle(Color.stxMuted)
            }

            Spacer(minLength: 0)

            Button(action: onOpenInBrowser) {
                Image(systemName: AppIcon.App.safari)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxMuted)
            .help("Open in browser")
        }
        .buttonStyle(.plain)
        .font(.sora(10).monospacedDigit())
        .foregroundStyle(Color.stxMuted)
    }
}

private struct LinuxDoReactionGlyph: View {
    let reactionID: String
    let displayText: String
    let imageURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(reactionID))
    }

    private var fallback: some View {
        Text(displayText)
            .font(.sora(size - 2))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

private struct LinuxDoPostReplyPreviewList: View {
    let repliesState: LinuxDoPostRepliesState
    let contentBlocks: (LinuxDoPost) -> [LinuxDoContentBlock]

    var body: some View {
        if repliesState.isExpanded {
            VStack(alignment: .leading, spacing: 0) {
                if repliesState.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading replies")
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                    }
                    .padding(.vertical, 8)
                }

                if let error = repliesState.error {
                    LinuxDoInlineError(message: error)
                        .padding(.vertical, 8)
                }

                ForEach(repliesState.replies) { reply in
                    LinuxDoReplyPreviewRow(reply: reply, contentBlocks: contentBlocks(reply))
                }
            }
            .padding(.top, 4)
        }
    }
}

private struct LinuxDoReplyPreviewRow: View {
    let reply: LinuxDoPost
    let contentBlocks: [LinuxDoContentBlock]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(reply.effectiveLikeCount)")
                .font(.sora(10, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
                .frame(width: 28, alignment: .trailing)
            Image(systemName: AppIcon.Action.reply)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(reply.textPreview)
                        .font(.sora(11, weight: .medium))
                        .lineLimit(2)
                    Text("–")
                        .foregroundStyle(Color.stxMuted)
                    Text(reply.displayAuthorName)
                        .foregroundStyle(Color.stxAccent)
                    Text(reply.createdAt.map { Format.relativeDate($0) } ?? "")
                        .foregroundStyle(Color.stxMuted)
                }
                .font(.sora(10))

                if contentBlocks.count > 1 {
                    Text(contentBlocks.dropFirst().map { plainText($0) }.joined(separator: " "))
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
        }
    }

    private func plainText(_ block: LinuxDoContentBlock) -> String {
        switch block.kind {
        case .paragraph(let nodes), .heading(_, let nodes):
            nodes.map(\.plainPreview).joined()
        case .quote(_, let blocks), .details(_, let blocks), .spoiler(let blocks):
            blocks.map(plainText).joined(separator: " ")
        case .callout(let callout):
            ([callout.title].compactMap(\.self) + callout.blocks.map(plainText)).joined(separator: " ")
        case .event(let event):
            [event.name, event.startsAt, event.endsAt].compactMap(\.self).joined(separator: " ")
        case .codeBlock(_, let code), .rawHTML(let code):
            code
        case .list(_, let items):
            items.flatMap(\.blocks).map(plainText).joined(separator: " ")
        case .table(let headers, let rows):
            (headers.flatMap(\.blocks) + rows.flatMap(\.cells).flatMap(\.blocks))
                .map(plainText)
                .joined(separator: " ")
        case .image, .onebox, .divider:
            ""
        }
    }
}

private struct LinuxDoComposer: View {
    let title: String
    let placeholder: String
    @Binding var raw: String
    let isSubmitting: Bool
    let error: String?
    let canSubmit: Bool
    let submitTitle: String
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.sora(11, weight: .semibold))
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .controlSize(.small)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $raw)
                    .font(.sora(12))
                    .frame(minHeight: 84)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                if raw.isEmpty {
                    Text(placeholder)
                        .font(.sora(12))
                        .foregroundStyle(Color.stxMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .padding(6)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            }

            if let error {
                LinuxDoInlineError(message: error)
            }

            HStack {
                Spacer(minLength: 0)
                Button {
                    onSubmit()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(submitTitle, systemImage: AppIcon.Action.send)
                    }
                }
                .controlSize(.small)
                .disabled(!canSubmit)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
        .onAppear {
            isFocused = true
        }
    }
}

private struct LinuxDoRichContentList: View {
    let blocks: [LinuxDoContentBlock]
    let context: LinuxDoRichContentContext
    var spacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(blocks) { block in
                LinuxDoContentBlockView(block: block, context: context)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LinuxDoContentBlockView: View {
    let block: LinuxDoContentBlock
    let context: LinuxDoRichContentContext

    var body: some View {
        switch block.kind {
        case .paragraph(let nodes):
            LinuxDoRichInlineText(nodes: nodes, fontSize: context.bodyFontSize)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let nodes):
            LinuxDoRichInlineText(nodes: nodes, fontSize: headingSize(for: level), weight: .semibold)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 4 : 2)
        case .quote(let attribution, let blocks):
            LinuxDoQuoteCard(attribution: attribution, blocks: blocks, context: context)
        case .callout(let callout):
            LinuxDoCalloutBlock(callout: callout, context: context)
        case .event(let event):
            LinuxDoEventBlock(event: event)
        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 0) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.sora(9, weight: .semibold))
                        .foregroundStyle(Color.stxMuted)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                }
                AppScrollView(.horizontal) {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                }
            }
            .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    LinuxDoListItemView(item: item, marker: marker(for: item, ordered: ordered, index: index), context: context)
                }
            }
        case .image(let url, let alt, let width, let height, let linkURL):
            LinuxDoImageBlock(url: url, alt: alt, width: width, height: height, linkURL: linkURL, context: context)
        case .onebox(let onebox):
            LinuxDoOneboxView(onebox: onebox)
        case .table(let headers, let rows):
            AppScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    if !headers.isEmpty {
                        GridRow {
                            ForEach(headers) { cell in
                                tableCell(cell.blocks, isHeader: true)
                            }
                        }
                    }
                    ForEach(rows) { row in
                        GridRow {
                            ForEach(row.cells) { cell in
                                tableCell(cell.blocks, isHeader: false)
                            }
                        }
                    }
                }
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 6))
            }
        case .details(let summary, let blocks):
            LinuxDoDisclosureBlockView(summary: summary, blocks: blocks, icon: "chevron.right", context: context)
        case .spoiler(let blocks):
            LinuxDoDisclosureBlockView(summary: [.text("Spoiler")], blocks: blocks, icon: "eye.slash", context: context)
        case .divider:
            StxRule()
                .padding(.vertical, 5)
        case .rawHTML(let text):
            Text(text)
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func marker(for item: LinuxDoListItem, ordered: Bool, index: Int) -> LinuxDoListMarker {
        if let taskState = item.taskState {
            return .task(taskState)
        }
        return ordered ? .text("\(index + 1).") : .text("-")
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: 20
        case 2: 17
        case 3: 15
        default: 13
        }
    }

    private func tableCell(_ blocks: [LinuxDoContentBlock], isHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(blocks) { block in
                LinuxDoContentBlockView(block: block, context: context)
            }
        }
        .font(isHeader ? .sora(11, weight: .semibold) : .sora(11))
        .padding(8)
        .frame(minWidth: 120, alignment: .topLeading)
        .border(Color.primary.opacity(0.12), width: 0.5)
    }
}

private enum LinuxDoListMarker: Equatable {
    case text(String)
    case task(LinuxDoTaskState)
}

private struct LinuxDoListItemView: View {
    let item: LinuxDoListItem
    let marker: LinuxDoListMarker
    let context: LinuxDoRichContentContext

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            markerView
                .frame(width: markerWidth, alignment: .trailing)
            LinuxDoRichContentList(blocks: item.blocks, context: context, spacing: 6)
        }
    }

    @ViewBuilder
    private var markerView: some View {
        switch marker {
        case .text(let text):
            Text(text)
                .font(.sora(context.bodyFontSize).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
        case .task(let state):
            Image(systemName: state == .checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(state == .checked ? Color.stxAccent : Color.stxMuted)
                .accessibilityLabel(state == .checked ? "Completed task" : "Incomplete task")
        }
    }

    private var markerWidth: CGFloat {
        switch marker {
        case .text(let text):
            text == "-" ? 14 : 26
        case .task:
            18
        }
    }
}

private struct LinuxDoQuoteCard: View {
    let attribution: LinuxDoQuoteAttribution?
    let blocks: [LinuxDoContentBlock]
    let context: LinuxDoRichContentContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if attribution != nil {
                header
            }
            LinuxDoRichContentList(blocks: blocks, context: context.nestedQuoteContext, spacing: 8)
        }
        .padding(.vertical, 8)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(context.quoteDepth == 0 ? 0.055 : 0.035), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.stxAccent.opacity(context.quoteDepth == 0 ? 0.45 : 0.28)).frame(width: 3)
        }
        .padding(.leading, context.quoteDepth > 0 ? 10 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quote")
    }

    @ViewBuilder
    private var header: some View {
        if let attribution {
            HStack(spacing: 6) {
                if let avatarURL = attribution.avatarURL {
                    AsyncImage(url: avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: AppIcon.Resource.quote)
                            .foregroundStyle(Color.stxMuted)
                    }
                    .frame(width: 18, height: 18)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                }
                Text(attribution.displayName ?? attribution.username ?? attribution.topicTitle ?? "Quote")
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                if let postNumber = attribution.postNumber {
                    Text("#\(postNumber)")
                        .font(.sora(9).monospacedDigit())
                        .foregroundStyle(Color.stxMuted.opacity(0.75))
                }
                Spacer(minLength: 0)
                if let url = attribution.postURL ?? attribution.topicURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: AppIcon.Navigation.openForward)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.stxMuted)
                    .help("Open quoted post")
                }
            }
        }
    }
}

private struct LinuxDoCalloutBlock: View {
    let callout: LinuxDoCallout
    let context: LinuxDoRichContentContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = callout.title, !title.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .bold))
                    Text(title)
                        .font(.sora(13, weight: .bold))
                }
                .foregroundStyle(accentColor)
            }
            LinuxDoRichContentList(blocks: callout.blocks, context: context, spacing: 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 7))
    }

    private var iconName: String {
        switch callout.style {
        case .note: AppIcon.Status.infoFilled
        case .tip: AppIcon.Feature.tip
        case .important: AppIcon.Feature.important
        case .warning: AppIcon.Status.warningFilled
        case .danger: AppIcon.Metric.boltFilled
        case .generic: AppIcon.Resource.textBubbleFilled
        }
    }

    private var accentColor: Color {
        switch callout.style {
        case .note: Color.stxAccent
        case .tip: .green
        case .important: .purple
        case .warning: .orange
        case .danger: .red
        case .generic: Color.stxMuted
        }
    }

    private var backgroundColor: Color {
        switch callout.style {
        case .danger: Color.red.opacity(0.18)
        case .warning: Color.orange.opacity(0.16)
        case .tip: Color.green.opacity(0.13)
        case .important: Color.purple.opacity(0.14)
        case .note: Color.stxAccent.opacity(0.12)
        case .generic: Color.primary.opacity(0.05)
        }
    }
}

private struct LinuxDoEventBlock: View {
    let event: LinuxDoPostEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(monthText)
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(.red)
                Text(dayText)
                    .font(.sora(18, weight: .semibold).monospacedDigit())
            }
            .frame(width: 48, height: 48)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(event.name ?? "Event")
                    .font(.sora(14, weight: .semibold))
                HStack(spacing: 6) {
                    Image(systemName: AppIcon.Status.clockFilled)
                    Text(eventRangeText)
                }
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                if let status = event.status {
                    Text(status.capitalized)
                        .font(.sora(9, weight: .medium))
                        .foregroundStyle(Color.stxAccent)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(Color.stxAccent.opacity(0.1), in: Capsule())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var eventRangeText: String {
        [event.startsAt, event.endsAt].compactMap(\.self).joined(separator: " -> ")
            + (event.timezone.map { " \($0)" } ?? "")
    }

    private var monthText: String {
        guard let startsAt = event.startsAt else { return "--" }
        let datePart = startsAt.split(separator: " ").first ?? Substring(startsAt)
        let parts = datePart.split(separator: "-")
        guard parts.count >= 2 else { return "--" }
        return "\(Int(parts[1]) ?? 0)月"
    }

    private var dayText: String {
        guard let startsAt = event.startsAt else { return "--" }
        let datePart = startsAt.split(separator: " ").first ?? Substring(startsAt)
        let parts = datePart.split(separator: "-")
        guard parts.count >= 3 else { return "--" }
        return "\(Int(parts[2]) ?? 0)"
    }
}

private struct LinuxDoImageBlock: View {
    let url: URL
    let alt: String?
    let width: Int?
    let height: Int?
    let linkURL: URL?
    let context: LinuxDoRichContentContext

    var body: some View {
        Button {
            NSWorkspace.shared.open(linkURL ?? url)
        } label: {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: min(90, context.imageMaxHeight))
                    .frame(maxWidth: .infinity)
            }
            .frame(width: fixedSmallWidth, height: fixedSmallHeight)
            .frame(maxHeight: context.imageMaxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(alt ?? "LinuxDo image")
        }
        .buttonStyle(.plain)
    }

    private var fixedSmallWidth: CGFloat? {
        guard isSmallImage, let width else { return nil }
        return CGFloat(width)
    }

    private var fixedSmallHeight: CGFloat? {
        guard isSmallImage, let height else { return nil }
        return CGFloat(height)
    }

    private var isSmallImage: Bool {
        max(width ?? 0, height ?? 0) > 0 && max(width ?? 0, height ?? 0) <= 80
    }
}

private struct LinuxDoRichInlineText: View {
    let nodes: [LinuxDoInlineNode]
    var fontSize: CGFloat
    var weight: Font.Weight = .regular

    var body: some View {
        Text(Self.attributedString(from: nodes, fontSize: fontSize, weight: weight))
            .environment(\.openURL, OpenURLAction { url in
                NSWorkspace.shared.open(url)
                return .handled
            })
    }

    private static func attributedString(from nodes: [LinuxDoInlineNode], fontSize: CGFloat, weight: Font.Weight) -> AttributedString {
        var result = AttributedString()
        append(nodes, style: LinuxDoInlineStyle(fontSize: fontSize, weight: weight), to: &result)
        return result
    }

    private static func append(_ nodes: [LinuxDoInlineNode], style: LinuxDoInlineStyle, to result: inout AttributedString) {
        for node in nodes {
            switch node {
            case .text(let text):
                result.append(run(text.addingSoftBreaksToLongRuns(), style: style))
            case .strong(let children):
                append(children, style: style.with(strong: true), to: &result)
            case .emphasis(let children):
                append(children, style: style.with(emphasis: true), to: &result)
            case .strikethrough(let children):
                append(children, style: style.with(strikethrough: true), to: &result)
            case .highlight(let children):
                append(children, style: style.with(highlight: true), to: &result)
            case .keyboard(let children):
                append(children, style: style.with(keyboard: true), to: &result)
            case .subscript(let children):
                append(children, style: style.with(isSubscript: true), to: &result)
            case .superscript(let children):
                append(children, style: style.with(superscript: true), to: &result)
            case .spoiler(let children):
                append(children, style: style.with(spoiler: true), to: &result)
            case .code(let text):
                result.append(run(text.addingSoftBreaksToLongRuns(), style: style.with(code: true)))
            case .link(let url, let children):
                var childRun = AttributedString()
                append(children, style: style, to: &childRun)
                childRun.link = url
                childRun.foregroundColor = Color.stxAccent
                result.append(childRun)
            case .image(_, let alt, _, _, let isEmoji):
                result.append(run(isEmoji ? (alt ?? "") : (alt ?? "[image]"), style: style))
            case .mention(let username, let url):
                var mention = run("@\(username)", style: style)
                mention.foregroundColor = Color.stxAccent
                if let url { mention.link = url }
                result.append(mention)
            case .hashtag(let text, let url):
                var hashtag = run(text.hasPrefix("#") ? text : "#\(text)", style: style)
                hashtag.foregroundColor = Color.stxAccent
                if let url { hashtag.link = url }
                result.append(hashtag)
            case .lineBreak:
                result.append(AttributedString("\n"))
            }
        }
    }

    private static func run(_ text: String, style: LinuxDoInlineStyle) -> AttributedString {
        var run = AttributedString(text)
        var fontSize = style.fontSize
        if style.isSubscript || style.isSuperscript {
            fontSize -= 2
        }
        var font: Font = style.isCode || style.isKeyboard
            ? .system(size: fontSize - 1, design: .monospaced)
            : .sora(fontSize, weight: style.isStrong ? .semibold : style.weight)
        if style.isEmphasis {
            font = font.italic()
        }
        run.font = font
        if style.isStrikethrough {
            run.strikethroughStyle = .single
        }
        if style.isCode || style.isKeyboard {
            run.backgroundColor = Color.primary.opacity(0.08)
        }
        if style.isHighlight {
            run.backgroundColor = Color.yellow.opacity(0.28)
        }
        if style.isSpoiler {
            run.backgroundColor = Color.primary.opacity(0.12)
            run.foregroundColor = Color.primary.opacity(0.72)
        }
        if style.isSubscript {
            run.baselineOffset = -style.fontSize * 0.22
        }
        if style.isSuperscript {
            run.baselineOffset = style.fontSize * 0.35
        }
        return run
    }
}

private struct LinuxDoInlineStyle {
    let fontSize: CGFloat
    let weight: Font.Weight
    var isStrong = false
    var isEmphasis = false
    var isStrikethrough = false
    var isCode = false
    var isHighlight = false
    var isKeyboard = false
    var isSubscript = false
    var isSuperscript = false
    var isSpoiler = false

    func with(
        strong: Bool = false,
        emphasis: Bool = false,
        strikethrough: Bool = false,
        code: Bool = false,
        highlight: Bool = false,
        keyboard: Bool = false,
        isSubscript: Bool = false,
        superscript: Bool = false,
        spoiler: Bool = false
    ) -> LinuxDoInlineStyle {
        var copy = self
        copy.isStrong = copy.isStrong || strong
        copy.isEmphasis = copy.isEmphasis || emphasis
        copy.isStrikethrough = copy.isStrikethrough || strikethrough
        copy.isCode = copy.isCode || code
        copy.isHighlight = copy.isHighlight || highlight
        copy.isKeyboard = copy.isKeyboard || keyboard
        copy.isSubscript = copy.isSubscript || isSubscript
        copy.isSuperscript = copy.isSuperscript || superscript
        copy.isSpoiler = copy.isSpoiler || spoiler
        return copy
    }
}

private struct LinuxDoOneboxView: View {
    let onebox: LinuxDoOnebox

    var body: some View {
        Button {
            if let url = onebox.url {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if let imageURL = onebox.imageURL {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.primary.opacity(0.05)
                    }
                    .frame(width: 72, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(onebox.title ?? onebox.url?.host() ?? "Link")
                        .font(.sora(12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let description = onebox.description, !description.isEmpty {
                        Text(description)
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(2)
                    }
                    if let url = onebox.url {
                        Text(url.host() ?? url.absoluteString)
                            .font(.sora(9))
                            .foregroundStyle(Color.stxAccent)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(onebox.url == nil)
    }
}

private struct LinuxDoDisclosureBlockView: View {
    let summary: [LinuxDoInlineNode]
    let blocks: [LinuxDoContentBlock]
    let icon: String
    let context: LinuxDoRichContentContext
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(blocks) { block in
                    LinuxDoContentBlockView(block: block, context: context)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                LinuxDoRichInlineText(nodes: summary, fontSize: 11, weight: .medium)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct LinuxDoPendingReadingPosition: Equatable {
    let topicID: Int
    let postID: Int
    let postNumber: Int
}

struct LinuxDoPostVisibility: Equatable {
    static let topGuideY: CGFloat = 12

    let id: Int
    let postNumber: Int
    let minY: CGFloat

    var distanceToTopGuide: CGFloat {
        abs(minY - Self.topGuideY)
    }

    func isBetterCandidate(than other: LinuxDoPostVisibility) -> Bool {
        let distance = distanceToTopGuide
        let otherDistance = other.distanceToTopGuide
        if distance == otherDistance {
            return postNumber < other.postNumber
        }
        return distance < otherDistance
    }
}

private extension LinuxDoInlineNode {
    var plainPreview: String {
        switch self {
        case .text(let text), .code(let text):
            text
        case .strong(let children),
             .emphasis(let children),
             .strikethrough(let children),
             .highlight(let children),
             .keyboard(let children),
             .subscript(let children),
             .superscript(let children),
             .spoiler(let children):
            children.map(\.plainPreview).joined()
        case .link(_, let children):
            children.map(\.plainPreview).joined()
        case .image(_, let alt, _, _, _):
            alt ?? ""
        case .mention(let username, _):
            "@\(username)"
        case .hashtag(let text, _):
            text
        case .lineBreak:
            "\n"
        }
    }
}

private extension String {
    func addingSoftBreaksToLongRuns(maxRunLength: Int = 32, chunkLength: Int = 16) -> String {
        split(separator: " ", omittingEmptySubsequences: false)
            .map { part -> String in
                guard part.count > maxRunLength else { return String(part) }
                var result = ""
                var count = 0
                for character in part {
                    if count > 0 && count.isMultiple(of: chunkLength) {
                        result += "\u{200B}"
                    }
                    result.append(character)
                    count += 1
                }
                return result
            }
            .joined(separator: " ")
    }
}

struct LinuxDoPostVisibilityPreference: PreferenceKey {
    static let defaultValue: LinuxDoPostVisibility? = nil

    static func reduce(value: inout LinuxDoPostVisibility?, nextValue: () -> LinuxDoPostVisibility?) {
        guard let candidate = nextValue() else { return }
        guard let current = value else {
            value = candidate
            return
        }
        if candidate.isBetterCandidate(than: current) {
            value = candidate
        }
    }
}
