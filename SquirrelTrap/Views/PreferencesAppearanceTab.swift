import SwiftUI

struct PreferencesAppearanceTab: View {
    @ObservedObject var preferences: AppPreferences
    @Binding var permissionGranted: Bool
    var isOnboarding: Bool = false

    @State private var isShowingDefaultColorPicker = false

    var body: some View {
        SettingsForm {
            // The panel's own look, grouped apart from the two toggles that
            // change what it does rather than how it looks.
            Section("Panel") {
                LabeledContent {
                    PanelPositionPicker(
                        selection: $preferences.panelPosition,
                        accent: preferences.panelTheme.accent
                    )
                } label: {
                    SettingLabel("Position", "Where the panel opens. Takes effect the next time it opens, so changing it doesn't yank the panel you're looking at across the screen.")
                }

                LabeledContent {
                    themeSwatches
                } label: {
                    SettingLabel("Theme", "Changes the panel's overall color, including the desktop widget.")
                }

                LabeledContent {
                    Toggle("", isOn: $preferences.translucencyEnabled)
                        .labelsHidden()
                } label: {
                    SettingLabel("Translucency", "Turns off the frosted-glass blur for a solid card, independent of the system-wide Reduce Transparency setting.")
                }

                LabeledContent {
                    Toggle("", isOn: $preferences.showMenuBarIcon)
                        .labelsHidden()
                } label: {
                    SettingLabel("Menu bar icon", "Shows a Squirrel Trap icon in the menu bar for quick access. Cmd+, always reopens Preferences, even with the icon hidden.")
                }
            }

            Section("Completing a To-Do") {
                LabeledContent {
                    Toggle("", isOn: $preferences.celebrationEnabled)
                        .labelsHidden()
                } label: {
                    SettingLabel("Celebration", "Plays a brief animation on the main panel whenever you complete a to-do.")
                }

                LabeledContent {
                    Toggle("", isOn: $preferences.showStreak)
                        .labelsHidden()
                } label: {
                    SettingLabel("Streak counter", "Shows the 🔥 day-streak counter on the main panel. Today's completed count stays visible either way.")
                }

                LabeledContent {
                    defaultColorControl
                } label: {
                    SettingLabel("Default color", "Automatically tags every new to-do with this color -- tap the selected swatch again to turn it off.")
                }
            }

            Section("Privacy") {
                LabeledContent {
                    Toggle("", isOn: $preferences.analyticsEnabled)
                        .labelsHidden()
                        // Deciding here (e.g. during onboarding) counts as
                        // having answered -- otherwise AnalyticsConsentPrompt
                        // would still ask again right after, even though this
                        // already set it.
                        .onChange(of: preferences.analyticsEnabled) { _, _ in
                            preferences.hasAskedAnalyticsConsent = true
                        }
                } label: {
                    SettingLabel("Share usage data", "Shares anonymous usage data -- which features get used, not your to-do text -- to help guide future updates. Off by default.")
                }

                LabeledContent {
                    permissionStatus
                } label: {
                    SettingLabel("Input Monitoring", "Squirrel Trap needs this to notice Cmd+Tab. It only ever watches for that one shortcut and never records what you type.")
                }
            }
        }
        .onAppear { permissionGranted = PermissionManager.status() == .granted }
    }

    private var defaultColorControl: some View {
        Button {
            isShowingDefaultColorPicker = true
        } label: {
            // A filled dot in the tag's own colour, matching how the per-row
            // colour control is drawn in IntentRowView. The control's job is to
            // show which colour is assigned, and a swatch shows that where a
            // tinted palette glyph does not.
            Circle()
                .fill(preferences.defaultColorTag?.color ?? Color.clear)
                .overlay(
                    Circle().strokeBorder(
                        preferences.defaultColorTag == nil ? Color.panelCheckboxRim : Color.clear,
                        lineWidth: 1.5
                    )
                )
                .frame(width: 14, height: 14)
                // Trailing, not centred. LabeledContent right-aligns its
                // control, so a centred dot inside a 24pt hit target sits ~5pt
                // left of where every Toggle's edge lands, and the column reads
                // as if this one row were nudged over. The box still exists --
                // a 14pt circle is too small a target on its own.
                .frame(width: 24, height: 24, alignment: .trailing)
                .contentShape(Rectangle())
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

/// A miniature screen you click a region of, rather than a menu of five
/// direction words.
///
/// "Bottom Left" in a dropdown asks you to read a label, picture the result,
/// and then open the panel to find out whether you were right. The thing being
/// chosen is a *place*, and a place is better shown than named: the control is
/// a small screen with the panel drawn on it, so the answer is already on
/// screen before you commit to it. Hovering a region previews the panel there
/// in outline, so you can compare positions without changing the setting.
///
/// Every position is drawn at once, faint, with the chosen one filled in. The
/// alternative -- drawing only the current choice -- makes the control a
/// picture of the answer but not of the question: nothing on screen says the
/// other four slots exist, so it reads as a static illustration rather than
/// something to click. Showing all five outlines makes the options visible and
/// the click target obvious, and turns choosing into recognition rather than
/// exploration.
///
private struct PanelPositionPicker: View {
    @Binding var selection: PanelPosition
    let accent: Color

    @State private var hovered: PanelPosition?

    private let screenSize = CGSize(width: 88, height: 56)
    private let cornerInset: CGFloat = 4

    /// Keeps the panel's own near-square 440x420 proportion, but not its true
    /// scale. Drawn to scale against a 14" display's usable area, an indicator
    /// is a third of this control's width and nearly half its height -- five of
    /// those crowd each other and the corners stop reading as corners. The
    /// control's job is to say *where*, and it says that better when the marks
    /// are small enough for the empty space around them to be legible.
    private let indicatorSize = CGSize(width: 18, height: 17)

    var body: some View {
        ZStack {
            screen
            ForEach(PanelPosition.allCases) { position in
                indicator(for: position)
            }
            regions
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panel position")
    }

    private var screen: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.panelSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.panelCheckboxRim, lineWidth: 1)
            )
    }

    /// Three states, one shape. Selected is a solid accent fill; hovered is the
    /// accent again but only as an outline, so a hover previews the position
    /// without ever looking like it has already been applied; everything else
    /// is a hairline in the same rim colour as the screen's own border, present
    /// enough to be seen as a slot and quiet enough not to compete with the
    /// choice.
    private func indicator(for position: PanelPosition) -> some View {
        let isSelected = selection == position
        let isHovered = hovered == position && !isSelected
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(isSelected ? accent : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear : (isHovered ? accent : Color.panelCheckboxRim),
                        lineWidth: 1
                    )
            )
            .frame(width: indicatorSize.width, height: indicatorSize.height)
            .padding(cornerInset)
            // Centre is lifted the same 5% the real placement is, so the
            // preview matches where the panel actually lands.
            .offset(y: position == .center ? -screenSize.height * 0.05 : 0)
            .frame(width: screenSize.width, height: screenSize.height, alignment: alignment(for: position))
            .animation(.easeOut(duration: 0.12), value: selection)
    }

    private func alignment(for position: PanelPosition) -> Alignment {
        switch position {
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .center: return .center
        }
    }

    /// A 3x3 grid of hit targets: the four corner cells pick their corner, and
    /// every other cell picks centre. Splitting it this way means there is no
    /// dead space and no cell smaller than roughly a third of the control --
    /// five separately-positioned targets on a 104pt-wide surface would each be
    /// too small to hit confidently.
    private var regions: some View {
        VStack(spacing: 0) {
            regionRow(leading: .topLeft, trailing: .topRight)
            regionRow(leading: .center, trailing: .center)
            regionRow(leading: .bottomLeft, trailing: .bottomRight)
        }
    }

    private func regionRow(leading: PanelPosition, trailing: PanelPosition) -> some View {
        HStack(spacing: 0) {
            region(leading)
            region(.center)
            region(trailing)
        }
    }

    private func region(_ position: PanelPosition) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { selection = position }
            .onHover { hovered = $0 ? position : (hovered == position ? nil : hovered) }
            .accessibilityAddTraits(selection == position ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(position.label)
            .accessibilityAction { selection = position }
    }
}
