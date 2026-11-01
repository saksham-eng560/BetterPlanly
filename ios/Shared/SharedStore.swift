import Foundation

/// Settings and a small cache shared by the app and the widget.
/// Uses the App Group when signing allows one (Config/Signing.xcconfig: APP_GROUP = YES);
/// otherwise each process keeps its own copy and the widget uses the address set in Edit Widget.
enum SharedStore {
    static let appGroup: String? = {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "PlanlyAppGroup") as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }()

    static let defaults: UserDefaults = {
        if let appGroup, let shared = UserDefaults(suiteName: appGroup) { return shared }
        return .standard
    }()

    private enum Key {
        static let server = "serverURL"
        static let remindersOn = "remindersOn"
        static let reminderLead = "reminderLeadMinutes"
        static let badgeOn = "badgeOn"
        static let snapshot = "todaySnapshot"
        static let reactToChanges = "reactToChanges"
        static let lastDayReview = "lastDayReview"
    }

    /// e.g. http://MacBook-Pro.local:8000 (no trailing slash, no /api).
    static var serverURL: String {
        get { defaults.string(forKey: Key.server) ?? "" }
        set { defaults.set(normalize(newValue), forKey: Key.server) }
    }

    static var isConfigured: Bool { URL(string: serverURL)?.host != nil }

    static var remindersOn: Bool {
        get { defaults.object(forKey: Key.remindersOn) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.remindersOn) }
    }

    /// Minutes before a task starts.
    static var reminderLead: Int {
        get { defaults.object(forKey: Key.reminderLead) as? Int ?? 5 }
        set { defaults.set(newValue, forKey: Key.reminderLead) }
    }

    static var badgeOn: Bool {
        get { defaults.object(forKey: Key.badgeOn) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.badgeOn) }
    }

    /// Let the agent react to ticks and moves (the web's "React to changes" switch).
    static var reactToChanges: Bool {
        get { defaults.object(forKey: Key.reactToChanges) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.reactToChanges) }
    }

    static var lastDayReview: String? {
        get { defaults.string(forKey: Key.lastDayReview) }
        set { defaults.set(newValue, forKey: Key.lastDayReview) }
    }

    /// Accepts "192.168.1.20", "mac.local:8000", "http://mac.local:8080/", "…/api".
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix("/api") { text.removeLast(4) }
        if var parts = URLComponents(string: text), parts.port == nil, parts.path.isEmpty {
            parts.port = 8000 // the API's port when started with `make phone`
            text = parts.string ?? text
        }
        return text
    }

    // MARK: today's tasks, cached for the widget and for when the Mac is out of reach

    struct Snapshot: Codable {
        var date: String
        var tasks: [PlanTask]
        var fetchedAt: Date
    }

    static var snapshot: Snapshot? {
        get {
            guard let data = defaults.data(forKey: Key.snapshot) else { return nil }
            return try? JSONDecoder().decode(Snapshot.self, from: data)
        }
        set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.snapshot)
        }
    }
}
