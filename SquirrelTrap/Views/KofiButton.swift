import AppKit
import SwiftUI

/// Opens the Ko-fi page directly, rather than embedding Ko-fi's own widget
/// (which is browser JS).
///
/// Ghost: no fill, no outline, secondary text colour, brightening only on
/// hover. It used to be a solid Ko-fi-blue pill, which made asking for money
/// the highest-contrast element in a panel whose entire job is a text field and
/// a list. A donation link should be findable by someone looking for it and
/// invisible to everyone else.
struct KofiButton: View {
    var onOpened: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button {
            if let url = URL(string: "https://ko-fi.com/B0B31XCPZQ") {
                NSWorkspace.shared.open(url)
            }
            onOpened()
        } label: {
            // Word only. `cup.and.saucer` at this size rendered as an
            // indistinct stack of ellipses rather than a cup, and a glyph
            // nobody can identify is worse than no glyph.
            Text("Ko-fi")
                .font(Theme.secondary)
                .foregroundStyle(isHovering ? Color.panelTextPrimary : Color.panelTertiary)
                .padding(.horizontal, 4)
                .frame(height: Theme.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .help("Support Squirrel Trap on Ko-fi")
        .accessibilityLabel("Support Squirrel Trap on Ko-fi")
    }
}
