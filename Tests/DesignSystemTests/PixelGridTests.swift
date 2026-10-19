import CoreGraphics
import Domain
import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// Founder review (19 Oct 2026): progress bars whose fill follows the frame's stepped pattern, and bar charts drawn as
/// pixel bars. These check the geometry and that nothing lands between device pixels at 1× or 2×.
@Suite("Pixel grid: bars and columns")
struct PixelGridTests {
    let px: CGFloat = 2

    @Test("Bar segments sit on whole points, a pixel apart, filling the inside of the frame exactly",
          arguments: [(600.0, 20), (571.0, 30), (90.0, 12), (157.0, 24), (1203.0, 40), (40.0, 4)])
    func barLayout(width: Double, segments: Int) {
        let layout = PixelBar.layout(width: width, height: 16, px: px, segments: segments, fraction: 0.5)
        #expect(layout.cells.count == segments)
        #expect(layout.cells.first?.minX == px * 2)
        #expect(layout.cells.last.map { Double($0.maxX) } == width - 4)
        for cell in layout.cells {
            #expect(cell.minX == cell.minX.rounded() && cell.width > 0, "segment edges on whole points")
            #expect(cell.minY == px * 2 && cell.height == 16 - px * 4)
        }
        for (a, b) in zip(layout.cells, layout.cells.dropFirst()) { #expect(b.minX - a.maxX == px, "one pixel of gap") }
        let widths = layout.cells.map(\.width)
        #expect((widths.max() ?? 0) - (widths.min() ?? 0) <= 1, "segments differ by a point at most")
    }

    @Test("Lit and empty runs: none, one segment, half, all, and no value")
    func barRuns() {
        func runs(_ f: Double?) -> (Int, PixelBar.Run?, PixelBar.Run?) {
            let l = PixelBar.layout(width: 600, height: 16, px: px, segments: 20, fraction: f)
            return (l.lit, l.litRun, l.empty)
        }
        #expect(runs(nil).0 == 0 && runs(nil).1 == nil && runs(nil).2?.rect.width == 600 - px * 4)
        #expect(runs(0).0 == 0 && runs(0).1 == nil)
        #expect(runs(0.01).0 == 1 && runs(0.01).1?.steps == 1, "a sliver still lights one stepped segment")
        #expect(runs(0.5).0 == 10 && runs(0.5).1?.rect.maxX == runs(0.5).2.map { $0.rect.minX - px })
        #expect(runs(1).0 == 20 && runs(1).2 == nil && runs(1).1?.rect.width == 600 - px * 4)
        #expect(runs(1.7).0 == 20, "clamped")
        // A run too narrow to show a step stays square rather than collapsing.
        let narrow = PixelBar.layout(width: 60, height: 16, px: px, segments: 12, fraction: 0.05)
        #expect(narrow.litRun?.steps == 0)
    }

    @Test("Stepped corners: two steps reproduce PixelRect; one step is a single pixel notch")
    func steppedRect() {
        let r = CGRect(x: 0, y: 0, width: 40, height: 16)
        #expect(PixelSteppedRect(step: px, steps: 2).path(in: r).boundingRect == PixelRect(step: px).path(in: r).boundingRect)
        for x in stride(from: 1.0, to: 40, by: 2) {
            for y in stride(from: 1.0, to: 16, by: 2) {
                let p = CGPoint(x: x, y: y)
                #expect(PixelSteppedRect(step: px, steps: 2).path(in: r).contains(p) == PixelRect(step: px).path(in: r).contains(p))
            }
        }
        let one = PixelSteppedRect(step: px, steps: 1).path(in: r)
        #expect(!one.contains(CGPoint(x: 1, y: 1)) && one.contains(CGPoint(x: 3, y: 1)) && one.contains(CGPoint(x: 1, y: 3)))
        #expect(!one.contains(CGPoint(x: 39, y: 15)))
    }

    @Test("Columns: whole-pixel widths and heights, stepped tops that shrink to fit")
    func columns() {
        let plot = PixelColumns.plot(CGRect(x: 38.4, y: 8, width: 700.3, height: 151.6))
        #expect(plot.minX == 38 && plot.maxX == 739 && plot.maxY == 160)
        for i in 0..<30 {
            let bar = PixelColumns.bar(i, of: 30, in: plot, share: 0.7, px: px)
            #expect(bar.x == bar.x.rounded() && bar.width.truncatingRemainder(dividingBy: px) == 0 && bar.width >= px)
            let slot = PixelColumns.slot(i, of: 30, in: plot)
            #expect(slot.minX == slot.minX.rounded() && slot.maxX == slot.maxX.rounded())
        }
        #expect(PixelColumns.height(0, of: 150, px: px) == 0)
        #expect(PixelColumns.height(0.0001, of: 150, px: px) == px, "anything above zero shows")
        #expect(PixelColumns.height(0.5, of: 151, px: px).truncatingRemainder(dividingBy: px) == 0)
        #expect(PixelColumns.height(1, of: 150, px: px) == 150)
        // Two steps on a wide bar; one on a bar four pixels wide; none on a bar two pixels wide.
        let wide = PixelColumns.shape(CGRect(x: 0, y: 0, width: 16, height: 20), px: px)
        #expect(!wide.contains(CGPoint(x: 3, y: 1)) && wide.contains(CGPoint(x: 5, y: 1)) && !wide.contains(CGPoint(x: 1, y: 3)))
        #expect(wide.contains(CGPoint(x: 1, y: 19)), "square at the base")
        let four = PixelColumns.shape(CGRect(x: 0, y: 0, width: 8, height: 20), px: px)
        #expect(!four.contains(CGPoint(x: 1, y: 1)) && four.contains(CGPoint(x: 3, y: 1)))
        let thin = PixelColumns.shape(CGRect(x: 0, y: 0, width: 4, height: 20), px: px)
        #expect(thin.contains(CGPoint(x: 1, y: 1)))
    }

    // MARK: Rendered pixels

    /// The distinct colours in a rendering. Anti-aliased edges add in-between shades; whole-pixel geometry adds none.
    @MainActor
    func colours(_ view: some View, width: CGFloat, height: CGFloat, scale: CGFloat, scheme: ColorScheme = .dark) -> Int {
        let theme = Theme.phosphor
        let renderer = ImageRenderer(content: view.frame(width: width, height: height)
            .background(theme.color(.background, scheme))
            .environment(\.theme, theme).environment(\.colorScheme, scheme))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return -1 }
        // Redrawn into a known 8-bit RGBA buffer, whatever format the renderer chose.
        let w = image.width, h = image.height
        var pixels = [UInt32](repeating: 0, count: w * h)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? Set(pixels).count : -1
    }

    @Test("Bars render without in-between shades at 1× and 2×, at awkward widths, in every pattern",
          arguments: [1.0, 2.0])
    @MainActor
    func barPixels(scale: Double) {
        // Background, frame, empty block, the colour and its lit edge: five colours at most.
        for (width, segments) in [(571.0, 30), (157.0, 24), (90.0, 12), (603.0, 20)] {
            for fraction in [0.0, 0.02, 0.5, 1] {
                #expect(colours(PixelBar(fraction: fraction, role: .accent, pattern: .solid, segments: segments),
                                width: width, height: 16, scale: scale) <= 5, "solid \(width) \(segments) \(fraction) @\(scale)×")
            }
            #expect(colours(PixelBar(fraction: 0.83, role: .statusStale, pattern: .hatched, segments: segments),
                            width: width, height: 16, scale: scale) <= 5)
            #expect(colours(PixelBar(fraction: nil, role: .statusUnknown, pattern: .outline, segments: segments),
                            width: width, height: 16, scale: scale) <= 5)
            #expect(colours(PixelBar(fraction: 0.4, role: .statusSuccess, pattern: .solid, segments: segments),
                            width: width, height: 16, scale: scale, scheme: .light) <= 5)
        }
        // The check can see anti-aliasing: a rectangle off the grid fails it.
        #expect(colours(Canvas { c, _ in c.fill(Path(CGRect(x: 3.3, y: 2.6, width: 50.4, height: 7.7)), with: .color(.init(white: 0.9))) },
                        width: 80, height: 16, scale: scale) > 5)
    }

    @Test("Columns render without in-between shades at 1× and 2×", arguments: [1.0, 2.0])
    @MainActor
    func columnPixels(scale: Double) {
        let values: [Double] = [0.35, 0.8, 0.5, 0, 0.15, 1, 0.65, 0.02, 0.45, 0.9, 0, 0.3, 0.7, 0.2, 0.55, 0.05, 0.95, 0.4, 0.6, 0.1, 0.33, 0.77, 0, 1]
        let chart = Canvas { context, size in
            let plot = PixelColumns.plot(CGRect(x: 19.2, y: 7.5, width: size.width - 19.2, height: size.height - 19.7))
            for (i, v) in values.enumerated() {
                let bar = PixelColumns.bar(i, of: values.count, in: plot, share: 0.72, px: 2)
                PixelColumns.fill(&context, x: bar.x, width: bar.width, height: v == 0 ? 2 : PixelColumns.height(v, of: plot.height, px: 2),
                                  baseline: plot.maxY, px: 2, color: v == 0 ? .init(white: 0.3) : .init(white: 0.9))
            }
        }
        #expect(colours(chart, width: 517, height: 133, scale: scale) <= 3)
    }
}
