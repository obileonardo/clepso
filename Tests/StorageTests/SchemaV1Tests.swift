import Foundation
import GRDB
import Testing
@testable import Storage

@Suite("Schema v1 under GRDB")
struct SchemaV1Tests {
    func migratedQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try Migrations.migrator().migrate(queue)
        return queue
    }

    func seed(_ db: Database) throws {
        try db.execute(sql: """
            INSERT INTO accounts (id, provider_id, kind, label, created_at) VALUES ('acc', 'anthropic', 'personalSubscription', 'This Mac', 0);
            INSERT INTO connections (id, account_id, adapter_id, state) VALUES ('con', 'acc', 'claude-code.statusline', 'connected');
            INSERT INTO allowance_pools (id, account_id, provider_pool_key, name, funding, window_type, created_at)
              VALUES ('pool5h', 'acc', 'claude-code.rate_limits.five_hour', '5-hour', 'includedSubscription', 'unknown', 0);
            """)
    }

    func insertObservation(_ db: Database, id: String, dedupe: String,
                           valueKind: String = "percent", valueText: String? = "83", absence: String? = nil) throws {
        try db.execute(sql: """
            INSERT INTO observations (id, account_id, connection_id, pool_id, subject_kind, metric_kind, value_kind,
              value_text, absence_reason, observed_at, received_at, evidence, quality, dedupe_key)
            VALUES (?, 'acc', 'con', 'pool5h', 'pool', 'quotaUsedPct', ?, ?, ?, 1000, 1001, 'officialLocalTelemetry', 'reported', ?)
            """, arguments: [id, valueKind, valueText, absence, dedupe])
    }

    @Test("Migration v1 creates every table in DATA_MODEL §3")
    func tablesExist() throws {
        let names = try migratedQueue().read { db in
            try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'grdb_%' AND name NOT LIKE 'sqlite_%'")
        }
        let expected: Set = ["accounts", "connections", "sessions", "allowance_pools", "pool_windows", "observations",
                             "pool_snapshots", "session_snapshots", "derived_events", "notification_receipts",
                             "alert_suppressions", "subscription_identities", "plan_catalog_versions", "entitlements",
                             "entitlement_pool_links", "reset_schedules", "calendar_sync_receipts", "connector_health",
                             "preferences", "devices", "sync_cursors",
                             "agent_tasks", "agent_runs"]                // migration v3 (increment 1.9)
        #expect(names == expected)
    }

    @Test("A duplicate dedupe_key is rejected by the UNIQUE index")
    func dedupe() throws {
        try migratedQueue().write { db in
            try seed(db)
            try insertObservation(db, id: "o1", dedupe: "k1")
            #expect(throws: DatabaseError.self) { try insertObservation(db, id: "o2", dedupe: "k1") }
            try db.execute(sql: "INSERT OR IGNORE INTO observations SELECT 'o3', account_id, connection_id, pool_id, session_id, subject_kind, model_id, metric_kind, value_kind, value_text, absence_reason, observed_at, received_at, evidence, quality, source_version, dedupe_key, metadata_json FROM observations WHERE id = 'o1'")
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM observations") == 1)
        }
    }

    @Test("Absent values must carry a reason and no value text")
    func absenceChecks() throws {
        try migratedQueue().write { db in
            try seed(db)
            try insertObservation(db, id: "ok", dedupe: "a1", valueKind: "absent", valueText: nil, absence: "providerOmitted")
            #expect(throws: DatabaseError.self) {
                try insertObservation(db, id: "bad1", dedupe: "a2", valueKind: "absent", valueText: "0", absence: "providerOmitted")
            }
            #expect(throws: DatabaseError.self) {
                try insertObservation(db, id: "bad2", dedupe: "a3", valueKind: "absent", valueText: nil, absence: nil)
            }
        }
    }

    @Test("Foreign keys are enforced")
    func foreignKeys() throws {
        try migratedQueue().write { db in
            _ = #expect(throws: DatabaseError.self) {
                try db.execute(sql: "INSERT INTO connections (id, account_id, adapter_id, state) VALUES ('c', 'missing', 'x', 'connected')")
            }
        }
    }

    @Test("One notification receipt per dedupe key and channel")
    func receiptUniqueness() throws {
        try migratedQueue().write { db in
            let insert = """
                INSERT INTO notification_receipts (id, dedupe_key, channel, account_id, kind, level, decided_at, outcome)
                VALUES (?, 'acc|pool|W1|approaching|80', ?, 'acc', 'approaching', 80, 0, 'delivered')
                """
            try db.execute(sql: insert, arguments: ["r1", "localNotification"])
            try db.execute(sql: insert, arguments: ["r2", "push"])
            #expect(throws: DatabaseError.self) { try db.execute(sql: insert, arguments: ["r3", "localNotification"]) }
        }
    }

    @Test("A file database opens in WAL mode")
    func walMode() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pool = try Migrations.openPool(at: dir.appendingPathComponent("pulse.sqlite").path)
        #expect(try pool.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") } == "wal")
    }
}
