import Foundation

enum UsageDailyDateNavigator {
    static func todayStart(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: now)
    }

    static func normalized(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        min(calendar.startOfDay(for: date), todayStart(now: now, calendar: calendar))
    }

    static func stepped(from date: Date, by offset: Int, now: Date = .now, calendar: Calendar = .current) -> Date {
        let current = calendar.startOfDay(for: date)
        let stepped = calendar.date(byAdding: .day, value: offset, to: current) ?? current
        return normalized(stepped, now: now, calendar: calendar)
    }

    static func canStepForward(from date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        normalized(date, now: now, calendar: calendar) < todayStart(now: now, calendar: calendar)
    }

    static func periodKey(for date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func date(fromPeriodKey periodKey: String, calendar: Calendar = .current) -> Date? {
        let parts = periodKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let date = calendar.date(from: components) else { return nil }
        return normalized(date, calendar: calendar)
    }

    static func label(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let day = normalized(date, now: now, calendar: calendar)
        let today = todayStart(now: now, calendar: calendar)
        if day == today {
            return L10n.string("usage.daily_date.today", defaultValue: "Today")
        }

        let yesterday = stepped(from: today, by: -1, now: now, calendar: calendar)
        if day == yesterday {
            return L10n.string("usage.daily_date.yesterday", defaultValue: "Yesterday")
        }

        return Format.day(day)
    }
}
