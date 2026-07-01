import AppKit
import SwiftUI

struct GitWorkspaceSidebar: View {
    let model: GitActivityViewModel
    @Binding var selection: GitWorkspaceSelection
    var onSelect: (GitWorkspaceSelection) -> Void
    var onExit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)

            SidebarRow(
                title: "Back to App",
                symbol: AppIcon.Navigation.back,
                isSelected: false
            ) {
                clearFocus()
                onExit()
            }

            statusCard
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 10)

            sectionHeader("REPOSITORIES")

            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    GitWorkspaceSidebarRow(
                        title: "All Repos",
                        subtitle: "\(model.overviewSnapshot.totalCommits) commits",
                        detail: Format.tokens(model.overviewSnapshot.totalChurn) + " churn",
                        symbol: AppIcon.Workspace.dashboard,
                        isSelected: selection == .all
                    ) {
                        select(.all)
                    }

                    ForEach(model.repos) { activity in
                        GitWorkspaceSidebarRow(
                            title: activity.repo.displayName,
                            subtitle: "\(activity.commitCount) commits",
                            detail: "\(activity.filesChanged) files",
                            symbol: AppIcon.Resource.folder,
                            isSelected: selection == .repo(activity.repo.id)
                        ) {
                            select(.repo(activity.repo.id))
                        }
                        .help(activity.repo.rootPath)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 10)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { clearFocus() }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("GIT")
                    .font(.sora(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 8)
                if model.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            HStack(spacing: 10) {
                WorkspaceMiniStat(value: "\(model.repos.count)", label: model.repos.count == 1 ? "repo" : "repos")
                WorkspaceMiniStat(value: "\(model.overviewSnapshot.totalCommits)", label: "commits")
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: model.gitAvailable ? "checkmark.circle" : AppIcon.Status.warning)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.gitAvailable ? Color.stxAccent : Color(red: 0.92, green: 0.58, blue: 0.16))
                Text(statusMessage)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1))
    }

    private var statusMessage: String {
        guard model.gitAvailable else { return "git command unavailable" }
        if model.repos.isEmpty { return model.isLoading ? "loading repositories" : "no repositories in range" }
        return model.userEmail.map { "author: \($0)" } ?? "all configured sources"
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(.sora(10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Color.stxMuted)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 4)
    }

    private func select(_ next: GitWorkspaceSelection) {
        clearFocus()
        onSelect(next)
    }

    private func clearFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

private struct GitWorkspaceSidebarRow: View {
    let title: String
    let subtitle: String
    let detail: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.sora(12, weight: .semibold))
                        .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 5) {
                        Text(subtitle)
                        Text("-")
                        Text(detail)
                    }
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
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
        .padding(.vertical, 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .accessibilityLabel(Text(title))
    }
}

#if DEBUG
#Preview("Git workspace sidebar") {
    @Previewable @State var selection = GitWorkspaceSelection.all
    let model = GitActivityViewModel.preview()
    return GitWorkspaceSidebar(
        model: model,
        selection: $selection,
        onSelect: { selection = $0 },
        onExit: {}
    )
    .frame(width: 240, height: 620)
    .background(VisualEffectBackground())
}
#endif
