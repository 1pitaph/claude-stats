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
