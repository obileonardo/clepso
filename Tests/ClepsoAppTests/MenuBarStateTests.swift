import DesignSystem
import Domain
import Foundation
import Testing
@testable import ClepsoApp

/// The menu bar status family against the design system (Logo › Menu bar): which glyph, whether the stale mark opens
/// its ring, and the text beside it, for each condition. Readings go through the real store and engine, Codex's under
/// `codex.*` keys as CodexMapper writes them, then the real projection.
extension Scenario {
    /// One pool reading (used % and reset time) observed and received at `at`.
    func pool(_ key: String, at: Date, used: Decimal, reset: Date?) async throws {
        var observations: [IncomingObservation] = []
        func add(_ kind: MetricKind, _ value: MetricValue) {
            let subject = SubjectKey.pool(providerPoolKey: key)
            observations.append(IncomingObservation(subject: subject, sessionRef: nil, modelID: nil, kind: kind, value: value,
                                                    observedAt: at, receivedAt: at, evidence: .officialLocalTelemetry,
                                                    quality: value.isAbsent ? .unknown : .reported, sourceVersion: nil,
                                                    dedupeKey: "\(subject.canonical)|\(kind.rawValue)|\(at.timeIntervalSince1970)"))
        }
        add(.quotaUsedPct, .percent(used))
        add(.resetAt, reset.map(MetricValue.instant) ?? .absent(.providerOmitted))
        _ = try await store.ingest(observations, session: nil)
    }

    func menuBar(now: Date, codex: Bool = true, showPercent: Bool = true) async throws -> OverviewSnapshot {
        _ = try await store.tick(now: now)
        var input = try await AppModel.read(store, now: now)
        input.installed = true
        input.codexEnabled = codex
        input.showPercent = showPercent
        return OverviewProjection.make(input, now: now, staleAfter: 600, zone: utc, locale: enUS)
    }
}

@Suite("Menu bar: glyph, stale mark and text per condition (design system, Menu bar)")
struct MenuBarStateTests {
    static let claude5h = "claude-code.rate_limits.five_hour", claude7d = "claude-code.rate_limits.seven_day"
    static let codex5h = "codex.rate_limits.five_hour", codex7d = "codex.rate_limits.seven_day"

    /// The founder's Mac, 19 Oct 2026 00:45: Claude Code fresh (5-hour 1 %, 7-day 56 %, read Sun 18 Oct 23:42 UTC);
    /// Codex last read Fri 16 Oct 17:35 UTC, 7-day at 100 % resetting Thu 22 Oct 06:50, 5-hour at 35 % whose reset
    /// (Fri 22:23) passed with no newer reading. The menu bar showed the flatline without the stale mark.
    @Test("Regression: a Codex limit reached two days ago shows the flatline WITH the stale mark, beside fresh Claude Code readings")
    func liveCodexCase() async throws {
        let s = try Scenario()
        let codexRead = t0 + 3 * 3600 + 35 * 60                           // Fri 16 Oct 17:35 UTC
        try await s.pool(Self.codex5h, at: codexRead, used: 35, reset: t0 + 8 * 3600 + 23 * 60)
        try await s.pool(Self.codex7d, at: codexRead, used: 100, reset: t0 + 6 * 86_400 - 7 * 3600 - 10 * 60)
        let claudeRead = t0 + 2 * 86_400 + 9 * 3600 + 42 * 60             // Sun 18 Oct 23:42 UTC
        try await s.pool(Self.claude5h, at: claudeRead, used: 1, reset: claudeRead + 4 * 3600)
        try await s.pool(Self.claude7d, at: claudeRead, used: 56, reset: claudeRead + 3 * 86_400)
        let snap = try await s.menuBar(now: claudeRead + 3 * 60)

        let codex = try #require(snap.codex)
        #expect(codex.pools.map(\.model.card) == [.resetExpected, .exhausted])
        #expect(snap.provider?.pools.allSatisfy { $0.model.valueState(now: snap.now, staleAfter: 600) == .live } == true)
        #expect(snap.icon == .exhausted && snap.iconShape == .flatline)
        #expect(snap.iconStaleMark, "the flatline is built from a 2-day-old Codex reading")
        #expect(snap.iconText == nil)                                      // UX_SPEC 1.4: icon.exhausted, text none
        #expect(snap.iconAccessibilityValue == "Limit reached, last reading is old")
        #expect(snap.aggregateLine.hasPrefix("Codex limit reached · reset expected"), "\(snap.aggregateLine)")
        #expect(!snap.aggregateLine.contains("last seen"), "Claude Code is live, so the line has no 'last seen' (UX_SPEC 1.4)")
    }

    @Test("A fresh Codex limit beside fresh Claude Code readings: flatline, no stale mark")
    func freshFlatline() async throws {
        let s = try Scenario()
        try await s.pool(Self.codex7d, at: t0, used: 100, reset: t0 + 3 * 86_400)
        try await s.pool(Self.claude5h, at: t0, used: 12, reset: t0 + 4 * 3600)
        let snap = try await s.menuBar(now: t0 + 60)
        #expect(snap.icon == .exhausted && !snap.iconStaleMark && snap.iconText == nil)
        #expect(snap.iconAccessibilityValue == "Limit reached")
    }

    @Test("A live limit behind the flatline keeps the ring closed, even when another reached limit is old")
    func liveLimitWins() async throws {
        let s = try Scenario()
        try await s.pool(Self.codex7d, at: t0, used: 100, reset: t0 + 3 * 86_400)
        try await s.pool(Self.claude5h, at: t0 + 3600, used: 100, reset: t0 + 4 * 3600)
        let snap = try await s.menuBar(now: t0 + 3600 + 60)
        #expect(snap.icon == .exhausted && !snap.iconStaleMark)
    }

    @Test("Approaching from an old reading, with another agent live: the ring opens (approaching-stale)")
    func approachingStale() async throws {
        let s = try Scenario()
        try await s.pool(Self.codex5h, at: t0, used: 85, reset: t0 + 4 * 3600)
        try await s.pool(Self.claude5h, at: t0 + 3600, used: 30, reset: t0 + 4 * 3600)
        let snap = try await s.menuBar(now: t0 + 3600 + 60)
        #expect(snap.icon == .approaching && snap.iconShape == .approaching && snap.iconStaleMark)
        #expect(snap.iconAccessibilityValue == "Nearing a limit, last reading is old")
        #expect(snap.aggregateLine == "1 limit nearing capacity")
    }

    @Test("Approaching from a live reading: the ring stays closed, and the % is the highest live value")
    func approachingLive() async throws {
        let s = try Scenario()
        try await s.pool(Self.codex5h, at: t0, used: 85, reset: t0 + 4 * 3600)
        try await s.pool(Self.claude5h, at: t0 + 3600, used: 91, reset: t0 + 4 * 3600)
        let snap = try await s.menuBar(now: t0 + 3600 + 60)
        #expect(snap.icon == .approaching && !snap.iconStaleMark && snap.iconText == "91%")
        #expect(snap.aggregateLine == "2 limits nearing capacity")
    }

    @Test("Everything old: approaching keeps its shape with the stale mark, no % and 'last seen' (UX_SPEC 1.4)")
    func allOldApproaching() async throws {
        let s = try Scenario()
        try await s.pool(Self.claude5h, at: t0, used: 88, reset: t0 + 4 * 3600)
        let snap = try await s.menuBar(now: t0 + 11 * 60)
        #expect(snap.icon == .approaching && snap.iconStaleMark && snap.iconText == nil)
        #expect(snap.aggregateLine == "1 limit nearing capacity · last seen 11m ago")
    }

    @Test("Text rules: % beside the beat and approaching only, from live readings, and only with the setting on")
    func textRules() async throws {
        let s = try Scenario()
        try await s.pool(Self.claude5h, at: t0, used: 41, reset: t0 + 4 * 3600)
        #expect(try await s.menuBar(now: t0 + 60).iconText == "41%")
        #expect(try await s.menuBar(now: t0 + 60, showPercent: false).iconText == nil)
        #expect(try await s.menuBar(now: t0 + 11 * 60).iconText == nil)                         // stale clock: none
        try await s.pool(Self.claude5h, at: t0 + 12 * 60, used: 84, reset: t0 + 4 * 3600)
        #expect(try await s.menuBar(now: t0 + 13 * 60).iconText == "84%")
        #expect(try await s.menuBar(now: t0 + 13 * 60, showPercent: false).iconText == nil)
        try await s.pool(Self.claude5h, at: t0 + 14 * 60, used: 100, reset: t0 + 4 * 3600)
        #expect(try await s.menuBar(now: t0 + 15 * 60).iconText == nil)                         // flatline: none
    }

    @Test("The stale mark only ever goes on the approaching and flatline glyphs, the two the kit draws it for")
    func staleMarkOnlyWhereTheKitHasIt() async throws {
        let s = try Scenario()
        var seen: [(MenuBarIcon.Shape, Bool)] = []
        for (minutes, used) in [(0, 41), (20, 88), (40, 100)] as [(Double, Decimal)] {
            try await s.pool(Self.claude5h, at: t0 + minutes * 60, used: used, reset: t0 + 4 * 3600)
            for after in [1.0, 11.0] {
                let snap = try await s.menuBar(now: t0 + (minutes + after) * 60)
                seen.append((snap.iconShape, snap.iconStaleMark))
            }
        }
        for (shape, mark) in seen where mark { #expect(shape == .approaching || shape == .flatline, "\(shape)") }
        #expect(seen.map(\.0) == [.beat, .stale, .approaching, .approaching, .flatline, .flatline])
        #expect(seen.map(\.1) == [false, false, false, true, false, true])
    }
}
