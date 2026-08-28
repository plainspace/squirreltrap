import SwiftUI

/// A small "?" icon that reveals its explanation in a popover on click --
/// shared across the Preferences tabs so a setting's explanation is visibly
/// discoverable next to its label, not just something you stumble into by
/// hovering the control itself. Deliberately NOT the native .help() tooltip:
/// that's hover-only with no click behavior, and unreliable in a menu-bar-only
/// (LSUIElement) app like this one, where AppKit's tooltip windows don't
/// always participate normally in an accessory app's window activation.
/// A tap-to-show popover sidesteps that entirely, and matches the same
/// mechanism already proven reliable everywhere else in this app (coach
/// tips, color/reminder pickers).
struct HelpTip: View {
    let text: String

    @State private var isShowingPopover = false

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        // Upstream's click-to-show popover, on this fork's tokens: tertiary at
        // rest rather than secondary-at-60%, and the shared type scale.
        Button {
            isShowingPopover = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(Theme.secondary)
                .foregroundStyle(Color.panelTertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPopover) {
            Text(text)
                .font(Theme.body)
                .foregroundStyle(Color.panelTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 220, alignment: .leading)
                .padding(12)
        }
    }
}
