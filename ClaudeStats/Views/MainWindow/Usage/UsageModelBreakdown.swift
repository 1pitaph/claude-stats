import SwiftUI

struct UsageModelBreakdown: View {
    let models: [ModelUsage]
    let series: TrendSeries
    let seriesID: String
    let includeCacheInTokens: Bool
    let costEstimationMode: CostEstimationMode
    let displayName: (String) -> String
    @State private var cachedSnapshotKey: UsageModelBreakdownSnapshot.Key?
    @State private var cachedSnapshot: UsageModelBreakdownSnapshot?

    var body: some View {
        let key = UsageModelBreakdownSnapshot.Key(
            seriesID: seriesID,
            includeCacheInTokens: includeCacheInTokens,
            costEstimationMode: costEstimationMode,
            modelsRevisionID: models.dataRevisionID,
            seriesRevisionID: series.dataRevisionID
        )
        let snapshot = cachedSnapshotKey == key
            ? (cachedSnapshot ?? makeSnapshot(key: key))
            : makeSnapshot(key: key)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("BY MODEL")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer()
                Text("Tokens · Cost · Share")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            if snapshot.rows.isEmpty {
                Text("No model data in this range.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, minHeight: 98, alignment: .center)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(snapshot.rows.enumerated()), id: \.element.id) { index, row in
                        UsageModelRow(row: row)
                        if index < snapshot.rows.count - 1 {
                            StxRule()
                        }
                    }
                }
            }
        }
        .mainUsagePanel(padding: 16)
        .onAppear { cacheSnapshotIfNeeded(key) }
        .onChange(of: key) { _, newKey in cacheSnapshotIfNeeded(newKey) }
    }

    private func makeSnapshot(key: UsageModelBreakdownSnapshot.Key) -> UsageModelBreakdownSnapshot {
        UsageModelBreakdownSnapshot(
            key: key,
            models: models,
            series: series,
            displayName: displayName
        )
    }

    private func cacheSnapshotIfNeeded(_ key: UsageModelBreakdownSnapshot.Key) {
        guard cachedSnapshotKey != key else { return }
        cachedSnapshot = makeSnapshot(key: key)
        cachedSnapshotKey = key
    }
}

private struct UsageModelRow: View {
    let row: UsageModelBreakdownSnapshot.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ModelPalette.color(at: row.colorIndex))
                    .frame(width: 10, height: 10)
                Text(row.displayName)
                    .font(.sora(13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                Text(row.totalText)
                    .font(.sora(12, weight: .semibold).monospacedDigit())
                    .stxNumericValueTransition(value: row.totalText)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 72, alignment: .trailing)
                Text(row.costText)
                    .font(.sora(12).monospacedDigit())
                    .stxNumericValueTransition(value: row.costText)
                    .foregroundStyle(Color.stxMuted)
                    .frame(minWidth: 70, alignment: .trailing)
                Text(row.shareText)
                    .font(.sora(12, weight: .semibold).monospacedDigit())
                    .stxNumericValueTransition(value: row.shareText)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 50, alignment: .trailing)
            }

            GeometryReader { proxy in
                let totalWidth = proxy.size.width
                let solidWidth = totalWidth * CGFloat(row.solidTokens) / CGFloat(row.maxTokens)
                let cachedWidth = totalWidth * CGFloat(row.cacheReadTokens) / CGFloat(row.maxTokens)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    HStack(spacing: 0) {
                        if solidWidth > 0 {
                            Rectangle()
                                .fill(ModelPalette.color(at: row.colorIndex))
                                .frame(width: solidWidth)
                        }
                        if cachedWidth > 0 {
                            ZStack {
                                Rectangle().fill(ModelPalette.color(at: row.colorIndex).opacity(0.68))
                                DiagonalStripes(spacing: 4)
                                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
                            }
                            .frame(width: cachedWidth)
                            .clipped()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                }
            }
            .frame(height: 7)
        }
        .padding(.vertical, 10)
    }
}

struct UsageModelBreakdownSnapshot {
    struct Key: Equatable {
        let seriesID: String
        let includeCacheInTokens: Bool
        let costEstimationMode: CostEstimationMode
        let modelsRevisionID: String
        let seriesRevisionID: String
    }

    struct Row: Identifiable, Equatable {
        let id: String
        let displayName: String
        let colorIndex: Int
        let totalText: String
        let costText: String
        let shareText: String
        let solidTokens: Int
        let cacheReadTokens: Int
        let maxTokens: Int
    }

    let key: Key
    let rows: [Row]

    init(
        key: Key,
        models: [ModelUsage],
        series: TrendSeries,
        displayName: (String) -> String
    ) {
        self.key = key

        let totals = models.map { $0.usage.total(includingCacheRead: key.includeCacheInTokens) }
        let allTokens = max(1, totals.reduce(0, +))
        let maxTokens = max(1, totals.max() ?? 1)
        let seriesIndexByModel = Dictionary(uniqueKeysWithValues: series.models.enumerated().map { ($0.element, $0.offset) })

        self.rows = models.enumerated().map { index, model in
            let total = totals[index]
            let share = Double(total) / Double(allTokens)
            let solidTokens = max(0, model.usage.total - model.usage.cacheReadTokens)
            return Row(
                id: model.id,
                displayName: displayName(model.model),
                colorIndex: seriesIndexByModel[model.model] ?? index,
                totalText: Format.tokens(total),
                costText: Format.costEstimate(model.costEstimate, mode: key.costEstimationMode),
                shareText: Format.percent(share),
                solidTokens: solidTokens,
                cacheReadTokens: key.includeCacheInTokens ? max(0, model.usage.cacheReadTokens) : 0,
                maxTokens: maxTokens
            )
        }
    }
}

struct UsageTokenCompositionPanel: View {
    let usage: TokenUsage
    let includeCacheInTokens: Bool
    let cacheHitRate: Double?

    private var parts: [Part] {
        [
            Part(id: "output", label: L10n.string("usage.token.output", defaultValue: "Output"), value: usage.outputTokens, color: Color.stxRamp[0]),
            Part(id: "input", label: L10n.string("usage.token.input", defaultValue: "Input"), value: usage.inputTokens, color: Color.stxRamp[1]),
            Part(id: "cache-write", label: L10n.string("usage.token.cache_write", defaultValue: "Cache write"), value: usage.cacheCreationTotalTokens, color: Color.stxRamp[2]),
            Part(id: "cache-read", label: L10n.string("usage.token.cache_read", defaultValue: "Cache read"), value: usage.cacheReadTokens, color: Color.stxRamp[3]),
        ]
    }

    private var compositionTotal: Int {
        max(1, parts.reduce(0) { $0 + $1.value })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("COMPOSITION")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer()
                Text(cacheHitRate.map(Format.percent) ?? "--")
                    .font(.sora(12, weight: .semibold).monospacedDigit())
                    .stxNumericValueTransition(value: cacheHitRate.map(Format.percent) ?? "--")
                    .foregroundStyle(.primary)
                    .help(L10n.string("usage.token.cache_hit_rate", defaultValue: "Cache hit rate"))
            }

            compositionBar

            VStack(alignment: .leading, spacing: 8) {
                ForEach(parts) { part in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(part.color)
                            .frame(width: 9, height: 9)
                        Text(part.label)
                            .font(.sora(11))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Format.tokens(part.value))
                            .font(.sora(11).monospacedDigit())
                            .stxNumericValueTransition(value: Format.tokens(part.value))
                            .foregroundStyle(Color.stxMuted)
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                }
            }

            StxRule()

            VStack(alignment: .leading, spacing: 5) {
                Text(includeCacheInTokens
                    ? L10n.string("usage.token.cache_reads_included", defaultValue: "Cache reads are included in totals.")
                    : L10n.string("usage.token.cache_reads_excluded", defaultValue: "Cache reads are excluded from totals."))
                    .font(.sora(11, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.string("usage.token.cache_write_note",
                                 defaultValue: "Cache write tokens are always counted because they represent newly primed context."))
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .mainUsagePanel(padding: 16)
    }

    private var compositionBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(parts) { part in
                    let width = proxy.size.width * CGFloat(part.value) / CGFloat(compositionTotal)
                    Rectangle()
                        .fill(part.color)
                        .frame(width: max(part.value > 0 ? CGFloat(2) : 0, width))
                }
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .frame(height: 8)
    }

    private struct Part: Identifiable {
        let id: String
        let label: String
        let value: Int
        let color: Color
    }
}

#if DEBUG
#Preview {
    UsageTokenCompositionPanel(
        usage: TokenUsage(inputTokens: 120_000, outputTokens: 82_000, cacheReadTokens: 800_000, cacheCreation5mTokens: 12_000, cacheCreation1hTokens: 44_000),
        includeCacheInTokens: true,
        cacheHitRate: 0.88
    )
    .padding(24)
    .frame(width: 360)
    .background(Color.stxBackground)
}
#endif
