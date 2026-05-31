import AppKit
import SwiftUI

struct MemoryStatusBadge: View {
    let text: String

    var body: some View {
        AIConfigsBadge(text: text, color: color)
    }

    private var color: Color {
        switch text {
        case "active":
            Color.stxAccent
        case "proposed":
            Color(red: 0.92, green: 0.58, blue: 0.16)
        case "conflicted", "retracted":
            Color(red: 0.9, green: 0.26, blue: 0.22)
        default:
            Color.stxMuted
        }
    }
}

struct MemoryFactRow: View {
    let memory: CodeMemoryMemory
    var trailing: AnyView?

    init<Content: View>(memory: CodeMemoryMemory, @ViewBuilder trailing: () -> Content) {
        self.memory = memory
        self.trailing = AnyView(trailing())
    }

    init(memory: CodeMemoryMemory) {
        self.memory = memory
        self.trailing = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.stxAccent)
                    .frame(width: 18)
                Text(memory.title)
                    .font(.sora(13, weight: .semibold))
                    .lineLimit(1)
                AIConfigsBadge(text: memory.type, color: Color.stxMuted)
                MemoryStatusBadge(text: memory.status)
                if let reviewReason = memory.reviewReason, !reviewReason.isEmpty {
                    AIConfigsBadge(text: reviewReason, color: Color.stxMuted)
                }
                Spacer(minLength: 8)
                if let trailing {
                    trailing
                }
            }

            Text(memory.body)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                compactFact("project", memory.projectID)
                compactFact("confidence", String(format: "%.2f", memory.confidence))
                compactFact("importance", String(format: "%.2f", memory.importance))
                if let validAt = memory.validAt {
                    compactFact("valid", MemoryFormat.timestamp(validAt))
                }
                if let invalidAt = memory.invalidAt {
                    compactFact("invalid", MemoryFormat.timestamp(invalidAt))
                }
                Spacer(minLength: 8)
                MemoryCopyButton(value: memory.body, label: "Copy Text")
                MemoryCopyButton(value: memory.id, label: "Copy ID", systemImage: "link")
            }

            if !memory.sourceRefs.isEmpty {
                MemorySourceRefsView(sourceRefs: memory.sourceRefs)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.62, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private var icon: String {
        switch memory.type {
        case "command", "workflow":
            "terminal"
        case "risk":
            "exclamationmark.triangle"
        case "rule", "convention":
            "checkmark.seal"
        case "decision":
            "arrow.triangle.branch"
        default:
            "text.badge.checkmark"
        }
    }

    private func compactFact(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.sora(10).monospaced())
    }
}

struct MemoryFactCardModel: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let type: String
    let status: String
    let reviewReason: String?
    let icon: String
    let facts: [MemoryCompactFactModel]
    let sourceRefs: [MemorySourceRefPillModel]
    let estimatedWeight: Int

    init(memory: CodeMemoryMemory) {
        id = memory.id
        title = memory.title
        body = memory.body
        type = memory.type
        status = memory.status
        let reviewReason = memory.reviewReason?.isEmpty == false ? memory.reviewReason : nil
        self.reviewReason = reviewReason
        icon = Self.icon(for: memory.type)

        var facts = [
            MemoryCompactFactModel(label: "project", value: memory.projectID),
            MemoryCompactFactModel(label: "confidence", value: String(format: "%.2f", memory.confidence)),
            MemoryCompactFactModel(label: "importance", value: String(format: "%.2f", memory.importance)),
        ]
        if let validAt = memory.validAt {
            facts.append(MemoryCompactFactModel(label: "valid", value: MemoryFormat.timestamp(validAt)))
        }
        if let invalidAt = memory.invalidAt {
            facts.append(MemoryCompactFactModel(label: "invalid", value: MemoryFormat.timestamp(invalidAt)))
        }
        self.facts = facts
        sourceRefs = memory.sourceRefs.map(MemorySourceRefPillModel.init(sourceRef:))
        estimatedWeight = Self.estimatedWeight(
            title: memory.title,
            body: memory.body,
            factCount: facts.count,
            sourceRefCount: memory.sourceRefs.count,
            hasReviewReason: reviewReason != nil
        )
    }

    private static func icon(for type: String) -> String {
        switch type {
        case "command", "workflow":
            "terminal"
        case "risk":
            "exclamationmark.triangle"
        case "rule", "convention":
            "checkmark.seal"
        case "decision":
            "arrow.triangle.branch"
        default:
            "text.badge.checkmark"
        }
    }

    private static func estimatedWeight(
        title: String,
        body: String,
        factCount: Int,
        sourceRefCount: Int,
        hasReviewReason: Bool
    ) -> Int {
        let titleLines = estimatedLineCount(for: title, charactersPerLine: 34, maximum: 2)
        let bodyLines = estimatedLineCount(for: body, charactersPerLine: 48, maximum: nil)
        let badgeLines = hasReviewReason ? 2 : 1
        return 86
            + titleLines * 20
            + badgeLines * 22
            + bodyLines * 15
            + factCount * 24
            + (sourceRefCount > 0 ? 28 : 0)
    }

    private static func estimatedLineCount(for text: String, charactersPerLine: Int, maximum: Int?) -> Int {
        let hardLineCount = text.filter(\.isNewline).count + 1
        let wrappedLineCount = max(1, Int((Double(text.count) / Double(charactersPerLine)).rounded(.up)))
        let lineCount = max(hardLineCount, wrappedLineCount)
        if let maximum {
            return min(maximum, lineCount)
        }
        return lineCount
    }
}

struct MemoryCompactFactModel: Identifiable, Equatable, Sendable {
    let label: String
    let value: String

    var id: String { label }
}

struct MemorySourceRefPillModel: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let helpText: String

    init(sourceRef: CodeMemorySourceRef) {
        id = sourceRef.id
        label = sourceRef.label
        helpText = sourceRef.helpText
    }
}

struct MemoryFactCard: View, Equatable {
    let model: MemoryFactCardModel

    init(model: MemoryFactCardModel) {
        self.model = model
    }

    init(memory: CodeMemoryMemory) {
        self.model = MemoryFactCardModel(memory: memory)
    }

    nonisolated static func == (lhs: MemoryFactCard, rhs: MemoryFactCard) -> Bool {
        lhs.model == rhs.model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: model.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.stxAccent)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)

                Text(model.title)
                    .font(.sora(13, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            MemoryCardBadges(
                type: model.type,
                status: model.status,
                reviewReason: model.reviewReason
            )

            Text(model.body)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)

            MemoryCompactFactsView(facts: model.facts)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                MemoryCopyIconButton(value: model.body, label: "Copy Text")
                MemoryCopyIconButton(value: model.id, label: "Copy ID", systemImage: "link")
            }

            if !model.sourceRefs.isEmpty {
                MemorySourceRefsCompactView(sourceRefs: model.sourceRefs)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.62, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }
}

private struct MemoryCardBadges: View {
    let type: String
    let status: String
    let reviewReason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AIConfigsBadge(text: type, color: Color.stxMuted)
                MemoryStatusBadge(text: status)
            }

            if let reviewReason {
                AIConfigsBadge(text: reviewReason, color: Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct MemoryCompactFactsView: View {
    let facts: [MemoryCompactFactModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(facts) { fact in
                MemoryCompactFactPill(fact: fact)
            }
        }
    }
}

private struct MemoryCompactFactPill: View {
    let fact: MemoryCompactFactModel

    var body: some View {
        HStack(spacing: 4) {
            Text(fact.label)
                .foregroundStyle(Color.stxMuted)
            Text(fact.value)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.sora(10).monospaced())
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct MemorySourceRefsCompactView: View {
    let sourceRefs: [MemorySourceRefPillModel]

    var body: some View {
        if let primarySourceRef = sourceRefs.first {
            HStack(spacing: 6) {
                MemorySourceRefCompactPill(sourceRef: primarySourceRef)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if overflowCount > 0 {
                    Text("+\(overflowCount)")
                        .font(.sora(10).monospaced())
                        .foregroundStyle(Color.stxMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
                        .help(helpText)
                }
            }
            .help(helpText)
        }
    }

    private var overflowCount: Int {
        max(0, sourceRefs.count - 1)
    }

    private var helpText: String {
        sourceRefs
            .map { sourceRef in
                "\(sourceRef.label)\n\(sourceRef.helpText)"
            }
            .joined(separator: "\n\n")
    }
}

private struct MemorySourceRefCompactPill: View {
    let sourceRef: MemorySourceRefPillModel

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "link")
                .font(.system(size: 9, weight: .semibold))
            Text(sourceRef.label)
                .font(.sora(10).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
        .help(sourceRef.helpText)
    }
}

struct MemorySearchResultRow: View {
    let result: CodeMemorySearchResult

    var body: some View {
        MemoryFactRow(memory: result.memory) {
            Text(String(format: "%.2f", result.score))
                .font(.sora(10).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
        }
        .overlay(alignment: .bottomTrailing) {
            if let evidence = result.evidence, !evidence.isEmpty {
                Text(evidence.map(\.adapter).joined(separator: " + "))
                    .font(.sora(10).monospaced())
                    .foregroundStyle(Color.stxAccent)
                    .lineLimit(1)
                    .padding(.trailing, 14)
                    .padding(.bottom, 8)
            }
        }
    }
}

struct MemoryGraphFactRow: View {
    let fact: CodeMemoryGraphFact
    var promote: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.stxAccent)
                    .frame(width: 18)
                Text(fact.title)
                    .font(.sora(13, weight: .semibold))
                    .lineLimit(1)
                AIConfigsBadge(text: fact.relation ?? "graph fact", color: Color.stxMuted)
                Spacer(minLength: 8)
                if let promote {
                    Button(action: promote) {
                        Label("Promote", systemImage: "checkmark.seal")
                    }
                    .controlSize(.small)
                }
            }

            Text(fact.fact)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                compactFact("project", fact.projectID)
                if let score = fact.score {
                    compactFact("score", String(format: "%.2f", score))
                }
                if let validAt = fact.validAt, !validAt.isEmpty {
                    compactFact("valid", validAt)
                }
                if let invalidAt = fact.invalidAt, !invalidAt.isEmpty {
                    compactFact("invalid", invalidAt)
                }
                Spacer(minLength: 8)
                MemoryCopyButton(value: fact.fact, label: "Copy Fact")
                MemoryCopyButton(value: fact.id, label: "Copy ID", systemImage: "link")
            }

            if !fact.sourceRefs.isEmpty {
                MemorySourceRefsView(sourceRefs: fact.sourceRefs)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.58, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private func compactFact(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.sora(10).monospaced())
    }
}

struct MemoryEpisodeRow: View {
    let episode: CodeMemoryEpisode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.stxAccent)
                    .frame(width: 18)
                Text(episode.title)
                    .font(.sora(13, weight: .semibold))
                    .lineLimit(1)
                AIConfigsBadge(text: episode.kind, color: Color.stxMuted)
                Spacer(minLength: 8)
                if let uri = episode.uri {
                    MemoryCopyButton(value: uri, label: "Copy URI", systemImage: "link")
                }
            }
            if let excerpt = episode.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                compactFact("project", episode.projectID)
                if let updatedAt = episode.updatedAt {
                    compactFact("updated", MemoryFormat.timestamp(updatedAt))
                }
                if let path = episode.path, !path.isEmpty {
                    compactFact("path", path.memoryAbbreviatingHomeDirectory)
                }
                Spacer(minLength: 8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.52, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private func compactFact(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.sora(10).monospaced())
    }
}

struct MemorySourceRefsView: View {
    let sourceRefs: [CodeMemorySourceRef]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sourceRefs) { ref in
                    HStack(spacing: 5) {
                        Image(systemName: "link")
                            .font(.system(size: 9, weight: .semibold))
                        Text(ref.label)
                            .font(.sora(10).monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
                    .help(ref.helpText)
                }
            }
        }
    }
}

struct MemoryCopyButton: View {
    let value: String
    var label: String = "Copy"
    var systemImage: String = "doc.on.doc"

    var body: some View {
        Button {
            MemoryClipboard.copy(value)
        } label: {
            Label(label, systemImage: systemImage)
        }
        .controlSize(.small)
        .disabled(value.isEmpty)
        .help(label)
    }
}

struct MemoryCopyIconButton: View {
    let value: String
    var label: String = "Copy"
    var systemImage: String = "doc.on.doc"

    var body: some View {
        Button {
            MemoryClipboard.copy(value)
        } label: {
            Label(label, systemImage: systemImage)
        }
        .labelStyle(.iconOnly)
        .controlSize(.small)
        .disabled(value.isEmpty)
        .help(label)
        .accessibilityLabel(label)
    }
}

enum MemoryClipboard {
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

enum MemoryFormat {
    static func timestamp(_ value: Double) -> String {
        let date = Date(timeIntervalSince1970: value)
        return date.formatted(.dateTime.year().month().day().hour().minute())
    }
}

extension CodeMemorySourceRef {
    var label: String {
        if let path, !path.isEmpty {
            return "\(kind): \(path.memoryAbbreviatingHomeDirectory)"
        }
        if let uri, !uri.isEmpty {
            return "\(kind): \(uri.memoryAbbreviatingHomeDirectory)"
        }
        if let sourceID, !sourceID.isEmpty {
            return "\(kind): \(sourceID)"
        }
        return kind
    }

    var helpText: String {
        [
            "kind=\(kind)",
            sourceID.map { "source_id=\($0)" },
            episodeID.map { "episode_id=\($0)" },
            contentHash.map { "hash=\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}
