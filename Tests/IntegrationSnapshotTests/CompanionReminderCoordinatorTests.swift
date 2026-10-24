import Foundation
import Testing
@testable import IntegrationSnapshot

@Suite("Serialized companion notification replacement") struct CompanionReminderCoordinatorTests {
    actor Client: CompanionReminderClient {
        enum Failure: Error { case unavailable }
        var calls = 0
        var installed: [CompanionReminderPlan.Reminder] = []
        var failNext = false
        var blockFirst: Bool
        var firstStarted = false
        var continuation: CheckedContinuation<Void, Never>?
        init(blockFirst: Bool = false) { self.blockFirst = blockFirst }
        func replace(_ reminders: [CompanionReminderPlan.Reminder]) async throws {
            calls += 1
            if blockFirst, calls == 1 {
                firstStarted = true
                await withCheckedContinuation { continuation = $0 }
            }
            if failNext { failNext = false; throw Failure.unavailable }
            installed = reminders
        }
        func release() { continuation?.resume(); continuation = nil }
        func fail() { failNext = true }
    }
    func plan() -> [CompanionReminderPlan.Reminder] {
        let now = Date(timeIntervalSince1970: 1_792_665_600)
        let row = UsageSnapshot.Limit(provider: .codex, window: .fiveHour, source: .automatic,
            usedPercent: 80, observedAt: now, resetsAt: now.addingTimeInterval(3600), state: .reported)
        return CompanionReminderPlan.make(RelayEnvelope(snapshot: UsageSnapshot(generatedAt: now, limits: [row]),
            receivedAt: now, expiresAt: now.addingTimeInterval(900)), enabled: true, leadMinutes: 0, now: now)
    }
    @Test func optOutFinishesAfterSuspendedOlderAdd() async throws {
        let client = Client(blockFirst: true), coordinator = CompanionReminderCoordinator(client: client)
        let first = Task { try await coordinator.replace(plan()) }
        while !(await client.firstStarted) { await Task.yield() }
        let off = Task { try await coordinator.replace([]) }
        first.cancel() // Cancelling the caller must not leave its write racing the cleanup.
        await client.release()
        try await first.value
        try await off.value
        #expect(await client.calls == 2)
        #expect(await client.installed.isEmpty)
    }
    @Test func identicalPlansCoalesceAndFailureCanRetry() async throws {
        let client = Client(), coordinator = CompanionReminderCoordinator(client: client)
        await client.fail()
        do { try await coordinator.replace(plan()); Issue.record("Expected OS failure") } catch {}
        try await coordinator.replace(plan())
        try await coordinator.replace(plan())
        #expect(await client.calls == 2)
        #expect(await client.installed == plan())
        try await coordinator.replace([])
        try await coordinator.replace([])
        #expect(await client.calls == 3)
        #expect(await client.installed.isEmpty)
    }
}
