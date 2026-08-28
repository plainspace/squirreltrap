import Foundation

@MainActor
final class PromptPanelViewModel: ObservableObject {
    @Published var draftText: String = ""
    @Published var focusToken = UUID()
    @Published var isShowingFavorites = false {
        // The two modes show different lists, so a row selected in one has no
        // counterpart in the other.
        didSet { if isShowingFavorites != oldValue { selectedEntryID = nil } }
    }
    // Not persisted — only meaningful for the current panel session, set when a
    // reminder fires so the relevant row can call itself out visually.
    @Published var highlightedEntryID: UUID?
    // Briefly true right when any task is completed -- drives the celebration
    // animation, then clears itself. Not persisted; a transient UI moment,
    // not state.
    @Published var isCelebrating = false
    /// The keyboard-selected row, or nil when focus belongs to the text field.
    ///
    /// The panel opens on a keystroke and is dismissed by one, but until now
    /// everything between those two keystrokes needed a mouse: there was no way
    /// to check anything off without pointing at it. Arrow keys move this;
    /// Return acts on it. nil is a real state, not "nothing selected yet" --
    /// it means the caret is back in the field and typing appends to the draft.
    @Published var selectedEntryID: UUID?

    let intentStore: IntentStore
    private let reminderScheduler: ReminderScheduler
    private let preferences: AppPreferences

    init(intentStore: IntentStore, reminderScheduler: ReminderScheduler, preferences: AppPreferences) {
        self.intentStore = intentStore
        self.reminderScheduler = reminderScheduler
        self.preferences = preferences
    }

    // MARK: Keyboard navigation

    /// The rows the arrow keys walk, in the order they appear on screen:
    /// pending first, then completed, matching PromptPanelView's own two
    /// sections. Favourites mode walks its own list instead.
    private var navigableEntries: [IntentEntry] {
        if isShowingFavorites { return intentStore.favoriteEntries }
        let visible = intentStore.visibleEntries
        return visible.filter { !$0.completed } + visible.filter { $0.completed }
    }

    /// Down from the text field selects the first row; down from the last row
    /// stays put rather than wrapping. Wrapping in a list this short means
    /// holding the key sends you back to the top without you noticing.
    func selectNext() {
        let entries = navigableEntries
        guard !entries.isEmpty else { return }
        guard let current = selectedEntryID,
              let index = entries.firstIndex(where: { $0.id == current })
        else {
            selectedEntryID = entries.first?.id
            return
        }
        guard index + 1 < entries.count else { return }
        selectedEntryID = entries[index + 1].id
    }

    /// Up from the first row returns focus to the text field rather than
    /// stopping dead, so the field is always one key away from the top of the
    /// list.
    func selectPrevious() {
        let entries = navigableEntries
        guard let current = selectedEntryID,
              let index = entries.firstIndex(where: { $0.id == current })
        else { return }
        if index == 0 {
            clearSelection()
        } else {
            selectedEntryID = entries[index - 1].id
        }
    }

    func clearSelection() {
        selectedEntryID = nil
        focusToken = UUID()
    }

    /// Return on a selected row toggles it. Selection then moves to whatever
    /// took its place at the same index, so checking off three things in a row
    /// is Return-Return-Return rather than Return-Down-Return-Down.
    func activateSelection() {
        guard let selected = selectedEntryID else { return }
        if isShowingFavorites {
            guard let entry = intentStore.favoriteEntries.first(where: { $0.id == selected }) else { return }
            repeatFavorite(entry)
            clearSelection()
            return
        }
        let entries = navigableEntries
        let index = entries.firstIndex { $0.id == selected }
        toggleCompleted(id: selected)
        guard let index else { return }
        let remaining = navigableEntries.filter { !$0.completed }
        selectedEntryID = remaining.indices.contains(index)
            ? remaining[index].id
            : remaining.last?.id
        if selectedEntryID == nil { clearSelection() }
    }

    func setReminder(for entryID: UUID, duration: TimeInterval) {
        let date = Date().addingTimeInterval(duration)
        intentStore.setReminder(id: entryID, date: date)
        reminderScheduler.schedule(for: entryID, at: date)
    }

    func cancelReminder(for entryID: UUID) {
        intentStore.setReminder(id: entryID, date: nil)
        reminderScheduler.cancel(for: entryID)
    }

    /// Completing a task with an active alarm silences it -- there's nothing
    /// left to be reminded about. Celebrates every completion (not gated by
    /// streak/day logic); toggling a task back to incomplete never does.
    func toggleCompleted(id: UUID) {
        guard let entry = intentStore.entries.first(where: { $0.id == id }) else { return }
        let isCompleting = !entry.completed
        intentStore.toggleCompleted(id: id)
        guard isCompleting else { return }
        AnalyticsService.shared.track(.taskCompleted, properties: [
            "time_since_created_seconds": Date().timeIntervalSince(entry.createdAt),
            "had_reminder": entry.reminderDate != nil,
        ])
        if entry.reminderDate != nil {
            cancelReminder(for: id)
        }
        if preferences.celebrationEnabled {
            isCelebrating = true
            Task {
                try? await Task.sleep(for: .seconds(celebrationDuration))
                isCelebrating = false
            }
        }
    }

    /// Called every time the panel is about to be shown: clears the draft, bumps
    /// focusToken so the text field reliably re-focuses even if the panel view's
    /// identity didn't change, and drops back out of favorites mode from any
    /// previous show. `entryID` carries a reminder-triggered highlight through;
    /// a normal Cmd+Tab show passes nil, clearing any highlight from before.
    func reset(highlighting entryID: UUID? = nil) {
        draftText = ""
        focusToken = UUID()
        isShowingFavorites = false
        highlightedEntryID = entryID
        // Every show starts with the caret in the field. Carrying a row
        // selection over from the last time the panel was open would mean the
        // first thing typed goes nowhere.
        selectedEntryID = nil
    }

    func submit(dismiss: () -> Void) {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            addEntryApplyingDefaultAlarm(text: trimmed)
        }
        dismiss()
    }

    /// Logs a fresh copy of a favorited intent, then drops back to the normal
    /// list so the user immediately sees it land at the top.
    func repeatFavorite(_ entry: IntentEntry) {
        addEntryApplyingDefaultAlarm(text: entry.text)
        isShowingFavorites = false
    }

    /// Shared by submit() and repeatFavorite() so "every new to-do gets a
    /// reminder" (Preferences' Default Alarm toggle), "every new to-do gets a
    /// color" (Default Color), and "every new to-do also snoozes Cmd+Tab"
    /// (Auto-snooze after entry) only need implementing once, each
    /// independent of the others' state.
    @discardableResult
    private func addEntryApplyingDefaultAlarm(text: String) -> IntentEntry {
        let entry = intentStore.add(text: text)

        if let defaultColorTag = preferences.defaultColorTag {
            intentStore.setColor(id: entry.id, colorTag: defaultColorTag)
        }
        if preferences.defaultAlarmEnabled {
            setReminder(for: entry.id, duration: preferences.defaultAlarmDurationSeconds)
        }
        if preferences.autoSnoozeAfterEntry {
            preferences.snoozeUntil = Date().addingTimeInterval(preferences.snoozeDurationMinutes * 60)
            debugLog("Squirrel Trap DEBUG: [addEntry] auto-snooze set snoozeUntil=\(preferences.snoozeUntil!)\n")
        }
        AnalyticsService.shared.track(.taskAdded, properties: [
            "has_color_tag": preferences.defaultColorTag != nil,
            "has_reminder": preferences.defaultAlarmEnabled,
        ])
        return entry
    }

    #if DEBUG
    /// Re-fires the celebration on demand, without needing to actually
    /// complete a task.
    func previewCelebration() {
        isCelebrating = true
        Task {
            try? await Task.sleep(for: .seconds(celebrationDuration))
            isCelebrating = false
        }
    }
    #endif
}
