import ClaudeCodeAdapter
import Foundation

/// Calendar layouts for the Stats overview (increment 1.8e), like GitHub's contribution graph. Pure; days are
/// Claude Code's own `YYYY-MM-DD` labels, so no time zone is involved.
public enum StatsCalendar {
    /// One square. `noData` (before the first session or after today) is drawn differently from a quiet day.
    public struct Cell: Sendable, Equatable {
        public enum State: Sendable, Equatable { case noData, level(Int) }
        public let date: String
        public let state: State
        public let messages: Int
        public let sessions: Int
    }

    public struct Grid: Sendable, Equatable {
        /// Columns of seven rows (Sunday on top); nil pads the first and last week outside the period.
        public let weeks: [[Cell?]]
        /// Month name over the column holding that month's first day.
        public let months: [(column: Int, label: String)]
        public static func == (a: Grid, b: Grid) -> Bool {
            a.weeks == b.weeks && a.months.map(\.column) == b.months.map(\.column) && a.months.map(\.label) == b.months.map(\.label)
        }
    }

    /// January to December of `year`, GitHub style.
    public static func year(_ year: Int, stats: ClaudeCodeStats, levels: [String: Int], today: String, firstDay: String?) -> Grid {
        layout(from: String(format: "%04d-01-01", year), through: String(format: "%04d-12-31", year), stats: stats, levels: levels,
               today: today, firstDay: firstDay)
    }

    /// The last `days` days ending today (30-day view: a month calendar).
    public static func recent(_ days: Int, stats: ClaudeCodeStats, levels: [String: Int], today: String, firstDay: String?) -> Grid {
        layout(from: StatsSummary.Day.adding(-(days - 1), to: today), through: today, stats: stats, levels: levels, today: today, firstDay: firstDay)
    }

    /// Claude Code's first public release (a research preview, February 2025): no statistics file holds an earlier day.
    public static let firstYear = 2025

    /// The years the all-time calendar can show: from 2025, or the first session's year if that is earlier, through
    /// today's year. Before the first session a year is drawn as "no data" (founder, 19 Oct 2026: the switcher has to go
    /// back past the first year with data); never a year after today's, and never further back than Claude Code.
    public static func years(firstDay: String?, today: String) -> [Int] {
        let last = Int(today.prefix(4)) ?? 0
        let first = min(firstDay.flatMap { Int($0.prefix(4)) } ?? firstYear, firstYear)
        return Array(min(first, last)...last)
    }

    /// The year to show for a chosen one: today's year when none is chosen, otherwise the chosen year held to `years`.
    public static func shownYear(_ chosen: Int?, of years: [Int]) -> Int {
        guard let first = years.first, let last = years.last else { return chosen ?? 0 }
        return min(max(chosen ?? last, first), last)
    }

    static func layout(from start: String, through end: String, stats: ClaudeCodeStats, levels: [String: Int],
                       today: String, firstDay: String?) -> Grid {
        let byDate = Dictionary(stats.days.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        guard let startDate = StatsSummary.Day.date(start) else { return Grid(weeks: [], months: []) }
        let leading = StatsSummary.Day.calendar.component(.weekday, from: startDate) - 1        // Sunday = 0
        var weeks: [[Cell?]] = []
        var week: [Cell?] = Array(repeating: nil, count: leading)
        var months: [(Int, String)] = []
        var day = start
        while day <= end {
            if day.hasSuffix("-01") || day == start, let date = StatsSummary.Day.date(day) {
                let label = date.formatted(Date.FormatStyle(timeZone: StatsSummary.Day.calendar.timeZone).month(.abbreviated))
                months.append((weeks.count, label))
            }
            let outside = day > today || (firstDay.map { day < $0 } ?? false)
            let record = byDate[day]
            week.append(Cell(date: day, state: outside ? .noData : .level(levels[day] ?? 0),
                             messages: record?.messages ?? 0, sessions: record?.sessions ?? 0))
            if week.count == 7 { weeks.append(week); week = [] }
            day = StatsSummary.Day.adding(1, to: day)
        }
        if !week.isEmpty { weeks.append(week + Array(repeating: nil, count: 7 - week.count)) }
        // A label squeezed into the column right before the next one would collide; keep the later month.
        let spaced = months.enumerated().filter { i, m in i + 1 >= months.count || months[i + 1].0 - m.0 >= 2 }.map(\.element)
        return Grid(weeks: weeks, months: spaced)
    }
}

extension StatsCalendar.Grid {
    /// Item 9: the day a keyboard cursor reaches from `date`, `days` (±1) or `weeks` (±1) away. Only days with data
    /// are reached (the ones a click can choose); padding and no-data days are passed over in the same direction, and
    /// at the edge the cursor stays. From no day, or a day not in the grid: the latest day with data.
    public func day(from date: String?, days: Int = 0, weeks: Int = 0) -> String? {
        let cells = self.weeks.flatMap { $0 }
        func choosable(_ cell: StatsCalendar.Cell?) -> Bool { if case .level = cell?.state { true } else { false } }
        guard let date, let start = cells.firstIndex(where: { $0?.date == date }) else {
            return cells.last(where: choosable)??.date
        }
        let stride = days + 7 * weeks
        guard stride != 0 else { return date }
        var index = start + stride
        while cells.indices.contains(index) {
            if choosable(cells[index]) { return cells[index]?.date }
            index += stride
        }
        return date
    }
}

/// Time axes for the Limits chart (increment 1.8d): the limit's own window, whole-hour or whole-day ticks.
public enum ChartAxis {
    /// The window a limit counts within: the reset minus its length, through the reset. Without a reset time,
    /// the length ending now.
    public static func window(length: TimeInterval, resetsAt: Date?, now: Date) -> ClosedRange<Date> {
        guard let resetsAt, resetsAt > now.addingTimeInterval(-length) else { return now.addingTimeInterval(-length)...now }
        return resetsAt.addingTimeInterval(-length)...resetsAt
    }

    /// Ticks on whole hours (windows up to a day) or local midnights (longer), never more than `maxTicks`.
    public static func ticks(_ range: ClosedRange<Date>, zone: TimeZone, maxTicks: Int = 8) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let span = range.upperBound.timeIntervalSince(range.lowerBound)
        let unit: Calendar.Component = span <= 86_400 ? .hour : .day
        guard var tick = calendar.nextDate(after: range.lowerBound.addingTimeInterval(-1),
                                           matching: unit == .hour ? DateComponents(minute: 0, second: 0) : DateComponents(hour: 0, minute: 0, second: 0),
                                           matchingPolicy: .nextTime) else { return [] }
        var all: [Date] = []
        while tick <= range.upperBound {
            all.append(tick)
            guard let next = calendar.date(byAdding: unit, value: 1, to: tick) else { break }
            tick = next
        }
        let stride = max(1, Int((Double(all.count) / Double(maxTicks)).rounded(.up)))
        return all.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
    }
}
