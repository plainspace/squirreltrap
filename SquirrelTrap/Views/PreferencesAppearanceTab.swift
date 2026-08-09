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
                Text("Show menu bar icon")
                    .foregroundStyle(Color.panelTextSecondary)
                    .lineLimit(1)
                Toggle("", isOn: $preferences.showMenuBarIcon)
                    .labelsHidden()
                    .help("Cmd+, always reopens Preferences, even with the icon hidden")
            }

            onboardingDivider

            GridRow {
                Text("Enable translucency")
                    .foregroundStyle(Color.panelTextSecondary)
                    .lineLimit(1)
                Toggle("", isOn: $preferences.translucencyEnabled)
                    .labelsHidden()
                    .help("Turns off the frosted-glass blur for a solid card, independent of the system-wide Reduce Transparency setting")
            }

            onboardingDivider

            GridRow {
                Text("Show Celebration")
                    .foregroundStyle(Color.panelTextSecondary)
                    .lineLimit(1)
                Toggle("", isOn: $preferences.celebrationEnabled)
                    .labelsHidden()
                    .help("Briefly pulses the streak count when you log the first to-do of a new day")
            }

            onboardingDivider

            GridRow {
                Text("Default Color")
                    .foregroundStyle(Color.panelTextSecondary)
                    .lineLimit(1)
                Button {
                    isShowingDefaultColorPicker = true
                } label: {
                    Image(systemName: preferences.defaultColorTag != nil ? "paintpalette.fill" : "paintpalette")
                        .font(.system(size: 13))
                        .foregroundStyle(preferences.defaultColorTag?.color ?? Color.accentColor.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("New to-dos automatically get this color -- tap the selected swatch again to clear it")
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
