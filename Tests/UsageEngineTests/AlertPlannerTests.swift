import Domain
import Foundation
import Testing
@testable import UsageEngine

/// Increments 2.1–2.3: which engine events become limit alerts (NOTIFICATIONS_AND_SCHEDULING §1).
struct AlertPlannerTests {
    let t0 = Date(timeIntervalSince1970: 1_792_000_000)
    let window = UUID()
    let pool = "claude-code.rate_limits.five_hour"

    func event(_ kind: DerivedEventKind, _ level: ThresholdLevel? = nil, at minutes: Double = 0, window: UUID? = nil) -> EngineEvent {
        EngineEvent(kind: kind, poolKey: pool, windowID: window ?? self.window, level: level, occurredAt: t0.addingTimeInterval(minutes * 60))
    }

    @Test func crossingsBecomeApproachingAndExhausted() {
        let a = AlertPlanner.plan([event(.thresholdCrossed, .warning)], context: .init(), now: t0)
        #expect(a.map(\.kind) == [.approaching] && a.first?.level == 80)
        let b = AlertPlanner.plan([event(.thresholdCrossed, .critical)], context: .init(), now: t0)
        #expect(b.first?.level == 95)
        let c = AlertPlanner.plan([event(.exhausted)], context: .init(), now: t0)
        #expect(c.map(\.kind) == [.exhausted] && c.first?.level == 100 && c.first?.relevance == 1.0)
    }

    @Test func oneReadingThroughSeveralLevelsAlertsOnceAtTheHighest() {
        let a = AlertPlanner.plan([event(.thresholdCrossed, .warning), event(.thresholdCrossed, .critical), event(.exhausted)],
                                  context: .init(), now: t0)
        #expect(a.map(\.kind) == [.exhausted])
    }

    @Test func eachCrossingIsShownOnce() {
        let first = AlertPlanner.plan([event(.thresholdCrossed, .warning)], context: .init(), now: t0)
        let again = AlertPlanner.plan([event(.thresholdCrossed, .warning)], context: .init(delivered: Set(first.map(\.dedupKey))), now: t0)
        #expect(again.isEmpty)
        // A new window re-arms: same level, different key.
        let next = AlertPlanner.plan([event(.thresholdCrossed, .warning, window: UUID())], context: .init(delivered: Set(first.map(\.dedupKey))), now: t0)
        #expect(next.count == 1)
    }

    @Test func readyAgainOnlyAfterTheLimitWasReached() {
        // B4: someone at 85% never asked for "ready".
        #expect(AlertPlanner.plan([event(.readyAgain)], context: .init(deliveredKinds: [window: [.approaching]]), now: t0).isEmpty)
        let ready = AlertPlanner.plan([event(.readyAgain)], context: .init(deliveredKinds: [window: [.exhausted]]), now: t0)
        #expect(ready.map(\.kind) == [.readyAgain])
        // In one batch: exhausted, then (later) the reset arrives and is verified.
        let both = AlertPlanner.plan([event(.exhausted), event(.readyAgain, at: 300)], context: .init(), now: t0)
        #expect(both.map(\.kind) == [.exhausted, .readyAgain])
    }

    @Test func resetExpectedOnlyForWindowsThatHitTheLimit() {
        #expect(AlertPlanner.plan([event(.resetExpected)], context: .init(), now: t0).isEmpty)
        #expect(AlertPlanner.plan([event(.resetExpected)], context: .init(deliveredKinds: [window: [.exhausted]]), now: t0).map(\.kind) == [.resetExpected])
    }

    @Test func snoozeHoldsLimitAlertsButNotReadyAgain() {
        let ctx = AlertPlanner.Context(deliveredKinds: [window: [.exhausted]], snoozedUntil: t0.addingTimeInterval(3600))
        #expect(AlertPlanner.plan([event(.thresholdCrossed, .warning)], context: ctx, now: t0).isEmpty)
        #expect(AlertPlanner.plan([event(.readyAgain)], context: ctx, now: t0).count == 1)
        // After the snooze ends, alerts flow again.
        #expect(AlertPlanner.plan([event(.thresholdCrossed, .warning)], context: ctx, now: t0.addingTimeInterval(3601)).count == 1)
    }

    @Test func offOrDemoMeansSilence() {
        #expect(AlertPlanner.plan([event(.exhausted)], context: .init(enabled: false), now: t0).isEmpty)
        #expect(AlertPlanner.plan([event(.exhausted)], context: .init(isDemo: true), now: t0).isEmpty)
    }

    @Test func otherEventsNeverAlert() {
        let quiet: [DerivedEventKind] = [.windowOpened, .windowRescheduled, .staleSource, .connectionStateChanged, .parserRejected, .paidOverageDetected]
        #expect(AlertPlanner.plan(quiet.map { event($0) }, context: .init(), now: t0).isEmpty)
    }

    @Test func poolsAreIndependent() {
        let codex = EngineEvent(kind: .exhausted, poolKey: "codex.rate_limits.seven_day", windowID: UUID(), level: nil, occurredAt: t0)
        let a = AlertPlanner.plan([event(.thresholdCrossed, .warning), codex], context: .init(), now: t0)
        #expect(Set(a.map(\.poolKey)) == [pool, "codex.rate_limits.seven_day"])
    }
}
