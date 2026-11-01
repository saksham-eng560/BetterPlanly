//
//  TodayView.swift
//  Planly
//
//  The website's main page: day header, week strip, timeline, then the checklist.
//

import SwiftUI

struct TodayView: View {
    @Environment(PlanStore.self) private var plan
    @State private var openTaskId: Int?
    @State private var showNewTask = false
    @State private var showImport = false
    @State private var datePickTask: PlanTask?

    private var isToday: Bool { plan.selectedDate == plan.today }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    WeekStrip()
                    if plan.offline || plan.loadError != nil {
                        OfflineCard()
                    }
                    TimelineSection(openTaskId: $openTaskId, onImport: { showImport = true })
                    ChecklistSection(openTaskId: $openTaskId, datePickTask: $datePickTask)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .refreshable { await plan.refresh() }
            .planlyScreen()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isToday {
                        Button("Today") { select(plan.today) }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showImport = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    Button { showNewTask = true } label: {
                        Label("New task", systemImage: "plus")
                    }
                }
            }
            .sheet(item: Binding(get: { openTaskId.map(TaskRef.init) }, set: { openTaskId = $0?.id })) { ref in
                TaskDetailView(taskId: ref.id)
            }
            .sheet(isPresented: $showNewTask) { NewTaskView(date: plan.selectedDate) }
            .sheet(isPresented: $showImport) { ImportView() }
            .sheet(item: $datePickTask) { task in MoveDatePicker(task: task) }
        }
        // refresh every 60 s while the screen is visible
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled { await plan.refresh() }
            }
        }
    }

    private var header: some View {
        let tasks = plan.dayTasks
        let done = tasks.filter(\.isDone).count
        return VStack(alignment: .leading, spacing: 4) {
            DisplayTitle(text: isToday ? "Today" : PlanDates.weekdayLong(plan.selectedDate))
            HStack(spacing: 8) {
                Text(isToday ? "\(PlanDates.weekdayLong(plan.selectedDate)), \(PlanDates.dayMonth(plan.selectedDate))"
                             : PlanDates.dayMonth(plan.selectedDate))
                if !tasks.isEmpty {
                    Text("·")
                    Text("\(done) of \(tasks.count) done").monospacedDigit()
                }
            }
            .font(.subheadline)
            .foregroundStyle(Palette.secondary)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private func select(_ date: String) {
        let needsFetch = PlanDates.weekStart(date) != PlanDates.weekStart(plan.selectedDate)
        plan.selectedDate = date
        if needsFetch { Task { await plan.refresh() } }
    }
}

/// Wraps a task id so `.sheet(item:)` can present it; the sheet reads the live task from the store.
struct TaskRef: Identifiable { let id: Int }

/// "Can't reach Planly on your Mac" with Retry; the last data stays on screen below it.
struct OfflineCard: View {
    @Environment(PlanStore.self) private var plan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(plan.offline ? "Can't reach Planly on your Mac" : "Something went wrong",
                  systemImage: plan.offline ? "wifi.exclamationmark" : "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(Palette.label)
            Text(plan.offline
                 ? "Is it running with `make phone`, and is this iPhone on the same Wi-Fi?"
                 : (plan.loadError ?? ""))
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
            HStack {
                if let updated = plan.lastUpdated ?? SharedStore.snapshot?.savedAt {
                    Text("Showing data from \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(Palette.tertiary)
                }
                Spacer()
                Button {
                    Task { await plan.refresh() }
                } label: {
                    if plan.isLoading { ProgressView() } else { Text("Retry").fontWeight(.semibold) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .glassCard(tint: Palette.red)
    }
}

/// Mon–Sun with a progress dot per day; tap to select.
struct WeekStrip: View {
    @Environment(PlanStore.self) private var plan

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PlanDates.week(of: plan.selectedDate), id: \.self) { day in
                dayButton(day)
            }
        }
    }

    private func dayButton(_ day: String) -> some View {
        let tasks = plan.tasks(on: day)
        let selected = day == plan.selectedDate
        let isToday = day == plan.today
        let allDone = !tasks.isEmpty && tasks.allSatisfy(\.isDone)
        return Button {
            let needsFetch = PlanDates.weekStart(day) != PlanDates.weekStart(plan.selectedDate)
            plan.selectedDate = day
            if needsFetch { Task { await plan.refresh() } }
        } label: {
            VStack(spacing: 4) {
                Text(PlanDates.weekdayShort(day)).font(.caption2.weight(.medium))
                    .foregroundStyle(selected ? Palette.ink.opacity(0.7) : Palette.tertiary)
                Text(PlanDates.dayNumber(day)).font(.headline.monospacedDigit())
                    .foregroundStyle(selected ? Palette.ink : Palette.label)
                Circle()
                    .fill(tasks.isEmpty ? .clear : (allDone ? Palette.lime : (selected ? Palette.ink : Palette.secondary)))
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.white.opacity(isToday ? 0.14 : 0.06)))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(PlanDates.weekdayLong(day)), \(PlanDates.dayMonth(day))\(isToday ? ", today" : "")")
        .accessibilityValue(tasks.isEmpty ? "Nothing planned" : "\(tasks.filter(\.isDone).count) of \(tasks.count) done")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
