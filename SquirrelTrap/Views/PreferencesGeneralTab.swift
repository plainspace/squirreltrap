import AppKit
import SwiftUI

struct PreferencesGeneralTab: View {
    @ObservedObject var preferences: AppPreferences
    let intentStore: IntentStore
    let reminderScheduler: ReminderScheduler
    @Binding var launchAtLoginEnabled: Bool
    var onConfirmationActiveChanged: (Bool) -> Void
    var onQuit: () -> Void
    /// True when shown as an onboarding step -- hides the destructive/
    /// irrelevant Clear Items and Quit rows, which make no sense for a
    /// brand-new user with no data yet.
    var isOnboarding: Bool = false

    @State private var showingClearCompletedConfirm = false
    @State private var showingClearAllConfirm = false

    private var hasActiveConfirmation: Bool {
        showingClearCompletedConfirm || showingClearAllConfirm
    }

    /// The excluded-apps control: the apps currently ignored, plus a picker to
    /// add one.
    ///
    /// Apps are chosen through the standard open panel rather than typed as
    /// bundle identifiers. Nobody knows their own apps by bundle ID, and a
    /// typo produces a rule that silently never matches, which is the worst
    /// possible failure for a setting whose entire job is to NOT do something.
    private var excludedApps: some View {
        VStack(alignment: .leading, spacing: 6) {
            if preferences.excludedBundleIDs.isEmpty {
                Text("None")
                    .foregroundStyle(Color.panelTertiary)
            } else {
                ForEach(preferences.excludedBundleIDs.sorted(), id: \.self) { bundleID in
                    HStack(spacing: 6) {
                        Text(Self.displayName(for: bundleID))
                            .foregroundStyle(Color.panelTextPrimary)
                            .lineLimit(1)
                            // The bundle ID stays reachable on hover, since two
                            // installed copies of an app share a display name.
                            .help(bundleID)
                        Button {
                            preferences.excludedBundleIDs.remove(bundleID)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.ghostIcon(size: 10, hoverTint: .panelDestructive))
                        .accessibilityLabel("Stop ignoring \(Self.displayName(for: bundleID))")
                    }
                }
            }

            Button("Add App…") { addExcludedApp() }
                .controlSize(.small)
        }
    }

    /// Resolves a bundle ID back to a readable name, falling back to the ID
    /// itself when the app is not installed any more. An exclusion for an app
    /// you have since deleted is harmless, so it is shown rather than dropped.
    private static func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Ignore"
        panel.message = "Squirrel Trap will not prompt when you switch away from these apps."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            preferences.excludedBundleIDs.insert(id)
        }
    }

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
                    Text("Launch at Login")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                    HelpTip("Automatically starts Squirrel Trap when you log in to your Mac.")
                }
                Toggle("", isOn: $launchAtLoginEnabled)
                    .labelsHidden()
                    .onChange(of: launchAtLoginEnabled) { _, newValue in
                        LaunchAtLoginManager.setEnabled(newValue)
                        AnalyticsService.shared.updateUserProperties(preferences: preferences)
                    }
            }

            onboardingDivider

            GridRow {
                HStack(spacing: 4) {
                    Text("Snooze for")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                    HelpTip("How long the Snooze button (bottom-left of this panel) suppresses Cmd+Tab for.")
                }
                HStack(spacing: 6) {
                    TimeoutComboBox(value: $preferences.snoozeDurationMinutes, options: [5, 10, 15, 30, 60])
                        .frame(width: 56)
                    Text("minutes")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            onboardingDivider

            GridRow {
                HStack(spacing: 4) {
                    Text("Auto-Snooze")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                    HelpTip("Adding a to-do also snoozes Cmd+Tab for the duration above, same as clicking Snooze by hand.")
                }
                Toggle("", isOn: $preferences.autoSnoozeAfterEntry)
                    .labelsHidden()
            }

            onboardingDivider

            GridRow {
                HStack(spacing: 4) {
                    Text("Auto-Dismiss")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                    HelpTip("How long the panel sits idle before it fades away on its own if you don't interact with it.")
                }
                HStack(spacing: 6) {
                    TimeoutComboBox(value: $preferences.inactivityTimeout, options: [3, 5, 7, 10, 15, 20, 30])
                        .frame(width: 56)
                    Text("seconds")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            onboardingDivider

            GridRow {
                HStack(spacing: 4) {
                    Text("Default Alarm")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                    HelpTip("Automatically sets a reminder on every new to-do, so you get a nudge later even if you forget to check back.")
                }
                HStack(spacing: 6) {
                    Toggle("", isOn: $preferences.defaultAlarmEnabled)
                        .labelsHidden()
                    if preferences.defaultAlarmEnabled {
                        Picker("", selection: $preferences.defaultAlarmDurationSeconds) {
                            ForEach(IntentRowView.reminderDurations, id: \.seconds) { duration in
                                Text(duration.label).tag(duration.seconds)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            if !isOnboarding {
                GridRow {
                    Text("")
                    Button("Clear Finished Items", role: .destructive) {
                        showingClearCompletedConfirm = true
                    }
                    .confirmationDialog(
                        "Delete all completed items? This can't be undone.",
                        isPresented: $showingClearCompletedConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Completed", role: .destructive) {
                            for id in intentStore.clearCompleted() {
                                reminderScheduler.cancel(for: id)
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }

                GridRow {
                    Text("")
                    Button("Clear All Items", role: .destructive) {
                        showingClearAllConfirm = true
                    }
                    .confirmationDialog(
                        "Delete your entire task history? This can't be undone.",
                        isPresented: $showingClearAllConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Everything", role: .destructive) {
                            for id in intentStore.clearAll() {
                                reminderScheduler.cancel(for: id)
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }

                GridRow {
                    HStack(spacing: 4) {
                        Text("Ignore apps")
                            .foregroundStyle(Color.panelTextSecondary)
                            .lineLimit(1)
                        HelpTip("Squirrel Trap will not prompt when you switch away from these apps. Useful for tools you tab in and out of constantly, where the prompt is noise rather than a catch.")
                    }
                    excludedApps
                }

                GridRow {
                    Text("")
                    Button("Quit Squirrel Trap", role: .destructive, action: onQuit)
                }
            }
        }
        .font(.system(size: 12))
        .onChange(of: showingClearCompletedConfirm) { _, _ in onConfirmationActiveChanged(hasActiveConfirmation) }
        .onChange(of: showingClearAllConfirm) { _, _ in onConfirmationActiveChanged(hasActiveConfirmation) }
    }
}
