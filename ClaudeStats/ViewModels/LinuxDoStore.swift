import AppKit
import Foundation
import Observation

struct LinuxDoListState: Sendable {
    var topics: [LinuxDoTopicSummary] = []
    var nextPage: Int? = 0
    var isLoading = false
    var isRefreshing = false
    var isStale = false
    var lastFetchedAt: Date?
    var error: String?

    var canLoadMore: Bool { nextPage != nil && !isLoading && !isRefreshing }
}

struct LinuxDoTopicDetailState: Sendable {
    var detail: LinuxDoTopicDetail?
    var loadedPostIDs: Set<Int> = []
    var remainingPostIDs: [Int] = []
    var replyStates: [Int: LinuxDoPostRepliesState] = [:]
    var replyComposers: [Int: LinuxDoComposerState] = [:]
    var pendingLikePostIDs: Set<Int> = []
    var pendingReactionPostIDs: Set<Int> = []
    var nextPage: Int?
    var scrollTargetPostID: Int?
    var timelineWarning: String?
    var isLoading = false
    var isLoadingMore = false
    var isJumping = false
    var isStale = false
    var error: String?

    var hasMorePosts: Bool {
        !remainingPostIDs.isEmpty || nextPage != nil
    }
}

struct LinuxDoPostRepliesState: Sendable {
    var replies: [LinuxDoPost] = []
    var reactionsByPostID: [Int: [LinuxDoReaction]] = [:]
    var isExpanded = false
    var isLoading = false
    var hasLoaded = false
    var error: String?
}

struct LinuxDoComposerState: Sendable, Equatable {
    var title = ""
    var raw = ""
    var isPresented = false
    var isSubmitting = false
    var error: String?

    var canSubmitReply: Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && !isSubmitting
    }

    var canSubmitTopic: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            && raw.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            && !isSubmitting
    }
}

struct LinuxDoUserProfileState: Sendable {
    var profile: LinuxDoUserProfile?
    var isLoading = false
    var fetchedAt: Date?
    var error: String?
}

enum LinuxDoAuthenticationStatus: Equatable, Sendable {
    case guest
    case userAPIKey
    case webSession(username: String?, avatarURL: URL?)

    var isAuthenticated: Bool {
        switch self {
        case .guest:
            false
        case .userAPIKey, .webSession:
            true
        }
    }

    var description: String {
        switch self {
        case .guest:
            "Guest"
        case .userAPIKey:
            "User API Key"
        case .webSession:
            "Browser session"
        }
    }

    var username: String? {
        switch self {
        case .webSession(let username, _):
            username
        case .guest, .userAPIKey:
            nil
        }
    }

    var avatarURL: URL? {
        switch self {
        case .webSession(_, let avatarURL):
            avatarURL
        case .guest, .userAPIKey:
            nil
        }
    }
}

private struct LinuxDoPostContentCacheKey: Hashable, Sendable {
    let postID: Int
    let updatedAt: Date?
    let htmlLength: Int
    let htmlHash: Int

    init(post: LinuxDoPost) {
        self.postID = post.id
        self.updatedAt = post.updatedAt
        self.htmlLength = post.cookedHTML.count
        self.htmlHash = post.cookedHTML.hashValue
    }
}

@MainActor
@Observable
final class LinuxDoStore {
    private(set) var categories: [LinuxDoCategory] = []
    private(set) var listStates: [String: LinuxDoListState] = [:]
    private(set) var topicStates: [Int: LinuxDoTopicDetailState] = [:]
    private(set) var currentUser: LinuxDoCurrentUser?
    private(set) var authenticationStatus: LinuxDoAuthenticationStatus
    private(set) var notifications: [LinuxDoNotification] = []
    private(set) var notificationAuthorization: LinuxDoNotificationAuthorizationStatus = .notDetermined
    private(set) var emojiURLsByID: [String: URL] = [:]
    private(set) var userProfileStates: [String: LinuxDoUserProfileState] = [:]
    private(set) var isLoadingCategories = false
    private(set) var isSigningIn = false
    private(set) var isAwaitingExternalBrowserSignIn = false
    private(set) var isRefreshingNotifications = false
    private(set) var lastError: String?
    private(set) var rateLimitedUntil: Date?

    var selectedFeed: LinuxDoFeed {
        didSet {
            preferences.linuxDoSelectedFeed = selectedFeed.storedValue
        }
    }
    var topPeriod: LinuxDoTopPeriod = .weekly
    var searchText = ""
    var submittedSearch = ""
    var selectedTopicID: Int?
    var newTopicComposer = LinuxDoComposerState()

    var isAuthenticated: Bool {
        authenticationStatus.isAuthenticated
    }

    var canWriteForum: Bool {
        hasWritableWebSession
    }

    var authenticationDescription: String {
        authenticationStatus.description
    }

    var selectedTopicState: LinuxDoTopicDetailState? {
        selectedTopicID.flatMap { topicStates[$0] }
    }

    var currentListState: LinuxDoListState {
        listStates[selectedFeed.key] ?? LinuxDoListState()
    }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let client: any LinuxDoClienting
    @ObservationIgnored private let cache: any LinuxDoCaching
    @ObservationIgnored private let credentials: any LinuxDoCredentialStoring
    @ObservationIgnored private let authService: LinuxDoAuthService
    @ObservationIgnored private let notificationService: any LinuxDoNotificationServicing
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var notificationTask: Task<Void, Never>?
    @ObservationIgnored private var contentBlockCache: [LinuxDoPostContentCacheKey: [LinuxDoContentBlock]] = [:]
    @ObservationIgnored private var contentBlockCacheOrder: [LinuxDoPostContentCacheKey] = []
    @ObservationIgnored private let contentBlockCacheLimit = 1_000
    @ObservationIgnored private let userProfileCacheTTL: TimeInterval = 30 * 60
    @ObservationIgnored private var hasAttemptedEmojiCatalogLoad = false
    @ObservationIgnored private var isLoadingEmojiCatalog = false

    init(
        preferences: Preferences,
        credentials: any LinuxDoCredentialStoring = LinuxDoKeychainStore.shared,
        cache: any LinuxDoCaching = LinuxDoCache(),
        notificationService: any LinuxDoNotificationServicing = LinuxDoNotificationService(),
        client: (any LinuxDoClienting)? = nil,
        authService: LinuxDoAuthService? = nil
    ) {
        self.preferences = preferences
        self.credentials = credentials
        self.cache = cache
        self.notificationService = notificationService
        self.client = client ?? LinuxDoClient(credentials: credentials)
        self.authService = authService ?? LinuxDoAuthService(credentials: credentials)
        self.authenticationStatus = Self.authenticationStatus(from: credentials)
        self.selectedFeed = LinuxDoFeed.stored(preferences.linuxDoSelectedFeed) ?? .latest
        if case .top(let period) = selectedFeed {
            self.topPeriod = period
        }
    }

    deinit {
        searchTask?.cancel()
        notificationTask?.cancel()
    }

    func start() {
        refreshAuthenticationState()
        Task {
            notificationAuthorization = await notificationService.authorizationStatus()
            if preferences.linuxDoNotificationsEnabled {
                startNotificationPolling()
            }
        }
    }

    func loadInitialIfNeeded() async {
        Log.app.info("LinuxDo initial load started")
        await loadEmojiCatalogIfNeeded()
        await loadCategoriesIfNeeded()
        await loadCurrentFeedIfNeeded()
        refreshAuthenticationState()
        if isAuthenticated {
            await loadCurrentUserIfNeeded()
        }
        Log.app.info("LinuxDo initial load finished")
    }

    func selectFeed(_ feed: LinuxDoFeed) {
        if case .top(let period) = feed {
            topPeriod = period
        }
        selectedFeed = feed
        if case .search(let query) = feed {
            submittedSearch = query
            searchText = query
        }
        Task {
            await loadCurrentFeedIfNeeded()
        }
    }

    func selectTopPeriod(_ period: LinuxDoTopPeriod) {
        topPeriod = period
        selectFeed(.top(period))
    }

    func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            lastError = "Type at least two characters to search LinuxDo."
            return
        }
        submittedSearch = query
        selectFeed(.search(query))
    }

    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.submitSearch()
        }
    }

    func refreshCurrentFeed() async {
        await loadTopicList(feed: selectedFeed, force: true)
    }

    func loadCurrentFeedIfNeeded() async {
        await loadTopicList(feed: selectedFeed, force: false)
    }

    func loadMoreCurrentFeed() async {
        var state = listStates[selectedFeed.key] ?? LinuxDoListState()
        guard let nextPage = state.nextPage, !state.isLoading, !state.isRefreshing else { return }
        state.isLoading = true
        state.error = nil
        listStates[selectedFeed.key] = state
        do {
            let list = try await client.fetchTopicList(feed: selectedFeed, page: nextPage, now: .now)
            refreshAuthenticationState()
            state.topics.append(contentsOf: list.topics)
            state.nextPage = list.nextPage
            state.lastFetchedAt = list.fetchedAt
            state.isLoading = false
            try? cache.writeTopicList(LinuxDoTopicList(topics: state.topics, page: nextPage, nextPage: state.nextPage, fetchedAt: list.fetchedAt), feed: selectedFeed)
        } catch {
            state.isLoading = false
            state.error = userFacingMessage(error)
            Log.network.error("LinuxDo feed page load failed: \(state.error ?? "unknown", privacy: .public)")
            handle(error)
        }
        listStates[selectedFeed.key] = state
    }

    func selectTopic(_ topic: LinuxDoTopicSummary) {
        openTopic(id: topic.id, slug: topic.slug)
    }

    func openTopic(id: Int, slug: String?, postNumber: Int? = nil) {
        Task {
            await openTopicAndWait(id: id, slug: slug, postNumber: postNumber)
        }
    }

    @discardableResult
    func openTopicAndWait(id: Int, slug: String?, postNumber: Int? = nil) async -> Int? {
        selectedTopicID = id
        await loadTopic(id: id, slug: slug, force: false)
        if let postNumber {
            return await jumpToPostNumber(topicID: id, postNumber: postNumber)
        }
        return nil
    }

    func openTopic(_ route: LinuxDoTopicRoute) {
        openTopic(id: route.id, slug: route.slug, postNumber: route.postNumber)
    }

    func openNotification(_ notification: LinuxDoNotification) {
        Task {
            await openNotificationAndWait(notification)
        }
    }

    func contentBlocks(for post: LinuxDoPost) -> [LinuxDoContentBlock] {
        cachedContentBlocks(for: post)
    }

    func readingPosition(for topicID: Int) -> LinuxDoReadingPosition? {
        preferences.linuxDoReadingPositions[topicID]
    }

    func recordReadingPosition(topicID: Int, postID: Int, postNumber: Int) {
        guard topicID > 0, postID > 0, postNumber > 0 else { return }
        let current = preferences.linuxDoReadingPositions[topicID]
        guard current.map(\.postNumber) ?? 0 < postNumber else { return }
        var positions = preferences.linuxDoReadingPositions
        positions[topicID] = LinuxDoReadingPosition(
            topicID: topicID,
            postID: postID,
            postNumber: postNumber,
            updatedAt: .now
        )
        preferences.linuxDoReadingPositions = positions
    }

    @discardableResult
    func continueReading(topicID: Int) async -> Int? {
        guard let position = readingPosition(for: topicID),
              let detail = topicStates[topicID]?.detail else { return nil }
        let totalFloors = totalFloors(for: detail)
        guard totalFloors >= 2,
              (2...totalFloors).contains(position.postNumber) else { return nil }
        return await jumpToPostIndex(topicID: topicID, index: position.postNumber - 1)
    }

    func emojiURL(for reactionID: String) -> URL? {
        emojiURLsByID[reactionID] ?? fallbackEmojiURL(for: reactionID)
    }

    func userProfileState(username: String) -> LinuxDoUserProfileState {
        userProfileStates[normalizedUsername(username)] ?? LinuxDoUserProfileState()
    }

    func loadUserProfile(username: String, force: Bool = false) async {
        let key = normalizedUsername(username)
        guard !key.isEmpty else { return }
        var state = userProfileStates[key] ?? LinuxDoUserProfileState()
        if !force,
           let fetchedAt = state.fetchedAt,
           state.profile != nil,
           Date().timeIntervalSince(fetchedAt) <= userProfileCacheTTL {
            return
        }
        guard !state.isLoading else { return }

        state.isLoading = true
        state.error = nil
        userProfileStates[key] = state

        do {
            let profile = try await client.fetchUserProfile(username: username)
            state = userProfileStates[key] ?? state
            state.profile = profile
            state.fetchedAt = Date()
            state.isLoading = false
            state.error = nil
        } catch {
            state = userProfileStates[key] ?? state
            state.isLoading = false
            state.error = userFacingMessage(error)
            handle(error)
        }
        userProfileStates[key] = state
    }

    func toggleReplies(topicID: Int, postID: Int) {
        var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
        var replies = state.replyStates[postID] ?? LinuxDoPostRepliesState()
        replies.isExpanded.toggle()
        let shouldLoad = replies.isExpanded && !replies.hasLoaded && !replies.isLoading
        state.replyStates[postID] = replies
        topicStates[topicID] = state
        if shouldLoad {
            Task { await loadReplies(topicID: topicID, postID: postID) }
        }
    }

    func beginReply(topicID: Int, postID: Int) {
        var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
        var composer = state.replyComposers[postID] ?? LinuxDoComposerState()
        composer.isPresented = true
        composer.error = nil
        state.replyComposers[postID] = composer
        topicStates[topicID] = state
    }

    func cancelReply(topicID: Int, postID: Int) {
        var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
        var composer = state.replyComposers[postID] ?? LinuxDoComposerState()
        composer.isPresented = false
        composer.raw = ""
        composer.error = nil
        state.replyComposers[postID] = composer
        topicStates[topicID] = state
    }

    func setReplyDraft(topicID: Int, postID: Int, raw: String) {
        var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
        var composer = state.replyComposers[postID] ?? LinuxDoComposerState()
        composer.raw = raw
        composer.error = nil
        state.replyComposers[postID] = composer
        topicStates[topicID] = state
    }

    func submitReply(topicID: Int, postID: Int) async {
        guard hasWritableWebSession else {
            setReplyError(topicID: topicID, postID: postID, message: "Sign in with a browser session to reply.")
            return
        }
        var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
        guard let parent = post(withID: postID, in: state) else { return }
        var composer = state.replyComposers[postID] ?? LinuxDoComposerState()
        let raw = composer.raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 2, !composer.isSubmitting else { return }
        composer.isSubmitting = true
        composer.error = nil
        state.replyComposers[postID] = composer
        topicStates[topicID] = state

        do {
            let created = try await client.createReply(topicID: topicID, raw: raw, replyToPostNumber: parent.postNumber)
            state = topicStates[topicID] ?? state
            if let detail = mergedDetail(state.detail, adding: [created]) {
                state.detail = detail
                refreshPaginationState(&state)
            }
            let incrementedParent = parent.replacingForumState(replyCount: parent.replyCount + 1)
            replacePost(in: &state, with: incrementedParent)
            var replies = state.replyStates[postID] ?? LinuxDoPostRepliesState()
            replies.replies = sortedPosts(uniquePosts(replies.replies + [created]), stream: [])
            replies.isExpanded = true
            replies.hasLoaded = true
            replies.isLoading = false
            replies.error = nil
            state.replyStates[postID] = replies
            composer.raw = ""
            composer.isPresented = false
            composer.isSubmitting = false
            state.replyComposers[postID] = composer
            prewarmContentBlocks(for: [created])
            if let detail = state.detail {
                try? cache.writeTopic(detail)
            }
        } catch {
            composer.isSubmitting = false
            composer.error = userFacingMessage(error)
            state.replyComposers[postID] = composer
            handle(error)
        }
        topicStates[topicID] = state
    }

    func toggleLike(topicID: Int, postID: Int) async {
        guard hasWritableWebSession else {
            setPostActionError(topicID: topicID, postID: postID, message: "Sign in with a browser session to like posts.")
            return
        }
        var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
        guard let original = post(withID: postID, in: state), !state.pendingLikePostIDs.contains(postID) else { return }
        let nextLiked = !original.isLikedByCurrentUser
        replacePost(in: &state, with: optimisticallyLikedPost(original, liked: nextLiked))
        state.pendingLikePostIDs.insert(postID)
        topicStates[topicID] = state

        do {
            let updated = try await client.toggleLike(postID: postID, liked: nextLiked)
            state = topicStates[topicID] ?? state
            replacePost(in: &state, with: updated)
            state.pendingLikePostIDs.remove(postID)
            clearPostActionError(topicID: topicID, postID: postID, state: &state)
            if let detail = state.detail {
                try? cache.writeTopic(detail)
            }
        } catch {
            state = topicStates[topicID] ?? state
            replacePost(in: &state, with: original)
            state.pendingLikePostIDs.remove(postID)
            setPostActionError(topicID: topicID, postID: postID, message: userFacingMessage(error), state: &state)
            handle(error)
        }
        topicStates[topicID] = state
    }

    func toggleReaction(topicID: Int, postID: Int, reactionID: String) async {
        guard hasWritableWebSession else {
            setPostActionError(topicID: topicID, postID: postID, message: "Sign in with a browser session to react.")
            return
        }
        var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
        guard let original = post(withID: postID, in: state), !state.pendingReactionPostIDs.contains(postID) else { return }
        let nextReaction = original.currentUserReaction == reactionID ? nil : reactionID
        replacePost(in: &state, with: optimisticallyReactedPost(original, nextReaction: nextReaction))
        state.pendingReactionPostIDs.insert(postID)
        topicStates[topicID] = state

        do {
            let updated = try await client.toggleReaction(postID: postID, reactionID: reactionID)
            state = topicStates[topicID] ?? state
            replacePost(in: &state, with: updated)
            state.pendingReactionPostIDs.remove(postID)
            clearPostActionError(topicID: topicID, postID: postID, state: &state)
            if let detail = state.detail {
                try? cache.writeTopic(detail)
            }
        } catch {
            state = topicStates[topicID] ?? state
            replacePost(in: &state, with: original)
            state.pendingReactionPostIDs.remove(postID)
            setPostActionError(topicID: topicID, postID: postID, message: userFacingMessage(error), state: &state)
            handle(error)
        }
        topicStates[topicID] = state
    }

    func loadReactionUsers(topicID: Int, postID: Int, reactionID: String? = nil) async {
        do {
            let reactions = try await client.fetchReactionUsers(postID: postID, reactionID: reactionID)
            var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
            guard let post = post(withID: postID, in: state) else { return }
            let merged = mergeReactions(existing: post.visibleReactions, fresh: reactions)
            replacePost(in: &state, with: post.replacingForumState(reactions: merged))
            topicStates[topicID] = state
        } catch {
            setPostActionError(topicID: topicID, postID: postID, message: userFacingMessage(error))
            handle(error)
        }
    }

    func presentNewTopicComposer() {
        guard hasWritableWebSession else {
            lastError = "Sign in with a browser session to create a topic."
            return
        }
        newTopicComposer.isPresented = true
        newTopicComposer.error = nil
    }

    func cancelNewTopicComposer() {
        newTopicComposer = LinuxDoComposerState()
    }

    func submitNewTopic() async {
        guard hasWritableWebSession else {
            newTopicComposer.error = "Sign in with a browser session to create a topic."
            return
        }
        let title = newTopicComposer.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = newTopicComposer.raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 2, raw.count >= 2, !newTopicComposer.isSubmitting else { return }
        newTopicComposer.isSubmitting = true
        newTopicComposer.error = nil
        do {
            let post = try await client.createTopic(title: title, raw: raw, categoryID: selectedCategoryID)
            newTopicComposer = LinuxDoComposerState()
            await refreshCurrentFeed()
            if let topicID = post.topicID {
                openTopic(id: topicID, slug: post.topicSlug)
            }
        } catch {
            newTopicComposer.isSubmitting = false
            newTopicComposer.error = userFacingMessage(error)
            handle(error)
        }
    }

    @discardableResult
    func openNotificationAndWait(_ notification: LinuxDoNotification) async -> Int? {
        guard let topicID = notification.topicID else { return nil }
        return await openTopicAndWait(id: topicID, slug: notification.slug, postNumber: notification.postNumber)
    }

    func loadTopic(id: Int, slug: String?, force: Bool) async {
        await loadEmojiCatalogIfNeeded()
        var state = topicStates[id] ?? LinuxDoTopicDetailState()
        if !force,
           let cached = cache.readTopic(id: id, ttl: 15 * 60, now: .now) {
            state.detail = sortedDetail(cached.detail)
            if let detail = state.detail {
                prewarmContentBlocks(for: detail.posts)
            }
            refreshPaginationState(&state)
            state.isStale = cached.isStale
            topicStates[id] = state
            if !cached.isStale { return }
        }

        state.isLoading = state.detail == nil
        state.error = nil
        topicStates[id] = state
        do {
            let detail = try await client.fetchTopic(id: id, slug: slug, now: .now)
            let sorted = sortedDetail(detail)
            state.detail = sorted
            prewarmContentBlocks(for: sorted.posts)
            refreshPaginationState(&state)
            state.isLoading = false
            state.isStale = false
            try? cache.writeTopic(sorted)
        } catch {
            state.isLoading = false
            state.error = userFacingMessage(error)
            handle(error)
        }
        topicStates[id] = state
    }

    func consumeScrollTarget(topicID: Int, postID: Int) {
        var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
        guard state.scrollTargetPostID == postID else { return }
        state.scrollTargetPostID = nil
        topicStates[topicID] = state
    }

    func loadMorePosts(topicID: Int) async {
        var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
        guard !state.isLoadingMore else { return }

        if let nextPage = state.nextPage {
            await loadMoreTopicPage(topicID: topicID, page: nextPage, state: state)
            return
        }

        guard !state.remainingPostIDs.isEmpty else { return }
        let batch = Array(state.remainingPostIDs.prefix(20))
        state.isLoadingMore = true
        state.error = nil
        topicStates[topicID] = state
        do {
            let posts = try await client.fetchPosts(topicID: topicID, postIDs: batch)
            state = topicStates[topicID] ?? state
            prewarmContentBlocks(for: posts)
            state.detail = mergedDetail(state.detail, adding: posts)
            refreshPaginationState(&state)
            state.isLoadingMore = false
            if posts.isEmpty {
                state.timelineWarning = "Linux.do did not return more posts for this batch."
                state.remainingPostIDs.removeAll { batch.contains($0) }
            }
            if let detail = state.detail {
                try? cache.writeTopic(detail)
            }
        } catch {
            state.isLoadingMore = false
            state.error = userFacingMessage(error)
            handle(error)
        }
        topicStates[topicID] = state
    }

    func loadReplies(topicID: Int, postID: Int) async {
        var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
        var replies = state.replyStates[postID] ?? LinuxDoPostRepliesState()
        guard !replies.isLoading else { return }
        replies.isLoading = true
        replies.error = nil
        state.replyStates[postID] = replies
        topicStates[topicID] = state

        do {
            let fetched = try await client.fetchPostReplies(postID: postID)
            state = topicStates[topicID] ?? state
            prewarmContentBlocks(for: fetched)
            if let detail = mergedDetail(state.detail, adding: fetched) {
                state.detail = detail
                refreshPaginationState(&state)
            }
            replies = state.replyStates[postID] ?? replies
            replies.replies = sortedPosts(uniquePosts(fetched), stream: [])
            replies.isLoading = false
            replies.hasLoaded = true
            replies.error = nil
            state.replyStates[postID] = replies
            if let detail = state.detail {
                try? cache.writeTopic(detail)
            }
        } catch {
            replies = state.replyStates[postID] ?? replies
            replies.isLoading = false
            replies.error = userFacingMessage(error)
            state.replyStates[postID] = replies
            handle(error)
        }
        topicStates[topicID] = state
    }

    private func loadMoreTopicPage(topicID: Int, page: Int, state initialState: LinuxDoTopicDetailState) async {
        guard let detail = initialState.detail else { return }
        var state = initialState
        state.isLoadingMore = true
        state.error = nil
        topicStates[topicID] = state
        do {
            let pageDetail = try await client.fetchTopicPage(id: topicID, slug: detail.slug, page: page, now: .now)
            state = topicStates[topicID] ?? state
            let knownIDs = state.loadedPostIDs
            let newPosts = pageDetail.posts.filter { !knownIDs.contains($0.id) }
            prewarmContentBlocks(for: newPosts)
            state.detail = mergedDetail(state.detail, adding: newPosts, stream: pageDetail.stream)
            refreshPaginationState(&state, currentPage: page, receivedNewPosts: !newPosts.isEmpty)
            state.isLoadingMore = false
            if newPosts.isEmpty {
                state.timelineWarning = "Linux.do did not return more posts for this page."
            }
            if let detail = state.detail {
                try? cache.writeTopic(detail)
            }
        } catch {
            state.isLoadingMore = false
            state.error = userFacingMessage(error)
            handle(error)
        }
        topicStates[topicID] = state
    }

    private func prewarmContentBlocks(for posts: [LinuxDoPost]) {
        for post in posts {
            _ = cachedContentBlocks(for: post)
        }
    }

    private func cachedContentBlocks(for post: LinuxDoPost) -> [LinuxDoContentBlock] {
        let key = LinuxDoPostContentCacheKey(post: post)
        if let blocks = contentBlockCache[key] {
            return blocks
        }
        let blocks = LinuxDoContentParser.blocks(from: post.cookedHTML)
        contentBlockCache[key] = blocks
        contentBlockCacheOrder.append(key)
        evictContentBlockCacheIfNeeded()
        return blocks
    }

    private func evictContentBlockCacheIfNeeded() {
        while contentBlockCacheOrder.count > contentBlockCacheLimit {
            let key = contentBlockCacheOrder.removeFirst()
            contentBlockCache.removeValue(forKey: key)
        }
    }

    @discardableResult
    func jumpToPostNumber(topicID: Int, postNumber: Int) async -> Int? {
        guard postNumber > 0 else { return nil }
        if var state = topicStates[topicID],
           let detail = state.detail,
           let loadedPost = detail.posts.first(where: { $0.postNumber == postNumber }) {
            state.timelineWarning = nil
            state.scrollTargetPostID = loadedPost.id
            topicStates[topicID] = state
            return loadedPost.id
        }
        return await jumpToPostIndex(topicID: topicID, index: postNumber - 1, preferredPostNumber: postNumber)
    }

    @discardableResult
    func jumpToPostIndex(topicID: Int, index: Int) async -> Int? {
        await jumpToPostIndex(topicID: topicID, index: index, preferredPostNumber: nil)
    }

    @discardableResult
    private func jumpToPostIndex(topicID: Int, index: Int, preferredPostNumber: Int?) async -> Int? {
        var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
        guard let detail = state.detail else { return nil }
        let stream = effectiveStream(for: detail)
        guard stream.indices.contains(index) else {
            state.timelineWarning = "That floor is outside this topic's post stream."
            topicStates[topicID] = state
            return nil
        }

        let targetID = stream[index]
        state.timelineWarning = nil
        if let preferredPostNumber,
           let loadedPost = detail.posts.first(where: { $0.postNumber == preferredPostNumber }) {
            state.scrollTargetPostID = loadedPost.id
            topicStates[topicID] = state
            return loadedPost.id
        }
        if preferredPostNumber == nil, state.loadedPostIDs.contains(targetID) {
            state.scrollTargetPostID = targetID
            topicStates[topicID] = state
            return targetID
        }

        let lowerBound = max(0, index - 10)
        let upperBound = min(stream.count, index + 11)
        let batch = Array(stream[lowerBound..<upperBound]).filter { !state.loadedPostIDs.contains($0) }
        guard !batch.isEmpty else {
            if let preferredPostNumber,
               let resolvedTargetID = state.detail?.posts.first(where: { $0.postNumber == preferredPostNumber })?.id {
                state.scrollTargetPostID = resolvedTargetID
            } else if preferredPostNumber == nil, state.loadedPostIDs.contains(targetID) {
                state.scrollTargetPostID = targetID
            } else {
                state.scrollTargetPostID = nil
                state.timelineWarning = "That floor could not be loaded from Linux.do."
            }
            topicStates[topicID] = state
            return state.scrollTargetPostID
        }

        state.isJumping = true
        state.isLoadingMore = true
        state.error = nil
        topicStates[topicID] = state

        do {
            let posts = try await client.fetchPosts(topicID: topicID, postIDs: batch)
            state = topicStates[topicID] ?? state
            state.detail = mergedDetail(state.detail, adding: posts)
            state.loadedPostIDs.formUnion(posts.map(\.id))
            state.remainingPostIDs.removeAll { state.loadedPostIDs.contains($0) }
            let resolvedTargetID: Int? = preferredPostNumber.flatMap { postNumber in
                state.detail?.posts.first { $0.postNumber == postNumber }?.id
            } ?? (state.loadedPostIDs.contains(targetID) ? targetID : nil)
            if let resolvedTargetID {
                state.scrollTargetPostID = resolvedTargetID
                state.timelineWarning = nil
            } else {
                state.scrollTargetPostID = nil
                state.timelineWarning = "That floor could not be loaded from Linux.do."
            }
            state.isJumping = false
            state.isLoadingMore = false
            if let detail = state.detail {
                try? cache.writeTopic(detail)
            }
        } catch {
            state.isJumping = false
            state.isLoadingMore = false
            state.timelineWarning = userFacingMessage(error)
            state.error = nil
            handle(error)
        }
        topicStates[topicID] = state
        if let preferredPostNumber,
           let resolvedTargetID = state.detail?.posts.first(where: { $0.postNumber == preferredPostNumber })?.id {
            return resolvedTargetID
        }
        return state.loadedPostIDs.contains(targetID) ? targetID : nil
    }

    func signInWithUserAPIKey(presentationAnchor: NSWindow?) async {
        guard let presentationAnchor else {
            lastError = "Open the main window before signing in to LinuxDo."
            return
        }
        isSigningIn = true
        lastError = nil
        do {
            _ = try await authService.login(presentationAnchor: presentationAnchor)
            refreshAuthenticationState()
            await loadCurrentUserIfNeeded(force: true)
            await refreshNotifications(announce: false)
        } catch LinuxDoAuthService.AuthError.cancelled {
            lastError = nil
        } catch {
            lastError = userFacingMessage(error)
        }
        refreshAuthenticationState()
        isSigningIn = false
    }

    @discardableResult
    func beginExternalBrowserSignIn() -> Bool {
        lastError = nil
        do {
            let url = try authService.beginExternalBrowserLogin()
            guard NSWorkspace.shared.open(url) else {
                authService.cancelExternalBrowserLogin()
                isAwaitingExternalBrowserSignIn = false
                lastError = "Could not open the LinuxDo authorization page in your default browser."
                return false
            }
            isAwaitingExternalBrowserSignIn = true
            Log.app.info("LinuxDo external browser authorization opened")
            return true
        } catch {
            isAwaitingExternalBrowserSignIn = false
            lastError = userFacingMessage(error)
            Log.app.error("LinuxDo external browser authorization failed to start: \(self.lastError ?? "unknown", privacy: .public)")
            return false
        }
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard LinuxDoAuthService.isCallbackURL(url) else { return false }
        Log.app.info("LinuxDo authorization callback received")
        Task { @MainActor in
            await completeExternalBrowserSignIn(callbackURL: url)
        }
        return true
    }

    func completeExternalBrowserSignIn(callbackURL: URL) async {
        isSigningIn = true
        lastError = nil
        do {
            _ = try authService.completeExternalBrowserLogin(callbackURL: callbackURL)
            credentials.deleteWebSession()
            refreshAuthenticationState()
            await loadCurrentUserIfNeeded(force: true)
            await refreshNotifications(announce: false)
            isAwaitingExternalBrowserSignIn = false
            Log.app.info("LinuxDo external browser authorization completed")
        } catch {
            isAwaitingExternalBrowserSignIn = false
            lastError = userFacingMessage(error)
            Log.app.error("LinuxDo external browser authorization failed: \(self.lastError ?? "unknown", privacy: .public)")
        }
        refreshAuthenticationState()
        isSigningIn = false
    }

    func signInWithWebSession(_ session: LinuxDoWebSession) async -> Bool {
        guard session.isAuthenticated else {
            lastError = "Linux.do login did not return a usable browser session yet."
            return false
        }

        isSigningIn = true
        lastError = nil
        credentials.deleteAPIKey()

        do {
            try credentials.saveWebSession(session)
            refreshAuthenticationState()
            let user = try await client.fetchCurrentUser()
            let csrfToken = try? await client.fetchCSRFToken()
            let enrichedSession = session.with(csrfToken: csrfToken, username: user.username, avatarURL: user.avatarURL)
            try credentials.saveWebSession(enrichedSession)
            refreshAuthenticationState()
            currentUser = user
            preferences.linuxDoLastLoginUsername = user.username
            Log.app.info("LinuxDo web session sign-in succeeded for @\(user.username, privacy: .public)")
            await refreshNotifications(announce: false)
            isSigningIn = false
            return true
        } catch {
            credentials.deleteWebSession()
            refreshAuthenticationState()
            currentUser = nil
            lastError = userFacingMessage(error)
            Log.app.error("LinuxDo web session sign-in failed: \(self.lastError ?? "unknown", privacy: .public)")
            isSigningIn = false
            return false
        }
    }

    func signOut() async {
        await client.revokeUserAPIKey()
        credentials.deleteAPIKey()
        credentials.deleteWebSession()
        preferences.linuxDoLastLoginUsername = ""
        preferences.linuxDoNotificationsEnabled = false
        preferences.linuxDoLastSeenNotificationID = 0
        preferences.linuxDoNotificationDeliveredIDs = []
        currentUser = nil
        notifications = []
        refreshAuthenticationState()
        stopNotificationPolling()
        Log.app.info("LinuxDo signed out")
    }

    func refreshAuthenticationState() {
        authenticationStatus = Self.authenticationStatus(from: credentials)
        if !authenticationStatus.isAuthenticated {
            currentUser = nil
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        guard enabled else {
            preferences.linuxDoNotificationsEnabled = false
            stopNotificationPolling()
            return
        }
        guard isAuthenticated else {
            lastError = "Sign in to LinuxDo before enabling notifications."
            preferences.linuxDoNotificationsEnabled = false
            return
        }
        notificationAuthorization = await notificationService.requestAuthorization()
        preferences.linuxDoNotificationsEnabled = notificationAuthorization.canSendNotifications
        if notificationAuthorization.canSendNotifications {
            await refreshNotifications(announce: false)
            startNotificationPolling()
        }
    }

    func refreshNotifications(announce: Bool = true) async {
        guard isAuthenticated else { return }
        isRefreshingNotifications = true
        defer { isRefreshingNotifications = false }
        do {
            let fresh = try await client.fetchNotifications(limit: 30)
            notifications = fresh
            if fresh.isEmpty { return }
            let maxID = fresh.map(\.id).max() ?? 0
            let lastSeen = preferences.linuxDoLastSeenNotificationID
            if lastSeen == 0 || !announce {
                preferences.linuxDoLastSeenNotificationID = max(maxID, lastSeen)
                return
            }
            var delivered = Set(preferences.linuxDoNotificationDeliveredIDs)
            for notification in fresh where notification.id > lastSeen && !delivered.contains(notification.id) && !notification.read {
                try? await notificationService.send(notification: notification)
                delivered.insert(notification.id)
            }
            preferences.linuxDoLastSeenNotificationID = max(maxID, lastSeen)
            preferences.linuxDoNotificationDeliveredIDs = Array(delivered.sorted().suffix(80))
        } catch {
            handle(error)
            Log.network.error("LinuxDo notification refresh failed: \(self.userFacingMessage(error), privacy: .public)")
        }
    }

    func clearCache() {
        do {
            try cache.clear()
            listStates.removeAll()
            topicStates.removeAll()
        } catch {
            lastError = "Could not clear LinuxDo cache."
        }
    }

    private func mergedDetail(_ detail: LinuxDoTopicDetail?, adding posts: [LinuxDoPost], stream: [Int] = []) -> LinuxDoTopicDetail? {
        guard var detail else { return nil }
        var byID = Dictionary(uniqueKeysWithValues: detail.posts.map { ($0.id, $0) })
        for post in posts {
            byID[post.id] = post
        }
        if !stream.isEmpty, Set(byID.keys).isSubset(of: Set(stream)) {
            detail.stream = stream
        }
        detail.posts = sortedPosts(Array(byID.values), stream: detail.stream)
        return detail
    }

    private func sortedDetail(_ detail: LinuxDoTopicDetail) -> LinuxDoTopicDetail {
        var copy = detail
        copy.posts = sortedPosts(copy.posts, stream: copy.stream)
        return copy
    }

    private func sortedPosts(_ posts: [LinuxDoPost], stream: [Int]) -> [LinuxDoPost] {
        let streamOrder = Dictionary(uniqueKeysWithValues: stream.enumerated().map { ($0.element, $0.offset) })
        return posts.sorted { lhs, rhs in
            let lhsOrder = streamOrder[lhs.id] ?? Int.max
            let rhsOrder = streamOrder[rhs.id] ?? Int.max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.postNumber < rhs.postNumber
        }
    }

    private func effectiveStream(for detail: LinuxDoTopicDetail) -> [Int] {
        if !detail.stream.isEmpty { return detail.stream }
        return detail.posts.sorted { $0.postNumber < $1.postNumber }.map(\.id)
    }

    private func totalFloors(for detail: LinuxDoTopicDetail) -> Int {
        max(detail.stream.count, detail.postsCount, detail.posts.count)
    }

    private func refreshPaginationState(
        _ state: inout LinuxDoTopicDetailState,
        currentPage: Int? = nil,
        receivedNewPosts: Bool = true
    ) {
        guard let detail = state.detail else {
            state.loadedPostIDs = []
            state.remainingPostIDs = []
            state.nextPage = nil
            return
        }

        state.loadedPostIDs = Set(detail.posts.map(\.id))
        state.remainingPostIDs = detail.stream.filter { !state.loadedPostIDs.contains($0) }
        guard state.remainingPostIDs.isEmpty,
              detail.postsCount > state.loadedPostIDs.count,
              receivedNewPosts else {
            state.nextPage = nil
            return
        }

        let streamOnlyCoversLoadedPosts = detail.stream.isEmpty || detail.stream.allSatisfy { state.loadedPostIDs.contains($0) }
        state.nextPage = streamOnlyCoversLoadedPosts ? (currentPage.map { $0 + 1 } ?? 2) : nil
    }

    private var hasWritableWebSession: Bool {
        if case .webSession = authenticationStatus {
            true
        } else {
            false
        }
    }

    private var selectedCategoryID: Int? {
        if case .category(let id, _, _) = selectedFeed {
            id
        } else {
            nil
        }
    }

    private func normalizedUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func post(withID postID: Int, in state: LinuxDoTopicDetailState) -> LinuxDoPost? {
        if let post = state.detail?.posts.first(where: { $0.id == postID }) {
            return post
        }
        for replies in state.replyStates.values {
            if let post = replies.replies.first(where: { $0.id == postID }) {
                return post
            }
        }
        return nil
    }

    private func replacePost(in state: inout LinuxDoTopicDetailState, with post: LinuxDoPost) {
        if var detail = state.detail {
            if let index = detail.posts.firstIndex(where: { $0.id == post.id }) {
                detail.posts[index] = post
            } else {
                detail.posts.append(post)
            }
            detail.posts = sortedPosts(uniquePosts(detail.posts), stream: detail.stream)
            state.detail = detail
            refreshPaginationState(&state)
        }

        for key in Array(state.replyStates.keys) {
            guard var replies = state.replyStates[key],
                  let index = replies.replies.firstIndex(where: { $0.id == post.id }) else {
                continue
            }
            replies.replies[index] = post
            replies.replies = sortedPosts(uniquePosts(replies.replies), stream: [])
            state.replyStates[key] = replies
        }
    }

    private func uniquePosts(_ posts: [LinuxDoPost]) -> [LinuxDoPost] {
        var byID: [Int: LinuxDoPost] = [:]
        for post in posts {
            byID[post.id] = post
        }
        return Array(byID.values)
    }

    private func optimisticallyLikedPost(_ post: LinuxDoPost, liked: Bool) -> LinuxDoPost {
        let current = post.likeActionSummary ?? LinuxDoPostActionSummary(
            id: 2,
            count: post.effectiveLikeCount,
            acted: false,
            canAct: post.canAct
        )
        let nextCount = max(0, current.count + (liked ? 1 : -1))
        let nextSummary = LinuxDoPostActionSummary(id: 2, count: nextCount, acted: liked, canAct: current.canAct)
        var summaries = post.actionsSummary.filter { $0.id != 2 }
        summaries.append(nextSummary)
        summaries.sort { $0.id < $1.id }
        return post.replacingForumState(likeCount: nextCount, actionsSummary: summaries)
    }

    private func optimisticallyReactedPost(_ post: LinuxDoPost, nextReaction: String?) -> LinuxDoPost {
        var reactions = post.visibleReactions
        if let current = post.currentUserReaction {
            reactions = adjusted(reactions: reactions, reactionID: current, delta: -1)
        }
        if let nextReaction {
            reactions = adjusted(reactions: reactions, reactionID: nextReaction, delta: 1)
        }
        return post.replacingForumState(
            reactions: reactions,
            currentUserReaction: nextReaction,
            clearsCurrentUserReaction: nextReaction == nil
        )
    }

    private func adjusted(reactions: [LinuxDoReaction], reactionID: String, delta: Int) -> [LinuxDoReaction] {
        var copy = reactions
        if let index = copy.firstIndex(where: { $0.id == reactionID }) {
            let nextCount = max(0, copy[index].count + delta)
            if nextCount == 0 {
                copy.remove(at: index)
            } else {
                copy[index] = LinuxDoReaction(id: reactionID, count: nextCount, users: copy[index].users)
            }
        } else if delta > 0 {
            copy.append(LinuxDoReaction(id: reactionID, count: delta, users: []))
        }
        return copy.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.id < rhs.id
        }
    }

    private func mergeReactions(existing: [LinuxDoReaction], fresh: [LinuxDoReaction]) -> [LinuxDoReaction] {
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for reaction in fresh {
            byID[reaction.id] = reaction
        }
        return byID.values.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.id < rhs.id
        }
    }

    private func setReplyError(topicID: Int, postID: Int, message: String) {
        var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
        var composer = state.replyComposers[postID] ?? LinuxDoComposerState()
        composer.error = message
        state.replyComposers[postID] = composer
        topicStates[topicID] = state
        lastError = message
    }

    private func setPostActionError(topicID: Int, postID: Int, message: String) {
        var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
        setPostActionError(topicID: topicID, postID: postID, message: message, state: &state)
        topicStates[topicID] = state
        lastError = message
    }

    private func setPostActionError(topicID: Int, postID: Int, message: String, state: inout LinuxDoTopicDetailState) {
        var replies = state.replyStates[postID] ?? LinuxDoPostRepliesState()
        replies.error = message
        state.replyStates[postID] = replies
    }

    private func clearPostActionError(topicID _: Int, postID: Int, state: inout LinuxDoTopicDetailState) {
        guard var replies = state.replyStates[postID] else { return }
        replies.error = nil
        state.replyStates[postID] = replies
    }

    private func loadEmojiCatalogIfNeeded() async {
        guard !hasAttemptedEmojiCatalogLoad, !isLoadingEmojiCatalog else { return }
        hasAttemptedEmojiCatalogLoad = true
        isLoadingEmojiCatalog = true
        defer { isLoadingEmojiCatalog = false }
        do {
            emojiURLsByID = try await client.fetchEmojiCatalog()
        } catch {
            Log.network.notice("LinuxDo emoji catalog load failed: \(self.userFacingMessage(error), privacy: .public)")
        }
    }

    private func fallbackEmojiURL(for reactionID: String) -> URL? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-")
        guard reactionID.rangeOfCharacter(from: allowed.inverted) == nil,
              let encoded = reactionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return LinuxDoURLResolver.url(from: "/images/emoji/twemoji/\(encoded).png?v=15")
    }

    private func loadCategoriesIfNeeded() async {
        if !categories.isEmpty { return }
        if let cached = cache.readCategories(ttl: 24 * 60 * 60, now: .now) {
            categories = cached.categories
            if !cached.isStale { return }
        }
        isLoadingCategories = true
        defer { isLoadingCategories = false }
        do {
            let fresh = try await client.fetchCategories()
            categories = fresh
            try? cache.writeCategories(fresh, now: .now)
        } catch {
            Log.network.error("LinuxDo categories load failed: \(self.userFacingMessage(error), privacy: .public)")
            handle(error)
        }
    }

    private func loadTopicList(feed: LinuxDoFeed, force: Bool) async {
        if let limited = rateLimitedUntil, limited > Date() {
            var state = listStates[feed.key] ?? LinuxDoListState()
            state.error = "Linux.do asked us to slow down. Try again \(Format.relativeDate(limited))."
            listStates[feed.key] = state
            return
        }
        var state = listStates[feed.key] ?? LinuxDoListState()
        if !force,
           let cached = cache.readTopicList(feed: feed, ttl: feed.cacheTTL, now: .now) {
            state.topics = cached.list.topics
            state.nextPage = cached.list.nextPage
            state.lastFetchedAt = cached.list.fetchedAt
            state.isStale = cached.isStale
            state.error = nil
            listStates[feed.key] = state
            if !cached.isStale { return }
        }

        state.isRefreshing = !state.topics.isEmpty
        state.isLoading = state.topics.isEmpty
        state.error = nil
        listStates[feed.key] = state
        do {
            let list = try await client.fetchTopicList(feed: feed, page: 0, now: .now)
            refreshAuthenticationState()
            state.topics = list.topics
            state.nextPage = list.nextPage
            state.lastFetchedAt = list.fetchedAt
            state.isStale = false
            state.isLoading = false
            state.isRefreshing = false
            try? cache.writeTopicList(list, feed: feed)
            if selectedTopicID == nil, let first = list.topics.first {
                selectTopic(first)
            }
        } catch {
            state.isLoading = false
            state.isRefreshing = false
            state.error = userFacingMessage(error)
            Log.network.error("LinuxDo feed load failed for \(feed.key, privacy: .public): \(state.error ?? "unknown", privacy: .public)")
            handle(error)
        }
        listStates[feed.key] = state
    }

    private func loadCurrentUserIfNeeded(force: Bool = false) async {
        guard isAuthenticated else { return }
        if currentUser != nil, !force { return }
        do {
            let user = try await client.fetchCurrentUser()
            currentUser = user
            preferences.linuxDoLastLoginUsername = user.username
            persistWebSessionMetadata(for: user)
        } catch {
            if let clientError = error as? LinuxDoClient.ClientError, clientError == .unauthorized {
                handle(error)
                return
            }
            if preferences.linuxDoLastLoginUsername.isEmpty {
                lastError = userFacingMessage(error)
            }
        }
    }

    private func persistWebSessionMetadata(for user: LinuxDoCurrentUser) {
        guard let session = credentials.readWebSession(), session.isAuthenticated else { return }
        let enrichedSession = session.with(csrfToken: nil, username: user.username, avatarURL: user.avatarURL)
        guard enrichedSession != session else { return }
        do {
            try credentials.saveWebSession(enrichedSession)
            refreshAuthenticationState()
        } catch {
            Log.app.notice("LinuxDo web session metadata save failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func startNotificationPolling() {
        guard preferences.linuxDoNotificationsEnabled, notificationTask == nil else { return }
        notificationTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNotifications(announce: true)
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    private func stopNotificationPolling() {
        notificationTask?.cancel()
        notificationTask = nil
    }

    private func handle(_ error: Error) {
        if let clientError = error as? LinuxDoClient.ClientError {
            switch clientError {
            case .unauthorized:
                credentials.deleteAPIKey()
                credentials.deleteWebSession()
                refreshAuthenticationState()
                currentUser = nil
                preferences.linuxDoNotificationsEnabled = false
                stopNotificationPolling()
            case .rateLimited(let retryAfter):
                rateLimitedUntil = retryAfter ?? Date().addingTimeInterval(120)
            default:
                break
            }
        }
        lastError = userFacingMessage(error)
    }

    private func userFacingMessage(_ error: Error) -> String {
        if let clientError = error as? LinuxDoClient.ClientError {
            return clientError.description
        }
        if let authError = error as? LinuxDoAuthService.AuthError {
            return authError.description
        }
        return error.localizedDescription
    }

    private static func authenticationStatus(from credentials: any LinuxDoCredentialStoring) -> LinuxDoAuthenticationStatus {
        if credentials.readAPIKey() != nil {
            return .userAPIKey
        }
        if let session = credentials.readWebSession(), session.isAuthenticated {
            return .webSession(username: session.username, avatarURL: session.avatarURL)
        }
        return .guest
    }
}
