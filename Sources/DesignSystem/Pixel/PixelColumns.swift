import SwiftUI

/// Vertical bar charts on the pixel grid (founder review, 19 Oct 2026): Home's last 30 days, Stats › Overview's when
/// you work, and the tokens per day charts all draw their bars here, so they stay alike. A bar's width is whole
/// pixels (`px`), its height is quantised to `px` from the baseline, and its top corners step like `PixelRect`'s
/// (two steps, fewer when the bar is too narrow or short to show them). No other effect: a pixel bar, not a heavier
/// one. Callers keep their own scale, labels, hover band and readouts.
public enum PixelColumns {
    /// `value` rounded to a whole number of `px` from `origin`.
    public static func snap(_ value: CGFloat, to px: CGFloat, from origin: CGFloat = 0) -> CGFloat {
        origin + ((value - origin) / px).rounded() * px
    }

    /// A plot rectangle with every edge on a whole point, so the baseline and the bars that stand on it are crisp.
    public static func plot(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded(), minY = rect.minY.rounded()
        return CGRect(x: minX, y: minY, width: max(0, rect.maxX.rounded() - minX), height: max(0, rect.maxY.rounded() - minY))
    }

    /// Slot `index` of `count` across `plot`, with whole-point edges (for the hover band).
    public static func slot(_ index: Int, of count: Int, in plot: CGRect) -> CGRect {
        let width = plot.width / CGFloat(max(1, count))
        let minX = (plot.minX + CGFloat(index) * width).rounded(), maxX = (plot.minX + CGFloat(index + 1) * width).rounded()
        return CGRect(x: minX, y: plot.minY, width: maxX - minX, height: plot.height)
    }

    /// The bar of slot `index`: `share` of the slot's width as whole pixels (at least one), centred on a whole point.
    /// Returns its left edge and width; every bar in a chart has the same width.
    public static func bar(_ index: Int, of count: Int, in plot: CGRect, share: CGFloat, px: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let slot = plot.width / CGFloat(max(1, count))
        let width = max(px, (slot * share / px).rounded() * px)
        let center = plot.minX + (CGFloat(index) + 0.5) * slot
        return ((center - width / 2).rounded(), width)
    }

    /// How tall a bar for `fraction` (0…1) of `height` stands, in whole pixels; anything above zero is at least one.
    public static func height(_ fraction: Double, of height: CGFloat, px: CGFloat) -> CGFloat {
        guard fraction > 0 else { return 0 }
        return max(px, (CGFloat(min(fraction, 1)) * height / px).rounded() * px)
    }

    /// A bar's outline: square at the base, top corners stepped like `PixelRect`'s.
    public static func shape(_ rect: CGRect, px: CGFloat) -> Path {
        let across = Int((rect.width / px).rounded()), tall = Int((rect.height / px).rounded())
        let steps = max(0, min(2, (across - 1) / 2, tall))
        return PixelSteppedRect(step: px, corners: (steps, steps, 0, 0)).path(in: rect)
    }

    /// One solid bar standing on `baseline`.
    public static func fill(_ context: inout GraphicsContext, x: CGFloat, width: CGFloat, height: CGFloat, baseline: CGFloat,
                            px: CGFloat, color: Color) {
        guard height > 0 else { return }
        context.fill(shape(CGRect(x: x, y: baseline - height, width: width, height: height), px: px), with: .color(color))
    }
}
