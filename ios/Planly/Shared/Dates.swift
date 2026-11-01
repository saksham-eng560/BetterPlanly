//
//  Dates.swift
//  Planly (shared)
//
//  Planly dates are local wall-clock "YYYY-MM-DD" strings and times are "HH:MM", the same as the
//  website (frontend/src/lib/dates.ts). These helpers never go through UTC.
//

import Foundation

nonisolated enum PlanDates {
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 2
        return c
    }

    static func isoDate(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 1, c.day ?? 1)
    }

    static func parseDate(_ iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func today(_ now: Date = .now) -> String { isoDate(now) }

    static func addDays(_ iso: String, _ days: Int) -> String {
        guard let date = parseDate(iso), let moved = calendar.date(byAdding: .day, value: days, to: date) else { return iso }
        return isoDate(moved)
    }

    /// Monday of the week containing `iso`.
    static func weekStart(_ iso: String) -> String {
        guard let date = parseDate(iso) else { return iso }
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        return addDays(iso, -((weekday + 5) % 7))
    }

    static func nextMonday(_ iso: String) -> String { addDays(weekStart(iso), 7) }

    /// The seven days Mon–Sun of the week containing `iso`.
    static func week(of iso: String) -> [String] {
        let monday = weekStart(iso)
        return (0..<7).map { addDays(monday, $0) }
    }

    /// Local time with UTC offset, e.g. 2026-10-30T10:05:00+05:30 (what the agent expects).
    static func localNowISO(_ now: Date = .now) -> String {
        let c = calendar.dateComponents([.hour, .minute, .second], from: now)
        let offset = TimeZone.current.secondsFromGMT(for: now) / 60
        let sign = offset >= 0 ? "+" : "-"
        let abs = Swift.abs(offset)
        return isoDate(now) + String(format: "T%02d:%02d:%02d%@%02d:%02d",
                                     c.hour ?? 0, c.minute ?? 0, c.second ?? 0, sign, abs / 60, abs % 60)
    }

    static func minutes(of time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    /// Minutes since local midnight.
    static func nowMinutes(_ now: Date = .now) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: now)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func timeOf(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    static func endTime(_ start: String, _ duration: Int?) -> String? {
        guard let duration, duration > 0 else { return nil }
        return timeOf(minutes(of: start) + duration)
    }

    /// Share of [start, start + duration) elapsed at `now`; 0 outside it.
    static func elapsedShare(start: String?, duration: Int?, now: Int?) -> Double {
        guard let now, let start, let duration, duration > 0 else { return 0 }
        let from = minutes(of: start)
        return now >= from && now < from + duration ? Double(now - from) / Double(duration) : 0
    }

    static func formatDuration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// A local `Date` at the given day and "HH:MM".
    static func dateTime(_ iso: String, _ time: String) -> Date? {
        guard let day = parseDate(iso) else { return nil }
        return calendar.date(byAdding: .minute, value: minutes(of: time), to: day)
    }

    static func weekdayLong(_ iso: String) -> String {
        parseDate(iso)?.formatted(.dateTime.weekday(.wide)) ?? iso
    }

    static func weekdayShort(_ iso: String) -> String {
        parseDate(iso)?.formatted(.dateTime.weekday(.abbreviated)) ?? iso
    }

    static func dayNumber(_ iso: String) -> String {
        parseDate(iso)?.formatted(.dateTime.day()) ?? iso
    }

    static func dayMonth(_ iso: String) -> String {
        parseDate(iso)?.formatted(.dateTime.day().month(.wide)) ?? iso
    }

    static func shortDay(_ iso: String) -> String {
        parseDate(iso)?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? iso
    }

    /// "Today", "Tomorrow", "Yesterday" or a short date.
    static func relativeDay(_ iso: String, today: String = PlanDates.today()) -> String {
        if iso == today { return "Today" }
        if iso == addDays(today, 1) { return "Tomorrow" }
        if iso == addDays(today, -1) { return "Yesterday" }
        return shortDay(iso)
    }

    static func timeAgo(_ date: Date, now: Date = .now) -> String {
        let seconds = Int(now.timeIntervalSince(date).rounded())
        if seconds < 45 { return "just now" }
        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = Int((Double(minutes) / 60).rounded())
        if hours < 24 { return "\(hours) h ago" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
