import SwiftUI

/// Axis labels drawn in a Canvas, nudged inward so one near an edge is never clipped.
enum ChartLabel {
    static func draw(_ context: GraphicsContext, _ text: Text, centeredAt x: CGFloat, top y: CGFloat, width: CGFloat) {
        let resolved = context.resolve(text)
        let size = resolved.measure(in: CGSize(width: width, height: .infinity))
        let center = min(max(x, size.width / 2), width - size.width / 2)
        context.draw(resolved, at: CGPoint(x: center, y: y), anchor: .top)
    }
}
