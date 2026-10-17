import ClaudeCodeAdapter
import Foundation

/// The Stats view's numbers (increment 1.7f), derived from Claude Code's own statistics file the way `/stats` shows
/// them: all time, or the last 30 or 7 days ending on `today`. Pure; dates are Claude Code's calendar days.
public struct StatsSummary: Sendable, Equatable {
    public enum Range: String, CaseIterable, Sendable { case allTime, last30, last7 }

    public struct ModelShare: Sendable, Equatable, Identifiable {
        public var id: String { model }
        public let model: String
        public let name: String
        public let tokens: Int64
        public let share: Double                 // 0…1 of the range's tokens
        public let totals: ClaudeCodeStats.ModelTotals?    // all-time breakdown (in, out, cache read, cache write)
    }

    public let range: Range
    public let today: String
    public let dayCount: Int                     // days in the range (all time: since the first session)
    public let activeDays: Int
    public let currentStreak: Int
    public let longestStreak: Int
    public let mostActiveDay: String?
    public let sessions: Int
    public let messages: Int
    public let totalTokens: Int64
    public let models: [ModelShare]              // largest first
    public let longestSessionMs: Int64?
    /// date → activity level 0 (none) … 4 (busiest quarter), for the heatmap.
    public let heatmap: [String: Int]
    /// Per day in the range, tokens by model id, oldest first (the Models chart).
    public let dailyTokens: [ClaudeCodeStats.DayTokens]
    public let hourCounts: [Int: Int]
    /// The last day the file covers. Claude Code folds a day in after it ends, so tokens stop here; see `seenToday`.
    public let computedThrough: String?
    public var favorite: ModelShare? { models.first }

    /// `seenToday`: Pulse received Claude Code readings today. Claude Code's file covers days up to yesterday, so today
    /// counts as active for days and streaks on Pulse's own evidence; today's tokens are not invented.
    public static func make(_ stats: ClaudeCodeStats, range: Range, today: String, seenToday: Bool = false) -> StatsSummary {
        let first: String = switch range {
        case .allTime: stats.firstSessionDate ?? stats.days.first?.date ?? today
        case .last30: Day.adding(-29, to: today)
        case .last7: Day.adding(-6, to: today)
        }
        let days = stats.days.filter { $0.date >= first && $0.date <= today }
        let active = days.filter { $0.messages > 0 }
        var activeSet = Set(active.map(\.date))
        if seenToday { activeSet.insert(today) }
        let tokensInRange = stats.dailyTokens.filter { $0.date >= first && $0.date <= today }

        // All time uses Claude Code's per-model totals (input, output and cache), as /stats does; a shorter range can
        // only use the per-day counts.
        var byModel: [String: Int64] = [:]
        if range == .allTime, !stats.models.isEmpty {
            for m in stats.models { byModel[m.model] = m.total }
        } else {
            for day in tokensInRange { for (m, n) in day.byModel { byModel[m, default: 0] += n } }
        }
        let total = byModel.values.reduce(0, +)
        let totalsByModel = Dictionary(stats.models.map { ($0.model, $0) }, uniquingKeysWith: { a, _ in a })
        let models = byModel.filter { $0.value > 0 }
            .map { ModelShare(model: $0.key, name: StatsReader.displayName($0.key), tokens: $0.value,
                              share: total > 0 ? Double($0.value) / Double(total) : 0, totals: totalsByModel[$0.key]) }
            .sorted { ($0.tokens, $1.model) > ($1.tokens, $0.model) }

        return StatsSummary(
            range: range, today: today, dayCount: Day.between(first, today) + 1, activeDays: activeSet.filter { $0 >= first && $0 <= today }.count,
            currentStreak: Day.streak(endingOn: activeSet.contains(today) ? today : Day.adding(-1, to: today), in: activeSet),
            longestStreak: Day.longestRun(activeSet),
            mostActiveDay: active.max { ($0.messages, $1.date) < ($1.messages, $0.date) }?.date,
            sessions: range == .allTime ? (stats.totalSessions ?? days.map(\.sessions).reduce(0, +)) : days.map(\.sessions).reduce(0, +),
            messages: range == .allTime ? (stats.totalMessages ?? days.map(\.messages).reduce(0, +)) : days.map(\.messages).reduce(0, +),
            totalTokens: total, models: models, longestSessionMs: stats.longestSessionMs,
            heatmap: heatmapLevels(days), dailyTokens: tokensInRange, hourCounts: stats.hourCounts, computedThrough: stats.computedThrough)
    }

    /// Quartiles of messages on active days: 1 for the quietest quarter … 4 for the busiest; 0 for no activity.
    static func heatmapLevels(_ days: [ClaudeCodeStats.Day]) -> [String: Int] {
        let counts = days.map(\.messages).filter { $0 > 0 }.sorted()
        guard !counts.isEmpty else { return [:] }
        func quartile(_ q: Double) -> Int { counts[min(counts.count - 1, Int(Double(counts.count - 1) * q))] }
        let (q1, q2, q3) = (quartile(0.25), quartile(0.5), quartile(0.75))
        var levels: [String: Int] = [:]
        for day in days {
            levels[day.date] = day.messages == 0 ? 0 : day.messages <= q1 ? 1 : day.messages <= q2 ? 2 : day.messages <= q3 ? 3 : 4
        }
        return levels
    }

    /// Calendar arithmetic on YYYY-MM-DD strings (no time zone involved: these are Claude Code's own day labels).
    enum Day {
        static let calendar: Calendar = {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: "UTC")!
            return c
        }()
        static func date(_ s: String) -> Date? {
            let p = s.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
        }
        static func string(_ d: Date) -> String {
            let c = calendar.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        static func adding(_ n: Int, to s: String) -> String {
            guard let d = date(s), let r = calendar.date(byAdding: .day, value: n, to: d) else { return s }
            return string(r)
        }
        static func between(_ a: String, _ b: String) -> Int {
            guard let x = date(a), let y = date(b) else { return 0 }
            return calendar.dateComponents([.day], from: x, to: y).day ?? 0
        }
        static func streak(endingOn end: String, in active: Set<String>) -> Int {
            var n = 0, day = end
            while active.contains(day) { n += 1; day = adding(-1, to: day) }
            return n
        }
        static func longestRun(_ active: Set<String>) -> Int {
            active.map { start in active.contains(adding(-1, to: start)) ? 0 : streak(endingOn: start, forwardIn: active) }.max() ?? 0
        }
        static func streak(endingOn start: String, forwardIn active: Set<String>) -> Int {
            var n = 0, day = start
            while active.contains(day) { n += 1; day = adding(1, to: day) }
            return n
        }
    }
}
