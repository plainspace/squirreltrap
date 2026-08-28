import SwiftUI

/// Ghost, matching KofiButton: no fill, no outline, secondary text that
/// brightens on hover. It used to be a solid green pill sitting next to a solid
/// blue one, which gave the footer two of the three loudest elements on the
/// surface for two things nobody opens the panel to do.
struct SnoozeButton: View {
    var minutes: Double
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "moon.zzz")
                Text("\(Int(minutes))m")
                    .lineLimit(1)
            }
            .fixedSize()
            .font(Theme.secondary)
            // Tertiary at rest, matching the icon buttons either side of it.
            // At secondary it was the brightest thing in the footer, which is
            // the wrong billing for a mute button.
            .foregroundStyle(isHovering ? Color.panelTextPrimary : Color.panelTertiary)
            .padding(.horizontal, 4)
            .frame(height: Theme.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .accessibilityLabel("Snooze Cmd+Tab for \(Int(minutes)) minutes")
    }
}
