import Foundation

/// A contextual tip surfaced near a specific control, cycling in
/// declaration order through whichever tips haven't been individually
/// dismissed -- see PromptPanelView.checkForCoachTip for the every-4th-show
/// rotation, and AppPreferences.dismissedCoachTips/coachTipRotationIndex for
/// the persisted state. A dismissed tip drops out of the rotation for good;
/// an undismissed one keeps recurring as the cycle comes back around, until
/// every tip has eventually been dismissed (Preferences → Activity has a
/// "Reset All Tips" button that clears all of this and starts over).
enum CoachTip: String, CaseIterable {
    case preferences
    case snooze
    case reminders
    case defaultAlarm
    case launchAtLogin

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
}
