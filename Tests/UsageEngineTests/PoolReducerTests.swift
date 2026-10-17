import Domain
import Foundation
import Testing
@testable import UsageEngine

let start = Date(timeIntervalSince1970: 1_792_159_200)       // 2026-10-16T14:00:00Z
let resetAt = start.addingTimeInterval(2 * 3600)
let pool = "claude-code.rate_limits.five_hour"

func observation(_ kind: MetricKind, _ value: MetricValue, at: Date, received: Date? = nil) -> IncomingObservation {
    IncomingObservation(subject: .pool(providerPoolKey: pool), sessionRef: "s", modelID: nil, kind: kind, value: value,
                        observedAt: at, receivedAt: received ?? at, evidence: .officialLocalTelemetry,
                        quality: .reported, sourceVersion: "2.1.302", dedupeKey: UUID().uuidString)
}

/// Runs a sequence of (minutes after start, used %, reset) through the reducer at live time.
struct Run {
    var state = PoolState(poolKey: pool)
    var events: [EngineEvent] = []
    var overage = false

    mutating func at(_ minutes: Double, used: Decimal?, reset: Date? = resetAt, absent: AbsenceReason? = nil) {
        let t = start.addingTimeInterval(minutes * 60)
        let usedValue: MetricValue = used.map { .percent($0) } ?? .absent(absent ?? .providerOmitted)
        let resetValue: MetricValue = reset.map { .instant($0) } ?? .absent(.providerOmitted)
        let r = PoolReducer.reduce(state, PoolUpdate(used: observation(.quotaUsedPct, usedValue, at: t),
                                                     reset: observation(.resetAt, resetValue, at: t)),
                                   now: t, overageEvidence: overage)
        state = r.state
        events += r.events
    }

    mutating func tick(_ minutes: Double) {
        let (s, e) = PoolReducer.tick(state, now: start.addingTimeInterval(minutes * 60))
        state = s
        events += e
    }

    func kinds(after index: Int = 0) -> [String] {
        events.dropFirst(index).map { [$0.kind.rawValue, $0.level?.rawValue].compactMap { $0 }.joined(separator: ".") }
    }
}

@Suite("Limit state machine (DATA_MODEL §7.1)")
struct LimitStateTests {
    @Test("G1: the first value sets the state with no threshold event, only a window")
    func firstValue() {
        var run = Run()
        run.at(0, used: 85)
        #expect(run.state.limit == .approaching(.warning))
        #expect(run.kinds() == ["windowOpened"], "initial-state alerts are off")
    }

    @Test("G2–G4: upward crossings only, each threshold once per window")
    func crossings() {
        var run = Run()
        run.at(0, used: 79)
        run.at(1, used: 95)
        #expect(run.kinds(after: 1) == ["thresholdCrossed.warning", "thresholdCrossed.critical"],
                "the engine reports every crossing; the notification engine coalesces (NOTIFICATIONS §1.5)")
        run.at(2, used: 96)
        run.at(3, used: 95)
        #expect(run.events.count == 3, "no repeat while still above the threshold")
        run.at(4, used: 100)
        #expect(run.kinds(after: 3) == ["exhausted"])
        #expect(run.state.limit == .exhausted)
    }

    @Test("G7, G8: hysteresis t − 3 on the way down, silently")
    func hysteresis() {
        var run = Run()
        run.at(0, used: 96)
        run.at(1, used: 93); #expect(run.state.limit == .approaching(.critical))
        run.at(2, used: 92); #expect(run.state.limit == .approaching(.warning))
        run.at(3, used: 78); #expect(run.state.limit == .approaching(.warning))
        run.at(4, used: 77); #expect(run.state.limit == .available)
        #expect(run.kinds() == ["windowOpened"], "decreases never produce events")
    }

    @Test("100 → 99 without a reset is not recovery")
    func noFalseRecovery() {
        var run = Run()
        run.at(0, used: 100)
        run.at(1, used: 99)
        #expect(run.state.limit == .exhausted)
        #expect(!run.kinds().contains("readyAgain"))
    }

    @Test("G5: paid overage only with evidence (F11)")
    func paidOverage() {
        var without = Run()
        without.at(0, used: 100)
        #expect(without.state.limit == .exhausted)
        var with = Run()
        with.overage = true
        with.at(0, used: 99)
        with.at(1, used: 100)
        #expect(with.state.limit == .paidOverage)
        #expect(with.kinds().contains("paidOverageDetected"))
    }

    @Test("G10, G11: a missing window keeps the measured state; nothing measured stays unknown")
    func absences() {
        var never = Run()
        never.at(0, used: nil, reset: nil)
        #expect(never.state.limit == .unknown && never.state.usedAbsence == .providerOmitted && never.state.usedPct == nil)

        var dropped = Run()
        dropped.at(0, used: 90)
        dropped.at(1, used: nil, reset: nil)
        #expect(dropped.state.limit == .approaching(.warning), "state survives the provider dropping the window")
        #expect(dropped.state.usedPct == 90)
        #expect(dropped.state.omittedSince == start.addingTimeInterval(60))
    }

    @Test("F09: an older sample after a newer one changes nothing")
    func outOfOrder() {
        var run = Run()
        run.at(10, used: 83)
        let before = run.state
        let older = PoolReducer.reduce(run.state, PoolUpdate(used: observation(.quotaUsedPct, .percent(80), at: start.addingTimeInterval(5 * 60),
                                                                               received: start.addingTimeInterval(11 * 60)), reset: nil),
                                       now: start.addingTimeInterval(11 * 60))
        #expect(older.state == before)
        #expect(older.events.isEmpty)
    }

    @Test("A stale observation updates the value but raises no alert")
    func staleObservation() {
        let late = PoolReducer.reduce(PoolState(poolKey: pool),
                                      PoolUpdate(used: observation(.quotaUsedPct, .percent(79), at: start), reset: nil), now: start)
        let r = PoolReducer.reduce(late.state, PoolUpdate(used: observation(.quotaUsedPct, .percent(97), at: start.addingTimeInterval(60)), reset: nil),
                                   now: start.addingTimeInterval(60 + 11 * 60))
        #expect(r.state.usedPct == 97)
        #expect(!r.events.contains { $0.kind == .thresholdCrossed })
    }
}

@Suite("Resets and windows (DATA_MODEL §6.3, §7.2)")
struct ResetTests {
    @Test("G9 then G6: reset expected once, ready again only on a fresh lower reading, once per window")
    func resetCycle() {
        var run = Run()
        run.at(0, used: 100)
        run.tick(119)
        #expect(run.state.limit == .exhausted, "before the reset time")
        run.tick(120)
        #expect(run.state.limit == .resetExpected)
        run.tick(125)
        #expect(run.kinds().filter { $0 == "resetExpected" }.count == 1)

        run.at(130, used: nil, reset: nil)                 // Claude Code drops the window after reset
        #expect(run.state.limit == .resetExpected, "an absent window is not recovery")

        let newReset = start.addingTimeInterval(130 * 60 + 5 * 3600)
        run.at(131, used: 3, reset: newReset)
        #expect(run.state.limit == .available)
        #expect(run.kinds().filter { $0 == "readyAgain" }.count == 1)
        #expect(run.state.window?.resetsAt == newReset)
        run.at(132, used: 4, reset: newReset)
        #expect(run.kinds().filter { $0 == "readyAgain" }.count == 1, "never twice for one window")
    }

    @Test("G6 needs a material drop: 100 → 98 after the reset time stays limited")
    func noMaterialDrop() {
        var run = Run()
        run.at(0, used: 100)
        run.at(121, used: 98, reset: start.addingTimeInterval(121 * 60 + 5 * 3600))
        #expect(!run.kinds().contains("readyAgain"))
    }

    @Test("A reset time moving 15 minutes or less keeps the window; more opens a new one and re-arms")
    func windowTolerance() {
        var run = Run()
        run.at(0, used: 85)
        let firstWindow = run.state.window?.id
        run.at(1, used: 86, reset: resetAt.addingTimeInterval(5 * 60))
        #expect(run.state.window?.id == firstWindow && run.state.window?.version == 2)
        #expect(run.kinds().last == "windowRescheduled")
        run.at(2, used: 70, reset: resetAt.addingTimeInterval(3600))
        #expect(run.state.window?.id != firstWindow)
        run.at(3, used: 81, reset: resetAt.addingTimeInterval(3600))
        #expect(run.kinds().last == "thresholdCrossed.warning", "a new window re-arms thresholds")
    }

    @Test("G13: stale once per episode on a tick, never on the pre-observation check")
    func staleness() {
        var run = Run()
        run.at(0, used: 20, reset: nil)
        run.tick(9)
        #expect(!run.kinds().contains("staleSource"))
        run.tick(10)
        run.tick(30)
        #expect(run.kinds().filter { $0 == "staleSource" }.count == 1)
        run.at(31, used: 21, reset: nil)
        run.at(60, used: 22, reset: nil)                  // 29 minutes quiet, then a fresh reading
        #expect(run.kinds().filter { $0 == "staleSource" }.count == 1, "a fresh reading after a gap is not 'stale'")
    }

    @Test("Window ids are derived, so a replay produces the same ids")
    func derivedIDs() {
        var a = Run(), b = Run()
        a.at(0, used: 50)
        b.at(0, used: 50)
        #expect(a.state.window?.id == b.state.window?.id)
        #expect(derivedUUID("x") == derivedUUID("x") && derivedUUID("x") != derivedUUID("y"))
    }
}

@Suite("Session reducer")
struct SessionReducerTests {
    @Test("Latest value per metric; older samples ignored; other sessions ignored")
    func latestWins() {
        func obs(_ ref: String, _ kind: MetricKind, _ value: MetricValue, _ minute: Double) -> IncomingObservation {
            IncomingObservation(subject: .session(sessionRef: ref), sessionRef: ref, modelID: "claude-opus-5-5", kind: kind, value: value,
                                observedAt: start.addingTimeInterval(minute * 60), receivedAt: start, evidence: .officialLocalTelemetry,
                                quality: .reported, sourceVersion: nil, dedupeKey: UUID().uuidString)
        }
        var s = SessionReducer.reduce(SessionState(sessionRef: "a"), [obs("a", .contextUsedPct, .percent(40), 2)])
        s = SessionReducer.reduce(s, [obs("a", .contextUsedPct, .percent(30), 1), obs("b", .contextUsedPct, .percent(99), 3)])
        #expect(s.values[.contextUsedPct]?.value == .percent(40))
        #expect(s.modelID == "claude-opus-5-5" && s.version == 1)
    }
}
