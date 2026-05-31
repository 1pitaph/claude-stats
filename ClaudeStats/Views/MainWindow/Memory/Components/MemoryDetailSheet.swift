import SwiftUI

struct MemoryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let memory: CodeMemoryMemory

    private var model: MemoryFactCardModel {
        MemoryFactCardModel(memory: memory)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            StxRule()
            content
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 520, idealHeight: 680)
        .background(AppSurface.panelFill)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: AppIcon.Action.close)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close memory detail")

            Image(systemName: model.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.stxAccent)
                .frame(width: 26, height: 26)
                .background(Color.stxAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(memory.title)
                    .font(.sora(14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(memory.title)

                HStack(spacing: 6) {
                    AIConfigsBadge(text: memory.type, color: Color.stxMuted)
                    MemoryStatusBadge(text: memory.status)
                    Text(memory.projectID.memoryAbbreviatingHomeDirectory)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(memory.projectID)
                }
            }

            Spacer(minLength: 12)

            MemoryCopyIconButton(value: memory.body, label: "Copy Text")
            MemoryCopyIconButton(value: memory.id, label: "Copy ID", systemImage: AppIcon.Resource.link)
            MemoryCopyIconButton(value: memory.projectID, label: "Copy Project", systemImage: AppIcon.Resource.folder)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var content: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summaryBlock
                factsBlock
                if !memory.sourceRefs.isEmpty {
                    sourceRefsBlock
                }
            }
            .padding(16)
        }
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                AIConfigsBadge(text: memory.type, color: Color.stxMuted)
                MemoryStatusBadge(text: memory.status)
                if let reviewReason = memory.reviewReason, !reviewReason.isEmpty {
                    AIConfigsBadge(text: reviewReason, color: Color.stxMuted)
                }
            }

            Text(memory.title)
                .font(.sora(16, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Text(memory.body)
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.62, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private var factsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            MemoryDetailSectionTitle("DETAILS")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8, alignment: .topLeading)], alignment: .leading, spacing: 8) {
                MemoryDetailFactPill(label: "id", value: memory.id)
                MemoryDetailFactPill(label: "project", value: memory.projectID.memoryAbbreviatingHomeDirectory, help: memory.projectID)
                MemoryDetailFactPill(label: "confidence", value: String(format: "%.2f", memory.confidence))
                MemoryDetailFactPill(label: "importance", value: String(format: "%.2f", memory.importance))
                MemoryDetailFactPill(label: "created", value: MemoryFormat.timestamp(memory.createdAt))
                MemoryDetailFactPill(label: "updated", value: MemoryFormat.timestamp(memory.updatedAt))
                if let extractedBy = memory.extractedBy, !extractedBy.isEmpty {
                    MemoryDetailFactPill(label: "extracted", value: extractedBy)
                }
                if let validAt = memory.validAt {
                    MemoryDetailFactPill(label: "valid", value: MemoryFormat.timestamp(validAt))
                }
                if let invalidAt = memory.invalidAt {
                    MemoryDetailFactPill(label: "invalid", value: MemoryFormat.timestamp(invalidAt))
                }
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.52, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private var sourceRefsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                MemoryDetailSectionTitle("SOURCES")
                Text("\(memory.sourceRefs.count)")
                    .font(.sora(9).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                Spacer()
            }

            ForEach(memory.sourceRefs) { ref in
                MemoryDetailSourceRefRow(sourceRef: ref)
            }
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.52, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }
}

private struct MemoryDetailSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.sora(10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Color.stxMuted)
    }
}

private struct MemoryDetailFactPill: View {
    let label: String
    let value: String
    var help: String?

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.sora(10).monospaced())
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
        .help(help ?? value)
    }
}

private struct MemoryDetailSourceRefRow: View {
    let sourceRef: CodeMemorySourceRef

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: AppIcon.Resource.link)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.stxAccent)
                Text(sourceRef.label)
                    .font(.sora(11, weight: .semibold).monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                MemoryCopyIconButton(value: sourceRef.helpText, label: "Copy Source", systemImage: AppIcon.Action.copy)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let uri = sourceRef.uri, !uri.isEmpty {
                    detailLine("uri", uri)
                }
                if let path = sourceRef.path, !path.isEmpty {
                    detailLine("path", path.memoryAbbreviatingHomeDirectory, help: path)
                }
                if let sourceID = sourceRef.sourceID, !sourceID.isEmpty {
                    detailLine("source", sourceID)
                }
                if let episodeID = sourceRef.episodeID, !episodeID.isEmpty {
                    detailLine("episode", episodeID)
                }
                if let contentHash = sourceRef.contentHash, !contentHash.isEmpty {
                    detailLine("hash", contentHash)
                }
                if let lineRange {
                    detailLine("lines", lineRange)
                }
                if let quote = sourceRef.quote, !quote.isEmpty {
                    Text(quote)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(sourceRef.helpText)
    }

    private var lineRange: String? {
        guard sourceRef.lineStart != nil || sourceRef.lineEnd != nil else { return nil }
        if let lineStart = sourceRef.lineStart, let lineEnd = sourceRef.lineEnd, lineEnd != lineStart {
            return "\(lineStart)-\(lineEnd)"
        }
        return (sourceRef.lineStart ?? sourceRef.lineEnd).map(String.init)
    }

    private func detailLine(_ label: String, _ value: String, help: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.sora(9).monospaced())
                .foregroundStyle(Color.stxMuted)
                .frame(width: 48, alignment: .trailing)
            Text(value)
                .font(.sora(10).monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(help ?? value)
        }
    }
}
