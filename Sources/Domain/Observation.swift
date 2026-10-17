import Foundation

/// Unit and value are one case, so they cannot separate (DATA_MODEL §2.2, departure D1).
public enum MetricValue: Codable, Sendable, Hashable {
    case percent(Decimal)                 // raw; values above 100 are preserved
    case tokens(Int64)
    case usd(Decimal)
    case instant(Date)
    case count(Int64)                     // a plain count: lines changed, cache requests (increment 1.7)
    case duration(milliseconds: Int64)    // elapsed time as Claude Code reports it
    case flag(Bool)                       // a yes/no fact: the prompt cache is warm
    case absent(AbsenceReason)            // a recorded fact, never rendered as 0
}

public enum AbsenceReason: String, Codable, Sendable, CaseIterable {
    case providerOmitted                  // key missing from the payload
    case providerNull                     // key present, value null
    case notExposedBySource               // the source never carries this field
    case rejectedBySanitizer              // out of range or wrong type
}

public enum MetricKind: String, Codable, Sendable, CaseIterable {
    case quotaUsedPct, quotaRemainingPct, resetAt
    case contextUsedPct, contextTokens, contextWindowSize
    case requestInputTokens, requestOutputTokens, cacheReadTokens, cacheCreationTokens
    case apiCostUSD, creditBalanceUSD
    // Increment 1.7 (session detail; DATA_MODEL §5.1): cumulative per session as Claude Code reports them.
    case sessionOutputTokens, wallDuration, apiDuration, linesAdded, linesRemoved
    case cacheHitPct, cacheRequests, cacheMisses, cacheWarm
}

public enum ObservationSubject: Codable, Sendable, Hashable {
    case pool(UUID)                       // account-level allowance
    case session(UUID)                    // one session; context metrics live here
}

/// Append-only ledger entry (DATA_MODEL §2.2). Everything shown traces back to one of these.
public struct Observation: Codable, Identifiable, Sendable, Hashable {
    public static let schemaVersion = 1
    public let id: UUID
    public let accountID: UUID
    public let connectionID: UUID
    public let subject: ObservationSubject
    public let sessionID: UUID?
    public let modelID: String?
    public let kind: MetricKind
    public let value: MetricValue
    public let observedAt: Date           // for the status line: the shim's read time
    public let receivedAt: Date
    public let evidence: EvidenceKind
    public let quality: Quality
    public let sourceVersion: String?
    public let dedupeKey: String
    public let metadata: [String: String]?

    public init(id: UUID, accountID: UUID, connectionID: UUID, subject: ObservationSubject, sessionID: UUID?,
                modelID: String?, kind: MetricKind, value: MetricValue, observedAt: Date, receivedAt: Date,
                evidence: EvidenceKind, quality: Quality, sourceVersion: String?, dedupeKey: String,
                metadata: [String: String]? = nil) {
        self.id = id
        self.accountID = accountID
        self.connectionID = connectionID
        self.subject = subject
        self.sessionID = sessionID
        self.modelID = modelID
        self.kind = kind
        self.value = value
        self.observedAt = observedAt
        self.receivedAt = receivedAt
        self.evidence = evidence
        self.quality = quality
        self.sourceVersion = sourceVersion
        self.dedupeKey = dedupeKey
        self.metadata = metadata
    }
}

public enum PoolFunding: String, Codable, Sendable {
    case includedSubscription, prepaidCredits, promotionalAPICredit
    case billedOverage, apiPayAsYouGo, unknown
}

public enum WindowType: String, Codable, Sendable { case rolling, scheduled, unknown }

/// Identity only; carries no measured value (DATA_MODEL departure D3).
public struct AllowancePool: Codable, Identifiable, Sendable, Hashable {
    public static let schemaVersion = 1
    public let id: UUID
    public let accountID: UUID
    public let providerPoolKey: String    // "claude-code.rate_limits.five_hour"
    public var name: String
    public var funding: PoolFunding
    public var windowType: WindowType     // never inferred from `name`
    public var eligibleProducts: [String]
    public var overageEvidence: EvidenceKind?
    public let createdAt: Date

    public init(id: UUID, accountID: UUID, providerPoolKey: String, name: String, funding: PoolFunding,
                windowType: WindowType = .unknown, eligibleProducts: [String] = [],
                overageEvidence: EvidenceKind? = nil, createdAt: Date) {
        self.id = id
        self.accountID = accountID
        self.providerPoolKey = providerPoolKey
        self.name = name
        self.funding = funding
        self.windowType = windowType
        self.eligibleProducts = eligibleProducts
        self.overageEvidence = overageEvidence
        self.createdAt = createdAt
    }
}

/// Lets `[MetricKind: …]` encode as a JSON object, so sorted-key encoding is byte-stable (snapshot rebuilds).
extension MetricKind: CodingKeyRepresentable {}
