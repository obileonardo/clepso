import DesignSystem
import Domain
import Foundation
import Storage
import UsageEngine

/// Everything the menu bar and popover show, computed once per refresh (DESIGN_SYSTEM §9: nothing reads
/// storage when the popover opens). Pure value; `OverviewProjection.make` is the only producer.
public struct OverviewSnapshot: Sendable {
    public enum Icon: String, Sendable, CaseIterable { case ok, approaching, exhausted, stale, demo }
    public enum Empty: Sendable, Equatable { case notConnected, waitingForFirstReading }

    public let now: Date
    public let isDemo: Bool
    public let icon: Icon
    public let iconStaleMark: Bool
    public let iconText: String?
    public let aggregateLine: String
    public let updatedAt: Date?
    public let provider: ProviderSection?
    public let empty: Empty?

    /// AT-07: the product name, then the aggregate line.
    public var iconAccessibilityLabel: String { "\(Product.name): \(aggregateLine)" }

    public var iconShape: MenuBarIcon.Shape {
        switch icon {
        case .ok: .ring
        case .approaching: .notch
        case .exhausted: .bar
        case .stale: .clock
        case .demo: .dashed
        }
    }
}

/// One provider in the popover and the detail view.
public struct ProviderSection: Sendable {
    public let identity: ProviderIdentity
    public let planName: String?
    public let plan: PlanProvenance
    public let header: String
    public let pools: [PoolRow]
    public let session: SessionRowModel?
    public let sessionCount: Int
    public let sourceVersion: String?
    public let lastSeen: Date?
}

/// One allowance pool with what the provenance inspector needs, prefetched (DESIGN_SYSTEM §9).
public struct PoolRow: Sendable, Identifiable {
    public var id: String { poolKey }
    public let poolKey: String
    public let providerField: String
    public let model: PoolCardModel
    public let receivedAt: Date?
    public let recent: [Store.Reading]
}

/// What the projection reads. The app model fills it from the store; tests and demo mode build it directly.
public struct OverviewInput: Sendable {
    public var pools: [PoolState] = []
    public var sessions: [SessionState] = []
    public var sessionSummaries: [Store.SessionSummary] = []
    public var recent: [String: [Store.Reading]] = [:]
    public var plan: Store.PlanIdentity?
    public var installed = false
    public var sourceVersion: String?
    public var lastEventAt: Date?
    public var showPercent = true
    public var isDemo = false
    public init() {}
}
