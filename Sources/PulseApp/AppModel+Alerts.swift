import DesignSystem
import Domain
import Foundation
import Storage
import UsageEngine

/// Limit alerts (increments 2.1–2.3). The engine's events become alerts through `AlertPlanner` (pure, tested); this
/// wires it to the store's receipts and to the notification center. Alerts need notification permission; nothing is
/// shown in demo mode, while snoozed, or twice for the same crossing.
extension AppModel {
    /// Called with every batch of engine events: Claude Code frames, Codex readings and the 30 s tick.
    func handleEngineEvents(_ events: [EngineEvent]) async {
        guard !events.isEmpty, notificationStatus == .authorized, let store else { return }
        let now = environment.clock.now()
        guard let history = try? await store.alertHistory(since: now.addingTimeInterval(-30 * 86_400)) else { return }
        let context = AlertPlanner.Context(delivered: history.delivered, deliveredKinds: history.kinds,
                                           snoozedUntil: alertsSnoozedUntil, enabled: alertsEnabled, isDemo: demo)
        for alert in AlertPlanner.plan(events, context: context, now: now) {
            await environment.notifications.deliver(notification(for: alert, now: now))
            try? await store.recordAlert(alert, at: now)
            diagnostics.record(.alertShown(kind: alert.kind.rawValue, level: alert.level))
        }
    }

    /// The text for one alert, from the snapshot the events came with.
    func notification(for alert: AlertCandidate, now: Date) -> AlertNotification {
        let agent = alert.poolKey.hasPrefix("codex.") ? Copy.Codex.name : "Claude Code"
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
        }
        return AlertNotification(identifier: alert.dedupKey, title: title, body: body, threadID: "pool:" + alert.poolKey,
                                 relevance: alert.relevance, snoozable: alert.kind == .approaching || alert.kind == .exhausted)
    }

    public func setAlertsEnabled(_ on: Bool) async {
        alertsEnabled = on
        try? await store?.setPreference(Pref.alertsEnabled, on, now: environment.clock.now())
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
