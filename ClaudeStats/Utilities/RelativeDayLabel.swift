import Foundation

enum RelativeDayLabel {
    static func label(
        for date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        todayKey: String,
        yesterdayKey: String,
        todayDefaultValue: String = "Today",
        yesterdayDefaultValue: String = "Yesterday"
    ) -> String {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
            ?? today.addingTimeInterval(-86_400)
        return label(
            forDay: day,
            today: today,
            yesterday: yesterday,
            todayKey: todayKey,
            yesterdayKey: yesterdayKey,
            todayDefaultValue: todayDefaultValue,
            yesterdayDefaultValue: yesterdayDefaultValue
        )
    }

    static func label(
        forDay day: Date,
        today: Date,
        yesterday: Date,
        todayKey: String,
        yesterdayKey: String,
        todayDefaultValue: String = "Today",
        yesterdayDefaultValue: String = "Yesterday"
    ) -> String {
        if day == today {
            return L10n.string(todayKey, defaultValue: todayDefaultValue)
        }

        if day == yesterday {
            return L10n.string(yesterdayKey, defaultValue: yesterdayDefaultValue)
        }

        return Format.day(day)
    }
}
