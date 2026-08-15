import SwiftUI

/// A small "?" icon carrying a native hover tooltip -- shared across the
/// Preferences tabs so a setting's explanation is visibly discoverable next
/// to its label, not just something you stumble into by hovering the
/// control itself.
struct HelpTip: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.system(size: 11))
            .foregroundStyle(Color.panelTextSecondary.opacity(0.6))
            .help(text)
    }
}
