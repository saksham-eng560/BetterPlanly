//
//  SharedStore.swift
//  Planly (shared)
//
//  Settings and the last "today" snapshot. Stored in the App Group when the build has one, so the
//  widget can read them; otherwise in each target's own defaults. A free Personal Team may not be
//  able to sign App Groups, which is why the widget also has its own "Mac address" setting.
//

import Foundation

nonisolated enum SharedStore {
    static let appGroup = "group.com.saksham.Planly"

    /// True when the App Group entitlement is present and its container exists.
    static var hasAppGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
    }

    static var defaults: UserDefaults {
        if hasAppGroup, let shared = UserDefaults(suiteName: appGroup) { return shared }
        return .standard
    }

    private enum Key {
        static let server = "serverAddress"
        static let onboarded = "onboarded"
        static let reminders = "remindersEnabled"
        static let lead = "reminderLeadMinutes"
        static let badge = "badgeEnabled"
        static let react = "reactToChanges"
        static let dayReview = "lastDayReview"
        static let snapshot = "todaySnapshot"
    }

    static var serverAddress: String {
        get { defaults.string(forKey: Key.server) ?? "" }
        set { defaults.set(newValue, forKey: Key.server) }
    }

    static var client: APIClient? { APIClient(address: serverAddress) }

    static var onboarded: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }

    static var remindersEnabled: Bool {
        get { defaults.object(forKey: Key.reminders) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.reminders) }
    }

    /// Minutes before a task's start to remind: 0, 5, 10 or 15.
    static var reminderLeadMinutes: Int {
        get { defaults.object(forKey: Key.lead) as? Int ?? 5 }
        set { defaults.set(newValue, forKey: Key.lead) }
    }

    static var badgeEnabled: Bool {
        get { defaults.object(forKey: Key.badge) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.badge) }
    }

    /// "Let the agent react to my changes" (on by default, like the website).
    static var reactToChanges: Bool {
        get { defaults.object(forKey: Key.react) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.react) }
    }

    /// The last calendar day a `day_review` run was sent.
    static var lastDayReview: String? {
        get { defaults.string(forKey: Key.dayReview) }
        set { defaults.set(newValue, forKey: Key.dayReview) }
    }

    // MARK: Snapshot

    struct Snapshot: Codable, Sendable {
        var date: String
        var tasks: [PlanTask]
        var savedAt: Date
    }

    static var snapshot: Snapshot? {
        guard let data = defaults.data(forKey: Key.snapshot) else { return nil }
        return try? PlanlyJSON.decoder().decode(Snapshot.self, from: data)
    }

    static func saveSnapshot(date: String, tasks: [PlanTask]) {
        let snapshot = Snapshot(date: date, tasks: tasks, savedAt: .now)
        if let data = try? PlanlyJSON.encoder().encode(snapshot) {
            defaults.set(data, forKey: Key.snapshot)
        }
    }
}
