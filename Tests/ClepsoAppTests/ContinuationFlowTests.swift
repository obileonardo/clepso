import ClaudeCodeAdapter
import Domain
import Foundation
import ShimProtocol
import Storage
import Sync
import Testing
import UsageEngine
@testable import ClepsoApp

/// Exercise the production mapper → store → view model → notification flow with the injected notification center.
/// Unix transport is tested separately: this suite also runs in restricted execution environments with no sockets.
@MainActor struct ContinuationFlowTests {
    func feed(_ model: AppModel, clock: TestClock, used: Double, reset: Date) async throws {
        let store = try #require(model.store)
        var raw = try #require(JSONSerialization.jsonObject(with: Data(frameBytes(at: clock.now(), fiveHour: used).dropFirst(4))) as? [String: Any])
        raw["rate_limits"] = ["five_hour": ["used_pct": used, "resets_at": reset.timeIntervalSince1970]]
        let frame = try JSONDecoder().decode(JSONValue.self, from: JSONSerialization.data(withJSONObject: raw))
        let mapped = try #require(FrameMapper.map(frame, connectionID: store.connectionID, receivedAt: clock.now()))
        let result = try await store.ingest(mapped.observations, session: .init(sessionRef: mapped.sessionRef ?? "test", modelID: mapped.modelID, modelDisplayName: mapped.modelDisplayName))
        await model.refresh()
        await model.handleEngineEvents(result.events)
    }

    @Test("A fired reminder, without an exhausted alert, qualifies Ready again exactly once")
    func reminderToReady() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock(), notes = FakeNotifications()
        let model = box.model(clock: clock, notifications: notes)
        await model.start(); defer { model.stop() }
        await model.requestNotifications()
        let reset = clock.now() + 3600
        try await feed(model, clock: clock, used: 85, reset: reset)
        #expect(notes.delivered.isEmpty)
        await model.setReminderLead(15)
        #expect(notes.pending.count == 1)
        clock.advance(2700)
        notes.fireDue(at: clock.now())
        await model.alertHousekeeping()
        #expect(notes.delivered.count == 1)
        clock.advance(901)
        try await feed(model, clock: clock, used: 3, reset: reset + 18_000)
        #expect(notes.delivered.filter { $0.identifier.contains("|readyAgain|") }.count == 1)
        clock.advance(1)
        try await feed(model, clock: clock, used: 3, reset: reset + 18_000)
        #expect(notes.delivered.filter { $0.identifier.contains("|readyAgain|") }.count == 1)
    }

    @Test("Expected resets use the age-checked app tick and never leave a stale OS trigger")
    func expectedResetFreshness() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock(), notes = FakeNotifications()
        let model = box.model(clock: clock, notifications: notes)
        await model.start(); defer { model.stop() }
        await model.requestNotifications()
        let reset = clock.now() + 3600
        try await feed(model, clock: clock, used: 40, reset: reset)
        clock.advance(60)
        try await feed(model, clock: clock, used: 100, reset: reset)
        #expect(notes.pending.isEmpty)
        clock.advance(3541)
        await model.refreshNow()
        #expect(notes.delivered.filter { $0.identifier.contains("|resetExpected|") }.count == 1)
        await model.refreshNow()
        #expect(notes.delivered.filter { $0.identifier.contains("|resetExpected|") }.count == 1)
        #expect(notes.pending.isEmpty)
    }

    @Test("Calendar export uses the reported weekly instant and creates nothing without a tap")
    func calendarExport() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock()
        var environment = box.model(clock: clock).environment
        environment.calendarDirectory = box.root.appendingPathComponent("calendar")
        var opened: [URL] = []
        environment.openFile = { opened.append($0) }
        let model = AppModel(environment: environment)
        await model.start(); defer { model.stop() }
        let reset = clock.now() + 7 * 86_400
        let store = try #require(model.store)
        let subject = SubjectKey.pool(providerPoolKey: "claude-code.rate_limits.seven_day")
        func observation(_ kind: MetricKind, _ value: MetricValue) -> IncomingObservation {
            IncomingObservation(subject: subject, sessionRef: nil, modelID: nil, kind: kind, value: value,
                                observedAt: clock.now(), receivedAt: clock.now(), evidence: .officialLocalTelemetry,
                                quality: .reported, sourceVersion: nil, dedupeKey: kind.rawValue)
        }
        _ = try await store.ingest([observation(.quotaUsedPct, .percent(100)), observation(.resetAt, .instant(reset))], session: nil)
        await model.refresh()
        #expect(opened.isEmpty)
        let row = try #require(model.snapshot.provider?.pools.first)
        #expect(model.calendarEvent(for: row)?.start == reset)
        let url = try #require(model.addResetToCalendar(row))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("BEGIN:VCALENDAR") && text.contains("BEGIN:VEVENT") && text.contains("END:VCALENDAR"))
        #expect(opened == [url])
    }

    @Test("Manual readings and retention survive restart; the provider sign-in action uses the configured PKCE URL")
    func manualAndProvider() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock(), auth = MemoryAuthStore()
        var environment = box.model(clock: clock).environment
        environment.sync = SyncClient(config: SyncConfig(projectURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "sb_publishable_test", redirectURL: SyncConfig.redirectURL, enabledProviders: [.github]),
            transport: OfflineTransport(), store: auth, now: { clock.now() })
        var opened: [URL] = []
        environment.openLink = { opened.append($0) }
        let model = AppModel(environment: environment)
        await model.start(); defer { model.stop() }
        try await model.saveManualAllowance(providerID: "cursor", window: .weekly, usedPercent: 83, resetsAt: nil,
                                            observedAt: clock.now(), planID: nil, paidOverage: false)
        #expect(model.manualAllowances.first?.usedPercent == 83)
        await model.signIn(provider: .apple)
        #expect(opened.isEmpty)
        await model.signIn(provider: .github)
        #expect(opened.first?.host == "example.supabase.co" && auth.load().pendingVerifier != nil)
        #expect(auth.load().session == nil, "opening OAuth never fabricates a signed-in account")
        let exported = try #require(model.manualAllowances.first)
        try await model.removeManualAllowance(exported)
        #expect(model.manualAllowances.isEmpty)
    }
}
