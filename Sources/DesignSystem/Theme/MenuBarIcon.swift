#if canImport(AppKit)
import AppKit

/// The menu bar template images (UX_SPEC §1.4, DESIGN_SYSTEM §4 `icon.*`). Shape carries the meaning and
/// colour is left to the system, so the icon reads the same in a light, dark or tinted menu bar.
/// The founder may redraw these; the five shapes must stay distinct without colour.
public enum MenuBarIcon {
    public enum Shape: String, CaseIterable, Sendable {
        case ring          // icon.ok
        case notch         // icon.approaching: ring with an exclamation mark
        case bar           // icon.exhausted: ring with a horizontal bar
        case clock         // icon.stale: ring with a clock mark
        case dashed        // icon.demo
    }

    public static func symbol(_ shape: Shape) -> String {
        switch shape {
        case .ring: "circle"
        case .notch: "exclamationmark.circle"
        case .bar: "minus.circle"
        case .clock: "clock"
        case .dashed: "circle.dashed"
        }
    }

    /// A template image; `staleMark` adds a small clock to a non-clock shape (stale but still exhausted, say).
    @MainActor
    public static func image(_ shape: Shape, staleMark: Bool, pointSize: CGFloat = 14) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let base = NSImage(systemSymbolName: symbol(shape), accessibilityDescription: nil)?.withSymbolConfiguration(configuration) ?? NSImage()
        guard staleMark, shape != .clock,
              let mark = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize * 0.55, weight: .bold)) else {
            base.isTemplate = true
            return base
        }
        let size = NSSize(width: base.size.width + mark.size.width * 0.6, height: base.size.height)
        let composite = NSImage(size: size, flipped: false) { _ in
            base.draw(in: NSRect(origin: .zero, size: base.size))
            mark.draw(in: NSRect(x: size.width - mark.size.width, y: 0, width: mark.size.width, height: mark.size.height))
            return true
        }
        composite.isTemplate = true
        return composite
    }
}

/// Increment 1.11: the Phosphor menu bar icon from the 1.7b concept board: a 16×16 pixel ring, a state mark inside
/// it, and the highest percentage in the pixel face, drawn as one template image so the system tints it for any
/// menu bar. The five states still differ by shape: plain ring, "!", a bar, clock hands, a broken ring.
extension MenuBarIcon {
    static let ring: [String] = [
        ".....######.....", "...##......##...", "..#..........#..", ".#............#.", ".#............#.", "#..............#",
        "#..............#", "#..............#", "#..............#", "#..............#", "#..............#", ".#............#.",
        ".#............#.", "..#..........#..", "...##......##...", ".....######.....",
    ]

    /// Pixels drawn inside the ring for each state (x, y on the 16×16 grid).
    static func mark(_ shape: Shape) -> [(Int, Int)] {
        switch shape {
        // 1.16: the Pulse mark (design/brand): the beat inside the ring is the live reading.
        case .ring: return [(3, 8), (4, 8), (5, 4), (5, 5), (5, 6), (5, 7), (5, 8), (6, 3), (7, 4), (7, 5), (7, 6), (7, 7),
                            (7, 8), (7, 9), (7, 10), (7, 11), (8, 12), (9, 9), (9, 10), (9, 11), (10, 8), (11, 8), (12, 8)]
        case .notch: return (4...9).flatMap { y in [(7, y), (8, y)] } + [(7, 11), (8, 11)]       // "!"
        case .bar: return (4...11).flatMap { x in [(x, 7), (x, 8)] }                              // a bar across
        case .clock: return (4...8).map { (7, $0) } + (8...10).map { ($0, 8) }                    // hands at 3 o'clock
        case .dashed: return []
        }
    }

    /// The grid as drawn: the ring (with gaps for demo) plus the state mark, and a small corner block when stale.
    public static func pixels(_ shape: Shape, staleMark: Bool) -> Set<Int> {
        var on = Set<Int>()
        for (y, row) in ring.enumerated() {
            for (x, ch) in row.enumerated() where ch == "#" {
                if shape == .dashed, (x + y) % 4 < 2 { continue }                                  // broken ring
                on.insert(y * 16 + x)
            }
        }
        for (x, y) in mark(shape) { on.insert(y * 16 + x) }
        if staleMark, shape != .clock { for (x, y) in [(13, 13), (14, 13), (13, 14), (14, 14), (15, 15)] { on.insert(y * 16 + x) } }
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
