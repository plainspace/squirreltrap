# Design

Implementation lives in `SquirrelTrap/Views/GlassTheme.swift`. This file explains
the reasoning; that file is the source of truth for values.

## Theme

The panel follows the system light/dark setting. It is not dark by default.

The scene: someone glances at a small panel in the bottom-left corner of a
screen they are already working on, in whatever lighting their room happens to
have, for about two seconds. A panel that is dark on a light desktop is a hole
punched in the screen. The right answer is whatever the rest of their Mac is
doing, which means the OS decides and the app does not.

This is also why the panel used to be dark-only: it forced `vibrantDark` so a
`.hudWindow` blur would render. The material is now `.popover`, which blurs
correctly in both appearances.

## Color

Strategy: **Restrained**. Tinted neutrals plus one accent.

Neutrals are tinted toward the accent hue rather than being pure white or pure
grey, so the card reads as a deliberate surface rather than an untinted default.

Accent is a blue at `#2E7CD6` light / `#4A9BEE` dark, defined in the
`AccentColor` asset so SwiftUI's `.accentColor` resolves to it everywhere.

Accent is permitted on exactly four things:

- The checkbox, when checked
- Links
- Selected states (the Preferences sidebar, a set alarm)
- Drop indicators

Everything else that used to be blue is now a neutral. Decorative and
resting-state icons are `panelTertiary`; destructive actions are
`panelDestructive`; favourite stars are `panelStar` and only when actually on.

A colour-tagged to-do checks off in its own tag colour instead of blue, and the
tag tints its swatch only, never a row fill. Sixteen tags tinting sixteen row
backgrounds is a paint chart, not a list.

## Typography

System font throughout, one family, four sizes:

| Token | Size | Role |
|---|---|---|
| `Theme.title` | 15 semibold | Panel-level titles, the favourites heading |
| `Theme.body` | 13.5 | To-do text, anything that is the content |
| `Theme.bodyMedium` | 13.5 medium | Text being typed into the input |
| `Theme.secondary` | 11.5 | Counts, status lines, helper copy |
| `Theme.sectionHeader` | 11 semibold, uppercase | Group labels ("COMPLETED") |

Four sizes is the ceiling. A fifth size is almost always a hierarchy problem
being solved with type instead of with structure.

## Spacing

4pt grid. `Theme.gutter` (20) is the screen edge. `Theme.rowHeight` (34) is the
number that matters most: at 32 the list reads as a dense table, at 40 as a
settings screen.

Separators are inset to `Theme.textColumnInset` so they start at the text column
rather than cutting under the checkboxes.

## Components

- **Checkbox** is a rounded square, not a circle. A circle reads as a radio
  button, meaning pick one of these; a rounded square reads as independently
  done or not, which is what this list is.
- **Rows are flat.** No card, no border, no fill at rest. Boundaries come from
  the hairline beneath and the hover fill.
- **Secondary controls fade in on hover**, but anything currently doing
  something (a set alarm, an assigned colour, a favourited star) stays visible
  at rest, or hovering away would look like unsetting it. Opacity is what
  changes, never presence, so keyboard and VoiceOver users always reach them and
  the row's width never shifts.
- **Footer controls are ghost.** No fill, no outline. Preferences, snooze and
  the Ko-fi link sit at the lowest weight on the surface.

## Motion

150 to 250 ms, ease-out. No bounce, no elastic, no orchestrated entrances.

Motion is allowed to convey exactly two things: that a click landed, and that an
item left the list. Everything else is instant.

`Core/CelebrationTiming.swift` holds the one duration knob for the
check-off sequence. All animation respects `accessibilityReduceMotion`, which
skips straight to the end state rather than playing a faster version.

## Sizing

`PromptPanelView.cardSize` is the single source of the card's dimensions.
`PanelController` sizes the AppKit window from it, and every view swapped into
that same window frames itself against it. A view that hardcodes its own size
does not resize the panel, it just gets clipped inside it.
