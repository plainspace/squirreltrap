import AppKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var cloudSyncEngine: CloudSyncEngine
    @ObservedObject var updateChecker: UpdateChecker
    let intentStore: IntentStore
    let reminderScheduler: ReminderScheduler
    @State private var launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
    @State private var permissionGranted = PermissionManager.status() == .granted
    @State private var selectedTab: PreferencesTab = .general
    // Local mirror of the General tab's confirmation-dialog state (owned there,
    // reported up here via onConfirmationActiveChanged) so onExitCommand below
    // can still avoid dismissing the whole panel while "Clear Finished/All
    // Items" is up — see the matching guard on PanelController's
    // suppressEscapeDismiss, which relies on the same callback.
    @State private var hasActiveConfirmation = false
    var onBack: () -> Void
    var onDismiss: () -> Void
    var onQuit: () -> Void
    var onConfirmationActiveChanged: (Bool) -> Void = { _ in }
    var onOpenReminderSync: () -> Void = {}
    var onSnooze: () -> Void = {}

    private var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private func handleConfirmationActiveChanged(_ active: Bool) {
        hasActiveConfirmation = active
        onConfirmationActiveChanged(active)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabBar
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Group {
                switch selectedTab {
                case .general:
                    PreferencesGeneralTab(
                        preferences: preferences,
                        intentStore: intentStore,
                        reminderScheduler: reminderScheduler,
                        launchAtLoginEnabled: $launchAtLoginEnabled,
                        onConfirmationActiveChanged: handleConfirmationActiveChanged,
                        onQuit: onQuit,
                        updateChecker: updateChecker
                    )
                case .appearance:
                    PreferencesAppearanceTab(preferences: preferences, permissionGranted: $permissionGranted)
                case .sync:
                    PreferencesSyncTab(
                        preferences: preferences,
                        cloudSyncEngine: cloudSyncEngine,
                        intentStore: intentStore,
                        onOpenReminderSync: onOpenReminderSync
                    )
                case .activity:
                    PreferencesActivityTab(intentStore: intentStore, preferences: preferences)
                }
            }
            // No horizontal gutter here: a grouped Form insets its own groups,
            // and adding the panel's gutter on top of that would indent them
            // twice and squeeze the label and control columns together.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .frame(width: PromptPanelView.cardSize.width, height: PromptPanelView.cardSize.height, alignment: .top)
        .onExitCommand { if !hasActiveConfirmation { onDismiss() } }
    }

    /// Tabs across the top, not down the left.
    ///
    /// The sidebar this replaced was 132pt of a 440pt panel -- roughly a third
    /// of the width -- and most of it was an app icon and a version string,
    /// neither of which is a setting. What it cost was the content column:
    /// every tab had well under 250pt to place a label and a control, which is
    /// why they were built as hand-rolled two-column Grids in the first place.
    /// Moving the tabs to a single row gives the settings the full width and
    /// lets them be native grouped Forms; the version and update check moved
    /// into General, where Mac apps put them anyway.
    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(PreferencesTab.allCases) { tab in
                tabButton(tab)
            }
        }
    }

    /// Custom-styled rather than .pickerStyle(.segmented) -- that would pull in
    /// chrome that clashes with the flat, hairline-separated look everywhere
    /// else in this app. Selection is a solid accent fill with white text -- a
    /// translucent tint reads fine in dark but loses contrast in light mode.
    private func tabButton(_ tab: PreferencesTab) -> some View {
        Button {
            selectedTab = tab
            AnalyticsService.shared.track(.preferencesTabOpened, properties: ["tab": tab.rawValue])
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                Text(tab.label)
                    .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
            }
            .foregroundStyle(selectedTab == tab ? .white : Color.panelTextSecondary)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                if selectedTab == tab {
                    // Solid fill, not upstream's 0.35 opacity: a translucent
                    // tint loses contrast in light mode. The color itself is
                    // upstream's selectable panelTheme.accent rather than the
                    // fixed system accent.
                    RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                        .fill(preferences.panelTheme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : .isButton)
    }

    /// Mirrors the main panel's footer exactly: a utility icon at the bottom-left
    /// (gear there, back-chevron here), the Snooze button pinned at the same
    /// on-screen spot it occupies there too -- rather than living inside
    /// General's Grid where its position shifted with the row's own content --
    /// and the Ko-fi button at the bottom-right.
    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13))
                    // Matches the footer's gear icon (PromptPanelView): a
                    // utility/nav control stays secondary, not accent, so
                    // accent is reserved for genuinely primary actions.
                    .foregroundStyle(Color.panelTextSecondary)
            }
            .buttonStyle(.plain)
            .help("Back to Squirrel Trap")
            .accessibilityLabel("Back to Squirrel Trap")

            SnoozeButton(minutes: preferences.snoozeDurationMinutes, action: onSnooze)
                .help("Snooze Cmd+Tab for a while")

            Spacer()

            KofiButton(onOpened: onDismiss)
        }
    }
}
