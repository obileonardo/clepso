import Domain
import Foundation
import GRDB
import UsageEngine

extension Store {
    /// Persist the schedules successfully accepted by the notification center, with their source observation.
    /// Clock passage never means delivered: only an actual notification returned by the OS can write that receipt.
    public func recordNotificationSchedules(_ plans: [ReminderPlanner.Planned], now: Date, enabled: Bool, activeIdentifiers: Set<String>? = nil) throws {
        try writer.write { db in
            let wanted = Set(plans.map(\.identifier))
            for row in try Row.fetchAll(db, sql: "SELECT id, reset_at, lead_minutes FROM reset_schedules WHERE channel = 'localNotification' AND status = 'planned'") {
                let id: String = row["id"]
                guard !wanted.contains(id) else { continue }
                let fireAt = date(row["reset_at"] as Int64).addingTimeInterval(-Double(row["lead_minutes"] as Int) * 60)
                let status: String
                if !enabled || activeIdentifiers.map({ !$0.contains(id) }) == true || fireAt > now { status = "cancelled" }
                else if now.timeIntervalSince(fireAt) > ReminderPlanner.staleAfter { status = "expired_stale" }
                else { continue } // the OS may be delivering it right now
                try db.execute(sql: "UPDATE reset_schedules SET status = ?, updated_at = ? WHERE id = ?", arguments: [status, ms(now), id])
            }
            for plan in plans {
                guard let pool = try Row.fetchOne(db, sql: "SELECT id, account_id FROM allowance_pools WHERE provider_pool_key = ?", arguments: [plan.poolKey]),
                      let source = try Row.fetchOne(db, sql: "SELECT id, observed_at FROM observations WHERE pool_id = ? AND metric_kind = 'quotaUsedPct' ORDER BY observed_at DESC, rowid DESC LIMIT 1", arguments: [pool["id"] as String]) else { continue }
                try db.execute(sql: """
                    INSERT INTO reset_schedules
                      (id, account_id, pool_id, window_id, source_observation_id, reset_at, source_verified_at, channel, kind, lead_minutes, mode, status, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 'localNotification', ?, ?, 'managed', 'planned', ?, ?)
                    ON CONFLICT (id) DO UPDATE SET
                      source_observation_id = excluded.source_observation_id, source_verified_at = excluded.source_verified_at,
                      reset_at = excluded.reset_at, lead_minutes = excluded.lead_minutes,
                      status = CASE WHEN reset_schedules.status = 'delivered' THEN 'delivered' ELSE 'planned' END,
                      version = reset_schedules.version + CASE WHEN reset_schedules.reset_at != excluded.reset_at OR reset_schedules.lead_minutes != excluded.lead_minutes THEN 1 ELSE 0 END,
                      updated_at = excluded.updated_at
                    ON CONFLICT (account_id, pool_id, reset_at, channel, kind) DO UPDATE SET
                      id = excluded.id, window_id = excluded.window_id, source_observation_id = excluded.source_observation_id,
                      source_verified_at = excluded.source_verified_at, lead_minutes = excluded.lead_minutes,
                      status = CASE WHEN reset_schedules.status = 'delivered' THEN 'delivered' ELSE 'planned' END,
                      version = reset_schedules.version + CASE WHEN reset_schedules.lead_minutes != excluded.lead_minutes THEN 1 ELSE 0 END,
                      updated_at = excluded.updated_at
                    """, arguments: [plan.identifier, pool["account_id"] as String, pool["id"] as String,
                                       plan.windowID.uuidString, source["id"] as String, ms(plan.resetsAt), source["observed_at"] as Int64,
                                       plan.kind.rawValue, plan.leadMinutes, ms(now), ms(now)])
            }
        }
    }

    /// A receipt from the OS, never inferred from a missing pending request or an elapsed timer. A cancelled or
    /// unrecognised schedule cannot qualify a window for Ready again.
    public func recordScheduledDelivery(identifier: String, deliveredAt: Date, now: Date) throws {
        try writer.write { db in
            guard deliveredAt <= now,
                  let row = try Row.fetchOne(db, sql: "SELECT * FROM reset_schedules WHERE id = ? AND channel = 'localNotification' AND status IN ('planned','delivered')", arguments: [identifier]) else { return }
            let fireAt = date(row["reset_at"] as Int64).addingTimeInterval(-Double(row["lead_minutes"] as Int) * 60)
            guard deliveredAt >= fireAt,
                  deliveredAt.timeIntervalSince(fireAt) <= AlertKind.resetReminder.maxAge else { return }
            try db.execute(sql: """
                INSERT OR IGNORE INTO notification_receipts
                  (id, dedupe_key, channel, account_id, pool_id, window_id, kind, level, decided_at, outcome)
                VALUES (?, ?, 'localNotification', ?, ?, ?, ?, NULL, ?, 'delivered')
                """, arguments: [UUID().uuidString, identifier, row["account_id"] as String, row["pool_id"] as String,
                                   row["window_id"] as String?, row["kind"] as String, ms(deliveredAt)])
            try db.execute(sql: "UPDATE reset_schedules SET status = 'delivered', updated_at = ? WHERE id = ?", arguments: [ms(now), identifier])
        }
    }
}
