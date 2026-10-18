import Foundation
import Testing
@testable import PulseApp

/// 2.1: a limit crossing on a real frame becomes one alert, with the agent, limit and reset in its text.
@MainActor
struct LimitAlertTests {
    @Test("80% crossing alerts once; repeats, snooze and demo stay silent; limit reached alerts again")
    func crossingsAlertOnce() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock(), notifications = FakeNotifications()
        let model = box.model(clock: clock, notifications: notifications)
        await model.start(); defer { model.stop() }
        await model.requestNotifications()
        #expect(model.notificationStatus == .authorized)

        func frame(_ pct: Double) async throws {
            clock.advance(60)
            #expect(send(model.environment.socketPath, try frameBytes(at: clock.now(), fiveHour: pct)))
            #expect(await eventually { model.snapshot.provider?.pools.first?.model.used.value == Decimal(pct) })
        }
        try await frame(50)                                   // first value: never an alert (G2)
        try await frame(83)
        #expect(await eventually { notifications.delivered.count == 1 })
        let alert = try #require(notifications.delivered.first)
        #expect(alert.title == "Claude Code · 5-hour limit at 80%")
        #expect(alert.body.hasPrefix("Resets ") && alert.snoozable && alert.threadID == "pool:claude-code.rate_limits.five_hour")

        try await frame(85)                                   // same window, no new crossing
        await model.snoozeAlerts(for: 3600)
        try await frame(96)                                   // 95% crossed while snoozed
        try await Task.sleep(for: .milliseconds(300))
        #expect(notifications.delivered.count == 1)

        await model.snoozeAlerts(for: nil)
        try await frame(100)
        #expect(await eventually { notifications.delivered.count == 2 })
        #expect(notifications.delivered.last?.title == "Claude Code · 5-hour limit reached")
        #expect(Set(notifications.delivered.map(\.identifier)).count == 2)
    }

    @Test("Limit alerts off: nothing is shown")
    func switchedOff() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock(), notifications = FakeNotifications()
        let model = box.model(clock: clock, notifications: notifications)
        await model.start(); defer { model.stop() }
        await model.requestNotifications()
        await model.setAlertsEnabled(false)
        for pct in [50.0, 99] {
            clock.advance(60)
            #expect(send(model.environment.socketPath, try frameBytes(at: clock.now(), fiveHour: pct)))
            #expect(await eventually { model.snapshot.provider?.pools.first?.model.used.value == Decimal(pct) })
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(notifications.delivered.isEmpty)
    }

    @Test("Clicking an alert opens the Dashboard on Limits; Snooze 1 h snoozes")
    func actions() async {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock()
        let model = box.model(clock: clock)
        await model.start(); defer { model.stop() }
        await model.handleAlertAction(.open)
        #expect(model.dashboardRequests == 1 && model.detailsSection == .limits)
        await model.handleAlertAction(.snoozeOneHour)
        #expect(model.alertsSnoozedUntil == clock.now().addingTimeInterval(3600))
    }
}
