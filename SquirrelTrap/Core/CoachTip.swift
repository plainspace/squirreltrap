import Foundation

/// A one-shot contextual tip surfaced near a specific control the first time
/// AppPreferences.totalPanelShows reaches its triggerCount. Each tip fires
/// exactly once by construction -- totalPanelShows only ever equals any
/// given number a single time -- so there's no separate per-tip dismissal
/// state, only the global AppPreferences.coachTipsEnabled opt-out.
enum CoachTip: CaseIterable {
    case preferences
    case snooze

    var triggerCount: Int {
        switch self {
        case .preferences: return 2
        case .snooze: return 5
        }
    }

    var message: String {
        switch self {
        case .preferences:
            return "Lots of ways to customize your Squirrel Trap experience, right here."
        case .snooze:
            return "Squirrel Trap popping up when you're already on track? Just Snooze it for now!"
        }
    }

    static func tip(forPanelShowCount count: Int) -> CoachTip? {
        allCases.first { $0.triggerCount == count }
    }
}
