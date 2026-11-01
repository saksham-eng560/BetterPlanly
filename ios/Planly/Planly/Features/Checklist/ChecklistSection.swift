//
//  ChecklistSection.swift
//  Planly
//
//  One card per section (Missed first, in red), the website's grouping and ordering
//  (frontend/src/features/checklist/Checklist.tsx). Rows tick optimistically and can be moved.
//

import SwiftUI

nonisolated enum ChecklistGrouping {
    static let noSection = "Tasks"
    static let missed = "Missed"

    /// Open tasks first; then by date (unscheduled last), time (untimed first) and source order.
    static func byUrgency(_ a: PlanTask, _ b: PlanTask) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        if a.date != b.date {
            guard let da = a.date else { return false }
            guard let db = b.date else { return true }
            return da < db
        }
        if a.start != b.start {
            guard let sa = a.start else { return true }
            guard let sb = b.start else { return false }
            return sa < sb
        }
        return a.position < b.position
    }

    /// One group per section in the order sections appear in their plans, with Missed first.
    static func groups(tasks: [PlanTask], unscheduled: [PlanTask], missed: [PlanTask]) -> [(String, [PlanTask])] {
        let missedIds = Set(missed.map(\.id))
        var seen = Set<Int>()
        let pool = (tasks + unscheduled)
            .filter { !missedIds.contains($0.id) && seen.insert($0.id).inserted }
            .sorted { ($0.planId ?? 0, $0.position, $0.id) < ($1.planId ?? 0, $1.position, $1.id) }
        var order: [String] = []
        var groups: [String: [PlanTask]] = [:]
        for task in pool {
            let key = task.section ?? noSection
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(task)
        }
        var result = order.map { ($0, groups[$0]!.sorted(by: byUrgency)) }
        if !missed.isEmpty { result.insert((self.missed, missed.sorted(by: byUrgency)), at: 0) }
        return result
    }
}

struct ChecklistSection: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var openTaskId: Int?
    @Binding var datePickTask: PlanTask?

    var body: some View {
        let groups = ChecklistGrouping.groups(tasks: plan.checklistTasks, unscheduled: plan.unscheduled, missed: plan.missed)
        let windowTasks = plan.checklistTasks
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Checklist").font(.title2.weight(.light)).foregroundStyle(Palette.label)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !windowTasks.isEmpty {
                    Text("\(windowTasks.filter(\.isDone).count) of \(windowTasks.count) done")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
            }
            .padding(.top, 8)

            if groups.isEmpty {
                Text("Import a plan and each of its sections shows up here as its own box.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
            } else {
                ForEach(groups, id: \.0) { title, tasks in
                    SectionCard(title: title, tasks: tasks, openTaskId: $openTaskId, datePickTask: $datePickTask)
                }
            }
        }
        .animation(planlyAnimation(reduceMotion), value: groups.map(\.1))
    }
}

private struct SectionCard: View {
    var title: String
    var tasks: [PlanTask]
    @Binding var openTaskId: Int?
    @Binding var datePickTask: PlanTask?
    @State private var expanded = false

    private static let rowsBeforeMore = 6

    var body: some View {
        let tint = Palette.sectionTint(title)
        let isMissed = title == ChecklistGrouping.missed
        let done = tasks.filter(\.isDone).count
        let visible = expanded ? tasks : Array(tasks.prefix(Self.rowsBeforeMore))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: isMissed ? "exclamationmark.triangle.fill" : "checklist")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(tint))
                    .accessibilityHidden(true)
                Text(title).font(.headline).foregroundStyle(Palette.label)
                Spacer()
                Text(isMissed ? "\(tasks.count)" : "\(done)/\(tasks.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.secondary)
                    .accessibilityLabel(isMissed ? "\(tasks.count) missed" : "\(done) of \(tasks.count) done")
            }
            .padding(.bottom, 6)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(visible) { task in
                ChecklistRow(task: task, tint: tint, openTaskId: $openTaskId, datePickTask: $datePickTask)
                if task.id != visible.last?.id { Divider().overlay(Palette.hairline) }
            }

            if tasks.count > Self.rowsBeforeMore {
                Button(expanded ? "Show less" : "Show all \(tasks.count)") { expanded.toggle() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(14)
        .glassCard(tint: tint)
    }
}

private struct ChecklistRow: View {
    @Environment(PlanStore.self) private var plan
    var task: PlanTask
    var tint: Color
    @Binding var openTaskId: Int?
    @Binding var datePickTask: PlanTask?

    var body: some View {
        let done = task.isDone
        let missed = !done && (task.date.map { $0 < plan.today } ?? false)
        HStack(spacing: 12) {
            Button {
                Task { await plan.toggleDone(task) }
            } label: {
                TickBox(done: done, tint: tint)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Reopen “\(task.title)”" : "Complete “\(task.title)”")
            .sensoryFeedback(.success, trigger: done) { _, new in new }

            Button {
                openTaskId = task.id
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.body)
                        .foregroundStyle(done ? Palette.tertiary : Palette.label)
                        .strikethrough(done, color: Palette.tertiary)
                        .multilineTextAlignment(.leading)
                    if let meta = meta {
                        Text(meta)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(missed ? Palette.red : (task.date == plan.today && !done ? Palette.secondary : Palette.tertiary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens details")

            Menu {
                MoveMenuItems(task: task, datePickTask: $datePickTask)
            } label: {
                Image(systemName: "arrow.right.circle")
                    .font(.title3)
                    .foregroundStyle(Palette.tertiary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Move “\(task.title)”")
        }
        .contextMenu {
            Button(done ? "Reopen" : "Complete", systemImage: done ? "arrow.uturn.backward" : "checkmark") {
                Task { await plan.toggleDone(task) }
            }
            Menu("Move to…") { MoveMenuItems(task: task, datePickTask: $datePickTask) }
            Button("Details", systemImage: "info.circle") { openTaskId = task.id }
        }
    }

    /// "Today · 09:30–11:00 · 2/5"
    private var meta: String? {
        var parts: [String] = []
        if let date = task.date { parts.append(PlanDates.relativeDay(date, today: plan.today)) }
        if let range = task.timeRange { parts.append(range) }
        else if let d = task.durationMin, d > 0 { parts.append(PlanDates.formatDuration(d)) }
        if task.section == nil { parts.append(task.type.label) }
        if let steps = task.stepsLabel { parts.append(steps) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Today / Tomorrow / Next week / Pick a date / Unscheduled.
struct MoveMenuItems: View {
    @Environment(PlanStore.self) private var plan
    var task: PlanTask
    @Binding var datePickTask: PlanTask?

    var body: some View {
        let today = plan.today
        Button("Today", systemImage: "sun.max") { move(today) }.disabled(task.date == today)
        Button("Tomorrow", systemImage: "sunrise") { move(PlanDates.addDays(today, 1)) }
            .disabled(task.date == PlanDates.addDays(today, 1))
        Button("Next week", systemImage: "calendar") { move(PlanDates.nextMonday(today)) }
        Button("Pick a date…", systemImage: "calendar.badge.clock") { datePickTask = task }
        Button("Unscheduled", systemImage: "tray") { move(nil) }.disabled(task.date == nil)
    }

    private func move(_ date: String?) {
        Task { await plan.reschedule(task, to: date) }
    }
}

/// A date picker sheet for "Pick a date…".
struct MoveDatePicker: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.dismiss) private var dismiss
    var task: PlanTask
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Move “\(task.title)”")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Move") {
                            let target = PlanDates.isoDate(date)
                            dismiss()
                            Task { await plan.reschedule(task, to: target) }
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .onAppear { date = task.date.flatMap(PlanDates.parseDate) ?? .now }
    }
}
