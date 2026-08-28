import SwiftUI

/// Shown once, ever, regardless of answer -- see
/// AppPreferences.hasAskedAnalyticsConsent. Unlike CoachTipBubble
/// (informational, dismiss-only, can recur through the rotation), this is a
/// real yes/no decision: both buttons permanently mark the ask as answered,
/// and only "Enable" also turns tracking on.
struct AnalyticsConsentPrompt: View {
    let themeAccent: Color
    var onDecide: (_ enabled: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Help improve Squirrel Trap?")
                .font(Theme.title)
                .foregroundStyle(Color.panelTextPrimary)
            Text("Sharing anonymous usage data -- which features get used, not your to-do text -- helps future updates focus on what actually helps. Change this anytime in Preferences → Appearance.")
                .font(Theme.body)
                .foregroundStyle(Color.panelTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading)

            HStack {
                Button("Not Now") { onDecide(false) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.panelTextSecondary)
                    .font(Theme.body)

                Spacer()

                // The accent lands on the affirmative, and only there: this is
                // the one place in the app asking the user to opt in to
                // something, so declining must not be the visually louder half.
                Button("Enable") { onDecide(true) }
                    .buttonStyle(.plain)
                    .foregroundStyle(themeAccent)
                    .font(Theme.bodyMedium)
            }
        }
        .padding(14)
    }
}
