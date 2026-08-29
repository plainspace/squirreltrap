import SwiftUI

struct PromptPanelView: View {
    @ObservedObject var viewModel: PromptPanelViewModel
    @ObservedObject var intentStore: IntentStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var reminderSyncEngine: ReminderSyncEngine
    @ObservedObject var updateChecker: UpdateChecker
    @FocusState private var isInputFocused: Bool
    @State private var isEndDropTargeted = false
    // Celebration-animation state, driven by runCelebrationAnimation() below
    // when viewModel.isCelebrating flips true -- see that function for
    // the timeline. Purely visual, not persisted. The row-collapse half of the
    // celebration lives on the individual to-do row instead -- see
    // PendingRowView.startCompletionAnimation.
    @State private var countScale: CGFloat = 1.0
    // Which CoachTip (if any) is currently popped over its anchor button --
    // see checkForCoachTip(). Not persisted; only whether a tip has ever
    // fired is (implicitly, via AppPreferences.totalPanelShows only ever
    // equaling any given trigger count once).
    @State private var activeCoachTip: CoachTip?
    @State private var isHoveringVersion = false
    // Gates AnalyticsConsentPrompt to at most once per launch even if this
    // view re-appears multiple times before the user answers it.
    @State private var isShowingAnalyticsConsent = false
    var onDismiss: () -> Void
    var onEscape: () -> Void
    var onOpenPreferences: () -> Void
    var onSnooze: () -> Void
    var onDragHandleHoverChanged: (Bool) -> Void

    /// The one place the card's dimensions are declared. `PanelController`
    /// sizes the actual window from this, and every other view that gets
    /// swapped into the same panel (Preferences, Onboarding, Reminders Sync,
    /// the permission explainer) frames itself against it too. It has to be a
    /// single constant rather than a number repeated per screen: the window is
    /// sized by AppKit, not by SwiftUI, so a view that disagrees doesn't resize
    /// the panel — it just gets clipped inside it.
    static let cardSize = CGSize(width: 440, height: 420)

    init(
        viewModel: PromptPanelViewModel,
        preferences: AppPreferences,
        reminderSyncEngine: ReminderSyncEngine,
        updateChecker: UpdateChecker,
        onDismiss: @escaping () -> Void,
        onEscape: @escaping () -> Void,
        onOpenPreferences: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onDragHandleHoverChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.intentStore = viewModel.intentStore
        self.preferences = preferences
        self.reminderSyncEngine = reminderSyncEngine
        self.updateChecker = updateChecker
        self.onDismiss = onDismiss
        self.onEscape = onEscape
        self.onOpenPreferences = onOpenPreferences
        self.onSnooze = onSnooze
        self.onDragHandleHoverChanged = onDragHandleHoverChanged
    }

    private var themeAccent: Color { preferences.panelTheme.accent }

    // Pending items always float above completed ones, each group newest-first.
    private var pendingEntries: [IntentEntry] {
        intentStore.visibleEntries.filter { !$0.completed }
    }

    private var completedEntries: [IntentEntry] {
        intentStore.visibleEntries.filter { $0.completed }
    }

    var body: some View {
        // spacing: 0 throughout — every gap below is stated explicitly at the
        // element that owns it, so the vertical rhythm is readable in one place
        // rather than being the sum of a stack spacing and several paddings.
        VStack(alignment: .leading, spacing: 0) {
            // Upstream's inline update link and syncing spinner live in this
            // fork's `statusStrip` instead, directly under the input, so they
            // share one slot rather than each claiming permanent vertical space.
            header
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)

            actionRow
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 14)

            statusStrip
                .padding(.horizontal, Theme.gutter)

            // maxHeight: .infinity so the list is unambiguously the element
            // that absorbs whatever height is left over. Without it the stack
            // could settle at its intrinsic height and sit pinned to the top of
            // the card, which put the footer somewhere in the middle with the
            // leftover space below it.
            Group {
                if viewModel.isShowingFavorites {
                    favoritesList
                } else {
                    entriesList
                }
            }
            .padding(.top, 12)
            .frame(maxHeight: .infinity, alignment: .top)

            // An explicit 1pt rule rather than Divider(). Divider's height is
            // not guaranteed to be a hairline: inside a stack it can resolve
            // taller, and since it sits directly above the footer, that extra
            // height reads as the footer having more space above its contents
            // than below them.
            Rectangle()
                .fill(Color.panelSeparator)
                .frame(height: 1)

            // Explicit asymmetric padding rather than centring in a fixed
            // height: see Theme.footerPaddingTop for why the two differ.
            footer
                .padding(.leading, Theme.footerPaddingLeading)
                .padding(.trailing, Theme.footerPaddingTrailing)
                .padding(.top, Theme.footerPaddingTop)
                .padding(.bottom, Theme.footerPaddingBottom)
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height, alignment: .top)
        .coordinateSpace(name: "panel")
        // SwiftUI's own exit-command path — needed alongside DismissiblePanel's
        // AppKit-level cancelOperation because a focused TextField sometimes
        // swallows Escape before it ever reaches the responder chain. Both
        // paths funnel into the same guarded handler (see PanelController),
        // so whichever one actually fires, confirmation dialogs are still
        // respected and double-firing is harmless.
        .onExitCommand(perform: onEscape)
        // Keyboard navigation. The panel is summoned by a keystroke and
        // dismissed by one, but everything in between used to need a mouse:
        // there was no way to check anything off without pointing at it.
        //
        // Only the arrows are handled here. They reach this modifier because
        // the focused text field is single-line and has no use for up/down.
        //
        // Space and Delete deliberately have no binding: the field holds focus
        // so it can be typed into at any moment, and it consumes both. Handlers
        // for them existed here and could never fire. Favouriting and deleting
        // stay mouse actions until there is a modifier combination the field
        // does not eat. Return is handled on the field itself, via onSubmit.
        // Escape is handled here as well as through onExitCommand and the
        // AppKit-level monitor. A focused NSTextField treats Escape as its own
        // cancel and can consume it before either of those sees it, which left
        // the one key everyone reaches for doing nothing while the field had
        // focus, which is almost always.
        //
        // A row selection is cleared first and the panel stays up: Escape means
        // "back out of what I am doing", and when something is selected that is
        // the selection, not the panel.
        .onKeyPress(.escape) {
            if viewModel.selectedEntryID != nil {
                viewModel.clearSelection()
            } else {
                onEscape()
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.selectNext()
            return .handled
        }
        .onAppear {
            // Deferred a tick -- setting @FocusState synchronously inside
            // onAppear can fire mid-update-cycle on macOS, which is what
            // produces SwiftUI's "Publishing changes from within view
            // updates is not allowed" console warning. Async lets the
            // current update transaction finish first; the focus change
            // still lands effectively instantly.
            if !viewModel.isShowingFavorites {
                DispatchQueue.main.async { isInputFocused = true }
            }
            // A consent decision takes priority over the coach-tip rotation
            // on any appearance where it hasn't been answered yet -- both are
            // popovers anchored in this same view, and showing both at once
            // would just be visual noise for a choice that only needs asking
            // one time, ever.
            if !preferences.hasAskedAnalyticsConsent {
                isShowingAnalyticsConsent = true
            } else {
                checkForCoachTip()
            }
        }
        .onChange(of: viewModel.focusToken) { _, _ in
            if !viewModel.isShowingFavorites {
                DispatchQueue.main.async { isInputFocused = true }
            }
        }
        .onChange(of: preferences.totalPanelShows) { _, _ in
            guard preferences.hasAskedAnalyticsConsent else { return }
            checkForCoachTip()
        }
    }

    private func decideAnalyticsConsent(enabled: Bool) {
        preferences.analyticsEnabled = enabled
        preferences.hasAskedAnalyticsConsent = true
        AnalyticsService.shared.updateConsent(enabled: enabled)
        isShowingAnalyticsConsent = false
    }

    /// Every 4th show starting at the 2nd (2, 6, 10, 14, ...) picks the next
    /// tip in the rotation through whatever hasn't been individually
    /// dismissed yet, via coachTipRotationIndex -- an undismissed tip keeps
    /// recurring as the cycle comes back around, so this doesn't stop until
    /// every tip has eventually been dismissed (or Reset All Tips runs).
    private func checkForCoachTip() {
        guard preferences.showTips else { return }
        let count = preferences.totalPanelShows
        guard count >= 2, (count - 2).isMultiple(of: 4) else { return }
        let undismissed = CoachTip.allCases.filter { !preferences.dismissedCoachTips.contains($0.rawValue) }
        guard !undismissed.isEmpty else { return }
        let tip = undismissed[preferences.coachTipRotationIndex % undismissed.count]
        activeCoachTip = tip
        preferences.coachTipRotationIndex += 1
        AnalyticsService.shared.track(.coachTipShown, properties: ["tip_id": tip.rawValue])
    }

    /// Single choke point for every way a coach tip can close -- the "Got
    /// it" button, clicking outside the popover, or Escape all end up here.
    /// Dismissing always means permanently: there's no more per-tip "show
    /// this again" opt-in, so any close drops the tip from the rotation for
    /// good (recoverable only via Preferences -> Activity -> Reset All Tips).
    private func dismissActiveCoachTip(_ tip: CoachTip) {
        preferences.dismissedCoachTips.insert(tip.rawValue)
        activeCoachTip = nil
        AnalyticsService.shared.track(.coachTipDismissed, properties: ["tip_id": tip.rawValue])
    }

    private func coachTipPopoverBinding(for tip: CoachTip) -> Binding<Bool> {
        Binding(
            get: { activeCoachTip == tip },
            set: { isPresented in
                if !isPresented { dismissActiveCoachTip(tip) }
            }
        )
    }

    @ViewBuilder
    private func coachTipBubble(for tip: CoachTip) -> some View {
        CoachTipBubble(
            message: tip.message(preferences: preferences),
            themeAccent: themeAccent,
            onDismiss: { dismissActiveCoachTip(tip) }
        )
    }

    /// The day's numbers on the left, the favourites toggle on the right.
    ///
    /// No app title. The panel is summoned by the user, appears in a fixed
    /// corner, and has its own icon in the menu bar; nobody seeing it needs to
    /// be told which app it belongs to. The title was pure chrome, and it was
    /// occupying the most valuable line on the surface.
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            activitySummary

            Spacer(minLength: 0)
        }
        // The analytics consent popover anchored to upstream's header title.
        // That title is gone here, so it anchors to the row that replaced it,
        // which occupies the same corner of the card.
        .popover(isPresented: $isShowingAnalyticsConsent) {
            AnalyticsConsentPrompt(themeAccent: themeAccent, onDecide: decideAnalyticsConsent)
        }
        // Nothing sits at the trailing end of this row any more: the card's
        // top-right corner belongs to the close button, which is an AppKit view
        // outside SwiftUI's layout and would otherwise land on top of whatever
        // was here. The favourites toggle moved to the footer.
        .padding(.trailing, Theme.controlHeight + 8)
    }

    /// Quiet, always-visible -- no badges, no "you lost your streak" copy on
    /// a reset. When viewModel.isCelebrating fires (every task completed, not
    /// just streak-day extensions), runCelebrationAnimation() pulses today's
    /// count and it settles back on its own.
    ///
    /// The 🔥 and ✓ emoji here were the only two glyphs in the app that came
    /// from the emoji font: they ignored the surrounding weight and colour, and
    /// sat on their own baseline. SF Symbols take the text's colour and weight,
    /// which is the entire point of using them next to text.
    private var activitySummary: some View {
        let days = intentStore.currentStreak
        return HStack(spacing: 10) {
            if preferences.showStreak {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                    Text("\(days)d")
                }
                .foregroundStyle(viewModel.isCelebrating ? themeAccent : Color.panelTextSecondary)
                .help("\(days) day\(days == 1 ? "" : "s") in a row")
                .accessibilityLabel("\(days) day\(days == 1 ? "" : "s") in a row")
            }

            // "today" is load-bearing, not filler: this counts what was checked
            // off *today*, while the list below shows the last 20 entries
            // regardless of when they were completed. Without the word, a panel
            // showing two ticked rows and the number 1 just looks broken.
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                Text("\(intentStore.todayCompletedCount)")
                    .scaleEffect(countScale)
                Text("today")
            }
            .foregroundStyle(Color.panelTextSecondary)
            .help("Checked off today")
            .accessibilityLabel("\(intentStore.todayCompletedCount) checked off today")
        }
        .font(Theme.secondary)
        .imageScale(.small)
        .frame(height: Theme.controlHeight)
        .onChange(of: viewModel.isCelebrating) { _, newValue in
            if newValue { runCelebrationAnimation() }
        }
    }

    /// Timed as a fraction of celebrationDuration (see
    /// Core/CelebrationTiming.swift -- the one knob to tweak for pacing).
    /// Scaled to 1.35x rather than the old 1.5x: at 1.5 a number in an 11.5pt
    /// line visibly pushes its neighbours around as it grows.
    private func runCelebrationAnimation() {
        let half = celebrationDuration / 2
        withAnimation(.spring(response: half, dampingFraction: 0.5)) {
            countScale = 1.35
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + half) {
            withAnimation(.spring(response: half, dampingFraction: 0.8)) {
                countScale = 1.0
            }
        }
    }

    /// Update-available and sync-in-progress notices. Both are transient and
    /// neither is the point of the panel, so they share one slot directly under
    /// the input rather than each claiming permanent vertical space.
    @ViewBuilder
    private var statusStrip: some View {
        if let update = updateChecker.availableUpdate {
            Link(destination: update.url) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Update to v\(update.version)")
                }
                .font(Theme.secondary)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.top, 8)
        }

        if reminderSyncEngine.isSyncing {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text("Syncing Reminders…")
                    .font(Theme.secondary)
                    .foregroundStyle(Color.panelTextSecondary)
            }
            .padding(.top, 8)
        }
    }

    // spacing 2, not 12: every control in here now carries its own 24pt hit
    // frame, so the visual gap is the frames' own padding. Adding 12 on top of
    // that pushed the footer apart into three unrelated islands.
    private var footer: some View {
        HStack(spacing: 2) {
            Button {
                // Dismiss any open coach-tip popover *before* navigating away
                // -- PanelController.setContent() removes this whole view
                // from the window to swap in Preferences, and doing that
                // while a popover anchored to it is still marked presented
                // left the popover's child window dangling, corrupting
                // Preferences' responder chain (Escape/dismiss stopped
                // working once you'd opened it that way).
                activeCoachTip = nil
                onOpenPreferences()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.ghostIcon)
            .help("Preferences")
            .accessibilityLabel("Preferences")
            .popover(isPresented: coachTipPopoverBinding(for: .preferences)) {
                coachTipBubble(for: .preferences)
            }
            // Reminders/Default Alarm aren't literally gear-icon features,
            // but there's no other always-present anchor in this footer to
            // hang a settings-adjacent tip on -- each only ever shows once,
            // at its own trigger count, so stacking a few here over time
            // reads as "more to discover" rather than repeated nagging.
            .popover(isPresented: coachTipPopoverBinding(for: .reminders)) {
                coachTipBubble(for: .reminders)
            }
            .popover(isPresented: coachTipPopoverBinding(for: .defaultAlarm)) {
                coachTipBubble(for: .defaultAlarm)
            }
            .popover(isPresented: coachTipPopoverBinding(for: .launchAtLogin)) {
                coachTipBubble(for: .launchAtLogin)
            }

            // Rapidly switching apps can turn the popup itself into the
            // annoyance — Snooze suppresses Cmd+Tab triggering it for a bit
            // (the menu bar icon and Cmd+, still work, and clicking the icon
            // cancels the snooze early). Duration is configured in Preferences;
            // the fade + "Snoozing…" message live in PanelController so both
            // this button and the one in Preferences share the same behavior.
            SnoozeButton(minutes: preferences.snoozeDurationMinutes) {
                activeCoachTip = nil
                onSnooze()
            }
            .help("Snooze Cmd+Tab for a while")
                .popover(isPresented: coachTipPopoverBinding(for: .snooze)) {
                    coachTipBubble(for: .snooze)
                }

            Button {
                viewModel.isShowingFavorites.toggle()
            } label: {
                Image(systemName: viewModel.isShowingFavorites ? "star.fill" : "star")
            }
            .buttonStyle(.ghostIcon(
                restingTint: viewModel.isShowingFavorites ? .panelStar : nil,
                hoverTint: .panelStar
            ))
            .help("Favorites")
            .accessibilityLabel(viewModel.isShowingFavorites ? "Back to your list" : "Show favorites")

            Spacer()

            versionLink

            KofiButton(onOpened: onDismiss)
        }
        // Every child is exactly controlHeight tall, so they share one centre
        // line rather than each centring on its own intrinsic height. The
        // surrounding strip is sized by Theme.footerHeight at the call site,
        // which is what makes the space above and below equal.
        .frame(height: Theme.controlHeight)
    }

    /// The text field, on its own row. It used to share a row with the
    /// favourites star, which meant the one control the panel exists for was
    /// inset from the right edge by an unrelated toggle; the star now lives up
    /// in the header and the field runs the full width.
    private var actionRow: some View {
        Group {
            if viewModel.isShowingFavorites {
                Text("Favorites")
                    .font(Theme.title)
                    .foregroundStyle(Color.panelTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("What are you about to do?", text: $viewModel.draftText)
                    .textFieldStyle(.plain)
                    .font(Theme.bodyMedium)
                    .foregroundStyle(Color.panelTextPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .panelSurface()
                    .focused($isInputFocused)
                    // Return is routed through the field's own submit rather
                    // than through an .onKeyPress on the panel. The field holds
                    // focus the whole time the panel is open, and a focused
                    // TextField consumes Return before any ancestor key handler
                    // sees it, so the panel-level handler was simply dead.
                    //
                    // Keeping focus in the field is deliberate: you can type at
                    // any moment without first dismissing a selection. Return
                    // therefore means "act on the selected row" when there is
                    // one, and "log what I typed" when there isn't.
                    .onSubmit {
                        if viewModel.selectedEntryID != nil {
                            viewModel.activateSelection()
                        } else {
                            viewModel.submit(dismiss: onDismiss)
                        }
                    }
            }
        }
    }

    private var entriesList: some View {
        Group {
            if pendingEntries.isEmpty && completedEntries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(pendingEntries.enumerated()), id: \.element.id) { index, entry in
                            PendingRowView(
                                entry: entry,
                                themeAccent: themeAccent,
                                isHighlighted: entry.id == viewModel.highlightedEntryID,
                                isSelected: entry.id == viewModel.selectedEntryID,
                                onToggleCompleted: { viewModel.toggleCompleted(id: entry.id) },
                                onToggleFavorite: { intentStore.toggleFavorite(id: entry.id) },
                                onSetReminder: { duration in viewModel.setReminder(for: entry.id, duration: duration) },
                                onCancelReminder: { viewModel.cancelReminder(for: entry.id) },
                                onSetColor: { color in intentStore.setColor(id: entry.id, colorTag: color) },
                                onDelete: {
                                    intentStore.delete(id: entry.id)
                                    AnalyticsService.shared.track(.taskDeleted)
                                },
                                onCommitEdit: { text in intentStore.setText(id: entry.id, text: text) },
                                onDrop: { draggedID in intentStore.movePendingEntry(id: draggedID, before: entry.id) },
                                onDragHandleHoverChanged: onDragHandleHoverChanged
                            )
                            // Namespaced so the pending and completed lists can
                            // never claim the same SwiftUI identity. Both are
                            // ForEaches keyed on entry.id inside one LazyVStack,
                            // so an entry crossing between them presented the
                            // same id in a different structural slot: SwiftUI
                            // moved the realized row rather than rebuilding it,
                            // and it carried on drawing its old completed state
                            // (checkbox filled, text struck through) even though
                            // the store and the enclosing body had both updated.
                            .id("pending-\(entry.id)")

                            if index < pendingEntries.count - 1 {
                                rowSeparator
                            }
                        }

                        // Every row above only offers "drop before me" — without
                        // this, there's no way to drag something to the very
                        // bottom of the pending list.
                        if !pendingEntries.isEmpty {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(isEndDropTargeted ? themeAccent : Color.clear)
                                .frame(height: isEndDropTargeted ? 2 : 12)
                                .padding(.leading, Theme.textColumnInset + 8)
                                .padding(.vertical, isEndDropTargeted ? 5 : 0)
                                .dropDestination(for: String.self) { items, _ in
                                    guard let draggedIDString = items.first, let draggedID = UUID(uuidString: draggedIDString) else { return false }
                                    intentStore.movePendingEntryToEnd(id: draggedID)
                                    return true
                                } isTargeted: { targeted in
                                    isEndDropTargeted = targeted
                                }
                        }

                        if !completedEntries.isEmpty {
                            Text("Completed")
                                .font(Theme.sectionHeader)
                                .foregroundStyle(Color.panelTextSecondary)
                                .textCase(.uppercase)
                                .kerning(0.5)
                                .padding(.leading, 8)
                                .padding(.top, pendingEntries.isEmpty ? 4 : 16)
                                .padding(.bottom, 6)

                            ForEach(Array(completedEntries.enumerated()), id: \.element.id) { index, entry in
                                IntentRowView(
                                    entry: entry,
                                    themeAccent: themeAccent,
                                    isSelected: entry.id == viewModel.selectedEntryID,
                                    onToggleCompleted: { viewModel.toggleCompleted(id: entry.id) },
                                    onToggleFavorite: { intentStore.toggleFavorite(id: entry.id) },
                                    onDelete: {
                                        intentStore.delete(id: entry.id)
                                        AnalyticsService.shared.track(.taskDeleted)
                                    },
                                    onCommitEdit: { text in intentStore.setText(id: entry.id, text: text) }
                                )
                                // See the pending list above: distinct identity
                                // namespace, so crossing between the two lists
                                // rebuilds the row instead of relocating a stale
                                // one.
                                .id("done-\(entry.id)")

                                if index < completedEntries.count - 1 {
                                    rowSeparator
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter - 8)
                    .padding(.bottom, 8)
                    .overlayScrollers()
                }
            }
        }
    }

    /// In debug builds this carries the next-version/build tag that used to sit
    /// in the header, so there is exactly one place on the panel that answers
    /// "which build is this" in either configuration.
    private var versionLabel: String {
        #if DEBUG
        return "v\(debugNextVersion)\(debugBuildTag)"
        #else
        return "v\(UpdateChecker.appVersion)"
        #endif
    }

    /// The version, as a link to the repo. Lowest weight on the surface: it is
    /// reference information, not an action, and it earns its place only
    /// because "which build am I actually running" is the first question worth
    /// asking when something looks wrong.
    private var versionLink: some View {
        Button {
            if let url = UpdateChecker.repoURL {
                NSWorkspace.shared.open(url)
            }
            onDismiss()
        } label: {
            Text(versionLabel)
                .font(Theme.secondary)
                .foregroundStyle(isHoveringVersion ? Color.panelTextSecondary : Color.panelTertiary)
                .padding(.horizontal, 4)
                .frame(height: Theme.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringVersion = $0 }
        .help("View Squirrel Trap on GitHub")
        .accessibilityLabel("Version \(UpdateChecker.appVersion). View on GitHub.")
    }

    /// Inset to start at the text column rather than running the full width:
    /// a rule that cuts under the checkboxes visually detaches them from the
    /// text they belong to.
    private var rowSeparator: some View {
        Rectangle()
            .fill(Color.panelSeparator)
            .frame(height: 1)
            .padding(.leading, Theme.textColumnInset + 8)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Nothing pending.")
                .font(Theme.body)
                .foregroundStyle(Color.panelTextSecondary)
            Text("Type above to catch the next one.")
                .font(Theme.secondary)
                .foregroundStyle(Color.panelTertiary)
                .padding(.top, 3)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var favoritesList: some View {
        Group {
            if intentStore.favoriteEntries.isEmpty {
                VStack(spacing: 0) {
                    Spacer()
                    Text("No favorites yet.")
                        .font(Theme.body)
                        .foregroundStyle(Color.panelTextSecondary)
                    Text("Star any item to keep it here.")
                        .font(Theme.secondary)
                        .foregroundStyle(Color.panelTertiary)
                        .padding(.top, 3)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(intentStore.favoriteEntries.enumerated()), id: \.element.id) { index, entry in
                            FavoriteRowView(
                                entry: entry,
                                isSelected: entry.id == viewModel.selectedEntryID,
                                onRepeat: { viewModel.repeatFavorite(entry) },
                                onRemove: { intentStore.toggleFavorite(id: entry.id) }
                            )

                            if index < intentStore.favoriteEntries.count - 1 {
                                rowSeparator
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter - 8)
                    .padding(.bottom, 8)
                    .overlayScrollers()
                }
            }
        }
    }
}

/// A saved favourite. Same row metrics as IntentRowView so the two lists feel
/// like the same list in two modes, and the same hover-to-reveal rule for the
/// destructive control.
private struct FavoriteRowView: View {
    let entry: IntentEntry
    var isSelected: Bool = false
    let onRepeat: () -> Void
    let onRemove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.checkboxGap) {
            Button(action: onRepeat) {
                HStack(spacing: Theme.checkboxGap) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isHovering ? Color.accentColor : Color.panelTertiary)
                        .frame(width: Theme.checkboxSize, height: Theme.checkboxSize)
                    Text(entry.text)
                        .font(Theme.body)
                        .foregroundStyle(Color.panelTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Log this again")
            .accessibilityLabel("Log \(entry.text) again")

            Button(action: onRemove) {
                Image(systemName: "star.slash")
            }
            .buttonStyle(.ghostIcon(size: 11.5, hoverTint: .panelDestructive))
            .opacity(isSelected || isHovering ? 1 : 0)
            .help("Remove from favorites")
            .accessibilityLabel("Remove from favorites")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: Theme.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(isSelected || isHovering ? Color.panelSurfaceRaised : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
    }
}
