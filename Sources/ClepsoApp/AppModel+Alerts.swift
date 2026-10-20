import DesignSystem
import Domain
import Foundation
import Storage
import UsageEngine

/// Limit alerts (increments 2.1–2.3). The engine's events become alerts through `AlertPlanner` (pure, tested); this
/// wires it to the store's receipts and to the notification center. Alerts need notification permission; nothing is
/// shown in demo mode, while snoozed, or twice for the same crossing. During quiet hours approaching alerts wait for
/// one digest at their end and the rest arrive without sound; reset reminders are scheduled ahead with the
/// notification center (`ReminderPlanner`, pure, tested) and kept in step with the readings.
extension AppModel {
    /// Called with every batch of engine events: Claude Code frames, Codex readings and the 30 s tick.
    func handleEngineEvents(_ events: [EngineEvent]) async {
        guard !events.isEmpty, notificationStatus == .authorized, let store else { return }
        let now = environment.clock.now()
        await collectScheduledDeliveries()
        guard let history = try? await store.alertHistory(since: now.addingTimeInterval(-30 * 86_400)) else { return }
        let context = AlertPlanner.Context(delivered: history.delivered, deliveredKinds: history.kinds,
                                           snoozedUntil: alertsSnoozedUntil, enabled: alertsEnabled, isDemo: demo,
                                           quietHours: quietHours, timeZone: environment.timeZone)
        let decision = AlertPlanner.decide(events, context: context, now: now)
        for alert in decision.alerts {
            var shown = notification(for: alert, now: now)
            shown.passive = decision.quiet
            await environment.notifications.deliver(shown)
            try? await store.recordAlert(alert, at: now)
            diagnostics.record(.alertShown(kind: alert.kind.rawValue, level: alert.level))
        }
        // Quiet hours: a receipt each (never planned again), shown together in the digest when they end.
        if !decision.deferred.isEmpty {
            for alert in decision.deferred { try? await store.recordAlert(alert, at: now, outcome: .quietDeferred) }
            diagnostics.record(.alertsDeferred(count: decision.deferred.count))
        }
        await reconcileReminders()
        // Due while the Mac slept, now too old to be news: one receipt each (never planned again), one line in all.
        guard !decision.expired.isEmpty else { return }
        for alert in decision.expired { try? await store.recordAlert(alert, at: now, outcome: .staleDropped) }
        diagnostics.record(.alertsExpired(count: decision.expired.count))
    }

    /// What isn't driven by a reading: the digest when quiet hours end, and the reminders' reconciliation. At launch,
    /// every tick, and when the user changes either setting.
    func alertHousekeeping() async {
        await collectScheduledDeliveries()
        await deliverDigestIfDue()
        await reconcileReminders()
    }

    static func agent(of poolKey: String) -> String { poolKey.hasPrefix("codex.") ? Copy.Codex.name : "Claude Code" }

    /// The text for one alert, from the snapshot the events came with.
    func notification(for alert: AlertCandidate, now: Date) -> AlertNotification {
        let agent = Self.agent(of: alert.poolKey)
        let scope = OverviewProjection.scope(of: alert.poolKey)
        let row = (snapshot.provider?.pools ?? []).first { $0.poolKey == alert.poolKey }
            ?? snapshot.codex?.pools.first { $0.poolKey == alert.poolKey }
        let reset = row?.model.resetsAt.value.map {
            Copy.Alerts.resets(Formatting.resetTime($0, now: now, zone: environment.timeZone, locale: environment.locale))
        } ?? Copy.Alerts.noReset
        let (title, body): (String, String) = switch alert.kind {
        case .approaching: (Copy.Alerts.approaching(agent, scope, alert.level ?? 80), reset)
        case .exhausted: (Copy.Alerts.exhausted(agent, scope), reset)
        case .resetExpected: (Copy.Alerts.resetExpected(agent, scope), Copy.Alerts.notRechecked(agent))
        case .readyAgain: (Copy.Alerts.readyAgain(agent, scope),
                           row?.model.used.value.map { Copy.Alerts.verified(Int(NSDecimalNumber(decimal: $0).doubleValue.rounded())) } ?? reset)
        case .resetReminder: (Copy.Alerts.resetReminder(agent, scope, reminderLead ?? 0), reset)   // scheduled, see `reminder(for:)`
        }
        return AlertNotification(identifier: alert.dedupKey, title: title, body: body, threadID: "pool:" + alert.poolKey,
                                 relevance: alert.relevance, snoozable: alert.kind == .approaching || alert.kind == .exhausted)
    }

    public func setAlertsEnabled(_ on: Bool) async {
        alertsEnabled = on
        try? await store?.setPreference(Pref.alertsEnabled, on, now: environment.clock.now())
        await reconcileReminders()
    }

    /// §1.6: off by default; a change can end quiet hours, so the digest and the reminders' sound are re-decided.
    public func setQuietHours(_ value: QuietHours) async {
        quietHours = value
        try? await store?.setPreference(Pref.quietHours, value, now: environment.clock.now())
        await alertHousekeeping()
    }

    /// §2: minutes before a reported reset; nil turns reminders off (the default).
    public func setReminderLead(_ minutes: Int?) async {
        reminderLead = minutes
        try? await store?.setPreference(Pref.reminderLead, minutes ?? 0, now: environment.clock.now())
        await reconcileReminders()
    }

    /// "Snooze 1 h" from an alert or Settings; nil resumes.
    public func snoozeAlerts(for duration: TimeInterval?) async {
        let until = duration.map { environment.clock.now().addingTimeInterval($0) }
        alertsSnoozedUntil = until
        try? await store?.setPreference(Pref.alertsSnoozedUntil, until, now: environment.clock.now())
    }

    /// An alert's action, from the notification center.
    func handleAlertAction(_ action: AlertAction) async {
        switch action {
        case .snoozeOneHour: await snoozeAlerts(for: 3600)
        case .open:
            detailsSection = .limits
            dashboardRequests += 1          // MenuBarLabel opens the Dashboard window
        }
    }
}

// MARK: - Quiet-hours digest (§1.6)

extension AppModel {
    func collectScheduledDeliveries() async {
        guard !demo, !snapshot.isDemo, let store else { return }
        let now = environment.clock.now()
        for note in await environment.notifications.deliveredSchedules() {
            try? await store.recordScheduledDelivery(identifier: note.identifier, deliveredAt: note.deliveredAt, now: now)
        }
    }

    /// The approaching alerts quiet hours held back, as one quiet notification once they end.
    func deliverDigestIfDue() async {
        guard notificationStatus == .authorized, let store, let held = try? await store.deferredAlerts(),
              let newest = held.last?.deferredAt else { return }
        let now = environment.clock.now()
        switch AlertPlanner.digest(newestDeferral: newest, quietHours: quietHours, snoozedUntil: alertsSnoozedUntil,
                                   timeZone: environment.timeZone, now: now) {
        case .wait: return
        case .deliver where alertsEnabled && !demo:
            await environment.notifications.deliver(digest(for: held, now: now))
            try? await store.recordDigest(at: now, outcome: .delivered)
            diagnostics.record(.digestShown(count: held.count))
        case .deliver:                                   // alerts switched off since: settle without showing
            try? await store.recordDigest(at: now, outcome: .staleDropped)
        case .expired:
            try? await store.recordDigest(at: now, outcome: .staleDropped)
            diagnostics.record(.alertsExpired(count: held.count))
        }
    }

    /// One line per pool, its highest crossing, in the order the limits are shown.
    func digest(for held: [Store.DeferredAlert], now: Date) -> AlertNotification {
        var highest: [String: Int] = [:]
        for alert in held { highest[alert.poolKey] = max(highest[alert.poolKey] ?? 0, alert.level ?? 80) }
        let order = OverviewProjection.poolOrder
        let pools = highest.keys.sorted { (order.firstIndex(of: $0) ?? order.count, $0) < (order.firstIndex(of: $1) ?? order.count, $1) }
        let lines = pools.map { Copy.Alerts.approaching(Self.agent(of: $0), OverviewProjection.scope(of: $0), highest[$0] ?? 80) + "." }
        return AlertNotification(identifier: "digest|\(Int64((now.timeIntervalSince1970 * 1000).rounded()))", title: Copy.Alerts.digestTitle,
                                 body: lines.joined(separator: "\n"), threadID: "digest", relevance: 0.2, snoozable: false, passive: true)
    }
}

// MARK: - Reset reminders (§2)

extension AppModel {
    /// Brings the notification center's reminders in line with the current windows: superseded ones removed, new and
    /// moved ones (re)scheduled, ones more than 15 minutes overdue dropped with one diagnostic line. Never a flood:
    /// nothing is scheduled for an instant already past.
    func reconcileReminders() async {
        guard notificationStatus == .authorized, let store else { return }
        let now = environment.clock.now()
        var windows: [ReminderPlanner.Window] = []
        if !demo, !snapshot.isDemo, let states = try? await store.poolStates() {
            // A pool counts while its agent is connected: removing Claude Code or switching Codex off cancels its reminders.
            let live = Set(((snapshot.provider?.pools ?? []) + (snapshot.codex?.pools ?? []))
                .filter { $0.model.connection == .connected }.map(\.poolKey))
            windows = states.compactMap { state in
                guard live.contains(state.poolKey), let window = state.window, window.closedAt == nil, let resetsAt = window.resetsAt else { return nil }
                return ReminderPlanner.Window(poolKey: state.poolKey, windowID: window.id, resetsAt: resetsAt)
            }
        }
        let history = try? await store.alertHistory(since: now.addingTimeInterval(-30 * 86_400))
        // Expected-reset alerts are decided on the app tick, where the 15-minute age limit can be enforced.
        // A calendar notification has no expiration deadline and can otherwise appear days after a sleeping Mac wakes.
        let desired = Array(ReminderPlanner.plan(windows, leadMinutes: reminderLead, now: now).filter { history?.delivered.contains($0.identifier) != true }
            .sorted { $0.fireAt < $1.fireAt }.prefix(ReminderPlanner.pendingLimit))
        let active = Set(reminderLead != nil ? windows.map { ReminderPlanner.identifier(poolKey: $0.poolKey, windowID: $0.windowID) } : [])
        let pending = await environment.notifications.pendingReminders()
        let changes = ReminderPlanner.reconcile(desired: desired,
                                                pending: pending.map { .init(identifier: $0.notification.identifier, fireAt: $0.fireAt) }, now: now,
                                                activeIdentifiers: active)
        await environment.notifications.removePending(changes.remove)
        // Adding an identifier that is pending replaces it: the same window keeps one request whatever its reset does.
        // Text and quiet-hours delivery are compared too, so a new zone or quiet-hours change re-plans it.
        let held = Dictionary(pending.map { ($0.notification.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        var accepted: [ReminderPlanner.Planned] = []
        for plan in desired {
            let request = reminder(for: plan)
            do {
                if held[plan.identifier] != request { try await environment.notifications.schedule(request) }
                accepted.append(plan)
            } catch { diagnostics.record(.notifications(status: "schedule failed")) }
        }
        try? await store.recordNotificationSchedules(accepted, now: now,
                                                     enabled: !demo && !snapshot.isDemo && (alertsEnabled || reminderLead != nil),
                                                     activeIdentifiers: active)
        if !changes.expired.isEmpty { diagnostics.record(.remindersExpired(count: changes.expired.count)) }
    }

    /// One reminder's request. The reset time is written as it will read when the reminder fires.
    func reminder(for plan: ReminderPlanner.Planned) -> ScheduledAlert {
        let time = Formatting.resetTime(plan.resetsAt, now: plan.fireAt, zone: environment.timeZone, locale: environment.locale)
        let note = AlertNotification(identifier: plan.identifier,
                                     title: plan.kind == .resetExpected
                                        ? Copy.Alerts.resetExpected(Self.agent(of: plan.poolKey), OverviewProjection.scope(of: plan.poolKey))
                                        : Copy.Alerts.resetReminder(Self.agent(of: plan.poolKey), OverviewProjection.scope(of: plan.poolKey), plan.leadMinutes),
                                     body: plan.kind == .resetExpected ? Copy.Alerts.notRechecked(Self.agent(of: plan.poolKey)) : Copy.Alerts.reportedReset(time),
                                     threadID: "pool:" + plan.poolKey,
                                     relevance: plan.kind.relevance, snoozable: false,
                                     passive: quietHours.isActive(at: plan.fireAt, in: environment.timeZone))
        return ScheduledAlert(notification: note, fireAt: plan.fireAt)
    }
}
