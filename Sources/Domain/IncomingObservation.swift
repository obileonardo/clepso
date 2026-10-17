import Foundation

/// What an observation is about, named by its provider key rather than a database id. The store
/// resolves keys to `AllowancePool` / `Session` ids inside its transaction (DATA_MODEL §5, §5.1).
public enum SubjectKey: Sendable, Hashable, Codable {
    case pool(providerPoolKey: String)          // "claude-code.rate_limits.five_hour"
    case session(sessionRef: String)            // the helper's HMAC'd session reference

    /// Stable text form used in the dedupe key.
    public var canonical: String {
        switch self {
        case .pool(let key): "pool:\(key)"
        case .session(let ref): "session:\(ref)"
        }
    }
}

/// An observation as produced by an adapter, before database ids exist (DATA_MODEL §5.1).
public struct IncomingObservation: Sendable, Hashable, Codable {
    public let subject: SubjectKey
    public let sessionRef: String?              // set on pool observations that arrived via a session
    public let modelID: String?
    public let kind: MetricKind
    public let value: MetricValue
    public let observedAt: Date
    public let receivedAt: Date
    public let evidence: EvidenceKind
    public let quality: Quality
    public let sourceVersion: String?
    public let dedupeKey: String

    public init(subject: SubjectKey, sessionRef: String?, modelID: String?, kind: MetricKind, value: MetricValue,
                observedAt: Date, receivedAt: Date, evidence: EvidenceKind, quality: Quality,
                sourceVersion: String?, dedupeKey: String) {
        self.subject = subject
        self.sessionRef = sessionRef
        self.modelID = modelID
        self.kind = kind
        self.value = value
        self.observedAt = observedAt
        self.receivedAt = receivedAt
        self.evidence = evidence
        self.quality = quality
        self.sourceVersion = sourceVersion
        self.dedupeKey = dedupeKey
    }
}

extension MetricValue {
    /// Canonical text for dedupe keys: one spelling per value, no float formatting surprises.
    public var canonical: String {
        switch self {
        case .percent(let d): "percent:\(d)"
        case .tokens(let n): "tokens:\(n)"
        case .usd(let d): "usd:\(d)"
        case .instant(let date): "instant:\(Int64((date.timeIntervalSince1970 * 1000).rounded()))"
        case .absent(let reason): "absent:\(reason.rawValue)"
        }
    }
}
