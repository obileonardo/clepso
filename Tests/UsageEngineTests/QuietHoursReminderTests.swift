import Domain
import Foundation
import Testing
@testable import UsageEngine

private func instant(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }
private let london = TimeZone(identifier: "Europe/London")!

/// §1.6 quiet hours: the span, its end, and what the planner does inside it.
struct QuietHoursTests {
    let night = QuietHours(enabled: true, start: 22 * 60, end: 7 * 60)
    let pool = "claude-code.rate_limits.five_hour"
    let window = UUID()

    func event(_ kind: DerivedEventKind, _ level: ThresholdLevel? = nil, at: Date) -> EngineEvent {
        EngineEvent(kind: kind, poolKey: pool, windowID: window, level: level, occurredAt: at)
    }

    @Test("22:00–07:00 crosses midnight: late evening and early morning are quiet, 07:00 and the day are not")
    func rangeCrossingMidnight() {
        // Thu 22 Oct 2026, BST (UTC+1): local times below are UTC + 1 h.
        for (local, quiet) in [("21:59", false), ("22:00", true), ("23:30", true), ("00:00", true), ("03:15", true),
                               ("06:59", true), ("07:00", false), ("12:00", false)] {
            let parts = local.split(separator: ":").map { Int($0)! }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = london
            let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: parts[0], minute: parts[1]))!
            #expect(night.isActive(at: date, in: london) == quiet, "\(local)")
        }
        // The same instant is quiet in London and not in Tokyo (09:30 there): read in the zone at decision time.
        let lateLondon = instant("2026-10-22T23:30:00Z")
        #expect(night.isActive(at: lateLondon, in: london))
        #expect(!night.isActive(at: lateLondon, in: TimeZone(identifier: "Asia/Tokyo")!))
        // A span within one day, an empty span, and the switch.
        let lunch = QuietHours(enabled: true, start: 12 * 60, end: 13 * 60)
        #expect(lunch.isActive(at: instant("2026-10-22T11:30:00Z"), in: london))     // 12:30 BST
        #expect(!lunch.isActive(at: instant("2026-10-22T12:30:00Z"), in: london))    // 13:30 BST
        #expect(!QuietHours(enabled: true, start: 600, end: 600).isActive(at: instant("2026-10-22T09:00:00Z"), in: london))
        var off = night
        off.enabled = false
        #expect(!off.isActive(at: lateLondon, in: london) && off.covers(lateLondon, in: london))
        #expect(QuietHours() == QuietHours(enabled: false, start: 1320, end: 420))     // off by default
        #expect(QuietHours(start: -30, end: 1440 + 30) == QuietHours(start: 1410, end: 30))
    }

    @Test("The span ends at the next 07:00 local, also across the night the clocks go back")
    func endAfter() {
        #expect(night.end(after: instant("2026-10-22T22:30:00Z"), in: london) == instant("2026-10-23T06:00:00Z"))   // 07:00 BST
        // Sat 24 → Sun 25 Oct: BST ends at 01:00 UTC, so 07:00 on Sunday is 07:00 GMT.
        #expect(night.end(after: instant("2026-10-24T22:30:00Z"), in: london) == instant("2026-10-25T07:00:00Z"))
    }

    @Test("Inside quiet hours approaching waits for the digest; limit reached is shown, quietly")
    func plannerDefersApproaching() {
        let now = instant("2026-10-22T23:00:00Z")                 // 00:00 BST
        let ctx = AlertPlanner.Context(quietHours: night, timeZone: london)
        let held = AlertPlanner.decide([event(.thresholdCrossed, .warning, at: now)], context: ctx, now: now)
        #expect(held.alerts.isEmpty && held.deferred.map(\.level) == [80] && held.quiet)
        let limit = AlertPlanner.decide([event(.exhausted, at: now)], context: ctx, now: now)
        #expect(limit.alerts.map(\.kind) == [.exhausted] && limit.deferred.isEmpty && limit.quiet)
        // 95 and 100 in one reading coalesce first: one limit-reached alert, nothing held.
        let both = AlertPlanner.decide([event(.thresholdCrossed, .critical, at: now), event(.exhausted, at: now)], context: ctx, now: now)
        #expect(both.alerts.map(\.kind) == [.exhausted] && both.deferred.isEmpty)
        // Daytime: nothing changes.
        let noon = instant("2026-10-23T11:00:00Z")
        let day = AlertPlanner.decide([event(.thresholdCrossed, .warning, at: noon)], context: ctx, now: noon)
        #expect(day.alerts.count == 1 && day.deferred.isEmpty && !day.quiet)
        // §1.7 keeps working: a snooze holds approaching outright, nothing is deferred.
        var snoozed = ctx
        snoozed.snoozedUntil = now.addingTimeInterval(3600)
        let held2 = AlertPlanner.decide([event(.thresholdCrossed, .warning, at: now)], context: snoozed, now: now)
        #expect(held2.alerts.isEmpty && held2.deferred.isEmpty)
    }

    @Test("The digest waits for the end, is shown within 30 minutes of it, and is dropped after a long sleep")
    func digestTiming() {
        let deferredAt = instant("2026-10-22T23:00:00Z")            // 00:00 BST; quiet until 07:00 BST = 06:00 UTC
        func decide(_ now: String, _ quiet: QuietHours? = nil, snoozed: Date? = nil) -> AlertPlanner.DigestDecision {
            AlertPlanner.digest(newestDeferral: deferredAt, quietHours: quiet ?? night, snoozedUntil: snoozed, timeZone: london, now: instant(now))
        }
        #expect(decide("2026-10-23T05:59:00Z") == .wait)
        #expect(decide("2026-10-23T06:00:00Z") == .deliver)
        #expect(decide("2026-10-23T06:30:00Z") == .deliver)
        #expect(decide("2026-10-23T06:31:00Z") == .expired)
        #expect(decide("2026-10-25T09:00:00Z") == .expired)
        var off = night
        off.enabled = false                                          // switched off at 03:00: shown then
        #expect(decide("2026-10-23T02:00:00Z", off) == .deliver)
        #expect(decide("2026-10-23T06:10:00Z", snoozed: instant("2026-10-23T07:00:00Z")) == .wait)
    }
}

/// §2 reset reminders: what is planned, and how the notification center is brought in line.
struct ReminderPlannerTests {
    let now = instant("2026-10-16T14:00:00Z")
    let pool = "claude-code.rate_limits.five_hour"
    let windowA = UUID(), windowB = UUID()

    @Test("A reminder fires at resetAt − lead; its identifier names the pool and window, not the reset time")
    func scheduledAtResetMinusLead() {
        let reset = instant("2026-10-16T17:00:00Z")
        let plan = ReminderPlanner.plan([.init(poolKey: pool, windowID: windowA, resetsAt: reset)], leadMinutes: 15, now: now)
        #expect(plan.count == 1)
        #expect(plan.first?.fireAt == instant("2026-10-16T16:45:00Z"))
        #expect(plan.first?.identifier == "\(pool)|\(windowA.uuidString)|resetReminder|-")
        #expect(plan.first.map { !$0.identifier.contains("\(Int(reset.timeIntervalSince1970))") } == true)
        #expect(plan.first.map { ReminderPlanner.isReminder($0.identifier) } == true)
        #expect(!ReminderPlanner.isReminder(AlertPlanner.key(poolKey: pool, windowID: windowA, kind: .exhausted, level: 100)))
        // Off (the default) plans nothing.
        #expect(ReminderPlanner.plan([.init(poolKey: pool, windowID: windowA, resetsAt: reset)], leadMinutes: nil, now: now).isEmpty)
    }

    @Test("A reset under 5 minutes out, or a fire instant already past, plans nothing")
    func tooCloseOrPast() {
        let soon = ReminderPlanner.Window(poolKey: pool, windowID: windowA, resetsAt: now.addingTimeInterval(4 * 60 + 59))
        #expect(ReminderPlanner.plan([soon], leadMinutes: 5, now: now).isEmpty)
        let tenOut = ReminderPlanner.Window(poolKey: pool, windowID: windowA, resetsAt: now.addingTimeInterval(10 * 60))
        #expect(ReminderPlanner.plan([tenOut], leadMinutes: 15, now: now).isEmpty)      // would fire 5 minutes ago
        #expect(ReminderPlanner.plan([tenOut], leadMinutes: 5, now: now).count == 1)
    }

    @Test("Window rescheduled within tolerance: the same identifier is re-planned in place, nothing removed")
    func rescheduledInPlace() {
        let first = ReminderPlanner.plan([.init(poolKey: pool, windowID: windowA, resetsAt: instant("2026-10-16T17:00:00Z"))], leadMinutes: 15, now: now)
        let moved = ReminderPlanner.plan([.init(poolKey: pool, windowID: windowA, resetsAt: instant("2026-10-16T17:05:00Z"))], leadMinutes: 15, now: now)
        let changes = ReminderPlanner.reconcile(desired: moved, pending: first.map { .init(identifier: $0.identifier, fireAt: $0.fireAt) }, now: now)
        #expect(changes.remove.isEmpty && changes.expired.isEmpty)
        #expect(changes.add.map(\.identifier) == first.map(\.identifier))
        #expect(changes.add.first?.fireAt == instant("2026-10-16T16:50:00Z"))
        // Unchanged: nothing to do.
        #expect(ReminderPlanner.reconcile(desired: moved, pending: moved.map { .init(identifier: $0.identifier, fireAt: $0.fireAt) }, now: now) == .init())
    }

    @Test("Window opened: the old window's request is removed and the new one scheduled; disconnect removes it")
    func windowOpenedReplaces() {
        let old = ReminderPlanner.plan([.init(poolKey: pool, windowID: windowA, resetsAt: instant("2026-10-16T17:00:00Z"))], leadMinutes: 30, now: now)
        let new = ReminderPlanner.plan([.init(poolKey: pool, windowID: windowB, resetsAt: instant("2026-10-16T18:00:00Z"))], leadMinutes: 30, now: now)
        let pending = old.map { ReminderPlanner.Pending(identifier: $0.identifier, fireAt: $0.fireAt) }
        let changes = ReminderPlanner.reconcile(desired: new, pending: pending, now: now)
        #expect(changes.remove == old.map(\.identifier) && changes.add == new && changes.expired.isEmpty)
        let gone = ReminderPlanner.reconcile(desired: [], pending: pending, now: now)
        #expect(gone.remove == old.map(\.identifier) && gone.add.isEmpty)
        // Other requests (an alert shown now, the test notification) are never touched.
        #expect(ReminderPlanner.reconcile(desired: [], pending: [.init(identifier: "clepso.test", fireAt: now.addingTimeInterval(60))], now: now) == .init())
    }

    @Test("Launch reconciliation: a request more than 15 minutes overdue is dropped and counted; a just-due one is left to the OS")
    func overdueAtLaunch() {
        let id = ReminderPlanner.identifier(poolKey: pool, windowID: windowA)
        let late = ReminderPlanner.reconcile(desired: [], pending: [.init(identifier: id, fireAt: now.addingTimeInterval(-90 * 86_400))], now: now)
        #expect(late.remove == [id] && late.expired == [id] && late.add.isEmpty)
        let justDue = ReminderPlanner.reconcile(desired: [], pending: [.init(identifier: id, fireAt: now.addingTimeInterval(-10 * 60))], now: now)
        #expect(justDue == .init())
    }

    @Test("At most 64 pending, nearest first; one window per pool")
    func cappedNearestFirst() {
        let windows = (0..<80).map { i in
            ReminderPlanner.Window(poolKey: "pool.\(i)", windowID: UUID(), resetsAt: now.addingTimeInterval(TimeInterval((80 - i) * 3600)))
        }
        let plan = ReminderPlanner.plan(windows, leadMinutes: 5, now: now)
        #expect(plan.count == 64)
        #expect(plan.map(\.fireAt) == plan.map(\.fireAt).sorted())
        #expect(plan.last.map { $0.resetsAt <= now.addingTimeInterval(64 * 3600) } == true)
        let two = ReminderPlanner.plan([.init(poolKey: pool, windowID: windowA, resetsAt: now.addingTimeInterval(3600)),
                                        .init(poolKey: pool, windowID: windowB, resetsAt: now.addingTimeInterval(7200))], leadMinutes: 5, now: now)
        #expect(two.map(\.windowID) == [windowB])
    }

    @Test("DST (Europe/London): the fire instant is resetAt − lead in absolute time, whatever the wall clock does")
    func dstKeepsTheInstant() {
        // Weekly reset Sun 25 Oct 2026 01:30 GMT, an hour after BST ended; a 60-minute lead lands before the change.
        let reset = instant("2026-10-25T01:30:00Z")
        let plan = ReminderPlanner.plan([.init(poolKey: "claude-code.rate_limits.seven_day", windowID: windowA, resetsAt: reset)],
                                        leadMinutes: 60, now: instant("2026-10-24T12:00:00Z"))
        #expect(plan.first?.fireAt == instant("2026-10-25T00:30:00Z"))
        #expect(plan.first.map { reset.timeIntervalSince($0.fireAt) } == 3600)
    }
}
