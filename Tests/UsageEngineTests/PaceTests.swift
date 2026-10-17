import Foundation
import Testing
@testable import UsageEngine

struct PaceTests {
    let now = Date(timeIntervalSince1970: 1_792_159_200)

    /// Readings every `step` minutes ending at `now`, rising by `perHour` from `start`.
    func series(start: Double, perHour: Double, minutes: Int, step: Int = 5) -> [UsagePoint] {
        stride(from: minutes, through: 0, by: -step).map { m in
            UsagePoint(at: now.addingTimeInterval(Double(-m) * 60), usedPct: start + perHour * Double(minutes - m) / 60)
        }
    }

    @Test("Rising 20 points an hour from 40%: 100% in 2 h when no reset intervenes")
    func reachesLimit() {
        let points = series(start: 40, perHour: 20, minutes: 60)                 // ends at 60%
        guard case .reachesLimit(let at) = PaceEstimate.estimate(points, windowOpenedAt: nil, resetsAt: now.addingTimeInterval(3 * 3600),
                                                                  now: now, lookback: 90 * 60) else { Issue.record("expected reachesLimit"); return }
        #expect(abs(at.timeIntervalSince(now) - 2 * 3600) < 60, "\(at.timeIntervalSince(now) / 3600) h")
    }

    @Test("The reset comes first: roughly how much will be used by then")
    func belowAtReset() {
        let points = series(start: 40, perHour: 20, minutes: 60)
        let result = PaceEstimate.estimate(points, windowOpenedAt: nil, resetsAt: now.addingTimeInterval(3600), now: now, lookback: 90 * 60)
        guard case .belowAtReset(let pct) = result else { Issue.record("\(result)"); return }
        #expect(abs(pct - 80) < 0.5)
    }

    @Test("Flat or falling usage gives no estimate")
    func flat() {
        #expect(PaceEstimate.estimate(series(start: 30, perHour: 0, minutes: 60), windowOpenedAt: nil, resetsAt: nil, now: now, lookback: 5400) == .notRising)
        #expect(PaceEstimate.estimate(series(start: 30, perHour: -10, minutes: 60), windowOpenedAt: nil, resetsAt: nil, now: now, lookback: 5400) == .notRising)
    }

    @Test("Too few readings, or too short a span, gives no estimate")
    func notEnough() {
        #expect(PaceEstimate.estimate(series(start: 30, perHour: 20, minutes: 5), windowOpenedAt: nil, resetsAt: nil, now: now, lookback: 5400) == .notEnoughData)
        #expect(PaceEstimate.estimate([], windowOpenedAt: nil, resetsAt: nil, now: now, lookback: 5400) == .notEnoughData)
    }

    @Test("Readings from before the window opened are ignored, so a reset never bends the line")
    func ignoresPreviousWindow() {
        // Before the reset: 90% climbing fast. After it (opened 30 min ago): 2% → 8%, slowly.
        let before = (0..<6).map { UsagePoint(at: now.addingTimeInterval(Double(-80 + $0 * 5) * 60), usedPct: 70 + Double($0) * 4) }
        let after = series(start: 2, perHour: 12, minutes: 30)
        let result = PaceEstimate.estimate(before + after, windowOpenedAt: now.addingTimeInterval(-30 * 60),
                                           resetsAt: now.addingTimeInterval(4.5 * 3600), now: now, lookback: 90 * 60)
        guard case .belowAtReset(let pct) = result else { Issue.record("\(result)"); return }
        #expect(abs(pct - (8 + 12 * 4.5)) < 0.5, "\(pct)")
    }

    @Test("Already at the limit")
    func atLimit() {
        #expect(PaceEstimate.estimate(series(start: 96, perHour: 10, minutes: 30), windowOpenedAt: nil, resetsAt: nil, now: now, lookback: 5400) == .atLimit)
    }
}
