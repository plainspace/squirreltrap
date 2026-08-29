import SwiftUI

/// One to-do. Flat rather than carded: the row's boundaries come from the
/// hairline beneath it and the hover fill, not from a border drawn around
/// every item. Its four secondary controls (alarm, colour, favourite, delete)
/// stay hidden until the pointer is on the row, so a list of eight to-dos is
/// eight pieces of text rather than eight pieces of text and thirty-two icons.
/// The controls still exist for keyboard and VoiceOver users at all times —
/// only their *opacity* is driven by hover, never their presence, so the row's
/// width never shifts and nothing is unreachable without a mouse.
struct IntentRowView: View {
    let entry: IntentEntry
    let themeAccent: Color
    var isHighlighted: Bool = false
    /// The keyboard-selected row. Distinct from `isHighlighted`, which marks
    /// the row a reminder just fired for: that is the app pointing at
    /// something, this is the user's own cursor.
    var isSelected: Bool = false
    /// Draws the checkbox as checked before the store says it is. PendingRowView
    /// sets this the moment you click, so the fill animation plays during the
    /// beat before the entry actually moves to the completed list — otherwise
    /// the box would stay empty right up until the row disappeared.
    var forceChecked: Bool = false
    let onToggleCompleted: () -> Void
    let onToggleFavorite: () -> Void
    var onSetReminder: ((TimeInterval) -> Void)?
    var onCancelReminder: (() -> Void)?
    var onSetColor: ((TodoColorTag?) -> Void)?
    var onDelete: (() -> Void)?
    /// Rewrites the row's text. Absent means the row is not editable.
    var onCommitEdit: ((String) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isShowingReminderPicker = false
    @State private var isShowingColorPicker = false
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isEditFieldFocused: Bool

    /// Not private — PreferencesView's "Default Alarm" picker reuses this
    /// exact same list, so the two stay in sync automatically.
    static let reminderDurations: [(label: String, seconds: TimeInterval)] = [
        ("1 min", 1 * 60),
        ("2 min", 2 * 60),
        ("5 min", 5 * 60),
        ("10 min", 10 * 60),
        ("15 min", 15 * 60),
        ("30 min", 30 * 60),
        ("60 min", 60 * 60)
    ]

    /// A colour-tagged item checks off in its own tag colour; everything else
    /// uses the panel theme's accent, so upstream's eight selectable themes
    /// drive this fork's one-accent rule rather than being replaced by it.
    private var accent: Color { entry.colorTag?.color ?? themeAccent }

    private var selectionFill: Color {
        if isSelected { return themeAccent.opacity(0.16) }
        if isHovering { return .panelSurfaceRaised }
        return .clear
    }

    /// Secondary controls fade in on hover, but anything currently *doing*
    /// something — a set alarm, an assigned colour, a favourited star — stays
    /// visible at rest. Otherwise hovering away would appear to unset it.
    private var showsSecondaryControls: Bool {
        isHovering || isSelected || isShowingReminderPicker || isShowingColorPicker || isEditing
    }

    var body: some View {
        HStack(spacing: Theme.checkboxGap) {
            // A tap gesture rather than a Button, deliberately.
            //
            // A focused SwiftUI Button on macOS activates on Return, so one
            // Return fired twice: once through the text field's onSubmit, which
            // acts on the selected row, and once by activating whichever
            // checkbox held key focus. Two toggles cancel out, so checking
            // anything off appeared to do nothing.
            //
            // `.focusable(false)` fixes that and breaks mouse clicks, which is
            // a worse bug than the one it fixes. A plain tap target takes the
            // click and is never activated by a keystroke, so both paths work
            // and neither fires twice. The accessibility traits below put back
            // what dropping Button gives up.
            Checkbox(isChecked: entry.completed || forceChecked, tint: accent)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggleCompleted)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: entry.completed ? "Mark not done" : "Mark done", onToggleCompleted)
                .accessibilityLabel(entry.completed ? "Mark not done" : "Mark done")
                .accessibilityValue(entry.completed ? "Completed" : "Not completed")

            if isEditing {
                // Deliberately unstyled: no border, no fill, the same font and
                // position the Text had. Editing a to-do should look like the
                // words became editable, not like a form opened on top of the
                // row. The caret is the only thing that needs to say "this is
                // live now".
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.body)
                    .foregroundStyle(Color.panelTextPrimary)
                    .focused($isEditFieldFocused)
                    .onSubmit(commitEdit)
                    // Escape abandons the edit rather than dismissing the
                    // panel. A focused field consumes Escape before the panel's
                    // own handlers see it, which is what makes this safe: the
                    // panel cannot close out from under an unsaved edit.
                    .onExitCommand(perform: cancelEdit)
                    .onChange(of: isEditFieldFocused) { _, focused in
                        // Clicking away commits. Losing the field without
                        // saving would silently throw the edit away, and there
                        // is no undo here.
                        if !focused { commitEdit() }
                    }
            } else {
                Text(entry.text)
                    .font(Theme.body)
                    .strikethrough(entry.completed, color: .panelTextSecondary)
                    .foregroundStyle(entry.completed ? Color.panelTextSecondary : Color.panelTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .contentShape(Rectangle())
                    // Double-click, the same as renaming a file. No pencil icon:
                    // the row already hides four controls behind hover, and a
                    // fifth for something this rare would cost every row width
                    // to serve the least common action.
                    .onTapGesture(count: 2, perform: beginEdit)
                    .help(onCommitEdit == nil ? "" : "Double-click to edit")
                    .accessibilityAddTraits(onCommitEdit == nil ? [] : .isButton)
            }

            Spacer(minLength: 8)

            // Reminders and colour tagging only make sense for tasks you
            // haven't finished yet -- same gate as the clock icon.
            if !entry.completed, let onSetReminder, let onCancelReminder {
                reminderControl(onSetReminder: onSetReminder, onCancelReminder: onCancelReminder)
                    .opacity(entry.reminderDate != nil || showsSecondaryControls ? 1 : 0)
            }

            if !entry.completed, let onSetColor {
                colorControl(onSetColor: onSetColor)
                    .opacity(entry.colorTag != nil || showsSecondaryControls ? 1 : 0)
            }

            Button(action: onToggleFavorite) {
                Image(systemName: entry.favorite ? "star.fill" : "star")
            }
            .buttonStyle(.ghostIcon(
                size: 12,
                restingTint: entry.favorite ? .panelStar : nil,
                hoverTint: .panelStar
            ))
            .opacity(entry.favorite || showsSecondaryControls ? 1 : 0)
            .help(entry.favorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityLabel(entry.favorite ? "Remove from favorites" : "Add to favorites")

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                // Red on hover only. A trash icon that is red at rest turns
                // every completed row into a warning; red is the confirmation
                // that you are about to destroy this specific one.
                .buttonStyle(.ghostIcon(size: 11.5, hoverTint: .panelDestructive))
                .opacity(showsSecondaryControls ? 1 : 0)
                .help("Delete")
                .accessibilityLabel("Delete")
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: Theme.rowHeight)
        // Selection and hover must not look the same. They were both
        // panelSurfaceRaised, so a row under the pointer was indistinguishable
        // from the keyboard-selected row, and a list read as having several
        // rows "already highlighted" before a key was ever pressed. Selection
        // is now a faint accent wash; hover stays neutral.
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(selectionFill)
        )
        .overlay(
            // Keyboard selection gets a hairline, not the 2pt ring a fired
            // reminder gets. Both are "look here", but one is a persistent
            // cursor the user is driving and the other is a one-off alarm; if
            // they shout equally, the alarm stops meaning anything.
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .strokeBorder(
                    themeAccent,
                    lineWidth: isHighlighted ? 2 : (isSelected ? 1 : 0)
                )
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: showsSecondaryControls)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isHighlighted)
        .accessibilityAction(named: "Edit", beginEdit)
        // A row that vanishes mid-edit (checked off, cleared, synced away)
        // would otherwise leave the field up, and committing it would write to
        // an entry that no longer exists.
        .onDisappear(perform: cancelEdit)
    }

    private func beginEdit() {
        guard onCommitEdit != nil, !isEditing else { return }
        draft = entry.text
        isEditing = true
        // Next runloop: the field does not exist yet on this pass, so focusing
        // it now is a no-op and the row would sit in edit mode with no caret.
        DispatchQueue.main.async { isEditFieldFocused = true }
    }

    /// Guarded on isEditing because two paths land here for one edit: Return
    /// fires onSubmit, which clears focus, which fires the focus change too.
    private func commitEdit() {
        guard isEditing else { return }
        isEditing = false
        isEditFieldFocused = false
        onCommitEdit?(draft)
    }

    private func cancelEdit() {
        guard isEditing else { return }
        isEditing = false
        isEditFieldFocused = false
    }

    @ViewBuilder
    private func reminderControl(onSetReminder: @escaping (TimeInterval) -> Void, onCancelReminder: @escaping () -> Void) -> some View {
        // Both states are the same plain Button — a Menu (used here previously
        // for the "pick a duration" state) has different internal chrome than
        // a Button even inside an identical outer frame, which kept shifting
        // this icon a couple points off the row's vertical center relative to
        // the star/checkbox next to it. Using a popover instead of Menu keeps
        // both states pixel-identical.
        Button {
            if entry.reminderDate != nil {
                onCancelReminder()
            } else {
                isShowingReminderPicker = true
            }
        } label: {
            Image(systemName: entry.reminderDate != nil ? "alarm.fill" : "alarm")
        }
        .buttonStyle(.ghostIcon(
            size: 12,
            restingTint: entry.reminderDate != nil ? themeAccent : nil
        ))
        .help(entry.reminderDate != nil ? "Cancel reminder" : "Remind me later")
        .accessibilityLabel(entry.reminderDate != nil ? "Cancel reminder" : "Remind me later")
        .popover(isPresented: $isShowingReminderPicker) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Self.reminderDurations, id: \.seconds) { duration in
                    Button(duration.label) {
                        onSetReminder(duration.seconds)
                        isShowingReminderPicker = false
                    }
                    .buttonStyle(.plain)
                    .font(Theme.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func colorControl(onSetColor: @escaping (TodoColorTag?) -> Void) -> some View {
        // Same shell as reminderControl (plain Button, fixed 20x20 frame,
        // .popover) so both icons stay pixel-aligned with each other and the
        // star/checkbox. Unlike the reminder icon, tapping this one always
        // opens the grid -- clearing happens by tapping the already-selected
        // swatch a second time, inside the grid itself.
        Button {
            isShowingColorPicker = true
        } label: {
            // A filled dot in the tag's own colour, rather than a paint-palette
            // glyph: the control's job is to show which colour is assigned, and
            // a swatch shows that at 12pt where an icon tinted that colour does
            // not.
            Circle()
                .fill(entry.colorTag?.color ?? Color.clear)
                .overlay(
                    Circle().strokeBorder(
                        entry.colorTag == nil ? Color.panelCheckboxRim : Color.clear,
                        lineWidth: 1.5
                    )
                )
                .frame(width: 11, height: 11)
        }
        .buttonStyle(.plain)
        .frame(width: Theme.controlHeight, height: Theme.controlHeight)
        .contentShape(Rectangle())
        .help(entry.colorTag != nil ? "Change or remove color" : "Assign a color")
        .accessibilityLabel(entry.colorTag != nil ? "Change or remove color" : "Assign a color")
        .popover(isPresented: $isShowingColorPicker) {
            ColorTagGridPicker(selected: entry.colorTag) { newTag in
                onSetColor(newTag)
                isShowingColorPicker = false
            }
        }
    }
}
