import Domain
import Foundation
import GRDB
import UsageEngine

/// Reads and small writes the app shell needs (increment 1.4): opening the database file, the
/// provenance inspector's recent readings, sessions, the selected plan and preferences.
extension Store {
    /// Opens (or creates) the database at `url`. The folder is 0700 and the file 0600 (PRIVACY_AND_SECURITY §4).
    public static func onDisk(at url: URL, now: Date, config: EngineConfig = EngineConfig()) throws -> Store {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Wait out a brief lock held by another process (the `pulse` CLI, an export) instead of failing at once.
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return try Store(writer: queue, config: config, now: now)
    }

    // MARK: - Ledger reads

    /// One stored reading, as the inspector shows it (UX_SPEC §2.6).
    public struct Reading: Sendable, Equatable {
        public let value: MetricValue
        public let observedAt: Date
        public let receivedAt: Date
        public let evidence: EvidenceKind
        public let quality: Quality
        public let sourceVersion: String?
    }

    /// The newest `limit` readings of one metric for one pool, newest first.
    public func recentReadings(poolKey: String, kind: MetricKind, limit: Int) throws -> [Reading] {
        try writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT o.*, a.provider_pool_key, NULL AS provider_session_key FROM observations o JOIN allowance_pools a ON a.id = o.pool_id
                WHERE a.account_id = ? AND a.provider_pool_key = ? AND o.metric_kind = ?
                ORDER BY o.observed_at DESC, o.received_at DESC, o.rowid DESC LIMIT ?
                """, arguments: [accountID.uuidString, poolKey, kind.rawValue, limit])
            .compactMap { row in
                Self.decode(row).map { Reading(value: $0.value, observedAt: $0.observedAt, receivedAt: $0.receivedAt,
                                                 evidence: $0.evidence, quality: $0.quality, sourceVersion: $0.sourceVersion) }
            }
        }
    }

    /// The Claude Code version on the newest reading of any kind.
    public func latestSourceVersion() throws -> String? {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT source_version FROM observations WHERE source_version IS NOT NULL ORDER BY received_at DESC, rowid DESC LIMIT 1")
        }
    }

    /// When the connection last delivered a frame.
    public func lastEventAt() throws -> Date? {
        try writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT last_event_at FROM connections WHERE id = ?", arguments: [connectionID.uuidString]).map(date)
        }
    }

    public struct SessionSummary: Sendable, Equatable {
        public let sessionRef: String
        public let modelDisplayName: String?
        public let lastSeen: Date
    }

    /// Sessions, most recently seen first.
    public func sessionSummaries(limit: Int) throws -> [SessionSummary] {
        try writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT provider_session_key, model_display_name, last_seen_at FROM sessions
                WHERE connection_id = ? ORDER BY last_seen_at DESC LIMIT ?
                """, arguments: [connectionID.uuidString, limit])
            .map { SessionSummary(sessionRef: $0["provider_session_key"], modelDisplayName: $0["model_display_name"], lastSeen: date($0["last_seen_at"])) }
        }
    }

    // MARK: - Plan (PLAN_CATALOG §4: user-confirmed or selected; never inferred)

    public struct PlanIdentity: Sendable, Equatable {
        public let catalogID: String
        public let displayName: String
        public let evidence: EvidenceKind
        public let effectiveFrom: Date
    }

    public func currentPlan() throws -> PlanIdentity? {
        try writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT plan_catalog_id, display_plan_name, evidence, effective_from FROM subscription_identities
                WHERE account_id = ? AND effective_until IS NULL ORDER BY effective_from DESC LIMIT 1
                """, arguments: [accountID.uuidString])
            .flatMap { row in
                guard let id: String = row["plan_catalog_id"], let name: String = row["display_plan_name"],
                      let evidence = EvidenceKind(rawValue: row["evidence"]) else { return nil }
                return PlanIdentity(catalogID: id, displayName: name, evidence: evidence, effectiveFrom: date(row["effective_from"]))
            }
        }
    }

    /// Ends the current plan and, unless `plan` is nil ("Not sure"), starts a new one. History is never rewritten.
    public func setPlan(catalogID: String?, displayName: String?, evidence: EvidenceKind, now: Date) throws {
        precondition(evidence == .userConfirmed || evidence == .userSelectedUnverified, "a plan is only ever chosen by the user in Stage A")
        try writer.write { db in
            try db.execute(sql: "UPDATE subscription_identities SET effective_until = ? WHERE account_id = ? AND effective_until IS NULL",
                           arguments: [ms(now), accountID.uuidString])
            guard let catalogID, let displayName else { return }
            try db.execute(sql: """
                INSERT INTO subscription_identities (id, account_id, provider_id, account_kind, plan_catalog_id, display_plan_name,
                  evidence, verified_at, effective_from) VALUES (?, ?, 'anthropic', 'personalSubscription', ?, ?, ?, ?, ?)
                """, arguments: [UUID().uuidString, accountID.uuidString, catalogID, displayName, evidence.rawValue,
                                 evidence == .userConfirmed ? ms(now) : nil, ms(now)])
        }
    }

    // MARK: - Preferences

    public func preference<T: Decodable & Sendable>(_ key: String, as type: T.Type) throws -> T? {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT value_json FROM preferences WHERE key = ?", arguments: [key])
                .flatMap { try? JSONDecoder().decode(T.self, from: Data($0.utf8)) }
        }
    }

    public func setPreference<T: Encodable & Sendable>(_ key: String, _ value: T, now: Date) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO preferences (key, value_json, updated_at) VALUES (?, ?, ?)",
                           arguments: [key, Self.encode(value), ms(now)])
        }
    }
}

// MARK: - Export and close (PRIVACY_AND_SECURITY §8)

/// One exported cell. Blobs are never exported.
public enum ExportValue: Sendable, Equatable {
    case null, integer(Int64), real(Double), text(String)
}

extension Store {
    /// §8 step 2: exactly these tables, nothing else.
    public static let exportTables = ["accounts", "observations", "pool_snapshots", "sessions", "notification_receipts", "preferences"]
    /// Internal bookkeeping with no meaning to the user (a content hash used for dedupe).
    static let exportExcludedColumns: [String: Set<String>] = ["observations": ["dedupe_key"]]

    public func exportRows() throws -> [(table: String, rows: [[String: ExportValue]])] {
        try writer.read { db in
            try Self.exportTables.map { table in
                let excluded = Self.exportExcludedColumns[table] ?? []
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY rowid").map { row in
                    var out: [String: ExportValue] = [:]
                    for column in row.columnNames where !excluded.contains(column) {
                        out[column] = switch (row[column] as DatabaseValue).storage {
                        case .int64(let n): .integer(n)
                        case .double(let d): .real(d)
                        case .string(let text): .text(text)
                        case .null, .blob: .null
                        }
                    }
                    return out
                }
                return (table, rows)
            }
        }
    }

    /// The SQLite result code behind a storage error, for the diagnostics log (never the message, which can hold SQL or paths).
    public static func sqliteCode(of error: Error) -> Int32? {
        (error as? DatabaseError)?.resultCode.primaryResultCode.rawValue
    }

    /// Closes the database so delete-all can remove the file. The store is unusable afterwards.
    public func close() throws {
        try writer.close()
    }
}
