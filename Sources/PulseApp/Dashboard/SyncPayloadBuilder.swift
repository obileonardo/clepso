import ClaudeCodeAdapter
import Foundation
import Storage
import Sync
import UsageEngine

/// What one upload sends, built from what the app already holds. Pure. Only data the user turned on is
/// included: the statistics file's rows only when it is on, agents per task only when counting is on.
enum SyncPayloadBuilder {
    struct Input {
        var profileName: String?
        var planLabel: String?
        var stats: ClaudeCodeStats?
        var fiveHour: [UsagePoint] = []
        var sevenDay: [UsagePoint] = []
        var agentTasks: [Store.AgentTask]?
        var goals = Goals()
        var goalStatuses: [GoalStatus] = []
        var now: Date
        var zone: TimeZone
    }

    /// The last `days` days are re-sent each time, so late data (the statistics file runs a day behind) corrects itself.
    static func make(_ input: Input, days: Int = 14) -> SyncPayload {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = input.zone
        func label(_ date: Date) -> String {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        let today = label(input.now)
        let first = label(calendar.date(byAdding: .day, value: -(days - 1), to: input.now) ?? input.now)
        var payload = SyncPayload()
        payload.profile = .init(displayName: input.profileName, planLabel: input.planLabel)

        if let stats = input.stats {
            payload.activity = stats.days.filter { $0.date >= first && $0.date <= today }
                .map { .init(day: $0.date, messages: $0.messages, sessions: $0.sessions, active: $0.messages > 0) }
            payload.modelTokens = stats.dailyTokens.filter { $0.date >= first && $0.date <= today }
                .flatMap { day in day.byModel.sorted { $0.key < $1.key }.map { .init(day: day.date, model: $0.key, tokens: $0.value) } }
            payload.modelTotals = stats.models.map { .init(model: $0.model, input: $0.input, output: $0.output, cacheRead: $0.cacheRead, cacheWrite: $0.cacheWrite) }
        }

        // Limits per local day: the 5-hour peak, and the 7-day value at the day's last reading.
        var peaks: [String: Double] = [:], ends: [String: (Date, Double)] = [:]
        for p in input.fiveHour where label(p.at) >= first && p.at <= input.now { peaks[label(p.at)] = max(peaks[label(p.at)] ?? 0, p.usedPct) }
        for p in input.sevenDay where label(p.at) >= first && p.at <= input.now {
            if let last = ends[label(p.at)], last.0 > p.at { continue }
            ends[label(p.at)] = (p.at, p.usedPct)
        }
        payload.limits = Set(peaks.keys).union(ends.keys).sorted().map { day in
            .init(day: day, fiveHourPeakPct: peaks[day].map { min(100, max(0, $0)) }, sevenDayEndPct: ends[day].map { min(100, max(0, $0.1)) })
        }

        if let tasks = input.agentTasks {
            var byDay: [String: (tasks: Int, agents: Int, types: [String: Int])] = [:]
            for t in tasks where label(t.startedAt) >= first {
                var d = byDay[label(t.startedAt)] ?? (0, 0, [:])
                d.tasks += 1
                d.agents += t.agents
                for (type, n) in t.byType { d.types[type, default: 0] += n }
                byDay[label(t.startedAt)] = d
            }
            payload.agents = byDay.keys.sorted().map { .init(day: $0, tasks: byDay[$0]!.tasks, agents: byDay[$0]!.agents, byType: byDay[$0]!.types) }
        }

        payload.goals = [.init(kind: GoalStatus.Kind.activeDays.rawValue, target: input.goals.activeDaysPerWeek),
                         .init(kind: GoalStatus.Kind.fiveHourPeak.rawValue, target: input.goals.fiveHourPeakMax),
                         .init(kind: GoalStatus.Kind.weeklyFinish.rawValue, target: input.goals.weeklyFinishMax)]
        payload.goalDays = input.goalStatuses.compactMap { status in
            guard status.state != .noData, let amount = status.amount else { return nil }
            let met: Bool? = switch status.state {
            case .met, .onTrack: true
            case .missed: false
            case .atRisk, .noData: nil
            }
            return .init(day: today, kind: status.kind.rawValue, value: (amount * 100).rounded() / 100, met: met)
        }
        return payload
    }
}
