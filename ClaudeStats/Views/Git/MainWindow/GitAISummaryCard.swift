import AppKit
import SwiftUI

struct GitAISummaryCard: View {
    @Environment(AppEnvironment.self) private var env

    let repo: GitRepo
    let target: GitSummaryTarget

    @State private var vm = GitAISummaryViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .padding(12)
        .appSurface(.compactCard(radius: 10))
        .task {
            await env.appLLMSettings.loadIfNeeded()
        }
        .onChange(of: target.identity) { _, _ in
            vm.reset()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("AI SUMMARY")
                .font(.sora(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            if case .loaded(let result) = vm.state {
                GitAISummaryCopyButton(
                    markdown: result.markdown,
                    label: "Copy AI summary as Markdown"
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
                Text("Generate a cached LLM summary for this diff.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                controls(result: nil)
            }
        case .loading:
            Text("Summarizing diff with \(env.appLLMSettings.mode.title)...")
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
                if !result.summary.isEmpty {
                    Text(result.summary)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !result.keyChanges.isEmpty {
                    GitAISummaryList(title: "KEY CHANGES", rows: result.keyChanges)
                }
                if !result.risksOrNotes.isEmpty {
                    GitAISummaryList(title: "RISKS / NOTES", rows: result.risksOrNotes)
                }
                if let verifierNotes = result.verifierNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !verifierNotes.isEmpty {
                    GitAISummaryList(title: "VERIFIER NOTES", rows: [verifierNotes])
                }
                if !result.commitTitle.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("COMMIT MESSAGE")
                            .font(.sora(9, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(Color.stxMuted)
                        Text(result.commitMessage)
                            .font(.sora(10).monospaced())
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                controls(result: result)
            }
        }
    }

    private func metadata(_ result: GitAISummaryResult) -> some View {
        GitSummaryFlowLayout(spacing: 5, rowSpacing: 5) {
            StatusSeverityBadge(label: result.algorithm.title, indicatorTint: Color.stxMuted)
            StatusSeverityBadge(label: result.modelName, indicatorTint: Color.stxMuted)
            StatusSeverityBadge(label: "\(result.usage.totalTokens) tok", indicatorTint: Color.stxMuted)
            ForEach(result.riskLabels.prefix(5)) { label in
                StatusSeverityBadge(label: label.title, indicatorTint: label.score >= 6 ? Color.orange : Color.stxMuted)
            }
        }
    }

    private func controls(result: GitAISummaryResult?) -> some View {
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
                    forceRefresh: forceRefresh
                )
            } catch {
                vm.fail(error.localizedDescription)
            }
        }
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

private struct GitAISummaryList: View {
    let title: String
    let rows: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.sora(9, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Color.stxMuted)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(Color.stxMuted.opacity(0.8))
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)
                        Text(row)
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct GitAISummaryCopyButton: View {
    let markdown: String
    let label: String

    var body: some View {
        Button {
            GitAISummaryClipboard.copy(markdown)
        } label: {
            Image(systemName: AppIcon.Action.copy)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(markdown.isEmpty)
        .foregroundStyle(markdown.isEmpty ? Color.stxMuted.opacity(0.45) : Color.stxMuted)
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

private enum GitAISummaryClipboard {
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct GitSummaryFlowLayout: Layout {
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
