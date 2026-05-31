import SwiftUI

struct LinuxDoTopicListView: View {
    @Bindable var store: LinuxDoStore

    private var state: LinuxDoListState {
        store.currentListState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            listHeader
            StxRule()
            content
        }
        .background(Color.primary.opacity(0.018))
    }

    private var listHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedFeed.title)
                    .font(.sora(15, weight: .semibold))
                    .lineLimit(1)
                if let lastFetchedAt = state.lastFetchedAt {
                    Text("Updated \(Format.relativeDate(lastFetchedAt))")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                } else {
                    Text("Linux.do")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
            }
            Spacer(minLength: 8)
            if state.isLoading || state.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await store.refreshCurrentFeed() }
            } label: {
                Image(systemName: AppIcon.Action.refresh)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(state.isLoading || state.isRefreshing)
            .help("Refresh")
            .accessibilityLabel("Refresh")
        }
        .padding(.horizontal, LinuxDoLayout.contentInset)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading && state.topics.isEmpty {
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else if state.topics.isEmpty {
            ContentUnavailableView {
                Label("No Topics", systemImage: AppIcon.Resource.tray)
            } description: {
                Text(state.error ?? "Nothing to show for this feed yet.")
            }
            .font(.sora(12))
        } else {
            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let error = state.error {
                        LinuxDoInlineError(message: error)
                            .padding(.leading, LinuxDoLayout.contentInset)
                            .padding(.trailing, LinuxDoLayout.contentInset)
                            .padding(.vertical, 12)
                    }
                    ForEach(state.topics) { topic in
                        LinuxDoTopicRow(
                            topic: topic,
                            categoryColorHex: categoryColor(for: topic),
                            isSelected: store.selectedTopicID == topic.id
                        ) {
                            store.selectTopic(topic)
                        }
                        .onAppear {
                            if topic.id == state.topics.last?.id {
                                Task { await store.loadMoreCurrentFeed() }
                            }
                        }
                        StxRule()
                    }
                    if state.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                    }
                }
            }
        }
    }

    private func categoryColor(for topic: LinuxDoTopicSummary) -> String? {
        guard let categoryID = topic.categoryID else { return nil }
        return store.categories.first { $0.id == categoryID }?.colorHex
    }
}

private struct LinuxDoTopicRow: View {
    let topic: LinuxDoTopicSummary
    let categoryColorHex: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let imageURL = topic.imageURL {
                    HStack(alignment: .top, spacing: 10) {
                        thumbnail(url: imageURL)
                        topicText
                    }
                    .padding(.horizontal, LinuxDoLayout.contentInset)
                } else {
                    topicText
                        .padding(.leading, LinuxDoLayout.contentInset)
                        .padding(.trailing, LinuxDoLayout.contentInset)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    Rectangle().fill(Color.stxAccent.opacity(0.11))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func thumbnail(url: URL) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.primary.opacity(0.04)
        }
        .frame(width: 54, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var categoryMarker: some View {
        if let categoryColorHex {
            Circle()
                .fill(Color(hex: categoryColorHex) ?? Color.stxMuted)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
        }
    }

    private var topicText: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 6) {
                Text(topic.displayTitle)
                    .font(.sora(12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                categoryMarker
            }

            if !topic.tags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(topic.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.sora(8, weight: .medium))
                            .foregroundStyle(Color.stxAccent)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(Color.stxAccent.opacity(0.1), in: Capsule())
                    }
                }
            }

            if !topic.displayExcerpt.isEmpty {
                Text(topic.displayExcerpt)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                stat("bubble.left", topic.replyCount)
                stat("eye", topic.views)
                stat("heart", topic.likeCount)
                Spacer(minLength: 4)
                if let date = topic.lastPostedAt ?? topic.bumpedAt ?? topic.createdAt {
                    Text(Format.relativeDate(date))
                        .font(.sora(9))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }
            }
        }
    }

    private func stat(_ symbol: String, _ value: Int) -> some View {
        Label("\(value)", systemImage: symbol)
            .font(.sora(9).monospacedDigit())
            .foregroundStyle(Color.stxMuted)
            .labelStyle(.titleAndIcon)
    }
}

struct LinuxDoInlineError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: AppIcon.Status.warning)
            .font(.sora(11))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
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
