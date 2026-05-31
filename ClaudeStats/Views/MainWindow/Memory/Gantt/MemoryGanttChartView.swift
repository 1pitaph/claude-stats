import Foundation
import SwiftUI

struct MemoryGanttChartView: View {
    let items: [MemoryGanttItem]
    let domain: MemoryGanttDomain
    let onOpen: (CodeMemoryMemory) -> Void

    private let labelWidth: CGFloat = 280
    private let timelineWidth: CGFloat = 900
    private let rowHeight: CGFloat = 54

    var body: some View {
        AppScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                axisHeader
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        MemoryGanttRow(
                            item: item,
                            ticks: ticks,
                            domain: domain,
                            labelWidth: labelWidth,
                            timelineWidth: timelineWidth,
                            rowHeight: rowHeight
                        ) {
                            onOpen(item.memory)
                        }
                    }
                }
            }
            .padding(18)
            .frame(minWidth: labelWidth + timelineWidth + 36, alignment: .topLeading)
        }
    }

    private var axisHeader: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("Memory")
                .font(.sora(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
                .frame(width: labelWidth, alignment: .leading)
                .padding(.top, 4)

            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.self) { tick in
                    let x = xPosition(for: tick)
                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle()
                            .fill(Color.stxStroke.opacity(0.75))
                            .frame(width: 1, height: 10)
                        Text(axisLabel(for: tick))
                            .font(.sora(9).monospaced())
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .offset(x: min(max(0, x - 2), timelineWidth - 96))
                }
            }
            .frame(width: timelineWidth, height: 38, alignment: .topLeading)
        }
        .padding(.bottom, 4)
    }

    private var ticks: [Double] {
        let count = 6
        let span = max(domain.end - domain.start, 1)
        return (0..<count).map { index in
            domain.start + span * Double(index) / Double(count - 1)
        }
    }

    private func xPosition(for time: Double) -> CGFloat {
        let span = max(domain.end - domain.start, 1)
        let ratio = (time - domain.start) / span
        return CGFloat(min(max(ratio, 0), 1)) * timelineWidth
    }

    private func axisLabel(for time: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current

        let span = domain.end - domain.start
        if span > 370 * 86_400 {
            formatter.dateFormat = "yyyy"
        } else if span > 10 * 86_400 {
            formatter.dateFormat = "MMM d"
        } else {
            formatter.dateFormat = "MMM d HH:mm"
        }
        return formatter.string(from: Date(timeIntervalSince1970: time))
    }
}

private struct MemoryGanttRow: View {
    let item: MemoryGanttItem
    let ticks: [Double]
    let domain: MemoryGanttDomain
    let labelWidth: CGFloat
    let timelineWidth: CGFloat
    let rowHeight: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 0) {
                label
                timeline
            }
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.sora(11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 6) {
                MemoryStatusBadge(text: item.status)
                AIConfigsBadge(text: item.type, color: Color.stxMuted)
            }
        }
        .frame(width: labelWidth, height: rowHeight, alignment: .leading)
        .padding(.trailing, 14)
    }

    private var timeline: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.028))
            ForEach(ticks, id: \.self) { tick in
                Rectangle()
                    .fill(Color.stxStroke.opacity(0.52))
                    .frame(width: 1)
                    .offset(x: xPosition(for: tick))
            }
            Rectangle()
                .fill(Color.stxStroke.opacity(0.55))
                .frame(height: 1)
                .offset(y: rowHeight / 2)
            bar
        }
        .frame(width: timelineWidth, height: rowHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var bar: some View {
        let color = MemoryStatusStyle.color(for: item.status)
        let startX = xPosition(for: item.start)
        let rawWidth = max(0, xPosition(for: item.end) - startX)
        let availableWidth = max(10, timelineWidth - startX)
        let preferredMinimum = item.isOpenEnded ? CGFloat(46) : CGFloat(10)
        let width = min(max(rawWidth, preferredMinimum), availableWidth)

        return ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.opacity(item.isOpenEnded ? 0.72 : 0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(color.opacity(0.9), lineWidth: 1)
                )
            if item.isOpenEnded {
                if width > 34 {
                    Text("now")
                        .font(.sora(8, weight: .semibold).monospaced())
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.trailing, 7)
                } else {
                    Circle()
                        .fill(.white.opacity(0.86))
                        .frame(width: 5, height: 5)
                        .padding(.trailing, 5)
                }
            }
        }
        .frame(width: width, height: 16)
        .offset(x: startX)
    }

    private var helpText: String {
        [
            item.title,
            "status: \(item.status)",
            "type: \(item.type)",
            "valid: \(MemoryFormat.timestamp(item.start))",
            "invalid: \(invalidLabel)",
            "duration: \(MemoryGanttDurationFormatter.string(from: item.duration))",
        ].joined(separator: "\n")
    }

    private var invalidLabel: String {
        if item.isOpenEnded {
            return "now"
        }
        return MemoryFormat.timestamp(item.memory.invalidAt ?? item.end)
    }

    private func xPosition(for time: Double) -> CGFloat {
        let span = max(domain.end - domain.start, 1)
        let ratio = (time - domain.start) / span
        return CGFloat(min(max(ratio, 0), 1)) * timelineWidth
    }
}

private enum MemoryGanttDurationFormatter {
    static func string(from seconds: Double) -> String {
        let seconds = max(0, seconds)
        if seconds >= 365 * 86_400 {
            return String(format: "%.1fy", seconds / (365 * 86_400))
        }
        if seconds >= 86_400 {
            return "\(Int(seconds / 86_400))d"
        }
        if seconds >= 3_600 {
            return "\(Int(seconds / 3_600))h"
        }
        if seconds >= 60 {
            return "\(Int(seconds / 60))m"
        }
        return "\(Int(seconds))s"
    }
}
