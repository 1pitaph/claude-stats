import SwiftUI
import AppKit

/// Detail pane shown when the user picks a session from the sidebar tree.
/// The layout uses the same `StatCard` + `ModelTable` visual language as the
/// Dashboard so the main window reads as one coherent surface.
///
/// Values are read fresh from the session every render — no view model, since
/// the underlying stats are already cached on ``Session/stats`` by
/// ``SessionStore``. If `stats` is `nil` (transcript hasn't been parsed yet
/// or failed to parse), the view shows a thin placeholder.
struct SessionDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let session: Session
    @State private var transcriptMessages: [SessionTranscriptMessage] = []
    @State private var transcriptIsLoading = false
    @State private var similarSessions: [SemanticSessionSearchResult] = []
    @State private var similarSessionsLoading = false

    init(session: Session) {
        self.session = session
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let stats = session.stats {
                statCards(stats)
                modelBreakdown(stats)
            } else {
                missingStatsPlaceholder
            }

            analysisInsightsSection
            similarSessionsSection
            transcriptSection
            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: session.id) {
            await loadTranscript()
            env.transcriptAnalysis.loadIfNeeded(
                provider: session.provider,
                sessions: env.store.sessions(for: session.provider),
                messageLoader: env.store.transcriptMessageLoader(for: session.provider)
            )
            await loadSimilarSessions()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.stxMuted)
                Text(session.projectDisplayName)
                    .font(.sora(11, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Color.stxMuted)
            }

            Text(session.stats?.title.nonEmpty ?? session.externalID)
                .font(.sora(22, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let cwd = session.cwd, !cwd.isEmpty {
                Text(cwd)
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Stat cards

    @ViewBuilder
    private func statCards(_ stats: SessionStats) -> some View {
        let includeCache = env.preferences.includeCacheInTokens
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatCard(label: L10n.string("session.stat.total_tokens", defaultValue: "TOTAL TOKENS"),
                         value: Format.tokens(stats.totalTokens(includingCacheRead: includeCache)))
                StatCard(label: L10n.string("session.stat.estimated_cost", defaultValue: "ESTIMATED COST"),
                         value: Format.cost(stats.totalCost(for: env.preferences.costEstimationMode)))
                StatCard(label: L10n.string("session.stat.messages", defaultValue: "MESSAGES"),
                         value: "\(stats.messageCount)")
                StatCard(label: L10n.string("session.stat.last_activity", defaultValue: "LAST ACTIVITY"),
                         value: Format.relativeDate(stats.lastActivity ?? session.lastModified),
                         animatesNumericValue: false)
            }
        }
    }

    // MARK: - Model breakdown

    @ViewBuilder
    private func modelBreakdown(_ stats: SessionStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BY MODEL")
                .font(.sora(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.stxMuted)
            ModelTable(
                models: stats.models,
                includeCacheInTotals: env.preferences.includeCacheInTokens,
                displayName: { env.store.displayName(forModel: $0, provider: session.provider) }
            )
        }
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CONVERSATION")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.stxMuted)

                Spacer(minLength: 0)

                if transcriptIsLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                } else if !transcriptMessages.isEmpty {
                    Text(L10n.messageCount(transcriptMessages.count))
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
            }

            if transcriptIsLoading && transcriptMessages.isEmpty {
                transcriptPlaceholder(L10n.string("session.transcript.loading",
                                                  defaultValue: "Loading transcript…"))
            } else if transcriptMessages.isEmpty {
                transcriptPlaceholder(L10n.string("session.transcript.empty",
                                                  defaultValue: "No readable conversation content found in this transcript."))
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(transcriptRows) { row in
                        TranscriptMessageRow(
                            message: row.message,
                            modelDisplayName: row.message.model.map {
                                env.store.displayName(forModel: $0, provider: session.provider)
                            }
                        )
                    }
                }
            }
        }
    }

    private var transcriptRows: [TranscriptMemoryRow] {
        transcriptMessages.enumerated().map { offset, message in
            TranscriptMemoryRow(
                id: "\(offset)-\(message.id)",
                message: message
            )
        }
    }

    private func transcriptPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.sora(12))
            .foregroundStyle(Color.stxMuted)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSurface(.compactCard(radius: 8), padding: nil)
    }

    private func loadTranscript() async {
        transcriptIsLoading = true
        let messages = await env.store.transcriptMessages(for: session)
        guard !Task.isCancelled else { return }
        transcriptMessages = messages
        transcriptIsLoading = false
    }

    // MARK: - Similar sessions

    @ViewBuilder
    private var similarSessionsSection: some View {
        if env.localAI.semanticSearchAvailable {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SIMILAR SESSIONS")
                        .font(.sora(10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Color.stxMuted)
                    Spacer(minLength: 0)
                    if similarSessionsLoading {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.72)
                    }
                }

                let sessionsByID = Dictionary(uniqueKeysWithValues: env.store.sessions(for: session.provider).map { ($0.id, $0) })
                let rows = similarSessions.compactMap { result -> SimilarSessionRowData? in
                    guard let related = sessionsByID[result.sessionID] else { return nil }
                    return SimilarSessionRowData(session: related, result: result)
                }

                if rows.isEmpty && !similarSessionsLoading {
                    Text("No close matches yet.")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appSurface(.compactCard(radius: 8), padding: nil)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            SimilarSessionResultRow(row: row)
                            if row.id != rows.last?.id {
                                Divider().overlay(Color.stxStroke)
                            }
                        }
                    }
                    .padding(12)
                    .appSurface(.compactCard(radius: 8), padding: nil)
                }
            }
        }
    }

    private func loadSimilarSessions() async {
        guard env.localAI.semanticSearchAvailable else {
            similarSessions = []
            similarSessionsLoading = false
            return
        }
        similarSessionsLoading = true
        let results = await env.localAI.similarSessions(
            to: session,
            providerSessions: env.store.sessions(for: session.provider),
            messageLoader: env.store.transcriptMessageLoader(for: session.provider)
        )
        guard !Task.isCancelled else { return }
        similarSessions = results
        similarSessionsLoading = false
    }

    // MARK: - Analysis

    @ViewBuilder
    private var analysisInsightsSection: some View {
        if let analysis = env.transcriptAnalysis.sessionAnalysis(for: session.id, provider: session.provider),
           !analysis.topTerms.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("INSIGHTS")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.stxMuted)

                VStack(alignment: .leading, spacing: 12) {
                    insightGroup("Top terms", terms: Array(analysis.topTerms.prefix(8)))
                    if !analysis.fileTerms.isEmpty {
                        insightGroup("Files", terms: analysis.fileTerms)
                    }
                    if !analysis.commandTerms.isEmpty {
                        insightGroup("Commands", terms: analysis.commandTerms)
                    }
                    if !analysis.errorTerms.isEmpty {
                        insightGroup("Errors", terms: analysis.errorTerms)
                    }
                }
                .padding(12)
                .appSurface(.compactCard(radius: 8), padding: nil)
            }
        } else if env.transcriptAnalysis.isLoading(for: session.provider) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
                Text("Analyzing terms...")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
        }
    }

    private func insightGroup(_ title: String, terms: [TranscriptSessionTerm]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.sora(9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.stxMuted)
            TranscriptInsightFlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(terms, id: \.chipID) { term in
                    Text(term.displayName)
                        .font(.sora(10, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }

    // MARK: - Missing stats placeholder

    private var missingStatsPlaceholder: some View {
        Text(L10n.string("session.stats.not_parsed",
                         defaultValue: "Transcript stats haven't been parsed yet."))
            .font(.sora(12))
            .foregroundStyle(Color.stxMuted)
            .appSurface(.mainWindowCard, padding: 16)
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.filePath)])
            } label: {
                Label("Reveal Transcript", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)

            if let cwd = session.cwd, FileManager.default.fileExists(atPath: cwd) {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                } label: {
                    Label("Open Project Folder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)
        }
        .font(.sora(11))
    }
}

private struct SimilarSessionRowData: Identifiable {
    let session: Session
    let result: SemanticSessionSearchResult

    var id: String { session.id }
}

private struct SimilarSessionResultRow: View {
    let row: SimilarSessionRowData

    private var title: String {
        row.session.stats?.title.nonEmpty ?? row.session.externalID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.sora(11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(String(format: "%.2f", row.result.score))
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
            Text(row.result.matchedExcerpt)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(2)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TranscriptMemoryRow: Identifiable {
    let id: String
    let message: SessionTranscriptMessage
}

private struct TranscriptMessageRow: View {
    let message: SessionTranscriptMessage
    let modelDisplayName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(message.role.displayName, systemImage: message.role.symbol)
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(message.role.accentColor)

                if let modelDisplayName {
                    Text(modelDisplayName)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }

                Spacer(minLength: 0)

                if let timestamp = message.timestamp {
                    Text(Format.shortDate(timestamp))
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }

                Button {
                    copyToPasteboard(message.text)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .controlSize(.small)
                .help("Copy text")
            }

            Text(message.text)
                .font(.sora(12))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8), padding: nil)
    }
}

private func copyToPasteboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}

private extension SessionTranscriptMessage.Role {
    var symbol: String {
        switch self {
        case .user: "person"
        case .assistant: "sparkles"
        case .tool: "wrench.and.screwdriver"
        case .system: "gearshape"
        }
    }

    var accentColor: Color {
        switch self {
        case .user: .stxAccent
        case .assistant: .primary
        case .tool: .stxMuted
        case .system: .stxMuted
        }
    }
}

private struct TranscriptInsightFlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6

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

private extension TranscriptSessionTerm {
    var chipID: String { "\(kind.rawValue)-\(canonical)" }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

#if DEBUG
#Preview {
    SessionDetailView(session: Session.previewSamples.first!)
        .environment(AppEnvironment.preview())
        .padding(24)
        .frame(width: 760, height: 600)
        .background(Color.stxBackground)
}
#endif
