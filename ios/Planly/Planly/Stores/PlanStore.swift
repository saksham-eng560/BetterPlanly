//
//  PlanStore.swift
//  Planly
//
//  Tasks, missed and unscheduled items, the server state, every mutation and its Undo toast.
//  The Mac's database is the source of truth: every mutation goes to the API, then the store refreshes.
//

import Foundation
import Observation

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var changeSetId: Int?
    var isError = false
}

@Observable
final class PlanStore {
    /// Tasks for the checklist window (this week's Monday + 14 days) and the selected week.
    private(set) var tasks: [PlanTask] = []
    private(set) var missed: [PlanTask] = []
    private(set) var unscheduled: [PlanTask] = []
    private(set) var state: AppState?
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    /// Set when the last refresh couldn't reach the Mac; the last data stays on screen.
    private(set) var offline = false
    private(set) var loadError: String?

    var selectedDate = PlanDates.today()
    var today = PlanDates.today()
    var toast: Toast?

    /// Set by the app so mutations can tell the agent what changed.
    weak var agent: AgentStore?

    private var client: APIClient? { SharedStore.client }
    private var toastTask: Task<Void, Never>?

    init() {
        if let snapshot = SharedStore.snapshot, snapshot.date == today { tasks = snapshot.tasks }
    }

    // MARK: Derived

    var checklistStart: String { PlanDates.weekStart(today) }
    var checklistEnd: String { PlanDates.addDays(checklistStart, 13) }

    var dayTasks: [PlanTask] { tasks.filter { $0.date == selectedDate } }

    /// Tasks the checklist shows from the dated window.
    var checklistTasks: [PlanTask] {
        tasks.filter { guard let d = $0.date else { return false }; return d >= checklistStart && d <= checklistEnd }
    }

    func tasks(on date: String) -> [PlanTask] { tasks.filter { $0.date == date } }

    var isConfigured: Bool { client != nil }

    // MARK: Loading

    func refresh() async {
        guard let client else { return }
        let now = PlanDates.today()
        if now != today {
            if selectedDate == today { selectedDate = now }
            today = now
        }
        isLoading = true
        defer { isLoading = false }

        // fetch the checklist window plus whatever week is selected
        let selectedWeek = PlanDates.weekStart(selectedDate)
        let start = min(checklistStart, selectedWeek)
        let end = max(checklistEnd, PlanDates.addDays(selectedWeek, 6))
        do {
            async let range = client.tasks(start: start, end: end)
            async let missedTasks = client.missed(before: today)
            async let undated = client.unscheduled()
            async let appState = client.state(today: today)
            tasks = try await range
            missed = try await missedTasks
            unscheduled = try await undated
            state = try? await appState
            offline = false
            loadError = nil
            lastUpdated = .now
            await Sync.afterRefresh(tasks: tasks, today: today)
        } catch {
            offline = error.isOffline
            loadError = error.isOffline ? nil : error.userMessage
        }
    }

    // MARK: Mutations

    func setDone(_ task: PlanTask, _ done: Bool) async {
        apply(task.id) { $0.status = done ? .done : .todo }  // optimistic
        await mutate(done ? "Completed “\(task.title)”" : "Reopened “\(task.title)”") { client in
            done ? try await client.complete(task.id) : try await client.uncomplete(task.id)
        }
    }

    func toggleDone(_ task: PlanTask) async { await setDone(task, !task.isDone) }

    func reschedule(_ task: PlanTask, to date: String?) async {
        let label = date.map { "Moved “\(task.title)” to \(PlanDates.relativeDay($0, today: today))" }
            ?? "Moved “\(task.title)” to Unscheduled"
        await mutate(label) { try await $0.reschedule(task.id, to: date) }
    }

    func setStep(_ item: ChecklistItem, of task: PlanTask, done: Bool) async {
        apply(task.id) { t in
            if let i = t.checklist.firstIndex(where: { $0.id == item.id }) { t.checklist[i].done = done }
        }
        await mutate(done ? "Ticked “\(item.title)”" : "Unticked “\(item.title)”") {
            try await $0.setChecklist(item.id, done: done)
        }
    }

    func update(_ task: PlanTask, _ fields: [String: JSONValue]) async {
        guard !fields.isEmpty else { return }
        await mutate("Updated “\(task.title)”") { try await $0.updateTask(task.id, fields) }
    }

    func delete(_ task: PlanTask) async {
        tasks.removeAll { $0.id == task.id }
        await mutate("Deleted “\(task.title)”") { try await $0.deleteTask(task.id) }
    }

    @discardableResult
    func create(_ fields: [String: JSONValue], title: String) async -> Bool {
        await mutate("Added “\(title)”") { try await $0.createTask(fields) }
    }

    /// Undo a change set from a toast or History.
    func undo(_ changeSetId: Int) async {
        guard let client else { return }
        do {
            _ = try await client.undo(changeSetId)
            agent?.markUndone([changeSetId])
            show(Toast(message: "Undone"))
        } catch {
            show(Toast(message: error.userMessage, isError: true))
        }
        await refresh()
    }

    /// Runs one API mutation, shows its toast with Undo, tells the agent, and refreshes.
    @discardableResult
    private func mutate(_ message: String, _ call: (APIClient) async throws -> TaskChange) async -> Bool {
        guard let client else { return false }
        var succeeded = false
        do {
            let change = try await call(client)
            if let task = change.task { replace(task) }
            show(Toast(message: message, changeSetId: change.changeSet?.id))
            if let id = change.changeSet?.id { agent?.notifyChange(id) }
            succeeded = true
        } catch {
            show(Toast(message: error.userMessage, isError: true))
        }
        await refresh()
        return succeeded
    }

    private func apply(_ id: Int, _ edit: (inout PlanTask) -> Void) {
        for list in [\PlanStore.tasks, \PlanStore.missed, \PlanStore.unscheduled] {
            if let i = self[keyPath: list].firstIndex(where: { $0.id == id }) { edit(&self[keyPath: list][i]) }
        }
    }

    private func replace(_ task: PlanTask) {
        apply(task.id) { $0 = task }
    }

    // MARK: Toasts

    func show(_ toast: Toast) {
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(toast.changeSetId == nil ? 3 : 6))
            if !Task.isCancelled, self.toast?.id == toast.id { self.toast = nil }
        }
    }
}
