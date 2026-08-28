import AppKit
import Combine
import SwiftUI

/// NSPanel subclass so Escape (cancelOperation) reliably dismisses the panel
/// even when a SwiftUI text field inside it has focus and might otherwise
/// swallow onExitCommand.
final class DismissiblePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        debugLog("Squirrel Trap DEBUG: [cancelOperation] AppKit cancelOperation fired\n")
        onCancel?()
    }
}

/// The card's close button.
///
/// Exists as a subclass purely to get a hover state: `NSButton` has no
/// equivalent of SwiftUI's `.onHover`, so it needs its own tracking area. The
/// previous button was a bare `xmark.circle.fill` with no hover feedback at
/// all, sitting half-outside the card's rounded corner because a 24pt control
/// cannot fit in a 20pt shadow margin. This one lives inside the card and
/// carries a fill that only appears under the pointer.
final class PanelCloseButton: NSButton {
    private var trackingArea: NSTrackingArea?

    private var isHovering = false {
        didSet {
            guard isHovering != oldValue else { return }
            contentTintColor = isHovering ? .labelColor : .tertiaryLabelColor
            layer?.backgroundColor = isHovering
                ? NSColor.labelColor.withAlphaComponent(0.10).cgColor
                : NSColor.clear.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }

    override func mouseExited(with event: NSEvent) { isHovering = false }

    /// The panel is `isMovableByWindowBackground`, and AppKit decides whether a
    /// drag moves the window by asking the view under the cursor. Without this,
    /// a click that drifts by a pixel on the way up became a window drag
    /// instead of a close.
    override var mouseDownCanMoveWindow: Bool { false }
}

@MainActor
final class PanelController: NSObject {
    private let intentStore: IntentStore
    private let preferences: AppPreferences
    private let reminderScheduler: ReminderScheduler
    private let reminderSyncEngine: ReminderSyncEngine
    private let cloudSyncEngine: CloudSyncEngine
    private let updateChecker: UpdateChecker
    private let promptViewModel: PromptPanelViewModel

    // The visible card is 420x340 (340 = 320 + one half-row, so an overflowing
    // list always leaves a partial next row peeking into view as a "there's more
    // below" cue instead of clipping cleanly at a full row boundary); the window
    // itself is padded out by cardMargin on every side so the close button can
    // sit outside the card's own corner without being clipped at the window edge.
    /// Shared by the blur, the opaque fallback and the content container, all
    /// three of which are stacked on the same rect — they have to round
    /// identically or the odd one out shows as a sliver at each corner.
    static let cardCornerRadius: CGFloat = 12

    /// Matches `Theme.controlHeight` so the close button is the same physical
    /// target as every other icon button on the surface.
    static let closeButtonSize: CGFloat = 26

    private let cardSize = NSSize(width: PromptPanelView.cardSize.width, height: PromptPanelView.cardSize.height)
    private let cardMargin: CGFloat = 20
    private var windowSize: NSSize {
        NSSize(width: cardSize.width + cardMargin * 2, height: cardSize.height + cardMargin * 2)
    }

    private var panel: DismissiblePanel?
    // The blur card and close button are plain AppKit views owned directly by the
    // window's contentView, not routed through SwiftUI. Embedding NSVisualEffectView
    // via a SwiftUI `.background()` modifier (even with isOpaque/backgroundColor
    // cleared) didn't reliably keep it as a live, blur-through layer — and swapping
    // `contentViewController` let NSHostingController's automatic content-size
    // negotiation quietly resize/reposition the window on every content swap.
    // Owning the chrome natively avoids both problems.
    private var effectView: NSVisualEffectView?
    // Shown instead of effectView when translucency is turned off in
    // Preferences. SwiftUI content lives in contentContainer, a separate
    // sibling view — not a child of effectView — so hiding the blur to show
    // this doesn't also hide the actual panel content.
    private var opaqueFallbackView: NSView?
    private var contentContainer: NSView?
    private var closeButton: NSButton?
    // A permanent color layer sitting above the material and below whatever
    // SwiftUI content is currently showing. The material alone just blurs
    // whatever's behind the window — on a warm/brown wallpaper that reads as
    // muddy, not blue. This overlay is what guarantees the panel always reads
    // as cool blue glass regardless of what's behind it.
    private var colorTintOverlay: NSView?
    private var currentHostingView: NSView?
    private var translucencyCancellable: AnyCancellable?
    private var panelThemeCancellable: AnyCancellable?
    // Shown in place of whatever SwiftUI content is up (Prompt or Preferences,
    // wherever Snooze was clicked from) while the panel fades out slowly.
    private var snoozeMessageLabel: NSTextField?

    // Reused across shows instead of recreated each time: recreating on every
    // Cmd+Tab (especially rapid repeats) raced SwiftUI's focus system against the
    // old view's teardown, producing "first responder in a different window"
    // warnings that AppKit flags as an eventual crash risk.
    private var promptHostingController: NSHostingController<PromptPanelView>?
    private var permissionHostingController: NSHostingController<PermissionRequestView>?
    private var preferencesHostingController: NSHostingController<PreferencesView>?
    private var reminderSyncPreferencesHostingController: NSHostingController<ReminderSyncPreferencesView>?
    private var onboardingHostingController: NSHostingController<OnboardingView>?
    // Set right before opening Reminders Sync setup *from* onboarding, so its
    // Back button returns there instead of normal Preferences -- reset back
    // to false the moment it's used, so every other entry into Reminders
    // Sync setup keeps going to normal Preferences as usual.
    private var reminderSyncReturnsToOnboarding = false
    private var globalClickMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?
    private var hasReclaimedFocusForCurrentShow = false
    // Sync only ever runs as a side effect of normal use — every Nth fresh
    // panel show — never in the background. Counted the same "fresh show"
    // way hasReclaimedFocusForCurrentShow is, not on content-switch shows
    // like Preferences -> back.
    private var invocationsSinceLastSync = 0
    var onQuit: (() -> Void)?
    /// Lets AppDelegate swap the menu bar icon to the app icon while the
    /// panel is visible, and back to the default otherwise.
    var onVisibilityChanged: ((Bool) -> Void)?
    // Lets the dismiss-on-any-non-text-key logic below tell a bare Cmd tap
    // (dismiss) apart from a real Cmd+Tab switch (never dismiss) — see
    // handlePotentialDismissKey. Wired by AppDelegate to AppSwitchMonitor,
    // which is the only thing with visibility into the real Cmd+Tab gesture
    // (via its own CGEventTap; a held Cmd key alone looks identical to us).
    var isSwitchGestureActive: (() -> Bool)?

    // Permission/onboarding content shouldn't be dismissible by accident the
    // way the ephemeral Cmd+Tab prompt is -- there's no recovery path back to
    // it (the menu bar icon, Cmd+Tab, and Cmd+, all route through the very
    // guards this content exists to satisfy), so a stray click elsewhere or a
    // few idle seconds must never make it disappear. Checked in present()
    // to skip installing the three dismiss mechanisms below for that content.
    private var isShowingStickyContent = false

    // Fades the panel out if you never interact with it, so an accidental or
    // half-considered Cmd+Tab doesn't just leave it sitting on screen forever.
    // Duration is user-configurable (AppPreferences.inactivityTimeout).
    private var dismissTimer: Timer?
    private var localActivityMonitor: Any?

    // Any non-text keyboard input (Escape, a Cmd/Control shortcut combo, or
    // just tapping Cmd/Option/Fn alone) dismisses the panel — the idea being
    // that reaching for any of those means your attention already moved on
    // from typing an intent. Shift and Cmd+Tab itself are the only exceptions.
    private var dismissKeyMonitor: Any?
    private var modifiersHeldAtRisk: NSEvent.ModifierFlags = []

    // Escape reliably dismisses the panel via DismissiblePanel.cancelOperation
    // (see that type's comment) — but that override fires at the AppKit level,
    // with no awareness of a SwiftUI confirmationDialog currently open on top.
    // Without this guard, hitting Escape to cancel "Clear All Items" closed
    // the whole panel *in addition to* the confirmation dialog, instead of
    // just canceling the dialog. PreferencesView flips this while a
    // confirmationDialog is presented.
    private var suppressEscapeDismiss = false

    init(intentStore: IntentStore, preferences: AppPreferences, reminderScheduler: ReminderScheduler, reminderSyncEngine: ReminderSyncEngine, cloudSyncEngine: CloudSyncEngine, updateChecker: UpdateChecker) {
        self.intentStore = intentStore
        self.preferences = preferences
        self.reminderScheduler = reminderScheduler
        self.reminderSyncEngine = reminderSyncEngine
        self.cloudSyncEngine = cloudSyncEngine
        self.updateChecker = updateChecker
        self.promptViewModel = PromptPanelViewModel(intentStore: intentStore, reminderScheduler: reminderScheduler, preferences: preferences)
        super.init()

        // Every Cmd+Tab ends with some other app's window becoming key — that's not
        // the user clicking away, it's the switch itself completing. Reclaim key focus
        // right after so the panel keeps the caret instead of self-dismissing.
        //
        // This must only happen for THAT ONE activation, not every subsequent app
        // activation while the panel happens to still be visible — logging showed
        // reclaiming unconditionally here fights any app the user deliberately
        // switches to afterward (e.g. Activity Monitor) for real key status,
        // sometimes leaving Escape/keystrokes going to the wrong app entirely.
        // hasReclaimedFocusForCurrentShow (reset in present()) limits it to once.
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // NotificationCenter's queue:.main guarantees this always runs on the
            // main thread, but the closure type isn't statically MainActor-isolated
            // -- the Task hop satisfies the compiler without changing behavior.
            Task { @MainActor in
                guard let self, !self.hasReclaimedFocusForCurrentShow else { return }
                self.hasReclaimedFocusForCurrentShow = true
                self.reclaimKeyFocusIfVisible()
            }
        }
    }

    deinit {
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
        if let localActivityMonitor {
            NSEvent.removeMonitor(localActivityMonitor)
        }
        if let dismissKeyMonitor {
            NSEvent.removeMonitor(dismissKeyMonitor)
        }
        dismissTimer?.invalidate()
    }

    func showPromptPanel(highlighting entryID: UUID? = nil) {
        // Redirects every normal entry point (Cmd+Tab, menu bar click) into
        // onboarding until it's actually completed -- dismissing onboarding
        // without finishing just postpones it, since the next trigger lands
        // right back here.
        guard preferences.hasCompletedOnboarding else {
            showOnboardingPanel()
            return
        }
        // Deliberately NO permission guard here.
        //
        // Upstream routes this back to PermissionRequestView whenever Input
        // Monitoring is missing, so the menu bar icon can always reach that
        // screen. That is right when the permission is obtainable and the
        // screen is a step on the way in. It is wrong when the permission
        // cannot be obtained at all: a build signed with a free Personal Team
        // is refused Input Monitoring outright on macOS 26 (see
        // DEVELOPMENT.md), which turned the explainer into a permanent wall in
        // front of an app that otherwise works perfectly well.
        //
        // Input Monitoring gates exactly one thing: the Cmd+Tab trigger.
        // Capturing intents, the list, reminders, sync and Preferences need
        // none of it, and the menu bar icon opens the same panel. So a missing
        // permission costs the user a keyboard shortcut, not the application.
        // The explainer is still shown once at launch and is still reachable
        // from Preferences; it just no longer blocks the way in.
        isShowingStickyContent = false
        // Drives CoachTip's triggerCount checks in PromptPanelView -- only
        // counts real prompt-panel shows, never Preferences/onboarding ones.
        preferences.totalPanelShows += 1
        AnalyticsService.shared.track(.panelOpened, properties: ["has_highlight": entryID != nil])
        // Re-arm the once-per-show reclaim guard on every invocation, not just
        // when the panel transitions from hidden to visible: a second Cmd+Tab
        // while the panel is already up from the first one previously left
        // this permanently latched true, silently blocking every subsequent
        // reclaim for the rest of that session (focus only ever landing in
        // the text field on the very first Cmd+Tab).
        hasReclaimedFocusForCurrentShow = false
        // Clear the draft/favorites-mode before the window appears, so there's no
        // flash of stale content — but the focus *trigger* below has to wait until
        // after present() actually makes the window key, otherwise SwiftUI applies
        // it to a not-yet-key window and the caret never actually lands.
        promptViewModel.reset(highlighting: entryID)
        _ = obtainPanel()
        let controller = promptHostingController ?? {
            let controller = NSHostingController(
                rootView: PromptPanelView(
                    viewModel: promptViewModel,
                    preferences: preferences,
                    reminderSyncEngine: reminderSyncEngine,
                    updateChecker: updateChecker,
                    onDismiss: { [weak self] in self?.hidePanel() },
                    onEscape: { [weak self] in
                        debugLog("Squirrel Trap DEBUG: [onExitCommand] SwiftUI onExitCommand fired\n")
                        self?.handleCancelOperation()
                    },
                    onOpenPreferences: { [weak self] in self?.showPreferencesPanel() },
                    onSnooze: { [weak self] in self?.snoozeAndFadeOut() },
                    onDragHandleHoverChanged: { [weak self] hovering in
                        self?.panel?.isMovableByWindowBackground = !hovering
                    }
                )
            )
            promptHostingController = controller
            return controller
        }()
        setContent(controller.view)
        present()
        // The SwiftUI-level @FocusState/focusToken mechanism (still bumped
        // above via reset()) isn't reliable in this hand-rolled
        // NSPanel/NSHostingController setup right after setContent() tears
        // down whatever content was showing before and swaps this one in --
        // so grab focus directly at the AppKit level instead. SwiftUI's
        // macOS TextField backs onto a private "AppKitTextField" class, not
        // NSTextView (confirmed via a full subview-tree dump), so this
        // targets the first view anywhere in the tree with
        // canBecomeKeyView == true -- reliably the text field, since it's
        // laid out before the scrollable list/footer (whose buttons are the
        // only other canBecomeKeyView views).
        //
        // A single fixed delay before this attempt was flaky -- how long
        // AppKit/SwiftUI actually take to finish laying the view back out
        // after being reattached to the window varies, so a guess that's
        // usually-but-not-always long enough just moves the race instead of
        // closing it. Retrying on a short interval until makeFirstResponder
        // actually confirms success (rather than firing once and hoping) is
        // what actually closes it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.grabPromptFocus(attemptsRemaining: 8)
        }
    }

    /// ESC not always dismissing the panel turned out to be the same bug as
    /// this one: both cancelOperation/onExitCommand/the dismissKey monitor
    /// AND the text field's first-responder status depend on the panel
    /// genuinely being the key window, not just visible. The previous
    /// version of this method only retried makeFirstResponder, which can't
    /// succeed if the window itself never actually became key -- it would
    /// just fail silently every attempt until attemptsRemaining ran out.
    /// Now it checks and re-asserts key-window status on every attempt too.
    private func grabPromptFocus(attemptsRemaining: Int) {
        guard let panel else { return }
        if !panel.isKeyWindow {
            panel.makeKeyAndOrderFront(nil)
        }
        guard panel.isKeyWindow, let contentContainer, let keyView = firstTextFieldView(in: contentContainer) else {
            retryPromptFocusIfPossible(attemptsRemaining: attemptsRemaining)
            return
        }
        let success = panel.makeFirstResponder(keyView)
        if !success {
            retryPromptFocusIfPossible(attemptsRemaining: attemptsRemaining)
        }
    }

    private func retryPromptFocusIfPossible(attemptsRemaining: Int) {
        guard attemptsRemaining > 0 else {
            // The one log kept from this whole retry loop -- a real failure
            // signal worth seeing if this regresses, unlike the per-attempt
            // logging above which just drowned it out during normal use.
            debugLog("Squirrel Trap DEBUG: [grabPromptFocus] gave up, no attempts remaining\n")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.grabPromptFocus(attemptsRemaining: attemptsRemaining - 1)
        }
    }

    /// "First view with canBecomeKeyView == true" was too broad a heuristic:
    /// footer buttons (gear, Snooze, the coach-tip popovers now anchored to
    /// them) and the favorites star are ALL canBecomeKeyView too, and one of
    /// them winning that search intermittently (observed: the favorites
    /// star, not just footer buttons) is exactly what put focus in the wrong
    /// place while still reporting makeFirstResponder success=true, since
    /// technically that view legitimately became first responder -- just
    /// not the one this method exists to find. SwiftUI's macOS TextField
    /// backs onto a private "AppKitTextField" class (confirmed via a full
    /// subview-tree dump earlier), so this targets that specifically by
    /// type name instead of "any keyable view will do."
    private func firstTextFieldView(in view: NSView) -> NSView? {
        if view.canBecomeKeyView, String(describing: type(of: view)).contains("TextField") {
            return view
        }
        for subview in view.subviews {
            if let found = firstTextFieldView(in: subview) {
                return found
            }
        }
        return nil
    }

    func showPermissionRequestPanel() {
        // See isShowingStickyContent's declaration -- there's no recovery
        // path back to this view once it's dismissed, so it must not be
        // dismissible by a stray click or a few idle seconds the way the
        // normal ephemeral panel content is.
        isShowingStickyContent = true
        // A deliberate exception to this app never calling NSApp.activate
        // (see PermissionManager.requestAccess's own comment on the same
        // rule) -- as a .nonactivatingPanel that never takes focus on its
        // own, this view could otherwise appear behind whatever's already
        // frontmost on a brand-new install, with no menu-bar habit yet
        // formed to bring it forward.
        NSApp.activate(ignoringOtherApps: true)
        _ = obtainPanel()
        let controller = permissionHostingController ?? {
            let controller = NSHostingController(
                rootView: PermissionRequestView(onDismiss: { [weak self] in
                    // Dismissing is an answer, not a postponement. Recording it
                    // is what stops the explainer greeting the user on every
                    // launch for a permission they may not be able to grant.
                    self?.preferences.hasDismissedPermissionExplainer = true
                    self?.hidePanel()
                })
            )
            permissionHostingController = controller
            return controller
        }()
        setContent(controller.view)
        present()
    }

    func showPreferencesPanel() {
        // Cmd+, is a direct shortcut into Preferences that bypasses
        // showPromptPanel()'s own guard -- without this, it'd be an
        // unintended way to skip onboarding entirely.
        guard preferences.hasCompletedOnboarding else {
            showOnboardingPanel()
            return
        }
        isShowingStickyContent = false
        _ = obtainPanel()
        let controller = preferencesHostingController ?? {
            let controller = NSHostingController(
                rootView: PreferencesView(
                    preferences: preferences,
                    cloudSyncEngine: cloudSyncEngine,
                    updateChecker: updateChecker,
                    intentStore: intentStore,
                    reminderScheduler: reminderScheduler,
                    onBack: { [weak self] in self?.showPromptPanel() },
                    onDismiss: { [weak self] in self?.hidePanel() },
                    onQuit: { [weak self] in self?.onQuit?() },
                    onConfirmationActiveChanged: { [weak self] active in self?.suppressEscapeDismiss = active },
                    onOpenReminderSync: { [weak self] in self?.showReminderSyncPreferencesPanel() },
                    onSnooze: { [weak self] in self?.snoozeAndFadeOut() }
                )
            )
            preferencesHostingController = controller
            return controller
        }()
        setContent(controller.view)
        present()
    }

    /// Shown automatically on a genuinely fresh install (see
    /// AppPreferences.hasCompletedOnboarding) -- never call this directly
    /// from a UI trigger; showPromptPanel()/showPreferencesPanel() redirect
    /// here themselves whenever onboarding isn't complete yet.
    func showOnboardingPanel() {
        // See isShowingStickyContent's declaration -- a brand-new user has
        // even less context than an existing one for "why did this vanish
        // and how do I get it back," so the same click-away/idle-fade/
        // dismiss-key mechanisms that are fine for the ephemeral Cmd+Tab
        // prompt must not apply here either.
        isShowingStickyContent = true
        // Onboarding should always present Share Usage Data as a genuinely
        // undecided choice, never pre-answer it with a leftover value the
        // user never consciously chose *here* -- e.g. a prior real decision
        // that got left in place by a debug reset of hasAskedAnalyticsConsent
        // alone (onboarding replayed for testing without also clearing this).
        // Only resets it when the consent question hasn't actually been
        // answered yet, so a real prior "yes" from this exact flow is never
        // silently discarded.
        if !preferences.hasAskedAnalyticsConsent {
            preferences.analyticsEnabled = false
        }
        _ = obtainPanel()
        let controller = onboardingHostingController ?? {
            let controller = NSHostingController(
                rootView: OnboardingView(
                    preferences: preferences,
                    cloudSyncEngine: cloudSyncEngine,
                    intentStore: intentStore,
                    reminderScheduler: reminderScheduler,
                    onOpenReminderSync: { [weak self] in
                        self?.reminderSyncReturnsToOnboarding = true
                        self?.showReminderSyncPreferencesPanel()
                    },
                    onFinished: { [weak self] in
                        self?.preferences.hasCompletedOnboarding = true
                        AnalyticsService.shared.track(.onboardingCompleted)
                        self?.showPromptPanel()
                    }
                )
            )
            onboardingHostingController = controller
            return controller
        }()
        setContent(controller.view)
        present()
    }

    func showReminderSyncPreferencesPanel() {
        // Only sticky when reached as a detour from onboarding -- from normal
        // Preferences it's just another ordinary navigable panel.
        isShowingStickyContent = reminderSyncReturnsToOnboarding
        _ = obtainPanel()
        let controller = reminderSyncPreferencesHostingController ?? {
            let controller = NSHostingController(
                rootView: ReminderSyncPreferencesView(
                    preferences: preferences,
                    syncEngine: reminderSyncEngine,
                    onBack: { [weak self] in
                        guard let self else { return }
                        if self.reminderSyncReturnsToOnboarding {
                            self.reminderSyncReturnsToOnboarding = false
                            self.showOnboardingPanel()
                        } else {
                            self.showPreferencesPanel()
                        }
                    }
                )
            )
            reminderSyncPreferencesHostingController = controller
            return controller
        }()
        setContent(controller.view)
        present()
    }

    func hidePanel() {
        suppressEscapeDismiss = false
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        removeGlobalClickMonitor()
        stopActivityMonitoring()
        removeDismissKeyMonitor()
        onVisibilityChanged?(false)
    }

    private func reclaimKeyFocusIfVisible() {
        guard let panel, panel.isVisible else {
            return
        }
        panel.makeKeyAndOrderFront(nil)
        // This makeKeyAndOrderFront is a SEPARATE key-window grab from the one
        // showPromptPanel() already scheduled -- some other app briefly
        // reactivating right after we present (observed in practice: Cmd+Tab
        // gesture fires, our panel becomes key, then another app's own
        // didActivateApplication notification lands and this method runs)
        // can race against or outright undo that first attempt. If the
        // prompt content is what's actually showing, re-run the same
        // retrying focus grab here too rather than assuming the earlier one
        // already won the race.
        if currentHostingView === promptHostingController?.view {
            grabPromptFocus(attemptsRemaining: 8)
        }
    }

    /// Clicking into whatever app you switched to should dismiss the panel — but that
    /// click is delivered to a different app's window, not ours, so a local event
    /// handler can't see it. A global monitor is the only way to catch it.
    private func installGlobalClickMonitor() {
        removeGlobalClickMonitor()
        #if DEBUG
        // In --show-panel mode the panel exists to be inspected, so it must not
        // vanish the moment anything else on the machine is clicked. This is
        // the last of the three things that made the panel impossible to
        // screenshot from a script: the permission screen replacing it, the
        // inactivity timeout closing it, and this dismissing it.
        if CommandLine.arguments.contains("--show-panel") { return }
        #endif
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                self.hidePanel()
            }
        }
    }

    private func removeGlobalClickMonitor() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
        globalClickMonitor = nil
    }

    /// A local monitor only sees events routed to our own app's windows, which is
    /// exactly "did the user touch this panel" — no extra permission needed, unlike
    /// the global click monitor above.
    private func startActivityMonitoring() {
        stopActivityMonitoring()
        // .leftMouseDragged matters on its own, not just .leftMouseDown — the
        // panel is draggable via isMovableByWindowBackground, and without it a
        // slow drag that outlasts the timeout would fade the window out mid-drag.
        localActivityMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .scrollWheel, .mouseMoved]
        ) { [weak self] event in
            self?.registerActivity()
            return event
        }
        registerActivity()
    }

    private func installDismissKeyMonitor() {
        removeDismissKeyMonitor()
        modifiersHeldAtRisk = []
        dismissKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handlePotentialDismissKey(event)
            return event
        }
    }

    private func removeDismissKeyMonitor() {
        if let dismissKeyMonitor {
            NSEvent.removeMonitor(dismissKeyMonitor)
        }
        dismissKeyMonitor = nil
        modifiersHeldAtRisk = []
    }

    /// Escape and Cmd/Control combos dismiss immediately (any key pressed while
    /// Cmd/Control is held is clearly a shortcut, not typing — Option is exempt
    /// since Option+letter is how accented characters are typed). Bare taps of
    /// Cmd, Option, or Fn alone (held with nothing else pressed, then released)
    /// also dismiss, EXCEPT a bare Cmd tap that turns out to be the start of a
    /// real Cmd+Tab — isSwitchGestureActive is the only way to tell those apart,
    /// since the system consumes the Tab keydown before it ever reaches us.
    private func handlePotentialDismissKey(_ event: NSEvent) {
        guard !suppressEscapeDismiss, let panel, panel.isVisible else {
            return
        }
        let watched: NSEvent.ModifierFlags = [.command, .option, .function]

        switch event.type {
        case .keyDown:
            modifiersHeldAtRisk = []
            if event.keyCode == 53 {
                handleCancelOperation()
                return
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) || flags.contains(.control) {
                handleCancelOperation()
            }

        case .flagsChanged:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let currentlyHeld = flags.intersection(watched)
            let wasHeld = modifiersHeldAtRisk
            if currentlyHeld.isEmpty, !wasHeld.isEmpty {
                let wasRealSwitch = wasHeld.contains(.command) && (isSwitchGestureActive?() ?? false)
                if !wasRealSwitch {
                    handleCancelOperation()
                }
            } else {
                modifiersHeldAtRisk = currentlyHeld
            }

        default:
            break
        }
    }

    private func stopActivityMonitoring() {
        if let localActivityMonitor {
            NSEvent.removeMonitor(localActivityMonitor)
        }
        localActivityMonitor = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    /// Resets the countdown to the full (user-configurable) timeout.
    private func registerActivity() {
        dismissTimer?.invalidate()
        #if DEBUG
        // --show-panel exists so the panel can be inspected and screenshotted
        // without a human holding it open. The 7-second inactivity timeout
        // defeats that: the panel is gone before a capture can be taken. In
        // measurement mode it simply never schedules the dismiss.
        if CommandLine.arguments.contains("--show-panel") { return }
        #endif
        dismissTimer = Timer.scheduledTimer(withTimeInterval: preferences.inactivityTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fadeOutAndHide()
            }
        }
    }

    private func fadeOutAndHide() {
        guard let panel, panel.isVisible else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            hidePanel()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // NSAnimationContext always invokes this on the main thread, but its
            // completionHandler parameter isn't statically MainActor-isolated.
            Task { @MainActor in
                self?.hidePanel()
            }
        })
    }

    /// Shared by the Snooze button on both the main panel and Preferences,
    /// and by the menu bar's Snooze item — swaps in a "Snoozing…" message in
    /// place of whatever content is currently showing, then fades the whole
    /// panel out slower than the normal inactivity fade (0.3s) so it reads
    /// as a deliberate action rather than the panel just idling away.
    func snoozeAndFadeOut() {
        let minutes = Int(preferences.snoozeDurationMinutes)
        preferences.snoozeUntil = Date().addingTimeInterval(preferences.snoozeDurationMinutes * 60)
        AnalyticsService.shared.track(.snoozed, properties: ["duration_minutes": minutes])

        // The actual snooze above always applies regardless of the panel's
        // state -- the menu bar's Snooze item calls this with the panel
        // closed, and it must have the same real effect as the in-panel
        // button, not silently no-op just because there's nothing to
        // animate. Only the fade-out visual below is conditional.
        guard let panel, panel.isVisible else {
            debugLog("Squirrel Trap DEBUG: [snoozeAndFadeOut] applied, no panel visible to animate\n")
            return
        }

        let message = "Snoozing Squirrel Trap for \(minutes) Minute\(minutes == 1 ? "" : "s")"
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        debugLog("Squirrel Trap DEBUG: [snoozeAndFadeOut] message=\"\(message)\" reduceMotion=\(reduceMotion)\n")
        snoozeMessageLabel?.stringValue = message
        contentContainer?.isHidden = true
        snoozeMessageLabel?.isHidden = false

        guard !reduceMotion else {
            // Reduce Motion means no animated fade, not "skip the message too" —
            // still hold it on screen for the same duration before hiding.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                debugLog("Squirrel Trap DEBUG: [snoozeAndFadeOut] reduceMotion delay elapsed, hiding\n")
                self?.hidePanel()
                self?.resetSnoozeMessageOverlay()
            }
            return
        }
        debugLog("Squirrel Trap DEBUG: [snoozeAndFadeOut] starting 0.9s fade animation\n")
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.9
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            debugLog("Squirrel Trap DEBUG: [snoozeAndFadeOut] fade animation completed\n")
            // See fadeOutAndHide()'s completion handler for why this Task hop
            // is needed despite always running on the main thread already.
            Task { @MainActor in
                self?.hidePanel()
                self?.resetSnoozeMessageOverlay()
            }
        })
    }

    private func resetSnoozeMessageOverlay() {
        snoozeMessageLabel?.isHidden = true
        contentContainer?.isHidden = false
    }

    private func obtainPanel() -> DismissiblePanel {
        if let panel { return panel }

        let newPanel = DismissiblePanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        // Deliberately left nil so the panel inherits the user's light/dark
        // setting. It used to be pinned to .vibrantDark, because the .hudWindow
        // material it used only blurs in a vibrant-dark context — but that made
        // the whole app dark-only on a light desktop, and forced every colour in
        // it to be defined as white-at-some-opacity. The material below is
        // .popover instead, which blurs correctly in both appearances.
        newPanel.appearance = nil
        newPanel.hasShadow = true
        newPanel.hidesOnDeactivate = false
        // Off by default on every NSWindow — without this, .mouseMoved never
        // actually dispatches, so just moving the cursor (no click) wouldn't
        // count as activity for the undim/timeout logic.
        newPanel.acceptsMouseMovedEvents = true
        newPanel.isMovableByWindowBackground = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        newPanel.isReleasedWhenClosed = false
        newPanel.onCancel = { [weak self] in self?.handleCancelOperation() }

        let baseView = NSView(frame: NSRect(origin: .zero, size: windowSize))
        baseView.wantsLayer = true
        baseView.layer?.backgroundColor = .clear

        // Solid stand-in for the blur, added first so it sits behind effect —
        // only one of the two is ever visible at a time (see the
        // translucencyEnabled subscription below), toggled without touching
        // the SwiftUI content in contentContainer at all.
        let opaqueFallback = NSView(frame: NSRect(
            x: cardMargin, y: cardMargin, width: cardSize.width, height: cardSize.height
        ))
        opaqueFallback.wantsLayer = true
        // .windowBackgroundColor rather than a theme base colour: the card is
        // meant to read as a system surface in whichever appearance the user is
        // in, and turning translucency off should not also mean turning dark
        // mode on. The selected theme drives the accent, not the ground.
        opaqueFallback.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        opaqueFallback.layer?.cornerRadius = Self.cardCornerRadius
        opaqueFallback.layer?.masksToBounds = true
        baseView.addSubview(opaqueFallback)
        opaqueFallbackView = opaqueFallback

        let effect = NSVisualEffectView(frame: NSRect(
            x: cardMargin, y: cardMargin, width: cardSize.width, height: cardSize.height
        ))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Self.cardCornerRadius
        effect.layer?.masksToBounds = true
        baseView.addSubview(effect)
        effectView = effect

        // Was a 13%-opacity blue wash over the entire card, which is what made
        // everything drawn on top of it fight for contrast against a tinted
        // ground. It is now a near-neutral scrim whose only job is to lift text
        // legibility over a busy desktop, since the panel floats above whatever
        // you were just looking at.
        let tint = NSView(frame: effect.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.5).cgColor
        tint.autoresizingMask = [.width, .height]
        effect.addSubview(tint)
        colorTintOverlay = tint

        // SwiftUI content's own container, stacked above both effect and
        // opaqueFallback — a sibling of both, not a child of effect, so
        // hiding effect to reveal opaqueFallback never hides the content too.
        let content = NSView(frame: NSRect(
            x: cardMargin, y: cardMargin, width: cardSize.width, height: cardSize.height
        ))
        content.wantsLayer = true
        content.layer?.backgroundColor = .clear
        content.layer?.cornerRadius = Self.cardCornerRadius
        content.layer?.masksToBounds = true
        // A hairline on the card's own edge. Without it the blurred card melts
        // into a light desktop at the top-left corner, where there's nothing
        // behind it to darken the blur.
        content.layer?.borderWidth = 1
        content.layer?.borderColor = NSColor.separatorColor.cgColor
        baseView.addSubview(content)
        contentContainer = content

        // Sits above contentContainer (added after it), hidden until
        // snoozeAndFadeOut() shows it — the blur/tint layers stay visible
        // underneath so it still reads as the same glass card. Auto Layout
        // (not a manual frame, unlike its siblings here) is what actually
        // centers it both ways regardless of how long the message text is.
        let snoozeLabel = NSTextField(labelWithString: "")
        snoozeLabel.alignment = .center
        snoozeLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        snoozeLabel.textColor = .labelColor
        snoozeLabel.backgroundColor = .clear
        snoozeLabel.isBezeled = false
        snoozeLabel.isEditable = false
        snoozeLabel.maximumNumberOfLines = 3
        snoozeLabel.lineBreakMode = .byWordWrapping
        snoozeLabel.isHidden = true
        snoozeLabel.translatesAutoresizingMaskIntoConstraints = false
        baseView.addSubview(snoozeLabel)
        NSLayoutConstraint.activate([
            snoozeLabel.centerXAnchor.constraint(equalTo: baseView.centerXAnchor),
            snoozeLabel.centerYAnchor.constraint(equalTo: baseView.centerYAnchor),
            snoozeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: cardSize.width - 40)
        ])
        snoozeMessageLabel = snoozeLabel

        // A bare 11pt xmark, not a filled circle. Grey rather than accent-blue
        // too: closing is the least interesting thing you can do here, and an
        // accent-coloured control in the corner read as the panel's primary
        // action. The circle now belongs to the hover fill, which is the only
        // moment the control needs a shape of its own.
        let closeImage = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        let closeBtn = PanelCloseButton(image: closeImage ?? NSImage(), target: self, action: #selector(closeButtonClicked))
        closeBtn.isBordered = false
        closeBtn.imageScaling = .scaleProportionallyDown
        closeBtn.contentTintColor = .tertiaryLabelColor
        closeBtn.setAccessibilityLabel("Close")
        closeBtn.toolTip = "Close"

        // 26pt, fully inside the card, inset from its corner. The old button
        // was 24pt centred *on* the corner point, which left 10 of its 24
        // points hanging over the transparent shadow margin: it looked severed,
        // and the part of it that sat outside the card was over nothing.
        let closeButtonSize = Self.closeButtonSize
        let closeInset: CGFloat = 8
        closeBtn.frame = NSRect(
            x: cardMargin + cardSize.width - closeInset - closeButtonSize,
            y: cardMargin + cardSize.height - closeInset - closeButtonSize,
            width: closeButtonSize,
            height: closeButtonSize
        )
        closeBtn.wantsLayer = true
        closeBtn.layer?.cornerRadius = closeButtonSize / 2
        baseView.addSubview(closeBtn)
        closeButton = closeBtn

        newPanel.contentView = baseView

        panel = newPanel

        // Fires immediately with the current value on subscribe, so the
        // right view is showing from the very first present() — no extra
        // "apply initial state" call needed.
        translucencyCancellable = preferences.$translucencyEnabled.sink { [weak self] enabled in
            self?.effectView?.isHidden = !enabled
            self?.opaqueFallbackView?.isHidden = enabled
        }

        // Same "fires immediately" behavior as translucencyCancellable above
        // -- also covers the initial theme, not just later changes.
        panelThemeCancellable = preferences.$panelTheme.sink { [weak self] theme in
            self?.opaqueFallbackView?.layer?.backgroundColor = NSColor(theme.base).cgColor
            self?.colorTintOverlay?.layer?.backgroundColor = NSColor(theme.accent).withAlphaComponent(0.13).cgColor
        }

        return newPanel
    }

    @objc private func closeButtonClicked() {
        debugLog("Squirrel Trap DEBUG: [closeButtonClicked] X button clicked\n")
        hidePanel()
    }

    private func handleCancelOperation() {
        debugLog("Squirrel Trap DEBUG: [handleCancelOperation] suppressEscapeDismiss=\(suppressEscapeDismiss)\n")
        guard !suppressEscapeDismiss else { return }
        hidePanel()
    }

    /// Swaps which SwiftUI content fills the card. Only removes the previously
    /// tracked hosting view — not every subview — so the permanent blue tint
    /// overlay underneath survives content swaps instead of being wiped each time.
    private func setContent(_ hostingView: NSView) {
        guard let contentContainer else { return }
        // Cleanly resign first responder before yanking the outgoing content
        // view out of the hierarchy -- removeFromSuperview() alone doesn't
        // go through normal AppKit resignation, which left SwiftUI's
        // FocusState believing the text field was still focused after the
        // FIRST Prompt -> Preferences -> Prompt round trip. That stale true
        // silently broke the direct makeFirstResponder focus grab (see
        // showPromptPanel) on every round trip after the first, since there
        // was no false -> true transition left for anything to react to.
        if let currentHostingView, let firstResponder = panel?.firstResponder as? NSView,
           firstResponder.isDescendant(of: currentHostingView) {
            panel?.makeFirstResponder(nil)
        }
        currentHostingView?.removeFromSuperview()
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.frame = contentContainer.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentContainer.addSubview(hostingView)
        currentHostingView = hostingView
    }

    private func present() {
        guard let panel else { return }
        // Only reposition when the panel is opening fresh (Cmd+Tab, menu bar,
        // Cmd+,). Navigating between content within an already-visible panel
        // (gear -> Preferences, back -> prompt) should stay exactly where it is.
        if !panel.isVisible {
            positionOnActiveScreen(panel)
            hasReclaimedFocusForCurrentShow = false
            maybeTriggerReminderSync()
            Task { [updateChecker] in
                await updateChecker.checkIfDue()
            }
        }
        panel.makeKeyAndOrderFront(nil)
        if isShowingStickyContent {
            removeGlobalClickMonitor()
            stopActivityMonitoring()
            removeDismissKeyMonitor()
        } else {
            installGlobalClickMonitor()
            startActivityMonitoring()
            installDismissKeyMonitor()
        }
        onVisibilityChanged?(true)
    }

    /// Sync only ever runs as a side effect of showing the panel — never a
    /// background timer/observer — and only every Nth fresh show, so the
    /// core "instant popup on Cmd+Tab" feel never waits on an EventKit round
    /// trip. Runs asynchronously; doesn't block the panel appearing.
    private func maybeTriggerReminderSync() {
        let reminderSyncOn = preferences.reminderSyncDirection != .off
        // iCloud sync's primary trigger is CloudKit push notifications
        // (near-instant) — this every-Nth-show cadence is just its fallback
        // safety net, same as it's the *only* trigger for Reminders sync.
        let cloudSyncOn = preferences.iCloudSyncEnabled
        guard reminderSyncOn || cloudSyncOn else { return }
        invocationsSinceLastSync += 1
        guard invocationsSinceLastSync >= max(1, preferences.reminderSyncEveryNInvocations) else { return }
        invocationsSinceLastSync = 0
        if reminderSyncOn {
            Task { [reminderSyncEngine] in
                await reminderSyncEngine.sync()
            }
        }
        if cloudSyncOn {
            Task { [cloudSyncEngine] in
                await cloudSyncEngine.sync()
            }
        }
    }

    /// Inset from the screen edge the panel's card sits at. The window itself is
    /// larger than the card by `cardMargin` on every side (that margin is the
    /// shadow gutter), so it gets subtracted back out to make this a true
    /// card-to-screen-edge distance rather than a window-to-edge one.
    private let screenEdgeInset: CGFloat = 24

    /// Anchors to the bottom-left of whichever display currently has the mouse
    /// cursor — the cursor being the best proxy for "which screen the user is
    /// looking at" mid keyboard-switch.
    ///
    /// Bottom-*left* specifically: the bottom-right corner is where macOS puts
    /// its own transient surfaces (Notes' floating new-note window, notification
    /// banners), so the left corner is the one that stays free. Cornering it also
    /// keeps the panel off the middle of the screen, where it covered whatever
    /// the switch was in service of.
    private func positionOnActiveScreen(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.minX + screenEdgeInset - cardMargin,
            y: screenFrame.minY + screenEdgeInset - cardMargin
        )
        panel.setFrame(NSRect(origin: origin, size: windowSize), display: false)
    }
}
