import CryptoKit
import Foundation

/// Wraps a value that must never reach a log, description or export in clear (PRIVACY_AND_SECURITY §5).
/// Not `Codable` by design: putting one in a persisted or exported model is a compile error.
/// `unsafeReveal` call sites are enumerated by `make ci` and allowed only where §5 says.
public struct Redacted<T: Sendable>: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let value: T
    public let label: String

    public init(_ value: T, label: String) {
        self.value = value
        self.label = label
    }

    public var description: String { "<redacted:\(label)>" }
    public var debugDescription: String { description }
    /// `dump()` and debuggers see the label only.
    public var customMirror: Mirror { Mirror(self, children: ["label": label]) }

    /// Only consumers with a legitimate need call this; the reason is part of the grep-able call site.
    public func unsafeReveal(reason: StaticString) -> T { value }

    /// A stable, non-reversible digest for correlating log lines: first 12 hex characters of SHA-256.
    public var fingerprint: String {
        SHA256.hash(data: Data(String(describing: value).utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
