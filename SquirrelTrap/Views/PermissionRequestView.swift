import SwiftUI

struct PermissionRequestView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Input Monitoring Needed")
                .font(Theme.title)
                .foregroundStyle(Color.panelTextPrimary)

            Text("Squirrel Trap watches for the Cmd+Tab key combination to show a quick prompt when you switch apps. It does not record any other keystrokes.")
                .font(Theme.body)
                .foregroundStyle(Color.panelTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Says the quiet part out loud. Without this the screen reads as a
            // hard requirement, and a user who cannot grant it (a locally
            // signed build cannot be, see DEVELOPMENT.md) has no way to know
            // the app is still perfectly usable.
            Text("Without it, everything still works except the Cmd+Tab trigger. Open the panel any time from the menu bar icon.")
                .font(Theme.secondary)
                .foregroundStyle(Color.panelTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Button("Continue Without It", action: onDismiss)
                Spacer()
                Button("Grant Access") {
                    PermissionManager.requestAccessOrOpenSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.gutter)
        .frame(width: PromptPanelView.cardSize.width, height: PromptPanelView.cardSize.height, alignment: .top)
        .onExitCommand(perform: onDismiss)
    }
}
