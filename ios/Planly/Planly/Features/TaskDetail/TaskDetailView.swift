//
//  TaskDetailView.swift
//  Planly
//
//  Everything about one task: times, notes, tags, steps and resources, with complete/reopen, move,
//  quick edits (PATCH), delete and "Ask the agent about this".
//

import SwiftUI

struct TaskDetailView: View {
    @Environment(PlanStore.self) private var plan
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let taskId: Int

    @State private var fetched: PlanTask?
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var datePickTask: PlanTask?

    /// The live task from the store, or the one fetched on open (e.g. from a notification).
    private var task: PlanTask? {
        (plan.tasks + plan.missed + plan.unscheduled).first { $0.id == taskId } ?? fetched
    }

    var body: some View {
        NavigationStack {
            Group {
                if let task {
                    content(task)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .planlyScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if task != nil {
                    ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
                }
            }
            .sheet(isPresented: $editing) {
                if let task { EditTaskView(task: task) }
            }
            .sheet(item: $datePickTask) { task in MoveDatePicker(task: task) }
            .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard let task else { return }
                    dismiss()
                    Task { await plan.delete(task) }
                }
            } message: {
                Text("You can undo this from the toast or History.")
            }
        }
        .presentationDragIndicator(.visible)
        .task {
            if task == nil, let client = SharedStore.client { fetched = try? await client.task(taskId) }
        }
    }

    private func content(_ task: PlanTask) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // type and title
                VStack(alignment: .leading, spacing: 10) {
                    Label(task.type.label, systemImage: task.type.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(task.type.color))
                    Text(task.title)
                        .font(.title.weight(.light))
                        .foregroundStyle(Palette.label)
                        .accessibilityAddTraits(.isHeader)
                    if let section = task.section {
                        Text(section).font(.subheadline).foregroundStyle(Palette.tertiary)
                    }
                }

                timeCard(task)

                if !task.notes.isEmpty {
                    card("Notes") {
                        Text(task.notes).foregroundStyle(Palette.secondary).textSelection(.enabled)
                    }
                }

                if !task.tags.isEmpty {
                    HStack { ForEach(task.tags, id: \.self) { Pill(text: "#\($0)") } }
                }

                if !task.checklist.isEmpty {
                    card("Steps · \(task.stepsLabel ?? "")") {
                        ForEach(task.checklist.sorted { $0.position < $1.position }) { item in
                            Button {
                                Task { await plan.setStep(item, of: task, done: !item.done) }
                            } label: {
                                HStack(spacing: 12) {
                                    TickBox(done: item.done, tint: task.type.color, size: 22)
                                    Text(item.title)
                                        .foregroundStyle(item.done ? Palette.tertiary : Palette.label)
                                        .strikethrough(item.done, color: Palette.tertiary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                                .frame(minHeight: 36)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.title)
                            .accessibilityValue(item.done ? "Done" : "Not done")
                        }
                    }
                }

                if !task.resources.isEmpty {
                    card("Resources") {
                        ForEach(task.resources) { resource in
                            Button {
                                if let s = resource.url, let url = URL(string: s) { openURL(url) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: resource.url == nil ? "doc.text" : "link")
                                        .foregroundStyle(Palette.secondary)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(resource.title).foregroundStyle(Palette.label).multilineTextAlignment(.leading)
                                        Text([resource.kind, resource.note].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.footnote).foregroundStyle(Palette.tertiary).lineLimit(2)
                                    }
                                    Spacer()
                                    if resource.url != nil {
                                        Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(Palette.tertiary)
                                    }
                                }
                                .frame(minHeight: 40)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(resource.url == nil)
                        }
                    }
                }

                actions(task)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
    }

    private func timeCard(_ task: PlanTask) -> some View {
        HStack(spacing: 0) {
            stat("Date", task.date.map { PlanDates.relativeDay($0, today: plan.today) } ?? "Unscheduled")
            Divider().overlay(Palette.hairline)
            stat("Time", task.timeRange ?? "Anytime")
            Divider().overlay(Palette.hairline)
            stat("Duration", task.durationMin.map(PlanDates.formatDuration) ?? "—")
            Divider().overlay(Palette.hairline)
            stat("Priority", task.priority.label, color: task.priority == .high ? Palette.flag : Palette.label)
        }
        .padding(.vertical, 12)
        .glassCard(radius: 20)
    }

    private func stat(_ label: String, _ value: String, color: Color = Palette.label) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Palette.tertiary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.tertiary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }

    private func actions(_ task: PlanTask) -> some View {
        VStack(spacing: 10) {
            Button {
                Task { await plan.toggleDone(task) }
            } label: {
                Label(task.isDone ? "Reopen" : "Complete", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(task.isDone ? AnyShapeStyle(.white.opacity(0.16)) : AnyShapeStyle(Color.white)))
                    .foregroundStyle(task.isDone ? Palette.label : Palette.ink)
            }
            HStack(spacing: 10) {
                Menu {
                    MoveMenuItems(task: task, datePickTask: $datePickTask)
                } label: {
                    secondaryLabel("Move", "arrow.right.circle")
                }
                Button {
                    dismiss()
                    router.ask("About task #\(task.id) “\(task.title)”: ")
                } label: {
                    secondaryLabel("Ask the agent", "sparkles")
                }
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(Palette.red)
            }
        }
        .padding(.top, 4)
    }

    private func secondaryLabel(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(.white.opacity(0.14)))
            .foregroundStyle(Palette.label)
    }
}

/// Quick edit of title, time, duration and priority; only changed fields are sent.
struct EditTaskView: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.dismiss) private var dismiss
    let task: PlanTask

    @State private var title = ""
    @State private var type: TaskType = .other
    @State private var hasTime = false
    @State private var time = Date.now
    @State private var duration = 0
    @State private var priority: Priority = .medium
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Picker("Type", selection: $type) {
                        ForEach(TaskType.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                }
                Section {
                    Toggle("Set a time", isOn: $hasTime)
                    if hasTime {
                        DatePicker("Start", selection: $time, displayedComponents: .hourAndMinute)
                    }
                    Stepper("Duration: \(duration == 0 ? "none" : PlanDates.formatDuration(duration))",
                            value: $duration, in: 0...600, step: 15)
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...8)
                }
            }
            .navigationTitle("Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        title = task.title
        type = task.type
        hasTime = task.start != nil
        if let start = task.start, let date = PlanDates.dateTime(task.date ?? PlanDates.today(), start) { time = date }
        duration = task.durationMin ?? 0
        priority = task.priority
        notes = task.notes
    }

    private func save() {
        var fields: [String: JSONValue] = [:]
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if trimmed != task.title { fields["title"] = .string(trimmed) }
        if type != task.type { fields["type"] = .string(type.rawValue) }
        let start = hasTime ? PlanDates.timeOf(PlanDates.nowMinutes(time)) : nil
        if start != task.start { fields["start"] = JSONValue(start) }
        let newDuration = duration == 0 ? nil : duration
        if newDuration != task.durationMin { fields["duration_min"] = JSONValue(newDuration) }
        if priority != task.priority { fields["priority"] = .string(priority.rawValue) }
        if notes != task.notes { fields["notes"] = .string(notes) }
        dismiss()
        Task { await plan.update(task, fields) }
    }
}
