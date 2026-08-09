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
                Text("Launch at Login")
                    .foregroundStyle(Color.panelTextSecondary)
                    .lineLimit(1)
                Toggle("", isOn: $launchAtLoginEnabled)
                    .labelsHidden()
                    .onChange(of: launchAtLoginEnabled) { _, newValue in
                        LaunchAtLoginManager.setEnabled(newValue)
                    }
            }

            onboardingDivider

            GridRow {
                Text("Snooze for")
                    .foregroundStyle(Color.panelTextSecondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    TimeoutComboBox(value: $preferences.snoozeDurationMinutes, options: [5, 10, 15, 30, 60])
                        .frame(width: 56)
                    Text("minutes")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .help("How long the Snooze button (bottom-left of this panel) suppresses Cmd+Tab for")
            }

            onboardingDivider

            GridRow {
                Text("Auto-Snooze")
                    .foregroundStyle(Color.panelTextSecondary)
                    .lineLimit(1)
                Toggle("", isOn: $preferences.autoSnoozeAfterEntry)
                    .labelsHidden()
                    .help("Adding a to-do also snoozes Cmd+Tab for the duration above, same as clicking Snooze by hand")
            }

            onboardingDivider

            GridRow {
                Text("Auto-Dismiss")
                    .foregroundStyle(Color.panelTextSecondary)
                    .lineLimit(1)
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
                Text("Default Alarm")
                    .foregroundStyle(Color.panelTextSecondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Toggle("", isOn: $preferences.defaultAlarmEnabled)
                        .labelsHidden()
                        .help("New to-dos automatically get a reminder set")
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
