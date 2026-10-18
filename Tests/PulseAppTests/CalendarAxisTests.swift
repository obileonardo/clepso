import ClaudeCodeAdapter
import DesignSystem
import Foundation
import Testing
@testable import PulseApp

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
            let gap = max(theme.stroke(.hairline) * 2, cell * CalendarGridView.gapRatio)
            let drawn = CalendarGridView.labelColumn(theme) + gap + 53 * (cell + gap)
            #expect(drawn <= width + 0.001, "\(width): drawn \(drawn)")
        }
    }
}
