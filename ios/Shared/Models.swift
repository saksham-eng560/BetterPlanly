import Foundation

// The JSON shapes of the Planly API (docs/API.md), mirroring frontend/src/lib/api.ts.
// Named PlanTask, not Task, so it never shadows Swift's concurrency Task.

struct ChecklistItem: Codable, Identifiable, Hashable {
    let id: Int
    var title: String
    var done: Bool
    var position: Int
}

struct Resource: Codable, Identifiable, Hashable {
    let id: Int
    var title: String
    var url: String?
    var kind: String
    var note: String
    var addedBy: String
}

struct PlanTask: Codable, Identifiable, Hashable {
    let id: Int
    var planId: Int?
    var title: String
    var type: String
    var date: String?          // YYYY-MM-DD, local
    var start: String?         // HH:MM, local
    var durationMin: Int?
    var priority: String       // high | medium | low
    var status: String         // todo | done | skipped
    var completedAt: String?
    var notes: String
    var section: String?
    var position: Int
    var tags: [String]
    var checklist: [ChecklistItem]
    var resources: [Resource]

    var isDone: Bool { status == "done" }
    var kind: TaskKind { TaskKind(rawValue: type) ?? .other }
    var end: String? { start.flatMap { PlanDates.endTime($0, durationMin) } }
    var startMinutes: Int? { start.map(PlanDates.minutes) }
    var stepsDone: Int { checklist.filter(\.done).count }
}

struct ChangeSet: Codable, Identifiable, Hashable {
    let id: Int
    var actor: String          // user | agent | import
    var summary: String
    var createdAt: String
    var undoneAt: String?
    var undoOf: Int?
}

struct TaskChange: Codable {
    var task: PlanTask?
    var changeSet: ChangeSet?
}

struct PlanInfo: Codable, Hashable {
    var id: Int
    var title: String
    var source: String
    var sourceRef: String
}

struct ImportResult: Codable {
    var plan: PlanInfo
    var plans: [PlanInfo]
    var skipped: [String]
    var created: Int
    var updated: Int
    var unchanged: Int
    var changeSet: ChangeSet?
}

struct AgentStatus: Codable, Hashable {
    var model: String
    var reachable: Bool
    var busy: Bool?
}

struct AppState: Codable, Hashable {
    var tasks: Int
    var done: Int
    var missed: Int
    var lastChangeAt: String?
    var agent: AgentStatus
    var notionConfigured: Bool
    var webSearchEnabled: Bool
}

struct ThreadMessage: Codable {
    var role: String           // user | assistant | event | tool
    var content: String
    var name: String?
    var toolCalls: [String]?
}

struct ThreadResponse: Codable {
    var messages: [ThreadMessage]
}

/// Fields for POST /tasks.
struct NewTask: Encodable {
    var title: String
    var type: String
    var date: String?
    var start: String?
    var durationMin: Int?
    var priority: String
    var notes: String
}

extension JSONDecoder {
    static let planly: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

extension JSONEncoder {
    static let planly: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}

/// Server timestamps ("2026-10-30T10:05:00.123456+00:00") → Date.
enum ServerTime {
    static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        // Python can emit 6 fractional digits; drop the fraction and try again
        if let dot = text.firstIndex(of: "."), let zone = text[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            return plain.date(from: String(text[..<dot]) + String(text[zone...]))
        }
        return nil
    }
}
