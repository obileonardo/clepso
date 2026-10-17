import Foundation

/// Working product name. Expected to change (DECISIONS C6); every user-visible use reads this constant.
public enum Product {
    public static let name = "Pulse"
}

/// One provenance vocabulary for every value (DATA_MODEL §2.1, departure D5).
public enum EvidenceKind: String, Codable, Sendable, CaseIterable {
    case officialAPI, officialLocalTelemetry, userConfirmed
    case userSelectedUnverified, officialAnnouncement, thirdPartyUnverified
    case inferred

    /// Tie-break priority only; higher wins when `observedAt` is equal (DATA_MODEL §6.1).
    public var priority: Int {
        switch self {
        case .officialAPI: 60
        case .officialLocalTelemetry: 50
        case .userConfirmed: 40
        case .officialAnnouncement: 30
        case .userSelectedUnverified: 20
        case .thirdPartyUnverified: 10
        case .inferred: 0
        }
    }
}

public enum Quality: String, Codable, Sendable { case verified, reported, estimated, unknown }

public enum AccountKind: String, Codable, Sendable {
    case personalSubscription, organizationSeat, apiOrganization, apiProject
}

public struct Account: Codable, Identifiable, Sendable, Hashable {
    public static let schemaVersion = 1
    public let id: UUID
    public let providerID: String
    public let kind: AccountKind
    public var label: String              // user-chosen; never an email
    public let createdAt: Date
    public var archivedAt: Date?

    public init(id: UUID, providerID: String, kind: AccountKind, label: String, createdAt: Date, archivedAt: Date? = nil) {
        self.id = id
        self.providerID = providerID
        self.kind = kind
        self.label = label
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }
}

public enum ConnectionState: String, Codable, Sendable {
    case notConnected, connected, paused, providerError, disconnected
}

public struct Connection: Codable, Identifiable, Sendable, Hashable {
    public static let schemaVersion = 1
    public let id: UUID
    public let accountID: UUID
    public let adapterID: String          // "claude-code.statusline"
    public var adapterVersion: String?
    public var state: ConnectionState
    public var lastEventAt: Date?

    public init(id: UUID, accountID: UUID, adapterID: String, adapterVersion: String? = nil,
                state: ConnectionState, lastEventAt: Date? = nil) {
        self.id = id
        self.accountID = accountID
        self.adapterID = adapterID
        self.adapterVersion = adapterVersion
        self.state = state
        self.lastEventAt = lastEventAt
    }
}

/// The clock is injected everywhere in Domain, UsageEngine and Scheduler; `Date()` there fails lint.
public protocol WallClock: Sendable {
    func now() -> Date
}

public struct SystemClock: WallClock {
    public init() {}
    public func now() -> Date { Date() }   // clock-ok: the one sanctioned wall-clock read
}
