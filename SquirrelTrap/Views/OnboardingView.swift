import SwiftUI

/// Shown once, automatically, the first time Squirrel Trap is set up --
/// walks through the actual Preferences tabs (reused as-is, not
/// reimplemented) so features like Snooze, Default Alarm/Color, and sync
/// aren't left undiscovered behind a gear icon nobody's clicked yet.
/// Activity is skipped -- there's no setup value in an empty chart for a
/// brand-new user with no completed to-dos yet. Finishing sets
/// AppPreferences.hasCompletedOnboarding, which PanelController checks
/// before every normal entry point (Cmd+Tab, menu bar click, Cmd+,) --
/// dismissing this without finishing just postpones it, since any of those
/// triggers lands right back here until it's actually completed.
struct OnboardingView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var cloudSyncEngine: CloudSyncEngine
    let intentStore: IntentStore
    let reminderScheduler: ReminderScheduler
    var onOpenReminderSync: () -> Void
    var onFinished: () -> Void

    private enum Step: Int, CaseIterable {
        case general, appearance, sync

        var title: String {
            switch self {
            case .general: return "General"
            case .appearance: return "Appearance"
            case .sync: return "Sync"
            }
        }
    }

    // Persists across content swaps (e.g. stepping into Reminders Sync setup
    // and back) since this view's identity lives in a cached
    // NSHostingController -- see PanelController.showOnboardingPanel.
    @State private var step: Step = .general
    @State private var launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
    @State private var permissionGranted = PermissionManager.status() == .granted

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            stepTabs

            Group {
                switch step {
                case .general:
                    PreferencesGeneralTab(
                        preferences: preferences,
                        intentStore: intentStore,
                        reminderScheduler: reminderScheduler,
                        launchAtLoginEnabled: $launchAtLoginEnabled,
                        onConfirmationActiveChanged: { _ in },
                        onQuit: {},
                        isOnboarding: true
                    )
                case .appearance:
                    PreferencesAppearanceTab(preferences: preferences, permissionGranted: $permissionGranted, isOnboarding: true)
                case .sync:
                    PreferencesSyncTab(
                        preferences: preferences,
                        cloudSyncEngine: cloudSyncEngine,
                        intentStore: intentStore,
                        onOpenReminderSync: onOpenReminderSync,
                        isOnboarding: true
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
        .padding(.top, 12)
        .frame(width: PromptPanelView.cardSize.width, height: PromptPanelView.cardSize.height, alignment: .top)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("Welcome to Squirrel Trap")
                .font(Theme.title)
                .foregroundStyle(Color.panelTextPrimary)
            Text("A few quick preferences before you get started")
                .font(Theme.secondary)
                .foregroundStyle(Color.panelTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// One continuous segmented bar (a single capsule track, not 3 separate
    /// buttons with gaps/borders of their own) -- each segment names the
    /// step and, since jumping between already-visible steps doesn't bypass
    /// onFinished() (only reachable from .sync's "Get Started"), there's no
    /// reason not to make them clickable too.
    private var stepTabs: some View {
        HStack(spacing: 0) {
            ForEach(Step.allCases, id: \.self) { candidate in
                Button {
                    step = candidate
                } label: {
                    Text(candidate.title)
                        .font(.system(size: 12, weight: candidate == step ? .semibold : .regular))
                        .foregroundStyle(candidate == step ? Color.white : Color.panelTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(candidate == step ? preferences.panelTheme.accent : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Otherwise the first tab (whichever one AppKit happens to
                // pick as initial first responder in this new panel) draws
                // the system keyboard-focus ring around itself, which reads
                // as a stray border on an otherwise borderless segment.
                .focusable(false)

                if candidate != Step.allCases.last {
                    Rectangle()
                        .fill(Color.panelTextSecondary.opacity(0.3))
                        .frame(width: 1, height: 16)
                }
            }
        }
        .background(Color.panelTextSecondary.opacity(0.08))
        .clipShape(Capsule())
        .overlay {
            Capsule().strokeBorder(Color.panelTextSecondary.opacity(0.35), lineWidth: 1)
        }
        .frame(width: 320)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .general {
                Button("Back") {
                    step = Step(rawValue: step.rawValue - 1) ?? .general
                }
                .buttonStyle(.plain)
                // Accent is reserved for the primary action (Next/Get
                // Started); Back stays secondary so there's only one accent
                // pull in the footer, matching this fork's accent-sparingly
                // design language.
                .foregroundStyle(Color.panelTextSecondary)
                .font(.system(size: 13, weight: .medium))
            }

            Spacer()

            Button(step == .sync ? "Get Started" : "Next") {
                if let next = Step(rawValue: step.rawValue + 1) {
                    step = next
                } else {
                    onFinished()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(preferences.panelTheme.accent)
            .font(.system(size: 13, weight: .semibold))
            .keyboardShortcut(.defaultAction)
        }
    }
}
