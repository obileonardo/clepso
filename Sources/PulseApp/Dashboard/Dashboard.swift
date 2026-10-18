import ClaudeCodeAdapter
import Foundation
import UsageEngine

/// Increment 1.10: the pure parts of Home, the player card and Goals. Everything here is computed from values the
/// app already holds (the snapshot, the statistics file, the user's goals), so it is tested without a window.

/// "Good afternoon, Elvis", by the hour in the user's time zone.
enum Greeting {
    static func make(_ date: Date, zone: TimeZone, name: String?) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: date)
        let part = switch hour {
        case 5..<12: Copy.Home.morning
        case 12..<17: Copy.Home.afternoon
        case 17..<22: Copy.Home.evening
        default: Copy.Home.late
        }
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return part }
        return "\(part), \(name)"
    }

    /// The first word of the Mac account's full name, as a default the user can change.
    static func defaultName(fullUserName: String) -> String? {
        fullUserName.split(separator: " ").first.map(String.init)
    }
}

/// A name for every level of the output ladder (`ModelLevel`), so a level reads as a place on the way up.
enum LevelName {
    static let names = ["Boot", "Prompt", "Script", "Loop", "Function", "Module", "Package", "Library", "Framework", "Compiler",
                        "Kernel", "Daemon", "Cluster", "Mainframe", "Grid", "Datacenter", "Backbone", "Network", "Constellation", "Singularity"]
    /// Past the last name, "Singularity II", "III" and so on.
    static func of(_ level: Int) -> String {
        guard level > 0 else { return names[0] }
        if level <= names.count { return names[level - 1] }
        let extra = level - names.count + 1
        let numerals = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
        return "\(names[names.count - 1]) \(extra < numerals.count ? numerals[extra] : String(extra))"
    }
}

/// The player card (1.10c; redesigned after the founder's review). Every figure is all time from Claude Code's
/// statistics file unless its name says otherwise; nothing is estimated.
struct PlayerCard: Sendable, Equatable {
    let name: String
    let since: String?             // the first session's day, YYYY-MM-DD
    let plan: String?
    /// Every token Claude Code has counted, all kinds (input, output, cache read, cache write), all models.
    let totalTokens: Int64
    let output: Int64              // all-time output tokens, all models: what the level is earned by
    let level: ModelLevel
    let levelName: String
    let currentStreak: Int         // consecutive active days ending today (or yesterday, if today has no activity yet)
    let bestStreak: Int            // the longest run of consecutive active days
    let activeDays: Int
    let dayCount: Int              // days since the first session, today included
    let topModel: String?          // most tokens, all time
    let topModelID: String?
    let topModelShare: Int?        // its share of all tokens, percent
    let sessions: Int
    let longestSessionMs: Int64?
    /// Lines over the sessions Clepso keeps (last 30 days at most); nil without any.
    let lines: CodeLines?
    /// The statistics file's last day: tokens stop there; days after it count as active on Clepso's own evidence.
    let statsThrough: String?
    let activity: CardActivity
    /// When the card's sources were last checked (the statistics file and Clepso's own readings).
    let updatedAt: Date?

    static func make(file: ClaudeCodeStats, summary: StatsSummary, name: String, plan: String?, lines: CodeLines? = nil,
                     updatedAt: Date? = nil, weeks: Int = CardActivity.weeks) -> PlayerCard {
        let output = file.models.map(\.output).reduce(0, +)
        let level = ModelLevel(output: output)
        return PlayerCard(name: name, since: file.firstSessionDate, plan: plan, totalTokens: RunningTotal.make(file).tokens,
                          output: output, level: level, levelName: LevelName.of(level.level),
                          currentStreak: summary.currentStreak, bestStreak: summary.longestStreak,
                          activeDays: summary.activeDays, dayCount: summary.dayCount,
                          topModel: summary.favorite?.name, topModelID: summary.favorite?.model,
                          topModelShare: summary.favorite.map { Int(($0.share * 100).rounded()) }, sessions: summary.sessions,
                          longestSessionMs: summary.longestSessionMs, lines: lines, statsThrough: summary.computedThrough,
                          activity: CardActivity.make(file: file, summary: summary, weeks: weeks), updatedAt: updatedAt)
    }
}

/// The back of the card: a contribution-style log of the last weeks, one square a day (Sunday on top), like the
/// Stats overview's calendar. Levels are the overview's quartiles of messages; `pending` marks a day Clepso saw
/// activity on that the statistics file doesn't cover yet.
struct CardActivity: Sendable, Equatable {
    struct Day: Sendable, Equatable {
        let date: String
        let level: Int             // 0 none … 4 busiest
        let pending: Bool
        /// Before the first session: drawn faintly, not counted.
        var beforeFirst = false
    }
    static let weeks = 30
    /// Columns of seven; nil after today.
    let columns: [[Day?]]
    let activeDays: Int
    let days: Int

    static func make(file: ClaudeCodeStats, summary: StatsSummary, weeks: Int) -> CardActivity {
        let today = summary.today
        let weekday = StatsSummary.Day.date(today).map { StatsSummary.Day.calendar.component(.weekday, from: $0) - 1 } ?? 0
        let count = 7 * (max(1, weeks) - 1) + weekday + 1             // starts on a Sunday, ends today
        let grid = StatsCalendar.recent(count, stats: file, levels: summary.heatmap, today: today,
                                        firstDay: file.firstSessionDate ?? file.days.first?.date)
        var active = 0, days = 0
        let columns: [[Day?]] = grid.weeks.map { week in
            week.map { cell in
                guard let cell, cell.date <= today else { return nil }
                guard case .level(let level) = cell.state else { return Day(date: cell.date, level: 0, pending: false, beforeFirst: true) }
                let pending = summary.seenActive.contains(cell.date)
                days += 1
                if level > 0 || pending { active += 1 }
                return Day(date: cell.date, level: level, pending: pending)
            }
        }
        return CardActivity(columns: columns, activeDays: active, days: days)
    }
}

/// Home's running total: every token Claude Code has counted, and the newest day it has folded in.
struct RunningTotal: Sendable, Equatable {
    let tokens: Int64
    let lastDay: Int64?
    let lastDayDate: String?

    static func make(_ file: ClaudeCodeStats) -> RunningTotal {
        let total = file.models.isEmpty ? file.dailyTokens.flatMap(\.byModel.values).reduce(0, +) : file.models.map(\.total).reduce(0, +)
        let last = file.dailyTokens.max { $0.date < $1.date }
        return RunningTotal(tokens: total, lastDay: last.map { $0.byModel.values.reduce(0, +) }, lastDayDate: last?.date)
    }
}

// MARK: - Goals

/// The user's goals, kept in preferences. A nil target is a goal that is turned off.
public struct Goals: Codable, Sendable, Equatable {
    public var activeDaysPerWeek: Int?
    public var fiveHourPeakMax: Int?
    public var weeklyFinishMax: Int?
    public init(activeDaysPerWeek: Int? = 5, fiveHourPeakMax: Int? = 80, weeklyFinishMax: Int? = 90) {
        self.activeDaysPerWeek = activeDaysPerWeek
        self.fiveHourPeakMax = fiveHourPeakMax
        self.weeklyFinishMax = weeklyFinishMax
    }
}

struct GoalStatus: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable, CaseIterable { case activeDays, fiveHourPeak, weeklyFinish }
    enum State: Sendable, Equatable { case met, onTrack, atRisk, missed, noData }
    let kind: Kind
    let value: String
    /// The value as a number (days, or percent), for upload; nil without data.
    var amount: Double? = nil
    let target: String
    /// How full the bar is: value against target, 0…1.
    let fraction: Double
    let state: State
    let detail: String
    /// Consecutive days the goal held, today included when it holds so far; nil where it doesn't apply.
    let streak: Int?
    var id: Kind { kind }
}

enum GoalEvaluator {
    /// `history` is the 5-hour limit's readings (oldest first); `sevenDayPct` and `sevenDayPace` are the 7-day limit's
    /// current value and pace estimate.
    static func evaluate(_ goals: Goals, last7: StatsSummary?, fiveHourHistory: [UsagePoint], sevenDayPct: Double?, sevenDayPace: PaceEstimate?,
                         now: Date, zone: TimeZone) -> [GoalStatus] {
        var out: [GoalStatus] = []
        if let target = goals.activeDaysPerWeek {
            if let last7 {
                let n = last7.activeDays
                out.append(GoalStatus(kind: .activeDays, value: "\(n)/7", amount: Double(n), target: "\(target)/7", fraction: min(1, Double(n) / Double(max(1, target))),
                                      state: n >= target ? .met : (n + 1 >= target ? .atRisk : .missed),
                                      detail: Copy.Goals.activeDetail(n, target), streak: nil))
            } else {
                out.append(GoalStatus(kind: .activeDays, value: "—", target: "\(target)/7", fraction: 0, state: .noData,
                                      detail: Copy.Goals.needsStats, streak: nil))
            }
        }
        if let target = goals.fiveHourPeakMax {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let today = calendar.startOfDay(for: now)
            var peaks: [Date: Double] = [:]
            for p in fiveHourHistory where p.at <= now { peaks[calendar.startOfDay(for: p.at), default: 0] = max(peaks[calendar.startOfDay(for: p.at)] ?? 0, p.usedPct) }
            if let peak = peaks[today] {
                var streak = 0
                var day = today
                while let p = peaks[day], p <= Double(target) {
                    streak += 1
                    guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
                    day = previous
                }
                out.append(GoalStatus(kind: .fiveHourPeak, value: "\(Int(peak.rounded()))%", amount: peak, target: "≤ \(target)%",
                                      fraction: min(1, peak / Double(max(1, target))), state: peak <= Double(target) ? .onTrack : .missed,
                                      detail: Copy.Goals.peakDetail(Int(peak.rounded()), target), streak: streak))
            } else {
                out.append(GoalStatus(kind: .fiveHourPeak, value: "—", target: "≤ \(target)%", fraction: 0, state: .noData,
                                      detail: Copy.Goals.noReadingsToday, streak: nil))
            }
        }
        if let target = goals.weeklyFinishMax {
            if let pct = sevenDayPct {
                let projected: Double = switch sevenDayPace {
                case .belowAtReset(let p)?: p
                case .reachesLimit?, .atLimit?: 100
                default: pct
                }
                let state: GoalStatus.State = pct > Double(target) ? .missed : (projected <= Double(target) ? .onTrack : .atRisk)
                out.append(GoalStatus(kind: .weeklyFinish, value: "\(Int(pct.rounded()))%", amount: pct, target: "≤ \(target)%",
                                      fraction: min(1, pct / Double(max(1, target))), state: state,
                                      detail: Copy.Goals.weeklyDetail(Int(pct.rounded()), projected: Int(projected.rounded()), target: target), streak: nil))
            } else {
                out.append(GoalStatus(kind: .weeklyFinish, value: "—", target: "≤ \(target)%", fraction: 0, state: .noData,
                                      detail: Copy.Goals.noReadingsToday, streak: nil))
            }
        }
        return out
    }
}

// MARK: - For you today (Home, after the founder's Deel pick)

/// One thing worth attention, most urgent first, with where to act on it.
struct ForYouItem: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable { case limit, goal, task, connect, stats, agents, account, allClear }
    let kind: Kind
    let title: String
    let detail: String
    let action: String?
    let section: AppModel.DetailsSection?
    var id: String { kind.rawValue + title }
}

enum ForYou {
    struct Input {
        var limits: [(scope: String, pct: Double?, state: GoalStatus.State)] = []   // atRisk ≥ 80%, missed ≥ 95%
        var goals: [GoalStatus] = []
        var runningTask: AgentsSummary.Task?
        var connected = true
        var statsOn = true
        var agentsOn = true
        var signedIn = true
        /// False in builds without an accounts project (builds from source): then sign-in is never suggested.
        var accountsAvailable = true
    }

    static func make(_ input: Input) -> [ForYouItem] {
        var items: [ForYouItem] = []
        for limit in input.limits where limit.state == .atRisk || limit.state == .missed {
            items.append(.init(kind: .limit, title: Copy.ForYou.limit(limit.scope, Int((limit.pct ?? 0).rounded())),
                               detail: limit.state == .missed ? Copy.ForYou.limitCritical : Copy.ForYou.limitApproaching,
                               action: Copy.ForYou.view, section: .limits))
        }
        for goal in input.goals where goal.state == .missed || goal.state == .atRisk {
            items.append(.init(kind: .goal, title: Copy.ForYou.goal(GoalsSection.title(goal.kind), goal.state == .missed),
                               detail: goal.detail, action: Copy.ForYou.view, section: .goals))
        }
        if let task = input.runningTask {
            items.append(.init(kind: .task, title: Copy.ForYou.running(task.agents), detail: task.byType.map { "\($0.name) \($0.count)" }.joined(separator: " · "),
                               action: Copy.ForYou.view, section: .session))
        }
        if !input.connected { items.append(.init(kind: .connect, title: Copy.ForYou.connectTitle, detail: Copy.Home.connectBody, action: Copy.Home.connect, section: nil)) }
        if !input.statsOn { items.append(.init(kind: .stats, title: Copy.ForYou.statsTitle, detail: Copy.Home.statsBody, action: Copy.Home.turnOn, section: nil)) }
        if !input.agentsOn { items.append(.init(kind: .agents, title: Copy.ForYou.agentsTitle, detail: Copy.Home.agentsBody, action: Copy.Home.turnOn, section: .settings)) }
        if input.accountsAvailable && !input.signedIn { items.append(.init(kind: .account, title: Copy.ForYou.signInTitle, detail: Copy.ForYou.signInBody, action: Copy.ForYou.signIn, section: .account)) }
        if items.isEmpty { items.append(.init(kind: .allClear, title: Copy.ForYou.allClear, detail: Copy.ForYou.allClearBody, action: nil, section: nil)) }
        return items
    }
}

// MARK: - Milestone ladders (Card, after the founder's Tripadvisor pick)

/// One category's rungs and where the user stands on them.
struct Ladder: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable, CaseIterable { case output, streak, sessions, activeDays }
    let kind: Kind
    let value: Int64
    let steps: [Int64]
    var id: Kind { kind }
    /// Rungs reached (0 = none yet).
    var reached: Int { steps.prefix { $0 <= value }.count }
    var next: Int64? { reached < steps.count ? steps[reached] : nil }
    var remaining: Int64? { next.map { $0 - value } }

    static func all(output: Int64, longestStreak: Int, sessions: Int, activeDays: Int) -> [Ladder] {
        [Ladder(kind: .output, value: output, steps: [10_000, 100_000, 1_000_000, 10_000_000, 100_000_000, 1_000_000_000]),
         Ladder(kind: .streak, value: Int64(longestStreak), steps: [3, 7, 14, 30, 60, 100, 365]),
         Ladder(kind: .sessions, value: Int64(sessions), steps: [10, 50, 100, 250, 500, 1000, 2500]),
         Ladder(kind: .activeDays, value: Int64(activeDays), steps: [7, 30, 100, 200, 365, 730])]
    }
}

// MARK: - Goal history (Goals detail, after the founder's Charma pick)

struct GoalDay: Sendable, Equatable, Identifiable {
    let day: String          // YYYY-MM-DD, local
    let value: Double?
    let met: Bool?
    var id: String { day }
}

enum GoalHistory {
    /// The last seven local days, oldest first: the 5-hour peak, the 7-day value at the day's last reading, or whether the
    /// day was active. nil value: no data that day.
    static func days(_ kind: GoalStatus.Kind, goals: Goals, fiveHour: [UsagePoint], sevenDay: [UsagePoint],
                     activeDays: Set<String>, knownThrough: String? = nil, now: Date, zone: TimeZone) -> [GoalDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        func label(_ date: Date) -> String {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        let labels = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0 - 6, to: now).map(label) }
        switch kind {
        case .activeDays:
            // Days after the statistics file's last day aren't known yet (unless already seen active): no data, not "missed".
            return labels.map { day in
                if !activeDays.contains(day), let known = knownThrough, day > known { return GoalDay(day: day, value: nil, met: nil) }
                return GoalDay(day: day, value: activeDays.contains(day) ? 1 : 0, met: activeDays.contains(day))
            }
        case .fiveHourPeak:
            var peaks: [String: Double] = [:]
            for p in fiveHour where p.at <= now { peaks[label(p.at)] = max(peaks[label(p.at)] ?? 0, p.usedPct) }
            return labels.map { day in
                let v = peaks[day]
                return GoalDay(day: day, value: v, met: v.flatMap { v in goals.fiveHourPeakMax.map { v <= Double($0) } })
            }
        case .weeklyFinish:
            var last: [String: (Date, Double)] = [:]
            for p in sevenDay where p.at <= now {
                if let l = last[label(p.at)], l.0 > p.at { continue }
                last[label(p.at)] = (p.at, p.usedPct)
            }
            return labels.map { day in
                let v = last[day]?.1
                return GoalDay(day: day, value: v, met: v.flatMap { v in goals.weeklyFinishMax.map { v <= Double($0) } })
            }
        }
    }
}
