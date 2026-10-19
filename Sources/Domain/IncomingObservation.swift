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

/// Which route a Claude Code reading came by (docs/specs/mod-bridge.md §7). The reducer lets the status line hold a
/// window briefly when both routes report it, so two apps' sessions never take turns moving one reading.
public enum ObservationChannel: String, Sendable, Hashable, Codable {
    /// Clepso's Claude Code mod, in sessions no terminal draws (the desktop app's Code tab, the VS Code panel).
    case mod
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
    /// nil: the status line, or another agent's adapter. Kept in the ledger's `metadata_json`, so a rebuild sees it.
    public let channel: ObservationChannel?

    public init(subject: SubjectKey, sessionRef: String?, modelID: String?, kind: MetricKind, value: MetricValue,
                observedAt: Date, receivedAt: Date, evidence: EvidenceKind, quality: Quality,
                sourceVersion: String?, dedupeKey: String, channel: ObservationChannel? = nil) {
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
        self.channel = channel
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
        case .count(let n): "count:\(n)"
        case .duration(let ms): "duration:\(ms)"
        case .flag(let b): "flag:\(b)"
        case .absent(let reason): "absent:\(reason.rawValue)"
        }
    }
}
