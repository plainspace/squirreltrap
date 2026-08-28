# Squirrel Trap

A menu-bar-only macOS app that pops up a small floating prompt every time you press Cmd+Tab, asking "what are you about to do?" It also shows your recent answers as a checklist — pending items on top, completed ones below — so unfinished intents stay visible.

The goal: catch the moment right before a keyboard-driven app switch, since that's when it's easiest to get sidetracked chasing something unrelated. (Hence the name — the squirrel is the distraction.)

## How it works

- **Native Cmd+Tab is untouched.** Squirrel Trap uses a listen-only `CGEventTap` to observe the Cmd+Tab keydown (never consuming or modifying it) and pops its own floating panel in parallel. The system app switcher keeps working exactly as it always has.
- The panel is a borderless, non-activating `NSPanel` with its blur card and close button owned directly by AppKit (not routed through SwiftUI's window sizing), so it can hold keyboard focus without stealing focus from the app you're actually switching to, and without SwiftUI silently repositioning it.
- Typing an intent and hitting Return logs it and dismisses the panel. Escape, clicking away, or the corner ✕ all dismiss instantly too — no confirmation dialogs anywhere.
- Every row has a star to favorite it (for one-click repeat later) and, once completed, a trash icon to delete it from history.
- The last 20 entries show in the panel; everything is kept indefinitely in `~/Library/Application Support/SquirrelTrap/entries.json`.
- Runs as a menu-bar-only agent (no Dock icon). Left-click the menu bar icon to open the same panel Cmd+Tab does; right-click for Preferences/Quit. The icon itself can be hidden — Cmd+, always reopens Preferences regardless.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode (full app, not just Command Line Tools)
- A Development Team selected in Signing & Capabilities (Xcode → Settings → Accounts → add your Apple ID for a free Personal Team). Without a stable signing identity, Input Monitoring permission resets on every rebuild.

## Building & running

```
open SquirrelTrap.xcodeproj
```

Select the `SquirrelTrap` scheme and "My Mac" destination, then Cmd+R. Or from the command line:

```
./scripts/run-local.sh      # Debug build, relaunch, report the pid
./scripts/install-local.sh  # Release build installed into /Applications
```

Both quit any running copy first and wait for it to actually exit. Opening
while the old process is still winding down gets LaunchServices error -600.

### Never touch the event tap before Input Monitoring is granted

`IOHIDRequestAccess` prompts **once per bundle identity, ever**. After the
first call, successful or not, macOS ignores every later call from that
identity. There is no second chance and no UI affordance to recover: the app
never appears in System Settings, Privacy & Security, Input Monitoring, and
adding it by hand with the **+** button silently does nothing, while that same
button works for every other app on the machine.

`CGEvent.tapCreate` is what burns it. It **succeeds without the permission**,
returning a live, enabled tap that never delivers a single callback, and the
attempt itself records a TCC denial that consumes the one-shot. So a single
speculative "let me just try the tap and see" permanently costs that identity
its only chance to ask. `tccutil reset` clears the grant but does not restore
the prompt.

The rule that follows: **gate on `IOHIDCheckAccess`, never on whether the tap
was created.** Nothing may call `tapCreate` until the status is `granted`.
Gating on tap creation is worse than useless, since it always succeeds and so
skips the permission screen entirely, and that screen is the only caller of
`IOHIDRequestAccess`.

Recovery, if an identity is already burned: change the bundle identifier. A
fresh identity gets a fresh one-shot.

Two further notes:

- **A locally-signed build CAN be granted Input Monitoring.** `spctl -a`
  reports `rejected`, `origin=Apple Development` for a Personal Team build, and
  that is a red herring: Gatekeeper assessment and TCC eligibility are separate
  things. Neither notarization nor a Developer ID certificate is required. This
  was established the hard way, after an earlier revision of this file
  confidently claimed the opposite.
- **Everything except the Cmd+Tab trigger works without the permission.** The
  menu bar icon opens the same panel, so the panel, the list, Preferences,
  onboarding and the widget can all be exercised while the grant is missing.
  The app should never block on it, and does not.

### Signing

Debug builds sign against `SquirrelTrap/SquirrelTrap-LocalDev.entitlements`,
which asks for nothing but the sandbox opt-out. That is what lets the project
build on a **free Apple Personal Team**, which cannot provision CloudKit
containers, App Groups, push, or time-sensitive notifications. The cost is that
iCloud sync across Macs, the desktop widget's shared data, and time-sensitive
alarm delivery are all inert in a Debug build. The Cmd+Tab loop, the list,
Reminders sync and ordinary notifications are unaffected.

`SquirrelTrap-Release.entitlements` still declares the full set. With a paid
Developer Program team signed in to Xcode, point the Debug configuration's
`CODE_SIGN_ENTITLEMENTS` back at it and everything returns.

Note that `CKContainer(identifier:)` **traps** rather than returning nil when
its container is not entitled, so `CloudSyncEngine` reads the entitlement off
its own code signature before constructing one. Removing that check
reintroduces a crash on launch for anyone building without CloudKit
provisioning.

### First run

Squirrel Trap needs **Input Monitoring** permission (System Settings → Privacy & Security → Input Monitoring) to observe the Cmd+Tab keystroke — this is a passive listen-only observation, it does not read or log any other keys you type. On first launch (or whenever permission is missing), it shows a one-time panel explaining this with a "Grant Access" button that opens the right System Settings pane. After granting, fully quit and relaunch once — `CGEventTap` reliably starts delivering events on a fresh process launch, not mid-session.

## Project layout

```
SquirrelTrap/
├── SquirrelTrapApp.swift             # @main App struct, NSStatusItem + AppDelegate wiring
├── Core/
│   ├── AppSwitchMonitor.swift        # CGEventTap wrapper + gesture debounce state machine
│   ├── PermissionManager.swift       # Input Monitoring TCC check/request/open-settings
│   ├── PanelController.swift         # NSPanel + native blur card/close button, show/hide, dismiss/focus wiring
│   ├── LaunchAtLoginManager.swift    # SMAppService wrapper
│   ├── AppPreferences.swift          # UserDefaults-backed settings
│   ├── PreferencesHotkeyMonitor.swift # global Cmd+, listener
│   ├── ReminderScheduler.swift       # per-item local notification alarms
│   ├── ReminderSyncEngine.swift      # EventKit sync with an Apple Reminders list (title + completion only)
│   ├── CloudSyncEngine.swift         # CloudKit sync of full entries across your own Macs
│   ├── UpdateChecker.swift           # polls GitHub Releases for a newer version
│   ├── ActivityStats.swift           # pure streak / daily-completion-count math, derived from IntentStore.entries
│   ├── CelebrationTiming.swift       # single adjustable duration for the completion celebration animation
│   ├── DebugBuildTag.swift           # #if DEBUG-only build tag shown in the main panel header
│   └── DebugLog.swift                # #if DEBUG-gated stderr logging helper
├── Persistence/
│   ├── IntentEntry.swift             # Codable model: id, text, createdAt, completed, completedAt, favorite, colorTag, etc.
│   ├── IntentStore.swift             # JSON load/save, add/toggle/delete, rolling-window + favorites + activity queries
│   └── TodoColorTag.swift            # the 16 preset color tags
└── Views/
    ├── PromptPanelViewModel.swift
    ├── PromptPanelView.swift         # text field, pending/completed list, favorites view, footer, streak/celebration
    ├── IntentRowView.swift           # one row: checkbox, text, favorite star, reminder/color controls, delete
    ├── PendingRowView.swift          # wraps IntentRowView with a drag handle + the completion shrink/puff animation
    ├── ColorTagGridPicker.swift      # shared 4x4 color-swatch grid (per-item picker + Default Color picker)
    ├── PermissionRequestView.swift   # one-time explainer shown when permission is missing
    ├── PreferencesView.swift         # sidebar tab container
    ├── PreferencesTab.swift          # tab enum (General/Appearance/Sync/Activity)
    ├── PreferencesGeneralTab.swift   # snooze, auto-dismiss, default alarm, default color, clear/quit
    ├── PreferencesAppearanceTab.swift # menu bar icon, translucency, celebration toggle
    ├── PreferencesSyncTab.swift      # iCloud sync + entry point into Reminders sync setup
    ├── PreferencesActivityTab.swift  # 7-day bar chart, best day, average tasks/day
    ├── ReminderSyncPreferencesView.swift # Reminders sync direction/list picker
    ├── KofiButton.swift              # shared support-link button
    ├── SnoozeButton.swift
    ├── TimeoutComboBox.swift
    └── GlassTheme.swift              # design tokens: type scale, metrics, light/dark colors, Checkbox
```

## Third-party assets

The menu bar glyph is the `squirrel` icon from [Lucide](https://lucide.dev),
used under the ISC license, shipped as a vector asset at
`SquirrelTrap/Assets.xcassets/MenuBarSquirrel.imageset/squirrel.svg`. Xcode
compiles the SVG to a vector rendition, and the imageset is marked
template-rendering so AppKit draws it in the menu bar's own colour.

## Design

The panel follows the system light/dark setting. Every colour, type size and
metric comes from `Views/GlassTheme.swift`. Add a token there rather than
writing a literal size or colour into a view, and prefer the semantic label
colours (`panelTextPrimary` / `panelTextSecondary` / `panelTertiary`) over
white-or-black-at-an-opacity, so contrast tracks the user's appearance and
accessibility settings.

Accent blue is reserved for checkboxes, links, selected states and genuinely
primary buttons. Decorative and resting-state icons are `panelTertiary`;
destructive actions are `panelDestructive`. Row-level secondary controls fade
in on hover but are never conditionally *removed*, so keyboard and VoiceOver
users always reach them and the row's width never shifts.

`PromptPanelView.cardSize` is the single source of the card's dimensions.
`PanelController` sizes the window from it, and every view swapped into that
same window frames itself against it. A view that hardcodes its own size won't
resize the panel, it will just be clipped inside it.

## Not in v1

- Voice input as a distinct feature (typing only — though the text field is a normal macOS field, so dictation/voice-to-text tools already work through it)
- Replacing/customizing the native Cmd+Tab switcher UI itself
- Browsing full history beyond the last 20 entries (they're on disk, just not surfaced in the UI yet)
- Automated tests — none exist yet; everything is verified by hand

## Distribution

The App Store is not an option for this app — Mac App Store submissions require App Sandbox, and App Sandbox makes it impossible to create the system-wide `CGEventTap` this app depends on. Direct distribution only:

- **Quick/free**: build a Release archive, zip it, share it. Recipients need a one-time right-click → Open to bypass Gatekeeper, since it's only signed with a personal development certificate.
- **Polished**: enroll in the Apple Developer Program ($99/year), get a Developer ID Application certificate, then Xcode → Product → Archive → Distribute App → Direct Distribution to notarize. Recipients get zero security warnings.
