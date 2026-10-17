import Domain
import Foundation

/// What one metric row can be. Views derive it with `resolve`; callers never choose it.
public enum ValueState: String, CaseIterable, Sendable {
    case live, stale, notAvailable, notReportedYet, notConnected, providerError
}

/// What one allowance pool card can be. Stale is a modifier (`PoolCardModel.isStale`), not a case.
public enum CardState: String, CaseIterable, Sendable {
    case available, approaching, critical, exhausted, exhaustedNoReset, exhaustedOverage
    case resetExpected, availableAgain, availableAgainUser, quotaNotAvailable, disconnected

    /// From the engine's limit state (mapping table).
    public init(limit: LimitState, hasResetTime: Bool, connected: Bool, availableAgain: AvailableAgain? = nil) {
        guard connected else { self = .disconnected; return }
        if let availableAgain { self = availableAgain == .verified ? .availableAgain : .availableAgainUser; return }
        switch limit {
        case .unknown: self = .quotaNotAvailable
        case .available: self = .available
        case .approaching(.warning): self = .approaching
        case .approaching(.critical): self = .critical
        case .exhausted: self = hasResetTime ? .exhausted : .exhaustedNoReset
        case .paidOverage: self = .exhaustedOverage
        case .resetExpected: self = .resetExpected
        }
    }

    public enum AvailableAgain: Sendable { case verified, userConfirmed }
}

/// How the plan label is known.
public enum PlanProvenance: String, CaseIterable, Sendable {
    case providerVerified, userConfirmed, selectedUnverified, notSet
}

/// Display identity of a data source.
public struct SourceDescriptor: Sendable, Equatable {
    public let evidence: EvidenceKind
    public let displayName: String           // "Claude Code", never an enum name
    public let version: String?
    public init(evidence: EvidenceKind, displayName: String, version: String?) {
        self.evidence = evidence
        self.displayName = displayName
        self.version = version
    }
    public var isEnteredByUser: Bool { evidence == .userConfirmed }
}

/// Wordmark and monogram only, never a provider logo (compliance decision).
public struct ProviderIdentity: Sendable, Equatable {
    public let wordmark: String
    public let monogram: String
    public init(wordmark: String, monogram: String) {
        self.wordmark = wordmark
        self.monogram = monogram
    }
    public static let claudeCode = ProviderIdentity(wordmark: "Claude Code", monogram: "C")
}

/// Everything one pool row needs. There is no bare-number initializer: the value always comes with
/// its provenance, so "0% for missing data" cannot be expressed.
public struct PoolCardModel: Sendable {
    public let scope: String                 // "5-hour"
    public let source: SourceDescriptor
    public let used: Provenanced<Decimal>
    public let resetsAt: Provenanced<Date>
    public let card: CardState
    public let connection: ConnectionState

    public init(scope: String, source: SourceDescriptor, used: Provenanced<Decimal>, resetsAt: Provenanced<Date>,
                card: CardState, connection: ConnectionState = .connected) {
        self.scope = scope
        self.source = source
        self.used = used
        self.resetsAt = resetsAt
        self.card = card
        self.connection = connection
    }

    public func valueState(now: Date, staleAfter: TimeInterval) -> ValueState {
        resolve(used, connection: connection, now: now, staleAfter: staleAfter)
    }
    public func isStale(now: Date, staleAfter: TimeInterval) -> Bool { valueState(now: now, staleAfter: staleAfter) == .stale }
}

/// One Claude Code session row: model and context, which belong to the session, never the account.
public struct SessionRowModel: Sendable {
    public let modelName: String?
    public let contextUsed: Provenanced<Decimal>
    public let contextTokens: Provenanced<Int64>
    public let contextWindow: Provenanced<Int64>
    public init(modelName: String?, contextUsed: Provenanced<Decimal>, contextTokens: Provenanced<Int64>, contextWindow: Provenanced<Int64>) {
        self.modelName = modelName
        self.contextUsed = contextUsed
        self.contextTokens = contextTokens
        self.contextWindow = contextWindow
    }
}

/// DATA_MODEL §2.2: connection first, then absence reason, then freshness.
public func resolve<T>(_ p: Provenanced<T>, connection: ConnectionState, now: Date, staleAfter: TimeInterval) -> ValueState {
    switch connection {
    case .notConnected, .disconnected: return .notConnected
    case .providerError: return .providerError
    case .connected, .paused: break
    }
    guard p.value != nil else {
        switch p.absence {
        case .providerNull: return .notReportedYet
        case .rejectedBySanitizer: return .providerError
        case .providerOmitted, .notExposedBySource, .none: return .notAvailable
        }
    }
    guard let at = p.observedAt, now.timeIntervalSince(at) < staleAfter else { return .stale }
    return .live
}
