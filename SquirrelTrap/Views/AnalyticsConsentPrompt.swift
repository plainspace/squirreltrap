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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelTextPrimary)
            Text("Sharing anonymous usage data -- which features get used, not your to-do text -- helps future updates focus on what actually helps. Change this anytime in Preferences → Appearance.")
                .font(.system(size: 12))
                .foregroundStyle(Color.panelTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading)

            HStack {
                Button("Not Now") { onDecide(false) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.panelTextSecondary)
                    .font(.system(size: 12))

                Spacer()

                Button("Enable") { onDecide(true) }
                    .buttonStyle(.plain)
                    .foregroundStyle(themeAccent)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(14)
    }
}
