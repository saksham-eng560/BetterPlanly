//
//  Models.swift
//  Planly (shared by the app and the widget)
//
//  Mirrors the backend's JSON (docs/API.md). Keys are snake_case on the wire and decoded with
//  `.convertFromSnakeCase`; enums fall back to a default for values this app doesn't know yet.
//

import Foundation

nonisolated enum TaskType: String, Codable, CaseIterable, Identifiable, Sendable {
    case study, work, reading, fitness, meeting, habit, errand, personal, other

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TaskType(rawValue: raw) ?? .other
    }
}

nonisolated enum Priority: String, Codable, CaseIterable, Identifiable, Sendable {
    case high, medium, low

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Priority(rawValue: raw) ?? .medium
    }
}

nonisolated enum TaskStatus: String, Codable, Sendable {
    case todo, done, skipped

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TaskStatus(rawValue: raw) ?? .todo
    }
}

nonisolated struct ChecklistItem: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var title: String
    var done: Bool
    var position: Int
}

nonisolated struct Resource: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var title: String
    var url: String?
    var kind: String
    var note: String
    var addedBy: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "link"
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        addedBy = try c.decodeIfPresent(String.self, forKey: .addedBy) ?? "user"
    }
}

/// A Planly task. Named `PlanTask` so it doesn't clash with Swift's `Task`.
nonisolated struct PlanTask: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var planId: Int?
    var title: String
    var type: TaskType
    var date: String?
    var start: String?
    var durationMin: Int?
    var priority: Priority
    var status: TaskStatus
    var completedAt: Date?
    var notes: String
    var section: String?
    var position: Int
    var tags: [String]
    var checklist: [ChecklistItem]
    var resources: [Resource]

    var isDone: Bool { status == .done }

    /// "09:30–11:00", "09:30" or nil.
    var timeRange: String? {
        guard let start else { return nil }
        if let end = PlanDates.endTime(start, durationMin) { return "\(start)–\(end)" }
        return start
    }

    /// "2/5" when the task has steps.
    var stepsLabel: String? {
        checklist.isEmpty ? nil : "\(checklist.filter(\.done).count)/\(checklist.count)"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        planId = try c.decodeIfPresent(Int.self, forKey: .planId)
        title = try c.decode(String.self, forKey: .title)
        type = try c.decodeIfPresent(TaskType.self, forKey: .type) ?? .other
        date = try c.decodeIfPresent(String.self, forKey: .date)
        start = try c.decodeIfPresent(String.self, forKey: .start)
        durationMin = try c.decodeIfPresent(Int.self, forKey: .durationMin)
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? .medium
        status = try c.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .todo
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        section = try c.decodeIfPresent(String.self, forKey: .section)
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        checklist = try c.decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? []
        resources = try c.decodeIfPresent([Resource].self, forKey: .resources) ?? []
    }
}

nonisolated struct ChangeSet: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var actor: String
    var summary: String
    var createdAt: Date
    var undoneAt: Date?
    var undoOf: Int?
}

/// What every mutation returns.
nonisolated struct TaskChange: Codable, Sendable {
    var task: PlanTask?
    var changeSet: ChangeSet?
}

nonisolated struct PlanRef: Codable, Hashable, Sendable {
    var id: Int
    var title: String
    var source: String?
    var sourceRef: String?
}

nonisolated struct ImportResult: Codable, Sendable {
    var plan: PlanRef?
    var plans: [PlanRef]?
    var skipped: [String]?
    var created: Int
    var updated: Int
    var unchanged: Int
    var changeSet: ChangeSet?
}

nonisolated struct AgentInfo: Codable, Hashable, Sendable {
    var model: String
    var reachable: Bool
    var busy: Bool
}

nonisolated struct AppState: Codable, Sendable {
    var tasks: Int
    var done: Int
    var missed: Int
    var lastChangeAt: Date?
    var agent: AgentInfo
    var notionConfigured: Bool
    var webSearchEnabled: Bool
}

nonisolated struct ThreadMessage: Codable, Sendable {
    var role: String
    var content: String
    var name: String?
    var toolCalls: [String]?
}

nonisolated struct AgentThread: Codable, Sendable {
    var messages: [ThreadMessage]
}

/// One entry of the agent's `changes` event.
nonisolated struct AgentChange: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var summary: String
    var undone: Bool
}

/// A JSON value for request bodies, so PATCH can send an explicit `null` (e.g. clear a time).
nonisolated enum JSONValue: Encodable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case strings([String])
    case intArray([Int])
    case null

    init(_ value: String?) { self = value.map(JSONValue.string) ?? .null }
    init(_ value: Int?) { self = value.map(JSONValue.int) ?? .null }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .strings(let v): try c.encode(v)
        case .intArray(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

// MARK: - Coding

nonisolated enum PlanlyJSON {
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            guard let date = parseTimestamp(raw) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad timestamp \(raw)")
            }
            return date
        }
        return d
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }

    /// Parses server timestamps leniently: Python sends up to 6 fractional digits, "Z" or "+00:00",
    /// and occasionally no zone at all (read as UTC).
    static func parseTimestamp(_ raw: String) -> Date? {
        var text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")
        var fraction = 0.0
        if let dot = text.firstIndex(of: ".") {
            var end = text.index(after: dot)
            while end < text.endIndex, text[end].isNumber { end = text.index(after: end) }
            fraction = Double("0" + text[dot..<end]) ?? 0
            text.removeSubrange(dot..<end)
        }
        let hasZone = text.hasSuffix("Z") || text.dropFirst(19).contains("+") || text.dropFirst(19).contains("-")
        if !hasZone { text += "Z" }
        guard let date = try? Date(text, strategy: .iso8601) else { return nil }
        return date.addingTimeInterval(fraction)
    }
}
