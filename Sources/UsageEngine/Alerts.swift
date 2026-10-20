import Domain
import Foundation

/// Limit alerts (increments 2.1–2.3; NOTIFICATIONS_AND_SCHEDULING §1). Pure: the engine's events in, the alerts to
/// show out. Crossing detection, re-arming and window identity are the reducer's (G2–G9); this decides which of
/// its events become notifications and keys each one so it can be shown at most once.
public enum AlertKind: String, Codable, Sendable, CaseIterable {
    case approaching, exhausted, resetExpected, readyAgain
    /// Scheduled ahead with the notification center (§2), never planned from an event: see `ReminderPlanner`.
    case resetReminder
}

public struct AlertCandidate: Sendable, Equatable {
    public let kind: AlertKind
    public let poolKey: String
    public let windowID: UUID?
    /// 80 or 95 for `approaching`, 100 for `exhausted`, nil otherwise.
    public let level: Int?
    public let occurredAt: Date
    /// §1.3 `pool|window|kind|level`; also the notification's identifier, so one crossing is one notification.
    public let dedupKey: String
    public init(kind: AlertKind, poolKey: String, windowID: UUID?, level: Int?, occurredAt: Date, dedupKey: String) {
        self.kind = kind; self.poolKey = poolKey; self.windowID = windowID; self.level = level
        self.occurredAt = occurredAt; self.dedupKey = dedupKey
    }
    /// §1.9: exhausted 1.0, readyAgain 0.9, resetExpected 0.8, approaching 0.6, others 0.2.
    public var relevance: Double { kind.relevance }
}

extension AlertKind {
    public var relevance: Double {
        switch self {
        case .exhausted: 1.0
        case .readyAgain: 0.9
        case .resetExpected: 0.8
        case .approaching: 0.6
        case .resetReminder: 0.2
        }
    }
}

extension AlertKind {
    /// How long after its event an alert is still worth showing (§3.5 freshness caps; §2 and TEST_PLAN §5 case 10 for
    /// resets: a fire instant more than 15 minutes past is `expired_stale`). After a weekend asleep, "reset time has
    /// arrived" for Friday's 17:00 reset would be news from three days ago.
    public var maxAge: TimeInterval {
        switch self {
        case .readyAgain: 10 * 60
        case .resetExpected, .resetReminder: 15 * 60
        case .approaching, .exhausted: 30 * 60
        }
    }
}

public enum AlertPlanner {
    /// What the planner needs to know besides the events.
    public struct Context: Sendable {
        /// Dedup keys already decided (receipts table: shown, or dropped as too old), across restarts.
        public var delivered: Set<String>
        /// Kinds already shown per window, for the "ready again" guard (B4).
        public var deliveredKinds: [UUID: Set<AlertKind>]
        public var snoozedUntil: Date?
        public var enabled: Bool
        public var isDemo: Bool
        /// §1.6, read in `timeZone` (the Mac's zone at decision time).
        public var quietHours: QuietHours
        public var timeZone: TimeZone
        public init(delivered: Set<String> = [], deliveredKinds: [UUID: Set<AlertKind>] = [:], snoozedUntil: Date? = nil,
                    enabled: Bool = true, isDemo: Bool = false, quietHours: QuietHours = QuietHours(),
                    timeZone: TimeZone = TimeZone(identifier: "UTC")!) {
            self.delivered = delivered
            self.deliveredKinds = deliveredKinds
            self.snoozedUntil = snoozedUntil
            self.enabled = enabled
            self.isDemo = isDemo
            self.quietHours = quietHours
            self.timeZone = timeZone
        }
    }

    public static func key(poolKey: String, windowID: UUID?, kind: AlertKind, level: Int?) -> String {
        [poolKey, windowID?.uuidString ?? "-", kind.rawValue, level.map(String.init) ?? "-"].joined(separator: "|")
    }

    /// One batch's outcome: what to show, and what was due but is too old to show (`stale_dropped` receipts and one
    /// diagnostic line, never a notification). During quiet hours (§1.6) `approaching` waits for the digest
    /// (`quiet_deferred` receipts) and everything else is shown quietly: `.passive`, no sound.
    public struct Decision: Sendable, Equatable {
        public var alerts: [AlertCandidate] = []
        public var expired: [AlertCandidate] = []
        public var deferred: [AlertCandidate] = []
        public var quiet = false
    }

    /// The alerts for one batch of events, highest level per pool and window, oldest first.
    public static func plan(_ events: [EngineEvent], context: Context, now: Date) -> [AlertCandidate] {
        decide(events, context: context, now: now).alerts
    }

    /// `plan`, plus the alerts it held back because their event is older than the kind's `maxAge`.
    public static func decide(_ events: [EngineEvent], context: Context, now: Date) -> Decision {
        guard context.enabled, !context.isDemo else { return Decision() }   // §1.10: never demo data
        var candidates: [AlertCandidate] = [], expired: [AlertCandidate] = []
        var shownKinds = context.deliveredKinds
        for event in events.sorted(by: { $0.occurredAt < $1.occurredAt }) {
            let kind: AlertKind, level: Int?
            switch event.kind {
            case .thresholdCrossed: kind = .approaching; level = event.level == .critical ? 95 : 80
            case .exhausted: kind = .exhausted; level = 100
            case .resetExpected: kind = .resetExpected; level = nil
            case .readyAgain: kind = .readyAgain; level = nil
            default: continue                                            // windows, staleness, overage: no alert
            }
            let prior = event.windowID.flatMap { shownKinds[$0] } ?? []
            switch kind {
            case .resetExpected where !prior.contains(.exhausted):
                continue                     // §2: expected resets are announced for windows that hit their limit
            case .readyAgain where prior.isDisjoint(with: [.exhausted, .resetExpected, .resetReminder]):
                continue                     // B4: nobody at 85% gets a "ready" they never waited for
            default: break
            }
            // §1.7: a snooze holds approaching and exhausted; the user is waiting for reset and ready alerts.
            if let until = context.snoozedUntil, now < until, kind == .approaching || kind == .exhausted { continue }
            let key = key(poolKey: event.poolKey, windowID: event.windowID, kind: kind, level: level)
            if context.delivered.contains(key) { continue }
            let candidate = AlertCandidate(kind: kind, poolKey: event.poolKey, windowID: event.windowID, level: level,
                                           occurredAt: event.occurredAt, dedupKey: key)
            // A clock stepped back makes the age negative: that is "just happened", never "expired".
            if now.timeIntervalSince(event.occurredAt) > kind.maxAge { expired.append(candidate); continue }
            candidates.append(candidate)
            if let window = event.windowID { shownKinds[window, default: []].insert(kind) }
        }
        let shown = coalesced(candidates)
        guard context.quietHours.isActive(at: now, in: context.timeZone) else { return Decision(alerts: shown, expired: expired) }
        return Decision(alerts: shown.filter { $0.kind != .approaching }, expired: expired,
                        deferred: shown.filter { $0.kind == .approaching }, quiet: true)
    }

    /// What to do with the approaching alerts quiet hours held back (§1.6, §1.8 `digest`).
    public enum DigestDecision: Sendable, Equatable {
        /// Still quiet (or snoozed): keep holding.
        case wait
        /// Show one digest now.
        case deliver
        /// The quiet spell ended more than `AlertKind.approaching.maxAge` ago (the Mac slept through the morning):
        /// settle without a notification, like any alert too old to be news.
        case expired
    }

    /// `newestDeferral`: when the last held-back alert was deferred. The digest is due at the end of the quiet spell
    /// that alert fell in, or at once if quiet hours were switched off before then.
    public static func digest(newestDeferral: Date, quietHours: QuietHours, snoozedUntil: Date?, timeZone: TimeZone,
                              now: Date) -> DigestDecision {
        if quietHours.isActive(at: now, in: timeZone) { return .wait }
        let due = min(quietHours.end(after: newestDeferral, in: timeZone), now)
        if now.timeIntervalSince(due) > AlertKind.approaching.maxAge { return .expired }
        if let snoozedUntil, now < snoozedUntil { return .wait }          // §1.7: a snooze holds approaching alerts
        return .deliver
    }

    /// §1.5: within one batch, a pool and window keep only the highest crossing (95 and 100 together → limit reached).
    static func coalesced(_ candidates: [AlertCandidate]) -> [AlertCandidate] {
        let rank: (AlertCandidate) -> Int = { c in
            switch c.kind {
            case .approaching: c.level ?? 0
            case .exhausted: 100
            default: -1                                                  // reset and ready alerts are never merged
            }
        }
        var best: [String: AlertCandidate] = [:]
        var others: [AlertCandidate] = []
        for c in candidates {
            guard rank(c) >= 0 else { others.append(c); continue }
            let group = c.poolKey + "|" + (c.windowID?.uuidString ?? "-")
            if let existing = best[group], rank(existing) >= rank(c) { continue }
            best[group] = c
        }
        return (Array(best.values) + others).sorted { ($0.occurredAt, $0.dedupKey) < ($1.occurredAt, $1.dedupKey) }
    }
}
