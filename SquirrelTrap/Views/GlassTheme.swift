import SwiftUI

/// The panel's design tokens.
///
/// This used to be a frosted-blue-glass theme that forced the whole panel into
/// `vibrantDark` and painted every row as a tinted translucent card. Two things
/// were wrong with that. The tint meant blue was carrying checkbox, star, gear,
/// trash, alarm, palette and every row background at once — when everything is
/// the accent colour, nothing reads as the accent colour. And a per-row card
/// puts a border around each line of a list whose items are already separated
/// by being on their own line, so the chrome competed with the content.
///
/// The replacement follows the system appearance and spends its contrast budget
/// on type instead of on surfaces: one quiet card, flat rows, hairline rules,
/// and blue reserved for the checkbox and genuinely primary actions.
enum Theme {
    // MARK: Type
    //
    // Four sizes, each with one job. Anything that needs a fifth size is
    // usually a hierarchy problem rather than a type problem.

    /// Panel title and the text field the whole app exists to serve.
    static let title = Font.system(size: 15, weight: .semibold)
    /// To-do text, favourites, anything that is the content itself.
    static let body = Font.system(size: 13.5)
    /// The same size in medium, for the input field's typed text.
    static let bodyMedium = Font.system(size: 13.5, weight: .medium)
    /// Counts, status lines, helper copy, footer controls.
    static let secondary = Font.system(size: 12)
    /// "Completed", and any other group label. Deliberately the same size as
    /// `secondary` rather than a fifth step: it separates itself by weight and
    /// uppercasing, and an 11 next to an 11.5 is not a hierarchy, it is two
    /// sizes that look like a mistake.
    static let sectionHeader = Font.system(size: 12, weight: .semibold)

    // MARK: Metrics
    //
    // A 4pt grid. Row height is the one number that matters most: at 32 the
    // list reads as a dense table, at 40 it reads as a settings screen. 34 is
    // where it reads as a list of things you actually intend to do.

    static let gutter: CGFloat = 20
    static let rowHeight: CGFloat = 34
    /// Hit area for the small icon buttons, and the uniform height every footer
    /// control is laid out at so they share one centre line. The glyphs inside
    /// are 12 to 14pt, but a 12pt click target is a 12pt click target no matter
    /// how big the icon looks; the frame is what the pointer has to find.
    static let controlHeight: CGFloat = 26

    /// Total height of the footer strip, including the space above and below
    /// its controls. Stated as one number rather than as vertical padding
    /// around an intrinsically-sized row: padding leaves the actual strip
    /// height at the mercy of whichever child happens to be tallest.
    static let footerHeight: CGFloat = 46

    /// The footer's controls are NOT centred in that strip. They sit 2pt above
    /// centre, and the asymmetry is the point.
    ///
    /// The strip is bounded above by a hard, high-contrast hairline and below
    /// by the card's own soft rounded edge. A hard edge reads as nearer than a
    /// soft one at the same distance, so a mathematically centred row looks
    /// top-heavy. Measured centring here was confirmed exact (10.0pt above,
    /// 10.0pt below) while still reading as wrong, which is the signature of an
    /// optical problem rather than a layout one.
    ///
    /// Do not "fix" these back to equal values. If the hairline is ever
    /// removed, they should go back to equal in the same change.
    static let footerPaddingTop: CGFloat = 9
    static let footerPaddingBottom: CGFloat = 11

    /// The footer's horizontal padding is likewise reduced rather than set to
    /// `gutter`, for the same reason and on the same principle.
    ///
    /// Its controls carry a 26pt hit frame around a ~13.5pt glyph, so the glyph
    /// sits about 6pt inside its own box. Padded to the standard gutter, the
    /// leading gear would start 26pt from the card edge while the checkboxes,
    /// the counts line and the text field above it all start at 20. What the
    /// eye aligns is the glyph, not the invisible frame around it.
    ///
    /// The trailing side is offset by less because the last control is a text
    /// label carrying only its own 4pt padding, not a square hit frame.
    static let footerPaddingLeading: CGFloat = gutter - 6
    static let footerPaddingTrailing: CGFloat = gutter - 4
    static let rowRadius: CGFloat = 6
    static let cardRadius: CGFloat = 12
    static let checkboxSize: CGFloat = 16
    /// Gap between the checkbox and the to-do text. Also the inset the
    /// separators start at, so rules line up with the text column rather than
    /// cutting under the checkboxes.
    static let checkboxGap: CGFloat = 10
    static var textColumnInset: CGFloat { checkboxSize + checkboxGap }
}

/// Builds a colour that resolves differently in light and dark. Every panel
/// colour goes through here rather than being a single fixed value, which is
/// what let the old theme get away with forcing a dark appearance: it only
/// ever had one set of values to show.
private func dynamicColor(light: (Int, Int, Int, Double), dark: (Int, Int, Int, Double)) -> Color {
    func make(_ c: (Int, Int, Int, Double)) -> NSColor {
        NSColor(
            srgbRed: CGFloat(c.0) / 255,
            green: CGFloat(c.1) / 255,
            blue: CGFloat(c.2) / 255,
            alpha: CGFloat(c.3)
        )
    }
    let lightColor = make(light)
    let darkColor = make(dark)
    return Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
    })
}

extension Color {
    // MARK: Text
    //
    // These map onto the system label colours rather than white-at-an-opacity,
    // so they track the user's appearance, increase-contrast and
    // reduce-transparency settings for free.

    /// Headlines, item text, anything that should read as the main content.
    static let panelTextPrimary = Color(nsColor: .labelColor)
    /// Captions, section labels, explainer text — present but de-emphasised.
    static let panelTextSecondary = Color(nsColor: .secondaryLabelColor)
    /// Resting-state icons, empty-state copy — present but barely.
    static let panelTertiary = Color(nsColor: .tertiaryLabelColor)

    // MARK: Surfaces

    /// The card itself, used when translucency is off. When it's on, this is
    /// the tint laid over the blur rather than the whole background.
    ///
    /// Not pure white and not a pure grey: both are cooled a few points toward
    /// the accent's blue. At this chroma nobody can name the colour, but an
    /// untinted `#FFFFFF` panel sitting on a tinted macOS desktop reads as a
    /// surface nobody chose.
    static let panelSurface = dynamicColor(
        light: (252, 253, 255, 1),
        dark: (29, 30, 34, 1)
    )

    /// Row hover, and the input field's resting fill. Deliberately close to the
    /// surface — a hover state that announces itself is a hover state you stop
    /// noticing.
    static let panelSurfaceRaised = dynamicColor(
        light: (16, 40, 78, 0.05),
        dark: (188, 208, 240, 0.08)
    )

    /// Hairline rules between rows.
    static let panelSeparator = dynamicColor(
        light: (16, 40, 78, 0.10),
        dark: (188, 208, 240, 0.12)
    )

    /// The unchecked checkbox's rim. Light enough to read as "not done yet"
    /// without drawing the eye the way a filled shape would.
    static let panelCheckboxRim = dynamicColor(
        light: (16, 40, 78, 0.26),
        dark: (188, 208, 240, 0.34)
    )

    /// Destructive actions only — delete, and nothing else.
    static let panelDestructive = dynamicColor(
        light: (215, 58, 62, 1),
        dark: (255, 105, 97, 1)
    )

    /// Favourite stars, once they're actually on.
    static let panelStar = dynamicColor(
        light: (240, 168, 40, 1),
        dark: (255, 190, 70, 1)
    )
}

/// A quiet neutral surface: used for the text field, popovers, and grouped
/// controls in Preferences. Replaces the old tinted-glass card, so anything
/// still calling `.glassCard()` picks up the new look without changing.
struct PanelSurface: ViewModifier {
    var cornerRadius: CGFloat = 8
    /// A colour-tagged to-do passes its tag here to get a hairline of that
    /// colour instead of the default neutral one. The tag tints the *edge*,
    /// not the fill, so sixteen possible tags can't turn the list into a
    /// paint chart.
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.panelSurfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tint ?? Color.panelSeparator, lineWidth: 1)
            )
    }
}

extension View {
    func panelSurface(cornerRadius: CGFloat = 8, tint: Color? = nil) -> some View {
        modifier(PanelSurface(cornerRadius: cornerRadius, tint: tint))
    }

    /// Retained so the Preferences screens keep compiling while they migrate;
    /// it now draws the neutral surface above rather than blue glass.
    func glassCard(cornerRadius: CGFloat = 8, tint: Color = .clear) -> some View {
        modifier(PanelSurface(cornerRadius: cornerRadius, tint: tint == .clear ? nil : tint))
    }
}

extension View {
    /// Debug-only: logs this view's resolved rect in the panel's own coordinate
    /// space. Layout questions like "is the space above these controls equal to
    /// the space below them" are answerable exactly, and guessing at them from a
    /// screenshot wastes far more time than measuring once.
    func measureFrame(_ label: String) -> some View {
        #if DEBUG
        return background(
            GeometryReader { proxy in
                Color.clear.onAppear {
                    let rect = proxy.frame(in: .named("panel"))
                    // Written straight to stderr rather than via debugLog:
                    // this file is a member of the widget extension target too,
                    // and DebugLog.swift is not.
                    let line = String(
                        format: "Squirrel Trap DEBUG: [measure] %@ y=%.1f h=%.1f (bottom=%.1f)\n",
                        label, rect.minY, rect.height, rect.maxY
                    )
                    FileHandle.standardError.write(Data(line.utf8))
                }
            }
        )
        #else
        return self
        #endif
    }
}

/// A thin, rounded, trackless scroller.
///
/// macOS's own overlay scroller is close to right but still draws a slot behind
/// the knob and sizes the knob for a document window. On a 440pt panel whose
/// whole argument is that chrome should recede, the indicator should be a hint
/// at the edge of the list and nothing more: a rounded pill, no track, no
/// arrows, and a colour that resolves against the current appearance rather
/// than a fixed grey.
final class PanelScroller: NSScroller {
    /// Width of the knob itself, not the control. The control stays wider so
    /// the knob remains comfortable to grab, since a 5pt hit target is a 5pt
    /// hit target however pretty it looks.
    private let knobThickness: CGFloat = 5
    private let edgeInset: CGFloat = 3

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        11
    }

    /// Nothing behind the knob. The slot is the part that reads as a control
    /// rather than an indicator, and the card behind it is a better ground than
    /// anything that could be drawn here.
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let frame = rect(for: .knob)
        guard frame.height > 0 || frame.width > 0 else { return }

        let knobRect: NSRect
        switch (frame.width > frame.height) {
        case false:
            knobRect = NSRect(
                x: frame.midX - knobThickness / 2 - edgeInset / 2,
                y: frame.minY,
                width: knobThickness,
                height: frame.height
            )
        case true:
            knobRect = NSRect(
                x: frame.minX,
                y: frame.midY - knobThickness / 2 - edgeInset / 2,
                width: frame.width,
                height: knobThickness
            )
        }

        // Tracks the appearance the panel is actually being drawn in, so the
        // knob stays visible on a light card and doesn't glare on a dark one.
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let alpha: CGFloat = isDark ? 0.32 : 0.26
        (isDark ? NSColor.white : NSColor.black).withAlphaComponent(alpha).setFill()

        NSBezierPath(
            roundedRect: knobRect,
            xRadius: knobThickness / 2,
            yRadius: knobThickness / 2
        ).fill()
    }
}

/// Forces the enclosing scroll view to macOS's overlay scroller style.
///
/// SwiftUI's `ScrollView` is an `NSScrollView`, and by default it honours
/// System Settings > Appearance > Show scroll bars. Set to "Always", that gives
/// a legacy scroller: a permanent, wide, opaque gutter that takes real layout
/// width away from the list and reads as a control rather than as an indicator.
/// On a 440pt panel that is a lot of surface spent on something the user is not
/// looking at.
///
/// Overlay scrollers float above the content, are much thinner, and fade out
/// when idle. That is the behaviour worth having here, so it is set explicitly
/// rather than left to a global preference this app has no say in.
///
/// This is the native equivalent of what a web project would reach for
/// OverlayScrollbars to get; there is no webview anywhere in this app.
private struct OverlayScrollerStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        // A zero-size probe. It exists only to reach its own enclosing
        // NSScrollView, which SwiftUI does not otherwise expose.
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Deferred: at update time the view is not yet in the window's
        // hierarchy, so enclosingScrollView is still nil.
        DispatchQueue.main.async {
            guard let scrollView = nsView.enclosingScrollView else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasHorizontalScroller = false
            // Draws no background of its own, so the scroller has nothing
            // behind it but the card.
            scrollView.drawsBackground = false
            // Swapped in once. Reassigning on every SwiftUI update would drop
            // the live scroller mid-drag and cancel the gesture.
            if !(scrollView.verticalScroller is PanelScroller) {
                scrollView.verticalScroller = PanelScroller()
            }
        }
    }
}

extension View {
    /// Applies macOS's overlay scroller style to the enclosing ScrollView.
    /// Attach to the ScrollView's content, not to the ScrollView itself.
    func overlayScrollers() -> some View {
        background(OverlayScrollerStyler().frame(width: 0, height: 0))
    }
}

/// The one interaction vocabulary for every small icon button on the surface:
/// footer controls, row controls, back chevrons.
///
/// No fill and no outline at rest. Hovering brightens the glyph from secondary
/// to primary; pressing dims and shrinks it very slightly. Previously these
/// were bare `Image`s inside `.buttonStyle(.plain)`, which meant they had no
/// hover state and no pressed state at all: you could click one and get no
/// acknowledgement that anything had been hit.
struct GhostIconButtonStyle: ButtonStyle {
    var size: CGFloat = 13.5
    /// Set when the control is currently *on* (a favourited star, a set alarm)
    /// so its resting colour states that, instead of the neutral tertiary. The
    /// style owns `foregroundStyle`, so a caller applying its own outside the
    /// style would simply be overridden; this is the way in.
    var restingTint: Color?
    /// Set for destructive controls so the hover state resolves red rather than
    /// simply darker.
    var hoverTint: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size))
            .foregroundStyle(resolvedColor)
            .frame(width: Theme.controlHeight, height: Theme.controlHeight)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .onHover { isHovering = $0 }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }

    private var resolvedColor: Color {
        guard isHovering else { return restingTint ?? .panelTertiary }
        return hoverTint ?? .panelTextPrimary
    }
}

extension ButtonStyle where Self == GhostIconButtonStyle {
    static var ghostIcon: GhostIconButtonStyle { GhostIconButtonStyle() }

    static func ghostIcon(
        size: CGFloat = 13.5,
        restingTint: Color? = nil,
        hoverTint: Color? = nil
    ) -> GhostIconButtonStyle {
        GhostIconButtonStyle(size: size, restingTint: restingTint, hoverTint: hoverTint)
    }
}

/// The list's checkbox. A rounded square rather than a circle: a circle reads
/// as a radio button (pick one of these), a rounded square reads as a checkbox
/// (each of these is independently done or not), which is what this list is.
struct Checkbox: View {
    let isChecked: Bool
    /// A colour-tagged item checks off in its own colour instead of blue.
    var tint: Color = .accentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .stroke(Color.panelCheckboxRim, lineWidth: 1.5)
                .opacity(isChecked ? 0 : 1)

            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(tint)
                .opacity(isChecked ? 1 : 0)
                .scaleEffect(isChecked ? 1 : 0.6)

            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .opacity(isChecked ? 1 : 0)
        }
        .frame(width: Theme.checkboxSize, height: Theme.checkboxSize)
        // Ease-out, not a springy overshoot. A box this small that scales past
        // its own bounds and settles back reads as wobble rather than as
        // confidence, and overshoot on a confirmation is the one place it is
        // least welcome: the user wants to know it took, not to watch it.
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: isChecked
        )
    }
}
