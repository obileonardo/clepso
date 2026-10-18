import AppKit
import Testing
@testable import PulseApp

/// 1.17: the Dashboard opens at three quarters of the screen (then where the user left it), and its page column grows with the window within bounds.
struct WindowSizingTests {
    @Test func columnGrowsWithTheWindowWithinBounds() {
        #expect(PageMetrics.column(fitting: 900) == 1040)               // small windows keep the old column
        #expect(PageMetrics.column(fitting: 1240) == 1144)              // in between: the window minus gutters
        #expect(PageMetrics.column(fitting: 3000) == 1360)              // very wide: capped for legibility
        let content = PageMetrics.content(1360)
        #expect(content == 1070, "\(content)")
    }

    @Test func windowOpensAtThreeQuartersCentredAndNeverPastTheScreen() {
        let visible = NSRect(x: 0, y: 80, width: 2304, height: 1213)    // below the menu bar, above the Dock
        let minimum = NSSize(width: 1100, height: 660)
        let frame = WindowFitter.FittingView.frame(for: visible, minimum: minimum)
        #expect(frame.width == 1728 && abs(frame.height - 910) <= 1, "\(frame)")
        #expect(abs(frame.midX - visible.midX) <= 1 && abs(frame.midY - visible.midY) <= 1, "centred")
        // A smaller screen: the minimum size wins over three quarters, and the window never leaves the screen.
        let laptop = NSRect(x: 0, y: 0, width: 1280, height: 760)
        let fitted = WindowFitter.FittingView.frame(for: laptop, minimum: minimum)
        #expect(fitted.width == 1100 && fitted.height == 660 && laptop.contains(fitted))
        let tiny = NSRect(x: 0, y: 0, width: 1024, height: 600)
        #expect(WindowFitter.FittingView.frame(for: tiny, minimum: minimum).height == 600)
    }
}
