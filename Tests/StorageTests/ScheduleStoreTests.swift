import Domain
import Foundation
import GRDB
import Testing
import UsageEngine
@testable import Storage

struct ScheduleStoreTests {
    @Test("A scheduled reminder persists, moves in place and only real delivery qualifies Ready again")
    func reminderLifecycle() async throws {
        let store = try Store.inMemory(now: t0, policy: .everyReading)
        let reset = t0.addingTimeInterval(7200)
        _ = try await store.ingest(batch(session: "A", used: 85, reset: reset, at: 0), session: meta("A"))
        let state = try #require(try await fiveHour(store)), window = try #require(state.window)
        let plan = try #require(ReminderPlanner.plan([.init(poolKey: state.poolKey, windowID: window.id, resetsAt: reset)], leadMinutes: 15, now: t0).first)
        try await store.recordNotificationSchedules([plan], now: t0, enabled: true)
        #expect(try await store.scheduleStatus(plan.identifier) == "planned")
        #expect(try await store.alertHistory(since: t0).kinds[window.id] == nil)
        let moved = try #require(ReminderPlanner.plan([.init(poolKey: state.poolKey, windowID: window.id, resetsAt: reset + 60)], leadMinutes: 5, now: t0).first)
        try await store.recordNotificationSchedules([moved], now: t0 + 60, enabled: true)
        #expect(try await store.scheduleCount() == 1)
        // An on-time notification collected later remains evidence; a late OS delivery does not.
        try await store.recordScheduledDelivery(identifier: plan.identifier, deliveredAt: moved.fireAt, now: reset + 120)
        #expect(try await store.alertHistory(since: t0).kinds[window.id] == [.resetReminder])
        #expect(try await store.scheduleStatus(plan.identifier) == "delivered")
    }

    @Test("Early, cancelled or delayed notifications never create delivery receipts")
    func rejectsFalseDelivery() async throws {
        let store = try Store.inMemory(now: t0)
        let reset = t0 + 7200
        _ = try await store.ingest(batch(session: "A", used: 100, reset: reset, at: 0), session: meta("A"))
        let state = try #require(try await fiveHour(store)), window = try #require(state.window)
        let plan = try #require(ReminderPlanner.expected([.init(poolKey: state.poolKey, windowID: window.id, resetsAt: reset)], now: t0).first)
        try await store.recordNotificationSchedules([plan], now: t0, enabled: true)
        try await store.recordScheduledDelivery(identifier: plan.identifier, deliveredAt: reset - 1, now: reset)
        try await store.recordScheduledDelivery(identifier: plan.identifier, deliveredAt: reset + 901, now: reset + 901)
        #expect(try await store.alertHistory(since: t0).delivered.isEmpty)
        try await store.recordNotificationSchedules([], now: t0 + 1, enabled: false)
        try await store.recordScheduledDelivery(identifier: plan.identifier, deliveredAt: reset, now: reset)
        #expect(try await store.scheduleStatus(plan.identifier) == "cancelled")
        #expect(try await store.alertHistory(since: t0).delivered.isEmpty)
    }
}

extension Store {
    func scheduleStatus(_ id: String) throws -> String? {
        try writer.read { try String.fetchOne($0, sql: "SELECT status FROM reset_schedules WHERE id = ?", arguments: [id]) }
    }
    func scheduleCount() throws -> Int { try writer.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM reset_schedules") ?? 0 } }
}
