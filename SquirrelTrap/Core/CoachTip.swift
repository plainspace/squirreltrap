import Foundation

/// A one-shot contextual tip surfaced near a specific control the first time
/// AppPreferences.totalPanelShows reaches its triggerCount. Each tip fires
/// exactly once by construction -- totalPanelShows only ever equals any
/// given number a single time -- so there's no separate per-tip dismissal
/// state, only the global AppPreferences.coachTipsEnabled opt-out.
enum CoachTip: CaseIterable {
    case preferences
    case snooze
    case reminders
    case defaultAlarm
    case launchAtLogin

    var triggerCount: Int {
        switch self {
        case .preferences: return 2
        case .snooze: return 5
        case .reminders: return 8
        case .defaultAlarm: return 12
        case .launchAtLogin: return 16
        }
    }

    /// A function of the live AppPreferences, not a static string -- several
    /// tips surface the actual current value of the setting they're
    /// describing (e.g. Snooze's own duration) rather than just naming it.
    @MainActor
    func message(preferences: AppPreferences) -> String {
        switch self {
        case .preferences:
            return "Lots of ways to customize your Squirrel Trap experience, right here."
        case .snooze:
            let minutes = Int(preferences.snoozeDurationMinutes)
            return "Squirrel Trap popping up when you're already on track? Just Snooze it for now! It's currently set to \(minutes) minute\(minutes == 1 ? "" : "s") -- adjust that in Preferences → General."
        case .reminders:
            return "See the small alarm icon on any to-do? Tap it to get reminded about that one item later."
        case .defaultAlarm:
            if preferences.defaultAlarmEnabled {
                let minutes = Int(preferences.defaultAlarmDurationSeconds / 60)
                return "Default Alarm is already on, so every new to-do gets a reminder in \(minutes) minute\(minutes == 1 ? "" : "s") automatically. Change the timing anytime in Preferences → General."
            } else {
                return "Want every new to-do to get a reminder automatically, with no extra tap? Turn on Default Alarm in Preferences → General -- it's currently off."
            }
        case .launchAtLogin:
            if LaunchAtLoginManager.isEnabled {
                return "Launch at Login is already on, so Squirrel Trap is ready the moment you start your Mac."
            } else {
                return "Want Squirrel Trap ready the moment you start your Mac? Turn on Launch at Login in Preferences → General -- it's currently off."
            }
        }
    }

    static func tip(forPanelShowCount count: Int) -> CoachTip? {
        allCases.first { $0.triggerCount == count }
    }
}
