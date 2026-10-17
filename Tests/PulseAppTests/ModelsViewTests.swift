@testable import ClaudeCodeAdapter
import Foundation
import Testing
@testable import PulseApp

/// Increment 1.8f: the numbers behind the Models views (scale, levels, specialty).
struct ModelsViewTests {
    @Test("The chart scale rounds up to a number whose quarters are round too")
    func niceCeiling() {
        #expect(StackedModelChart.niceCeiling(0) == 4)
        #expect(StackedModelChart.niceCeiling(3) == 4)
        #expect(StackedModelChart.niceCeiling(7) == 8)
        #expect(StackedModelChart.niceCeiling(9) == 12)
        #expect(StackedModelChart.niceCeiling(6_500_000) == 8_000_000)
        #expect(StackedModelChart.niceCeiling(2_300_000) == 2_400_000)
        #expect(StackedModelChart.niceCeiling(10_000) == 10_000)
        for v: Int64 in [5, 99, 1_234, 987_654, 16_500_000_000] {
            let top = StackedModelChart.niceCeiling(v)
            #expect(top >= v && top % 4 == 0, "\(v) → \(top)")
            #expect(top < v * 2 || v < 10, "\(v) → \(top) leaves too much headroom")
        }
    }

    @Test("A level comes from output on fixed 1-2-5 targets; progress is the way from this level's target to the next")
    func levels() {
        func check(_ output: Int64, level: Int, floor: Int64, next: Int64) {
            let l = ModelLevel(output: output)
            #expect(l.level == level && l.floor == floor && l.next == next, "\(output) → LV \(l.level), \(l.floor)…\(l.next)")
        }
        check(0, level: 1, floor: 0, next: 1_000)
        check(999, level: 1, floor: 0, next: 1_000)
        check(1_000, level: 2, floor: 1_000, next: 2_000)
        check(5_700, level: 4, floor: 5_000, next: 10_000)
        check(10_100, level: 5, floor: 10_000, next: 20_000)
        check(309_700, level: 9, floor: 200_000, next: 500_000)
        check(2_800_000, level: 12, floor: 2_000_000, next: 5_000_000)
        check(5_300_000, level: 13, floor: 5_000_000, next: 10_000_000)
        check(18_200_000, level: 14, floor: 10_000_000, next: 20_000_000)
        #expect(abs(ModelLevel(output: 18_200_000).progress - 0.82) < 1e-9)
        // The ladder the app's legend and the documentation site both publish (scripts/build-site.py mirrors it).
        #expect(Array(ModelLevel.targets.prefix(19)) == [1_000, 2_000, 5_000, 10_000, 20_000, 50_000, 100_000, 200_000, 500_000,
                                                         1_000_000, 2_000_000, 5_000_000, 10_000_000, 20_000_000, 50_000_000,
                                                         100_000_000, 200_000_000, 500_000_000, 1_000_000_000])
        // More output never means a lower level, and a target always lies above the output.
        var last = 0
        for output in stride(from: Int64(0), through: 100_000_000, by: 77_777) {
            let l = ModelLevel(output: output)
            #expect(l.level >= last && l.next > output && l.floor <= output)
            last = l.level
        }
    }

    @Test("Specialty is the kind a model uses most relative to all models, not its largest kind")
    func specialty() {
        func totals(_ id: String, _ i: Int64, _ o: Int64, _ r: Int64, _ w: Int64) -> ClaudeCodeStats.ModelTotals {
            .init(model: id, input: i, output: o, cacheRead: r, cacheWrite: w)
        }
        let opus = totals("claude-opus-5-5", 4, 10, 15_000, 600)
        let haiku = totals("claude-haiku-5-5", 8, 1, 120, 30)
        let party = [opus, haiku]
        // Both mostly read from cache; Haiku reads input far more than the party does.
        let h = ModelSpecialty.of(haiku, party: party)
        #expect(h?.kind == .input)
        #expect((h?.ratio ?? 0) > 10)
        // A model that is the whole party is an all-rounder (every ratio is 1).
        #expect(ModelSpecialty.of(opus, party: [opus])?.ratio == 1)
        #expect(Copy.Stats.specialty("Reading input", times: 1.0) == "All-rounder")
        #expect(ModelSpecialty.of(nil, party: party) == nil)
        #expect(ModelSpecialty.of(totals("x", 0, 0, 0, 0), party: party) == nil)
    }

    @Test("Model families map to sprites; unknown models get the robot")
    func families() {
        #expect(ModelSprite.Family("claude-opus-5-5") == .opus)
        #expect(ModelSprite.Family("claude-sonnet-4-5-20250929") == .sonnet)
        #expect(ModelSprite.Family("claude-haiku-5-5") == .haiku)
        #expect(ModelSprite.Family("claude-fable-5-1") == .fable)
        #expect(ModelSprite.Family("some-other-model") == .other)
        for f in [ModelSprite.Family.opus, .sonnet, .haiku, .fable, .other] {
            let rows = ModelSprite.bitmap(f)
            #expect(rows.count == 12 && rows.allSatisfy { $0.count == 12 }, "\(f) bitmap is not 12×12")
        }
    }
}
