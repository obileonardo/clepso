import Domain
import Foundation
import Testing
@testable import UsageEngine
@testable import ClepsoApp

/// Founder decisions 19 Oct 2026 (decision sheet §2 and §3): an old reading is never drawn as if measured up to NOW, and
/// the inspector says how old a number is and whether its window has already reset. The founder's Codex state is the
/// fixture: weekly 100% and 5-hour 35%, both last read 16 Oct 17:35:38 UTC; the 5-hour reset (22:23 that night) has
/// passed, the weekly one (22 Oct 06:50) has not. The clock is the test's own `now`.
@MainActor
struct StaleReadingTests {
    let fixture = CodexProvenanceTests()
    var now: Date { fixture.now }                                            // 19 Oct 2026 08:53:20 UTC
    let measured = Date(timeIntervalSince1970: 1_792_172_138)                // 16 Oct 2026 17:35:38 UTC
    let utc = TimeZone(identifier: "UTC")!
    let locale = Locale(identifier: "en_GB")

    func snapshot() -> OverviewSnapshot {
        var input = fixture.founderInput()
        input.history["codex.rate_limits.seven_day"] = [UsagePoint(at: measured.addingTimeInterval(-33), usedPct: 100), UsagePoint(at: measured, usedPct: 100)]
        input.history["codex.rate_limits.five_hour"] = [UsagePoint(at: measured.addingTimeInterval(-33), usedPct: 34), UsagePoint(at: measured, usedPct: 35)]
        input.history["claude-code.rate_limits.five_hour"] = [UsagePoint(at: now.addingTimeInterval(-120), usedPct: 40)]
        return fixture.make(input)
    }

    func chart(_ row: PoolRow) -> WindowChart { WindowChart(row: row, now: now, zone: utc, locale: locale) }

    // MARK: - The chart's unmeasured span

    @Test("The hatch starts only once a reading is stale (10 minutes), so ordinary gaps between turns stay solid")
    func spanStartsAfterTheStalenessRule() throws {
        let ttl = Freshness.localTelemetryTTL
        #expect(UnmeasuredSpan.make(lastReading: now.addingTimeInterval(-5 * 60), resetsAt: nil, now: now, staleAfter: ttl) == nil)
        #expect(UnmeasuredSpan.make(lastReading: nil, resetsAt: nil, now: now, staleAfter: ttl) == nil)
        let last = now.addingTimeInterval(-11 * 60)
        let span = try #require(UnmeasuredSpan.make(lastReading: last, resetsAt: now.addingTimeInterval(3600), now: now, staleAfter: ttl))
        #expect(span.from == last.addingTimeInterval(ttl) && span.resetPassed == nil, "a reset still to come is not a passed one")
    }

    @Test("A reset counts as passed in the span only when it fell after the newest reading and before now")
    func resetPassedOnlyInsideTheSpan() {
        let ttl = Freshness.localTelemetryTTL, last = now.addingTimeInterval(-3 * 86_400)
        let reset = now.addingTimeInterval(-86_400)
        #expect(UnmeasuredSpan.make(lastReading: last, resetsAt: reset, now: now, staleAfter: ttl)?.resetPassed == reset)
        #expect(UnmeasuredSpan.make(lastReading: last, resetsAt: last.addingTimeInterval(-60), now: now, staleAfter: ttl)?.resetPassed == nil)
        #expect(UnmeasuredSpan.make(lastReading: last, resetsAt: nil, now: now, staleAfter: ttl)?.resetPassed == nil)
    }

    @Test("A reset that passed less than a window ago keeps its window on the axis, carried on to NOW")
    func axisCarriesOnToNow() {
        let fiveHours: TimeInterval = 5 * 3600
        let recent = now.addingTimeInterval(-2 * 3600)
        #expect(UnmeasuredSpan.axis(length: fiveHours, resetsAt: recent, now: now) == recent.addingTimeInterval(-fiveHours)...now)
        let longAgo = now.addingTimeInterval(-3 * 86_400)
        #expect(UnmeasuredSpan.axis(length: fiveHours, resetsAt: longAgo, now: now) == now.addingTimeInterval(-fiveHours)...now)
        let ahead = now.addingTimeInterval(3600)
        #expect(UnmeasuredSpan.axis(length: fiveHours, resetsAt: ahead, now: now) == ChartAxis.window(length: fiveHours, resetsAt: ahead, now: now))
    }

    @Test("VoiceOver hears that the span after an old reading is not measured, and that the 5-hour window has reset")
    func readoutSaysTheSpanIsNotMeasured() throws {
        let codex = try #require(snapshot().codex)
        let fiveHour = try #require(codex.pools.first), weekly = try #require(codex.pools.last)
        let week = chart(weekly)
        let weekPoints = weekly.history
        #expect(week.unmeasured?.lastReading == measured && week.unmeasured?.resetPassed == nil)
        #expect(week.summary(weekPoints) == "7-day usage history: from 100 to 100 percent over 2 readings; not measured since Fri 17:35",
                "\(week.summary(weekPoints))")
        let five = chart(fiveHour)
        #expect(five.unmeasured?.resetPassed == Date(timeIntervalSince1970: 1_792_189_411))
        // The 5-hour reset was three days ago: the axis is the last five hours, with no reading in it.
        #expect(five.summary([]) == "5-hour usage history: no readings in this window; not measured since Fri 17:35; its window reset at Fri 22:23, after the last reading",
                "\(five.summary([]))")
    }

    @Test("A fresh reading reads exactly as before: no unmeasured span")
    func freshReadingIsUnchanged() throws {
        let claude = try #require(snapshot().provider?.pools.first)
        let c = chart(claude)
        #expect(c.unmeasured == nil)
        #expect(!c.summary(claude.history).contains("not measured"))
    }

    // MARK: - The inspector

    @Test("Measured at carries the reading's age; the Window row appears only once the reading's window has reset")
    func inspectorSaysHowOldAndWhetherReset() throws {
        let snap = snapshot()
        let codex = try #require(snap.codex)
        let fiveHour = fixture.inspector(try #require(codex.pools.first)).details
        #expect(fiveHour.contains("Measured at: 16 Oct 2026 at 17:35:38 · 2 days ago"), "\(fiveHour)")
        #expect(fiveHour.contains("Window: Reset passed 16 Oct 2026 at 22:23: this number is from the last window"), "\(fiveHour)")
        let weekly = fixture.inspector(try #require(codex.pools.last)).details
        #expect(weekly.contains("· 2 days ago") && !weekly.contains("Window:"), "\(weekly)")
        // Claude Code's live reading: the age only, no Window row.
        let claude = fixture.inspector(try #require(snap.provider?.pools.first)).details
        #expect(claude.contains("· just now") && !claude.contains("Window:"), "\(claude)")
    }

    @Test func agesInWholeUnits() {
        #expect(Copy.Inspector.ago(-5) == "just now" && Copy.Inspector.ago(59) == "just now")
        #expect(Copy.Inspector.ago(60) == "1 minute ago" && Copy.Inspector.ago(3599) == "59 minutes ago")
        #expect(Copy.Inspector.ago(3600) == "1 hour ago" && Copy.Inspector.ago(86_399) == "23 hours ago")
        #expect(Copy.Inspector.ago(86_400) == "1 day ago" && Copy.Inspector.ago(3 * 86_400 + 5) == "3 days ago")
    }
}
