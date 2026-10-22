import Testing
@testable import ClepsoApp

@Suite("Native level-up flourish triggers") struct ModelLevelTransitionTests {
    @Test func onlyNewVisibleThresholdsCelebrate() {
        var tracker = ModelLevelTransition()
        func observe(id: String, scope: String, output: Int64?, active: Bool) -> Int? {
            tracker.observe(id: id, scope: scope, output: output, active: active)
        }
        #expect(observe(id: "opus-5", scope: "all", output: 900, active: true) == nil)
        #expect(observe(id: "opus-5", scope: "all", output: 950, active: true) == nil)
        #expect(observe(id: "opus-5", scope: "all", output: 1_100, active: true) == 2)
        #expect(observe(id: "opus-5", scope: "all", output: 1_100, active: true) == nil)
        #expect(observe(id: "opus-5", scope: "all", output: 900, active: true) == nil)
        #expect(observe(id: "opus-5", scope: "all", output: 1_100, active: true) == nil)
    }
    @Test func selectionRangeDemoAndHiddenUpdatesAreNotLevelUps() {
        var tracker = ModelLevelTransition()
        func observe(id: String, scope: String, output: Int64?, active: Bool) -> Int? {
            tracker.observe(id: id, scope: scope, output: output, active: active)
        }
        #expect(observe(id: "opus", scope: "all", output: 900, active: false) == nil)
        #expect(observe(id: "sonnet", scope: "all", output: 20_000, active: true) == nil)
        #expect(observe(id: "opus", scope: "all", output: 1_500, active: true) == nil)
        #expect(observe(id: "opus", scope: "week", output: 2_000, active: true) == nil)
        #expect(observe(id: "opus", scope: "preview", output: 5_000, active: false) == nil)
        #expect(observe(id: "opus", scope: "all", output: 5_000, active: true) == nil)
        #expect(observe(id: "opus", scope: "all", output: 10_000, active: false) == nil)
        #expect(observe(id: "opus", scope: "all", output: 10_000, active: true) == nil)
        #expect(observe(id: "opus", scope: "all", output: nil, active: true) == nil)
        #expect(observe(id: "opus", scope: "all", output: 20_000, active: true) == nil)
    }
}
