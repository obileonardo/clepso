import Domain
import Foundation
import Testing
@testable import Storage

/// Increment 1.7c: the ledger keeps changes and check-ins, not every repeat (DATA_MODEL §6.4).
struct LedgerPolicyTests {
    func rows(_ store: Store, _ sql: String) async throws -> Int {
        try await store.count(sql)
    }

    @Test("An hour of unchanged frames every 8 s keeps a check-in every 2 minutes, not 450 copies")
    func unchangedFramesAreThinned() async throws {
        let store = try Store.inMemory(now: t0)
        let reset = t0.addingTimeInterval(4 * 3600)
        var stored = 0, skipped = 0
        for i in 0..<450 {                                   // 450 × 8 s = 60 min
            let r = try await store.ingest(batch(session: "A", used: 40, reset: reset, at: Double(i) * 8 / 60), session: meta("A"))
            stored += r.inserted; skipped += r.unchanged
        }
        let poolRows = try await store.count("SELECT count(*) FROM observations WHERE subject_kind = 'pool'")
        // First frame plus one pair per 120 s: 1 + 29 pairs (the 30th falls at exactly 60 min, outside the hour).
        #expect(poolRows == 2 * 30, "\(poolRows)")
        #expect(stored + skipped == 450 * 3)
        let state = try #require(try await store.poolStates().first)
        #expect(state.usedPct == 40)
        #expect(t0.addingTimeInterval(59 * 60).timeIntervalSince(state.lastProviderMeasured ?? .distantPast) < 120, "freshness kept by check-ins")
    }

    @Test("A change in used % is stored at once, even seconds after the last row, and drives the engine")
    func changesStoredImmediately() async throws {
        let store = try Store.inMemory(now: t0)
        let reset = t0.addingTimeInterval(4 * 3600)
        _ = try await store.ingest(batch(session: "A", used: 79, reset: reset, at: 0), session: meta("A"))
        let r = try await store.ingest(batch(session: "A", used: 81, reset: reset, at: 10.0 / 60), session: meta("A"))
        #expect(r.inserted >= 2, "the pool pair is stored together")
        #expect(r.events.contains { $0.kind == .thresholdCrossed }, "the 80% crossing fires at once")
        // The reset time alone changing also stores the pair.
        let moved = try await store.ingest(batch(session: "A", used: 81, reset: reset.addingTimeInterval(3600), at: 20.0 / 60), session: meta("A"))
        #expect(moved.inserted >= 2)
    }

    @Test("Session metrics: a change within the minute waits; after a minute it is stored")
    func sessionMinInterval() async throws {
        let store = try Store.inMemory(now: t0)
        _ = try await store.ingest(batch(session: "A", used: 40, reset: nil, context: 40, at: 0), session: meta("A"))
        let soon = try await store.ingest(batch(session: "A", used: 40, reset: nil, context: 41, at: 30.0 / 60), session: meta("A"))
        #expect(try await store.count("SELECT count(*) FROM observations WHERE metric_kind = 'contextUsedPct'") == 1)
        #expect(soon.unchanged >= 1)
        _ = try await store.ingest(batch(session: "A", used: 40, reset: nil, context: 42, at: 61.0 / 60), session: meta("A"))
        #expect(try await store.count("SELECT count(*) FROM observations WHERE metric_kind = 'contextUsedPct'") == 2)
        #expect(try await store.sessionStates().first?.values[.contextUsedPct]?.value == .percent(42))
    }

    @Test("Live state still equals a rebuild from the thinned ledger")
    func rebuildStillMatches() async throws {
        let store = try Store.inMemory(now: t0)
        let reset = t0.addingTimeInterval(30 * 60)
        let used: [Decimal] = [10, 10, 10, 50, 50, 79, 81, 81, 96, 100, 100, 100, 3, 3, 3]
        for (i, u) in used.enumerated() {
            _ = try await store.ingest(batch(session: "A", used: u, reset: i < 12 ? reset : reset.addingTimeInterval(5 * 3600), at: Double(i) * 3), session: meta("A"))
        }
        _ = try await store.tick(now: t0.addingTimeInterval(50 * 60))
        let live = try await store.projectionDump()
        try await store.rebuild(now: t0.addingTimeInterval(50 * 60))
        #expect(try await store.projectionDump() == live)
    }
}

struct RetentionTests {
    @Test("Purge drops pool readings after 90 days and sessions after 30, keeps the rest and the current state")
    func purge() async throws {
        let store = try Store.inMemory(now: t0, policy: .everyReading)
        let day: Double = 24 * 60
        for (session, minutesAgo) in [("old", 100 * day), ("mid", 40 * day), ("new", 1 * day)] {
            _ = try await store.ingest(batch(session: session, used: 20, reset: nil, at: -minutesAgo), session: meta(session))
        }
        let now = t0
        let before = try await store.poolStates()
        let report = try await store.purge(now: now)
        #expect(report.sessions == 1, "the 100-day session goes; the 40-day one still delivered pool readings that are kept")
        #expect(try await store.count("SELECT count(*) FROM observations WHERE subject_kind = 'pool'") == 4, "the 40-day and 1-day pairs stay")
        #expect(try await store.count("SELECT count(*) FROM observations WHERE subject_kind = 'session'") == 1)
        #expect(try await store.count("SELECT count(*) FROM session_snapshots") == 1, "only the recent session keeps a snapshot")
        #expect(try await store.sessionSummaries(limit: 10).map(\.sessionRef) == ["new", "mid"])
        #expect(try await store.poolStates() == before, "projections untouched")
        #expect(try await store.purge(now: now) == Store.PurgeReport(), "a second purge finds nothing")
    }
}
