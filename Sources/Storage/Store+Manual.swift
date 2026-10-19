import Domain
import Foundation
import GRDB

extension Store {
    public func recordManualAllowance(_ value: ManualAllowance) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO manual_allowances
                  (id, provider_id, window_kind, used_pct, reset_at, observed_at, entered_at, plan_catalog_id, paid_overage)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [value.id.uuidString, value.providerID, value.window.rawValue,
                                   value.usedPercent.map { NSDecimalNumber(decimal: $0).stringValue }, value.resetsAt.map(ms),
                                   ms(value.observedAt), ms(value.enteredAt), value.planCatalogID, value.paidOverage ? 1 : 0])
        }
    }

    /// The latest measured value per provider/window; entering an older observation retains history without moving
    /// the current card backwards. A tie uses the last entry.
    public func manualAllowances() throws -> [ManualAllowance] {
        try writer.read { db in
            var seen = Set<String>()
            return try Row.fetchAll(db, sql: "SELECT * FROM manual_allowances ORDER BY observed_at DESC, entered_at DESC, rowid DESC").compactMap { row in
                let provider: String = row["provider_id"], kind: String = row["window_kind"]
                guard !seen.contains(provider + "|" + kind), let id = UUID(uuidString: row["id"]),
                      let window = ManualAllowance.Window(rawValue: kind),
                      let value = try? ManualAllowance(id: id, providerID: provider, window: window,
                          usedPercent: (row["used_pct"] as String?).flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) },
                          resetsAt: (row["reset_at"] as Int64?).map(date), observedAt: date(row["observed_at"] as Int64),
                          enteredAt: date(row["entered_at"] as Int64), planCatalogID: row["plan_catalog_id"], paidOverage: (row["paid_overage"] as Int) == 1)
                else { return nil }
                seen.insert(provider + "|" + kind)
                return value
            }
        }
    }

    /// Disconnect this manually tracked window, including its earlier entries, so an old value cannot reappear.
    public func removeManualAllowance(providerID: String, window: ManualAllowance.Window) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM manual_allowances WHERE provider_id = ? AND window_kind = ?", arguments: [providerID, window.rawValue])
        }
    }
}
