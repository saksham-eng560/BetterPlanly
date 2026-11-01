//
//  TimelineSection.swift
//  Planly
//
//  The day's timeline: an Anytime group, type-coloured cards in time order, "Free · 1h 20m" gaps and a
//  lime now-line before the first task that starts now or later (frontend/src/features/timeline).
//

import SwiftUI

struct TimelineSection: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var openTaskId: Int?
    var onImport: () -> Void

    private static let freeGapMinutes = 30

    var body: some View {
        let tasks = plan.dayTasks
        let isToday = plan.selectedDate == plan.today
        if tasks.isEmpty {
            emptyDay
        } else {
            // re-render every 30 s so the now-line and progress ruler move
            TimelineView(.periodic(from: .now, by: 30)) { context in
                content(tasks, now: isToday ? PlanDates.nowMinutes(context.date) : nil)
            }
        }
    }

    private enum Row: Identifiable {
        case now(Int), free(Int, after: Int), task(PlanTask)
        var id: String {
            switch self {
            case .now: "now"
            case .free(_, let after): "free-\(after)"
            case .task(let t): "task-\(t.id)"
            }
        }
    }

    private func rows(_ timed: [PlanTask], now: Int?) -> [Row] {
        var rows: [Row] = []
        let nowIndex = now.flatMap { now in timed.firstIndex { PlanDates.minutes(of: $0.start!) >= now } }
        for (i, task) in timed.enumerated() {
            if let now, i == nowIndex { rows.append(.now(now)) }
            if i > 0 {
                let prev = timed[i - 1]
                let gap = PlanDates.minutes(of: task.start!) - (PlanDates.minutes(of: prev.start!) + (prev.durationMin ?? 0))
                if gap >= Self.freeGapMinutes { rows.append(.free(gap, after: prev.id)) }
            }
            rows.append(.task(task))
        }
        if let now, nowIndex == nil { rows.append(.now(now)) }
        return rows
    }

    private func content(_ tasks: [PlanTask], now: Int?) -> some View {
        let anytime = tasks.filter { $0.start == nil }.sorted { $0.position < $1.position }
        let timed = tasks.filter { $0.start != nil }.sorted { PlanDates.minutes(of: $0.start!) < PlanDates.minutes(of: $1.start!) }
        return VStack(alignment: .leading, spacing: 10) {
            if !anytime.isEmpty {
                Text("Anytime").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.tertiary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(anytime) { task in card(task, now: nil) }
                if !timed.isEmpty { Divider().overlay(Palette.hairline).padding(.vertical, 4) }
            }
            ForEach(rows(timed, now: now)) { row in
                switch row {
                case .now(let minutes):
                    NowLine(minutes: minutes)
                case .free(let gap, _):
                    Pill(text: "Free · \(PlanDates.formatDuration(gap))", color: Palette.tertiary)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Free for \(PlanDates.formatDuration(gap))")
                case .task(let task):
                    card(task, now: now)
                }
            }
        }
        .padding(12)
        .glassCard()
        .animation(planlyAnimation(reduceMotion), value: tasks)
    }

    private func card(_ task: PlanTask, now: Int?) -> some View {
        TaskCard(task: task, now: now)
            .onTapGesture { openTaskId = task.id }
            .accessibilityAction(named: task.isDone ? "Reopen" : "Complete") {
                Task { await plan.toggleDone(task) }
            }
            .contextMenu {
                Button(task.isDone ? "Reopen" : "Complete", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark") {
                    Task { await plan.toggleDone(task) }
                }
                Button("Details", systemImage: "info.circle") { openTaskId = task.id }
            }
    }

    private var emptyDay: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.secondary)
                .accessibilityHidden(true)
            Text("Nothing planned").font(.title2.weight(.light)).foregroundStyle(Palette.label)
            Text("Import a plan file or ask the agent to plan this day.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
            Button("Import a plan", action: onImport)
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(.white))
                .foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .glassCard()
    }
}

struct NowLine: View {
    var minutes: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(PlanDates.timeOf(minutes))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Palette.lime))
            Rectangle().fill(Palette.lime).frame(height: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now, \(PlanDates.timeOf(minutes))")
    }
}

/// A type-coloured timeline card.
struct TaskCard: View {
    var task: PlanTask
    var now: Int?

    var body: some View {
        let progress = PlanDates.elapsedShare(start: task.start, duration: task.durationMin, now: now)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.type.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(task.type.color))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(task.isDone ? Palette.tertiary : Palette.label)
                        .strikethrough(task.isDone, color: Palette.tertiary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if task.priority == .high && !task.isDone {
                        Image(systemName: "flag.fill").foregroundStyle(Palette.flag).font(.caption)
                            .accessibilityLabel("High priority")
                    }
                    if task.isDone {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.lime)
                            .accessibilityLabel("Done")
                    }
                }
                HStack(spacing: 8) {
                    if let range = task.timeRange {
                        Text(range).font(.subheadline.monospacedDigit()).foregroundStyle(Palette.secondary)
                    } else {
                        Text(task.type.label).font(.subheadline).foregroundStyle(Palette.secondary)
                    }
                    if let duration = task.durationMin, duration > 0 {
                        Pill(text: PlanDates.formatDuration(duration))
                    }
                    if let steps = task.stepsLabel {
                        Label(steps, systemImage: "checklist")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Palette.tertiary)
                            .accessibilityLabel("\(steps) steps done")
                    }
                }
                if progress > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule().fill(Palette.lime).frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                    .accessibilityElement()
                    .accessibilityLabel("In progress")
                    .accessibilityValue("\(Int(progress * 100)) percent")
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(task.type.color.opacity(task.isDone ? 0.06 : 0.16))
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(task.type.color).frame(width: 3).padding(.vertical, 12)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details")
        .accessibilityAddTraits(.isButton)
    }
}
