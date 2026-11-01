import Foundation

/// Local-date helpers, ported from frontend/src/lib/dates.ts.
/// Planly dates are local wall-clock "YYYY-MM-DD" strings and times are "HH:MM".
enum PlanDates {
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        cal.firstWeekday = 2 // Monday, like the web app
        return cal
    }

    static func iso(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func parse(_ iso: String) -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? Date()
    }

    static func today(_ now: Date = Date()) -> String { iso(now) }

    static func addDays(_ iso: String, _ days: Int) -> String {
        self.iso(calendar.date(byAdding: .day, value: days, to: parse(iso)) ?? parse(iso))
    }

    /// Monday of the week containing `iso`.
    static func weekStart(_ iso: String) -> String {
        let weekday = calendar.component(.weekday, from: parse(iso)) // 1 = Sunday
        return addDays(iso, -((weekday + 5) % 7))
    }

    static func nextMonday(_ iso: String) -> String { addDays(weekStart(iso), 7) }

    /// Local time with UTC offset, e.g. 2026-10-30T10:05:00+05:30 (what the agent expects).
    static func localNowISO(_ now: Date = Date()) -> String {
        let c = calendar.dateComponents([.hour, .minute, .second], from: now)
        let offset = TimeZone.current.secondsFromGMT(for: now) / 60
        let sign = offset >= 0 ? "+" : "-"
        return String(format: "%@T%02d:%02d:%02d%@%02d:%02d", iso(now), c.hour ?? 0, c.minute ?? 0, c.second ?? 0,
                      sign, abs(offset) / 60, abs(offset) % 60)
    }

    static func minutes(_ time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    /// Minutes since local midnight.
    static func nowMinutes(_ now: Date = Date()) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: now)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func timeOf(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    static func formatDuration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func endTime(_ start: String, _ duration: Int?) -> String? {
        guard let duration, duration > 0 else { return nil }
        return timeOf(minutes(start) + duration)
    }

    /// Share of [start, start + duration) elapsed at `now`; 0 outside it.
    static func elapsedShare(start: String?, duration: Int?, now: Int?) -> Double {
        guard let now, let start, let duration, duration > 0 else { return 0 }
        let from = minutes(start)
        return now >= from && now < from + duration ? Double(now - from) / Double(duration) : 0
    }

    /// The Date a task starts at, for reminders.
    static func dateTime(date: String, time: String) -> Date? {
        let m = minutes(time)
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: parse(date))
    }

    private static func format(_ iso: String, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: parse(iso))
    }

    static func weekdayLong(_ iso: String) -> String { format(iso, "EEEE") }
    static func weekdayShort(_ iso: String) -> String { format(iso, "EEE") }
    static func dayNumber(_ iso: String) -> String { format(iso, "d") }
    static func dayMonth(_ iso: String) -> String { format(iso, "d MMMM") }
    static func shortDay(_ iso: String) -> String { format(iso, "EEE d MMM") }

    /// "Today", "Tomorrow", "Yesterday" or a short date.
    static func relativeDay(_ iso: String, today: String = PlanDates.today()) -> String {
        if iso == today { return "Today" }
        if iso == addDays(today, 1) { return "Tomorrow" }
        if iso == addDays(today, -1) { return "Yesterday" }
        return shortDay(iso)
    }
}
