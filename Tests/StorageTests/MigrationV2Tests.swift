import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

/// Migration v2 (increment 1.7): the ledger is rebuilt to accept count, duration and flag values. DATA_MODEL §4
/// rule 3: no row may change. Proof: a v1 database with real ingest data dumps identically before and after.
struct MigrationV2Tests {
    static let t0 = Date(timeIntervalSince1970: 1_792_159_200)

    /// Every column of every ledger row, plus rowid, as text in rowid order.
    static func dump(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT rowid || '|' || id || '|' || IFNULL(pool_id,'-') || '|' || IFNULL(session_id,'-') || '|' || subject_kind || '|' ||
              IFNULL(model_id,'-') || '|' || metric_kind || '|' || value_kind || '|' || IFNULL(value_text,'-') || '|' ||
              IFNULL(absence_reason,'-') || '|' || observed_at || '|' || received_at || '|' || evidence || '|' || quality || '|' ||
              IFNULL(source_version,'-') || '|' || dedupe_key || '|' || IFNULL(metadata_json,'-')
            FROM observations ORDER BY rowid
            """)
    }

    @Test("v1 → v2 keeps every ledger row byte for byte, keeps the indexes, and then accepts the new value kinds")
    func rowsSurvive() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator().migrate(queue, upTo: "v1_initial")
        // Seed v1 the way the v1 store wrote rows: pool and session readings, absences included.
        try queue.write { db in
            try db.execute(sql: "INSERT INTO accounts (id, provider_id, kind, label, created_at) VALUES ('a', 'anthropic', 'personalSubscription', 'This Mac', 1)")
            try db.execute(sql: "INSERT INTO connections (id, account_id, adapter_id, state) VALUES ('c', 'a', 'claude-code.statusline', 'connected')")
            try db.execute(sql: "INSERT INTO allowance_pools (id, account_id, provider_pool_key, name, funding, window_type, created_at) VALUES ('p', 'a', 'claude-code.rate_limits.five_hour', '5-hour', 'includedSubscription', 'unknown', 1)")
            try db.execute(sql: "INSERT INTO sessions (id, account_id, connection_id, provider_session_key, first_seen_at, last_seen_at) VALUES ('s', 'a', 'c', '0123456789abcdef', 1, 1)")
            let rows: [(String, String?, String?, String, String, String?, String?)] = [
                ("pool", "p", nil, "quotaUsedPct", "percent", "14", nil),
                ("pool", "p", nil, "resetAt", "instant", "1792168200000", nil),
                ("pool", "p", nil, "quotaUsedPct", "absent", nil, "providerOmitted"),
                ("session", nil, "s", "contextTokens", "tokens", "729769", nil),
                ("session", nil, "s", "apiCostUSD", "usd", "22.7700407", nil),
            ]
            for (i, r) in rows.enumerated() {
                try db.execute(sql: """
                    INSERT INTO observations (id, account_id, connection_id, pool_id, session_id, subject_kind, model_id, metric_kind,
                      value_kind, value_text, absence_reason, observed_at, received_at, evidence, quality, source_version, dedupe_key)
                    VALUES (?, 'a', 'c', ?, ?, ?, 'claude-opus-5-5', ?, ?, ?, ?, ?, ?, 'officialLocalTelemetry', ?, '2.1.302', ?)
                    """, arguments: ["o\(i)", r.1, r.2, r.0, r.3, r.4, r.5, r.6, 1000 + i, 2000 + i,
                                     r.4 == "absent" ? "unknown" : "reported", "k\(i)"])
            }
            #expect(throws: (any Error).self, "v1 rejects the new kinds") {
                try db.execute(sql: "INSERT INTO observations (id, account_id, connection_id, session_id, subject_kind, metric_kind, value_kind, value_text, observed_at, received_at, evidence, quality, dedupe_key) VALUES ('x', 'a', 'c', 's', 'session', 'linesAdded', 'count', '1', 1, 1, 'e', 'reported', 'kx')")
            }
        }
        let before = try queue.read(Self.dump)
        #expect(before.count == 5)

        try Migrations.migrator().migrate(queue)

        #expect(try queue.read(Self.dump) == before, "every row identical after the rebuild")
        let indexes = try queue.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'observations' AND sql IS NOT NULL ORDER BY name") }
        #expect(indexes == ["idx_obs_pool_time", "idx_obs_received", "idx_obs_session_time", "uq_observations_dedupe"])
        try queue.write { db in
            for (i, (kind, text)) in [("count", "4740"), ("duration", "5271359"), ("flag", "1")].enumerated() {
                try db.execute(sql: "INSERT INTO observations (id, account_id, connection_id, session_id, subject_kind, metric_kind, value_kind, value_text, observed_at, received_at, evidence, quality, dedupe_key) VALUES (?, 'a', 'c', 's', 'session', 'linesAdded', ?, ?, 1, 1, 'e', 'reported', ?)",
                               arguments: ["n\(i)", kind, text, "kn\(i)"])
            }
            #expect(throws: (any Error).self, "the dedupe index still holds") {
                try db.execute(sql: "INSERT INTO observations (id, account_id, connection_id, session_id, subject_kind, metric_kind, value_kind, value_text, observed_at, received_at, evidence, quality, dedupe_key) VALUES ('dup', 'a', 'c', 's', 'session', 'linesAdded', 'count', '1', 1, 1, 'e', 'reported', 'k0')")
            }
            #expect(try Int.fetchOne(db, sql: "PRAGMA foreign_key_check") == nil, "no dangling references")
        }
    }

    @Test("The new values round-trip through the store and decode to the same MetricValue")
    func roundTrip() async throws {
        let store = try Store.inMemory(now: Self.t0)
        let values: [(MetricKind, MetricValue)] = [(.linesAdded, .count(4740)), (.wallDuration, .duration(milliseconds: 5_271_359)),
                                                   (.cacheWarm, .flag(true)), (.cacheHitPct, .percent(Decimal(string: "98.9")!))]
        let observations = values.map { kind, value in
            IncomingObservation(subject: .session(sessionRef: "0123456789abcdef"), sessionRef: "0123456789abcdef", modelID: nil,
                                kind: kind, value: value, observedAt: Self.t0, receivedAt: Self.t0, evidence: .officialLocalTelemetry,
                                quality: .reported, sourceVersion: "2.1.302", dedupeKey: "rt|\(kind.rawValue)")
        }
        _ = try await store.ingest(observations, session: Store.SessionMeta(sessionRef: "0123456789abcdef", modelID: nil, modelDisplayName: nil))
        let session = try #require(try await store.sessionStates().first)
        for (kind, value) in values { #expect(session.values[kind]?.value == value, "\(kind)") }
    }

    @Test("Opening an existing v1 database backs it up before migrating; a fresh database gets no backup")
    func backupBeforeMigrate() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mig-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("pulse.sqlite")
        do {
            let queue = try DatabaseQueue(path: url.path)
            try Migrations.migrator().migrate(queue, upTo: "v1_initial")
            try queue.write { try $0.execute(sql: "INSERT INTO preferences (key, value_json, updated_at) VALUES ('k', '1', 1)") }
        }
        _ = try Store.onDisk(at: url, now: Self.t0)
        let backup = folder.appendingPathComponent("pulse.sqlite.pre-v2_value_kinds_count_duration_flag.bak")
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect((try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int) == 0o600)
        let old = try DatabaseQueue(path: backup.path)
        #expect(try old.read { try String.fetchOne($0, sql: "SELECT value_json FROM preferences WHERE key = 'k'") } == "1")
        #expect(try old.read { try Migrations.migrator().appliedIdentifiers($0) } == ["v1_initial"], "the backup is the pre-migration file")

        let fresh = folder.appendingPathComponent("fresh.sqlite")
        _ = try Store.onDisk(at: fresh, now: Self.t0)
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: folder.path)).contains { $0.hasPrefix("fresh.sqlite.pre-") })
    }
}
