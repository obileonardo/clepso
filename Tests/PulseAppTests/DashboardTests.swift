@testable import ClaudeCodeAdapter
import DesignSystem
import Foundation
import SwiftUI
import Testing
import UsageEngine
@testable import PulseApp

/// Increment 1.10: Home, the player card and Goals.
struct DashboardTests {
    @Test("Greeting by the hour in the user's zone, with or without a name")
    func greeting() {
        let london = TimeZone(identifier: "Europe/London")!
        func at(_ hour: Int) -> Date {
            var c = Calendar(identifier: .gregorian); c.timeZone = london
            return c.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: hour))!
        }
        #expect(Greeting.make(at(9), zone: london, name: "Elvis") == "Good morning, Elvis")
        #expect(Greeting.make(at(15), zone: london, name: "Elvis") == "Good afternoon, Elvis")
        #expect(Greeting.make(at(19), zone: london, name: " ") == "Good evening")
        #expect(Greeting.make(at(2), zone: london, name: nil) == "Working late")
        #expect(Greeting.defaultName(fullUserName: "Elvis Obi") == "Elvis")
    }

    @Test("Every level has a name; past the list they count on")
    func levelNames() {
        #expect(LevelName.of(1) == "Boot" && LevelName.of(14) == "Mainframe" && LevelName.of(20) == "Singularity")
        #expect(LevelName.of(21) == "Singularity II" && LevelName.of(22) == "Singularity III")
        #expect(Set((1...20).map(LevelName.of)).count == 20)
    }

    func stats() throws -> ClaudeCodeStats {
        guard case .success(let s) = StatsReader.parse(Data(StatsTests.file.utf8)) else { throw CancellationError() }
        return s
    }

    @Test("Player card: output level, name, milestones are the highest earned per kind; the running total adds every kind")
    func card() throws {
        let file = try stats()
        let summary = StatsSummary.make(file, range: .allTime, today: "2026-10-17")
        let card = PlayerCard.make(file: file, summary: summary, name: "Elvis", plan: "Max 5×")
        let output = file.models.map(\.output).reduce(0, +)
        #expect(card.output == output && card.level == ModelLevel(output: output) && card.levelName == LevelName.of(card.level.level))
        #expect(Set(card.milestones.map(\.id)).count == card.milestones.count, "one stamp per kind")
        let total = RunningTotal.make(file)
        #expect(total.tokens == file.models.map(\.total).reduce(0, +))
        #expect(total.lastDayDate == file.dailyTokens.map(\.date).max())
    }

    @Test("Goals: active days, today's 5-hour peak with its streak, the week's projected finish")
    func goals() {
        let zone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_792_159_200)              // 16 Oct 2026 14:00 UTC
        let day: Double = 86_400
        // Peaks: two days ago 70, yesterday 75, today 63 so far: three days in a row under 80.
        let history = [UsagePoint(at: now - 2 * day, usedPct: 70), UsagePoint(at: now - day, usedPct: 75),
                       UsagePoint(at: now - 3600, usedPct: 40), UsagePoint(at: now - 60, usedPct: 63)]
        var statuses = GoalEvaluator.evaluate(Goals(), last7: nil, fiveHourHistory: history, sevenDayPct: 40,
                                              sevenDayPace: .belowAtReset(projectedPct: 95), now: now, zone: zone)
        #expect(statuses.map(\.kind) == [.activeDays, .fiveHourPeak, .weeklyFinish])
        #expect(statuses[0].state == .noData)
        #expect(statuses[1].state == .onTrack && statuses[1].value == "63%" && statuses[1].streak == 3)
        #expect(statuses[2].state == .atRisk, "under the target now, over it at the projected reset")

        // A day over the target breaks the streak; a 7-day limit already past the target is over.
        let over = history + [UsagePoint(at: now - day + 60, usedPct: 91)]
        statuses = GoalEvaluator.evaluate(Goals(activeDaysPerWeek: nil), last7: nil, fiveHourHistory: over, sevenDayPct: 92,
                                          sevenDayPace: .notRising, now: now, zone: zone)
        #expect(statuses.map(\.kind) == [.fiveHourPeak, .weeklyFinish])
        #expect(statuses[0].streak == 1 && statuses[1].state == .missed)

        // No readings today: no data, not "met".
        statuses = GoalEvaluator.evaluate(Goals(activeDaysPerWeek: nil, weeklyFinishMax: nil), last7: nil,
                                          fiveHourHistory: [UsagePoint(at: now - day, usedPct: 10)], sevenDayPct: nil, sevenDayPace: nil, now: now, zone: zone)
        #expect(statuses.first?.state == .noData)
    }

    @Test("The card renders to a 2× image the size of the card, for copy, save and share")
    @MainActor
    func cardImage() throws {
        PixelFonts.ensureRegistered()
        let file = try stats()
        let summary = StatsSummary.make(file, range: .allTime, today: "2026-10-17")
        let card = PlayerCard.make(file: file, summary: summary, name: "Elvis", plan: nil)
        let renderer = ImageRenderer(content: PlayerCardView(card: card, topModelID: summary.favorite?.model)
            .environment(\.theme, .phosphor).environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int(PlayerCardView.width * 2) && image.height > 400)
    }
}
