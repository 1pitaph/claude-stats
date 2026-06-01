import SwiftUI

struct DailyReportProjectGitDetailSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let selection: DailyReportProjectGitSheetSelection

    @State private var vm = DailyReportProjectGitSheetViewModel()
    @State private var generationTask: Task<Void, Never>?
    @AppStorage("dailyReport.gitSummaryInputMode") private var inputModeRaw = DailyReportGitSummaryInputMode.diffAware.rawValue

    var body: some View {
        VStack(spacing: 0) {
            header
            StxRule()
            content
        }
        .frame(minWidth: 1_000, idealWidth: 1_140, minHeight: 620, idealHeight: 720)
        .background(AppSurface.panelFill)
        .task(id: loadTaskID) {
            await loadSheet()
        }
        .onDisappear {
            generationTask?.cancel()
        }
    }

    private var loadTaskID: String {
        "\(selection.id)|\(inputMode.rawValue)"
    }

    private var inputMode: DailyReportGitSummaryInputMode {
        DailyReportGitSummaryInputMode(rawValue: inputModeRaw) ?? .diffAware
    }

    private var inputModeBinding: Binding<DailyReportGitSummaryInputMode> {
        Binding {
            inputMode
        } set: { next in
            inputModeRaw = next.rawValue
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: AppIcon.Action.close)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close git detail")

            Image(systemName: AppIcon.Workspace.dailyReport)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.stxAccent)
                .frame(width: 26, height: 26)
                .background(Color.stxAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(selection.project.displayName)
                    .font(.sora(14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(selection.project.displayName)
                HStack(spacing: 7) {
                    DailyReportGitSheetInfoPill(symbol: AppIcon.Workspace.dailyReport, text: selection.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))
                    if let repo = vm.snapshot?.repo {
                        DailyReportGitSheetInfoPill(symbol: AppIcon.Workspace.git, text: repo.displayName)
                        DailyReportGitSheetInfoPill(symbol: AppIcon.Navigation.forward, text: repo.currentBranch ?? "HEAD")
                    } else if let path = selection.project.path {
                        DailyReportGitSheetInfoPill(symbol: AppIcon.Resource.folder, text: path)
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            DailyReportGitSummaryModeChips(mode: inputModeBinding)

            DailyReportGitSheetGenerateButton(
                title: vm.summary == nil ? "Generate" : "Regenerate",
                disabled: !vm.canGenerate,
                action: startGenerate
            )
            .help(generateHelp)

            if vm.isLoadingCommits || vm.isGeneratingSummary {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            commitsPanel
                .frame(width: 430, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)
            summaryPanel
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
    }

    private var commitsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader(title: "COMMITS", badge: commitBadge)
            AppScrollView {
                commitTimeline
                    .padding(.trailing, 4)
            }
        }
        .mainWindowPanel(padding: 14)
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader(title: "LLM SUMMARY", badge: summaryBadge)
            AppScrollView {
                summaryContent
                    .padding(.trailing, 4)
            }
        }
        .mainWindowPanel(padding: 14)
    }

    @ViewBuilder
    private var commitTimeline: some View {
        switch vm.commitState {
        case .idle, .loading:
            DailyReportGitSheetEmptyState(
                symbol: AppIcon.Status.clock,
                title: "Loading commits",
                detail: "Reading git history for the selected day."
            )
        case .failed(let message):
            DailyReportGitSheetEmptyState(
                symbol: AppIcon.Status.warning,
                title: "Could not load commits",
                detail: message
            )
        case .loaded(let snapshot):
            if let message = snapshot.statusMessage {
                DailyReportGitSheetEmptyState(
                    symbol: AppIcon.Workspace.git,
                    title: "No git repository",
                    detail: message
                )
            } else if snapshot.commits.isEmpty {
                DailyReportGitSheetEmptyState(
                    symbol: AppIcon.Workspace.git,
                    title: "No commits",
                    detail: "No matching non-merge commits were found for this project on this day."
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let lastID = snapshot.commits.last?.id
                    ForEach(snapshot.commits) { commit in
                        DailyReportGitCommitTimelineRow(
                            commit: commit,
                            isLast: commit.id == lastID
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var summaryContent: some View {
        if let readiness = vm.llmReadinessMessage, vm.summary == nil, !vm.isGeneratingSummary {
            DailyReportGitSheetEmptyState(
                symbol: AppIcon.Feature.ai,
                title: "LLM not ready",
                detail: readiness
            )
        }

        switch vm.summaryState {
        case .idle:
            if vm.llmReadinessMessage == nil {
                DailyReportGitSheetEmptyState(
                    symbol: AppIcon.Feature.ai,
                    title: "Ready to summarize",
                    detail: idleSummaryDetail
                )
            }
        case .loading:
            DailyReportGitSheetEmptyState(
                symbol: AppIcon.Feature.ai,
                title: "Summarizing",
                detail: "Generating with \(env.appLLMSettings.mode.title)."
            )
        case .failed(let message):
            DailyReportGitSheetEmptyState(
                symbol: AppIcon.Status.warning,
                title: "Summary failed",
                detail: message
            )
        case .loaded(let summary):
            DailyReportGitSummaryBody(summary: summary)
        }
    }

    private func panelHeader(title: String, badge: String?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.sora(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            Spacer(minLength: 8)
            if let badge {
                AIConfigsBadge(text: badge, color: Color.stxMuted)
            }
        }
    }

    private var commitBadge: String? {
        guard case .loaded(let snapshot) = vm.commitState else { return nil }
        return "\(snapshot.commitCount) commits"
    }

    private var summaryBadge: String? {
        guard let summary = vm.summary else { return nil }
        return summary.isCached ? "cached" : "generated"
    }

    private var idleSummaryDetail: String {
        guard vm.canGenerate else {
            return "Load a git-backed project with commits before generating a summary."
        }
        switch inputMode {
        case .diffAware:
            return "Generate a cached summary from commit metadata and capped diff excerpts."
        case .metadataOnly:
            return "Generate a cached summary from commit messages and file statistics."
        }
    }

    private var generateHelp: String {
        if vm.summary == nil { return "Generate a git summary for this day" }
        return "Regenerate the cached git summary"
    }

    private func loadSheet() async {
        await vm.loadCommits(project: selection.project, day: selection.day, calendar: .current)
        let resolved = await resolveEndpoint()
        await vm.loadCachedSummary(
            endpoint: resolved.endpoint,
            endpointError: resolved.error,
            language: outputLanguage,
            inputMode: inputMode
        )
    }

    private func startGenerate() {
        generationTask?.cancel()
        generationTask = Task {
            await env.appLLMSettings.loadIfNeeded()
            do {
                let endpoint = try env.generationEndpoint()
                await vm.generate(
                    endpoint: endpoint,
                    language: outputLanguage,
                    inputMode: inputMode,
                    forceRefresh: vm.summary != nil
                )
            } catch {
                vm.failSummary(error.localizedDescription)
            }
        }
    }

    private func resolveEndpoint() async -> (endpoint: AppLLMGenerationEndpoint?, error: String?) {
        await env.appLLMSettings.loadIfNeeded()
        do {
            return (try env.generationEndpoint(), nil)
        } catch {
            return (nil, error.localizedDescription)
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

private struct DailyReportGitSummaryModeChips: View {
    @Binding var mode: DailyReportGitSummaryInputMode

    var body: some View {
        PillSegmentedBar(
            DailyReportGitSummaryInputMode.allCases,
            selection: $mode,
            help: { option in
                switch option {
                case .diffAware:
                    "Include capped diff excerpts in the generated summary"
                case .metadataOnly:
                    "Use commit messages and file statistics only"
                }
            },
            accessibilityLabel: { $0.title }
        ) { value, _ in
            Text(value.title)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Summary input mode")
    }
}

private struct DailyReportGitSheetGenerateButton: View {
    let title: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.sora(12, weight: .medium))
                .lineLimit(1)
                .frame(minWidth: 92)
                .frame(height: PillTimeStepperBarStyle.standard.totalHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .foregroundStyle(disabled ? Color.stxMuted.opacity(0.55) : Color.primary)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(disabled ? 0.035 : 0.06))
        )
        .accessibilityLabel(title)
    }
}

private struct DailyReportGitCommitTimelineRow: View {
    let commit: DailyReportGitDayCommit
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.stxAccent)
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
                if !isLast {
                    Rectangle()
                        .fill(Color.stxStroke.opacity(0.8))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(commit.authorDate.formatted(.dateTime.hour().minute()))
                        .font(.sora(10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                    Text(commit.shortHash)
                        .font(.sora(10).monospaced())
                        .foregroundStyle(Color.stxAccent)
                    Spacer(minLength: 8)
                    Text("+\(commit.insertions) -\(commit.deletions)")
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }

                Text(commit.subject)
                    .font(.sora(12, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !commit.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(commit.body)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    DailyReportGitSheetInfoPill(symbol: AppIcon.Resource.document, text: "\(commit.filesChanged) files")
                    DailyReportGitSheetInfoPill(symbol: AppIcon.Resource.key, text: commit.authorName)
                }
            }
            .padding(.bottom, isLast ? 0 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DailyReportGitSummaryBody: View {
    let summary: DailyReportGitDayLLMSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DailyReportGitSummaryFlowLayout(spacing: 5, rowSpacing: 5) {
                AIConfigsBadge(text: summary.inputMode.title, color: Color.stxMuted)
                AIConfigsBadge(text: summary.modelName, color: Color.stxMuted)
                AIConfigsBadge(text: "\(summary.usage.totalTokens) tok", color: Color.stxMuted)
                AIConfigsBadge(text: summary.generatedAt.formatted(.dateTime.hour().minute()), color: Color.stxMuted)
            }

            Text(summary.summary)
                .font(.sora(12))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !summary.keyChanges.isEmpty {
                DailyReportGitSummaryList(title: "KEY CHANGES", rows: summary.keyChanges)
            }

            if !summary.risksOrNotes.isEmpty {
                DailyReportGitSummaryList(title: "RISKS / NOTES", rows: summary.risksOrNotes)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DailyReportGitSummaryList: View {
    let title: String
    let rows: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.sora(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(Color.stxMuted.opacity(0.8))
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)
                        Text(row)
                            .font(.sora(11))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct DailyReportGitSheetInfoPill: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(.sora(10))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.055)))
    }
}

private struct DailyReportGitSheetEmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            Text(title)
                .font(.sora(14, weight: .semibold))
            Text(detail)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

private struct DailyReportGitSummaryFlowLayout: Layout {
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

#if DEBUG
#Preview("Daily Report git sheet") {
    let project = DailyReportProjectDaySummary(
        id: "/Users/dev/app",
        displayName: "app",
        path: "/Users/dev/app",
        providers: [.codex],
        activeDuration: 3_600,
        tokens: 42_000,
        sessionCount: 2,
        gitCommitCount: 3,
        latestActivity: .now
    )
    DailyReportProjectGitDetailSheet(selection: DailyReportProjectGitSheetSelection(project: project, day: .now))
        .environment(AppEnvironment.preview())
}
#endif
