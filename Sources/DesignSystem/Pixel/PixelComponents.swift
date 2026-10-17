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

/// A segmented "health bar": filled blocks in the state's colour with a lit top edge; stale data is dithered
/// (a checkerboard, the non-colour cue for hatched); no value draws only the empty frame.
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
            context.fill(PixelRect(step: px).path(in: frame), with: .color(theme.color(.separator, scheme)))
            context.fill(PixelRect(step: px).path(in: frame.insetBy(dx: px, dy: px)), with: .color(theme.color(.background, scheme)))
            let inner = frame.insetBy(dx: px * 2, dy: px * 2)
            let gap = px
            let width = (inner.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
            let lit = fraction.map { Int((min(max($0, 0), 1) * Double(segments)).rounded(.up)) } ?? 0
            for i in 0..<segments {
                let cell = CGRect(x: inner.minX + CGFloat(i) * (width + gap), y: inner.minY, width: width, height: inner.height)
                guard i < lit else {
                    context.fill(Path(cell), with: .color(theme.color(.surfaceMuted, scheme)))
                    continue
                }
                let color = theme.color(role, scheme)
                if pattern == .hatched {                      // dither: every other pixel
                    var y = cell.minY, row = 0
                    while y < cell.maxY {
                        var x = cell.minX + (row % 2 == 0 ? 0 : px)
                        while x < cell.maxX { context.fill(Path(CGRect(x: x, y: y, width: px, height: px)), with: .color(color)); x += px * 2 }
                        y += px; row += 1
                    }
                } else {
                    context.fill(Path(cell), with: .color(color))
                    context.fill(Path(CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: px)), with: .color(.white.opacity(0.35)))
                }
            }
            if fraction == nil || pattern == .outline || pattern == .dashed {
                context.stroke(PixelRect(step: px).path(in: frame.insetBy(dx: px / 2, dy: px / 2)), with: .color(theme.color(role, scheme)), lineWidth: px / 2)
            }
        }
        .frame(height: theme.spacing(.standard) + theme.spacing(.compact) * 2)
        .accessibilityHidden(true)
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

/// Bevelled pixel button: a lit top-left edge and a shaded bottom-right edge that swap when pressed.
public struct PixelButtonStyle: ButtonStyle {
    public var prominent: Bool
    public init(prominent: Bool = false) { self.prominent = prominent }

    public func makeBody(configuration: Configuration) -> some View { PixelButtonBody(configuration: configuration, prominent: prominent) }

    struct PixelButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.theme) private var theme
        @Environment(\.colorScheme) private var scheme
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let px = theme.stroke(.hairline) * 2
            let pressed = configuration.isPressed
            let face = prominent ? theme.color(.accent, scheme) : theme.color(.surfaceMuted, scheme)
            configuration.label
                .font(theme.font(.title))
                .textCase(.uppercase)
                .foregroundStyle(prominent ? theme.color(.background, scheme) : theme.color(.textPrimary, scheme))
                .padding(.horizontal, theme.spacing(.windowPadding))
                .padding(.vertical, theme.spacing(.compact) + px)
                .background(PixelRect(step: px).fill(face))
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(pressed ? 0.05 : 0.30)).frame(height: px).padding(.horizontal, px * 2).padding(.top, px) }
                .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(pressed ? 0.05 : 0.45)).frame(height: px).padding(.horizontal, px * 2).padding(.bottom, px) }
                .overlay(PixelRect(step: px).strokeBorder(theme.color(.separator, scheme), lineWidth: px))
                .offset(y: pressed ? px / 2 : 0)
                .opacity(enabled ? 1 : 0.45)
                .contentShape(PixelRect(step: px))
        }
    }
}
