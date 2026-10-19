import Domain
import Foundation
import Testing
@testable import UsageEngine

/// v0.3 (docs/specs/mod-bridge.md §7): one source per window. While the status line reports a window, the mod's
/// reading of it (another app's session) is history only for 60 s, so two apps' sessions never take turns moving it.
@Suite("One source per window")
struct SourceHoldOffTests {
    func update(_ used: Decimal, at seconds: Double, via channel: ObservationChannel?, reset: Date = resetAt) -> PoolUpdate {
        let t = start.addingTimeInterval(seconds)
        func o(_ kind: MetricKind, _ value: MetricValue) -> IncomingObservation {
            IncomingObservation(subject: .pool(providerPoolKey: pool), sessionRef: "s", modelID: nil, kind: kind, value: value,
                                observedAt: t, receivedAt: t, evidence: .officialLocalTelemetry, quality: .reported,
                                sourceVersion: "2.1.299", dedupeKey: UUID().uuidString, channel: channel)
        }
        return PoolUpdate(used: o(.quotaUsedPct, .percent(used)), reset: o(.resetAt, .instant(reset)))
    }

    func reduce(_ steps: [(Decimal, Double, ObservationChannel?)]) -> (PoolState, [EngineEvent]) {
        var state = PoolState(poolKey: pool)
        var events: [EngineEvent] = []
        for (used, seconds, channel) in steps {
            let r = PoolReducer.reduce(state, update(used, at: seconds, via: channel), now: start.addingTimeInterval(seconds))
            state = r.state
            events += r.events
        }
        return (state, events)
    }

    @Test("A mod reading within 60 s of the status line's is history only; after 60 s it applies")
    func holdOff() {
        var (state, _) = reduce([(26, 0, nil), (27, 30, .mod)])
        #expect(state.usedPct == 26 && state.lastProviderMeasured == start)
        (state, _) = reduce([(26, 0, nil), (27, 30, .mod), (28, 61, .mod)])
        #expect(state.usedPct == 28)
        #expect(state.lastStatusLineAt == start, "the mod never starts a hold")
    }

    @Test("The status line always applies; mod readings alone (desktop-only work) apply as they come")
    func statusLineWins() {
        let (mixed, _) = reduce([(27, 0, .mod), (26, 10, nil), (27, 40, .mod), (27, 50, nil)])
        #expect(mixed.usedPct == 27 && mixed.lastProviderMeasured == start.addingTimeInterval(50))
        let (desktop, _) = reduce([(26, 0, .mod), (27, 30, .mod), (30, 300, .mod)])
        #expect(desktop.usedPct == 30)
    }

    @Test("A threshold crossed through the mod while the status line holds the window fires once it is the status line's turn")
    func noFlappingAlerts() {
        // Status line 79 %, the desktop session says 81 % 20 s later (held), the status line then reports 81 % itself.
        let (_, events) = reduce([(79, 0, nil), (81, 20, .mod), (81, 30, nil), (79, 40, .mod), (81, 50, nil)])
        #expect(events.filter { $0.kind == .thresholdCrossed }.count == 1, "\(events.map(\.kind))")
    }

    @Test("A reset seen through the mod opens the next window when the status line is quiet")
    func resetThroughMod() {
        let next = resetAt.addingTimeInterval(5 * 3600)
        var state = PoolState(poolKey: pool)
        state = PoolReducer.reduce(state, update(96, at: 0, via: nil), now: start).state
        let after = resetAt.timeIntervalSince(start) + 60
        let r = PoolReducer.reduce(state, update(2, at: after, via: .mod, reset: next), now: start.addingTimeInterval(after))
        #expect(r.events.map(\.kind).contains(.readyAgain))
        #expect(r.state.window?.resetsAt == next && r.state.usedPct == 2)
    }

    @Test("Sessions: the status line holds its own session; mod readings of a session with no status line apply")
    func sessions() {
        func o(_ tokens: Int64, at seconds: Double, via channel: ObservationChannel?) -> IncomingObservation {
            IncomingObservation(subject: .session(sessionRef: "abc"), sessionRef: "abc", modelID: nil, kind: .contextTokens,
                                value: .tokens(tokens), observedAt: start.addingTimeInterval(seconds),
                                receivedAt: start.addingTimeInterval(seconds), evidence: .officialLocalTelemetry, quality: .reported,
                                sourceVersion: nil, dedupeKey: UUID().uuidString, channel: channel)
        }
        var s = SessionReducer.reduce(SessionState(sessionRef: "abc"), [o(100, at: 0, via: nil)])
        s = SessionReducer.reduce(s, [o(999, at: 20, via: .mod)])
        #expect(s.values[.contextTokens]?.value == .tokens(100))
        s = SessionReducer.reduce(s, [o(200, at: 90, via: .mod)])
        #expect(s.values[.contextTokens]?.value == .tokens(200))
        let desktop = SessionReducer.reduce(SessionState(sessionRef: "abc"), [o(5, at: 0, via: .mod), o(6, at: 10, via: .mod)])
        #expect(desktop.values[.contextTokens]?.value == .tokens(6))
    }

    @Test("A snapshot saved before v0.3 (no lastStatusLineAt) still decodes")
    func oldSnapshot() throws {
        var state = PoolState(poolKey: pool)
        state.usedPct = 41
        let data = try JSONEncoder().encode(state)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["lastStatusLineAt"] = nil
        let decoded = try JSONDecoder().decode(PoolState.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.usedPct == 41 && decoded.lastStatusLineAt == nil)
    }
}
