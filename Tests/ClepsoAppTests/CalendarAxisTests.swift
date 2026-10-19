import ClaudeCodeAdapter
import DesignSystem
import Foundation
import Testing
@testable import ClepsoApp

/// Increment 1.8d/e: the maths the founder's review found wrong (axes, ranges, calendar span).
struct CalendarAxisTests {
    func stats() throws -> ClaudeCodeStats {
        guard case .success(let s) = StatsReader.parse(Data(StatsTests.file.utf8)) else { throw CancellationError() }
        return s
    }

    @Test("A year grid runs 1 January to 31 December, Sunday on top; days outside the history are 'no data'")
    func yearGrid() throws {
        let s = try stats()
        let summary = StatsSummary.make(s, range: .allTime, today: "2026-10-17")
        let grid = StatsCalendar.year(2026, stats: s, levels: summary.heatmap, today: "2026-10-17", firstDay: "2026-10-10")
        #expect(grid.weeks.count == 53)
        // 1 Jan 2026 is a Thursday: Sunday–Wednesday of the first column are padding.
        #expect(grid.weeks[0].prefix(4).allSatisfy { $0 == nil } && grid.weeks[0][4]?.date == "2026-01-01")
        let cells = grid.weeks.flatMap { $0 }.compactMap { $0 }
        #expect(cells.count == 365 && cells.first?.date == "2026-01-01" && cells.last?.date == "2026-12-31")
        #expect(cells.first { $0.date == "2026-03-01" }?.state == .noData, "before the first session")
        #expect(cells.first { $0.date == "2026-11-01" }?.state == .noData, "after today")
        #expect(cells.first { $0.date == "2026-10-12" }?.state == .level(0), "a quiet day inside the history is zero, not no-data")
        #expect(cells.first { $0.date == "2026-10-14" }?.state == .level(4))
        #expect(cells.first { $0.date == "2026-10-14" }?.messages == 300)
        #expect(grid.months.map(\.label) == ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])
        #expect(grid.months.first?.column == 0)
        #expect(StatsCalendar.years(firstDay: "2024-05-02", today: "2026-10-17") == [2024, 2025, 2026])
    }

    @Test("Thirty days are thirty cells ending today")
    func recentGrid() throws {
        let s = try stats()
        let grid = StatsCalendar.recent(30, stats: s, levels: [:], today: "2026-10-17", firstDay: "2026-10-10")
        let cells = grid.weeks.flatMap { $0 }.compactMap { $0 }
        #expect(cells.count == 30 && cells.first?.date == "2026-09-18" && cells.last?.date == "2026-10-17")
    }

    @Test("A limit's window is reset minus its length through the reset; ticks fall on whole hours or days")
    func axis() {
        let utc = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_792_240_200)                          // 17 Oct 2026 12:30 UTC
        let reset = now.addingTimeInterval(54 * 60)                                    // 13:24
        let window = ChartAxis.window(length: 5 * 3600, resetsAt: reset, now: now)
        #expect(window.lowerBound == reset.addingTimeInterval(-5 * 3600) && window.upperBound == reset)
        let ticks = ChartAxis.ticks(window, zone: utc)
        #expect(ticks.count == 5, "09:00 through 13:00")
        #expect(ticks.allSatisfy { Int($0.timeIntervalSince1970) % 3600 == 0 })
        let week = ChartAxis.window(length: 7 * 86_400, resetsAt: now.addingTimeInterval(4 * 86_400), now: now)
        #expect(ChartAxis.ticks(week, zone: utc).allSatisfy { Int($0.timeIntervalSince1970) % 86_400 == 0 })
        #expect(ChartAxis.window(length: 3600, resetsAt: nil, now: now) == now.addingTimeInterval(-3600)...now, "no reset: ending now")
    }

    @Test("A year fitted to a width is never drawn wider than it (it pushed Overview past the window's edge at 1100 pt)")
    @MainActor func yearFits() {
        let theme = Theme.phosphor
        for width in stride(from: CGFloat(560), through: 1100, by: 7) {
            let cell = CalendarGridView.cell(fitting: width, weeks: 53, theme: theme)
            let gap = CalendarGridView.gap(cell, theme)
            let drawn = CalendarGridView.labelColumn(theme) + gap + 53 * (cell + gap)
            #expect(drawn <= width + 0.001, "\(width): drawn \(drawn)")
            // Pixel art: squares and gaps are whole points (whole device pixels at 1× and 2×), squares a pixel tile.
            #expect(cell == cell.rounded() && gap == gap.rounded() && cell == PixelDensity.tile(fitting: cell, px: 2), "\(width)")
        }
        // The Dashboard's default width (a 750-point content side): GitHub's 10-point squares with 3-point gaps.
        #expect(CalendarGridView.cell(fitting: 750, weeks: 53, theme: theme) == 10)
        #expect(CalendarGridView.gap(10, theme) == 3)
    }

    @Test("Month view: the level's band is whole pixel rows under plain ground for the figures (no plate cut into the dither)")
    @MainActor func monthBand() {
        for theme in Theme.all {
            let px = theme.stroke(.hairline) * 2
            // Every square the month view can draw (`OverviewSection.monthCell`: two to three and a half spacious steps).
            for limit in stride(from: theme.spacing(.spacious) * 2, through: theme.spacing(.spacious) * 3.5, by: 1) {
                let cell = PixelDensity.tile(fitting: limit, px: px), band = CalendarGridView.monthBand(cell, theme)
                #expect(band.rows >= 1 && band.ground == band.ground.rounded() && band.ground.truncatingRemainder(dividingBy: px) == 0, "\(theme.name) \(cell)")
                #expect(band.ground + CGFloat(band.rows) * px == cell, "\(theme.name) \(cell): ground and band fill the square")
                #expect(band.ground > cell / 2, "\(theme.name) \(cell): the figures keep most of the square")
            }
        }
        // The pixel themes' usual square (70 pt, 35 pixels): 13 rows of pattern under 44 pt of ground.
        #expect(CalendarGridView.monthBand(70, .phosphor) == (rows: 13, ground: 44))
    }

    @Test("The year switcher goes back to 2025 (Claude Code's release) before the first session, and never past this year")
    @MainActor func yearBounds() throws {
        // Today comes from the injected clock, the way AppModel derives it: 19 Oct 2026, 09:00 in London.
        let today = AppModel.dayLabel(Date(timeIntervalSince1970: 1_792_396_800), zone: TimeZone(identifier: "Europe/London")!)
        #expect(today == "2026-10-19")
        // The founder's case: history starts in 2026, so 2025 is reachable (shown empty) and nothing earlier.
        let years = StatsCalendar.years(firstDay: "2026-09-22T09:00:00.000Z", today: today)
        #expect(years == [2025, 2026])
        #expect(StatsCalendar.shownYear(nil, of: years) == 2026, "today's year first")
        #expect(StatsCalendar.shownYear(2025, of: years) == 2025)
        #expect(StatsCalendar.shownYear(2024, of: years) == 2025, "held at the floor")
        #expect(StatsCalendar.shownYear(2027, of: years) == 2026, "never after today's year")
        #expect(StatsCalendar.years(firstDay: nil, today: today) == [2025, 2026], "no history yet")
        #expect(StatsCalendar.years(firstDay: "2025-03-01", today: "2025-12-31") == [2025])
        #expect(StatsCalendar.years(firstDay: "2026-01-05", today: "2028-02-01") == [2025, 2026, 2027, 2028])
        #expect(StatsCalendar.years(firstDay: "2024-05-02", today: today) == [2024, 2025, 2026], "a history older than the floor is kept")
        // The empty year before the history is all "no data", with no day to choose and no active days.
        let s = try stats()
        let grid = StatsCalendar.year(2025, stats: s, levels: [:], today: today, firstDay: "2026-09-22")
        let cells = grid.weeks.flatMap { $0 }.compactMap { $0 }
        #expect(cells.count == 365 && cells.allSatisfy { $0.state == .noData })
        #expect(grid.day(from: nil) == nil)
    }
}
