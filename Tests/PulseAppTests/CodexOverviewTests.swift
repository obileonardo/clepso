import Domain
import Foundation
import Testing
import UsageEngine
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
}
