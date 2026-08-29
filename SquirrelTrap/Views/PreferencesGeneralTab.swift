import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PreferencesGeneralTab: View {
    @ObservedObject var preferences: AppPreferences
    let intentStore: IntentStore
    let reminderScheduler: ReminderScheduler
    @Binding var launchAtLoginEnabled: Bool
    var onConfirmationActiveChanged: (Bool) -> Void
    var onQuit: () -> Void
    /// Version and update-checking, which used to live in the Preferences
    /// sidebar. Nil during onboarding, where that section is not shown.
    /// Observed by PreferencesView, which owns it -- this view re-renders as
    /// part of that parent's body, so no @ObservedObject is needed here (and an
    /// optional one is not expressible anyway).
    var updateChecker: UpdateChecker?
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
        panel.allowedContentTypes = [UTType.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Ignore"
        panel.message = "Squirrel Trap will not prompt when you switch away from these apps."

        // Both lines are required, and the picker is invisible without them.
        //
        // Preferences is presented inside a .floating NSPanel, so an open panel
        // at normal window level opens BEHIND it: the click appears to do
        // nothing at all. And this is an accessory app (LSUIElement) that
        // deliberately never activates, so without activating here the picker
        // cannot take keyboard focus even once it is on top.
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            preferences.excludedBundleIDs.insert(id)
        }
    }

    /// A grouped Form, which is the construct macOS System Settings itself uses.
    ///
    /// This replaced a flat two-column Grid holding every setting in one
    /// undifferentiated list. The controls were all correct; nothing told you
    /// that Snooze, Auto-Snooze, Auto-Dismiss and Ignore Apps are one idea
    /// (when may this thing interrupt me) while Clear and Quit are another.
    /// Sections carry that, and a Form gets the right-aligned label column, the
    /// inset rounded groups and the platform's own row metrics for free rather
    /// than by hand.
    var body: some View {
        SettingsForm {
            Section {
                LabeledContent {
                    Toggle("", isOn: $launchAtLoginEnabled)
                        .labelsHidden()
                        .onChange(of: launchAtLoginEnabled) { _, newValue in
                            LaunchAtLoginManager.setEnabled(newValue)
                            AnalyticsService.shared.updateUserProperties(preferences: preferences)
                        }
                } label: {
                    SettingLabel("Launch at Login", "Automatically starts Squirrel Trap when you log in to your Mac.")
                }
            }

            Section("Interruptions") {
                LabeledContent {
                    HStack(spacing: 6) {
                        TimeoutComboBox(value: $preferences.snoozeDurationMinutes, options: [5, 10, 15, 30, 60])
                            .frame(width: 56)
                        Text("minutes")
                            .foregroundStyle(Color.panelTextSecondary)
                            .fixedSize()
                    }
                } label: {
                    SettingLabel("Snooze for", "How long the Snooze button suppresses Cmd+Tab for.")
                }

                LabeledContent {
                    Toggle("", isOn: $preferences.autoSnoozeAfterEntry)
                        .labelsHidden()
                } label: {
                    SettingLabel("Auto-Snooze", "Adding a to-do also snoozes Cmd+Tab for the duration above, same as clicking Snooze by hand.")
                }

                LabeledContent {
                    HStack(spacing: 6) {
                        TimeoutComboBox(value: $preferences.inactivityTimeout, options: [3, 5, 7, 10, 15, 20, 30])
                            .frame(width: 56)
                        Text("seconds")
                            .foregroundStyle(Color.panelTextSecondary)
                            .fixedSize()
                    }
                } label: {
                    SettingLabel("Auto-Dismiss", "How long the panel sits idle before it fades away on its own.")
                }

                if !isOnboarding {
                    LabeledContent {
                        excludedApps
                    } label: {
                        SettingLabel("Ignore apps", "Squirrel Trap will not prompt when you switch away from these apps. Useful for tools you tab in and out of constantly, where the prompt is noise rather than a catch.")
                    }
                }
            }

            Section("New To-Dos") {
                LabeledContent {
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
                } label: {
                    SettingLabel("Default Alarm", "Automatically sets a reminder on every new to-do, so you get a nudge later even if you forget to check back.")
                }
            }

            // Destructive actions get their own section at the bottom, away
            // from anything you might click while browsing. Hidden entirely
            // during onboarding, where a new user has nothing to delete.
            if !isOnboarding {
                Section {
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

                    Button("Quit Squirrel Trap", role: .destructive, action: onQuit)
                }
            }

            // Version and updates, which used to sit in the Preferences
            // sidebar under the app icon. That put a permanent, rarely-read
            // block of chrome beside every tab and cost the content column a
            // third of the panel's width. Checking for updates is a General
            // setting in every Mac app that has one; this is where people
            // already look for it.
            if let updateChecker, !isOnboarding {
                Section {
                    LabeledContent {
                        updateStatus(updateChecker)
                    } label: {
                        SettingLabel("Version \(Self.appVersionString)")
                    }
                }
            }
        }
        .onChange(of: showingClearCompletedConfirm) { _, _ in onConfirmationActiveChanged(hasActiveConfirmation) }
        .onChange(of: showingClearAllConfirm) { _, _ in onConfirmationActiveChanged(hasActiveConfirmation) }
    }

    private static var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Persistent confirmation that a check actually happened, rather than a
    /// manual check silently reverting to itself with no visible feedback when
    /// nothing newer is found.
    @ViewBuilder
    private func updateStatus(_ updateChecker: UpdateChecker) -> some View {
        if updateChecker.isChecking {
            ProgressView()
                .controlSize(.small)
        } else if let update = updateChecker.availableUpdate {
            Link("Update to v\(update.version)", destination: update.url)
        } else {
            HStack(spacing: 6) {
                Button(preferences.lastUpdateCheckAt == nil ? "Check for Updates" : "Check Again") {
                    Task { await updateChecker.check() }
                }
                if preferences.lastUpdateCheckAt != nil {
                    Label("Up to date", systemImage: "checkmark.circle")
                        // Matches the Appearance tab's permission checkmark: a
                        // confirmation stays secondary, never accent.
                        .foregroundStyle(Color.panelTextSecondary)
                }
            }
        }
    }
}

