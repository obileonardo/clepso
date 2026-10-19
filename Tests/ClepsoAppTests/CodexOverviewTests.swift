import Domain
import Foundation
import Testing
@testable import UsageEngine
@testable import CodexAdapter
@testable import ClepsoApp

/// Increment 3.4: Codex's pools form their own section and never enter Claude Code's.
struct CodexOverviewTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    func pool(_ key: String, used: Decimal) -> PoolState {
        var s = PoolState(poolKey: key)
        s.usedPct = used
        s.limit = .available
        s.lastProviderMeasured = now
        s.lastSeen = now
        return s
    }

    func make(_ input: OverviewInput) -> OverviewSnapshot {
        OverviewProjection.make(input, now: now, staleAfter: Freshness.localTelemetryTTL, zone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_GB"))
    }

    @Test func codexIsItsOwnSectionInWindowOrder() throws {
        var input = OverviewInput()
        input.pools = [pool("claude-code.rate_limits.five_hour", used: 40)]
        input.codexPools = [pool("codex.rate_limits.seven_day", used: 94), pool("codex.rate_limits.five_hour", used: 35)]
        input.codexEnabled = true
        input.codexPlan = "plus"
        input.codexModel = "gpt-5-codex"
        let snap = make(input)
        let codex = try #require(snap.codex)
        #expect(codex.name == "Codex" && codex.plan == "plus" && codex.model == "gpt-5-codex")
        #expect(codex.pools.map(\.poolKey) == ["codex.rate_limits.five_hour", "codex.rate_limits.seven_day"])
        #expect(snap.provider?.pools.map(\.poolKey) == ["claude-code.rate_limits.five_hour"])
        #expect(OverviewProjection.scope(of: "codex.rate_limits.five_hour") == "5-hour")
        #expect(OverviewProjection.paceLookback("codex.rate_limits.five_hour") == 90 * 60)
    }

    @Test func offOrDemoOrNoReadingMeansNoSection() {
        var input = OverviewInput()
        input.codexPools = [pool("codex.rate_limits.five_hour", used: 35)]
        #expect(make(input).codex == nil)                      // switch off
        input.codexEnabled = true
        input.isDemo = true
        #expect(make(input).codex == nil)                      // demo shows demo data only
        input.isDemo = false
        input.codexPools = []
        #expect(make(input).codex == nil)                      // on, but Codex has written nothing yet
    }

    @Test func claudeWindowsStillReadTheSame() {
        #expect(OverviewProjection.window(of: "claude-code.rate_limits.seven_day") == "seven_day")
        #expect(OverviewProjection.window(of: "something-else") == "something-else")
    }

    @Test func codexCountsTowardTheMenuBar() {
        var input = OverviewInput()
        input.pools = [pool("claude-code.rate_limits.five_hour", used: 40)]
        var weekly = pool("codex.rate_limits.seven_day", used: 100)
        weekly.limit = .exhausted
        input.codexPools = [pool("codex.rate_limits.five_hour", used: 62), weekly]
        input.codexEnabled = true
        input.lastEventAt = now
        let snap = make(input)
        #expect(snap.icon == .exhausted)
        #expect(snap.aggregateLine.hasPrefix("Codex limit reached"), "\(snap.aggregateLine)")
        // Without Codex the same Claude Code reading is fine.
        input.codexEnabled = false
        #expect(make(input).icon == .ok)
    }

    @Test func codexAloneDrivesTheIconWhenClaudeCodeIsNotConnected() {
        var input = OverviewInput()
        input.codexPools = [pool("codex.rate_limits.five_hour", used: 62)]
        input.codexEnabled = true
        let snap = make(input)
        #expect(snap.empty == .notConnected)              // the panel still offers to connect Claude Code
        #expect(snap.icon == .ok && snap.iconText == "62%")
    }
}

/// Founder report, 19 Oct 2026: "Where this number comes from" on a Codex limit named Claude Code's status line, its
/// adapter and its version. Each agent's numbers now carry their own origin.
@MainActor
struct CodexProvenanceTests {
    let now = Date(timeIntervalSince1970: 1_792_400_000)                     // 2026-10-19 UTC

    func pool(_ key: String, used: Decimal, limit: LimitState, measured: Date, resetsAt: Date?) -> PoolState {
        var s = PoolState(poolKey: key)
        s.usedPct = used
        s.limit = limit
        s.lastProviderMeasured = measured
        s.lastSeen = measured
        s.window = WindowState(id: UUID(), openedAt: measured.addingTimeInterval(-3600), resetsAt: resetsAt, closedAt: nil, version: 1)
        return s
    }

    func inspector(_ row: PoolRow) -> InspectorView {
        InspectorView(row: row, isDemo: false, now: now, zone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_GB")) {}
    }

    /// The founder's Codex on 16–19 Oct: 35% of the 5-hour window, measured 16 Oct 17:35:38 UTC with its reset at 22:23
    /// that night, and the weekly limit used up until 22 Oct 06:50 UTC. No reading since: Codex refused every turn.
    func founderInput() -> OverviewInput {
        let measured = Date(timeIntervalSince1970: 1_792_172_138)
        var input = OverviewInput()
        input.pools = [pool("claude-code.rate_limits.five_hour", used: 40, limit: .available, measured: now, resetsAt: now.addingTimeInterval(3600))]
        input.sourceVersion = "2.1.302"
        input.lastEventAt = now
        input.installed = true
        input.codexEnabled = true
        input.codexVersion = "0.163.0"
        input.codexPools = [
            pool("codex.rate_limits.five_hour", used: 35, limit: .resetExpected, measured: measured, resetsAt: Date(timeIntervalSince1970: 1_792_189_411)),
            pool("codex.rate_limits.seven_day", used: 100, limit: .exhausted, measured: measured, resetsAt: Date(timeIntervalSince1970: 1_792_651_827))]
        return input
    }

    func make(_ input: OverviewInput) -> OverviewSnapshot {
        OverviewProjection.make(input, now: now, staleAfter: Freshness.localTelemetryTTL, zone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_GB"))
    }

    @Test func codexInspectorNamesCodexNeverClaudeCode() throws {
        let snap = make(founderInput())
        let codex = try #require(snap.codex)
        for row in codex.pools {
            #expect(row.origin == .codex(version: "0.163.0"))
            let details = inspector(row).details
            #expect(!details.contains("Claude"), "\(details)")
            #expect(details.contains("Source: Codex session files") && details.contains("Adapter: Codex session reader, token_count events"))
            #expect(details.contains("Codex version: 0.163.0"))
        }
        #expect(codex.pools.map(\.providerField) == ["token_count › rate_limits.primary.used_percent",
                                                     "token_count › rate_limits.secondary.used_percent"])
        let claude = try #require(snap.provider?.pools.first)
        let details = inspector(claude).details
        #expect(details.contains("Source: Claude Code status line") && details.contains("Claude Code version: 2.1.302"))
        #expect(!details.contains("Codex"))
    }

    @Test("Codex's version unknown: a dash, never Claude Code's version in its place")
    func unknownCodexVersionIsADash() throws {
        var input = founderInput()
        input.codexVersion = nil
        let row = try #require(make(input).codex?.pools.first)
        #expect(inspector(row).details.contains("Codex version: —"))
        #expect(!inspector(row).details.contains("2.1.302"))
    }

    /// UX_SPEC 1.2 and DATA_MODEL G9/G13: a passed reset with no fresh reading reads "Reset expected · awaiting next
    /// update", the old figure is stale (hatched, "last seen"), and the menu bar leads with the used-up weekly limit.
    @Test func passedResetWithoutAFreshReadingIsShownAsSuch() throws {
        let snap = make(founderInput())
        let codex = try #require(snap.codex)
        let fiveHour = try #require(codex.pools.first), weekly = try #require(codex.pools.last)
        #expect(fiveHour.model.card == .resetExpected)
        #expect(fiveHour.model.valueState(now: now, staleAfter: Freshness.localTelemetryTTL) == .stale)
        #expect(weekly.model.card == .exhausted)
        #expect(weekly.model.valueState(now: now, staleAfter: Freshness.localTelemetryTTL) == .stale)
        #expect(snap.icon == .exhausted)
        #expect(snap.aggregateLine.hasPrefix("Codex limit reached · reset expected"), "\(snap.aggregateLine)")
    }
}

/// Increment 3.4b: Codex's figures for a Stats range.
struct CodexStatsTests {
    func day(_ d: String, _ model: String?, input: Int64, output: Int64) -> CodexUsage.Day {
        CodexUsage.Day(day: d, model: model, tokens: .init(input: input, cachedInput: 0, cacheWrite: 0, output: output, reasoningOutput: 0))
    }

    @Test func rangeTotalsAndTopModel() throws {
        let days = [day("2026-09-01", "gpt-5", input: 1000, output: 100),
                    day("2026-10-15", "gpt-5-codex", input: 300, output: 30), day("2026-10-15", nil, input: 50, output: 5),
                    day("2026-10-17", "gpt-5-codex", input: 600, output: 60)]
        let week = try #require(CodexStats.make(days, range: .last7, today: "2026-10-18"))
        #expect(week.from == "2026-10-12" && week.total == 1045 && week.output == 95)
        #expect(week.activeDays == 2 && week.dayCount == 7)
        #expect(week.topModel == "gpt-5-codex" && week.topShare == 95)
        #expect(week.series.names == ["gpt-5-codex", Copy.Codex.unknownModel])
        let all = try #require(CodexStats.make(days, range: .allTime, today: "2026-10-18"))
        #expect(all.from == "2026-09-01" && all.total == 2145 && all.topModel == "gpt-5")
        #expect(CodexStats.make([], range: .last30, today: "2026-10-18") == nil)
    }
}
