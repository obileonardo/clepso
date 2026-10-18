import DesignSystem
import Domain
import Foundation
import Storage
import UsageEngine

/// Everything the menu bar and popover show, computed once per refresh (nothing reads
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
    /// Agents per task (increment 1.9); nil while the hooks aren't installed.
    public let agents: AgentsSummary?
    /// Codex's limits (increment 3.4); nil while reading Codex is off.
    public var codex: AgentLimitsSection? = nil

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
    /// Limit windows Claude Code sent that Pulse does not read. 0 is the normal case today.
    public let unreadLimitWindows: Int
    /// Increment 1.7e: every session Pulse has seen (30-day retention), newest first, with what Claude Code reports.
    public let sessions: [SessionDetail]
    /// Sessions grouped by their main model: an approximation (Claude Code's background models count under it).
    public let models: [ModelGroup]
    /// Lines added and removed over every kept session (the player card); nil when no session reported lines.
    public var lines: CodeLines? = nil
}

/// Lines of code per session, as Claude Code's status line reports them (lines added and removed, cumulative per
/// session), summed over the sessions Clepso still keeps: those seen in the last 30 days. Not a lifetime figure: older
/// sessions are deleted with their readings, and sessions from before Clepso was connected were never seen.
public struct CodeLines: Sendable, Equatable {
    public let added: Int64
    public let removed: Int64
    public let sessions: Int
    /// The window's start: 30 days ago, or the first kept session's first sighting if that is later (a newer install).
    public let since: Date
    /// True when `since` is the retention edge rather than the first session Clepso saw.
    public let fullWindow: Bool

    public static let window: TimeInterval = 30 * 86_400

    /// Sessions last seen within the window, each counted once at its latest cumulative value.
    public static func make(_ sessions: [SessionState], firstSeen: Date?, now: Date) -> CodeLines? {
        let edge = now.addingTimeInterval(-window)
        var added: Int64 = 0, removed: Int64 = 0, count = 0
        for s in sessions where (s.lastSeen ?? .distantPast) >= edge {
            let a: Int64? = if case .count(let n)? = s.values[.linesAdded]?.value { n } else { nil }
            let r: Int64? = if case .count(let n)? = s.values[.linesRemoved]?.value { n } else { nil }
            guard a != nil || r != nil else { continue }
            added += max(0, a ?? 0); removed += max(0, r ?? 0); count += 1
        }
        guard count > 0 else { return nil }
        let start = max(edge, firstSeen ?? edge)
        return CodeLines(added: added, removed: removed, sessions: count, since: start, fullWindow: start == edge)
    }
}

/// One Claude Code session as its status line reports it: cumulative for the session, as of `lastSeen`.
public struct SessionDetail: Sendable, Identifiable, Equatable {
    public let id: String                       // the hashed session reference
    public let modelName: String?
    public let lastSeen: Date?
    public let contextPct: Decimal?
    /// `context_window.total_input_tokens` / `total_output_tokens`: the current context window's contents,
    /// not the session's cumulative usage (verified against the real capture: input total = context size).
    public let tokensIn: Int64?
    public let tokensOut: Int64?
    public let contextWindow: Int64?
    public let costUSD: Decimal?                // Claude Code's estimate at list price, not a bill
    public let wallMs: Int64?
    public let apiMs: Int64?
    public let linesAdded: Int64?
    public let linesRemoved: Int64?
    public let cacheHitPct: Decimal?
    public let cacheRequests: Int64?
    public let cacheMisses: Int64?
    public let cacheWarm: Bool?
}

public struct ModelGroup: Sendable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let sessions: Int
    public let costUSD: Decimal                 // Claude Code's estimates, summed over the group's sessions
    public let linesAdded: Int64
    public let apiMs: Int64
    /// Share of the summed cost estimates. Context token counts are not summed: they describe one context window
    /// at a time, not usage (increment 1.8).
    public let share: Double
}

/// One allowance pool with what the provenance inspector needs, prefetched.
public struct PoolRow: Sendable, Identifiable {
    public var id: String { poolKey }
    public let poolKey: String
    public let providerField: String
    public let model: PoolCardModel
    public let receivedAt: Date?
    public let recent: [Store.Reading]
    /// Measured used % over the last 7 days, oldest first (thinned by the ledger policy).
    public let history: [UsagePoint]
    /// Always shown as an estimate (increment 1.7c).
    public let pace: PaceEstimate
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
    public var unreadLimitWindows = 0
    public var history: [String: [UsagePoint]] = [:]
    public var agentsTracking = false
    public var agentTasks: [Store.AgentTask] = []
    /// Increment 3.4: Codex's pools, kept apart from Claude Code's; plan and model from its latest reading.
    public var codexEnabled = false
    public var codexPools: [PoolState] = []
    public var codexPlan: String?
    public var codexModel: String?
    /// The oldest kept session's first sighting (`CodeLines.since`).
    public var firstSessionSeen: Date?
    public init() {}
}

/// Agents per task (increment 1.9): the latest task, recent ones, and 30-day totals. Counts only.
public struct AgentsSummary: Sendable, Equatable {
    public struct Task: Sendable, Equatable, Identifiable {
        public let id: String
        public let startedAt: Date
        public let endedAt: Date?
        public let running: Bool                 // no stop seen yet and recent
        public let agents: Int
        public let finished: Int
        /// Display order: Explore, Plan, General, other built-ins, Custom, Unknown; zero counts left out.
        public let byType: [(name: String, count: Int)]
        public static func == (a: Task, b: Task) -> Bool {
            a.id == b.id && a.startedAt == b.startedAt && a.endedAt == b.endedAt && a.running == b.running && a.agents == b.agents
                && a.finished == b.finished && a.byType.map(\.name) == b.byType.map(\.name) && a.byType.map(\.count) == b.byType.map(\.count)
        }
    }
    public let latest: Task?
    public let recent: [Task]                    // newest first, at most 8
    public let tasks: Int                        // in the last 30 days
    public let tasksWithAgents: Int
    public let totalAgents: Int
    public let mostInOneTask: Int
    public var averagePerTask: Double { tasks > 0 ? Double(totalAgents) / Double(tasks) : 0 }
}

/// Another agent's limits beside Claude Code's (increment 3.4: Codex), drawn with the same pool rows.
public struct AgentLimitsSection: Sendable {
    public let name: String
    public let plan: String?
    public let model: String?
    public let pools: [PoolRow]
    public let lastSeen: Date?
}
