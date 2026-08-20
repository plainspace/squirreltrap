import SwiftUI

/// Popover content for a single CoachTip -- a message and a dismiss button.
/// Dismissing it, by any means (this button, clicking outside the popover,
/// Escape), permanently drops that tip out of the rotation -- there's no
/// "show this again" opt-in anymore; every tip is one-and-done unless the
/// user resets the whole set from Preferences -> Activity -> Reset All Tips.
struct CoachTipBubble: View {
    let message: String
    let themeAccent: Color
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color.panelTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 220, alignment: .leading)

            Button("Got it") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(themeAccent)
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
    }
}
