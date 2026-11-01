//
//  Sync.swift
//  Planly
//
//  Work that follows every refresh: the widget snapshot, reminders, the badge and widget reloads.
//  Also the background app refresh, which does the same without the UI.
//

import BackgroundTasks
import WidgetKit

enum Sync {
    static let refreshTaskId = "com.saksham.Planly.refresh"

    /// Call after the app's task list changes. `tasks` must cover today and tomorrow.
    static func afterRefresh(tasks: [PlanTask], today: String = PlanDates.today()) async {
        let todays = tasks.filter { $0.date == today }
        SharedStore.saveSnapshot(date: today, tasks: todays)
        WidgetCenter.shared.reloadAllTimelines()
        await Badge.update(openToday: todays.filter { !$0.isDone }.count)
        await Reminders.reschedule(tasks: tasks)
    }

    /// The `BGAppRefreshTask` body: fetch today and tomorrow, then update everything that depends on them.
    static func backgroundRefresh() async {
        scheduleBackgroundRefresh()
        guard let client = SharedStore.client else { return }
        let today = PlanDates.today()
        guard let tasks = try? await client.tasks(start: today, end: PlanDates.addDays(today, 1)) else { return }
        await afterRefresh(tasks: tasks, today: today)
    }

    /// Asks iOS for the next background refresh in about 30 minutes (iOS decides the actual time).
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
