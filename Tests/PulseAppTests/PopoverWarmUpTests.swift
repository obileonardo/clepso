import AppKit
import Testing
@testable import PulseApp

/// Item 8: popover open speed. The launch warm-up must really render the popover (a blank or partial render would warm
/// nothing and the first click would pay again), and it renders from the snapshot without changing any state.
@MainActor
struct PopoverWarmUpTests {
    @Test("The warm-up renders the whole popover off screen and leaves the model as it was")
    func warmUpRendersThePopover() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let model = box.model(clock: TestClock())
        await model.start(); defer { model.stop() }
        await model.setDemo(true)
        let before = model.snapshot
        let image = try #require(PopoverWarmUp.run(model))
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        #expect(CGFloat(image.width) / scale == PopoverMetrics.width, "the popover's own width")
        #expect(CGFloat(image.height) / scale > 300, "header, both limit cards, the session strip and the action bar")
        #expect(model.snapshot.now == before.now && model.snapshot.isDemo && model.popoverRoute == .overview)
    }
}
