import Domain
import Foundation
import Testing
import UsageEngine
@testable import CodexAdapter
@testable import PulseApp

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
