import SwiftUI

// Increment 1.7b: the pixel layer. Shapes and patterns are drawn on a pixel grid (`step`), never from bitmaps, so they
// stay sharp on any display and scale with text size. Style reference: the founder's pixel UI pack, Matrix and the
// Tesla Roadster; nothing is copied from the pack.

/// A rectangle with corners cut in pixel steps, like a pixel-art frame.
public struct PixelRect: InsettableShape {
    public var step: CGFloat
    var inset: CGFloat = 0
    public init(step: CGFloat) { self.step = step }

    public func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset), s = step
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 2 * s, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.minY + s)); p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + 2 * s)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY - 2 * s)); p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.maxY - s)); p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.maxY - s)); p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - 2 * s)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.minY + 2 * s)); p.addLine(to: CGPoint(x: r.minX + s, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.minY + s)); p.closeSubpath()
        return p
    }

    public func inset(by amount: CGFloat) -> PixelRect { var copy = self; copy.inset += amount; return copy }
}

/// A rectangle with each corner cut in its own number of pixel steps (0 = square), clockwise from the top-left.
/// `PixelRect` is this with two steps at every corner; a fill inside a frame takes one step fewer than the frame,
/// so its corners run parallel to the frame's, one pixel in (as the lit segment of `PixelSegmented` does).
public struct PixelSteppedRect: Shape {
    public var step: CGFloat
    public var corners: (topLeft: Int, topRight: Int, bottomRight: Int, bottomLeft: Int)

    public init(step: CGFloat, steps: Int) { self.init(step: step, corners: (steps, steps, steps, steps)) }
    public init(step: CGFloat, corners: (topLeft: Int, topRight: Int, bottomRight: Int, bottomLeft: Int)) {
        self.step = step
        self.corners = corners
    }

    public func path(in r: CGRect) -> Path {
        // One corner's staircase from the left edge to the top edge, in steps: (0,n), (1,n), (1,n-1), … (n,0).
        func stairs(_ n: Int) -> [(CGFloat, CGFloat)] {
            guard n > 0 else { return [(0, 0)] }
            var points: [(CGFloat, CGFloat)] = []
            for k in 0..<n { points += [(CGFloat(k), CGFloat(n - k)), (CGFloat(k + 1), CGFloat(n - k))] }
            return points + [(CGFloat(n), 0)]
        }
        let s = step
        var points: [CGPoint] = []
        points += stairs(corners.topLeft).map { CGPoint(x: r.minX + $0.0 * s, y: r.minY + $0.1 * s) }
        points += stairs(corners.topRight).reversed().map { CGPoint(x: r.maxX - $0.0 * s, y: r.minY + $0.1 * s) }
        points += stairs(corners.bottomRight).map { CGPoint(x: r.maxX - $0.0 * s, y: r.maxY - $0.1 * s) }
        points += stairs(corners.bottomLeft).reversed().map { CGPoint(x: r.minX + $0.0 * s, y: r.maxY - $0.1 * s) }
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        return p
    }
}

/// A segmented "health bar": filled blocks in the state's colour with a lit top edge; stale data is dithered
/// (a checkerboard, the non-colour cue for hatched); no value draws the frame in the state's colour over empty blocks.
///
/// Founder review (19 Oct 2026): the fill follows the frame's pixel pattern. The lit run and the empty run are each a
/// block whose corners step one pixel in from the frame's (`PixelSteppedRect`), so a one-pixel gap of background runs
/// all the way round, corners included, and the fill reads as part of the frame rather than a rectangle laid on it.
/// Every edge sits on a whole point, so nothing is anti-aliased at 1× or 2×.
public struct PixelBar: View {
    let fraction: Double?
    let role: ColorToken
    let pattern: FillPattern
    let segments: Int
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(fraction: Double?, role: ColorToken, pattern: FillPattern, segments: Int = 24) {
        self.fraction = fraction
        self.role = role
        self.pattern = pattern
        self.segments = segments
    }

    public var body: some View {
        let px = theme.stroke(.hairline) * 2
        Canvas { context, size in
            let frame = CGRect(origin: .zero, size: size)
            let outlined = fraction == nil || pattern == .outline || pattern == .dashed
            context.fill(PixelRect(step: px).path(in: frame), with: .color(theme.color(outlined ? role : .separator, scheme)))
            context.fill(PixelRect(step: px).path(in: frame.insetBy(dx: px, dy: px)), with: .color(theme.color(.background, scheme)))
            let layout = Self.layout(width: size.width, height: size.height, px: px, segments: segments, fraction: fraction)
            if let empty = layout.empty {
                Self.drawRun(&context, empty, cells: layout.cells[layout.lit...], px: px) { layer, _ in
                    layer.fill(Path(empty.rect), with: .color(theme.color(.surfaceMuted, scheme)))
                }
            }
            if let lit = layout.litRun {
                let color = theme.color(role, scheme)
                Self.drawRun(&context, lit, cells: layout.cells[..<layout.lit], px: px) { layer, shape in
                    if pattern == .hatched {              // dither: every other pixel, on one grid across the segments
                        var y = lit.rect.minY, row = 0
                        while y < lit.rect.maxY {
                            var x = layout.inner.minX + (row % 2 == 0 ? 0 : px)
                            while x < lit.rect.maxX { layer.fill(Path(CGRect(x: x, y: y, width: px, height: px)), with: .color(color)); x += px * 2 }
                            y += px; row += 1
                        }
                    } else {                              // solid, and a lit top edge that follows the stepped corners
                        layer.fill(Path(lit.rect), with: .color(color))
                        var edge = shape
                        edge.addPath(shape.offsetBy(dx: 0, dy: px))
                        layer.fill(edge, with: .color(theme.color(.textPrimary, scheme).opacity(0.35)), style: FillStyle(eoFill: true))
                    }
                }
            }
        }
        .frame(height: theme.spacing(.standard) + theme.spacing(.compact) * 2)
        .accessibilityHidden(true)
    }

    /// A run of segments drawn as one stepped block: `rect` is its bounding box, `steps` its corner cut.
    struct Run: Equatable {
        let rect: CGRect
        let steps: Int
    }

    /// Where everything goes, in whole points (pure, so tests can check the grid): the area inside the frame, each
    /// segment's cell, how many are lit, and the lit and empty runs (nil when there is none).
    struct Layout {
        let inner: CGRect
        let cells: [CGRect]
        let lit: Int
        let litRun: Run?
        let empty: Run?
    }

    nonisolated static func layout(width: CGFloat, height: CGFloat, px: CGFloat, segments: Int, fraction: Double?) -> Layout {
        let inner = CGRect(x: px * 2, y: px * 2, width: max(0, width - px * 4), height: max(0, height - px * 4))
        let count = max(1, segments)
        // Segment edges on whole points: segment i spans [start(i), start(i+1) - gap); the last one ends exactly at the
        // frame's inner edge (the frame itself is pixel-aligned by layout).
        let pitch = (inner.width + px) / CGFloat(count)
        func start(_ i: Int) -> CGFloat { inner.minX + (CGFloat(i) * pitch).rounded() }
        func end(_ i: Int) -> CGFloat { i == count - 1 ? inner.maxX : start(i + 1) - px }
        let cells = (0..<count).map { i in CGRect(x: start(i), y: inner.minY, width: max(0, end(i) - start(i)), height: inner.height) }
        let lit = fraction.map { min(count, Int((min(max($0, 0), 1) * Double(count)).rounded(.up))) } ?? 0
        // One step in from the frame's two, when the run is wide and tall enough to show it.
        func run(_ range: Range<Int>) -> Run? {
            guard !range.isEmpty else { return nil }
            let first = cells[range.lowerBound], last = cells[range.upperBound - 1]
            let rect = CGRect(x: first.minX, y: inner.minY, width: last.maxX - first.minX, height: inner.height)
            return Run(rect: rect, steps: rect.width >= px * 3 && rect.height >= px * 3 ? 1 : 0)
        }
        return Layout(inner: inner, cells: cells, lit: lit, litRun: run(0..<lit), empty: run(lit..<count))
    }

    /// Clips to the run's stepped block and to its segments (the gaps), then lets `body` paint inside.
    static func drawRun(_ context: inout GraphicsContext, _ run: Run, cells: ArraySlice<CGRect>, px: CGFloat,
                        _ body: (inout GraphicsContext, Path) -> Void) {
        let shape = PixelSteppedRect(step: px, steps: run.steps).path(in: run.rect)
        var segments = Path()
        for cell in cells { segments.addRect(cell) }
        context.drawLayer { layer in
            layer.clip(to: shape)
            layer.clip(to: segments)
            body(&layer, shape)
        }
    }
}

/// A pixel frame panel: outer border, inner rule, and a glass or solid fill behind the content.
public struct PixelPanel<Content: View>: View {
    let glass: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(glass: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.glass = glass
        self.content = content
    }

    public var body: some View {
        let px = theme.stroke(.hairline) * 2
        content()
            .padding(theme.spacing(.windowPadding))
            .background {
                if glass {
                    PixelRect(step: px).fill(.ultraThinMaterial)
                    PixelRect(step: px).fill(theme.color(.surfaceElevated, scheme).opacity(0.72))
                } else {
                    PixelRect(step: px).fill(theme.color(.surfaceElevated, scheme))
                }
            }
            .overlay(PixelRect(step: px).strokeBorder(theme.color(.separator, scheme), lineWidth: px))
            .overlay(PixelRect(step: px).inset(by: px * 2).strokeBorder(theme.color(.accent, scheme).opacity(0.35), lineWidth: px / 2))
    }
}

/// Item 9: the keyboard focus indicator of every control the app draws itself: a pixel frame in the accent colour,
/// two focus strokes outside the control, so it never hides the control's own frame or reads as its selected state.
/// Drawn only while the control holds keyboard focus (System Settings › Keyboard › Keyboard navigation).
public struct PixelFocusRing: ViewModifier {
    let focused: Bool
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    public init(focused: Bool) { self.focused = focused }

    public func body(content: Content) -> some View {
        content.overlay {
            if focused {
                PixelRect(step: theme.stroke(.hairline) * 2).inset(by: -theme.stroke(.focus) * 2)
                    .strokeBorder(theme.color(.accent, scheme), lineWidth: theme.stroke(.focus))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .transformPreference(PixelFocusRingCount.self) { $0 += focused ? 1 : 0 }
    }
}

/// How many pixel focus rings a view tree draws right now. The focus-gallery probe checks it is exactly one while a
/// self-drawn control holds focus (a style whose focus signal never turns true draws none).
public struct PixelFocusRingCount: PreferenceKey {
    public static let defaultValue = 0
    public static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

extension View {
    /// Draws `PixelFocusRing` while `focused`.
    public func pixelFocusRing(_ focused: Bool) -> some View { modifier(PixelFocusRing(focused: focused)) }
}

extension EnvironmentValues {
    /// Item 9: whether the pixel-styled button around this view holds keyboard focus, set by `PixelFocusTracked`.
    /// The button styles read this, not `isFocused`: on macOS `isFocused` stays false inside a `ButtonStyle` body even
    /// while the button holds focus (the focus-gallery probe showed it: focused, yet no ring drawn).
    @Entry public var pixelButtonFocused: Bool = false
}

/// Item 9: how every pixel button style builds its button: a real `Button` from the primitive configuration (so
/// VoiceOver's press, Space, and the caller's keyboard shortcut and role all stay the system's), wearing `face`, with
/// its keyboard focus tracked through `@FocusState` and handed to the face as `pixelButtonFocused`. The system's
/// rounded ring is turned off here, and only here, because the face draws the pixel ring from that signal.
struct PixelFocusTracked<Face: ButtonStyle>: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let face: Face
    @FocusState private var focused: Bool

    var body: some View {
        Button(configuration)
            .buttonStyle(face)
            .focused($focused)
            .focusEffectDisabled()                       // the pixel ring instead of the system's rounded one
            .environment(\.pixelButtonFocused, focused)
    }
}

/// Item 9: the style for a button whose label draws itself (sidebar rows, limit cards, chips, swatches, segments):
/// no chrome of its own, a dimmed label while pressed (callers dim a disabled label themselves, as with `.plain`),
/// and the pixel focus ring. Use it instead of
/// `.plain`, which draws no focus indicator of the app's own (`scripts/ci.sh` checks).
public struct PixelPlainButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { PixelFocusTracked(configuration: configuration, face: Face()) }

    struct Face: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { PlainBody(configuration: configuration) }
    }

    struct PlainBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.pixelButtonFocused) private var focused
        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.75 : 1)
                .pixelFocusRing(focused)
        }
    }
}

/// Bevelled pixel button: a lit top-left edge and a shaded bottom-right edge that swap when pressed.
public struct PixelButtonStyle: PrimitiveButtonStyle {
    public var prominent: Bool
    /// 1.15: an irreversible action (Delete All): the blocked colour as the face, so it never looks like the safe choice.
    public var destructive: Bool
    public init(prominent: Bool = false, destructive: Bool = false) {
        self.prominent = prominent
        self.destructive = destructive
    }

    public func makeBody(configuration: Configuration) -> some View {
        PixelFocusTracked(configuration: configuration, face: Face(prominent: prominent, destructive: destructive))
    }

    struct Face: ButtonStyle {
        let prominent: Bool
        let destructive: Bool
        func makeBody(configuration: Configuration) -> some View {
            PixelButtonBody(configuration: configuration, prominent: prominent, destructive: destructive)
        }
    }

    struct PixelButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let destructive: Bool
        @Environment(\.theme) private var theme
        @Environment(\.colorScheme) private var scheme
        @Environment(\.isEnabled) private var enabled
        @Environment(\.pixelButtonFocused) private var focused

        var body: some View {
            let px = theme.stroke(.hairline) * 2
            let pressed = configuration.isPressed
            let filled = prominent || destructive
            let face = destructive ? theme.color(.statusBlocked, scheme) : prominent ? theme.color(.accent, scheme) : theme.color(.surfaceMuted, scheme)
            configuration.label
                .font(theme.font(.title))
                .textCase(.uppercase)
                .foregroundStyle(filled ? theme.color(.background, scheme) : theme.color(.textPrimary, scheme))
                .padding(.horizontal, theme.spacing(.windowPadding))
                .padding(.vertical, theme.spacing(.compact) + px)
                .background(PixelRect(step: px).fill(face))
                .overlay(alignment: .top) {
                    Rectangle().fill(theme.color(.textPrimary, scheme).opacity(pressed ? 0.05 : 0.30)).frame(height: px)
                        .padding(.horizontal, px * 2).padding(.top, px)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.color(.background, scheme).opacity(pressed ? 0.05 : 0.55)).frame(height: px)
                        .padding(.horizontal, px * 2).padding(.bottom, px)
                }
                .overlay(PixelRect(step: px).strokeBorder(theme.color(.separator, scheme), lineWidth: px))
                .offset(y: pressed ? px / 2 : 0)
                .opacity(enabled ? 1 : 0.45)
                .contentShape(PixelRect(step: px))
                .pixelFocusRing(focused)
        }
    }
}
