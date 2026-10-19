import Domain
import Foundation

/// Latest value per metric for one Claude Code session (context %, tokens, cost estimate).
/// Persisted as `session_snapshots.snapshot_json`. Context is session-scoped and never aggregated.
public struct SessionState: Codable, Sendable, Equatable {
    public struct Value: Codable, Sendable, Equatable {
        public let value: MetricValue
        public let observedAt: Date
        public let quality: Quality
    }

    public let sessionRef: String
    public var values: [MetricKind: Value] = [:]
    public var modelID: String?
    public var lastSeen: Date?
    /// The newest status-line reading of this session; the mod's readings within the hold after it are skipped (§7).
    public var lastStatusLineAt: Date?
    public var version: Int64 = 0

    public init(sessionRef: String) { self.sessionRef = sessionRef }
}

public enum SessionReducer {
    /// Latest-wins per metric kind; an older sample never replaces a newer one. A session the status line reports keeps
    /// it as its one source: the mod's readings within `holdOff` after the status line's newest are skipped
    /// (docs/specs/mod-bridge.md §7; the mod already skips sessions a terminal draws).
    public static func reduce(_ input: SessionState, _ observations: [IncomingObservation],
                              holdOff: TimeInterval = EngineConfig().sourceHoldOff) -> SessionState {
        var s = input
        var changed = false
        for o in observations where o.subject == .session(sessionRef: s.sessionRef) {
            if o.channel == .mod, let held = s.lastStatusLineAt, o.observedAt.timeIntervalSince(held) < holdOff { continue }
            if o.channel != .mod { s.lastStatusLineAt = max(s.lastStatusLineAt ?? o.observedAt, o.observedAt) }
            if let existing = s.values[o.kind], existing.observedAt > o.observedAt { continue }
            s.values[o.kind] = SessionState.Value(value: o.value, observedAt: o.observedAt, quality: o.quality)
            if let model = o.modelID { s.modelID = model }
            s.lastSeen = max(s.lastSeen ?? o.observedAt, o.observedAt)
            changed = true
        }
        if changed { s.version += 1 }
        return s
    }
}
