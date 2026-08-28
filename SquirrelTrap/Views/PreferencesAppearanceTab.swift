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
                    // A filled dot in the tag's own colour, matching how the
                    // per-row colour control is drawn in IntentRowView. The
                    // control's job is to show which colour is assigned, and a
                    // swatch shows that where a tinted palette glyph does not.
                    Circle()
                        .fill(preferences.defaultColorTag?.color ?? Color.clear)
                        .overlay(
                            Circle().strokeBorder(
                                preferences.defaultColorTag == nil ? Color.panelCheckboxRim : Color.clear,
                                lineWidth: 1.5
                            )
                        )
                        .frame(width: 14, height: 14)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
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
        .font(Theme.secondary)
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

    /// A row of small tappable swatches, one per PanelTheme.
    ///
    /// Each swatch shows the theme's ACCENT, not its base. Upstream showed the
    /// base fill because the base was the card's own colour, but this fork
    /// deliberately does not adopt it: the card is the system window background
    /// so the panel reads correctly in both appearances, and the theme drives
    /// only the accent. Showing a base colour here would advertise something
    /// that changes nothing on screen, which is worse than showing no swatch at
    /// all: the user picks a theme, nothing they can see changes, and the
    /// feature looks broken.
    ///
    /// Selection is a ring around the swatch rather than a fill change, so the
    /// colour being chosen is never distorted by the act of choosing it.
    private var themeSwatches: some View {
        HStack(spacing: 7) {
            ForEach(PanelTheme.allCases, id: \.self) { theme in
                let isSelected = preferences.panelTheme == theme
                Button {
                    preferences.panelTheme = theme
                } label: {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 16, height: 16)
                        .overlay(
                            // A hairline so a swatch close to the card's own
                            // colour still has an edge in both appearances.
                            Circle().strokeBorder(Color.panelSeparator, lineWidth: 0.5)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(theme.accent, lineWidth: isSelected ? 1.5 : 0)
                                .padding(-3)
                        )
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(theme.displayName)
                .accessibilityLabel(theme.displayName)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
