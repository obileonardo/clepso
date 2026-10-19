import Domain
import Foundation
import GRDB

/// Readings by the route they came (docs/specs/mod-bridge.md §7, §8).
extension Store {
    /// When a reading last arrived through `channel` (the ledger's `metadata_json`), or nil if none ever did. Settings
    /// uses it to say whether the desktop app has reported since the mod was turned on.
    public func lastReading(channel: ObservationChannel) throws -> Date? {
        guard let metadata = Self.metadata(channel) else { return nil }
        return try writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT MAX(received_at) FROM observations WHERE metadata_json = ?", arguments: [metadata])
        }.map(date)
    }
}
