import CryptoKit
import Foundation

/// Local phone cache binding. The opaque account digest never goes to the Watch or mobile relay.
/// A previous account's cache must not be shown while signing in to a different account on the same phone.
public struct CompanionCache: Codable, Sendable {
    private let accountDigest: String
    private let envelope: RelayEnvelope
    public init(accountID: String, envelope: RelayEnvelope) {
        accountDigest = Self.digest(accountID); self.envelope = envelope
    }
    public func reading(for accountID: String) -> RelayEnvelope? {
        guard !accountID.isEmpty, Self.digest(accountID) == accountDigest, envelope.valid else { return nil }
        return envelope
    }
    private static func digest(_ id: String) -> String { SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() }
}
