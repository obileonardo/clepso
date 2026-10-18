import SwiftUI

/// Pulse's icon set (increment 1.13): every icon drawn on a 12×12 pixel grid, so icons match the pixel type and panels
/// instead of the system's smooth symbols. A glyph is a Shape, so it takes the surrounding foreground colour.
public enum PixelGlyph: String, CaseIterable, Sendable {
    case home, gauge, terminal, calendar, people, card, target, person, gear, power, percent, bell, link, dollar, bars, export, demo, trash, pulse, envelope, chevronLeft, chevronRight, info, warning, checkSquare, xSquare, dashedSquare, flame, cursor, flag, code, circle, circleAlert, circleAlertFill, nosign, reset, checkCircle, minusCircle, ellipsisCircle, linkPlus, boltSlash, live, clock, clockAlert, seal, personCheck, question, bubble, trend, arrowCCW, halfCircle, key, chevronBack, palette, external, grid, refresh, square

    /// For call sites written with SF Symbol names; unknown names fall back to a question mark (a test keeps the map complete).
    public init(symbol: String) { self = Self.symbols[symbol] ?? .question }

    public var rows: [String] { Self.bitmaps[self] ?? [] }
}

/// The glyph as a shape: one square per lit pixel.
public struct PixelGlyphShape: Shape {
    public let glyph: PixelGlyph
    public init(_ glyph: PixelGlyph) { self.glyph = glyph }

    public func path(in rect: CGRect) -> Path {
        let rows = glyph.rows
        let n = CGFloat(max(1, rows.count))
        let unit = min(rect.width, rect.height) / n
        let origin = CGPoint(x: rect.midX - unit * n / 2, y: rect.midY - unit * n / 2)
        var path = Path()
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch == "#" {
                path.addRect(CGRect(x: origin.x + CGFloat(x) * unit, y: origin.y + CGFloat(y) * unit, width: unit, height: unit))
            }
        }
        return path
    }
}

/// A pixel icon at a size that keeps every pixel on whole device pixels (multiples of 6 pt: 12, 18, 24).
public struct PixelIcon: View {
    let glyph: PixelGlyph
    let size: CGFloat
    public init(_ glyph: PixelGlyph, size: CGFloat = 12) {
        self.glyph = glyph
        self.size = max(12, (size / 6).rounded() * 6)
    }
    public init(symbol: String, size: CGFloat = 12) { self.init(PixelGlyph(symbol: symbol), size: size) }

    public var body: some View {
        PixelGlyphShape(glyph).frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// A Label whose icon is a pixel glyph.
public struct PixelLabel: View {
    let title: String
    let glyph: PixelGlyph
    @Environment(\.theme) private var theme
    public init(_ title: String, symbol: String) { self.title = title; self.glyph = PixelGlyph(symbol: symbol) }
    public init(_ title: String, glyph: PixelGlyph) { self.title = title; self.glyph = glyph }
    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
            PixelIcon(glyph).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.bottom] - 1 }
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }
}
