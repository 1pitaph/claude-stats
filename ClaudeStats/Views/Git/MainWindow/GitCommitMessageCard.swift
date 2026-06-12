import AppKit
import SwiftUI

struct GitCommitMessageCard: View {
    @Environment(AppEnvironment.self) private var env

    let repo: GitRepo
    let target: GitCommitMessageTarget
    let onLocalCommitSucceeded: (@MainActor (GitWorkingTreeCommitResult) async -> Void)?
    let onPushSucceeded: (@MainActor () async -> Void)?

    @State private var vm = GitCommitMessageViewModel()
    @State private var pendingCommitResult: GitCommitMessageResult?

    init(
        repo: GitRepo,
        target: GitCommitMessageTarget,
        onLocalCommitSucceeded: (@MainActor (GitWorkingTreeCommitResult) async -> Void)? = nil,
        onPushSucceeded: (@MainActor () async -> Void)? = nil
    ) {
        self.repo = repo
        self.target = target
        self.onLocalCommitSucceeded = onLocalCommitSucceeded
        self.onPushSucceeded = onPushSucceeded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .padding(12)
        .appSurface(.compactCard(radius: 10))
        .task(id: cacheLoadID) {
            await loadCached()
        }
        .onChange(of: target.identity) { _, _ in
            vm.reset()
        }
        .confirmationDialog(
            "Stage all changes and commit?",
            isPresented: commitConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Stage All & Commit") {
                guard let result = pendingCommitResult else { return }
                pendingCommitResult = nil
                commit(result)
            }
            Button("Cancel", role: .cancel) {
                pendingCommitResult = nil
            }
        } message: {
            Text("This will stage every current working tree change in this repository and commit with the generated message.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("COMMIT MESSAGE")
                .font(.sora(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            if case .loaded(let result) = vm.state {
                GitCommitMessageCopyButton(
                    text: result.copyText,
                    label: "Copy commit message"
                )
            }
            Spacer(minLength: 0)
            switch vm.state {
            case .loading:
                ProgressView()
                    .controlSize(.mini)
            case .loaded(let result):
                StatusSeverityBadge(
                    label: result.isCached ? "cached" : "generated",
                    indicatorTint: result.isCached ? Color.stxMuted : Color.stxAccent
                )
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle:
            VStack(alignment: .leading, spacing: 9) {
                Text("Generate a cached commit message for this diff.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                controls(result: nil)
            }
        case .loading:
            Text("Generating commit message with \(env.appLLMSettings.mode.title)...")
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 9) {
                Text(message)
                    .font(.sora(10))
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                controls(result: nil)
            }
        case .loaded(let result):
            VStack(alignment: .leading, spacing: 10) {
                metadata(result)
                GitCommitMessageContent(result: result)
                controls(result: result)
                commitStatus
            }
        }
    }

    private func metadata(_ result: GitCommitMessageResult) -> some View {
        let tags = GitCommitMessageMetadataTag.tags(for: result)
        return GitCommitMessageMetadataFlowLayout(spacing: 5, rowSpacing: 5) {
            ForEach(tags) { tag in
                GitCommitMessageMetadataTag(tag: tag)
            }
        }
    }

    private func controls(result: GitCommitMessageResult?) -> some View {
        HStack(spacing: 7) {
            Button {
                generate(forceRefresh: false)
            } label: {
                Label(result == nil ? "Generate" : "Regenerate", systemImage: AppIcon.Feature.ai)
            }
            .controlSize(.small)
            .disabled(isLoading || isCommitting || isPushing)

            if result != nil {
                Button {
                    generate(forceRefresh: true)
                } label: {
                    Label("Refresh", systemImage: AppIcon.Action.refresh)
                }
                .controlSize(.small)
                .disabled(isLoading || isCommitting || isPushing)

                actionPill(result: result)
            }
        }
    }

    private var isLoading: Bool {
        if case .loading = vm.state { return true }
        return false
    }

    private var isCommitting: Bool {
        if case .committing = vm.commitState { return true }
        return false
    }

    private var isPushing: Bool {
        if case .pushing = vm.commitState { return true }
        return false
    }

    @ViewBuilder
    private func actionPill(result: GitCommitMessageResult?) -> some View {
        if target == .workingTree, let result {
            GitCommitMessageActionPill(
                label: actionPillLabel,
                systemImage: actionPillIcon,
                tint: actionPillTint,
                isDisabled: isLoading || isCommitting || isPushing || isActionPillTerminal
            ) {
                handleActionPill(result: result)
            }
        }
    }

    private var actionPillLabel: String {
        switch vm.commitState {
        case .idle, .failed:
            return "Commit"
        case .committing:
            return "Committing"
        case .committed:
            return "Committed"
        case .readyToPush(let pending), .pushFailed(_, let pending):
            return pending.target.buttonLabel
        case .pushing(let pending):
            return pending.target.mode == .publishBranch ? "Publishing" : "Pushing"
        case .pushed:
            return "Pushed"
        }
    }

    private var actionPillIcon: String {
        switch vm.commitState {
        case .readyToPush, .pushing, .pushFailed:
            return AppIcon.Action.uploadTray
        case .committed, .pushed:
            return AppIcon.Status.success
        default:
            return AppIcon.Action.confirm
        }
    }

    private var actionPillTint: Color {
        switch vm.commitState {
        case .committed, .pushed:
            return Color.stxAccent
        case .pushFailed:
            return Color.red
        default:
            return Color.stxAccent
        }
    }

    private var isActionPillTerminal: Bool {
        switch vm.commitState {
        case .committed, .pushed:
            return true
        default:
            return false
        }
    }

    private var commitConfirmationBinding: Binding<Bool> {
        Binding {
            pendingCommitResult != nil
        } set: { isPresented in
            if !isPresented {
                pendingCommitResult = nil
            }
        }
    }

    @ViewBuilder
    private var commitStatus: some View {
        switch vm.commitState {
        case .idle, .committing:
            EmptyView()
        case .committed(let shortHash):
            Label("Committed \(shortHash).", systemImage: AppIcon.Status.success)
                .font(.sora(10))
                .foregroundStyle(Color.stxAccent)
        case .readyToPush(let pending):
            Label("Committed \(pending.shortHash) locally.", systemImage: AppIcon.Status.success)
                .font(.sora(10))
                .foregroundStyle(Color.stxAccent)
        case .pushing:
            EmptyView()
        case .pushed(let shortHash):
            Label("Pushed \(shortHash).", systemImage: AppIcon.Status.success)
                .font(.sora(10))
                .foregroundStyle(Color.stxAccent)
        case .failed(let message):
            Label(message, systemImage: AppIcon.Status.warning)
                .font(.sora(10))
                .foregroundStyle(Color.red)
                .fixedSize(horizontal: false, vertical: true)
        case .pushFailed(let message, _):
            Label(message, systemImage: AppIcon.Status.warning)
                .font(.sora(10))
                .foregroundStyle(Color.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func generate(forceRefresh: Bool) {
        Task {
            await env.appLLMSettings.loadIfNeeded()
            do {
                let endpoint = try env.generationEndpoint()
                await vm.generate(
                    repo: repo,
                    target: target,
                    endpoint: endpoint,
                    language: outputLanguage,
                    algorithmPreference: env.appLLMSettings.gitCommitMessageAlgorithmPreference,
                    forceRefresh: forceRefresh
                )
            } catch {
                vm.fail(error.localizedDescription)
            }
        }
    }

    private func commit(_ result: GitCommitMessageResult) {
        Task {
            guard let outcome = await vm.commitAllWorkingTreeChanges(repo: repo, target: target, result: result) else { return }
            await onLocalCommitSucceeded?(outcome)
        }
    }

    private func handleActionPill(result: GitCommitMessageResult) {
        switch vm.commitState {
        case .readyToPush, .pushFailed:
            push()
        case .idle, .failed:
            pendingCommitResult = result
        default:
            break
        }
    }

    private func push() {
        Task {
            guard await vm.pushCommittedChanges(repo: repo) else { return }
            await onPushSucceeded?()
        }
    }

    private func loadCached() async {
        await env.appLLMSettings.loadIfNeeded()
        do {
            let endpoint = try env.generationEndpoint()
            await vm.loadCached(
                repo: repo,
                target: target,
                endpoint: endpoint,
                language: outputLanguage,
                algorithmPreference: env.appLLMSettings.gitCommitMessageAlgorithmPreference
            )
        } catch {
            if case .loaded = vm.state {
                vm.reset()
            }
        }
    }

    private var cacheLoadID: String {
        [
            repo.cacheKey,
            target.kind,
            target.identity,
            env.appLLMSettings.mode.rawValue,
            env.appLLMSettings.gitCommitMessageAlgorithmPreference.rawValue,
            env.preferences.appLanguagePreference.rawValue,
        ].joined(separator: "|")
    }

    private var outputLanguage: String {
        switch env.preferences.appLanguagePreference {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "Simplified Chinese"
        case .system:
            let identifier = Locale.autoupdatingCurrent.identifier.lowercased()
            return identifier.hasPrefix("zh") ? "Simplified Chinese" : "English"
        }
    }

}

private struct GitCommitMessageCopyButton: View {
    let text: String
    let label: String

    var body: some View {
        Button {
            GitCommitMessageClipboard.copy(text)
        } label: {
            Image(systemName: AppIcon.Action.copy)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
        .foregroundStyle(text.isEmpty ? Color.stxMuted.opacity(0.45) : Color.stxMuted)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.stxStroke.opacity(0.55), lineWidth: 1)
        )
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct GitCommitMessageActionPill: View {
    let label: String
    let systemImage: String
    let tint: Color
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.sora(9, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isDisabled ? AppSurface.pillForeground.opacity(0.55) : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppSurface.pillFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct GitCommitMessageContent: View {
    let result: GitCommitMessageResult

    private var title: String {
        result.commitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var bodyItems: [String] {
        result.commitBodyMarkdownItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: bodyItems.isEmpty ? 0 : 8) {
            if !title.isEmpty {
                Text(title)
                    .font(GitCommitMessageTextFont.font(for: title, size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !bodyItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(bodyItems.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 7) {
                            Circle()
                                .fill(Color.stxMuted.opacity(0.8))
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                            GitCommitMessageMarkdownText(
                                text: item,
                                size: 10,
                                color: Color.stxMuted
                            )
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GitCommitMessageMarkdownText: View {
    let text: String
    let size: CGFloat
    let weight: Font.Weight
    let color: Color

    init(
        text: String,
        size: CGFloat,
        weight: Font.Weight = .regular,
        color: Color
    ) {
        self.text = text
        self.size = size
        self.weight = weight
        self.color = color
    }

    var body: some View {
        Text(Self.attributedString(from: text, size: size, weight: weight, color: color))
    }

    private static func attributedString(
        from text: String,
        size: CGFloat,
        weight: Font.Weight,
        color: Color
    ) -> AttributedString {
        var result = AttributedString()
        for segment in segments(from: text) {
            var run = AttributedString(segment.text.addingGitCommitMessageSoftBreaks())
            if segment.isCode {
                run.font = .system(size: max(8, size - 1), weight: .medium, design: .monospaced)
                run.foregroundColor = Color.primary.opacity(0.78)
                run.backgroundColor = Color.primary.opacity(0.08)
            } else {
                run.font = GitCommitMessageTextFont.font(for: segment.text, size: size, weight: weight)
                run.foregroundColor = color
            }
            result.append(run)
        }
        return result
    }

    private static func segments(from text: String) -> [Segment] {
        var segments: [Segment] = []
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "`" {
                let contentStart = text.index(after: index)
                if let closing = text[contentStart...].firstIndex(of: "`"), closing > contentStart {
                    segments.append(Segment(text: String(text[contentStart..<closing]), isCode: true))
                    index = text.index(after: closing)
                } else {
                    segments.append(Segment(text: String(text[index...]), isCode: false))
                    break
                }
            } else {
                let nextTick = text[index...].firstIndex(of: "`") ?? text.endIndex
                segments.append(Segment(text: String(text[index..<nextTick]), isCode: false))
                index = nextTick
            }
        }

        return segments.filter { !$0.text.isEmpty }
    }

    private struct Segment {
        let text: String
        let isCode: Bool
    }
}

private enum GitCommitMessageTextFont {
    static func font(for text: String, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        containsCJK(text) ? .custom("OPPO Sans", size: size).weight(weight) : .sora(size, weight: weight)
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x20000...0x2A6DF).contains(scalar.value)
        }
    }
}

private extension String {
    func addingGitCommitMessageSoftBreaks(maxRunLength: Int = 32, chunkLength: Int = 16) -> String {
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

private struct GitCommitMessageMetadataTag: View {
    struct Tag: Identifiable {
        let label: String
        let value: String

        var id: String { "\(label)|\(value)" }
    }

    let tag: Tag

    var body: some View {
        HStack(spacing: 4) {
            Text(tag.label.uppercased())
                .font(.sora(8, weight: .semibold))
                .foregroundStyle(Color.stxMuted.opacity(0.82))
            Text(tag.value)
                .font(.sora(8, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.74))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.055)))
        .fixedSize(horizontal: true, vertical: false)
    }

    static func tags(for result: GitCommitMessageResult) -> [Tag] {
        [
            Tag(label: "algorithm", value: result.algorithm.title),
            Tag(label: "model", value: result.modelName),
            Tag(label: "calls", value: "\(result.usage.requestCount)"),
            Tag(label: "in", value: Format.tokens(result.usage.inputTokens)),
            Tag(label: "out", value: Format.tokens(result.usage.outputTokens)),
            Tag(label: "total", value: Format.tokens(result.usage.totalTokens)),
        ]
    }
}

private struct GitCommitMessageMetadataFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(proposal: proposal, subviews: subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * rowSpacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if nextWidth > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.items.append(Item(index: index, size: size))
            current.width = current.items.count == 1 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private struct Item {
        var index: Int
        var size: CGSize
    }
}

private enum GitCommitMessageClipboard {
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
