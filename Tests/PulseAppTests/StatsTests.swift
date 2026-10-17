import ClaudeCodeAdapter
import Foundation
import Testing
@testable import PulseApp

/// Increment 1.7d/f: the stats file reader and the /stats-style summary. Synthetic data shaped like Claude Code's
/// `stats-cache.json` (format version 5); no real values.
struct StatsTests {
    static let file = """
    {"version": 5, "lastComputedDate": "2026-10-16", "dailyModelTokensVersion": 5,
     "dailyActivity": [
       {"date": "2026-10-10", "messageCount": 40, "sessionCount": 2, "toolCallCount": 90},
       {"date": "2026-10-11", "messageCount": 10, "sessionCount": 1, "toolCallCount": 20},
       {"date": "2026-10-12", "messageCount": 0, "sessionCount": 0, "toolCallCount": 0},
       {"date": "2026-10-14", "messageCount": 300, "sessionCount": 3, "toolCallCount": 700},
       {"date": "2026-10-15", "messageCount": 5, "sessionCount": 1, "toolCallCount": 4},
       {"date": "2026-10-16", "messageCount": 80, "sessionCount": 2, "toolCallCount": 150},
       {"date": "not-a-date", "messageCount": 1}],
     "dailyModelTokens": [
       {"date": "2026-10-14", "tokensByModel": {"claude-opus-5-5": 9000, "claude-sonnet-5-5": 1000}},
       {"date": "2026-10-16", "tokensByModel": {"claude-opus-5-5": 4000, "../evil": 7}}],
     "modelUsage": {
       "claude-opus-5-5": {"inputTokens": 100, "outputTokens": 900, "cacheReadInputTokens": 7000, "cacheCreationInputTokens": 2000,
                           "costUSD": 12.5, "contextWindow": 1000000, "maxOutputTokens": 0, "webSearchRequests": 0},
       "claude-haiku-4-5-20251001": {"inputTokens": 10, "outputTokens": 20, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0}},
     "totalSessions": 9, "totalMessages": 435,
     "longestSession": {"sessionId": "SECRET-SESSION-ID", "timestamp": "2026-10-14T09:00:00.000Z", "duration": 3600000, "messageCount": 77},
     "firstSessionDate": "2026-10-10T08:00:00.000Z",
     "hourCounts": {"9": 3, "14": 6, "25": 1},
     "aFutureField": {"anything": true}}
    """

    func stats() throws -> ClaudeCodeStats {
        guard case .success(let s) = StatsReader.parse(Data(Self.file.utf8)) else { throw CancellationError() }
        return s
    }

    @Test("The reader keeps allowlisted fields, drops bad dates, odd model ids and impossible hours, and never the session id")
    func reader() throws {
        let s = try stats()
        #expect(s.days.map(\.date) == ["2026-10-10", "2026-10-11", "2026-10-12", "2026-10-14", "2026-10-15", "2026-10-16"])
        #expect(s.dailyTokens.last?.byModel == ["claude-opus-5-5": 4000])
        #expect(s.models.map(\.model) == ["claude-opus-5-5", "claude-haiku-4-5-20251001"])
        #expect(s.models.first?.total == 10_000)
        #expect(s.hourCounts == [9: 3, 14: 6])
        #expect(s.rejected == 3, "bad date, odd model id, hour 25")
        #expect(s.longestSessionMs == 3_600_000 && s.longestSessionMessages == 77)
        #expect(!String(describing: s).contains("SECRET"), "the session id is never read")
        #expect(s.firstSessionDate == "2026-10-10" && s.computedThrough == "2026-10-16")
    }

    @Test("All time: totals from Claude Code's per-model figures, days since the first session, streaks and busiest day")
    func allTime() throws {
        let s = StatsSummary.make(try stats(), range: .allTime, today: "2026-10-17")
        #expect(s.dayCount == 8 && s.activeDays == 5)
        #expect(s.longestStreak == 3, "runs 10–11 (two days) and 14–16 (three days)")
        #expect(s.mostActiveDay == "2026-10-14")
        #expect(s.sessions == 9 && s.messages == 435)
        #expect(s.totalTokens == 10_030)
        #expect(s.favorite?.name == "Opus 5.5" && abs((s.favorite?.share ?? 0) - 10_000.0 / 10_030) < 1e-9)
        #expect(s.currentStreak == 3, "yesterday back: 16, 15, 14")
    }

    @Test("Seen today on Pulse's own evidence: today counts as active and extends the streak, tokens unchanged")
    func seenToday() throws {
        let without = StatsSummary.make(try stats(), range: .allTime, today: "2026-10-17")
        let with = StatsSummary.make(try stats(), range: .allTime, today: "2026-10-17", seenToday: true)
        #expect(with.activeDays == without.activeDays + 1)
        #expect(with.currentStreak == 4)
        #expect(with.totalTokens == without.totalTokens)
    }

    @Test("Last 7 days: per-day token counts, sessions in range only")
    func last7() throws {
        let s = StatsSummary.make(try stats(), range: .last7, today: "2026-10-17")
        #expect(s.dayCount == 7)
        #expect(s.sessions == 7, "11th–16th: 1 + 0 + 3 + 1 + 2 (the 10th is outside)")
        #expect(s.totalTokens == 14_000)
        #expect(s.models.map(\.name) == ["Opus 5.5", "Sonnet 5.5"])
        #expect(s.heatmap["2026-10-14"] == 4 && s.heatmap["2026-10-12"] == 0)
    }

    @Test("Model names: Claude ids become readable; anything else is shown as given")
    func names() {
        #expect(StatsReader.displayName("claude-opus-5-5") == "Opus 5.5")
        #expect(StatsReader.displayName("claude-haiku-4-5-20251001") == "Haiku 4.5")
        #expect(StatsReader.displayName("claude-fable-5") == "Fable 5")
        #expect(StatsReader.displayName("gpt-x") == "gpt-x")
    }

    @Test("A missing file and a non-object file are reported, not crashed on")
    func problems() {
        #expect(StatsReader.read(home: URL(fileURLWithPath: "/nonexistent-\(UUID())")) == .failure(.missing))
        #expect(StatsReader.parse(Data("[1,2]".utf8)) == .failure(.notAnObject))
    }
}

@MainActor
struct StatsModelTests {
    @Test("The stats file is not read until the user turns it on; turning it off forgets it")
    func optIn() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try Data(StatsTests.file.utf8).write(to: box.home.appendingPathComponent(".claude/stats-cache.json"))
        let model = box.model(clock: TestClock(Date(timeIntervalSince1970: 1_792_238_400)))     // 17 Oct 2026, 12:00 UTC
        await model.start(); defer { model.stop() }
        model.loadStats()
        #expect(model.stats == nil && model.statsSummary(.allTime) == nil, "off by default")

        await model.setStatsEnabled(true)
        let summary = try #require(model.statsSummary(.allTime))
        #expect(summary.sessions == 9 && summary.today == "2026-10-17")
        #expect(model.diagnostics.entries.contains { $0.code == "stats.reading" })

        await model.setStatsEnabled(false)
        #expect(model.stats == nil)
    }
}
