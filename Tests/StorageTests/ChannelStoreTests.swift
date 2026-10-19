import Domain
import Foundation
import GRDB
import Testing
import UsageEngine
@testable import Storage

/// v0.3 (docs/specs/mod-bridge.md §7): the route a reading came by is kept in the ledger (`metadata_json`), so the
/// one-source-per-window rule gives the same result live and after a rebuild.
@Suite("Store: readings from the mod")
struct ChannelStoreTests {
    let reset = t0.addingTimeInterval(2 * 3600)

    /// `batch` from StoreTests, on the given channel.
    func on(_ channel: ObservationChannel?, _ observations: [IncomingObservation]) -> [IncomingObservation] {
        observations.map {
            IncomingObservation(subject: $0.subject, sessionRef: $0.sessionRef, modelID: $0.modelID, kind: $0.kind, value: $0.value,
                                observedAt: $0.observedAt, receivedAt: $0.receivedAt, evidence: $0.evidence, quality: $0.quality,
                                sourceVersion: $0.sourceVersion, dedupeKey: $0.dedupeKey + "|\(channel?.rawValue ?? "sl")", channel: channel)
        }
    }

    @Test("A terminal and a desktop session on one pool: the status line holds it for 60 s, then the mod's reading counts")
    func holdThenApply() async throws {
        let store = try Store.inMemory(now: t0, policy: .everyReading)
        _ = try await store.ingest(on(nil, batch(session: "T", used: 26, reset: reset, at: 0)), session: meta("T"))
        _ = try await store.ingest(on(.mod, batch(session: "D", used: 27, reset: reset, at: 0.5)), session: meta("D"))
        #expect(try await fiveHour(store)?.usedPct == 26)
        _ = try await store.ingest(on(.mod, batch(session: "D", used: 28, reset: reset, at: 2)), session: meta("D"))
        #expect(try await fiveHour(store)?.usedPct == 28)
        #expect(try await store.lastReading(channel: .mod) == t0.addingTimeInterval(120))
    }

    @Test("The channel round-trips through the ledger, and rebuild equals live with both channels mixed")
    func rebuildEqualsLive() async throws {
        let store = try Store.inMemory(now: t0, policy: .everyReading)
        let steps: [(ObservationChannel?, String, Decimal, Double)] = [
            (nil, "T", 26, 0), (.mod, "D", 27, 0.3), (.mod, "D", 27, 0.8), (nil, "T", 27, 1), (.mod, "D", 29, 3), (nil, "T", 29, 3.2),
        ]
        for (channel, session, used, minute) in steps {
            _ = try await store.ingest(on(channel, batch(session: session, used: used, reset: reset, at: minute)), session: meta(session))
        }
        let live = try await store.projectionDump()
        try await store.rebuild(now: t0.addingTimeInterval(4 * 60))
        #expect(try await store.projectionDump() == live)
        let channels = try await store.storedChannels()
        #expect(channels.filter { $0 == "{\"channel\":\"mod\"}" }.count == 9, "three mod frames, three rows each")
        #expect(channels.filter { $0 == nil }.count == 9)
    }

    @Test("No mod reading yet: nil")
    func none() async throws {
        let store = try Store.inMemory(now: t0)
        _ = try await store.ingest(batch(session: "T", used: 26, reset: reset, at: 0), session: meta("T"))
        #expect(try await store.lastReading(channel: .mod) == nil)
    }
}

extension Store {
    /// Every observation's `metadata_json`, in ledger order (tests only).
    func storedChannels() throws -> [String?] {
        try writer.read { try String?.fetchAll($0, sql: "SELECT metadata_json FROM observations ORDER BY rowid") }
    }
}
