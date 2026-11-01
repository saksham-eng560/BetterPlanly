//
//  Reminders.swift
//  Planly
//
//  Local notifications shortly before each timed task, with "Mark done" and "Snooze 10 min" actions.
//

import UserNotifications

enum Reminders {
    static let category = "PLANLY_TASK"
    static let markDoneAction = "MARK_DONE"
    static let snoozeAction = "SNOOZE_10"
    private static let prefix = "task-"
    /// iOS keeps 64 pending requests; leave room for snoozes.
    private static let maxPending = 60

    static func registerCategories() {
        let done = UNNotificationAction(identifier: markDoneAction, title: "Mark done", options: [])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "Snooze 10 min", options: [])
        let category = UNNotificationCategory(identifier: category, actions: [done, snooze], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces the scheduled reminders with one per timed, not-done task in the next two days.
    static func reschedule(tasks: [PlanTask], now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        guard SharedStore.remindersEnabled else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let lead = TimeInterval(SharedStore.reminderLeadMinutes * 60)
        let horizon = now.addingTimeInterval(2 * 24 * 3600)
        let upcoming = tasks
            .filter { !$0.isDone }
            .compactMap { task -> (PlanTask, Date)? in
                guard let date = task.date, let start = task.start,
                      let begins = PlanDates.dateTime(date, start) else { return nil }
                let fire = begins.addingTimeInterval(-lead)
                return fire > now && fire < horizon ? (task, fire) : nil
            }
            .sorted { $0.1 < $1.1 }
            .prefix(maxPending)

        for (task, fire) in upcoming {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: prefix + String(task.id), content: content(for: task), trigger: trigger)
            try? await center.add(request)
        }
    }

    static func content(for task: PlanTask) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = [task.timeRange, task.type.label].compactMap { $0 }.joined(separator: " · ")
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = ["taskId": task.id]
        return content
    }

    /// Shows the same reminder again in 10 minutes.
    static func snooze(_ original: UNNotificationContent) async {
        guard let content = original.mutableCopy() as? UNMutableNotificationContent else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
        let request = UNNotificationRequest(identifier: "snooze-\(UUID().uuidString)", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

enum Badge {
    /// Shows today's open tasks on the app icon (or clears it when the badge is off).
    static func update(openToday: Int) async {
        let count = SharedStore.badgeEnabled ? openToday : 0
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}
