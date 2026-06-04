import AppKit
import SwiftUI

struct GitCommitMessageCard: View {
    @Environment(AppEnvironment.self) private var env

    let repo: GitRepo
    let target: GitCommitMessageTarget

    @State private var vm = GitCommitMessageViewModel()

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
            .disabled(isLoading)

            if result != nil {
                Button {
                    generate(forceRefresh: true)
                } label: {
                    Label("Refresh", systemImage: AppIcon.Action.refresh)
                }
                .controlSize(.small)
                .disabled(isLoading)
            }

        }
    }

    private var isLoading: Bool {
        if case .loading = vm.state { return true }
        return false
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

private struct GitCommitMessageContent: View {
    let result: GitCommitMessageResult

    private var title: String {
        result.commitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var bodyItems: [String] {
        Self.bodyItems(from: result.commitBody)
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
                        HStack(alignment: .top, spacing: 6) {
                            Text("-")
                                .font(GitCommitMessageTextFont.font(for: item, size: 10, weight: .medium))
                                .foregroundStyle(Color.stxMuted)
                                .padding(.top, 1)
                            Text(item)
                                .font(GitCommitMessageTextFont.font(for: item, size: 10))
                                .foregroundStyle(Color.stxMuted)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func bodyItems(from rawBody: String) -> [String] {
        let normalized = rawBody
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { cleanedBodyItem(String($0)) }
            .filter { !$0.isEmpty }
        if lines.count != 1 {
            return lines
        }
        return sentenceItems(from: lines[0])
    }

    private static func cleanedBodyItem(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["- ", "* ", "• "] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func sentenceItems(from value: String) -> [String] {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let separators = CharacterSet(charactersIn: ".!?。！？")
        var items: [String] = []
        var start = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            let scalarText = String(text[index])
            if scalarText.rangeOfCharacter(from: separators) != nil {
                let item = String(text[start..<next]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !item.isEmpty {
                    items.append(item)
                }
                start = next
                while start < text.endIndex, text[start].isWhitespace {
                    start = text.index(after: start)
                }
                index = start
            } else {
                index = next
            }
        }

        let tail = String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            items.append(tail)
        }
        return items.count > 1 ? items : [text]
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
