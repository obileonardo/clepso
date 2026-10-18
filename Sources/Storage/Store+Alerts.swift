import Domain
import Foundation
import GRDB
import UsageEngine

/// Limit alerts' receipts (NOTIFICATIONS_AND_SCHEDULING §1.4): one row per alert shown, so a crossing is announced
/// once across restarts, and "ready again" can check that the window's limit was announced first (B4).
extension Store {
    public struct AlertHistory: Sendable, Equatable {
        public var delivered: Set<String> = []
        public var kinds: [UUID: Set<AlertKind>] = [:]
    }

    /// Delivered alerts since `since` (receipts are kept 30 days, B7).
    public func alertHistory(since: Date) throws -> AlertHistory {
        try writer.read { db in
            var history = AlertHistory()
            for row in try Row.fetchAll(db, sql: """
                SELECT dedupe_key, window_id, kind FROM notification_receipts
                WHERE channel = 'localNotification' AND outcome = 'delivered' AND decided_at >= ?
                """, arguments: [ms(since)]) {
                history.delivered.insert(row["dedupe_key"])
                if let w: String = row["window_id"], let window = UUID(uuidString: w), let kind = AlertKind(rawValue: row["kind"]) {
                    history.kinds[window, default: []].insert(kind)
                }
            }
            return history
        }
    }

    /// Records that `alert` was shown. Idempotent: the same dedup key is one row.
    public func recordAlert(_ alert: AlertCandidate, at now: Date) throws {
        try writer.write { db in
            let pool = try Row.fetchOne(db, sql: "SELECT id, account_id FROM allowance_pools WHERE provider_pool_key = ?", arguments: [alert.poolKey])
            try db.execute(sql: """
                INSERT OR IGNORE INTO notification_receipts (id, dedupe_key, channel, account_id, pool_id, window_id, kind, level, decided_at, outcome)
                VALUES (?, ?, 'localNotification', ?, ?, ?, ?, ?, ?, 'delivered')
                """, arguments: [UUID().uuidString, alert.dedupKey, (pool?["account_id"] as String?) ?? accountID.uuidString,
                                 pool?["id"] as String?, alert.windowID?.uuidString, alert.kind.rawValue, alert.level, ms(now)])
        }
    }
}
