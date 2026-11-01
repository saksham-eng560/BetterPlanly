//
//  AgentStore.swift
//  Planly
//
//  The agent conversation and its run queue: one run at a time, a 409 retries after 2 s, task
//  changes are batched into one `task_event` run after 4 s of quiet (frontend/src/features/chat/agentStore.ts).
//

import Foundation
import Observation

enum ChatItem: Identifiable {
    case user(id: Int, text: String)
    case assistant(id: Int, text: String)
    case event(id: Int, text: String)
    case error(id: Int, text: String)
    case tool(id: Int, name: String, args: [String: AnyJSON], done: Bool)
    case changes(id: Int, changes: [AgentChange])

    var id: Int {
        switch self {
        case .user(let id, _), .assistant(let id, _), .event(let id, _), .error(let id, _),
             .tool(let id, _, _, _), .changes(let id, _):
            id
        }
    }
}

/// Just enough of an arbitrary JSON value to label tool calls (`args.id`, `args.title`, …).
nonisolated enum AnyJSON: Decodable, Sendable {
    case string(String), number(Double), bool(Bool), other

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else { self = .other }
    }

    var text: String? {
        switch self {
        case .string(let s): s
        case .number(let n): n.rounded() == n ? String(Int(n)) : String(n)
        case .bool(let b): String(b)
        case .other: nil
        }
    }

    var isTrue: Bool { if case .bool(true) = self { true } else { false } }
}

@Observable
final class AgentStore {
    private(set) var items: [ChatItem] = []
    private(set) var running = false
    private(set) var loaded = false

    weak var plan: PlanStore?

    private enum Run {
        case chat(String)
        case taskEvent([Int])
        case dayReview

        var body: [String: JSONValue] {
            var body: [String: JSONValue] = ["now": .string(PlanDates.localNowISO())]
            switch self {
            case .chat(let message):
                body["trigger"] = .string("chat"); body["message"] = .string(message)
            case .taskEvent(let ids):
                body["trigger"] = .string("task_event"); body["change_set_ids"] = .intArray(ids)
            case .dayReview:
                body["trigger"] = .string("day_review")
            }
            return body
        }
    }

    private var queue: [Run] = []
    private var pendingChangeIds: [Int] = []
    private var debounce: Task<Void, Never>?
    private var nextId = 1
    private var loading = false

    private func newId() -> Int { defer { nextId += 1 }; return nextId }

    // MARK: Public

    func load() async {
        guard !loaded, !loading, let client = SharedStore.client else { return }
        loading = true
        defer { loading = false }
        do {
            let thread = try await client.thread()
            var history: [ChatItem] = []
            for message in thread.messages {
                switch message.role {
                case "tool":
                    continue
                case "assistant":
                    for name in message.toolCalls ?? [] {
                        history.append(.tool(id: newId(), name: name, args: [:], done: true))
                    }
                    if !message.content.isEmpty { history.append(.assistant(id: newId(), text: message.content)) }
                case "event":
                    history.append(.event(id: newId(), text: message.content))
                default:
                    history.append(.user(id: newId(), text: message.content))
                }
            }
            items = history + items
            loaded = true
        } catch {
            // leave `loaded` false so opening the tab again retries
        }
    }

    func send(_ message: String) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        enqueue(.chat(text))
    }

    /// Collects a change and sends one `task_event` run after 4 s without further changes.
    func notifyChange(_ changeSetId: Int) {
        guard SharedStore.reactToChanges else { return }
        pendingChangeIds.append(changeSetId)
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !pendingChangeIds.isEmpty else { return }
            let ids = pendingChangeIds
            pendingChangeIds = []
            enqueue(.taskEvent(ids))
        }
    }

    /// Once per calendar day, when there are missed tasks, ask the agent to review them.
    func dayReviewIfNeeded(missed: Int, today: String) {
        guard missed > 0, SharedStore.lastDayReview != today else { return }
        SharedStore.lastDayReview = today
        enqueue(.dayReview)
    }

    /// Undone changes drop out of the pending batch and show as undone in change cards.
    func markUndone(_ ids: [Int]) {
        pendingChangeIds.removeAll { ids.contains($0) }
        items = items.map { item in
            guard case .changes(let id, var changes) = item else { return item }
            for i in changes.indices where ids.contains(changes[i].id) { changes[i].undone = true }
            return .changes(id: id, changes: changes)
        }
    }

    // MARK: Queue

    private func enqueue(_ run: Run) {
        queue.append(run)
        pump()
    }

    private func pump() {
        guard !running, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        Task { await perform(next) }
    }

    private func perform(_ run: Run) async {
        guard let client = SharedStore.client else { return }
        running = true
        var streamingText = false
        do {
            let stream = try await client.agentRun(run.body)
            for try await event in stream {
                handle(event, streamingText: &streamingText)
            }
        } catch let error as APIError where error.status == 409 {
            // another client's run is active; retry shortly
            queue.insert(run, at: 0)
            try? await Task.sleep(for: .seconds(2))
        } catch {
            items.append(.error(id: newId(), text: error.isOffline
                ? "Can't reach the agent on your Mac."
                : error.userMessage))
        }
        running = false
        await plan?.refresh()
        pump()
    }

    private func handle(_ event: SSEEvent, streamingText: inout Bool) {
        struct Message: Decodable { var role: String; var content: String }
        struct Token: Decodable { var text: String }
        struct ToolCall: Decodable { var name: String; var args: [String: AnyJSON]? }
        struct ErrorBody: Decodable { var message: String }

        switch event.event {
        case "message":
            guard let m = event.decode(Message.self) else { return }
            items.append(m.role == "event" ? .event(id: newId(), text: m.content) : .user(id: newId(), text: m.content))
        case "token":
            guard let t = event.decode(Token.self) else { return }
            if streamingText, let i = items.lastIndex(where: { if case .assistant = $0 { true } else { false } }),
               case .assistant(let id, let text) = items[i] {
                items[i] = .assistant(id: id, text: text + t.text)
            } else {
                items.append(.assistant(id: newId(), text: t.text))
            }
            streamingText = true
        case "tool_call":
            guard let call = event.decode(ToolCall.self) else { return }
            streamingText = false
            items.append(.tool(id: newId(), name: call.name, args: call.args ?? [:], done: false))
        case "tool_result":
            if let i = items.lastIndex(where: { if case .tool(_, _, _, false) = $0 { true } else { false } }),
               case .tool(let id, let name, let args, _) = items[i] {
                items[i] = .tool(id: id, name: name, args: args, done: true)
            }
            Task { await plan?.refresh() }  // show the agent's moves as they happen
        case "changes":
            if let changes = event.decode([AgentChange].self), !changes.isEmpty {
                items.append(.changes(id: newId(), changes: changes))
            }
        case "error":
            items.append(.error(id: newId(), text: event.decode(ErrorBody.self)?.message ?? "The agent hit an error."))
        default:
            break
        }
    }

    // MARK: Labels

    /// The chat label for a tool call.
    static func label(tool name: String, args: [String: AnyJSON]) -> String {
        let id = args["task_id"]?.text ?? args["id"]?.text
        let ref = id.map { "#\($0)" } ?? "a task"
        switch name {
        case "replan_day": return args["pull_earlier"]?.isTrue == true ? "Pulling the day earlier" : "Re-planning the day"
        case "reschedule_task": return "Moving \(ref)"
        case "create_task": return args["title"]?.text.map { "Adding “\($0)”" } ?? "Adding a task"
        case "update_task": return "Updating \(ref)"
        case "list_tasks": return "Looking at your tasks"
        case "get_task": return "Reading \(ref)"
        case "find_resources": return "Finding resources"
        case "save_resource": return "Saving a resource"
        case "evaluate_progress": return "Checking your progress"
        case "remember_preference": return "Remembering that"
        default: return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Event messages as short chips: drop the "[update]" prefix and the instructions after it.
    static func eventSummary(_ text: String) -> String {
        var s = text
        for prefix in ["[update]", "[day review]"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        for marker in ["Adjust the rest of today", "Bring the missed tasks"] {
            if let r = s.range(of: marker) { s = String(s[..<r.lowerBound]) }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
