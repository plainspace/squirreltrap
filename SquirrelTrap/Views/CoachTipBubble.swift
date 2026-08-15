import SwiftUI

/// Popover content for a single CoachTip -- a message, a "Don't show tips
/// like this again" checkbox (a global opt-out, not a per-tip one; see
/// CoachTip's doc comment for why), and a dismiss button.
struct CoachTipBubble: View {
    let message: String
    var onDismiss: () -> Void
    var onDisableAll: () -> Void

    @State private var doNotShowAgain = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color.panelTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 220, alignment: .leading)

            Toggle("Don't show tips like this again", isOn: $doNotShowAgain)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(Color.panelTextSecondary)

            Button("Got it") {
                if doNotShowAgain {
                    onDisableAll()
                }
                onDismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
    }
}
