import AppKit
import Testing
@testable import PulseApp

/// 1.17: the Dashboard opens filling the screen, and its page column grows with the window within bounds.
struct WindowSizingTests {
    @Test func columnGrowsWithTheWindowWithinBounds() {
        #expect(PageMetrics.column(fitting: 900) == 1040)               // small windows keep the old column
        #expect(PageMetrics.column(fitting: 1240) == 1144)              // in between: the window minus gutters
        #expect(PageMetrics.column(fitting: 3000) == 1360)              // very wide: capped for legibility
        let content = PageMetrics.content(1360)
        #expect(content == 1070, "\(content)")
    }

    @Test func windowFillsTheVisibleScreenAndIsNeverTallerThanIt() {
        let visible = NSRect(x: 0, y: 80, width: 1728, height: 1037)    // below the menu bar, above the Dock
        let frame = WindowFitter.FittingView.frame(for: visible, minimum: NSSize(width: 1100, height: 660))
        #expect(frame == visible)
        // A screen smaller than the minimum: never taller than the screen, centred, top-aligned.
        let small = NSRect(x: 0, y: 0, width: 1024, height: 600)
        let fitted = WindowFitter.FittingView.frame(for: small, minimum: NSSize(width: 1100, height: 660))
        #expect(fitted.height == 600 && fitted.maxY == 600 && fitted.midX == small.midX)
    }
}
