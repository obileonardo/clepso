import Foundation
import Storage

/// Users may shorten the approved retention defaults. Decoding is validated again before a purge, so a corrupt
/// preference cannot erase the ledger or keep personal data indefinitely.
public struct DataRetention: Codable, Sendable, Equatable {
    public var readings: Int = 90
    public var sessions: Int = 30
    public var receipts: Int = 30
    public var logs: Int = 7
    public init() {}

    public static let readingOptions = [7, 30, 90]
    public static let sessionOptions = [7, 14, 30]
    public static let logOptions = [1, 3, 7]

    public var validated: Self {
        var value = self
        if !Self.readingOptions.contains(value.readings) { value.readings = 90 }
        if !Self.sessionOptions.contains(value.sessions) { value.sessions = 30 }
        if !Self.sessionOptions.contains(value.receipts) { value.receipts = 30 }
        if !Self.logOptions.contains(value.logs) { value.logs = 7 }
        return value
    }

    var storePolicy: Store.Retention {
        let value = validated
        var policy = Store.Retention()
        policy.readings = TimeInterval(value.readings) * 86_400
        policy.sessions = TimeInterval(value.sessions) * 86_400
        policy.receipts = TimeInterval(value.receipts) * 86_400
        return policy
    }
}
