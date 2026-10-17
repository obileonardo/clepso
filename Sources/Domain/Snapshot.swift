import Foundation

public enum ThresholdLevel: String, Codable, Sendable { case warning, critical }

public enum LimitState: Codable, Sendable, Hashable {
    case unknown
    case available
    case approaching(ThresholdLevel)
    case exhausted
    case paidOverage                      // reachable only with overage evidence
    case resetExpected                    // resetsAt elapsed, no fresh evidence yet
}

/// Two tiers only (DECISIONS B2). Computed at render from `lastProviderMeasured`, never stored.
public enum Freshness: Codable, Sendable, Hashable {
    case live
    case stale(age: TimeInterval)
    case never

    /// Local telemetry is stale 10 minutes after its reading.
    public static let localTelemetryTTL: TimeInterval = 10 * 60

    public static func of(lastMeasured: Date?, at now: Date, ttl: TimeInterval) -> Freshness {
        guard let lastMeasured else { return .never }
        let age = now.timeIntervalSince(lastMeasured)
        return age < ttl ? .live : .stale(age: age)
    }
}

/// A value with its provenance. `value == nil` is absence, which is distinct from stale.
public struct Provenanced<T: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    public let value: T?
    public let absence: AbsenceReason?
    public let evidence: EvidenceKind
    public let quality: Quality
    public let observedAt: Date?
    public let observationID: UUID?

    /// Exactly one of `value` and `absence` is set; the two constructors are the only way in.
    private init(value: T?, absence: AbsenceReason?, evidence: EvidenceKind, quality: Quality,
                 observedAt: Date?, observationID: UUID?) {
        self.value = value
        self.absence = absence
        self.evidence = evidence
        self.quality = quality
        self.observedAt = observedAt
        self.observationID = observationID
    }

    public static func measured(_ value: T, evidence: EvidenceKind, quality: Quality,
                                observedAt: Date, observationID: UUID?) -> Self {
        Self(value: value, absence: nil, evidence: evidence, quality: quality,
             observedAt: observedAt, observationID: observationID)
    }

    public static func absent(_ reason: AbsenceReason, evidence: EvidenceKind,
                              observedAt: Date?, observationID: UUID?) -> Self {
        Self(value: nil, absence: reason, evidence: evidence, quality: .unknown,
             observedAt: observedAt, observationID: observationID)
    }
}

/// Rebuildable projection of the ledger (DATA_MODEL §2.4).
public struct PoolSnapshot: Codable, Sendable, Hashable {
    public static let schemaVersion = 1
    public let poolID: UUID
    public let accountID: UUID
    public let windowID: UUID?
    public let usedPct: Provenanced<Decimal>
    public let remainingPct: Provenanced<Decimal>
    public let resetsAt: Provenanced<Date>
    public let state: LimitState
    public let lastKnownState: LimitState?
    public let lastProviderMeasured: Date?
    public let lastSeen: Date?
    public let omittedSince: Date?
    public let highWaterUsedPct: Decimal?
    public let version: Int64

    public init(poolID: UUID, accountID: UUID, windowID: UUID?, usedPct: Provenanced<Decimal>,
                remainingPct: Provenanced<Decimal>, resetsAt: Provenanced<Date>, state: LimitState,
                lastKnownState: LimitState?, lastProviderMeasured: Date?, lastSeen: Date?,
                omittedSince: Date?, highWaterUsedPct: Decimal?, version: Int64) {
        self.poolID = poolID
        self.accountID = accountID
        self.windowID = windowID
        self.usedPct = usedPct
        self.remainingPct = remainingPct
        self.resetsAt = resetsAt
        self.state = state
        self.lastKnownState = lastKnownState
        self.lastProviderMeasured = lastProviderMeasured
        self.lastSeen = lastSeen
        self.omittedSince = omittedSince
        self.highWaterUsedPct = highWaterUsedPct
        self.version = version
    }

    public func freshness(at now: Date, ttl: TimeInterval = Freshness.localTelemetryTTL) -> Freshness {
        Freshness.of(lastMeasured: lastProviderMeasured, at: now, ttl: ttl)
    }
}

/// Engine events (DATA_MODEL §2.8). The notification engine (2.1) turns some of these into alerts.
public enum DerivedEventKind: String, Codable, Sendable, CaseIterable {
    case thresholdCrossed, exhausted, paidOverageDetected, resetExpected, readyAgain
    case staleSource, windowOpened, windowRescheduled, connectionStateChanged, parserRejected
}
