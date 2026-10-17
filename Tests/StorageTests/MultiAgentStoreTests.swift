import Domain
import Foundation
import Testing
@testable import Storage

/// Increment 3.4: a second agent (Codex) gets its own account and connection; its pools live beside Claude Code's.
struct MultiAgentStoreTests {
    func codex(_ key: String, used: Decimal, reset: Date, at minutes: Double, connection: UUID) -> [IncomingObservation] {
        let at = t0.addingTimeInterval(minutes * 60)
        return [(MetricKind.quotaUsedPct, MetricValue.percent(used)), (.resetAt, .instant(reset))].map { kind, value in
            IncomingObservation(subject: .pool(providerPoolKey: key), sessionRef: nil, modelID: "gpt-5-codex", kind: kind, value: value,
                                observedAt: at, receivedAt: at, evidence: .officialLocalTelemetry, quality: .reported, sourceVersion: nil,
                                dedupeKey: "\(key)|\(kind)|\(value.canonical)|\(minutes)")
        }
    }

    @Test("Codex gets its own account and connection, created once")
    func connectionIsCreatedOnce() async throws {
        let store = try Store.inMemory(now: t0)
        let a = try await store.connection(adapterID: "codex.sessions", providerID: "openai", label: "Codex", now: t0)
        let b = try await store.connection(adapterID: "codex.sessions", providerID: "openai", label: "Codex", now: t0)
        #expect(a == b && a != store.connectionID)
        #expect(try await store.count("SELECT count(*) FROM accounts") == 2)
        #expect(try await store.count("SELECT count(*) FROM accounts WHERE provider_id = 'openai'") == 1)
    }

    @Test("Both agents' limits are reduced side by side, each under its own account")
    func twoProvidersSideBySide() async throws {
        let store = try Store.inMemory(now: t0)
        let codexConnection = try await store.connection(adapterID: "codex.sessions", providerID: "openai", label: "Codex", now: t0)
        let reset = t0.addingTimeInterval(4 * 3600)
        _ = try await store.ingest(batch(session: "A", used: 40, reset: reset, at: 0), session: meta("A"))
        _ = try await store.ingest(codex("codex.rate_limits.five_hour", used: 79, reset: reset, at: 1, connection: codexConnection),
                                   session: nil, connection: codexConnection)
        let r = try await store.ingest(codex("codex.rate_limits.five_hour", used: 83, reset: reset, at: 2, connection: codexConnection),
                                       session: nil, connection: codexConnection)
        #expect(r.events.contains { $0.kind == .thresholdCrossed }, "Codex crossing 80% fires like Claude Code's")
        let states = try await store.poolStates()
        #expect(states.first { $0.poolKey == "codex.rate_limits.five_hour" }?.usedPct == 83)
        #expect(states.first { $0.poolKey == "claude-code.rate_limits.five_hour" }?.usedPct == 40)
        #expect(try await store.count("""
            SELECT count(*) FROM allowance_pools p JOIN connections c ON c.account_id = p.account_id
            WHERE p.provider_pool_key = 'codex.rate_limits.five_hour' AND c.adapter_id = 'codex.sessions'
            """) == 1)
        #expect(try await store.count("SELECT count(*) FROM pool_snapshots s JOIN allowance_pools p ON p.id = s.pool_id WHERE s.account_id != p.account_id") == 0)
        #expect(try await store.count("SELECT count(*) FROM allowance_pools WHERE provider_pool_key LIKE 'codex.%' AND eligible_products = '[\"codex\"]'") == 1)
        #expect(try await store.usageHistory(poolKey: "codex.rate_limits.five_hour", since: t0).map(\.usedPct) == [79, 83])
    }

    @Test("A rebuild from the ledger gives the same states for both agents")
    func rebuildKeepsBoth() async throws {
        let store = try Store.inMemory(now: t0)
        let c = try await store.connection(adapterID: "codex.sessions", providerID: "openai", label: "Codex", now: t0)
        let reset = t0.addingTimeInterval(4 * 3600)
        _ = try await store.ingest(batch(session: "A", used: 81, reset: reset, at: 0), session: meta("A"))
        _ = try await store.ingest(codex("codex.rate_limits.seven_day", used: 96, reset: reset, at: 2, connection: c), session: nil, connection: c)
        let before = try await store.poolStates()
        try await store.rebuild(now: t0.addingTimeInterval(5 * 60))
        let after = try await store.poolStates()
        #expect(before.map(\.poolKey) == after.map(\.poolKey))
        #expect(before.map(\.usedPct) == after.map(\.usedPct))
        #expect(before.map(\.limit) == after.map(\.limit))
    }

    @Test("An unknown connection is refused and nothing is written")
    func unknownConnectionRefused() async throws {
        let store = try Store.inMemory(now: t0)
        await #expect(throws: StoreError.unknownConnection) {
            _ = try await store.ingest(codex("codex.rate_limits.five_hour", used: 1, reset: t0, at: 0, connection: UUID()), session: nil, connection: UUID())
        }
        #expect(try await store.count("SELECT count(*) FROM observations") == 0)
    }
}
