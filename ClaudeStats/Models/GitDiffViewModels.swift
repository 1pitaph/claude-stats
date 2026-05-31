import Foundation

enum DiffViewMode: String, CaseIterable, Identifiable, Sendable {
    case fluid
    case blocks
    case unified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fluid: return "Fluid"
        case .blocks: return "Blocks"
        case .unified: return "Unified"
        }
    }

    var systemImage: String {
        switch self {
        case .fluid: return AppIcon.Layout.sideBySide
        case .blocks: return AppIcon.Layout.rectangleGrid
        case .unified: return AppIcon.Layout.rectangle
        }
    }
}

enum GitDiffBlockGranularity: String, CaseIterable, Identifiable, Sendable {
    case fine
    case coarse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fine:
            return "Fine"
        case .coarse:
            return "Coarse"
        }
    }
}

struct StructuredFileDiff: Sendable, Hashable {
    let path: String
    let isBinary: Bool
    let fileHeaders: [String]
    let hunks: [DiffHunk]
    let unifiedLines: [DiffLine]

    var isEmpty: Bool {
        !isBinary && hunks.allSatisfy { $0.segments.isEmpty }
    }

    static func build(from diff: FileDiff) -> StructuredFileDiff {
        DiffStructureBuilder().build(from: diff)
    }
}

struct DiffHunk: Sendable, Hashable, Identifiable {
    let id: String
    let header: String
    let oldStart: Int
    let newStart: Int
    let segments: [DiffSegment]
}

struct DiffSegment: Sendable, Hashable, Identifiable {
    enum Kind: Sendable, Hashable {
        case context
        case change
    }

    let id: String
    let kind: Kind
    let contextLines: [DiffTextLine]
    let change: ChangeBlock?

    static func context(id: String, lines: [DiffTextLine]) -> DiffSegment {
        DiffSegment(id: id, kind: .context, contextLines: lines, change: nil)
    }

    static func change(id: String, block: ChangeBlock) -> DiffSegment {
        DiffSegment(id: id, kind: .change, contextLines: [], change: block)
    }
}

struct ChangeBlock: Sendable, Hashable, Identifiable {
    let id: String
    let oldLines: [DiffTextLine]
    let newLines: [DiffTextLine]
    let linePairs: [DiffLinePair]
}

struct DiffLinePair: Sendable, Hashable, Identifiable {
    enum Kind: Sendable, Hashable {
        case modified
        case deleted
        case inserted
    }

    let id: String
    let kind: Kind
    let oldLine: DiffTextLine?
    let newLine: DiffTextLine?
}

struct DiffTextLine: Sendable, Hashable, Identifiable {
    enum Side: Sendable, Hashable {
        case old
        case new
        case both
    }

    let id: String
    let side: Side
    let kind: DiffLine.Kind
    let text: String
    let oldLine: Int?
    let newLine: Int?
    let inlineSpans: [DiffInlineSpan]

    func withInlineSpans(_ spans: [DiffInlineSpan]) -> DiffTextLine {
        DiffTextLine(
            id: id,
            side: side,
            kind: kind,
            text: text,
            oldLine: oldLine,
            newLine: newLine,
            inlineSpans: spans
        )
    }
}

struct DiffInlineSpan: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case deletion
        case addition
    }

    let offset: Int
    let length: Int
    let kind: Kind
}

struct FluidSyncMap: Sendable, Hashable {
    struct Offsets: Sendable, Hashable {
        let oldY: Double
        let newY: Double
    }

    struct Segment: Sendable, Hashable, Identifiable {
        enum Kind: Sendable, Hashable {
            case hunkHeader
            case context
            case change(changeID: String)
        }

        let id: String
        let kind: Kind
        let virtualStart: Double
        let virtualHeight: Double
        let oldStart: Double
        let oldHeight: Double
        let newStart: Double
        let newHeight: Double

        var virtualEnd: Double { virtualStart + virtualHeight }
        var oldEnd: Double { oldStart + oldHeight }
        var newEnd: Double { newStart + newHeight }
    }

    let segments: [Segment]
    let virtualHeight: Double
    let oldContentHeight: Double
    let newContentHeight: Double

    func offsets(for virtualY: Double) -> Offsets {
        guard !segments.isEmpty else { return Offsets(oldY: 0, newY: 0) }
        let y = min(max(virtualY, 0), virtualHeight)

        if let segment = segments.first(where: { y >= $0.virtualStart && y <= $0.virtualEnd }) {
            let progress: Double
            if segment.virtualHeight <= 0 {
                progress = 0
            } else {
                progress = min(max((y - segment.virtualStart) / segment.virtualHeight, 0), 1)
            }
            return Offsets(
                oldY: segment.oldStart + segment.oldHeight * progress,
                newY: segment.newStart + segment.newHeight * progress
            )
        }

        if let last = segments.last, y >= last.virtualEnd {
            return Offsets(oldY: oldContentHeight, newY: newContentHeight)
        }
        return Offsets(oldY: 0, newY: 0)
    }

    static func build(from diff: StructuredFileDiff, lineHeight: Double) -> FluidSyncMap {
        var segments: [Segment] = []
        var virtualY = 0.0
        var oldY = 0.0
        var newY = 0.0

        func append(kind: Segment.Kind, id: String, oldHeight: Double, newHeight: Double) {
            let virtualHeight = max(oldHeight, newHeight, lineHeight)
            segments.append(Segment(
                id: id,
                kind: kind,
                virtualStart: virtualY,
                virtualHeight: virtualHeight,
                oldStart: oldY,
                oldHeight: oldHeight,
                newStart: newY,
                newHeight: newHeight
            ))
            virtualY += virtualHeight
            oldY += oldHeight
            newY += newHeight
        }

        for hunk in diff.hunks {
            append(kind: .hunkHeader, id: "\(hunk.id)|header", oldHeight: lineHeight, newHeight: lineHeight)
            for segment in hunk.segments {
                switch segment.kind {
                case .context:
                    let height = Double(segment.contextLines.count) * lineHeight
                    append(kind: .context, id: segment.id, oldHeight: height, newHeight: height)
                case .change:
                    guard let change = segment.change else { continue }
                    append(
                        kind: .change(changeID: change.id),
                        id: segment.id,
                        oldHeight: Double(change.oldLines.count) * lineHeight,
                        newHeight: Double(change.newLines.count) * lineHeight
                    )
                }
            }
        }

        return FluidSyncMap(
            segments: segments,
            virtualHeight: virtualY,
            oldContentHeight: oldY,
            newContentHeight: newY
        )
    }
}

struct DiffStructureBuilder: Sendable {
    private let inlineDiffer = InlineDiffBuilder()
    private static let linePairThreshold = 0.34
    private static let linePairDPLimit = 40_000
    private static let linePairGapPenalty = -0.01

    private enum AlignmentStep {
        case modified(old: Int, new: Int)
        case deleted(old: Int)
        case inserted(new: Int)
    }

    private enum AlignmentParent {
        case modified
        case deleted
        case inserted
    }

    func build(from diff: FileDiff) -> StructuredFileDiff {
        var fileHeaders: [String] = []
        var hunks: [DiffHunk] = []
        var currentHeader: String?
        var currentOldStart = 0
        var currentNewStart = 0
        var currentLines: [DiffLine] = []
        var hunkIndex = 0

        func flushHunk() {
            guard let currentHeader else { return }
            let segments = buildSegments(from: currentLines, hunkIndex: hunkIndex)
            hunks.append(DiffHunk(
                id: "hunk-\(hunkIndex)",
                header: currentHeader,
                oldStart: currentOldStart,
                newStart: currentNewStart,
                segments: segments
            ))
            hunkIndex += 1
            currentLines = []
        }

        for line in diff.lines {
            switch line.kind {
            case .fileHeader:
                fileHeaders.append(line.text)
            case .hunkHeader:
                flushHunk()
                currentHeader = line.text
                let starts = Self.parseHunkStarts(line.text)
                currentOldStart = starts.old
                currentNewStart = starts.new
            case .context, .addition, .deletion:
                currentLines.append(line)
            }
        }
        flushHunk()

        return StructuredFileDiff(
            path: diff.path,
            isBinary: diff.isBinary,
            fileHeaders: fileHeaders,
            hunks: hunks,
            unifiedLines: diff.lines
        )
    }

    private func buildSegments(from lines: [DiffLine], hunkIndex: Int) -> [DiffSegment] {
        var segments: [DiffSegment] = []
        var index = 0
        var segmentIndex = 0

        while index < lines.count {
            let line = lines[index]
            if line.kind == .context {
                var context: [DiffTextLine] = []
                while index < lines.count, lines[index].kind == .context {
                    context.append(Self.textLine(from: lines[index], side: .both, id: "h\(hunkIndex)-s\(segmentIndex)-c\(context.count)"))
                    index += 1
                }
                segments.append(.context(id: "h\(hunkIndex)-s\(segmentIndex)", lines: context))
                segmentIndex += 1
            } else {
                var oldLines: [DiffTextLine] = []
                var newLines: [DiffTextLine] = []
                while index < lines.count, lines[index].kind == .deletion || lines[index].kind == .addition {
                    if lines[index].kind == .deletion {
                        oldLines.append(Self.textLine(from: lines[index], side: .old, id: "h\(hunkIndex)-s\(segmentIndex)-o\(oldLines.count)"))
                    } else {
                        newLines.append(Self.textLine(from: lines[index], side: .new, id: "h\(hunkIndex)-s\(segmentIndex)-n\(newLines.count)"))
                    }
                    index += 1
                }
                let block = buildChangeBlock(id: "h\(hunkIndex)-s\(segmentIndex)-change", oldLines: oldLines, newLines: newLines)
                segments.append(.change(id: "h\(hunkIndex)-s\(segmentIndex)", block: block))
                segmentIndex += 1
            }
        }

        return segments
    }

    private func buildChangeBlock(id: String, oldLines: [DiffTextLine], newLines: [DiffTextLine]) -> ChangeBlock {
        var pairs: [DiffLinePair] = []
        for step in Self.align(oldLines: oldLines, newLines: newLines) {
            switch step {
            case .modified(let oldIndex, let newIndex):
                let oldLine = oldLines[oldIndex]
                let newLine = newLines[newIndex]
                let spans = inlineDiffer.spans(old: oldLine.text, new: newLine.text)
                pairs.append(DiffLinePair(
                    id: "\(id)-modified-\(oldIndex)-\(newIndex)",
                    kind: .modified,
                    oldLine: oldLine.withInlineSpans(spans.old),
                    newLine: newLine.withInlineSpans(spans.new)
                ))
            case .deleted(let oldIndex):
                let oldLine = oldLines[oldIndex]
                pairs.append(DiffLinePair(id: "\(id)-delete-\(oldIndex)", kind: .deleted, oldLine: oldLine, newLine: nil))
            case .inserted(let newIndex):
                let newLine = newLines[newIndex]
                pairs.append(DiffLinePair(id: "\(id)-insert-\(newIndex)", kind: .inserted, oldLine: nil, newLine: newLine))
            }
        }

        let pairedOld = pairs.compactMap(\.oldLine)
        let pairedNew = pairs.compactMap(\.newLine)
        return ChangeBlock(id: id, oldLines: pairedOld, newLines: pairedNew, linePairs: pairs)
    }

    private static func align(oldLines: [DiffTextLine], newLines: [DiffTextLine]) -> [AlignmentStep] {
        if oldLines.isEmpty {
            return newLines.indices.map { .inserted(new: $0) }
        }
        if newLines.isEmpty {
            return oldLines.indices.map { .deleted(old: $0) }
        }
        if oldLines.count * newLines.count > linePairDPLimit {
            return greedyAlign(oldLines: oldLines, newLines: newLines)
        }

        let oldCount = oldLines.count
        let newCount = newLines.count
        var scores = Array(repeating: Array(repeating: 0.0, count: newCount), count: oldCount)
        for oldIndex in oldLines.indices {
            for newIndex in newLines.indices {
                scores[oldIndex][newIndex] = lineSimilarity(oldLines[oldIndex].text, newLines[newIndex].text)
            }
        }

        var table = Array(
            repeating: Array(repeating: -Double.infinity, count: newCount + 1),
            count: oldCount + 1
        )
        var parents = Array(
            repeating: Array(repeating: AlignmentParent?.none, count: newCount + 1),
            count: oldCount + 1
        )
        table[0][0] = 0

        for oldIndex in 0...oldCount {
            for newIndex in 0...newCount {
                let current = table[oldIndex][newIndex]
                guard current.isFinite else { continue }
                if oldIndex < oldCount {
                    update(
                        &table,
                        &parents,
                        row: oldIndex + 1,
                        column: newIndex,
                        score: current + linePairGapPenalty,
                        parent: .deleted
                    )
                }
                if newIndex < newCount {
                    update(
                        &table,
                        &parents,
                        row: oldIndex,
                        column: newIndex + 1,
                        score: current + linePairGapPenalty,
                        parent: .inserted
                    )
                }
                if oldIndex < oldCount, newIndex < newCount {
                    let similarity = scores[oldIndex][newIndex]
                    if similarity >= linePairThreshold {
                        update(
                            &table,
                            &parents,
                            row: oldIndex + 1,
                            column: newIndex + 1,
                            score: current + similarity,
                            parent: .modified
                        )
                    }
                }
            }
        }

        var steps: [AlignmentStep] = []
        var oldIndex = oldCount
        var newIndex = newCount
        while oldIndex > 0 || newIndex > 0 {
            switch parents[oldIndex][newIndex] {
            case .modified:
                steps.append(.modified(old: oldIndex - 1, new: newIndex - 1))
                oldIndex -= 1
                newIndex -= 1
            case .deleted:
                steps.append(.deleted(old: oldIndex - 1))
                oldIndex -= 1
            case .inserted:
                steps.append(.inserted(new: newIndex - 1))
                newIndex -= 1
            case nil:
                if newIndex > 0 {
                    steps.append(.inserted(new: newIndex - 1))
                    newIndex -= 1
                } else {
                    steps.append(.deleted(old: oldIndex - 1))
                    oldIndex -= 1
                }
            }
        }
        return steps.reversed()
    }

    private static func update(
        _ table: inout [[Double]],
        _ parents: inout [[AlignmentParent?]],
        row: Int,
        column: Int,
        score: Double,
        parent: AlignmentParent
    ) {
        if score > table[row][column] || (score == table[row][column] && priority(parent) > priority(parents[row][column])) {
            table[row][column] = score
            parents[row][column] = parent
        }
    }

    private static func priority(_ parent: AlignmentParent?) -> Int {
        switch parent {
        case .modified:
            return 3
        case .inserted:
            return 2
        case .deleted:
            return 1
        case nil:
            return 0
        }
    }

    private static func greedyAlign(oldLines: [DiffTextLine], newLines: [DiffTextLine]) -> [AlignmentStep] {
        var steps: [AlignmentStep] = []
        var consumedNew = Set<Int>()
        var nextNewSearch = 0

        for oldIndex in oldLines.indices {
            var bestIndex: Int?
            var bestScore = 0.0
            for newIndex in nextNewSearch..<newLines.count where !consumedNew.contains(newIndex) {
                let score = lineSimilarity(oldLines[oldIndex].text, newLines[newIndex].text)
                if score > bestScore {
                    bestScore = score
                    bestIndex = newIndex
                }
            }

            if let bestIndex, bestScore >= linePairThreshold {
                while nextNewSearch < bestIndex {
                    if !consumedNew.contains(nextNewSearch) {
                        steps.append(.inserted(new: nextNewSearch))
                        consumedNew.insert(nextNewSearch)
                    }
                    nextNewSearch += 1
                }
                steps.append(.modified(old: oldIndex, new: bestIndex))
                consumedNew.insert(bestIndex)
                nextNewSearch = bestIndex + 1
            } else {
                steps.append(.deleted(old: oldIndex))
            }
        }

        for newIndex in newLines.indices where !consumedNew.contains(newIndex) {
            steps.append(.inserted(new: newIndex))
        }
        return steps
    }

    private static func textLine(from line: DiffLine, side: DiffTextLine.Side, id: String) -> DiffTextLine {
        DiffTextLine(
            id: id,
            side: side,
            kind: line.kind,
            text: line.text,
            oldLine: line.oldLine,
            newLine: line.newLine,
            inlineSpans: []
        )
    }

    private static func parseHunkStarts(_ header: String) -> (old: Int, new: Int) {
        let parts = header.split(separator: " ")
        guard parts.count >= 3 else { return (0, 0) }
        let old = Int(parts[1].dropFirst().split(separator: ",").first ?? "") ?? 0
        let new = Int(parts[2].dropFirst().split(separator: ",").first ?? "") ?? 0
        return (old, new)
    }

    private static func lineSimilarity(_ old: String, _ new: String) -> Double {
        if old == new { return 1 }
        let oldTokens = Set(InlineDiffBuilder.tokenTexts(in: old).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        let newTokens = Set(InlineDiffBuilder.tokenTexts(in: new).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        guard !oldTokens.isEmpty || !newTokens.isEmpty else { return 0 }
        let intersection = oldTokens.intersection(newTokens).count
        let union = oldTokens.union(newTokens).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }
}

struct InlineDiffBuilder: Sendable {
    struct Result: Sendable, Hashable {
        let old: [DiffInlineSpan]
        let new: [DiffInlineSpan]
    }

    private struct Token: Sendable, Hashable {
        let text: String
        let offset: Int
        let length: Int
    }

    func spans(old: String, new: String) -> Result {
        let oldTokens = Self.tokens(in: old)
        let newTokens = Self.tokens(in: new)
        guard !oldTokens.isEmpty || !newTokens.isEmpty else {
            return Result(old: [], new: [])
        }

        let matches = Self.lcsMatches(oldTokens.map(\.text), newTokens.map(\.text))
        let matchedOld = Set(matches.map(\.old))
        let matchedNew = Set(matches.map(\.new))
        let oldSpans = Self.mergeSpans(oldTokens.indices.compactMap { index in
            matchedOld.contains(index) ? nil : DiffInlineSpan(offset: oldTokens[index].offset, length: oldTokens[index].length, kind: .deletion)
        })
        let newSpans = Self.mergeSpans(newTokens.indices.compactMap { index in
            matchedNew.contains(index) ? nil : DiffInlineSpan(offset: newTokens[index].offset, length: newTokens[index].length, kind: .addition)
        })
        return Result(old: oldSpans, new: newSpans)
    }

    static func tokenTexts(in text: String) -> [String] {
        tokens(in: text).map(\.text)
    }

    private static func tokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentKind: TokenKind?
        var currentOffset = 0
        var offset = 0

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(Token(text: current, offset: currentOffset, length: current.count))
            current = ""
            currentKind = nil
        }

        for character in text {
            let kind = TokenKind(character)
            if currentKind == nil {
                currentKind = kind
                currentOffset = offset
            } else if currentKind != kind || kind == .punctuation {
                flush()
                currentKind = kind
                currentOffset = offset
            }
            current.append(character)
            offset += 1
        }
        flush()
        return tokens
    }

    private enum TokenKind: Sendable {
        case word
        case whitespace
        case punctuation

        init(_ character: Character) {
            if character.isWhitespace {
                self = .whitespace
            } else if character.isLetter || character.isNumber || character == "_" {
                self = .word
            } else {
                self = .punctuation
            }
        }
    }

    private static func lcsMatches(_ old: [String], _ new: [String]) -> [(old: Int, new: Int)] {
        guard !old.isEmpty, !new.isEmpty else { return [] }
        var table = Array(repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
        for oldIndex in stride(from: old.count - 1, through: 0, by: -1) {
            for newIndex in stride(from: new.count - 1, through: 0, by: -1) {
                if old[oldIndex] == new[newIndex] {
                    table[oldIndex][newIndex] = table[oldIndex + 1][newIndex + 1] + 1
                } else {
                    table[oldIndex][newIndex] = max(table[oldIndex + 1][newIndex], table[oldIndex][newIndex + 1])
                }
            }
        }

        var matches: [(old: Int, new: Int)] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count, newIndex < new.count {
            if old[oldIndex] == new[newIndex] {
                matches.append((oldIndex, newIndex))
                oldIndex += 1
                newIndex += 1
            } else if table[oldIndex + 1][newIndex] >= table[oldIndex][newIndex + 1] {
                oldIndex += 1
            } else {
                newIndex += 1
            }
        }
        return matches
    }

    private static func mergeSpans(_ spans: [DiffInlineSpan]) -> [DiffInlineSpan] {
        var merged: [DiffInlineSpan] = []
        for span in spans.sorted(by: { $0.offset < $1.offset }) {
            guard let last = merged.last, last.kind == span.kind, last.offset + last.length >= span.offset else {
                merged.append(span)
                continue
            }
            merged[merged.count - 1] = DiffInlineSpan(
                offset: last.offset,
                length: max(last.offset + last.length, span.offset + span.length) - last.offset,
                kind: last.kind
            )
        }
        return merged
    }
}
