import AppKit
import Foundation
import Testing
@testable import ClaudeStats

@Suite("LinuxDo")
@MainActor
struct LinuxDoTests {
    @Test("Feed storage round-trips stable routes")
    func feedStorageRoundTrips() {
        let feeds: [LinuxDoFeed] = [
            .latest,
            .hot,
            .top(.monthly),
            .category(id: 7, name: "General", slug: "general"),
            .search("swift native"),
        ]

        for feed in feeds {
            #expect(LinuxDoFeed.stored(feed.storedValue) == feed)
        }
    }

    @Test("Category response decodes Discourse icon names")
    func categoryResponseDecodesIconNames() throws {
        let data = Data(Self.categoriesJSON.utf8)
        let response = try JSONDecoder().decode(CategoriesResponse.self, from: data)

        #expect(response.categories.count == 2)
        #expect(response.categories[0].name == "开发调优")
        #expect(response.categories[0].iconName == "code")
        #expect(response.categories[1].name == "运营反馈")
        #expect(response.categories[1].iconName == "comments")
    }

    @Test("Category sidebar icons are semantic and unique")
    func categorySidebarIconsAreSemanticAndUnique() {
        let categories = Self.knownLinuxDoCategories
        let symbols = categories.map { LinuxDoCategoryIcon.symbolName(for: $0) }

        #expect(Set(symbols).count == categories.count)
        #expect(symbols[categories.firstIndex { $0.slug == "resource" }!] == "point.3.connected.trianglepath.dotted")
        #expect(symbols[categories.firstIndex { $0.slug == "wiki" }!] == "doc.richtext.fill")
        #expect(symbols[categories.firstIndex { $0.slug == "reading" }!] == "book.closed.fill")
        #expect(symbols[categories.firstIndex { $0.slug == "square" }!] == "hurricane")

        for symbol in symbols {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
        }
    }

    @Test("Cooked HTML is reduced to ordered native blocks")
    func cookedHTMLBlocks() throws {
        let blocks = LinuxDoContentParser.blocks(from: """
        <p>Hello &amp; welcome</p>
        <blockquote>Keep it native</blockquote>
        <pre><code>if true {
            print(&quot;hi&quot;)
        }</code></pre>
        <ul><li>One</li><li>Two</li></ul>
        <img src="/uploads/test.png">
        """)

        #expect(blocks.count == 5)
        #expect(Self.plainText(blocks[0]) == "Hello & welcome")
        if case .quote(attribution: _, blocks: let quoteBlocks) = blocks[1].kind {
            #expect(Self.plainText(quoteBlocks.first) == "Keep it native")
        } else {
            Issue.record("Expected a quote block")
        }
        if case .codeBlock(_, let code) = blocks[2].kind {
            #expect(code.contains("print(\"hi\")"))
            #expect(code.contains("    "))
        } else {
            Issue.record("Expected a code block")
        }
        if case .list(false, let items) = blocks[3].kind {
            #expect(items.map { Self.plainText($0.blocks.first) } == ["One", "Two"])
        } else {
            Issue.record("Expected an unordered list")
        }
        if case .image(let url, _, _, _, _) = blocks[4].kind {
            #expect(url == URL(string: "https://linux.do/uploads/test.png")!)
        } else {
            Issue.record("Expected an image block")
        }
    }

    @Test("Paragraph-wrapped post images become native image blocks")
    func paragraphWrappedImagesBecomeBlocks() {
        let blocks = LinuxDoContentParser.blocks(from: """
        <p>Before <img class="emoji" src="/emoji/apple/wave.png" alt=":wave:"> after</p>
        <p><img src="/uploads/direct.png" alt="Direct"></p>
        <p><a href="/uploads/original.png"><img src="/uploads/thumb.png" alt="Linked"></a></p>
        """)

        #expect(blocks.count == 3)
        #expect(Self.plainText(blocks[0]) == "Before :wave: after")
        if case .image(let url, let alt, _, _, let linkURL) = blocks[1].kind {
            #expect(url == URL(string: "https://linux.do/uploads/direct.png")!)
            #expect(alt == "Direct")
            #expect(linkURL == nil)
        } else {
            Issue.record("Expected a direct image block")
        }
        if case .image(let url, let alt, _, _, let linkURL) = blocks[2].kind {
            #expect(url == URL(string: "https://linux.do/uploads/thumb.png")!)
            #expect(alt == "Linked")
            #expect(linkURL == URL(string: "https://linux.do/uploads/original.png")!)
        } else {
            Issue.record("Expected a linked image block")
        }
    }

    @Test("Store caches parsed post blocks and invalidates when post content changes")
    func storeCachesParsedPostBlocks() {
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore()
        )
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        let post = Self.post(
            id: 100,
            topicID: 1,
            postNumber: 1,
            cookedHTML: "<p>First</p>",
            updatedAt: updatedAt
        )

        let first = store.contentBlocks(for: post)
        let second = store.contentBlocks(for: post)

        #expect(first == second)
        #expect(Self.plainText(first.first) == "First")

        let changedHTML = Self.post(
            id: 100,
            topicID: 1,
            postNumber: 1,
            cookedHTML: "<p>Second</p>",
            updatedAt: updatedAt
        )
        let changedHTMLBlocks = store.contentBlocks(for: changedHTML)
        #expect(Self.plainText(changedHTMLBlocks.first) == "Second")

        let changedUpdatedAt = Self.post(
            id: 100,
            topicID: 1,
            postNumber: 1,
            cookedHTML: "<p>Third</p>",
            updatedAt: updatedAt.addingTimeInterval(1)
        )
        let changedUpdatedAtBlocks = store.contentBlocks(for: changedUpdatedAt)
        #expect(Self.plainText(changedUpdatedAtBlocks.first) == "Third")
    }

    @Test("Cooked HTML preserves rich Discourse shapes")
    func cookedHTMLRichDiscourseShapes() throws {
        let blocks = LinuxDoContentParser.blocks(from: """
        <p><a class="mention" href="/u/alice">@alice</a> see <a href="/t/dexo/42">Dexo</a> <span class="spoiler">hidden</span> <a class="hashtag-cooked" href="/tag/swift">#swift</a></p>
        <details><summary>More</summary><p>Inside</p></details>
        <table><thead><tr><th>Name</th><th>Link</th></tr></thead><tbody><tr><td>Dexo</td><td><a href="/t/dexo/42">Topic</a></td></tr></tbody></table>
        <aside class="onebox"><header><a href="https://github.com/Eilgnaw/dexo">Dexo</a></header><p>Native client</p></aside>
        """)

        #expect(blocks.count == 4)
        if case .paragraph(let nodes) = blocks[0].kind {
            #expect(nodes.contains(.mention(username: "alice", url: URL(string: "https://linux.do/u/alice")!)))
            #expect(nodes.contains(.hashtag(text: "#swift", url: URL(string: "https://linux.do/tag/swift")!)))
            #expect(Self.plainText(nodes).contains("hidden"))
            guard case .some(.link(let url, _)) = nodes.first(where: {
                if case .link = $0 { return true }
                return false
            }) else {
                Issue.record("Expected a link node")
                return
            }
            #expect(url == URL(string: "https://linux.do/t/dexo/42")!)
        } else {
            Issue.record("Expected a rich paragraph")
        }

        if case .details(let summary, let childBlocks) = blocks[1].kind {
            #expect(Self.plainText(summary) == "More")
            #expect(Self.plainText(childBlocks.first) == "Inside")
        } else {
            Issue.record("Expected details block")
        }

        if case .table(let headers, let rows) = blocks[2].kind {
            #expect(headers.count == 2)
            #expect(Self.plainText(headers[0].blocks.first) == "Name")
            #expect(Self.plainText(headers[1].blocks.first) == "Link")
            #expect(rows.first?.cells.count == 2)
            #expect(Self.plainText(rows.first?.cells[1].blocks.first) == "Topic")
        } else {
            Issue.record("Expected table block")
        }

        if case .onebox(let onebox) = blocks[3].kind {
            #expect(onebox.title == "Dexo")
            #expect(onebox.description == "Native client")
            #expect(onebox.url == URL(string: "https://github.com/Eilgnaw/dexo")!)
        } else {
            Issue.record("Expected onebox block")
        }
    }

    @Test("Discourse quote aside keeps title chrome out of quote body")
    func discourseQuoteAsideParsesAttribution() throws {
        let blocks = LinuxDoContentParser.blocks(from: """
        <aside class="quote no-group" data-username="neo" data-post="1" data-topic="662077">
          <div class="title">
            <div class="quote-controls">ignored</div>
            <img alt="" width="24" height="24" src="https://linux.do/user_avatar/linux.do/neo/48/12_2.png" class="avatar"> Neo:
          </div>
          <blockquote><p><strong>Quoted</strong> body</p></blockquote>
        </aside>
        """)

        #expect(blocks.count == 1)
        guard case .quote(let attribution, let quoteBlocks) = blocks[0].kind else {
            Issue.record("Expected quote")
            return
        }
        #expect(attribution?.username == "neo")
        #expect(attribution?.displayName == "Neo")
        #expect(attribution?.avatarURL == URL(string: "https://linux.do/user_avatar/linux.do/neo/48/12_2.png")!)
        #expect(attribution?.postNumber == 1)
        #expect(attribution?.postURL == URL(string: "https://linux.do/t/topic/662077/1")!)
        #expect(Self.plainText(quoteBlocks.first) == "Quoted body")
        #expect(!Self.containsImage(quoteBlocks))
        #expect(!quoteBlocks.contains { Self.plainText($0).contains("ignored") })
    }

    @Test("Cooked HTML callouts support alert divs and markdown markers")
    func cookedHTMLCallouts() throws {
        let blocks = LinuxDoContentParser.blocks(from: """
        <div class="alert alert-danger"><p><strong>Danger</strong></p><p>请自己写回帖内容</p></div>
        <blockquote><p>[!DANGER]</p><p>Marker body</p></blockquote>
        """)

        #expect(blocks.count == 2)
        guard case .callout(let alert) = blocks[0].kind else {
            Issue.record("Expected alert callout")
            return
        }
        #expect(alert.style == .danger)
        #expect(alert.title == "Danger")
        #expect(Self.plainText(alert.blocks.first) == "请自己写回帖内容")

        guard case .callout(let marker) = blocks[1].kind else {
            Issue.record("Expected marker callout")
            return
        }
        #expect(marker.style == .danger)
        #expect(marker.title == "Danger")
        #expect(Self.plainText(marker.blocks.first) == "Marker body")
    }

    @Test("Cooked HTML preserves event, task list, inline markdown, and empty anchors")
    func cookedHTMLMarkdownExtensions() throws {
        let blocks = LinuxDoContentParser.blocks(from: """
        <div class="discourse-post-event" data-start="2025-05-20 12:10" data-end="2025-05-27 12:10" data-timezone="Asia/Shanghai" data-status="public" data-name="社区文化宣导周"></div>
        <ul class="task-list"><li><input type="checkbox" checked> Done <kbd>Cmd K</kbd> <mark>marked</mark> H<sub>2</sub>O<sup>2</sup></li></ul>
        <h2><a name="p-1-title" class="anchor" href="#p-1-title" aria-label="标题链接"></a>Title</h2>
        """)

        #expect(blocks.count == 3)
        guard case .event(let event) = blocks[0].kind else {
            Issue.record("Expected event")
            return
        }
        #expect(event.name == "社区文化宣导周")
        #expect(event.startsAt == "2025-05-20 12:10")
        #expect(event.endsAt == "2025-05-27 12:10")
        #expect(event.timezone == "Asia/Shanghai")
        #expect(event.status == "public")

        guard case .list(false, let items) = blocks[1].kind, let item = items.first else {
            Issue.record("Expected task list")
            return
        }
        #expect(item.taskState == .checked)
        #expect(Self.plainText(item.blocks.first) == "Done Cmd K marked H2O2")
        guard case .paragraph(let nodes) = item.blocks.first?.kind else {
            Issue.record("Expected task paragraph")
            return
        }
        #expect(nodes.contains { if case .keyboard = $0 { return true }; return false })
        #expect(nodes.contains { if case .highlight = $0 { return true }; return false })
        #expect(nodes.contains { if case .subscript = $0 { return true }; return false })
        #expect(nodes.contains { if case .superscript = $0 { return true }; return false })

        #expect(Self.plainText(blocks[2]) == "Title")
    }

    @Test("Post response optional Discourse metadata decodes without breaking older shapes")
    func postResponseMetadataDecode() throws {
        let rich = try JSONDecoder().decode(PostResponse.self, from: Data("""
        {
          "id": 10,
          "topic_id": 3,
          "post_number": 2,
          "reply_to_post_number": 1,
          "username": "alice",
          "cooked": "<p>Hello</p>",
          "reads": 12,
          "score": 3.5,
          "actions_summary": [
            { "id": 2, "count": 8, "acted": true, "ignored": "ok" }
          ]
        }
        """.utf8)).model

        #expect(rich.replyToPostNumber == 1)
        #expect(rich.reads == 12)
        #expect(rich.score == 3.5)
        #expect(rich.actionsSummary == [LinuxDoPostActionSummary(id: 2, count: 8, acted: true)])

        let old = try JSONDecoder().decode(PostResponse.self, from: Data("""
        { "id": 11, "post_number": 1, "username": "bob", "cooked": "<p>Old</p>" }
        """.utf8)).model

        #expect(old.replyToPostNumber == nil)
        #expect(old.reads == 0)
        #expect(old.score == nil)
        #expect(old.actionsSummary.isEmpty)
    }

    @Test("Post response decodes reactions and falls back to action summary likes")
    func postResponseReactionsDecode() throws {
        let post = try JSONDecoder().decode(PostResponse.self, from: Data("""
        {
          "id": 12,
          "topic_id": 3,
          "topic_slug": "hello",
          "post_number": 1,
          "username": "alice",
          "display_username": "Alice",
          "cooked": "<p>Hello</p>",
          "actions_summary": [
            { "id": 2, "count": 7, "acted": true, "can_act": true }
          ],
          "reactions": [
            {
              "id": "heart",
              "count": 7,
              "users": [
                { "username": "bob", "avatar_template": "/user_avatar/linux.do/bob/{size}/1.png", "can_undo": false }
              ]
            },
            { "reaction_value": "clap", "reaction_users_count": 3 }
          ],
          "current_user_reaction": { "id": "heart" },
          "can_reply": true,
          "post_url": "/t/hello/3/1"
        }
        """.utf8)).model

        #expect(post.topicSlug == "hello")
        #expect(post.displayAuthorName == "Alice")
        #expect(post.effectiveLikeCount == 7)
        #expect(post.isLikedByCurrentUser)
        #expect(post.canToggleLike)
        #expect(post.visibleReactions.map(\.id) == ["heart", "clap"])
        #expect(post.visibleReactions.first?.users.first?.avatarURL?.absoluteString == "https://linux.do/user_avatar/linux.do/bob/96/1.png")
        #expect(post.postURL?.absoluteString == "https://linux.do/t/hello/3/1")
    }

    @Test("User profile response decodes Discourse profile stats badges and groups")
    func userProfileResponseDecode() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeLinuxDoDate)
        let response = try decoder.decode(UserProfileResponse.self, from: Data(Self.userProfileRichJSON.utf8))
        let profile = LinuxDoResponseMapper.userProfile(from: response)

        #expect(profile.id == 1)
        #expect(profile.username == "tester")
        #expect(profile.displayName == "Tester")
        #expect(profile.avatarURL?.absoluteString == "https://linux.do/user_avatar/linux.do/tester/96/1.png")
        #expect(profile.title == "Builder")
        #expect(profile.plainBioExcerpt == "Native reader")
        #expect(profile.website == "example.com")
        #expect(profile.location == "Xi'an")
        #expect(profile.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(profile.lastSeenAt == Date(timeIntervalSince1970: 1_700_003_600))
        #expect(profile.trustLevel == 3)
        #expect(profile.isModerator)
        #expect(!profile.isAdmin)
        #expect(profile.primaryGroupName == "linux-do")
        #expect(profile.flairName == "Guide")
        #expect(profile.flairURL?.absoluteString == "https://linux.do/images/flair.png")
        #expect(profile.stats.postCount == 42)
        #expect(profile.stats.topicCount == 7)
        #expect(profile.stats.likesReceived == 99)
        #expect(profile.stats.likesGiven == 12)
        #expect(profile.stats.solutionsCount == 5)
        #expect(profile.stats.profileViewCount == 1_234)
        #expect(profile.stats.readTimeSeconds == 3_600)
        #expect(profile.groups.map(\.name) == ["seed-users", "linux-do"])
        #expect(profile.badges.map(\.name) == ["Great Share"])
        #expect(profile.badges.first?.grantedAt == Date(timeIntervalSince1970: 1_700_000_100))

        let minimal = try decoder.decode(UserProfileResponse.self, from: Data("""
        {
          "user": {
            "id": 2,
            "username": "minimal",
            "ignored_shape": { "ok": true }
          }
        }
        """.utf8))
        let minimalProfile = LinuxDoResponseMapper.userProfile(from: minimal)
        #expect(minimalProfile.username == "minimal")
        #expect(minimalProfile.badges.isEmpty)
        #expect(minimalProfile.groups.isEmpty)
    }

    @Test("Emoji catalog response decodes dynamic Discourse groups")
    func emojiCatalogResponseDecode() throws {
        let response = try JSONDecoder().decode(EmojiCatalogResponse.self, from: Data("""
        {
          "smileys_&_emotion": [
            { "name": "distorted_face", "url": "/images/emoji/twemoji/distorted_face.png?v=15" }
          ],
          "custom": [
            { "name": "bili_057", "url": "//linuxdo-uploads.s3.linux.do/original/4X/b/i/l/bili_057.png" }
          ]
        }
        """.utf8))
        let urls = LinuxDoResponseMapper.emojiURLs(from: response)

        #expect(urls["distorted_face"]?.absoluteString == "https://linux.do/images/emoji/twemoji/distorted_face.png?v=15")
        #expect(urls["bili_057"]?.absoluteString == "https://linuxdo-uploads.s3.linux.do/original/4X/b/i/l/bili_057.png")
    }

    @Test("LinuxDo topic URLs map to native topic routes")
    func topicRouteParsesLinuxDoURLs() throws {
        let routed = try #require(LinuxDoTopicRoute(url: URL(string: "https://linux.do/t/dexo/42/7")!))
        #expect(routed.id == 42)
        #expect(routed.slug == "dexo")
        #expect(routed.postNumber == 7)

        let compact = try #require(LinuxDoTopicRoute(url: URL(string: "https://linux.do/t/42/3")!))
        #expect(compact.id == 42)
        #expect(compact.slug == nil)
        #expect(compact.postNumber == 3)

        #expect(LinuxDoTopicRoute(url: URL(string: "https://example.com/t/dexo/42")!) == nil)
    }

    @Test("Discourse topic list fixture decodes to app models")
    func topicListFixtureDecode() throws {
        let json = """
        {
          "topic_list": {
            "more_topics_url": "/latest.json?page=1",
            "topics": [
              {
                "id": 42,
                "title": "Hello &amp; Linux",
                "fancy_title": null,
                "slug": "hello-linux",
                "category_id": 1,
                "tags": [{"id": 1, "name": "mac", "slug": "mac-tag"}],
                "excerpt": "<p>Native &amp; fast</p>",
                "posts_count": 3,
                "reply_count": 2,
                "views": 10,
                "like_count": 4,
                "image_url": "/uploads/default/original/1X/image.png"
              }
            ]
          }
        }
        """

        let response = try JSONDecoder().decode(TopicListResponse.self, from: Data(json.utf8))
        let list = LinuxDoResponseMapper.topicList(from: response, page: 0, now: Date(timeIntervalSince1970: 100))
        let topic = try #require(list.topics.first)

        #expect(list.nextPage == 1)
        #expect(topic.displayTitle == "Hello & Linux")
        #expect(topic.tags == ["mac"])
        #expect(topic.displayExcerpt == "Native & fast")
        #expect(topic.imageURL?.absoluteString == "https://linux.do/uploads/default/original/1X/image.png")
    }

    @Test("Topic tags decode from string object and empty shapes")
    func tagShapesDecode() throws {
        let json = """
        {
          "topic_list": {
            "topics": [
              { "id": 1, "title": "String tags", "slug": "one", "tags": ["swift"] },
              { "id": 2, "title": "Object tags", "slug": "two", "tags": [{"id": 2, "name": "macOS", "slug": "macos"}] },
              { "id": 3, "title": "Empty tags", "slug": "three", "tags": [] }
            ]
          }
        }
        """

        let response = try JSONDecoder().decode(TopicListResponse.self, from: Data(json.utf8))
        let topics = LinuxDoResponseMapper.topicList(from: response, page: 0, now: Date()).topics

        #expect(topics.map(\.tags) == [["swift"], ["macOS"], []])
    }

    @Test("Linux.do guest topic list shape decodes")
    func linuxDoGuestShapeDecode() throws {
        let json = """
        {
          "users": [],
          "topic_list": {
            "more_topics_url": "/hot.json?page=1",
            "topics": [
              {
                "fancy_title": "Hot &amp; Native",
                "id": 2213371,
                "title": "Hot Native",
                "slug": "topic",
                "posts_count": 47,
                "reply_count": 24,
                "image_url": "https://cdn3.ldstatic.com/original/example.png",
                "created_at": "2026-05-20T09:09:14.607Z",
                "last_posted_at": "2026-05-20T14:33:33.809Z",
                "bumped_at": "2026-05-20T14:33:33.809Z",
                "tags": [{"id": 1461, "name": "纯水", "slug": "1461-tag"}],
                "views": 1297,
                "like_count": 70,
                "category_id": 42
              }
            ]
          }
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeLinuxDoDate)
        let response = try decoder.decode(TopicListResponse.self, from: Data(json.utf8))
        let list = LinuxDoResponseMapper.topicList(from: response, page: 0, now: Date())
        let topic = try #require(list.topics.first)

        #expect(list.nextPage == 1)
        #expect(topic.displayTitle == "Hot & Native")
        #expect(topic.tags == ["纯水"])
    }

    @Test("Cache distinguishes fresh and stale list entries")
    func cacheFreshAndStale() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = LinuxDoCache(rootURL: root)
        let list = LinuxDoTopicList(
            topics: [Self.topic(id: 1, title: "Cached")],
            page: 0,
            nextPage: 1,
            fetchedAt: Date(timeIntervalSince1970: 10)
        )

        try cache.writeTopicList(list, feed: .latest)

        let fresh = try #require(cache.readTopicList(feed: .latest, ttl: 100, now: Date()))
        #expect(fresh.list.topics.first?.title == "Cached")
        #expect(fresh.isStale == false)

        let stale = try #require(cache.readTopicList(feed: .latest, ttl: 5, now: Date().addingTimeInterval(10)))
        #expect(stale.isStale == true)
    }

    @Test("In-memory credential store covers save read and logout")
    func credentialStoreRoundTrip() {
        let store = InMemoryLinuxDoCredentialStore()

        #expect(store.readAuthCredential() == nil)

        store.saveWebSession(Self.webSession(username: "tester"))

        #expect(store.readWebSession()?.username == "tester")
        #expect(store.readAuthCredential() == .webSession(Self.webSession(username: "tester")))

        store.deleteWebSession()
        #expect(store.readAuthCredential() == nil)
    }

    @Test("Store uses fresh cache without touching network")
    func storeUsesFreshCache() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = LinuxDoCache(rootURL: root)
        let cached = LinuxDoTopicList(
            topics: [Self.topic(id: 2, title: "From Cache")],
            page: 0,
            nextPage: nil,
            fetchedAt: Date()
        )
        try cache.writeTopicList(cached, feed: .latest)

        let client = FakeLinuxDoClient(topicList: LinuxDoTopicList(
            topics: [Self.topic(id: 3, title: "From Network")],
            page: 0,
            nextPage: nil,
            fetchedAt: Date()
        ))
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(),
            cache: cache,
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        await store.loadCurrentFeedIfNeeded()

        #expect(store.currentListState.topics.first?.title == "From Cache")
        #expect(client.fetchTopicListCalls == 0)
    }

    @Test("Notification sync skips history and delivers each new unread id once")
    func notificationsHighWaterMark() async {
        let preferences = Self.makePreferences()
        let credentials = InMemoryLinuxDoCredentialStore(webSession: Self.webSession(username: "tester"))
        let client = FakeLinuxDoClient(notifications: [Self.notification(id: 10)])
        let notificationService = FakeLinuxDoNotificationService()
        let store = LinuxDoStore(
            preferences: preferences,
            credentials: credentials,
            notificationService: notificationService,
            client: client
        )

        await store.refreshNotifications(announce: true)
        #expect(notificationService.sentIDs == [])
        #expect(preferences.linuxDoLastSeenNotificationID == 10)

        client.notifications = [Self.notification(id: 11), Self.notification(id: 10)]
        await store.refreshNotifications(announce: true)
        await store.refreshNotifications(announce: true)

        #expect(notificationService.sentIDs == [11])
        #expect(preferences.linuxDoLastSeenNotificationID == 11)
        #expect(preferences.linuxDoNotificationDeliveredIDs == [11])
    }

    @Test("Reading positions persist as JSON and trim to recent topics")
    func readingPositionsPersistAndTrim() {
        let suiteName = "ClaudeStatsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = Preferences(defaults: defaults)
        let base = Date(timeIntervalSince1970: 1_000)

        preferences.linuxDoReadingPositions = Dictionary(
            uniqueKeysWithValues: (0..<205).map { index in
                (
                    index,
                    LinuxDoReadingPosition(
                        topicID: index,
                        postID: 10_000 + index,
                        postNumber: index + 1,
                        updatedAt: base.addingTimeInterval(TimeInterval(index))
                    )
                )
            }
        )

        #expect(preferences.linuxDoReadingPositions.count == 200)
        #expect(preferences.linuxDoReadingPositions[0] == nil)
        #expect(preferences.linuxDoReadingPositions[204]?.postNumber == 205)

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.linuxDoReadingPositions == preferences.linuxDoReadingPositions)
    }

    @Test("Reading position only advances to the furthest floor")
    func readingPositionOnlyAdvances() {
        let preferences = Self.makePreferences()
        let store = LinuxDoStore(
            preferences: preferences,
            credentials: InMemoryLinuxDoCredentialStore(),
            notificationService: FakeLinuxDoNotificationService(),
            client: FakeLinuxDoClient()
        )

        store.recordReadingPosition(topicID: 77, postID: 700, postNumber: 7)
        store.recordReadingPosition(topicID: 77, postID: 500, postNumber: 5)
        store.recordReadingPosition(topicID: 77, postID: 900, postNumber: 9)
        store.recordReadingPosition(topicID: 77, postID: 901, postNumber: 9)

        #expect(store.readingPosition(for: 77)?.postID == 900)
        #expect(store.readingPosition(for: 77)?.postNumber == 9)
        #expect(preferences.linuxDoReadingPositions[77]?.postNumber == 9)
    }

    @Test("Continue reading uses the existing jump path")
    func continueReadingUsesJumpPath() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let preferences = Self.makePreferences()
        preferences.linuxDoReadingPositions = [
            21: LinuxDoReadingPosition(
                topicID: 21,
                postID: 802,
                postNumber: 3,
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
        ]
        let detail = Self.detail(
            id: 21,
            postsCount: 4,
            stream: [800, 801, 802, 803],
            posts: [Self.post(id: 800, topicID: 21, postNumber: 1)]
        )
        let client = FakeLinuxDoClient(
            topicDetail: detail,
            postsByID: [802: Self.post(id: 802, topicID: 21, postNumber: 3)]
        )
        let store = LinuxDoStore(
            preferences: preferences,
            credentials: InMemoryLinuxDoCredentialStore(),
            cache: LinuxDoCache(rootURL: root),
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        await store.loadTopic(id: 21, slug: "continue", force: true)
        let target = await store.continueReading(topicID: 21)
        let state = try #require(store.topicStates[21])

        #expect(target == 802)
        #expect(state.scrollTargetPostID == 802)
        #expect(client.fetchPostsBatches == [[801, 802, 803]])
    }

    @Test("Continue reading ignores positions outside the current topic")
    func continueReadingIgnoresOutOfRangePosition() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let preferences = Self.makePreferences()
        preferences.linuxDoReadingPositions = [
            22: LinuxDoReadingPosition(
                topicID: 22,
                postID: 999,
                postNumber: 99,
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
        ]
        let client = FakeLinuxDoClient(
            topicDetail: Self.detail(
                id: 22,
                postsCount: 3,
                stream: [900, 901, 902],
                posts: [Self.post(id: 900, topicID: 22, postNumber: 1)]
            )
        )
        let store = LinuxDoStore(
            preferences: preferences,
            credentials: InMemoryLinuxDoCredentialStore(),
            cache: LinuxDoCache(rootURL: root),
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        await store.loadTopic(id: 22, slug: "short", force: true)
        let target = await store.continueReading(topicID: 22)

        #expect(target == nil)
        #expect(client.fetchPostsBatches.isEmpty)
    }

    @Test("Reading navigator math clamps floors and samples long streams")
    func readingNavigatorMath() {
        #expect(LinuxDoReadingNavigatorLayout.mode(width: 700, totalFloors: 10) == .rail)
        #expect(LinuxDoReadingNavigatorLayout.mode(width: 640, totalFloors: 10) == .compact)
        #expect(LinuxDoReadingNavigatorLayout.mode(width: 500, totalFloors: 10) == .compact)
        #expect(LinuxDoReadingNavigatorLayout.mode(width: 900, totalFloors: 9) == .hidden)
        #expect(LinuxDoReadingNavigatorLayout.railTrackHeight == 220)

        let y = LinuxDoReadingNavigatorLayout.positionY(for: 6, totalFloors: 11, height: 100)
        #expect(abs(y - 50) < 0.001)
        #expect(LinuxDoReadingNavigatorLayout.floor(at: 50, totalFloors: 11, height: 100) == 6)
        #expect(LinuxDoReadingNavigatorLayout.floor(at: -20, totalFloors: 11, height: 100) == 1)
        #expect(LinuxDoReadingNavigatorLayout.floor(at: 200, totalFloors: 11, height: 100) == 11)
        #expect(LinuxDoReadingNavigatorLayout.floor(at: 50, totalFloors: 1, height: 100) == 1)

        let sampled = LinuxDoReadingNavigatorLayout.sampledFloors(Array(1...250), totalFloors: 250)
        #expect(sampled.count <= 60)
        #expect(sampled.first == 1)
        #expect(sampled.last == 250)
    }

    @Test("Reading navigator mode uses hysteresis while resizing")
    func readingNavigatorModeHysteresis() {
        #expect(LinuxDoReadingNavigatorLayout.mode(width: 900, totalFloors: 9, currentMode: .rail) == .hidden)
        #expect(LinuxDoReadingNavigatorLayout.mode(width: 660, totalFloors: 10, currentMode: .compact) == .rail)
        #expect(LinuxDoReadingNavigatorLayout.mode(width: 640, totalFloors: 10, currentMode: .rail) == .rail)
        #expect(LinuxDoReadingNavigatorLayout.mode(width: 640, totalFloors: 10, currentMode: .compact) == .compact)
        #expect(LinuxDoReadingNavigatorLayout.mode(width: 579, totalFloors: 10, currentMode: .rail) == .compact)
        #expect(LinuxDoReadingNavigatorLayout.mode(width: 700, totalFloors: 10, currentMode: .hidden) == .rail)
    }

    @Test("Post visibility prefers the row closest to the reading guide")
    func postVisibilityPrefersClosestRow() {
        let far = LinuxDoPostVisibility(id: 1, postNumber: 1, minY: -80)
        let nearest = LinuxDoPostVisibility(id: 2, postNumber: 2, minY: 13)
        let tiedEarlier = LinuxDoPostVisibility(id: 3, postNumber: 1, minY: 11)

        #expect(nearest.isBetterCandidate(than: far))
        #expect(tiedEarlier.isBetterCandidate(than: nearest))

        var reduced: LinuxDoPostVisibility?
        LinuxDoPostVisibilityPreference.reduce(value: &reduced) { far }
        LinuxDoPostVisibilityPreference.reduce(value: &reduced) { nearest }
        LinuxDoPostVisibilityPreference.reduce(value: &reduced) { tiedEarlier }

        #expect(reduced?.id == 3)
    }

    @Test("Jump to post index loads a stream window and keeps post order stable")
    func jumpToPostIndexLoadsMissingPosts() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let detail = Self.detail(
            id: 9,
            postsCount: 5,
            stream: [100, 101, 102, 103, 104],
            posts: [
                Self.post(id: 100, topicID: 9, postNumber: 1),
                Self.post(id: 104, topicID: 9, postNumber: 5),
            ]
        )
        let client = FakeLinuxDoClient(
            topicDetail: detail,
            postsByID: [
                101: Self.post(id: 101, topicID: 9, postNumber: 2),
                102: Self.post(id: 102, topicID: 9, postNumber: 3),
                103: Self.post(id: 103, topicID: 9, postNumber: 4),
            ]
        )
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(),
            cache: LinuxDoCache(rootURL: root),
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        await store.loadTopic(id: 9, slug: "jump", force: true)

        let alreadyLoaded = await store.jumpToPostIndex(topicID: 9, index: 0)
        #expect(alreadyLoaded == 100)
        #expect(client.fetchPostsBatches.isEmpty)

        let target = await store.jumpToPostIndex(topicID: 9, index: 2)
        let state = try #require(store.topicStates[9])

        #expect(target == 102)
        #expect(state.scrollTargetPostID == 102)
        #expect(state.detail?.posts.map(\.id) == [100, 101, 102, 103, 104])
        #expect(client.fetchPostsBatches == [[101, 102, 103]])
    }

    @Test("Jump to post number resolves the loaded post number instead of raw stream index")
    func jumpToPostNumberResolvesPostNumberMismatch() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let detail = Self.detail(
            id: 29,
            postsCount: 4,
            stream: [290, 291, 292, 293],
            posts: [Self.post(id: 290, topicID: 29, postNumber: 1)]
        )
        let client = FakeLinuxDoClient(
            topicDetail: detail,
            postsByID: [
                291: Self.post(id: 291, topicID: 29, postNumber: 2),
                292: Self.post(id: 292, topicID: 29, postNumber: 4),
                293: Self.post(id: 293, topicID: 29, postNumber: 5),
            ]
        )
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(),
            cache: LinuxDoCache(rootURL: root),
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        await store.loadTopic(id: 29, slug: "mismatch", force: true)
        let target = await store.jumpToPostNumber(topicID: 29, postNumber: 4)
        let state = try #require(store.topicStates[29])

        #expect(target == 292)
        #expect(state.scrollTargetPostID == 292)
        #expect(client.fetchPostsBatches == [[291, 292, 293]])
    }

    @Test("Store falls back to topic pages when stream omits replies")
    func storeFallsBackToTopicPagesWhenStreamOmitsReplies() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let detail = Self.detail(
            id: 16,
            postsCount: 3,
            stream: [400],
            posts: [Self.post(id: 400, topicID: 16, postNumber: 1)]
        )
        let pageTwo = Self.detail(
            id: 16,
            postsCount: 3,
            stream: [400],
            posts: [
                Self.post(id: 401, topicID: 16, postNumber: 2),
                Self.post(id: 402, topicID: 16, postNumber: 3),
            ]
        )
        let client = FakeLinuxDoClient(
            topicDetail: detail,
            topicPages: [2: pageTwo]
        )
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(),
            cache: LinuxDoCache(rootURL: root),
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        await store.loadTopic(id: 16, slug: "fallback", force: true)
        let initialState = try #require(store.topicStates[16])
        #expect(initialState.remainingPostIDs.isEmpty)
        #expect(initialState.hasMorePosts)

        await store.loadMorePosts(topicID: 16)
        let loadedState = try #require(store.topicStates[16])

        #expect(client.fetchPostsBatches.isEmpty)
        #expect(client.fetchTopicPages == [2])
        #expect(loadedState.detail?.posts.map(\.id) == [400, 401, 402])
        #expect(!loadedState.hasMorePosts)
    }

    @Test("Store loads expanded post replies once")
    func storeLoadsExpandedPostRepliesOnce() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let parent = Self.post(id: 500, topicID: 18, postNumber: 1)
        let reply = Self.post(id: 501, topicID: 18, postNumber: 2)
        let client = FakeLinuxDoClient(
            topicDetail: Self.detail(id: 18, postsCount: 2, stream: [500, 501], posts: [parent]),
            repliesByPostID: [500: [reply]]
        )
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(),
            cache: LinuxDoCache(rootURL: root),
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        await store.loadTopic(id: 18, slug: "replies", force: true)
        await store.loadReplies(topicID: 18, postID: 500)
        store.toggleReplies(topicID: 18, postID: 500)
        store.toggleReplies(topicID: 18, postID: 500)
        store.toggleReplies(topicID: 18, postID: 500)

        let state = try #require(store.topicStates[18])
        #expect(client.fetchPostRepliesCalls == [500])
        #expect(state.replyStates[500]?.replies.map(\.id) == [501])
        #expect(state.replyStates[500]?.isExpanded == true)
    }

    @Test("Store submits replies through web session and merges them into detail")
    func storeSubmitsReplyAndMerges() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let parent = Self.post(id: 600, topicID: 19, postNumber: 1)
        let created = Self.post(id: 601, topicID: 19, postNumber: 2, cookedHTML: "<p>Thanks</p>")
        let client = FakeLinuxDoClient(
            topicDetail: Self.detail(id: 19, postsCount: 2, stream: [600, 601], posts: [parent]),
            nextCreatedPost: created
        )
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(webSession: Self.webSession(csrfToken: "csrf-token")),
            cache: LinuxDoCache(rootURL: root),
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        await store.loadTopic(id: 19, slug: "reply", force: true)
        store.beginReply(topicID: 19, postID: 600)
        store.setReplyDraft(topicID: 19, postID: 600, raw: "Thanks")
        await store.submitReply(topicID: 19, postID: 600)

        let state = try #require(store.topicStates[19])
        #expect(client.createReplyCalls.first?.topicID == 19)
        #expect(client.createReplyCalls.first?.replyToPostNumber == 1)
        #expect(state.detail?.posts.map(\.id) == [600, 601])
        #expect(state.replyStates[600]?.replies.map(\.id) == [601])
        #expect(state.replyComposers[600]?.isPresented == false)
    }

    @Test("Store writes require browser session and likes optimistically settle")
    func storeForumWritesRequireWebSessionAndLike() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let post = Self.post(id: 700, topicID: 20, postNumber: 1)
        let guestClient = FakeLinuxDoClient(topicDetail: Self.detail(id: 20, stream: [700], posts: [post]))
        let guestStore = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(),
            cache: LinuxDoCache(rootURL: root),
            notificationService: FakeLinuxDoNotificationService(),
            client: guestClient
        )
        await guestStore.loadTopic(id: 20, slug: "guest", force: true)
        await guestStore.toggleLike(topicID: 20, postID: 700)
        #expect(guestStore.lastError == "Sign in with a browser session to like posts.")
        #expect(guestClient.toggleLikeCalls.isEmpty)

        let authedClient = FakeLinuxDoClient(
            topicDetail: Self.detail(id: 20, stream: [700], posts: [post]),
            postsByID: [700: post]
        )
        let authedStore = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(webSession: Self.webSession(csrfToken: "csrf-token")),
            cache: LinuxDoCache(rootURL: try TempDir.make()),
            notificationService: FakeLinuxDoNotificationService(),
            client: authedClient
        )
        await authedStore.loadTopic(id: 20, slug: "authed", force: true)
        await authedStore.toggleLike(topicID: 20, postID: 700)

        let liked = try #require(authedStore.topicStates[20]?.detail?.posts.first)
        #expect(authedClient.toggleLikeCalls.first?.liked == true)
        #expect(liked.isLikedByCurrentUser)
        #expect(liked.effectiveLikeCount == 1)
    }

    @Test("Topic detail response keeps full post stream for lazy replies")
    func topicDetailResponseKeepsFullPostStream() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeLinuxDoDate)
        let response = try decoder.decode(TopicDetailResponse.self, from: Data("""
        {
          "id": 17,
          "title": "Streamed replies",
          "slug": "streamed-replies",
          "posts_count": 3,
          "post_stream": {
            "posts": [
              {
                "id": 500,
                "topic_id": 17,
                "post_number": 1,
                "username": "op",
                "cooked": "<p>First</p>",
                "created_at": "2026-05-21T10:00:00.000Z"
              }
            ],
            "stream": [500, 501, 502]
          }
        }
        """.utf8))
        let detail = LinuxDoResponseMapper.topicDetail(from: response, now: Date(timeIntervalSince1970: 100))

        #expect(detail.postsCount == 3)
        #expect(detail.posts.map(\.id) == [500])
        #expect(detail.stream == [500, 501, 502])
    }

    @Test("Notification open loads the topic and targets the notification post number")
    func notificationOpenTargetsPostNumber() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let detail = Self.detail(
            id: 12,
            postsCount: 3,
            stream: [200, 201, 202],
            posts: [Self.post(id: 200, topicID: 12, postNumber: 1)]
        )
        let client = FakeLinuxDoClient(
            topicDetail: detail,
            postsByID: [
                201: Self.post(id: 201, topicID: 12, postNumber: 2),
                202: Self.post(id: 202, topicID: 12, postNumber: 3),
            ]
        )
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(),
            cache: LinuxDoCache(rootURL: root),
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        let target = await store.openNotificationAndWait(Self.notification(id: 40, topicID: 12, postNumber: 2, slug: "notice"))
        let state = try #require(store.topicStates[12])

        #expect(store.selectedTopicID == 12)
        #expect(target == 201)
        #expect(state.scrollTargetPostID == 201)
    }

    @Test("Jump to post index warns when LinuxDo omits the target post")
    func jumpToPostIndexWarnsWhenTargetIsMissing() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let detail = Self.detail(
            id: 14,
            postsCount: 3,
            stream: [300, 301, 302],
            posts: [Self.post(id: 300, topicID: 14, postNumber: 1)]
        )
        let client = FakeLinuxDoClient(
            topicDetail: detail,
            postsByID: [302: Self.post(id: 302, topicID: 14, postNumber: 3)]
        )
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(),
            cache: LinuxDoCache(rootURL: root),
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        await store.loadTopic(id: 14, slug: "missing", force: true)
        let target = await store.jumpToPostIndex(topicID: 14, index: 1)
        let state = try #require(store.topicStates[14])

        #expect(target == nil)
        #expect(state.scrollTargetPostID == nil)
        #expect(state.timelineWarning == "That floor could not be loaded from Linux.do.")
    }

    @Test("Store treats web session as authenticated and clears it on sign out")
    func storeWebSessionAuthAndLogout() async throws {
        let credentials = InMemoryLinuxDoCredentialStore(webSession: Self.webSession(username: "tester"))
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: credentials,
            notificationService: FakeLinuxDoNotificationService(),
            client: FakeLinuxDoClient()
        )

        #expect(store.isAuthenticated)
        #expect(store.authenticationDescription == "Browser session")

        await store.signOut()

        #expect(credentials.readWebSession() == nil)
        #expect(!store.isAuthenticated)
    }

    @Test("Store persists web session avatar after sign in")
    func storePersistsWebSessionAvatarAfterSignIn() async throws {
        let avatarURL = try #require(URL(string: "https://linux.do/user_avatar/linux.do/tester/96/1.png"))
        let credentials = InMemoryLinuxDoCredentialStore()
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: credentials,
            notificationService: FakeLinuxDoNotificationService(),
            client: FakeLinuxDoClient(currentUser: LinuxDoCurrentUser(id: 1, username: "tester", name: nil, avatarURL: avatarURL))
        )

        let signedIn = await store.signInWithWebSession(Self.webSession())

        #expect(signedIn)
        #expect(store.currentUser?.avatarURL == avatarURL)
        #expect(credentials.readWebSession()?.avatarURL == avatarURL)
        #expect(store.authenticationStatus.avatarURL == avatarURL)
    }

    @Test("Store caches auth summary for render-time access")
    func storeCachesAuthSummaryForRenderAccess() {
        let credentials = CountingLinuxDoCredentialStore(webSession: Self.webSession(username: "tester"))
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: credentials,
            notificationService: FakeLinuxDoNotificationService(),
            client: FakeLinuxDoClient()
        )

        let readsAfterInit = credentials.readCount

        #expect(store.isAuthenticated)
        #expect(store.authenticationDescription == "Browser session")
        #expect(store.authenticationStatus.username == "tester")
        #expect(credentials.readCount == readsAfterInit)

        credentials.deleteWebSession()
        store.refreshAuthenticationState()

        #expect(!store.isAuthenticated)
        #expect(store.authenticationDescription == "Guest")
    }

    @Test("Store caches user profiles and keeps stale data available on retryable failures")
    func storeCachesUserProfilesAndRetries() async throws {
        let firstProfile = LinuxDoUserProfile(
            id: 20,
            username: "neo",
            name: "Neo",
            avatarURL: URL(string: "https://linux.do/user_avatar/linux.do/neo/96/1.png")
        )
        let refreshedProfile = LinuxDoUserProfile(
            id: 20,
            username: "neo",
            name: "Neo Refreshed",
            avatarURL: URL(string: "https://linux.do/user_avatar/linux.do/neo/96/2.png")
        )
        let client = FakeLinuxDoClient(userProfilesByUsername: ["neo": firstProfile])
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(),
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        await store.loadUserProfile(username: "Neo")
        await store.loadUserProfile(username: "neo")

        #expect(store.userProfileState(username: "NEO").profile?.name == "Neo")
        #expect(client.fetchUserProfileUsernames == ["Neo"])

        client.fetchUserProfileError = LinuxDoClient.ClientError.http(status: 500)
        await store.loadUserProfile(username: "neo", force: true)

        let failedState = store.userProfileState(username: "neo")
        #expect(failedState.profile?.name == "Neo")
        #expect(failedState.error == "Linux.do returned HTTP 500.")

        client.fetchUserProfileError = nil
        client.userProfilesByUsername["neo"] = refreshedProfile
        await store.loadUserProfile(username: "neo", force: true)

        let refreshedState = store.userProfileState(username: "neo")
        #expect(refreshedState.profile?.name == "Neo Refreshed")
        #expect(refreshedState.error == nil)
        #expect(client.fetchUserProfileUsernames == ["Neo", "neo", "neo"])
    }

    @Test("Client sends web session cookies")
    func clientSendsWebSessionCookies() async throws {
        let credentials = InMemoryLinuxDoCredentialStore(webSession: Self.webSession(csrfToken: "csrf-token"))
        let client = Self.makeClient(credentials: credentials) { request in
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("_t=session-token") == true)
            #expect(request.value(forHTTPHeaderField: "X-CSRF-Token") == "csrf-token")
            #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
            #expect(request.value(forHTTPHeaderField: "Discourse-Logged-In") == "true")
            return Self.response(body: Self.currentUserJSON)
        }

        _ = try await client.fetchCurrentUser()
    }

    @Test("Client fetches Discourse emoji catalog")
    func clientFetchesEmojiCatalog() async throws {
        let credentials = InMemoryLinuxDoCredentialStore()
        let client = Self.makeClient(credentials: credentials) { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/emojis.json")
            return Self.response(body: """
            {
              "smileys": [
                { "name": "distorted_face", "url": "/images/emoji/twemoji/distorted_face.png?v=15" }
              ]
            }
            """)
        }

        let catalog = try await client.fetchEmojiCatalog()

        #expect(catalog["distorted_face"]?.absoluteString == "https://linux.do/images/emoji/twemoji/distorted_face.png?v=15")
    }

    @Test("Client sends forum write endpoints with web session CSRF")
    func clientForumWriteEndpoints() async throws {
        let credentials = InMemoryLinuxDoCredentialStore(webSession: Self.webSession(csrfToken: "csrf-token"))
        let calls = LinuxDoCallCounter()
        let client = Self.makeClient(credentials: credentials) { request in
            let body = Self.jsonBody(request)
            switch calls.increment() {
            case 1:
                #expect(request.httpMethod == "POST")
                #expect(request.url?.path == "/post_actions.json")
                #expect(request.value(forHTTPHeaderField: "X-CSRF-Token") == "csrf-token")
                #expect(body["id"] as? Int == 42)
                #expect(body["post_action_type_id"] as? Int == 2)
                return Self.response(body: Self.postResponseJSON(id: 42, topicID: 9, postNumber: 1))
            case 2:
                #expect(request.httpMethod == "PUT")
                #expect(request.url?.path == "/discourse-reactions/posts/42/custom-reactions/clap/toggle.json")
                return Self.response(body: Self.postResponseJSON(id: 42, topicID: 9, postNumber: 1))
            case 3:
                #expect(request.httpMethod == "POST")
                #expect(request.url?.path == "/posts.json")
                #expect(body["topic_id"] as? Int == 9)
                #expect(body["reply_to_post_number"] as? Int == 1)
                #expect(body["raw"] as? String == "Thanks")
                return Self.response(body: Self.postResponseJSON(id: 43, topicID: 9, postNumber: 2))
            case 4:
                #expect(request.httpMethod == "POST")
                #expect(request.url?.path == "/posts.json")
                #expect(body["title"] as? String == "New Topic")
                #expect(body["category"] as? Int == 4)
                #expect(body["raw"] as? String == "Body")
                return Self.response(body: Self.postResponseJSON(id: 44, topicID: 44, postNumber: 1, slug: "new-topic"))
            default:
                Issue.record("Unexpected write request: \(request.httpMethod ?? "?") \(request.url?.path ?? "nil")")
                return Self.response(status: 404, body: "{}")
            }
        }

        _ = try await client.toggleLike(postID: 42, liked: true)
        _ = try await client.toggleReaction(postID: 42, reactionID: "clap")
        _ = try await client.createReply(topicID: 9, raw: "Thanks", replyToPostNumber: 1)
        _ = try await client.createTopic(title: "New Topic", raw: "Body", categoryID: 4)

        #expect(calls.value == 4)
    }

    @Test("Client fetches CSRF before forum writes when browser session lacks token")
    func clientFetchesCSRFFromWebSessionBeforeWrite() async throws {
        let credentials = InMemoryLinuxDoCredentialStore(webSession: Self.webSession())
        let calls = LinuxDoCallCounter()
        let client = Self.makeClient(credentials: credentials) { request in
            switch calls.increment() {
            case 1:
                #expect(request.httpMethod == "GET")
                #expect(request.url?.path == "/session/csrf")
                #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("_t=session-token") == true)
                return Self.response(body: #"{"csrf":"fresh-token"}"#)
            case 2:
                #expect(request.httpMethod == "POST")
                #expect(request.url?.path == "/post_actions.json")
                #expect(request.value(forHTTPHeaderField: "X-CSRF-Token") == "fresh-token")
                return Self.response(body: Self.postResponseJSON(id: 42, topicID: 9, postNumber: 1))
            default:
                Issue.record("Unexpected request: \(request.url?.path ?? "nil")")
                return Self.response(status: 404, body: "{}")
            }
        }

        _ = try await client.toggleLike(postID: 42, liked: true)

        #expect(credentials.readWebSession()?.csrfToken == "fresh-token")
        #expect(calls.value == 2)
    }

    @Test("Client fills missing current user avatar from profile response")
    func clientFillsMissingCurrentUserAvatarFromProfileResponse() async throws {
        let credentials = InMemoryLinuxDoCredentialStore(webSession: Self.webSession(csrfToken: "csrf-token"))
        let client = Self.makeClient(credentials: credentials) { request in
            switch request.url?.path {
            case "/session/current.json":
                return Self.response(body: Self.currentUserWithoutAvatarJSON)
            case "/u/tester.json":
                return Self.response(body: Self.userProfileJSON)
            default:
                Issue.record("Unexpected LinuxDo request path: \(request.url?.path ?? "nil")")
                return Self.response(status: 404, body: "{}")
            }
        }

        let user = try await client.fetchCurrentUser()

        #expect(user.username == "tester")
        #expect(user.avatarURL?.absoluteString == "https://linux.do/user_avatar/linux.do/tester/96/1.png")
    }

    @Test("Client fetches user profile with web session cookies")
    func clientFetchesUserProfileWithWebSessionCookies() async throws {
        let credentials = InMemoryLinuxDoCredentialStore(webSession: Self.webSession(csrfToken: "csrf-token"))
        let client = Self.makeClient(credentials: credentials) { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/u/tester.json")
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("_t=session-token") == true)
            #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
            return Self.response(body: Self.userProfileRichJSON)
        }

        let profile = try await client.fetchUserProfile(username: "tester")

        #expect(profile.username == "tester")
        #expect(profile.avatarURL?.absoluteString == "https://linux.do/user_avatar/linux.do/tester/96/1.png")
        #expect(profile.badges.first?.name == "Great Share")
    }

    @Test("Client retries public feed as guest after stale web session unauthorized")
    func clientRetriesPublicFeedAsGuest() async throws {
        let credentials = InMemoryLinuxDoCredentialStore(webSession: Self.webSession())
        let calls = LinuxDoCallCounter()
        let client = Self.makeClient(credentials: credentials) { request in
            let call = calls.increment()
            if call == 1 {
                #expect(request.value(forHTTPHeaderField: "Cookie") != nil)
                return Self.response(status: 401, body: "{}")
            }
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            return Self.response(body: Self.topicListJSON)
        }

        let list = try await client.fetchTopicList(feed: LinuxDoFeed.latest, page: 0, now: Date())

        #expect(calls.value == 2)
        #expect(credentials.readWebSession() == nil)
        #expect(list.topics.first?.title == "Guest Topic")
    }

    private static func makePreferences() -> Preferences {
        let suiteName = "ClaudeStatsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return Preferences(defaults: defaults)
    }

    private static func topic(id: Int, title: String) -> LinuxDoTopicSummary {
        LinuxDoTopicSummary(
            id: id,
            title: title,
            fancyTitle: nil,
            slug: "topic-\(id)",
            categoryID: nil,
            tags: [],
            excerpt: nil,
            postsCount: 1,
            replyCount: 0,
            views: 0,
            likeCount: 0,
            createdAt: nil,
            bumpedAt: nil,
            lastPostedAt: nil,
            imageURL: nil
        )
    }

    nonisolated fileprivate static func detail(
        id: Int = 1,
        postsCount: Int = 1,
        stream: [Int] = [100],
        posts: [LinuxDoPost]? = nil
    ) -> LinuxDoTopicDetail {
        LinuxDoTopicDetail(
            id: id,
            title: "Detail",
            fancyTitle: nil,
            slug: "detail",
            categoryID: nil,
            tags: [],
            postsCount: postsCount,
            stream: stream,
            posts: posts ?? [Self.post(id: 100, topicID: id, postNumber: 1)],
            fetchedAt: Date()
        )
	}

    nonisolated private static func post(
        id: Int,
        topicID: Int,
        postNumber: Int,
        cookedHTML: String? = nil,
        updatedAt: Date? = nil
    ) -> LinuxDoPost {
        LinuxDoPost(
            id: id,
            topicID: topicID,
            postNumber: postNumber,
            replyToPostNumber: postNumber > 1 ? 1 : nil,
            username: "user\(postNumber)",
            name: nil,
            avatarURL: nil,
            cookedHTML: cookedHTML ?? "<p>Post \(postNumber)</p>",
            createdAt: nil,
            updatedAt: updatedAt,
            likeCount: 0,
            replyCount: 0,
            reads: 0,
            score: nil,
            actionsSummary: []
        )
    }

    private static func plainText(_ block: LinuxDoContentBlock?) -> String {
        guard let block else { return "" }
        switch block.kind {
        case .paragraph(let nodes):
            return plainText(nodes)
        case .heading(level: _, content: let nodes):
            return plainText(nodes)
        case .quote(attribution: _, blocks: let blocks):
            return blocks.map { plainText($0) }.joined(separator: " ")
        case .callout(let callout):
            return ([callout.title].compactMap(\.self) + callout.blocks.map { plainText($0) }).joined(separator: " ")
        case .event(let event):
            return [event.name, event.startsAt, event.endsAt].compactMap(\.self).joined(separator: " ")
        case .spoiler(let blocks):
            return blocks.map { plainText($0) }.joined(separator: " ")
        case .details(summary: _, blocks: let blocks):
            return blocks.map { plainText($0) }.joined(separator: " ")
        case .codeBlock(_, let code), .rawHTML(let code):
            return code
        case .list(_, let items):
            return items.map { $0.blocks.map { plainText($0) }.joined(separator: " ") }.joined(separator: " ")
        case .table(let headers, let rows):
            return (headers.flatMap(\.blocks) + rows.flatMap(\.cells).flatMap(\.blocks))
                .map { plainText($0) }
                .joined(separator: " ")
        case .image, .onebox, .divider:
            return ""
        }
    }

    private static func plainText(_ nodes: [LinuxDoInlineNode]) -> String {
        nodes.map { node in
            switch node {
            case .text(let text), .code(let text):
                return text
            case .strong(let children),
                 .emphasis(let children),
                 .strikethrough(let children),
                 .highlight(let children),
                 .keyboard(let children),
                 .subscript(let children),
                 .superscript(let children),
                 .spoiler(let children):
                return plainText(children)
            case .link(_, let children):
                return plainText(children)
            case .image(_, let alt, _, _, _):
                return alt ?? ""
            case .mention(let username, _):
                return "@\(username)"
            case .hashtag(let text, _):
                return text
            case .lineBreak:
                return "\n"
            }
        }.joined()
    }

    private static func containsImage(_ blocks: [LinuxDoContentBlock]) -> Bool {
        blocks.contains { block in
            switch block.kind {
            case .image:
                return true
            case .quote(_, let blocks), .details(_, let blocks), .spoiler(let blocks):
                return containsImage(blocks)
            case .callout(let callout):
                return containsImage(callout.blocks)
            case .list(_, let items):
                return items.contains { containsImage($0.blocks) }
            case .table(let headers, let rows):
                return headers.contains { containsImage($0.blocks) }
                    || rows.flatMap(\.cells).contains { containsImage($0.blocks) }
            case .paragraph, .heading, .event, .codeBlock, .onebox, .divider, .rawHTML:
                return false
            }
        }
    }

    private static func notification(
        id: Int,
        topicID: Int? = 1,
        postNumber: Int? = 1,
        slug: String? = "topic"
    ) -> LinuxDoNotification {
        LinuxDoNotification(
            id: id,
            notificationType: 1,
            read: false,
            createdAt: nil,
            topicID: topicID,
            postNumber: postNumber,
            slug: slug,
            title: "Notification \(id)",
            excerpt: "Body"
        )
    }

    nonisolated private static func webSession(csrfToken: String? = nil, username: String? = nil) -> LinuxDoWebSession {
        LinuxDoWebSession(
            cookies: [
                LinuxDoStoredCookie(name: "_t", value: "session-token", domain: ".linux.do"),
                LinuxDoStoredCookie(name: "_forum_session", value: "forum-session", domain: "linux.do"),
                LinuxDoStoredCookie(name: "cf_clearance", value: "clearance", domain: ".linux.do"),
            ],
            csrfToken: csrfToken,
            username: username,
            savedAt: Date(timeIntervalSince1970: 100)
        )
    }

    nonisolated private static let currentUserJSON = """
    {
      "current_user": {
        "id": 1,
        "username": "tester",
        "name": "Tester",
        "avatar_template": "/user_avatar/linux.do/tester/{size}/1.png"
      }
    }
    """

    nonisolated private static let currentUserWithoutAvatarJSON = """
    {
      "current_user": {
        "id": 1,
        "username": "tester",
        "name": "Tester"
      }
    }
    """

    nonisolated private static let userProfileJSON = """
    {
      "user": {
        "id": 1,
        "username": "tester",
        "name": "Tester",
        "avatar_template": "/user_avatar/linux.do/tester/{size}/1.png"
      }
    }
    """

    nonisolated private static let userProfileRichJSON = """
    {
      "user": {
        "id": 1,
        "username": "tester",
        "name": "Tester",
        "avatar_template": "/user_avatar/linux.do/tester/{size}/1.png",
        "title": "Builder",
        "bio_excerpt": "<p>Native reader</p>",
        "website": "example.com",
        "location": "Xi'an",
        "created_at": "2023-11-14T22:13:20.000Z",
        "last_seen_at": "2023-11-14T23:13:20.000Z",
        "trust_level": 3,
        "admin": false,
        "moderator": true,
        "primary_group_name": "linux-do",
        "flair_name": "Guide",
        "flair_url": "/images/flair.png",
        "topic_count": 7,
        "post_count": 42,
        "likes_received": 99,
        "likes_given": 12,
        "solutions_count": 5,
        "profile_view_count": 1234,
        "time_read": 3600,
        "recent_time_read": 120,
        "topics_entered": 55,
        "posts_read_count": 500,
        "groups": [
          {
            "id": 11,
            "name": "seed-users",
            "full_name": "Seed Users",
            "flair_url": "/images/seed.png"
          }
        ]
      },
      "badges": [
        {
          "id": 501,
          "name": "Great Share",
          "slug": "great-share",
          "description": "Shared something useful",
          "icon": "fa-link"
        }
      ],
      "user_badges": [
        {
          "badge_id": 501,
          "granted_at": "2023-11-14T22:15:00.000Z"
        }
      ],
      "groups": [
        {
          "id": 12,
          "name": "linux-do",
          "full_name": "LINUX DO"
        }
      ]
    }
    """

    nonisolated private static let topicListJSON = """
    {
      "topic_list": {
        "topics": [
          { "id": 1, "title": "Guest Topic", "slug": "guest-topic", "tags": [] }
        ]
      }
    }
    """

    nonisolated private static let knownLinuxDoCategories: [LinuxDoCategory] = [
        LinuxDoCategory(id: 4, name: "开发调优", slug: "develop", colorHex: "32c3c3", textColorHex: "000000", iconName: "code", topicCount: 89_042),
        LinuxDoCategory(id: 98, name: "国产替代", slug: "domestic", colorHex: "D12C25", textColorHex: "000000", iconName: "seedling", topicCount: 1_204),
        LinuxDoCategory(id: 14, name: "资源荟萃", slug: "resource", colorHex: "12A89D", textColorHex: "000000", iconName: "square-share-nodes", topicCount: 25_300),
        LinuxDoCategory(id: 42, name: "文档共建", slug: "wiki", colorHex: "9cb6c4", textColorHex: "000000", iconName: "book", topicCount: 930),
        LinuxDoCategory(id: 27, name: "非我莫属", slug: "job", colorHex: "a8c6fe", textColorHex: "000000", iconName: "briefcase", topicCount: 7_604),
        LinuxDoCategory(id: 32, name: "读书成诗", slug: "reading", colorHex: "e0d900", textColorHex: "000000", iconName: "book-open-reader", topicCount: 3_112),
        LinuxDoCategory(id: 34, name: "前沿快讯", slug: "news", colorHex: "BB8FCE", textColorHex: "000000", iconName: "newspaper", topicCount: 11_008),
        LinuxDoCategory(id: 92, name: "网络记忆", slug: "feeds", colorHex: "F7941D", textColorHex: "000000", iconName: "rss", topicCount: 2_280),
        LinuxDoCategory(id: 36, name: "福利羊毛", slug: "welfare", colorHex: "E45735", textColorHex: "000000", iconName: "piggy-bank", topicCount: 8_455),
        LinuxDoCategory(id: 11, name: "搞七捻三", slug: "gossip", colorHex: "3AB54A", textColorHex: "000000", iconName: "droplet", topicCount: 27_910),
        LinuxDoCategory(id: 110, name: "虫洞广场", slug: "square", colorHex: "ff00f7", textColorHex: "000000", iconName: "hurricane", topicCount: 142),
        LinuxDoCategory(id: 2, name: "运营反馈", slug: "feedback", colorHex: "808281", textColorHex: "000000", iconName: "comments", topicCount: 6_353),
    ]

    nonisolated private static let categoriesJSON = """
    {
      "category_list": {
        "categories": [
          {
            "id": 4,
            "name": "开发调优",
            "slug": "develop",
            "color": "32c3c3",
            "text_color": "000000",
            "icon": "code",
            "topic_count": 89042
          },
          {
            "id": 2,
            "name": "运营反馈",
            "slug": "feedback",
            "color": "808281",
            "text_color": "000000",
            "icon": "comments",
            "topic_count": 6353
          }
        ]
      }
    }
    """

    nonisolated private static func response(status: Int = 200, body: String, headers: [String: String] = [:]) -> MockLinuxDoResponse {
        MockLinuxDoResponse(status: status, headers: headers, data: Data(body.utf8))
    }

    nonisolated private static func jsonBody(_ request: URLRequest) -> [String: Any] {
        var bodyData = request.httpBody
        if bodyData == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }

            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            bodyData = data
        }

        guard let data = bodyData,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    nonisolated private static func postResponseJSON(id: Int, topicID: Int, postNumber: Int, slug: String = "topic") -> String {
        """
        {
          "id": \(id),
          "topic_id": \(topicID),
          "topic_slug": "\(slug)",
          "post_number": \(postNumber),
          "username": "tester",
          "cooked": "<p>OK</p>",
          "actions_summary": [{ "id": 2, "count": 1, "acted": true }]
        }
        """
    }

    nonisolated private static func makeClient(
        credentials: InMemoryLinuxDoCredentialStore,
        handler: @escaping @Sendable (URLRequest) throws -> MockLinuxDoResponse
    ) -> LinuxDoClient {
        MockLinuxDoURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockLinuxDoURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return LinuxDoClient(baseURL: URL(string: "https://linux.do")!, session: session, credentials: credentials)
    }

    nonisolated private static func decodeLinuxDoDate(from decoder: Decoder) throws -> Date {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date"))
    }
}

private final class FakeLinuxDoClient: LinuxDoClienting, @unchecked Sendable {
    var topicList: LinuxDoTopicList
    var topicDetail: LinuxDoTopicDetail?
    var topicPages: [Int: LinuxDoTopicDetail]
    var postsByID: [Int: LinuxDoPost]
    var repliesByPostID: [Int: [LinuxDoPost]]
    var reactionUsersByPostID: [Int: [LinuxDoReaction]]
    var notifications: [LinuxDoNotification]
    var currentUser: LinuxDoCurrentUser
    var userProfilesByUsername: [String: LinuxDoUserProfile]
    var fetchUserProfileError: Error?
    var nextCreatedPost: LinuxDoPost?
    var fetchTopicListCalls = 0
    var fetchPostsBatches: [[Int]] = []
    var fetchTopicPages: [Int] = []
    var fetchPostRepliesCalls: [Int] = []
    var fetchUserProfileUsernames: [String] = []
    var toggleLikeCalls: [(postID: Int, liked: Bool)] = []
    var toggleReactionCalls: [(postID: Int, reactionID: String)] = []
    var createReplyCalls: [(topicID: Int, raw: String, replyToPostNumber: Int?)] = []
    var createTopicCalls: [(title: String, raw: String, categoryID: Int?)] = []

    init(
        topicList: LinuxDoTopicList = LinuxDoTopicList(topics: [], page: 0, nextPage: nil, fetchedAt: Date()),
        topicDetail: LinuxDoTopicDetail? = nil,
        topicPages: [Int: LinuxDoTopicDetail] = [:],
        postsByID: [Int: LinuxDoPost] = [:],
        repliesByPostID: [Int: [LinuxDoPost]] = [:],
        reactionUsersByPostID: [Int: [LinuxDoReaction]] = [:],
        notifications: [LinuxDoNotification] = [],
        currentUser: LinuxDoCurrentUser = LinuxDoCurrentUser(id: 1, username: "tester", name: nil, avatarURL: nil),
        userProfilesByUsername: [String: LinuxDoUserProfile] = [:],
        fetchUserProfileError: Error? = nil,
        nextCreatedPost: LinuxDoPost? = nil
    ) {
        self.topicList = topicList
        self.topicDetail = topicDetail
        self.topicPages = topicPages
        self.postsByID = postsByID
        self.repliesByPostID = repliesByPostID
        self.reactionUsersByPostID = reactionUsersByPostID
        self.notifications = notifications
        self.currentUser = currentUser
        self.userProfilesByUsername = userProfilesByUsername
        self.fetchUserProfileError = fetchUserProfileError
        self.nextCreatedPost = nextCreatedPost
    }

    func fetchTopicList(feed: LinuxDoFeed, page: Int, now: Date) async throws -> LinuxDoTopicList {
        fetchTopicListCalls += 1
        return topicList
    }

    func fetchCategories() async throws -> [LinuxDoCategory] {
        []
    }

    func fetchTopic(id: Int, slug: String?, now: Date) async throws -> LinuxDoTopicDetail {
        topicDetail ?? LinuxDoTests.detail(id: id)
    }

    func fetchTopicPage(id: Int, slug: String?, page: Int, now: Date) async throws -> LinuxDoTopicDetail {
        fetchTopicPages.append(page)
        return topicPages[page] ?? LinuxDoTests.detail(id: id, postsCount: 0, stream: [], posts: [])
    }

    func fetchPosts(topicID: Int, postIDs: [Int]) async throws -> [LinuxDoPost] {
        fetchPostsBatches.append(postIDs)
        return postIDs.compactMap { postsByID[$0] }
    }

    func fetchPostReplies(postID: Int) async throws -> [LinuxDoPost] {
        fetchPostRepliesCalls.append(postID)
        return repliesByPostID[postID] ?? []
    }

    func fetchReactionUsers(postID: Int, reactionID: String?) async throws -> [LinuxDoReaction] {
        reactionUsersByPostID[postID] ?? []
    }

    func fetchEmojiCatalog() async throws -> [String: URL] {
        [
            "distorted_face": URL(string: "https://linux.do/images/emoji/twemoji/distorted_face.png?v=15")!,
            "+1": URL(string: "https://linux.do/images/emoji/twemoji/+1.png?v=15")!,
        ]
    }

    func toggleLike(postID: Int, liked: Bool) async throws -> LinuxDoPost {
        toggleLikeCalls.append((postID, liked))
        let post = postsByID[postID] ?? Self.fallbackPost(id: postID)
        return post.replacingForumState(
            likeCount: max(0, post.effectiveLikeCount + (liked ? 1 : -1)),
            actionsSummary: [LinuxDoPostActionSummary(id: 2, count: max(0, post.effectiveLikeCount + (liked ? 1 : -1)), acted: liked, canAct: true)]
        )
    }

    func toggleReaction(postID: Int, reactionID: String) async throws -> LinuxDoPost {
        toggleReactionCalls.append((postID, reactionID))
        let post = postsByID[postID] ?? Self.fallbackPost(id: postID)
        return post.replacingForumState(
            reactions: [LinuxDoReaction(id: reactionID, count: 1, users: [])],
            currentUserReaction: reactionID
        )
    }

    func createReply(topicID: Int, raw: String, replyToPostNumber: Int?) async throws -> LinuxDoPost {
        createReplyCalls.append((topicID, raw, replyToPostNumber))
        return nextCreatedPost ?? LinuxDoPost(
            id: 9_001,
            topicID: topicID,
            postNumber: (replyToPostNumber ?? 1) + 1,
            replyToPostNumber: replyToPostNumber,
            username: "tester",
            name: nil,
            avatarURL: nil,
            cookedHTML: "<p>\(raw)</p>",
            createdAt: nil,
            updatedAt: nil,
            likeCount: 0,
            replyCount: 0,
            reads: 0,
            score: nil,
            actionsSummary: []
        )
    }

    func createTopic(title: String, raw: String, categoryID: Int?) async throws -> LinuxDoPost {
        createTopicCalls.append((title, raw, categoryID))
        return nextCreatedPost ?? LinuxDoPost(
            id: 9_002,
            topicID: 9_002,
            topicSlug: "created-topic",
            postNumber: 1,
            replyToPostNumber: nil,
            username: "tester",
            name: nil,
            avatarURL: nil,
            cookedHTML: "<p>\(raw)</p>",
            raw: raw,
            createdAt: nil,
            updatedAt: nil,
            likeCount: 0,
            replyCount: 0,
            reads: 0,
            score: nil,
            actionsSummary: []
        )
    }

    func fetchCurrentUser() async throws -> LinuxDoCurrentUser {
        currentUser
    }

    func fetchUser(username: String) async throws -> LinuxDoCurrentUser {
        currentUser
    }

    func fetchUserProfile(username: String) async throws -> LinuxDoUserProfile {
        fetchUserProfileUsernames.append(username)
        if let fetchUserProfileError {
            throw fetchUserProfileError
        }
        return userProfilesByUsername[username.lowercased()] ?? LinuxDoUserProfile(
            id: currentUser.id,
            username: username,
            name: currentUser.name,
            avatarURL: currentUser.avatarURL
        )
    }

    func fetchCSRFToken() async throws -> String {
        "csrf-token"
    }

    func fetchNotifications(limit: Int) async throws -> [LinuxDoNotification] {
        notifications
    }

    private static func fallbackPost(id: Int) -> LinuxDoPost {
        LinuxDoPost(
            id: id,
            topicID: nil,
            postNumber: 1,
            replyToPostNumber: nil,
            username: "tester",
            name: nil,
            avatarURL: nil,
            cookedHTML: "<p>Post</p>",
            createdAt: nil,
            updatedAt: nil,
            likeCount: 0,
            replyCount: 0,
            reads: 0,
            score: nil,
            actionsSummary: []
        )
    }
}

private struct MockLinuxDoResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let data: Data
}

private final class LinuxDoCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

private final class CountingLinuxDoCredentialStore: LinuxDoCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var webSession: LinuxDoWebSession?
    private var webSessionReads = 0

    init(webSession: LinuxDoWebSession? = nil) {
        self.webSession = webSession
    }

    var readCount: Int {
        lock.withLock { webSessionReads }
    }

    func deleteLegacyUserAPIKey() {}

    func readWebSession() -> LinuxDoWebSession? {
        lock.withLock {
            webSessionReads += 1
            return webSession
        }
    }

    func saveWebSession(_ session: LinuxDoWebSession) {
        lock.withLock { webSession = session }
    }

    func deleteWebSession() {
        lock.withLock { webSession = nil }
    }
}

private final class MockLinuxDoURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> MockLinuxDoResponse)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let mock = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: mock.status,
                httpVersion: nil,
                headerFields: mock.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: mock.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class FakeLinuxDoNotificationService: LinuxDoNotificationServicing, @unchecked Sendable {
    var sentIDs: [Int] = []
    var status: LinuxDoNotificationAuthorizationStatus = .authorized

    func authorizationStatus() async -> LinuxDoNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> LinuxDoNotificationAuthorizationStatus {
        status
    }

    func send(notification: LinuxDoNotification) async throws {
        sentIDs.append(notification.id)
    }
}
