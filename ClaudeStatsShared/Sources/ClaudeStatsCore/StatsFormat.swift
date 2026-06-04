import Foundation

public enum StatsFormat {
    public static func tokens(_ count: Int) -> String {
        let value = Double(count)
        return switch abs(count) {
        case 1_000_000_000...: String(format: "%.2fB", value / 1_000_000_000)
        case 1_000_000...: String(format: "%.2fM", value / 1_000_000)
        case 1_000...: String(format: "%.2fK", value / 1_000)
        default: "\(count)"
        }
    }

    public static func cost(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    public static func percentPoints(_ percent: Double) -> String {
        "\(Int(percent.rounded()))%"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(totalSeconds)s"
    }

    public static func shortDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    public static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}
