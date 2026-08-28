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
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
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
                    Text("Show Streak")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                    HelpTip("Shows the 🔥 day-streak counter on the main panel. Today's completed count stays visible either way.")
                }
                Toggle("", isOn: $preferences.showStreak)
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
                        // Tertiary at rest (no default color set yet), matching
                        // GhostIconButtonStyle's own resting/restingTint split
                        // rather than a dimmed accent.
                        .foregroundStyle(preferences.defaultColorTag?.color ?? Color.panelTertiary)
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
                HStack(spacing: 4) {
                    Text("Panel Theme")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                    HelpTip("Changes the panel's overall color, including the desktop widget.")
                }
                themeSwatches
            }

            onboardingDivider

            GridRow {
                HStack(spacing: 4) {
                    Text("Share Usage Data")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                    HelpTip("Shares anonymous usage data -- which features get used, not your to-do text -- to help guide future updates. Off by default.")
                }
                Toggle("", isOn: $preferences.analyticsEnabled)
                    .labelsHidden()
                    // Deciding here (e.g. during onboarding) counts as having
                    // answered -- otherwise AnalyticsConsentPrompt would still
                    // ask again right after, even though this already set it.
                    .onChange(of: preferences.analyticsEnabled) { _, _ in
                        preferences.hasAskedAnalyticsConsent = true
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
                    // Matches the "Up to date" checkmark in PreferencesView's
                    // updateStatus: a confirmation checkmark stays secondary,
                    // not accent.
                    .foregroundStyle(Color.panelTextSecondary)
                Text("Watching for Cmd+Tab")
                    .foregroundStyle(Color.panelTextSecondary)
            }
            .font(Theme.secondary)
        } else {
            Button("Grant Input Monitoring Access…") {
                PermissionManager.requestAccessOrOpenSettings()
            }
            .controlSize(.small)
        }
    }

    /// A row of small tappable swatches, one per PanelTheme -- each shows its
    /// base fill with an accent-colored ring only around the currently
    /// selected one, so picking a theme is a single click with no popover
    /// (unlike per-item Default Color above, which needs a popover since it
    /// includes 16 options plus "none").
    private var themeSwatches: some View {
        HStack(spacing: 6) {
            ForEach(PanelTheme.allCases, id: \.self) { theme in
                Button {
                    preferences.panelTheme = theme
                } label: {
                    Circle()
                        .fill(theme.base)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.panelTextPrimary.opacity(0.3), lineWidth: 0.5)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(theme.accent, lineWidth: preferences.panelTheme == theme ? 2 : 0)
                                .padding(-2)
                        )
                }
                .buttonStyle(.plain)
                .help(theme.displayName)
                .accessibilityLabel(theme.displayName)
            }
        }
    }
}
