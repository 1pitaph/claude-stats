import Foundation

/// Small display formatters shared across views.
enum Format {
    /// Compact token counts: `847`, `12.34K`, `4.12M`, `2.00B`.
    static func tokens(_ count: Int) -> String {
        let n = Double(count)
        switch abs(count) {
        case 1_000_000_000...: return String(format: "%.2fB", n / 1_000_000_000)
        case 1_000_000...:     return String(format: "%.2fM", n / 1_000_000)
        case 1_000...:         return String(format: "%.2fK", n / 1_000)
        default:               return "\(count)"
        }
    }

    /// Compact byte sizes: `847 B`, `12.34 KB`, `4.12 MB`, `2.00 GB`.
    static func bytes(_ count: Int) -> String {
        let n = Double(count)
        switch abs(count) {
        case 1_000_000_000...: return String(format: "%.2f GB", n / 1_000_000_000)
        case 1_000_000...:     return String(format: "%.2f MB", n / 1_000_000)
        case 1_000...:         return String(format: "%.2f KB", n / 1_000)
        default:               return "\(count) B"
        }
    }

    /// `$0.00`, `$1.23`, `$12.34`. Always two decimals; never localizes the
    /// currency symbol away (this is an estimate, not a billing figure).
    static func cost(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    static func relativeDate(_ date: Date, now: Date = .now) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: now)
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func shortTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute())
    }

    /// Day only, no year: `May 1`, `Dec 12`.
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Compact duration: `0m`, `7m`, `1h 04m`, `3h`. Rounds to the minute.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : String(format: "%dh %02dm", h, m)
    }

    static func signedDuration(_ seconds: TimeInterval) -> String {
        signed(seconds, zero: "0m") { duration(abs($0)) }
    }

    static func signedCount(_ count: Int) -> String {
        if count == 0 { return "0" }
        return count > 0 ? "+\(count)" : "\(count)"
    }

    /// Signed compact token deltas: `+12.34K`, `-4.12M`, `0`.
    static func signedTokens(_ count: Int) -> String {
        if count == 0 { return "0" }
        let rendered = tokens(abs(count))
        return count > 0 ? "+\(rendered)" : "-\(rendered)"
    }

    static func signedCurrency(_ amount: Double) -> String {
        if abs(amount) < 0.005 { return "$0.00" }
        return amount > 0 ? "+\(cost(amount))" : "-\(cost(abs(amount)))"
    }

    private static func signed(_ value: TimeInterval, zero: String, render: (TimeInterval) -> String) -> String {
        if abs(value) < 0.5 { return zero }
        return value > 0 ? "+\(render(value))" : "-\(render(value))"
    }

    /// `0%`, `48%`, `100%` from a `0...1` ratio.
    static func percent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    /// `0%`, `48%`, `100%` from percentage points.
    static func percentPoints(_ percent: Double) -> String {
        "\(Int(percent.rounded()))%"
    }
}
