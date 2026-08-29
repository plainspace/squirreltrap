import SwiftUI

/// Wraps IntentRowView with a drag handle for reordering, without touching
/// IntentRowView itself — only the handle carries `.draggable`, so the
/// checkbox/star/reminder/delete buttons inside IntentRowView keep working
/// with no gesture conflicts.
struct PendingRowView: View {
    let entry: IntentEntry
    let themeAccent: Color
    var isHighlighted: Bool = false
    var isSelected: Bool = false
    let onToggleCompleted: () -> Void
    let onToggleFavorite: () -> Void
    let onSetReminder: (TimeInterval) -> Void
    let onCancelReminder: () -> Void
    let onSetColor: (TodoColorTag?) -> Void
    let onDelete: () -> Void
    let onCommitEdit: (String) -> Void
    let onDrop: (UUID) -> Void
    var onDragHandleHoverChanged: (Bool) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isDropTargeted = false
    // Completion-animation state -- see startCompletionAnimation(). Purely
    // visual, not persisted. `isChecking` fills the checkbox, `isCompleting`
    // collapses the row; they fire in that order, a beat apart.
    @State private var isChecking = false
    @State private var isCompleting = false

    var body: some View {
        HStack(spacing: 2) {
            IntentRowView(
                entry: entry,
                themeAccent: themeAccent,
                isHighlighted: isHighlighted || isDropTargeted,
                isSelected: isSelected,
                forceChecked: isChecking,
                onToggleCompleted: startCompletionAnimation,
                onToggleFavorite: onToggleFavorite,
                onSetReminder: onSetReminder,
                onCancelReminder: onCancelReminder,
                onSetColor: onSetColor,
                onDelete: onDelete,
                onCommitEdit: onCommitEdit
            )

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(Color.panelTertiary)
                .frame(width: 16, height: Theme.rowHeight)
                .contentShape(Rectangle())
                // Only visible while the pointer is on the row. A grip that is
                // always drawn turns a list into a table of controls; one that
                // appears where the hand already is costs nothing at rest.
                // Deliberately not shown for keyboard selection: dragging is
                // the one thing on this row a keyboard cannot do.
                .opacity(isHovering ? 1 : 0)
                // The panel is otherwise movable by clicking/dragging its
                // background (isMovableByWindowBackground) -- a plain Image
                // isn't an AppKit "control", so without this a click-drag on
                // the handle was being claimed by that window-move behavior
                // instead of starting the item drag below. Disabling it while
                // hovering the handle (before mouseDown) lets .draggable win.
                .onHover { hovering in onDragHandleHoverChanged(hovering) }
                .draggable(entry.id.uuidString) {
                    // Explicit width matters: without it, a preview dragged from
                    // this small handle rendered as just the system drag-operation
                    // badge with no visible content at all.
                    HStack(spacing: Theme.checkboxGap) {
                        Checkbox(isChecked: false, tint: entry.colorTag?.color ?? themeAccent)
                        Text(entry.text)
                            .font(Theme.body)
                            .foregroundStyle(Color.panelTextPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 380, height: Theme.rowHeight, alignment: .leading)
                    .panelSurface(cornerRadius: Theme.rowRadius)
                }
        }
        // Collapsing the row's own height is what makes the items below slide
        // up to meet it, rather than the row vanishing and leaving a gap that
        // snaps shut a frame later.
        .frame(height: isCompleting ? 0 : nil)
        .opacity(isCompleting ? 0 : 1)
        .clipped()
        .onHover { isHovering = $0 }
        // Both flags describe a completion that is currently playing, so they
        // must not outlive it. An entry that is checked off and later unchecked
        // comes back into this list, and SwiftUI may hand it the same view
        // state it had on the way out: forceChecked still true, drawing a
        // checked box on an entry whose `completed` is false, or isCompleting
        // still true, collapsing the row to zero height so it never reappears.
        .onAppear {
            isChecking = false
            isCompleting = false
        }
        .onChange(of: entry.completed) { _, _ in
            isChecking = false
            isCompleting = false
        }
        .dropDestination(for: String.self) { items, _ in
            guard let draggedIDString = items.first, let draggedID = UUID(uuidString: draggedIDString) else { return false }
            onDrop(draggedID)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    /// Checking something off is the one moment the app exists for, so it gets
    /// a beat rather than an instant swap: the checkbox fills (that animation
    /// lives on `Checkbox` itself), the row holds long enough to actually read
    /// as *checked*, and only then collapses out of the pending list. The real
    /// `onToggleCompleted()` fires last, so the structural move from the
    /// pending list to the completed one happens with nothing left on screen
    /// to jump.
    ///
    /// This replaces a shrink-to-1%-scale plus a 💨 emoji puff. Scaling a row
    /// to a point drags the eye toward the vanishing centre, and the emoji
    /// rendered at whatever weight the system font had — neither survives
    /// being looked at twice.
    private func startCompletionAnimation() {
        // The real toggle is deferred by roughly 0.6s so the checkbox fill can
        // be seen. A second click inside that window used to schedule a second
        // toggle, and two toggles land back where they started: the row moved
        // out and back, and the checkbox appeared not to have changed at all.
        guard !isChecking else { return }

        guard !reduceMotion else {
            onToggleCompleted()
            return
        }

        let hold = celebrationDuration * 0.45
        let collapse = celebrationDuration * 0.35

        isChecking = true

        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            withAnimation(.easeInOut(duration: collapse)) {
                isCompleting = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + collapse) {
                onToggleCompleted()
            }
        }
    }
}
