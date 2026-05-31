import SwiftUI

struct LinuxDoSidebarColumn: View {
    @Bindable var store: LinuxDoStore
    var signInEnabled = true
    var onExit: () -> Void
    var onSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)

            SidebarRow(
                title: "Back to App",
                symbol: AppIcon.Navigation.back,
                isSelected: false,
                action: onExit
            )

            LinuxDoSourceColumn(store: store, signInEnabled: signInEnabled, onSignIn: onSignIn)
                .frame(maxHeight: .infinity)
        }
        .padding(.bottom, 10)
    }
}

struct LinuxDoSourceColumn: View {
    @Bindable var store: LinuxDoStore
    var signInEnabled = true
    var onSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    searchSection
                    feedSection
                    topSection
                    categoriesSection
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)

            StxRule()

            accountSummary
                .padding(12)
        }
    }

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sourceHeader("Feeds")
            sourceButton(title: "Latest", symbol: AppIcon.Status.clock, feed: .latest)
            sourceButton(title: "Hot", symbol: AppIcon.LinuxDo.hot, feed: .hot)
        }
    }

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sourceHeader("Top")
            sourceButton(title: "Top \(store.topPeriod.displayName)", symbol: AppIcon.Leaderboard.trophyFilled, feed: .top(store.topPeriod))
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sourceHeader("Search")
            TextField("Search LinuxDo", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .font(.sora(12))
                .onSubmit { store.submitSearch() }
                .onChange(of: store.searchText) { _, value in
                    if value.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                        store.scheduleSearch()
                    }
                }
            Button {
                store.submitSearch()
            } label: {
                Label("Search", systemImage: AppIcon.Action.search)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sourceHeader("Categories")
            if store.isLoadingCategories && store.categories.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 8)
            } else {
                ForEach(store.categories.prefix(28)) { category in
                    categorySourceButton(category)
                }
            }
        }
    }

    private var accountSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                accountAvatarControl

                VStack(alignment: .leading, spacing: 2) {
                    Text(accountTitle)
                        .font(.sora(12, weight: .medium))
                        .lineLimit(1)
                    Text(accountSubtitle)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            if store.isSigningIn {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Signing in")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var accountAvatarControl: some View {
        if store.isAuthenticated {
            accountAvatar
        } else {
            Button {
                onSignIn()
            } label: {
                accountAvatar
            }
            .buttonStyle(.plain)
            .disabled(!signInEnabled || store.isSigningIn)
            .help("Sign in to LinuxDo")
            .accessibilityLabel("Sign in to LinuxDo")
        }
    }

    private var accountAvatar: some View {
        Group {
            if store.isAuthenticated, let avatarURL = store.currentUser?.avatarURL ?? store.authenticationStatus.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    accountAvatarFallback
                }
            } else {
                accountAvatarFallback
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(store.isAuthenticated ? Color.stxAccent.opacity(0.35) : Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private var accountAvatarFallback: some View {
        ZStack {
            Circle()
                .fill(store.isAuthenticated ? Color.stxAccent.opacity(0.16) : Color.primary.opacity(0.06))
            if store.isAuthenticated {
                Text(accountInitial)
                    .font(.sora(11, weight: .semibold))
                    .foregroundStyle(Color.stxAccent)
            } else {
                Image(systemName: AppIcon.People.person)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
            }
        }
    }

    private var accountInitial: String {
        let username = store.currentUser?.username ?? store.authenticationStatus.username ?? ""
        return username.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "L"
    }

    private var accountTitle: String {
        if let user = store.currentUser {
            return "@\(user.username)"
        }
        if let username = store.authenticationStatus.username, !username.isEmpty {
            return "@\(username)"
        }
        return store.isAuthenticated ? "Signed in" : "Guest browsing"
    }

    private var accountSubtitle: String {
        store.isAuthenticated ? "\(store.authenticationDescription) active." : "Public feeds do not require sign-in."
    }

    private func sourceHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.sora(10, weight: .semibold))
            .tracking(1)
            .foregroundStyle(Color.stxMuted)
    }

    private func sourceButton(title: String, symbol: String, feed: LinuxDoFeed, colorHex: String? = nil) -> some View {
        Button {
            store.selectFeed(feed)
        } label: {
            HStack(spacing: 8) {
                if let colorHex {
                    Circle()
                        .fill(Color(hex: colorHex) ?? Color.stxMuted)
                        .frame(width: 8, height: 8)
                        .frame(width: 16)
                } else {
                    Image(systemName: symbol)
                        .frame(width: 16)
                        .foregroundStyle(store.selectedFeed == feed ? Color.stxAccent : Color.stxMuted)
                }
                Text(title)
                    .font(.sora(12, weight: store.selectedFeed == feed ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background {
                if store.selectedFeed == feed {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.stxAccent.opacity(0.13))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func categorySourceButton(_ category: LinuxDoCategory) -> some View {
        let feed = LinuxDoFeed.category(id: category.id, name: category.name, slug: category.slug)
        return Button {
            store.selectFeed(feed)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: LinuxDoCategoryIcon.symbolName(for: category))
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color(hex: category.colorHex ?? "") ?? Color.stxMuted)
                    .frame(width: 16)
                Text(category.name)
                    .font(.sora(12, weight: store.selectedFeed == feed ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background {
                if store.selectedFeed == feed {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.stxAccent.opacity(0.13))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

enum LinuxDoCategoryIcon {
    static func symbolName(for category: LinuxDoCategory) -> String {
        let slug = category.slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let symbol = symbolName(forKnownSlug: slug) {
            return symbol
        }

        let icon = category.iconName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let icon, let symbol = symbolName(forDiscourseIcon: icon) {
            return symbol
        }

        return symbolName(forText: "\(category.name) \(slug)")
    }

    private static func symbolName(forKnownSlug slug: String) -> String? {
        return switch slug {
        case "develop":
            "chevron.left.forwardslash.chevron.right"
        case "domestic":
            "leaf.fill"
        case "resource":
            "point.3.connected.trianglepath.dotted"
        case "wiki":
            "doc.richtext.fill"
        case "job":
            "briefcase.fill"
        case "reading":
            "book.closed.fill"
        case "news":
            "newspaper.fill"
        case "feeds":
            "dot.radiowaves.left.and.right"
        case "welfare":
            "gift.fill"
        case "gossip":
            "drop.fill"
        case "square":
            "hurricane"
        case "feedback":
            "bubble.left.and.bubble.right.fill"
        default:
            nil
        }
    }

    private static func symbolName(forDiscourseIcon icon: String) -> String? {
        return switch icon {
        case "code":
            "chevron.left.forwardslash.chevron.right"
        case "seedling":
            "leaf.fill"
        case "share-nodes", "square-share-nodes", "share-alt", "share":
            "point.3.connected.trianglepath.dotted"
        case "hard-drive", "hdd":
            "externaldrive.fill"
        case "book":
            "doc.richtext.fill"
        case "book-open", "book-open-reader":
            "book.closed.fill"
        case "briefcase":
            "briefcase.fill"
        case "newspaper":
            "newspaper.fill"
        case "rss":
            "dot.radiowaves.left.and.right"
        case "piggy-bank":
            "gift.fill"
        case "droplet", "tint":
            "drop.fill"
        case "hurricane":
            "hurricane"
        case "comments":
            "bubble.left.and.bubble.right.fill"
        case "list", "list-ul":
            "list.bullet"
        case "bug", "worm":
            "circle.hexagongrid.fill"
        default:
            nil
        }
    }

    private static func symbolName(forText text: String) -> String {
        let lowered = text.lowercased()
        if lowered.contains("开发") || lowered.contains("code") || lowered.contains("dev") {
            return "chevron.left.forwardslash.chevron.right"
        }
        if lowered.contains("资源") || lowered.contains("share") || lowered.contains("resource") {
            return "point.3.connected.trianglepath.dotted"
        }
        if lowered.contains("文档") || lowered.contains("wiki") || lowered.contains("doc") {
            return "doc.richtext.fill"
        }
        if lowered.contains("读书") || lowered.contains("reading") || lowered.contains("book") {
            return "book.closed.fill"
        }
        if lowered.contains("新闻") || lowered.contains("快讯") || lowered.contains("news") {
            return "newspaper.fill"
        }
        if lowered.contains("反馈") || lowered.contains("comment") || lowered.contains("feedback") {
            return "bubble.left.and.bubble.right.fill"
        }
        if lowered.contains("工作") || lowered.contains("job") || lowered.contains("briefcase") {
            return "briefcase.fill"
        }
        if lowered.contains("rss") || lowered.contains("feed") {
            return "dot.radiowaves.left.and.right"
        }
        if lowered.contains("福利") || lowered.contains("welfare") {
            return "gift.fill"
        }
        if lowered.contains("广场") || lowered.contains("square") {
            return "hurricane"
        }
        if lowered.contains("国产") || lowered.contains("domestic") {
            return "leaf.fill"
        }
        return "folder.badge.questionmark"
    }
}

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = Int(cleaned, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xff) / 255.0
        let green = Double((value >> 8) & 0xff) / 255.0
        let blue = Double(value & 0xff) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
