//
//  NewTaskView.swift
//  Planly
//
//  The + sheet: title, type, date, optional time, duration, priority and notes.
//

import SwiftUI

struct NewTaskView: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.dismiss) private var dismiss
    let date: String

    @State private var title = ""
    @State private var type: TaskType = .study
    @State private var day = Date.now
    @State private var scheduled = true
    @State private var hasTime = false
    @State private var time = Date.now
    @State private var duration = 60
    @State private var priority: Priority = .medium
    @State private var notes = ""
    @State private var saving = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you want to do?", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.done)
                    Picker("Type", selection: $type) {
                        ForEach(TaskType.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                }
                Section {
                    Toggle("On a day", isOn: $scheduled)
                    if scheduled {
                        DatePicker("Date", selection: $day, displayedComponents: .date)
                        Toggle("At a time", isOn: $hasTime)
                        if hasTime {
                            DatePicker("Start", selection: $time, displayedComponents: .hourAndMinute)
                        }
                    }
                    Stepper("Duration: \(duration == 0 ? "none" : PlanDates.formatDuration(duration))",
                            value: $duration, in: 0...600, step: 15)
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical).lineLimit(2...6)
                }
            }
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
        .onAppear {
            day = PlanDates.parseDate(date) ?? .now
            titleFocused = true
        }
    }

    private func save() async {
        saving = true
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        var fields: [String: JSONValue] = [
            "title": .string(trimmed),
            "type": .string(type.rawValue),
            "priority": .string(priority.rawValue),
            "notes": .string(notes),
        ]
        if scheduled {
            fields["date"] = .string(PlanDates.isoDate(day))
            if hasTime { fields["start"] = .string(PlanDates.timeOf(PlanDates.nowMinutes(time))) }
        }
        if duration > 0 { fields["duration_min"] = .int(duration) }
        if await plan.create(fields, title: trimmed) { dismiss() }
        saving = false
    }
}
