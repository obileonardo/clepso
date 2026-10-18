@testable import ClaudeCodeAdapter
import DesignSystem
import Foundation
import SwiftUI
import Testing
@testable import PulseApp

/// Item 9: what the keyboard reaches without a pointer: the charts' readout cursor and the calendar's chosen day.
struct KeyboardTests {
    @Test("A chart's cursor starts at the latest bar, steps one bar per arrow and holds at the ends")
    func chartCursor() {
        #expect(ChartCursor.step(nil, count: 14, by: 0) == 13)          // focus arrives: the latest bar
        #expect(ChartCursor.step(nil, count: 14, by: -1) == 13)
        #expect(ChartCursor.step(13, count: 14, by: -1) == 12)
        #expect(ChartCursor.step(0, count: 14, by: -1) == 0)            // held at the first bar
        #expect(ChartCursor.step(13, count: 14, by: 1) == 13)           // and at the last
        #expect(ChartCursor.step(5, count: 14, by: 0) == 5)             // a bar the pointer chose is kept on focus
        #expect(ChartCursor.step(30, count: 14, by: 1) == 13)           // a stale index (range changed) comes back in range
        #expect(ChartCursor.step(nil, count: 0, by: 1) == nil)          // an empty chart has no cursor
        // Every step from every bar stays a valid index, so the readout can always be drawn.
        for count in 1...30 { for start in [nil] + (0..<count).map(Optional.some) { for delta in [-1, 0, 1] {
            let next = ChartCursor.step(start, count: count, by: delta)
            #expect(next.map { (0..<count).contains($0) } == true)
        } } }
    }

    /// Two weeks, Sunday on top: padding before Tuesday the 1st, the 3rd quiet but choosable, the 6th–7th and 11th
    /// without data (before the first session / after today), padding after the 12th.
    static let grid: StatsCalendar.Grid = {
        func cell(_ day: Int, _ state: StatsCalendar.Cell.State) -> StatsCalendar.Cell {
            StatsCalendar.Cell(date: String(format: "2026-09-%02d", day), state: state, messages: day, sessions: 1)
        }
        let states: [Int: StatsCalendar.Cell.State] = [1: .level(2), 2: .level(1), 3: .level(0), 4: .level(4), 5: .level(1),
                                                       6: .noData, 7: .noData, 8: .level(3), 9: .level(1), 10: .level(2),
                                                       11: .noData, 12: .level(1)]
        let days: [StatsCalendar.Cell?] = [nil, nil] + (1...12).map { cell($0, states[$0]!) }
        return StatsCalendar.Grid(weeks: [Array(days[0..<7]), Array(days[7..<14])], months: [(0, "Sep")])
    }()

    @Test("The calendar's keyboard cursor moves by day and by week over days with data only, and stays at the edges")
    func calendarCursor() {
        let g = Self.grid
        #expect(g.day(from: nil) == "2026-09-12")                       // the first arrow: the latest day with data
        #expect(g.day(from: "2026-01-01", days: 1) == "2026-09-12")     // a day from another year: start again
        #expect(g.day(from: "2026-09-04", days: 1) == "2026-09-05")
        #expect(g.day(from: "2026-09-05", days: 1) == "2026-09-08")     // passes over the two days without data
        #expect(g.day(from: "2026-09-03", days: -1) == "2026-09-02")    // a quiet day (level 0) can be chosen
        #expect(g.day(from: "2026-09-01", days: -1) == "2026-09-01")    // the start: stays
        #expect(g.day(from: "2026-09-12", days: 1) == "2026-09-12")     // the end: stays
        #expect(g.day(from: "2026-09-01", weeks: 1) == "2026-09-08")    // same weekday, next week
        #expect(g.day(from: "2026-09-04", weeks: 1) == "2026-09-04")    // the 11th has no data and the grid ends: stays
        #expect(g.day(from: "2026-09-08", weeks: -1) == "2026-09-01")
        #expect(g.day(from: "2026-09-02", weeks: -1) == "2026-09-02")   // padding above: stays
        #expect(g.day(from: "2026-09-05", days: 0) == "2026-09-05")
        // From any day, any arrow lands on a choosable day.
        let choosable = Set(g.weeks.joined().compactMap { $0 }.filter { if case .level = $0.state { true } else { false } }.map(\.date))
        for start in choosable { for (d, w) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            #expect(choosable.contains(g.day(from: start, days: d, weeks: w) ?? ""), "\(start) \(d) \(w)")
        } }
    }

    @Test("A real year: the cursor walks every day with data from the latest back to the first, one press each")
    func calendarWalksTheYear() throws {
        guard case .success(let stats) = StatsReader.parse(Data(StatsTests.file.utf8)) else { throw CancellationError() }
        let summary = StatsSummary.make(stats, range: .allTime, today: "2026-10-17")
        let grid = StatsCalendar.year(2026, stats: stats, levels: summary.heatmap, today: "2026-10-17", firstDay: stats.firstSessionDate)
        var day = grid.day(from: nil)
        var visited = [day]
        while let current = day, let previous = grid.day(from: current, days: -1), previous != current {
            visited.append(previous)
            day = previous
        }
        #expect(visited.first == "2026-10-17")                          // today counts (computed through yesterday or not)
        #expect(visited.last == "2026-10-10")                           // the first session's day
        #expect(visited.count == 8)
    }
}
