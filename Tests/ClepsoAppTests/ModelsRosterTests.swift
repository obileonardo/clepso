@testable import ClaudeCodeAdapter
import Foundation
import Testing
@testable import ClepsoApp

/// The Models page as the founder chose it (19 Oct 2026, proposal A "Roster + Dossier"): ranking, selection, the level
/// track, the states, and that every fact the old page showed (F1–F21 in docs/design-concepts/models) still has a source.
/// Synthetic numbers shaped like the founder's recording; no real values.
struct ModelsRosterTests {
    /// Six models as in the recording (all-time breakdown), daily tokens in the last week, and a seventh model that
    /// appears only in the daily counts (no tokens-by-kind record).
    static let file = """
    {"version": 5, "lastComputedDate": "2026-10-16",
     "dailyActivity": [
       {"date": "2026-09-01", "messageCount": 40, "sessionCount": 2, "toolCallCount": 90},
       {"date": "2026-10-14", "messageCount": 300, "sessionCount": 3, "toolCallCount": 700},
       {"date": "2026-10-16", "messageCount": 80, "sessionCount": 2, "toolCallCount": 150}],
     "dailyModelTokens": [
       {"date": "2026-09-01", "tokensByModel": {"claude-fable-5": 700}},
       {"date": "2026-10-14", "tokensByModel": {"claude-opus-5-5": 9000, "claude-sonnet-5-5": 1000, "claude-mystery-1": 50}},
       {"date": "2026-10-16", "tokensByModel": {"claude-opus-5-5": 4000, "claude-opus-5": 300}}],
     "modelUsage": {
       "claude-opus-5-5": {"inputTokens": 71700, "outputTokens": 18200000, "cacheReadInputTokens": 11900000000, "cacheCreationInputTokens": 189900000},
       "claude-opus-5": {"inputTokens": 20000, "outputTokens": 5300000, "cacheReadInputTokens": 2100000000, "cacheCreationInputTokens": 94680000},
       "claude-fable-5-1": {"inputTokens": 9000, "outputTokens": 2800000, "cacheReadInputTokens": 900000000, "cacheCreationInputTokens": 33391000},
       "claude-sonnet-5-5": {"inputTokens": 3000, "outputTokens": 309700, "cacheReadInputTokens": 900000000, "cacheCreationInputTokens": 29987300},
       "claude-haiku-4-5-20251001": {"inputTokens": 900, "outputTokens": 10100, "cacheReadInputTokens": 10000000, "cacheCreationInputTokens": 389000},
       "claude-fable-5": {"inputTokens": 100, "outputTokens": 5700, "cacheReadInputTokens": 700000, "cacheCreationInputTokens": 48000}},
     "firstSessionDate": "2026-09-01T08:00:00.000Z"}
    """

    static func stats(_ json: String = file) throws -> ClaudeCodeStats {
        guard case .success(let s) = StatsReader.parse(Data(json.utf8)) else { throw CancellationError() }
        return s
    }

    static func roster(_ range: StatsSummary.Range = .allTime, _ json: String = file) throws -> (ModelsRoster, StatsSummary) {
        let summary = StatsSummary.make(try stats(json), range: range, today: "2026-10-17")
        return (ModelsRoster(summary), summary)
    }

    @Test("Ranked by output (the level), then tokens; each model keeps the colour of its place by tokens")
    func ranking() throws {
        let (roster, summary) = try Self.roster()
        #expect(roster.entries.map(\.id) == ["claude-opus-5-5", "claude-opus-5", "claude-fable-5-1", "claude-sonnet-5-5",
                                             "claude-haiku-4-5-20251001", "claude-fable-5"])
        #expect(roster.entries.map(\.rank) == [1, 2, 3, 4, 5, 6])
        #expect(roster.entries.map { $0.level?.level } == [14, 13, 12, 9, 5, 4])
        // Sonnet has fewer tokens than Fable 5.1 by output but its colour follows its place by tokens.
        for entry in roster.entries { #expect(summary.models[entry.style].model == entry.id) }
        // A tie on output falls to tokens, then to the id, so the order never flickers.
        let tie = try Self.roster(.allTime, """
        {"version": 5, "modelUsage": {
          "claude-b": {"inputTokens": 0, "outputTokens": 10, "cacheReadInputTokens": 5, "cacheCreationInputTokens": 0},
          "claude-a": {"inputTokens": 0, "outputTokens": 10, "cacheReadInputTokens": 5, "cacheCreationInputTokens": 0},
          "claude-c": {"inputTokens": 0, "outputTokens": 10, "cacheReadInputTokens": 50, "cacheCreationInputTokens": 0}}}
        """).0
        #expect(tie.entries.map(\.id) == ["claude-c", "claude-a", "claude-b"])
    }

    @Test("Every fact the old page showed (F4–F21) has a source on the new one")
    func factCoverage() throws {
        let (roster, summary) = try Self.roster()
        let opus = try #require(roster.entries.first)
        #expect(roster.total == summary.totalTokens && roster.total > 0)                                    // F4 total
        #expect(opus.name == "Opus 5.5" && opus.share.tokens > 0 && opus.share.share > 0.7)                  // F5 name, tokens, share
        #expect(ModelsRoster.percent(opus.share.share) == String(format: "%.1f%%", opus.share.share * 100)) // F5 one decimal
        #expect(opus.rank == 1)                                                                              // F6 rank
        #expect(opus.specialty != nil)                                                                       // F7 specialty
        let level = try #require(opus.level)                                                                 // F8 LV
        #expect(level.level == 14 && level.floor == 10_000_000 && level.next == 20_000_000)                  // F9 progress
        #expect(level.output == 18_200_000 && level.next - level.output == 1_800_000)                        // F9 to go
        let kinds = try #require(opus.kinds)                                                                 // F10 four kinds
        #expect(kinds.map(\.kind) == [.output, .input, .cacheRead, .cacheWrite])
        #expect(kinds.map(\.tokens) == [18_200_000, 71_700, 11_900_000_000, 189_900_000])
        #expect(kinds.filter(\.countsForLevel).map(\.kind) == [.output])                                     // F15 counts for level
        #expect(abs(kinds.map(\.fraction).reduce(0, +) - 1) < 1e-9)
        #expect(opus.activeDays == 2)                                                                        // F11 active days
        #expect(roster.track.first { $0.level == 14 }?.models.map(\.id) == ["claude-opus-5-5"])               // F12 ladder + models
        #expect(roster.track.first { $0.level == 15 }?.target == 20_000_000)                                 // F12 targets
        for text in [Copy.ModelsPage.trackIntro(.allTime), Copy.Stats.ladderNote, Copy.Stats.arenaNote, Copy.Stats.arenaRangeNote,
                     Copy.Stats.rankRule, Copy.Stats.specialtyRule, Copy.ModelsPage.kindsUnknown] {               // F13, F14, F16, F17, F21
            #expect(!text.isEmpty)
        }
        #expect(Copy.Stats.kindDefinitions.count == 4 && ModelsRoster.kindOrder.allSatisfy { !$0.definition.isEmpty })   // F15
        // F21: a model with no tokens-by-kind record (only in the daily counts, so only in a shorter range).
        let (week, _) = try Self.roster(.last7)
        let mystery = try #require(week.entries.first { $0.id == "claude-mystery-1" })
        #expect(mystery.level == nil && mystery.kinds == nil && mystery.specialty == nil && mystery.activeDays == 1)
        #expect(week.unplaced.map(\.id) == ["claude-mystery-1"])
        #expect(!week.track.contains { $0.models.contains { $0.id == "claude-mystery-1" } })
        #expect(week.entries.last?.id == "claude-mystery-1", "an unknown level ranks last")
    }

    @Test("Selection: #1 by default, kept while the model is in the range, else #1; arrows hold at the ends")
    func selection() throws {
        let (roster, _) = try Self.roster()
        #expect(roster.resolve(nil)?.id == "claude-opus-5-5")
        #expect(roster.resolve("claude-sonnet-5-5")?.id == "claude-sonnet-5-5")
        #expect(roster.resolve("gone")?.id == "claude-opus-5-5")
        #expect(roster.step(nil, by: 1) == "claude-opus-5")
        #expect(roster.step("claude-opus-5-5", by: -1) == "claude-opus-5-5")
        #expect(roster.step("claude-fable-5", by: 1) == "claude-fable-5")
        #expect(roster.step("claude-opus-5", by: 1) == "claude-fable-5-1")
        #expect(roster.firstID == "claude-opus-5-5" && roster.lastID == "claude-fable-5")
        // Typing a letter: the next name starting with it, wrapping round.
        #expect(roster.typeSelect("o", after: "claude-opus-5-5") == "claude-opus-5")
        #expect(roster.typeSelect("O", after: "claude-opus-5") == "claude-opus-5-5")
        #expect(roster.typeSelect("f", after: nil) == "claude-fable-5-1")
        #expect(roster.typeSelect("z", after: nil) == nil)
        // A range change: Fable 5 had no tokens in the last week, so the choice falls back to #1; Sonnet 5.5 stays.
        let (week, _) = try Self.roster(.last7)
        #expect(week.resolve("claude-fable-5")?.id == week.entries.first?.id)
        #expect(week.resolve("claude-sonnet-5-5")?.id == "claude-sonnet-5-5")
        // Levels stay all time in every range.
        #expect(week.entries.first { $0.id == "claude-sonnet-5-5" }?.level?.level == 9)
    }

    @Test("The track: levels 1–20 grouped by power of ten, each model on its level, NEXT after the chosen one's")
    func track() throws {
        let (roster, _) = try Self.roster()
        let track = roster.track
        #expect(track.count == 20 && roster.trackLength == 20)
        #expect(track.map(\.level) == Array(1...20))
        #expect(track[0].target == 0 && track[1].target == 1_000 && track[19].target == 1_000_000_000)
        #expect(track.map(\.decade) == [0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6, 7])
        #expect(track.flatMap(\.models).count == roster.entries.count)
        for entry in roster.entries { #expect(track[entry.level!.level - 1].models.contains(entry)) }
        #expect(roster.nextLevel(for: nil) == 15)
        #expect(roster.nextLevel(for: "claude-sonnet-5-5") == 10)
        // Two models on one level stand together, in rank order.
        let pair = try Self.roster(.allTime, """
        {"version": 5, "modelUsage": {
          "claude-opus-5-5": {"inputTokens": 0, "outputTokens": 1500, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
          "claude-haiku-5": {"inputTokens": 0, "outputTokens": 1200, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0}}}
        """).0
        #expect(pair.track[1].models.map(\.id) == ["claude-opus-5-5", "claude-haiku-5"])
        // A model past LV 20 extends the track to one level beyond it.
        let big = try Self.roster(.allTime, """
        {"version": 5, "modelUsage": {
          "claude-opus-5-5": {"inputTokens": 0, "outputTokens": 6000000000, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0}}}
        """).0
        #expect(big.entries.first?.level?.level == 22 && big.trackLength == 23 && big.track.last?.level == 23)
        #expect(big.nextLevel(for: nil) == 23)
    }

    @Test("Track cells share the width, a wider gap between powers of ten; too narrow and the track scrolls")
    func trackMetrics() {
        let wide = LevelTrack.metrics(width: 1260, levels: 20, gap: 4, decadeGap: 12, minimum: 32)
        #expect(!wide.scrolls && wide.cell * 20 + 12 * 4 + 7 * 12 <= 1260 && wide.cell > 55)
        let narrow = LevelTrack.metrics(width: 868, levels: 20, gap: 4, decadeGap: 12, minimum: 32)
        #expect(!narrow.scrolls && narrow.cell >= 32, "the minimum window still fits 20 levels")
        let squeezed = LevelTrack.metrics(width: 500, levels: 20, gap: 4, decadeGap: 12, minimum: 32)
        #expect(squeezed.scrolls && squeezed.cell == 32)
        // The roster shows every row up to eight models (no half-cut row); past that it scrolls within the pane.
        #expect(RosterList.listFrame(content: 520, pane: 400, rows: 6, floor: 160) == 520)
        #expect(RosterList.listFrame(content: 900, pane: 400, rows: 12, floor: 160) == 400)
        #expect(RosterList.listFrame(content: 300, pane: 400, rows: 12, floor: 160) == 300)
        #expect(RosterList.listFrame(content: 900, pane: 0, rows: 12, floor: 160) == 160)
    }

    @Test("No models: nothing to choose; one model: no roster, the dossier alone at 100% share")
    func states() throws {
        let (empty, summary) = try Self.roster(.allTime, #"{"version": 5}"#)
        #expect(summary.models.isEmpty && empty.isEmpty && empty.resolve(nil) == nil && empty.step(nil, by: 1) == nil)
        #expect(empty.unplaced.isEmpty && empty.firstID == nil)
        let (one, _) = try Self.roster(.allTime, """
        {"version": 5, "modelUsage": {
          "claude-opus-5-5": {"inputTokens": 1, "outputTokens": 2500, "cacheReadInputTokens": 9000, "cacheCreationInputTokens": 0}}}
        """)
        #expect(!one.showsRoster && one.resolve("anything")?.id == "claude-opus-5-5")
        #expect(ModelsRoster.percent(one.entries[0].share.share) == "100.0%")
        // A record whose kinds are all zero has no tiles (nothing to divide by), but keeps its level.
        let (zero, _) = try Self.roster(.last7, """
        {"version": 5, "dailyModelTokens": [{"date": "2026-10-16", "tokensByModel": {"claude-opus-5-5": 10}}],
         "modelUsage": {"claude-opus-5-5": {"inputTokens": 0, "outputTokens": 0, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0}}}
        """)
        #expect(zero.entries.first?.kinds == nil && zero.entries.first?.level?.level == 1)
    }

    @Test("Shares read to one decimal everywhere; a sliver reads <0.1%, never 0.0%")
    func percents() {
        #expect(ModelsRoster.percent(0.7512) == "75.1%")
        #expect(ModelsRoster.percent(0.001) == "0.1%")
        #expect(ModelsRoster.percent(0.0004) == "<0.1%")
        #expect(ModelsRoster.percent(0) == "0.0%")
        #expect(ModelsRoster.spokenPercent(0.0004) == "less than 0.1 percent")
        #expect(ModelsRoster.spoken(12_200_000_000) == "12.2 billion" && ModelsRoster.spoken(940) == "940")
    }

    @Test("Roster zones split where output crosses 1K, 1M, 1B (the promotion-zone line); unknown levels come last")
    func zones() throws {
        #expect([1, 2, 10, 11, 19, 20, 28, 29].map(ModelsRoster.zone(of:)) == [0, 1, 1, 2, 2, 3, 3, 4])
        #expect([0, 1, 2, 3].map(ModelsRoster.zoneFloor) == [1, 2, 11, 20])
        #expect(ModelsRoster.target(of: 11) == 1_000_000 && ModelsRoster.target(of: 20) == 1_000_000_000)
        let (roster, _) = try Self.roster()
        #expect(roster.zones.map(\.floorLevel) == [11, 2])
        #expect(roster.zones.map { $0.entries.map(\.rank) } == [[1, 2, 3], [4, 5, 6]])
        #expect(roster.zones.flatMap(\.entries) == roster.entries, "zones keep every row in rank order")
        let (week, _) = try Self.roster(.last7)
        #expect(week.zones.last?.floorLevel == nil && week.zones.last?.entries.map(\.id) == ["claude-mystery-1"])
        #expect(Copy.ModelsPage.zoneLabel(floorLevel: 11, target: "1M") == "LV 11+ · 1M+ OUTPUT")
        #expect(Copy.ModelsPage.zoneLabel(floorLevel: 1, target: "0") == "LV 1 · UNDER 1K OUTPUT")
    }

    @Test("Activity: one cell per day (per week past 120 days), lit by quarters of the model's busiest cell")
    func activity() throws {
        let (_, week) = try Self.roster(.last7)
        let cells = ModelsRoster.activity("claude-opus-5-5", summary: week, from: "2026-10-11")
        #expect(cells == [0, 0, 0, 4, 0, 2, 0])                 // 9000 on the 14th, 4000 on the 16th
        #expect(ModelsRoster.activity("claude-fable-5", summary: week, from: "2026-10-11") == Array(repeating: 0, count: 7))
        let (_, all) = try Self.roster(.allTime)
        let long = ModelsRoster.activity("claude-opus-5-5", summary: all, from: "2026-04-01")
        #expect(long.count == 29 && long.allSatisfy { (0...4).contains($0) })   // 200 days in weeks
    }
}
