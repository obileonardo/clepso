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
#endif
