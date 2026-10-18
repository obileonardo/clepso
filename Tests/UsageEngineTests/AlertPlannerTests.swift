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
        // After the snooze ends, new crossings alert again.
        #expect(AlertPlanner.plan([event(.thresholdCrossed, .warning, at: 60.02)], context: ctx, now: t0.addingTimeInterval(3601)).count == 1)
    }

    @Test("Freshness caps (§3.5, §2): an alert whose event is too old for its kind is held back as expired, not shown")
    func tooOldIsExpiredNotShown() {
        let shown: Set<AlertKind> = [.exhausted]
        let ctx = AlertPlanner.Context(deliveredKinds: [window: shown])
        // The cap itself still alerts; one second past it does not.
        for (kind, event) in [(AlertKind.resetExpected, event(.resetExpected)), (.readyAgain, event(.readyAgain)),
                              (.approaching, event(.thresholdCrossed, .warning)), (.exhausted, event(.exhausted))] {
            let atCap = AlertPlanner.decide([event], context: ctx, now: t0.addingTimeInterval(kind.maxAge))
            #expect(atCap.alerts.map(\.kind) == [kind] && atCap.expired.isEmpty)
            let late = AlertPlanner.decide([event], context: ctx, now: t0.addingTimeInterval(kind.maxAge + 1))
            #expect(late.alerts.isEmpty && late.expired.map(\.kind) == [kind])
        }
        #expect([AlertKind.readyAgain, .resetExpected, .approaching, .exhausted].map(\.maxAge) == [600, 900, 1800, 1800])
        // A weekend asleep: Friday's reset reached on Monday is expired, with the key it would have had.
        let monday = AlertPlanner.decide([event(.resetExpected)], context: ctx, now: t0.addingTimeInterval(3 * 86_400))
        #expect(monday.alerts.isEmpty && monday.expired.first?.dedupKey == AlertPlanner.key(poolKey: pool, windowID: window, kind: .resetExpected, level: nil))
        // A clock stepped back (event "in the future") is fresh, not expired.
        #expect(AlertPlanner.decide([event(.exhausted, at: 2)], context: ctx, now: t0).alerts.count == 1)
        // Guards and receipts come first: a window that never hit its limit, or an already decided key, is neither.
        #expect(AlertPlanner.decide([event(.resetExpected)], context: .init(), now: t0.addingTimeInterval(86_400)) == .init())
        let decided = AlertPlanner.Context(delivered: [monday.expired[0].dedupKey], deliveredKinds: [window: shown])
        #expect(AlertPlanner.decide([event(.resetExpected)], context: decided, now: t0.addingTimeInterval(86_400)) == .init())
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
