# Security

## Why this app asks for Input Monitoring

Squirrel Trap detects Cmd+Tab so it can pop up alongside the app switcher. On macOS that requires a session-level `CGEventTap`, which is gated behind the Input Monitoring permission — the same permission a keylogger would need. That's a reasonable thing to be cautious about, so here's exactly what the tap does, in [`AppSwitchMonitor.swift`](SquirrelTrap/Core/AppSwitchMonitor.swift):

- **It's listen-only.** The tap is created with [`options: .listenOnly`](SquirrelTrap/Core/AppSwitchMonitor.swift#L41-L50) — it can observe events but cannot modify or consume them. The native app switcher, and every other app on the system, sees every keystroke exactly as if the tap didn't exist.
- **It only asks for two event types.** `eventsOfInterest` is limited to `keyDown` and `flagsChanged`, plus `tapDisabledByTimeout`/`tapDisabledByUserInput` (macOS's own notifications that the tap was suspended, which the code re-enables and nothing else). No other event type ever reaches this code.
- **It reads two fields and nothing else.** The callback in [`handleTapEvent`](SquirrelTrap/Core/AppSwitchMonitor.swift#L70-L102) checks `event.flags.contains(.maskCommand)` and `event.getIntegerValueField(.keyboardEventKeycode)` — whether Command is held, and whether the key is Tab. It never reads a character, unicode value, or any other field. Nothing about what you type is stored, logged, or transmitted; the only thing this code can ever know is "Cmd+Tab happened."
- **The app runs without the App Sandbox** (`com.apple.security.app-sandbox = false` in the entitlements). This is a requirement, not an oversight: a session-level `CGEventTap` cannot be created from inside the sandbox at all. Everything else about the app's own data (the to-do list, preferences) still lives in the normal per-app container regardless.

## Reporting a vulnerability

If you find a security issue, please email **jeremy@livedigitally.com** with details rather than opening a public issue. We'll acknowledge and work with you on a fix and disclosure timeline.
