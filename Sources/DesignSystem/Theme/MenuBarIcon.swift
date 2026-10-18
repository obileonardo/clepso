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
    public static func pixelImage(_ shape: Shape, staleMark: Bool, text: String?, height: CGFloat = 16) -> NSImage {
        _ = PixelFonts.ensureRegistered()
        let on = pixels(shape, staleMark: staleMark)
        let unit = height / 16
        let font = NSFont(name: PixelFonts.display, size: 10) ?? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let label = text.map { NSAttributedString(string: $0, attributes: [.font: font, .foregroundColor: NSColor.black]) }
        let gap: CGFloat = label == nil ? 0 : 4
        let textWidth = ceil(label?.size().width ?? 0)
        let size = NSSize(width: height + gap + textWidth, height: height)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            for index in on {
                NSRect(x: CGFloat(index % 16) * unit, y: CGFloat(index / 16) * unit, width: unit, height: unit).fill()
            }
            if let label {
                let h = label.size().height
                label.draw(at: NSPoint(x: height + gap, y: (height - h) / 2))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
#endif
