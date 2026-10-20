#if canImport(AppKit)
import AppKit

/// The menu bar template image: the brand kit's status family (design/brand/menubar, `state-*.png`), a 16×16 pixel
/// ring with a mark inside that says the state, and optionally the highest percentage in the pixel face, drawn as one
/// template image so the system tints it for a light, dark or tinted menu bar. Shape carries the meaning, never colour.
/// The glyphs themselves are generated: `Shape` and `rows(_:)` live in MenuBarGlyphs.swift (design/brand/pipeline).
public enum MenuBarIcon {}

extension MenuBarIcon.Shape {
    /// The state in words, for the status item's accessibility value (the glyph's meaning, whatever the line says).
    public var spokenName: String {
        switch self {
        case .beat: "Receiving readings"
        case .approaching: "Nearing a limit"
        case .flatline: "Limit reached"
        case .stale: "Readings out of date"
        case .demo: "Demo data"
        case .waiting: "Waiting for the first reading"
        case .notConnected: "Not connected"
        }
    }
}

extension MenuBarIcon {
    /// The state in words; `staleMark` adds that the shape showing is the last reading, not a live one.
    public static func spokenState(_ shape: Shape, staleMark: Bool) -> String {
        shape.spokenName + (marksStale(shape, staleMark) ? ", last reading is old" : "")
    }

    /// The stale modifier only goes on a shape that is not itself the stale clock.
    static func marksStale(_ shape: Shape, _ staleMark: Bool) -> Bool { staleMark && shape != .stale }

    /// The grid as drawn (index y × 16 + x): the generated glyph, with the ring opened and a dot set when stale.
    public static func pixels(_ shape: Shape, staleMark: Bool) -> Set<Int> {
        var on = Set<Int>()
        for (y, row) in rows(shape).enumerated() {
            for (x, ch) in row.enumerated() where ch == "#" { on.insert(y * 16 + x) }
        }
        if marksStale(shape, staleMark) {
            for (x, y) in staleCleared { on.remove(y * 16 + x) }
            for (x, y) in staleAdded { on.insert(y * 16 + x) }
        }
        return on
    }

    @MainActor
    public static func pixelImage(_ shape: Shape, staleMark: Bool, text: String?, height: CGFloat = 16,
                                  reservingText: [String] = []) -> NSImage {
        renderedImage(shape, staleMark: staleMark, text: text, height: height, reservingText: reservingText,
                      inset: 0, foreground: .black, background: nil)
    }

    /// A compact, opaque brand capsule. macOS must preserve these colours instead of template-tinting them.
    /// Six points of horizontal padding replaces the design's eight; the display face remains on its pixel grid.
    @MainActor
    public static func pillImage(_ shape: Shape, staleMark: Bool, text: String?, theme: Theme = .phosphor,
                                 reservingText: [String] = []) -> NSImage {
        let colors = pillColors(shape, staleMark: staleMark, theme: theme)
        return renderedImage(shape, staleMark: staleMark, text: text?.uppercased(), height: 20,
                             reservingText: reservingText.map { $0.uppercased() }, inset: 6,
                             foreground: NSColor(srgbRed: colors.ink.red, green: colors.ink.green, blue: colors.ink.blue, alpha: 1),
                             background: NSColor(srgbRed: colors.fill.red, green: colors.fill.green, blue: colors.fill.blue, alpha: 1))
    }

    /// The state remains readable from the glyph and wording as well as colour. Stale readings never look live.
    public static func pillColors(_ shape: Shape, staleMark: Bool, theme: Theme = .phosphor) -> (ink: RGB, fill: RGB) {
        let token: ColorToken = switch shape {
        case .flatline: .statusBlocked
        case .approaching: .statusAttention
        case .stale: .statusStale
        case .waiting, .notConnected: .statusUnknown
        case .beat, .demo: staleMark ? .statusStale : .accent
        }
        let fill = theme.rgb(token, .dark)
        let darkInk = theme.rgb(.background, .dark), lightInk = theme.rgb(.textPrimary, .dark)
        let ink = RGB.contrast(darkInk, fill) >= RGB.contrast(lightInk, fill) ? darkInk : lightInk
        return (ink, fill)
    }

    @MainActor
    private static func renderedImage(_ shape: Shape, staleMark: Bool, text: String?, height: CGFloat,
                                      reservingText: [String], inset: CGFloat, foreground: NSColor, background: NSColor?) -> NSImage {
        _ = PixelFonts.ensureRegistered()
        let on = pixels(shape, staleMark: staleMark)
        let glyphHeight: CGFloat = background == nil ? height : 16
        let unit = glyphHeight / 16
        let font = NSFont(name: PixelFonts.display, size: 10) ?? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let label = text.map { NSAttributedString(string: $0, attributes: [.font: font, .foregroundColor: foreground]) }
        let gap: CGFloat = label == nil ? 0 : 4
        // Reserve the widest frame for a rotating readout; adjacent status items must not move every six seconds.
        let reservedWidth = text == nil ? 0 : reservingText.map {
            NSAttributedString(string: $0, attributes: [.font: font]).size().width
        }.max() ?? 0
        let textWidth = ceil(max(label?.size().width ?? 0, reservedWidth))
        // Center the icon + current label inside the reserved canvas. Reserving only trailing space makes short
        // frames sit against the left edge of macOS's pill. Snap to whole points to preserve the pixel grid.
        let contentOffset = inset + floor((textWidth - ceil(label?.size().width ?? 0)) / 2)
        let size = NSSize(width: glyphHeight + gap + textWidth + 2 * inset, height: height)
        let image = NSImage(size: size, flipped: true) { _ in
            if let background {
                background.setFill()
                NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: height / 2, yRadius: height / 2).fill()
            }
            foreground.setFill()
            for index in on {
                NSRect(x: contentOffset + CGFloat(index % 16) * unit, y: (height - glyphHeight) / 2 + CGFloat(index / 16) * unit, width: unit, height: unit).fill()
            }
            if let label {
                // Clepso Pixel at 10 pt puts one font pixel on one point (INTEGRATION.md §2), and its 12 pt line box
                // centred on the 16 pt icon puts the baseline on a whole point, so every glyph edge is on the grid.
                // Antialiasing and font smoothing would still grow a grey fringe around each edge, which the template
                // tint turns into a blur: draw the text aliased, hard pixels like the glyph beside it.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.shouldAntialias = false
                NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
                let h = label.size().height
                label.draw(at: NSPoint(x: contentOffset + glyphHeight + gap, y: (height - h) / 2))
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = background == nil
        return image
    }
}
#endif
