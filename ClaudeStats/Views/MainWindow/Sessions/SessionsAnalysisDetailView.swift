import SwiftUI

struct SessionsAnalysisDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selectedKind: TranscriptTermKind?
    @State private var latestDictionarySignature: String?

    private var provider: ProviderKind { env.preferences.selectedProvider }
    private var sessions: [Session] { env.store.sessions(for: provider) }
    private var snapshot: TranscriptAnalysisSnapshot? { env.transcriptAnalysis.snapshot(for: provider) }
    private var progress: TranscriptAnalysisProgress { env.transcriptAnalysis.progress(for: provider) }

    private var taskID: String {
        "\(provider.rawValue)-\(sessions.count)-\(Int(env.store.lastRefreshedAt?.timeIntervalSince1970 ?? 0))-\(env.technicalTerms.revision)"
    }

    private var dictionaryNeedsRefresh: Bool {
        guard let snapshot, let latestDictionarySignature else { return false }
        return snapshot.dictionarySignature != latestDictionarySignature
    }

    private var filteredTerms: [TranscriptTermStats] {
        let terms = snapshot?.terms ?? []
        guard let selectedKind else { return Array(terms.prefix(40)) }
        return Array(terms.filter { $0.kind == selectedKind }.prefix(40))
    }

    var body: some View {
        CenteredPaneContainer {
            VStack(alignment: .leading, spacing: 18) {
                header

                if env.transcriptAnalysis.isLoading(for: provider) && snapshot == nil {
                    loadingState
                } else if let snapshot {
                    if env.transcriptAnalysis.isLoading(for: provider) {
                        loadingState
                    }
                    statsGrid(snapshot)
                    runSummaryCard(snapshot)
                    engineCard(snapshot)
                    if dictionaryNeedsRefresh {
                        dictionaryRefreshBanner
                    }
                    SemanticVisualizationShowcase(analysis: snapshot, sessions: sessions)
                    kindFilters(snapshot)
                    termsSection(snapshot)
                    examplesSection(snapshot)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: taskID) {
            env.transcriptAnalysis.loadIfNeeded(
                provider: provider,
                sessions: sessions,
                messageLoader: env.store.transcriptMessageLoader(for: provider)
            )
            latestDictionarySignature = await env.technicalTerms.corpusSignature(for: sessions)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: AppIcon.Resource.textSearch)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(provider.accentColor)
                Text("ANALYSIS")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
            }

            Text("\(provider.shortName) session terms")
                .font(.sora(24, weight: .semibold))

            Text("Evidence-based changed topics, technical vocabulary, files, commands, and errors across discovered sessions.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
        }
    }

    private var dictionaryRefreshBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: AppIcon.Resource.dictionary)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(provider.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dictionary changed.")
                    .font(.sora(12, weight: .semibold))
                Text("Refresh analysis to apply the updated technical terms.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 0)
            Button {
                env.transcriptAnalysis.reload(
                    provider: provider,
                    sessions: sessions,
                    messageLoader: env.store.transcriptMessageLoader(for: provider)
                )
                Task {
                    latestDictionarySignature = await env.technicalTerms.corpusSignature(for: sessions)
                }
            } label: {
                Label("Refresh Analysis", systemImage: AppIcon.Action.refresh)
            }
            .buttonStyle(.borderedProminent)
            .disabled(env.transcriptAnalysis.isLoading(for: provider))
            .font(.sora(11))
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8), padding: nil)
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(progress.phase.displayName)
                    .font(.sora(12, weight: .semibold))
                Spacer(minLength: 0)
                if progress.total > 0 {
                    Text("\(progress.completed)/\(progress.total)")
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }
            }
            if progress.total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .progressViewStyle(.linear)
            }
            if let title = progress.currentSessionTitle {
                Text(title)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .appSurface(.compactCard(radius: 8), padding: nil)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Analysis Yet", systemImage: AppIcon.Resource.textSearch)
        } description: {
            Text(sessions.isEmpty ? "No sessions are available for \(provider.shortName)." : "Open this page again after transcripts finish scanning.")
        } actions: {
            Button("Analyze Now") {
                env.transcriptAnalysis.reload(
                    provider: provider,
                    sessions: sessions,
                    messageLoader: env.store.transcriptMessageLoader(for: provider)
                )
            }
            .disabled(env.transcriptAnalysis.isLoading(for: provider))
        }
        .font(.sora(12))
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func statsGrid(_ snapshot: TranscriptAnalysisSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatCard(label: "ANALYZED", value: "\(snapshot.analyzedSessionCount)")
                    StatCard(label: "TERMS", value: "\(snapshot.terms.count)")
                    StatCard(label: "ENGINE", value: snapshot.engine.displayName, animatesNumericValue: false)
                    StatCard(label: "EMBEDDING", value: snapshot.engine.embeddingStatus.displayName, animatesNumericValue: false)
                }
            }

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatCard(label: "ANALYZED", value: "\(snapshot.analyzedSessionCount)")
                    StatCard(label: "TERMS", value: "\(snapshot.terms.count)")
                }
                GridRow {
                    StatCard(label: "ENGINE", value: snapshot.engine.displayName, animatesNumericValue: false)
                    StatCard(label: "EMBEDDING", value: snapshot.engine.embeddingStatus.displayName, animatesNumericValue: false)
                }
            }
        }
    }

    private func runSummaryCard(_ snapshot: TranscriptAnalysisSnapshot) -> some View {
        let summary = snapshot.runSummary
        return HStack(spacing: 10) {
            CacheMetric(label: "REUSED", value: summary.reused)
            CacheMetric(label: "NEW", value: summary.newCount)
            CacheMetric(label: "CHANGED", value: summary.changed)
            CacheMetric(label: "EMPTY", value: summary.empty)
            CacheMetric(label: "DELETED", value: summary.deleted)
            Spacer(minLength: 0)
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8), padding: nil)
    }

    private func engineCard(_ snapshot: TranscriptAnalysisSnapshot) -> some View {
        let cacheStatus = snapshot.runSummary.indexUpdatedAt == .distantPast
            ? "SQLite cache ready"
            : "SQLite cache updated \(Format.relativeDate(snapshot.runSummary.indexUpdatedAt))"
        return HStack(spacing: 12) {
            Image(systemName: AppIcon.Workspace.system)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(provider.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.engine.displayName)
                    .font(.sora(12, weight: .semibold))
                Text("Dictionary \(snapshot.engine.dictionaryVersion) - \(cacheStatus)")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 0)
            Button {
                env.transcriptAnalysis.reload(
                    provider: provider,
                    sessions: sessions,
                    messageLoader: env.store.transcriptMessageLoader(for: provider)
                )
            } label: {
                Label("Refresh", systemImage: AppIcon.Action.refresh)
            }
            .buttonStyle(.bordered)
            .disabled(env.transcriptAnalysis.isLoading(for: provider))
            .font(.sora(11))
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8), padding: nil)
    }

    private func kindFilters(_ snapshot: TranscriptAnalysisSnapshot) -> some View {
        let kinds = TranscriptTermKind.allCases.filter { kind in
            snapshot.terms.contains { $0.kind == kind }
        }
        return TermKindFilterFlowLayout(spacing: 8, rowSpacing: 8) {
            termFilterButton(title: "All", symbol: AppIcon.Resource.tag, isSelected: selectedKind == nil) {
                selectedKind = nil
            }
            ForEach(kinds) { kind in
                termFilterButton(title: kind.displayName, symbol: kind.symbol, isSelected: selectedKind == kind) {
                    selectedKind = kind
                }
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func termFilterButton(title: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.sora(11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(isSelected ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func termsSection(_ snapshot: TranscriptAnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOP TERMS")
                .font(.sora(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.stxMuted)

            VStack(spacing: 0) {
                ForEach(filteredTerms) { term in
                    TermRow(term: term)
                    if term.id != filteredTerms.last?.id { Divider().opacity(0.35) }
                }
            }
            .appSurface(.compactCard(radius: 10), padding: nil)
        }
    }

    @ViewBuilder
    private func examplesSection(_ snapshot: TranscriptAnalysisSnapshot) -> some View {
        let examples = Array(snapshot.terms.flatMap(\.examples).prefix(8))
        if !examples.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("EXAMPLES")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.stxMuted)
                VStack(spacing: 0) {
                    ForEach(examples) { example in
                        ExampleRow(example: example)
                        if example.id != examples.last?.id { Divider().opacity(0.35) }
                    }
                }
                .appSurface(.compactCard(radius: 10), padding: nil)
            }
        }
    }
}

private struct TermKindFilterFlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct CacheMetric: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.sora(8, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.stxMuted)
            Text("\(value)")
                .font(.sora(14, weight: .semibold).monospacedDigit())
        }
        .frame(minWidth: 58, alignment: .leading)
    }
}

private struct TermRow: View {
    let term: TranscriptTermStats

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: term.kind.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(term.displayName)
                        .font(.sora(12, weight: .semibold))
                        .lineLimit(1)
                    Text(term.kind.displayName)
                        .font(.sora(9, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                }
                Text("freq \(term.frequency) - sessions \(term.documentFrequency) - score \(String(format: "%.1f", term.tfidf))")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct ExampleRow: View {
    let example: TranscriptTermExample

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(example.sessionTitle)
                    .font(.sora(11, weight: .semibold))
                    .lineLimit(1)
                Text(example.role.displayName)
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 0)
                if let timestamp = example.timestamp {
                    Text(Format.shortDate(timestamp))
                        .font(.sora(9).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }
            }
            Text(example.excerpt)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

#if DEBUG
#Preview("Sessions analysis") {
    SessionsAnalysisDetailView()
        .environment(AppEnvironment.preview())
        .frame(width: 760, height: 640)
        .background(Color.stxBackground)
}
#endif
