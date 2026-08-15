import SwiftUI

struct PreferencesAppearanceTab: View {
    @ObservedObject var preferences: AppPreferences
    @Binding var permissionGranted: Bool
    var isOnboarding: Bool = false

    @State private var isShowingDefaultColorPicker = false

    /// Hairline row separators, only between rows shown during onboarding --
    /// normal Preferences stays as a denser Grid with no dividers.
    @ViewBuilder
    private var onboardingDivider: some View {
        if isOnboarding {
            GridRow {
                Divider().gridCellColumns(2)
            }
        }
    }

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                HStack(spacing: 4) {
                    Text("Show menu bar icon")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                    HelpTip("Shows a Squirrel Trap icon in the menu bar for quick access. Cmd+, always reopens Preferences, even with the icon hidden.")
                }
                Toggle("", isOn: $preferences.showMenuBarIcon)
                    .labelsHidden()
            }

            onboardingDivider

            GridRow {
                HStack(spacing: 4) {
                    Text("Enable translucency")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                    HelpTip("Turns off the frosted-glass blur for a solid card, independent of the system-wide Reduce Transparency setting.")
                }
                Toggle("", isOn: $preferences.translucencyEnabled)
                    .labelsHidden()
            }

            onboardingDivider

            GridRow {
                HStack(spacing: 4) {
                    Text("Show Celebration")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                    HelpTip("Plays a brief animation on the main panel whenever you complete a to-do.")
                }
                Toggle("", isOn: $preferences.celebrationEnabled)
                    .labelsHidden()
            }

            onboardingDivider

            GridRow {
                HStack(spacing: 4) {
                    Text("Default Color")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                    HelpTip("Automatically tags every new to-do with this color -- tap the selected swatch again to turn it off.")
                }
                Button {
                    isShowingDefaultColorPicker = true
                } label: {
                    Image(systemName: preferences.defaultColorTag != nil ? "paintpalette.fill" : "paintpalette")
                        .font(.system(size: 13))
                        .foregroundStyle(preferences.defaultColorTag?.color ?? Color.accentColor.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preferences.defaultColorTag != nil ? "Change or remove default color" : "Set a default color")
                .popover(isPresented: $isShowingDefaultColorPicker) {
                    ColorTagGridPicker(selected: preferences.defaultColorTag) { newTag in
                        preferences.defaultColorTag = newTag
                        isShowingDefaultColorPicker = false
                    }
                }
            }

            onboardingDivider

            GridRow {
                Text("")
                permissionStatus
            }
        }
        .font(.system(size: 12))
        .onAppear { permissionGranted = PermissionManager.status() == .granted }
    }

    @ViewBuilder
    private var permissionStatus: some View {
        if permissionGranted {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Color.accentColor)
                Text("Watching for Cmd+Tab")
                    .foregroundStyle(Color.panelTextSecondary)
            }
            .font(.system(size: 11))
        } else {
            Button("Grant Input Monitoring Access…") {
                PermissionManager.requestAccessOrOpenSettings()
            }
            .controlSize(.small)
        }
    }
}
