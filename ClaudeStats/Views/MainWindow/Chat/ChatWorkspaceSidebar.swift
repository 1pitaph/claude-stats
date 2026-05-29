import AppKit
import SwiftUI

struct ChatWorkspaceSidebar: View {
    @Bindable var store: ChatStore
    let defaultModelID: String
    var onExit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)

            SidebarRow(
                title: "Back to App",
                symbol: "chevron.left",
                isSelected: false,
                action: close
            )

            statusCard
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 10)

            HStack(spacing: 8) {
                Text("CHATS")
                    .font(.sora(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 8)
                Button {
                    store.newConversation(defaultModelID: defaultModelID)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .help("New Chat")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(store.conversations) { conversation in
                        ChatConversationSidebarRow(
                            conversation: conversation,
                            isSelected: store.selectedConversationID == conversation.id,
                            onSelect: { store.selectConversation(conversation.id) },
                            onDelete: { store.deleteConversation(conversation.id, defaultModelID: defaultModelID) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .padding(.bottom, 10)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { clearFocus() }
        }
        .task {
            await store.loadIfNeeded(defaultModelID: defaultModelID)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("LOCAL CHAT")
                    .font(.sora(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 8)
                if store.isLoading || store.isGenerating {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            HStack(spacing: 10) {
                AIConfigsMiniStat(value: "\(store.conversations.count)", label: String(localized: "threads"))
                AIConfigsMiniStat(value: store.projectOptions.isEmpty ? "0" : "\(store.projectOptions.count)", label: String(localized: "repos"))
            }

            HStack(spacing: 8) {
                Image(systemName: store.isGenerating ? "sparkles" : "checkmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.isGenerating ? Color.stxAccent : Color.stxMuted)
                Text(store.isGenerating ? String(localized: "generating") : String(localized: "ready"))
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1))
    }

    private func close() {
        clearFocus()
        onExit()
    }

    private func clearFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

private struct ChatConversationSidebarRow: View {
    let conversation: ChatConversation
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    private var preview: String {
        conversation.messages.last(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.content
            ?? String(localized: "No messages yet")
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(conversation.title)
                        .font(.sora(12, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                        .lineLimit(1)
                    Text(preview)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if hovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.stxMuted)
                    .help("Delete Chat")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.10))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete Chat", role: .destructive, action: onDelete)
        }
        .onHover { hovering = $0 }
    }
}
