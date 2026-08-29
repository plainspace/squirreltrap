import AppKit
import SwiftUI

struct PreferencesSyncTab: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var cloudSyncEngine: CloudSyncEngine
    let intentStore: IntentStore
    var onOpenReminderSync: () -> Void
    var isOnboarding: Bool = false

    @State private var showCopiedConfirmation = false

    var body: some View {
        SettingsForm {
            // iCloud's status, its error and its manual trigger are one
            // subject, so they sit in one group. Previously the status text was
            // crammed into the same row as the toggle and the error landed in a
            // label-less row below it, which read as an unrelated stray line.
            Section("iCloud") {
                LabeledContent {
                    Toggle("", isOn: $preferences.iCloudSyncEnabled)
                        .labelsHidden()
                        .disabled(!cloudSyncEngine.isAvailable)
                        .onChange(of: preferences.iCloudSyncEnabled) { oldValue, newValue in
                            // Same reasoning as Reminders sync: flip the toggle on and
                            // wait for the every-Nth-show fallback (or a push that
                            // hasn't arrived yet) reads as "nothing happened" — sync
                            // right away instead, same as turning on Reminders sync
                            // immediately forces a list load.
                            guard !oldValue, newValue else { return }
                            Task { await cloudSyncEngine.sync() }
                        }
                } label: {
                    SettingLabel("Sync this Mac", "Keeps your to-do list in sync across every Mac you use, always both ways, via your own iCloud account -- not a third-party server.")
                }

                LabeledContent {
                    HStack(spacing: 6) {
                        if cloudSyncEngine.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else if preferences.iCloudSyncEnabled {
                            Button("Sync Now") {
                                Task { await cloudSyncEngine.sync() }
                            }
                        }
                        Text(cloudSyncEngine.accountStatusDescription)
                            .foregroundStyle(Color.panelTextSecondary)
                    }
                } label: {
                    SettingLabel("Account")
                }

                if let lastSyncError = cloudSyncEngine.lastSyncError {
                    // panelDestructive rather than .red: it resolves per
                    // appearance, where a raw .red vibrates against the dark
                    // card.
                    Text(lastSyncError)
                        .foregroundStyle(Color.panelDestructive)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let lastSyncSummary = cloudSyncEngine.lastSyncSummary {
                    Text(lastSyncSummary)
                        .foregroundStyle(Color.panelTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Other Apps") {
                LabeledContent {
                    Button("Set Up…", action: onOpenReminderSync)
                } label: {
                    SettingLabel("Apple Reminders", "Optionally connects Squirrel Trap to a list in Apple's Reminders app, one-directional or both ways, your choice.")
                }

                LabeledContent {
                    HStack(spacing: 6) {
                        Button("Copy as CSV") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(intentStore.csvExport(), forType: .string)
                            // This only ever copies to the clipboard, silently -- with
                            // no confirmation it's indistinguishable from doing
                            // nothing at all. Same fix as the update-check status.
                            showCopiedConfirmation = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                showCopiedConfirmation = false
                            }
                        }
                        if showCopiedConfirmation {
                            Label("Copied", systemImage: "checkmark.circle")
                                .foregroundStyle(Color.panelTextSecondary)
                        }
                    }
                } label: {
                    SettingLabel("Export open items", "Copies your open (not completed) items to the clipboard as CSV, ready to paste into a spreadsheet.")
                }
            }
        }
        .onAppear { cloudSyncEngine.refreshAccountStatus() }
    }
}
