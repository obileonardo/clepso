import Domain
import Foundation
import GRDB
import Testing
import UsageEngine
@testable import Storage

let t0 = Date(timeIntervalSince1970: 1_792_159_200)
let fiveHourKey = "claude-code.rate_limits.five_hour"

/// One frame's observations, shaped like FrameMapper output (DATA_MODEL §5.1).
func batch(session: String, used: Decimal?, reset: Date?, context: Decimal = 40, at minutes: Double, received: Double? = nil) -> [IncomingObservation] {
    let at = t0.addingTimeInterval(minutes * 60)
    let receivedAt = t0.addingTimeInterval((received ?? minutes) * 60)
    func o(_ subject: SubjectKey, _ kind: MetricKind, _ value: MetricValue) -> IncomingObservation {
        IncomingObservation(subject: subject, sessionRef: session, modelID: "claude-opus-5-5", kind: kind, value: value,
                            observedAt: at, receivedAt: receivedAt, evidence: .officialLocalTelemetry,
                            quality: { if case .absent = value { return .unknown } else { return .reported } }(),
                            sourceVersion: "2.1.302", dedupeKey: "\(session)|\(subject.canonical)|\(kind)|\(value.canonical)|\(minutes)")
    }
    let pool = SubjectKey.pool(providerPoolKey: fiveHourKey)
    return [o(pool, .quotaUsedPct, used.map { .percent($0) } ?? .absent(.providerOmitted)),
            o(pool, .resetAt, reset.map { .instant($0) } ?? .absent(.providerOmitted)),
            o(.session(sessionRef: session), .contextUsedPct, .percent(context))]
}

func meta(_ session: String) -> Store.SessionMeta { .init(sessionRef: session, modelID: "claude-opus-5-5", modelDisplayName: "Opus 5.5") }

func fiveHour(_ store: Store) async throws -> PoolState? {
    try await store.poolStates().first { $0.poolKey == fiveHourKey }
}

@Suite("Store: ledger, reduce, snapshot in one transaction")
struct StoreTests {
    let reset = t0.addingTimeInterval(2 * 3600)

    @Test("F08: two sessions on one pool show the latest value, never the sum")
    func twoSessions() async throws {
        let store = try Store.inMemory(now: t0)
        _ = try await store.ingest(batch(session: "A", used: 80, reset: reset, at: 0), session: meta("A"))
        _ = try await store.ingest(batch(session: "B", used: 83, reset: reset, context: 12, at: 0.5), session: meta("B"))
        let state = try #require(try await fiveHour(store))
        #expect(state.usedPct == 83 && state.limit == .approaching(.warning))
        let sessions = try await store.sessionStates()
        #expect(sessions.count == 2, "context stays per session")
        #expect(sessions.map { $0.values[.contextUsedPct]?.value } == [.percent(40), .percent(12)])
    }

    @Test("A replayed batch is dropped by the dedupe index and changes nothing")
    func dedupe() async throws {
        let store = try Store.inMemory(now: t0, policy: .everyReading)          // exercise the dedupe index itself
        let first = try await store.ingest(batch(session: "A", used: 50, reset: reset, at: 0), session: meta("A"))
        let before = try await store.projectionDump()
        let replay = try await store.ingest(batch(session: "A", used: 50, reset: reset, at: 0, received: 0.1), session: meta("A"))
        #expect(first.inserted == 3 && first.duplicates == 0)
        #expect(replay.inserted == 0 && replay.duplicates == 3)
        #expect(try await store.projectionDump() == before)
    }

    @Test("F09: an older sample arriving later is kept as history but never wins")
    func outOfOrder() async throws {
        let store = try Store.inMemory(now: t0)
        _ = try await store.ingest(batch(session: "A", used: 83, reset: reset, at: 10), session: meta("A"))
        let late = try await store.ingest(batch(session: "B", used: 80, reset: reset, at: 5, received: 11), session: meta("B"))
        #expect(late.inserted == 3, "the older sample is recorded")
        #expect(try await fiveHour(store)?.usedPct == 83)
    }

    @Test("No rate limits: unknown with a reason, no zero anywhere")
    func absent() async throws {
        let store = try Store.inMemory(now: t0)
        _ = try await store.ingest(batch(session: "A", used: nil, reset: nil, at: 0), session: meta("A"))
        let state = try #require(try await fiveHour(store))
        #expect(state.limit == .unknown && state.usedPct == nil && state.usedAbsence == .providerOmitted)
    }

    @Test("A timer tick moves an exhausted pool to reset expected once the reset time passes")
    func tickResets() async throws {
        let store = try Store.inMemory(now: t0)
        _ = try await store.ingest(batch(session: "A", used: 100, reset: reset, at: 0), session: meta("A"))
        let before = try await store.tick(now: reset.addingTimeInterval(-1))
        #expect(before.map(\.kind) == [.staleSource], "two silent hours: the source is stale, but no reset yet")
        let events = try await store.tick(now: reset)
        #expect(events.map(\.kind) == [.resetExpected])
        #expect(try await fiveHour(store)?.limit == .resetExpected)
    }

    @Test("Rebuild from the ledger reproduces the live projections byte for byte")
    func rebuildEqualsLive() async throws {
        let store = try Store.inMemory(now: t0)
        let newReset = t0.addingTimeInterval(130 * 60 + 5 * 3600)
        // A full cycle: rise, crossings, exhaustion, timer ticks, window dropped, ready again, a late older sample, a reschedule.
        let script: [(String, Decimal?, Date?, Double)] = [
            ("A", 70, reset, 0), ("B", 82, reset, 5), ("A", 96, reset, 20), ("A", 100, reset, 40),
            ("A", nil, nil, 125), ("B", 4, newReset, 131), ("A", 3, nil, 129), ("A", 6, newReset.addingTimeInterval(300), 140),
        ]
        // Arrival order follows the script; the 129-minute reading arrives at 133, after the 131-minute one.
        let arrivals: [Double] = [0, 5, 20, 40, 125, 131, 133, 140]
        for ((session, used, r, minutes), arrived) in zip(script, arrivals) {
            _ = try await store.ingest(batch(session: session, used: used, reset: r, at: minutes, received: arrived), session: meta(session))
            _ = try await store.tick(now: t0.addingTimeInterval((arrived + 1) * 60))
        }
        let now = t0.addingTimeInterval(200 * 60)
        _ = try await store.tick(now: now)
        let live = try await store.projectionDump()
        let liveState = try await fiveHour(store)
        try await store.rebuild(now: now)
        let rebuilt = try await store.projectionDump()
        if rebuilt != live {
            let a = live.split(separator: "\n"), b = rebuilt.split(separator: "\n")
            for (x, y) in zip(a, b) where x != y { print("LIVE   \(x)\nREBUILT\(y)") }
        }
        #expect(rebuilt == live, "rebuild must equal incremental processing")
        #expect(liveState?.limit == .available && liveState?.usedPct == 6)
        let kinds = try await store.events().map(\.kind)
        #expect(kinds.filter { $0 == .readyAgain }.count == 1)
        #expect(kinds.contains(.exhausted) && kinds.contains(.resetExpected) && kinds.contains(.windowRescheduled))
    }

    @Test("Reopening the database keeps the same account and connection")
    func reopen() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tk-store-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("pulse.sqlite").path
        let first = try Store(writer: try DatabasePool(path: path), now: t0)
        _ = try await first.ingest(batch(session: "A", used: 42, reset: reset, at: 0), session: meta("A"))
        let second = try Store(writer: try DatabasePool(path: path), now: t0)
        #expect(first.accountID == second.accountID && first.connectionID == second.connectionID)
        #expect(try await fiveHour(second)?.usedPct == 42)
    }
}
