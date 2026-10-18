import Domain
import Foundation
import GRDB
import UsageEngine

/// Limit alerts' receipts (NOTIFICATIONS_AND_SCHEDULING §1.4): one row per alert shown, so a crossing is announced
/// once across restarts, and "ready again" can check that the window's limit was announced first (B4).
extension Store {
    public struct AlertHistory: Sendable, Equatable {
        /// Every key already decided: shown, held for the quiet-hours digest, or dropped as too old. Either way it is
        /// never planned again.
        public var delivered: Set<String> = []
        /// Kinds actually shown per window; a dropped alert was never seen, so it doesn't count for B4.
        public var kinds: [UUID: Set<AlertKind>] = [:]
    }

    /// How an alert was settled: shown, held back because its event was too old (`AlertKind.maxAge`), or held for the
    /// digest at the end of quiet hours (§1.6).
    public enum AlertOutcome: String, Sendable { case delivered, staleDropped = "stale_dropped", quietDeferred = "quiet_deferred" }

    /// Decided alerts since `since` (receipts are kept 30 days, B7).
    public func alertHistory(since: Date) throws -> AlertHistory {
        try writer.read { db in
            var history = AlertHistory()
            for row in try Row.fetchAll(db, sql: """
                SELECT dedupe_key, window_id, kind, outcome FROM notification_receipts
                WHERE channel = 'localNotification' AND outcome IN ('delivered', 'stale_dropped', 'quiet_deferred') AND decided_at >= ?
                """, arguments: [ms(since)]) {
                history.delivered.insert(row["dedupe_key"])
                if row["outcome"] as String == AlertOutcome.delivered.rawValue, let w: String = row["window_id"], let window = UUID(uuidString: w), let kind = AlertKind(rawValue: row["kind"]) {
                    history.kinds[window, default: []].insert(kind)
                }
            }
            return history
        }
    }

    /// Records how `alert` was settled. Idempotent: the same dedup key is one row.
    public func recordAlert(_ alert: AlertCandidate, at now: Date, outcome: AlertOutcome = .delivered) throws {
        try writer.write { db in
            let pool = try Row.fetchOne(db, sql: "SELECT id, account_id FROM allowance_pools WHERE provider_pool_key = ?", arguments: [alert.poolKey])
            try db.execute(sql: """
                INSERT OR IGNORE INTO notification_receipts (id, dedupe_key, channel, account_id, pool_id, window_id, kind, level, decided_at, outcome)
                VALUES (?, ?, 'localNotification', ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [UUID().uuidString, alert.dedupKey, (pool?["account_id"] as String?) ?? accountID.uuidString,
                                 pool?["id"] as String?, alert.windowID?.uuidString, alert.kind.rawValue, alert.level, ms(now),
                                 outcome.rawValue])
        }
    }

    // MARK: - Quiet-hours digest (§1.6)

    /// One alert quiet hours held back.
    public struct DeferredAlert: Sendable, Equatable {
        public let poolKey: String
        public let kind: AlertKind
        public let level: Int?
        public let deferredAt: Date
    }

    /// Alerts held for the digest since the last digest was settled (shown or dropped), oldest first.
    public func deferredAlerts() throws -> [DeferredAlert] {
        try writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT dedupe_key, kind, level, decided_at FROM notification_receipts
                WHERE channel = 'localNotification' AND outcome = 'quiet_deferred'
                  AND decided_at > IFNULL((SELECT MAX(decided_at) FROM notification_receipts WHERE channel = 'digest'), -1)
                ORDER BY decided_at, dedupe_key
                """).compactMap { row in
                guard let kind = AlertKind(rawValue: row["kind"]),
                      let pool = (row["dedupe_key"] as String).split(separator: "|").first else { return nil }
                return DeferredAlert(poolKey: String(pool), kind: kind, level: row["level"], deferredAt: date(row["decided_at"] as Int64))
            }
        }
    }

    /// Settles every alert held so far: the digest was shown, or dropped as too old. One row on the `digest` channel.
    public func recordDigest(at now: Date, outcome: AlertOutcome) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO notification_receipts (id, dedupe_key, channel, account_id, kind, decided_at, outcome)
                VALUES (?, ?, 'digest', ?, 'digest', ?, ?)
                """, arguments: [UUID().uuidString, "digest|\(ms(now))", accountID.uuidString, ms(now), outcome.rawValue])
        }
    }
}
