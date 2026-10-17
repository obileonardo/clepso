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

/// Stamps on the player card: the highest one earned in each category.
struct Milestone: Sendable, Equatable, Identifiable {
    let id: String
    let big: String        // "1", "30", "1B"
    let unit: String       // "YEAR", "DAY STREAK", "OUTPUT"
}

enum Milestones {
    static func make(file: ClaudeCodeStats, summary: StatsSummary) -> [Milestone] {
        var out: [Milestone] = []
        if let first = file.firstSessionDate {
            let days = StatsSummary.Day.between(first, summary.today)
            let tenure: [(Int, String, String)] = [(730, "2", "YEARS"), (365, "1", "YEAR"), (100, "100", "DAYS"), (30, "30", "DAYS")]
            if let t = tenure.first(where: { days >= $0.0 }) { out.append(Milestone(id: "tenure", big: t.1, unit: t.2)) }
        }
        if let s = [100, 30, 7].first(where: { summary.longestStreak >= $0 }) {
            out.append(Milestone(id: "streak", big: "\(s)", unit: "DAY STREAK"))
        }
        let output = file.models.map(\.output).reduce(0, +)
        let outputMarks: [(Int64, String)] = [(1_000_000_000, "1B"), (100_000_000, "100M"), (10_000_000, "10M"), (1_000_000, "1M")]
        if let o = outputMarks.first(where: { output >= $0.0 }) { out.append(Milestone(id: "output", big: o.1, unit: "OUTPUT")) }
        if let n = [1000, 100].first(where: { summary.sessions >= $0 }) {
            out.append(Milestone(id: "sessions", big: "\(n)", unit: "SESSIONS"))
        }
        return out
    }
}

/// The player card: who, since when, how far up the ladder, and four headline numbers.
struct PlayerCard: Sendable, Equatable {
    let name: String
    let since: String?             // the first session's day
    let plan: String?
    let output: Int64              // all-time output tokens, all models
    let level: ModelLevel
    let levelName: String
    let milestones: [Milestone]
    let streak: Int
    let topModel: String?
    let sessions: Int
    let longestSessionMs: Int64?

    static func make(file: ClaudeCodeStats, summary: StatsSummary, name: String, plan: String?) -> PlayerCard {
        let output = file.models.map(\.output).reduce(0, +)
        let level = ModelLevel(output: output)
        return PlayerCard(name: name, since: file.firstSessionDate, plan: plan, output: output, level: level,
                          levelName: LevelName.of(level.level), milestones: Milestones.make(file: file, summary: summary),
                          streak: summary.currentStreak, topModel: summary.favorite?.name, sessions: summary.sessions,
                          longestSessionMs: summary.longestSessionMs)
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
                out.append(GoalStatus(kind: .activeDays, value: "\(n)/7", target: "\(target)/7", fraction: min(1, Double(n) / Double(max(1, target))),
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
                out.append(GoalStatus(kind: .fiveHourPeak, value: "\(Int(peak.rounded()))%", target: "≤ \(target)%",
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
                out.append(GoalStatus(kind: .weeklyFinish, value: "\(Int(pct.rounded()))%", target: "≤ \(target)%",
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
