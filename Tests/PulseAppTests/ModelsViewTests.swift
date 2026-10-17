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

    @Test("A level is one more for every doubling of tokens above a thousand; progress is the way to the next")
    func levels() {
        #expect(ModelLevel.of(0) == (1, 0))
        #expect(ModelLevel.of(500).0 == 1)
        #expect(ModelLevel.of(2_000).0 == 2)
        #expect(ModelLevel.of(4_000).0 == 3)
        let (level, progress) = ModelLevel.of(3_000)
        #expect(level == 2 && abs(progress - (log2(3.0) - 1)) < 1e-9)
        #expect(ModelLevel.of(16_500_000_000).0 == 24)
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
