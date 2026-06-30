import AppKit
import SwiftUI

struct GitReferenceSidebar: View {
    @Environment(AppEnvironment.self) private var env

    let repo: GitRepo
    @Bindable var model: GitReferenceSidebarViewModel
    let compact: Bool
    let onSelectTarget: (String, GitReferenceTreeRowKind) async -> Void
    let onRepositoryChanged: () async -> Void

    @State private var confirmation: GitReferenceConfirmation?
    @State private var namePrompt: GitReferenceNamePrompt?
    @State private var promptText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppSurface.panelFill)
        .task(id: repo.id) {
            await model.load(repo: repo)
        }
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let confirmation {
                Button(confirmation.buttonTitle, role: confirmation.role) {
                    Task { await runConfirmation(confirmation) }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text(confirmation?.message ?? "")
        }
        .alert(
            namePrompt?.title ?? "",
            isPresented: Binding(
                get: { namePrompt != nil },
                set: { if !$0 { namePrompt = nil } }
            )
        ) {
            TextField(namePrompt?.placeholder ?? "", text: $promptText)
            Button(namePrompt?.buttonTitle ?? "Create") {
                guard let namePrompt else { return }
                Task { await runNamePrompt(namePrompt, value: promptText) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(namePrompt?.message ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            FadingLineText(
                compact ? "Refs" : "GIT REFS",
                font: .sora(11, weight: .semibold),
                foregroundStyle: Color.stxMuted,
                tracking: compact ? 0 : 1.0,
                fadeWidth: 28
            )
            Spacer(minLength: 8)
            if model.isLoading || model.isOperationRunning {
                ProgressView()
                    .controlSize(.mini)
            }
            Button {
                Task { await model.reload(repo: repo) }
            } label: {
                Image(systemName: AppIcon.Action.refresh)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxMuted)
            .help("Refresh refs")
        }
        .padding(.horizontal, compact ? 14 : 12)
        .padding(.vertical, compact ? 12 : 10)
    }

    @ViewBuilder
    private var content: some View {
        if model.rows.isEmpty, model.isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.rows) { row in
                        GitReferenceRow(row: row) {
                            activate(row)
                        }
                        .contextMenu {
                            contextMenu(for: row)
                        }
                    }
                }
                .padding(.horizontal, compact ? 10 : 8)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for row: GitReferenceTreeRow) -> some View {
        if let reference = reference(for: row) {
            Button("Show Commit") {
                activate(row)
            }
            if let hash = row.targetHash {
                Button("New Branch from Here") {
                    presentPrompt(.createBranch(startPoint: hash))
                }
                Button("Create Tag Here") {
                    presentPrompt(.createTag(target: hash))
                }
            }
            Divider()
            switch reference.kind {
            case .localBranch:
                Button("Checkout") {
                    confirmation = .checkoutLocalBranch(reference.shortName)
                }
                .disabled(reference.isCurrent)
                Button("Rename") {
                    presentPrompt(.renameBranch(oldName: reference.shortName))
                }
                Button("Delete", role: .destructive) {
                    confirmation = .deleteBranch(name: reference.shortName, force: false)
                }
                .disabled(reference.isCurrent)
                Button("Force Delete", role: .destructive) {
                    confirmation = .deleteBranch(name: reference.shortName, force: true)
                }
                .disabled(reference.isCurrent)
            case .remoteBranch:
                Button("Create Local Tracking Branch") {
                    presentPrompt(.createTrackingBranch(
                        remoteShortName: reference.shortName,
                        defaultName: reference.branchName ?? reference.shortName
                    ))
                }
                if let remoteName = reference.remoteName {
                    Button("Fetch \(remoteName)") {
                        confirmation = .fetch(remoteName)
                    }
                    Button("Prune \(remoteName)") {
                        confirmation = .prune(remoteName)
                    }
                }
            case .tag:
                Button("Checkout Detached") {
                    confirmation = .checkoutDetached(target: reference.shortName, displayName: reference.shortName)
                }
                Button("Delete Local Tag", role: .destructive) {
                    confirmation = .deleteTag(reference.shortName)
                }
            }
            if let hash = row.targetHash {
                Divider()
                Button("Copy Hash") {
                    copy(hash)
                }
            }
        } else if row.kind == .remoteGroup, let remoteName = row.remoteName {
            Button("Fetch \(remoteName)") {
                confirmation = .fetch(remoteName)
            }
            Button("Prune \(remoteName)") {
                confirmation = .prune(remoteName)
            }
        } else if row.kind == .reflog, let hash = row.targetHash {
            Button("Show Commit") {
                activate(row)
            }
            Button("Create Branch from This Commit") {
                presentPrompt(.createBranch(startPoint: hash))
            }
            Button("Create Tag Here") {
                presentPrompt(.createTag(target: hash))
            }
            Divider()
            Button("Copy Hash") {
                copy(hash)
            }
        }
    }

    private func activate(_ row: GitReferenceTreeRow) {
        if row.isExpandable {
            model.toggle(row)
            return
        }
        if row.id == "reflog:load-more" {
            Task { await model.loadMoreReflogs(repo: repo) }
            return
        }
        guard let targetHash = row.targetHash else { return }
        model.select(row)
        Task {
            await onSelectTarget(targetHash, row.kind)
        }
    }

    private func reference(for row: GitReferenceTreeRow) -> GitReference? {
        guard let fullName = row.referenceFullName else { return nil }
        return model.snapshot.reference(fullName: fullName)
    }

    private func presentPrompt(_ prompt: GitReferenceNamePrompt) {
        promptText = prompt.defaultValue
        namePrompt = prompt
    }

    private func runConfirmation(_ confirmation: GitReferenceConfirmation) async {
        self.confirmation = nil
        let succeeded: Bool
        switch confirmation.action {
        case .checkoutLocalBranch(let name):
            succeeded = await model.checkoutLocalBranch(repo: repo, name: name)
        case .checkoutDetached(let target):
            succeeded = await model.checkoutDetached(repo: repo, target: target)
        case .deleteBranch(let name, let force):
            succeeded = await model.deleteBranch(repo: repo, name: name, force: force)
        case .deleteTag(let name):
            succeeded = await model.deleteTag(repo: repo, name: name)
        case .fetch(let remoteName):
            succeeded = await model.fetch(repo: repo, remoteName: remoteName)
        case .prune(let remoteName):
            succeeded = await model.prune(repo: repo, remoteName: remoteName)
        }
        await finishOperation(succeeded: succeeded)
    }

    private func runNamePrompt(_ prompt: GitReferenceNamePrompt, value: String) async {
        namePrompt = nil
        let succeeded: Bool
        switch prompt.action {
        case .createBranch(let startPoint):
            succeeded = await model.createBranch(repo: repo, name: value, startPoint: startPoint)
        case .createTrackingBranch(let remoteShortName):
            succeeded = await model.createTrackingBranch(
                repo: repo,
                localName: value,
                remoteShortName: remoteShortName
            )
        case .renameBranch(let oldName):
            succeeded = await model.renameBranch(repo: repo, oldName: oldName, newName: value)
        case .createTag(let target):
            succeeded = await model.createTag(repo: repo, name: value, target: target)
        }
        await finishOperation(succeeded: succeeded)
    }

    private func finishOperation(succeeded: Bool) async {
        if succeeded {
            await onRepositoryChanged()
        } else if let failure = model.lastFailureNotice {
            env.notices.showGitFailure(failure)
            model.clearFailureNotice()
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct GitReferenceRow: View {
    let row: GitReferenceTreeRow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Spacer()
                    .frame(width: CGFloat(row.depth) * 14)
                disclosure
                    .frame(width: 12)
                Image(systemName: row.systemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.sora(row.kind == .section ? 11 : 12, weight: row.kind == .section ? .semibold : .regular))
                        .foregroundStyle(row.kind == .section ? Color.stxMuted : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle = row.subtitle {
                        Text(subtitle)
                            .font(.sora(9))
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                if let detail = row.detail {
                    Text(detail)
                        .font(.sora(9).monospacedDigit())
                        .foregroundStyle(row.isCurrent ? Color.stxAccent : Color.stxMuted)
                        .lineLimit(1)
                }
            }
            .frame(height: rowHeight)
            .padding(.horizontal, 7)
            .contentShape(Rectangle())
            .background(selectionFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(rowHelp)
        .accessibilityLabel(row.title)
    }

    @ViewBuilder
    private var disclosure: some View {
        if row.isExpandable {
            Image(systemName: row.isExpanded ? AppIcon.Navigation.down : AppIcon.Navigation.disclosure)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.stxMuted.opacity(0.75))
        } else {
            Color.clear
        }
    }

    private var rowHeight: CGFloat {
        row.subtitle == nil ? 28 : 36
    }

    private var iconSize: CGFloat {
        row.kind == .section ? 12 : 13
    }

    private var iconColor: Color {
        if row.isCurrent { return Color.stxAccent }
        switch row.kind {
        case .section, .remoteGroup, .folder:
            return Color.stxMuted
        case .reference, .reflog:
            return row.isSelected ? Color.stxAccent : Color.stxMuted
        }
    }

    private var selectionFill: Color {
        if row.isSelected { return Color.stxAccent.opacity(0.14) }
        if row.isCurrent { return Color.stxAccent.opacity(0.08) }
        return .clear
    }

    private var rowHelp: String {
        if row.isExpandable {
            return row.isExpanded ? "Collapse \(row.title)" : "Expand \(row.title)"
        }
        if let targetHash = row.targetHash {
            return "Show \(String(targetHash.prefix(7)))"
        }
        return row.title
    }
}

private struct GitReferenceConfirmation: Identifiable {
    enum Action {
        case checkoutLocalBranch(String)
        case checkoutDetached(target: String)
        case deleteBranch(name: String, force: Bool)
        case deleteTag(String)
        case fetch(String)
        case prune(String)
    }

    let id = UUID()
    let title: String
    let message: String
    let buttonTitle: String
    let role: ButtonRole?
    let action: Action

    static func checkoutLocalBranch(_ name: String) -> GitReferenceConfirmation {
        GitReferenceConfirmation(
            title: "Checkout branch?",
            message: "Switch to \(name). Git will stop if your working tree cannot be checked out cleanly.",
            buttonTitle: "Checkout",
            role: nil,
            action: .checkoutLocalBranch(name)
        )
    }

    static func checkoutDetached(target: String, displayName: String) -> GitReferenceConfirmation {
        GitReferenceConfirmation(
            title: "Checkout detached?",
            message: "Checkout \(displayName) in detached HEAD mode. Git will stop if your working tree cannot be checked out cleanly.",
            buttonTitle: "Checkout Detached",
            role: nil,
            action: .checkoutDetached(target: target)
        )
    }

    static func deleteBranch(name: String, force: Bool) -> GitReferenceConfirmation {
        GitReferenceConfirmation(
            title: force ? "Force delete branch?" : "Delete branch?",
            message: force
                ? "Force delete \(name). Unmerged commits on that branch may become unreachable."
                : "Delete \(name). Git will stop if the branch is not fully merged.",
            buttonTitle: force ? "Force Delete" : "Delete",
            role: .destructive,
            action: .deleteBranch(name: name, force: force)
        )
    }

    static func deleteTag(_ name: String) -> GitReferenceConfirmation {
        GitReferenceConfirmation(
            title: "Delete local tag?",
            message: "Delete local tag \(name). This does not delete any remote tag.",
            buttonTitle: "Delete Tag",
            role: .destructive,
            action: .deleteTag(name)
        )
    }

    static func fetch(_ remoteName: String) -> GitReferenceConfirmation {
        GitReferenceConfirmation(
            title: "Fetch remote?",
            message: "Fetch updates from \(remoteName).",
            buttonTitle: "Fetch",
            role: nil,
            action: .fetch(remoteName)
        )
    }

    static func prune(_ remoteName: String) -> GitReferenceConfirmation {
        GitReferenceConfirmation(
            title: "Prune remote?",
            message: "Remove stale remote-tracking refs for \(remoteName). This does not delete remote branches.",
            buttonTitle: "Prune",
            role: .destructive,
            action: .prune(remoteName)
        )
    }
}

private struct GitReferenceNamePrompt: Identifiable {
    enum Action {
        case createBranch(startPoint: String)
        case createTrackingBranch(remoteShortName: String)
        case renameBranch(oldName: String)
        case createTag(target: String)
    }

    let id = UUID()
    let title: String
    let message: String
    let placeholder: String
    let defaultValue: String
    let buttonTitle: String
    let action: Action

    static func createBranch(startPoint: String) -> GitReferenceNamePrompt {
        GitReferenceNamePrompt(
            title: "New Branch",
            message: "Create a local branch at \(String(startPoint.prefix(7))).",
            placeholder: "branch-name",
            defaultValue: "",
            buttonTitle: "Create",
            action: .createBranch(startPoint: startPoint)
        )
    }

    static func createTrackingBranch(remoteShortName: String, defaultName: String) -> GitReferenceNamePrompt {
        GitReferenceNamePrompt(
            title: "New Tracking Branch",
            message: "Create a local branch that tracks \(remoteShortName).",
            placeholder: "branch-name",
            defaultValue: defaultName,
            buttonTitle: "Create",
            action: .createTrackingBranch(remoteShortName: remoteShortName)
        )
    }

    static func renameBranch(oldName: String) -> GitReferenceNamePrompt {
        GitReferenceNamePrompt(
            title: "Rename Branch",
            message: "Rename \(oldName).",
            placeholder: "branch-name",
            defaultValue: oldName,
            buttonTitle: "Rename",
            action: .renameBranch(oldName: oldName)
        )
    }

    static func createTag(target: String) -> GitReferenceNamePrompt {
        GitReferenceNamePrompt(
            title: "New Tag",
            message: "Create a local tag at \(String(target.prefix(7))).",
            placeholder: "tag-name",
            defaultValue: "",
            buttonTitle: "Create",
            action: .createTag(target: target)
        )
    }
}
