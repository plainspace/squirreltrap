import SwiftUI

/// Popover content for a single CoachTip -- a message, a per-tip "Don't show
/// this tip again" checkbox (checking it drops just this tip out of the
/// rotation for good; leaving it unchecked means this same tip can come
/// back around once the cycle reaches it again), and a dismiss button.
struct CoachTipBubble: View {
    let message: String
    var onDismiss: () -> Void
    var onDismissThisTipPermanently: () -> Void

    @State private var doNotShowAgain = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color.panelTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 220, alignment: .leading)

            Toggle("Don't show this tip again", isOn: $doNotShowAgain)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(Color.panelTextSecondary)

            Button("Got it") {
                if doNotShowAgain {
                    onDismissThisTipPermanently()
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
