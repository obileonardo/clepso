import DesignSystem
import Domain
import Foundation
import Storage
import Testing
@testable import PulseApp

/// Feeds readings through the real store and engine, then projects: the same path the app uses.
struct Scenario {
    let store: Store
    init() throws { store = try Store.inMemory(now: t0) }

    /// One frame's pool readings at `at`. nil `used` means the provider omitted the field.
    func reading(at: Date, fiveHour: Decimal?, fiveHourReset: Date? = nil, sevenDay: Decimal? = nil, sevenDayReset: Date? = nil) async throws {
        var observations: [IncomingObservation] = []
        func add(_ key: String, _ kind: MetricKind, _ value: MetricValue) {
            let subject = SubjectKey.pool(providerPoolKey: key)
            observations.append(IncomingObservation(subject: subject, sessionRef: nil, modelID: nil, kind: kind, value: value,
                                                    observedAt: at, receivedAt: at, evidence: .officialLocalTelemetry,
                                                    quality: value.isAbsent ? .unknown : .reported, sourceVersion: "2.1.302",
                                                    dedupeKey: "\(subject.canonical)|\(kind.rawValue)|\(at.timeIntervalSince1970)"))
        }
        add("claude-code.rate_limits.five_hour", .quotaUsedPct, fiveHour.map(MetricValue.percent) ?? .absent(.providerOmitted))
        add("claude-code.rate_limits.five_hour", .resetAt, fiveHourReset.map(MetricValue.instant) ?? .absent(.providerOmitted))
        if sevenDay != nil || sevenDayReset != nil {
            add("claude-code.rate_limits.seven_day", .quotaUsedPct, sevenDay.map(MetricValue.percent) ?? .absent(.providerOmitted))
            add("claude-code.rate_limits.seven_day", .resetAt, sevenDayReset.map(MetricValue.instant) ?? .absent(.providerOmitted))
        }
        _ = try await store.ingest(observations, session: nil)
    }

    func snapshot(now: Date, installed: Bool = true, demo: Bool = false) async throws -> OverviewSnapshot {
        _ = try await store.tick(now: now)
        var input = try await AppModel.read(store)
        input.installed = installed
        input.isDemo = demo
        return OverviewProjection.make(input, now: now, staleAfter: 600, zone: utc, locale: enUS)
    }
}

extension MetricValue {
    var isAbsent: Bool { if case .absent = self { true } else { false } }
}

@Suite("Overview projection: menu bar icon and aggregate line (UX_SPEC §1.4)")
struct OverviewProjectionTests {
    @Test("All available and live: ring, highest percent, 'Reported limits available' (C7: never 'All')")
    func ok() async throws {
        let s = try Scenario()
        try await s.reading(at: t0, fiveHour: 41, fiveHourReset: t0 + 9000, sevenDay: 21, sevenDayReset: t0 + 400_000)
        let snap = try await s.snapshot(now: t0 + 60)
        #expect(snap.icon == .ok && !snap.iconStaleMark && snap.iconShape == .ring)
        #expect(snap.iconText == "41%")
        #expect(snap.aggregateLine == "Reported limits available · updated 1m ago")
        #expect(snap.iconAccessibilityLabel == "Pulse: Reported limits available · updated 1m ago")
        #expect(snap.provider?.unreadLimitWindows == 0)
        #expect(snap.provider?.pools.map(\.model.scope) == ["5-hour", "7-day"])
        #expect(snap.provider?.pools.first?.providerField == "rate_limits.five_hour.used_percentage")
        // F15: metrics live, no plan chosen.
        #expect(snap.provider?.header == "Claude Code metrics connected · plan not verified")
        #expect(snap.provider?.plan == .notSet)
    }

    @Test("Approaching or nearly exhausted: notch, count of pools nearing capacity")
    func approaching() async throws {
        let s = try Scenario()
        try await s.reading(at: t0, fiveHour: 83, fiveHourReset: t0 + 9000, sevenDay: 96, sevenDayReset: t0 + 400_000)
        let snap = try await s.snapshot(now: t0 + 60)
        #expect(snap.icon == .approaching && snap.iconShape == .notch)
        #expect(snap.iconText == "96%")
        #expect(snap.aggregateLine == "2 limits nearing capacity")
    }

    @Test("Exhausted outranks approaching and shows no percentage")
    func exhaustedWins() async throws {
        let s = try Scenario()
        try await s.reading(at: t0, fiveHour: 100, fiveHourReset: t0 + 9000, sevenDay: 83, sevenDayReset: t0 + 400_000)
        let snap = try await s.snapshot(now: t0 + 60)
        #expect(snap.icon == .exhausted && snap.iconShape == .bar && snap.iconText == nil)
        #expect(snap.aggregateLine == "Claude Code limit reached · reset expected 4:30 PM")
    }

    @Test("Exhausted with no reset time says so instead of inventing one")
    func exhaustedNoReset() async throws {
        let s = try Scenario()
        try await s.reading(at: t0, fiveHour: 100)
        let snap = try await s.snapshot(now: t0 + 60)
        #expect(snap.aggregateLine == "Claude Code limit reached · reset time not reported")
    }

    @Test("AT-08: F05 reset passed, then 11 minutes of silence: stale mark, 'last seen', never 'Live' or 'Available again'")
    func resetExpectedThenStale() async throws {
        let s = try Scenario()
        try await s.reading(at: t0, fiveHour: 100, fiveHourReset: t0 + 120, sevenDay: 30, sevenDayReset: t0 + 400_000)
        let atReset = try await s.snapshot(now: t0 + 180)
        #expect(atReset.provider?.pools.first?.model.card == .resetExpected)
        #expect(atReset.aggregateLine == "Claude Code reset expected · awaiting next update")

        let later = try await s.snapshot(now: t0 + 180 + 11 * 60)
        #expect(later.icon == .exhausted && later.iconStaleMark)
        #expect(later.aggregateLine.contains("last seen"))
        var texts = [later.aggregateLine]
        for row in later.provider?.pools ?? [] {
            texts.append(StatusStyles.of(row.model.card).label)
            texts.append(AccessibilityText.poolRow(row.model, now: later.now, staleAfter: 600, zone: utc, locale: enUS))
        }
        #expect(!texts.contains { $0.contains("Live") || $0.localizedCaseInsensitiveContains("available again") }, "\(texts)")
    }

    @Test("Everything stale: clock shape and 'Last seen', no percentage in the menu bar")
    func stale() async throws {
        let s = try Scenario()
        try await s.reading(at: t0, fiveHour: 41, fiveHourReset: t0 + 9000)
        let snap = try await s.snapshot(now: t0 + 11 * 60)
        #expect(snap.icon == .stale && snap.iconShape == .clock && snap.iconText == nil)
        #expect(snap.aggregateLine == "Last seen 11m ago")
    }

    @Test("F06: reporting but no rate limits is 'not available', never 0% and never stale")
    func noRateLimits() async throws {
        let s = try Scenario()
        try await s.reading(at: t0, fiveHour: nil, sevenDay: nil, sevenDayReset: nil)
        let snap = try await s.snapshot(now: t0 + 30)
        #expect(snap.icon == .ok && snap.iconText == nil)
        #expect(snap.aggregateLine == "Account quota not available · updated just now")
        let row = try #require(snap.provider?.pools.first)
        #expect(row.model.used.value == nil)
        #expect(row.model.valueState(now: snap.now, staleAfter: 600) == .notAvailable)
    }

    @Test("Available again only after the verified G6 reading, and only for 60 minutes")
    func availableAgainReverts() async throws {
        let s = try Scenario()
        try await s.reading(at: t0, fiveHour: 100, fiveHourReset: t0 + 600)
        try await s.reading(at: t0 + 900, fiveHour: 4, fiveHourReset: t0 + 900 + 18_000)
        let soon = try await s.snapshot(now: t0 + 960)
        #expect(soon.provider?.pools.first?.model.card == .availableAgain)
        let hourLater = try await s.snapshot(now: t0 + 900 + 3601)
        #expect(hourLater.provider?.pools.first?.model.card == .available)
    }

    @Test("Demo: dashed ring, DEMO text, and the label says demo data (AT-09)")
    func demo() async throws {
        let s = try Scenario()
        try await s.reading(at: t0, fiveHour: 83, fiveHourReset: t0 + 9000)
        let snap = try await s.snapshot(now: t0 + 60, demo: true)
        #expect(snap.icon == .demo && snap.iconShape == .dashed && snap.iconText == "DEMO")
        #expect(snap.iconAccessibilityLabel.localizedCaseInsensitiveContains("demo data"))
        let row = try #require(snap.provider?.pools.first)
        #expect(AccessibilityText.poolRow(row.model, now: snap.now, staleAfter: 600, zone: utc, locale: enUS, isDemo: true).hasPrefix("Demo data,"))
    }

    @Test("Nothing connected, or installed and waiting: empty states, no provider card")
    func emptyStates() async throws {
        let s = try Scenario()
        let none = try await s.snapshot(now: t0, installed: false)
        #expect(none.empty == .notConnected && none.provider == nil && none.aggregateLine == "Not connected")
        let waiting = try await s.snapshot(now: t0, installed: true)
        #expect(waiting.empty == .waitingForFirstReading && waiting.aggregateLine == "Installed · waiting for first reading")
    }

    @Test("Removed from Claude Code, only old readings left: cards say Not connected; frames arriving count as connected")
    func connection() async throws {
        let s = try Scenario()
        try await s.reading(at: t0, fiveHour: 41, fiveHourReset: t0 + 9000)
        #expect(try await s.snapshot(now: t0 + 60, installed: false).provider?.pools.first?.model.card == .available)
        #expect(try await s.snapshot(now: t0 + 11 * 60, installed: false).provider?.pools.first?.model.card == .disconnected)
    }

    @Test("Plan header by provenance (UX_SPEC §1.3)")
    func planHeader() async throws {
        let s = try Scenario()
        try await s.reading(at: t0, fiveHour: 41, fiveHourReset: t0 + 9000)
        try await s.store.setPlan(catalogID: "anthropic.max.5x", displayName: "Claude Max 5×", evidence: .userConfirmed, now: t0)
        #expect(try await s.snapshot(now: t0 + 60).provider?.header == "Claude · Max 5× · User confirmed")
        try await s.store.setPlan(catalogID: "anthropic.pro", displayName: "Claude Pro", evidence: .userSelectedUnverified, now: t0 + 1)
        #expect(try await s.snapshot(now: t0 + 60).provider?.header == "Claude · Pro · Selected · not verified")
        try await s.store.setPlan(catalogID: nil, displayName: nil, evidence: .userSelectedUnverified, now: t0 + 2)   // "Not sure"
        #expect(try await s.snapshot(now: t0 + 20 * 60).provider?.header == "Claude · Plan not set", "no plan and nothing live")
    }

    @Test("Inspector data is prefetched: newest three readings, newest first")
    func recentReadings() async throws {
        let s = try Scenario()
        for (i, used) in [10, 20, 30, 40].enumerated() {
            try await s.reading(at: t0 + Double(i) * 60, fiveHour: Decimal(used), fiveHourReset: t0 + 9000)
        }
        let snap = try await s.snapshot(now: t0 + 240)
        let recent = try #require(snap.provider?.pools.first?.recent)
        #expect(recent.map(\.value) == [.percent(40), .percent(30), .percent(20)])
        #expect(recent.allSatisfy { $0.sourceVersion == "2.1.302" && $0.quality == .reported })
    }
}
