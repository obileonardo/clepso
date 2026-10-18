import Foundation

/// Reset reminders (increment 2.3; NOTIFICATIONS_AND_SCHEDULING §2, §2.1). Pure: the open windows, the user's lead
/// and the time in, the reminders that should be pending with the notification center out, and what to change to get
/// there. The notification center is the schedule's only copy: every pass compares it with what the current readings
/// call for, so a window rescheduled within tolerance re-plans the same request (the identifier carries the window,
/// not the reset time), a new window replaces the old one's, and a pool that disconnects loses its reminder.
///
/// DECISIONS B11 (founder, 18 Oct 2026, recommended option): a planned reminder never expires because its reading
/// is old. It is replaced or cancelled only when a newer reading moves or closes the window, or dropped when its fire
/// instant is more than 15 minutes past.
public enum ReminderPlanner {
    /// One pool's current window, as the reducer last left it.
    public struct Window: Sendable, Equatable {
        public let poolKey: String
        public let windowID: UUID
        public let resetsAt: Date
        public init(poolKey: String, windowID: UUID, resetsAt: Date) {
            self.poolKey = poolKey; self.windowID = windowID; self.resetsAt = resetsAt
        }
    }

    /// One reminder that should be pending.
    public struct Planned: Sendable, Equatable {
        public let identifier: String
        public let poolKey: String
        public let windowID: UUID
        public let resetsAt: Date
        public let leadMinutes: Int
        /// The absolute instant `resetsAt − lead`: a zone or daylight-saving change never moves it (F16, F17).
        public let fireAt: Date
    }

    /// A request the notification center holds.
    public struct Pending: Sendable, Equatable {
        public let identifier: String
        public let fireAt: Date
        public init(identifier: String, fireAt: Date) { self.identifier = identifier; self.fireAt = fireAt }
    }

    /// The leads the user can pick, in minutes.
    public static let leads = [5, 15, 30, 60]
    /// Only for a reported reset at least this far out: closer than that, the countdown says it already.
    public static let minimumNotice: TimeInterval = 5 * 60
    /// The OS keeps at most 64 pending requests per app.
    public static let pendingLimit = 64
    /// §2.1 `expired_stale`: a fire instant this far past is dropped, never delivered late.
    public static let staleAfter = AlertKind.resetReminder.maxAge

    /// `pool|window|resetReminder|-` (§1.3): the same window is the same request.
    public static func identifier(poolKey: String, windowID: UUID) -> String {
        AlertPlanner.key(poolKey: poolKey, windowID: windowID, kind: .resetReminder, level: nil)
    }

    public static func isReminder(_ identifier: String) -> Bool {
        identifier.hasSuffix("|" + AlertKind.resetReminder.rawValue + "|-")
    }

    /// The reminders that should be pending now, nearest first, at most `limit`. Nothing when the user hasn't chosen
    /// a lead (`nil` or 0), for a reset under five minutes out, or for a fire instant already past.
    public static func plan(_ windows: [Window], leadMinutes: Int?, now: Date, limit: Int = pendingLimit) -> [Planned] {
        guard let lead = leadMinutes, lead > 0 else { return [] }
        var latest: [String: Window] = [:]                      // one window per pool: the newest reset wins
        for window in windows where latest[window.poolKey].map({ $0.resetsAt < window.resetsAt }) ?? true {
            latest[window.poolKey] = window
        }
        let planned = latest.values.compactMap { window -> Planned? in
            guard window.resetsAt.timeIntervalSince(now) >= minimumNotice else { return nil }
            let fireAt = window.resetsAt.addingTimeInterval(-TimeInterval(lead * 60))
            guard fireAt > now else { return nil }
            return Planned(identifier: identifier(poolKey: window.poolKey, windowID: window.windowID), poolKey: window.poolKey,
                           windowID: window.windowID, resetsAt: window.resetsAt, leadMinutes: lead, fireAt: fireAt)
        }
        return Array(planned.sorted { ($0.fireAt, $0.identifier) < ($1.fireAt, $1.identifier) }.prefix(limit))
    }

    /// The changes that bring the notification center's reminders to `desired`.
    public struct Changes: Sendable, Equatable {
        /// Requests to add; adding an identifier that is pending replaces it in place.
        public var add: [Planned] = []
        /// Superseded or unwanted requests to remove.
        public var remove: [String] = []
        /// Of `remove`, the ones whose fire instant is more than 15 minutes past (`expired_stale`: one diagnostic line).
        public var expired: [String] = []
    }

    /// `pending` may hold other requests; only reminders are touched. A reminder that came due in the last 15 minutes
    /// is left to the OS, which may be delivering it right now.
    public static func reconcile(desired: [Planned], pending: [Pending], now: Date) -> Changes {
        var changes = Changes()
        let wanted = Dictionary(desired.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        var held: [String: Date] = [:]
        for request in pending where isReminder(request.identifier) {
            held[request.identifier] = request.fireAt
            if wanted[request.identifier] != nil { continue }
            if request.fireAt > now { changes.remove.append(request.identifier) }
            else if now.timeIntervalSince(request.fireAt) > staleAfter {
                changes.remove.append(request.identifier)
                changes.expired.append(request.identifier)
            }
        }
        changes.add = desired.filter { held[$0.identifier] != $0.fireAt }
        changes.remove.sort()
        changes.expired.sort()
        return changes
    }
}
