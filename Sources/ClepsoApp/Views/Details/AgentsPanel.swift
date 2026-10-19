import DesignSystem
import Domain
import SwiftUI

/// Agents per task (increment 1.9; cards after the founder's review of 18 Oct 2026) on the Session page: the 30-day
/// figures as cards, the latest task as a card of its own, and the recent tasks as a table. Counts and types only;
/// when the hooks aren't installed, what turning them on would do and where. Item 4: the same panel for Codex, from
/// its session files, with the approval auto-reviews Codex ran beside each task's agents.
struct AgentsPanel: View {
    enum Source { case claudeCode, codex }
    let summary: AgentsSummary?
    let now: Date
    let zone: TimeZone
    let locale: Locale
    var source: Source = .claudeCode
    let openProviders: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// 1.14: content only; the page's section supplies the name and the line.
    var body: some View {
        if let summary {
            if let latest = summary.latest {
                VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                    totals(summary)
                    if !summary.live.isEmpty { liveCard(summary.live) }
                    latestCard(latest, othersRunning: summary.live.contains { !$0.inLatestTask })
                    if summary.recent.count > 1 { recent(summary) }
                }
            } else {
                Text(source == .codex ? Copy.Agents.codexNoTasks : Copy.Agents.noTasks).font(theme.font(.label))
                    .foregroundStyle(theme.color(.textSecondary, scheme)).fixedSize(horizontal: false, vertical: true)
            }
        } else if source == .codex {
            Text(Copy.Agents.codexReading).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
        } else {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                Text(Copy.Agents.offBody).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Button(Copy.Agents.openSettings, action: openProviders).buttonStyle(PixelButtonStyle())
            }
        }
    }

    /// The last 30 days in four cards: how many tasks, how many used subagents, the average and the most.
    func totals(_ s: AgentsSummary) -> some View {
        StatCardRow {
            StatCard(caption: Copy.Agents.tasks, value: "\(s.tasks)", detail: Copy.Agents.last30)
            StatCard(caption: Copy.Agents.withAgents, value: s.tasks > 0 ? "\(Self.share(s))%" : "—",
                     detail: Copy.Agents.ofTasks(s.tasksWithAgents, s.tasks))
            StatCard(caption: Copy.Agents.average, value: String(format: "%.1f", s.averagePerTask), detail: Copy.Agents.inAll(s.totalAgents))
            StatCard(caption: Copy.Agents.most, value: "\(s.mostInOneTask)", detail: Copy.Agents.oneTask)
        }
    }

    /// Whole-percent share of the 30 days' tasks that started at least one subagent.
    static func share(_ s: AgentsSummary) -> Int {
        s.tasks > 0 ? Int((Double(s.tasksWithAgents) / Double(s.tasks) * 100).rounded()) : 0
    }

    /// Subagents running now, from every task (founder review, 19 Oct 2026): a background subagent keeps working after
    /// the prompt that started it, so the latest task alone can't say what is running. How many, by type, and one row
    /// each: its type, the task that started it, and how long it has run (or, with no event from its session for 10
    /// minutes, when Clepso last heard from it).
    func liveCard(_ live: [AgentsSummary.LiveAgent]) -> some View {
        let allStale = live.allSatisfy(\.stale)
        let shown = 6
        return VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            HStack(alignment: .top, spacing: theme.spacing(.spacious)) {
                VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                    Text(Copy.Agents.runningNow).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
                    HStack(alignment: .center, spacing: theme.spacing(.standard) + theme.spacing(.compact)) {
                        Text(Copy.Agents.count(live.count).uppercased()).font(theme.font(.metricHero))
                            .foregroundStyle(theme.color(.textPrimary, scheme)).lineLimit(1).minimumScaleFactor(0.6)
                            .padding(.vertical, -theme.spacing(.compact))
                        RunTag(text: allStale ? Copy.Agents.lastSeen(Formatting.age(of: live.map(\.lastSeen).max() ?? now, now: now, zone: zone, locale: locale))
                                        : Copy.Agents.running, lit: !allStale)
                    }
                    Text(liveWhen(live)).font(theme.font(.supporting)).monospacedDigit().foregroundStyle(theme.color(.textSecondary, scheme))
                }
                Spacer(minLength: theme.spacing(.spacious))
                FlowTags(tags: Self.typeCounts(live.map(\.type)).map { "\($0.name.uppercased()) \($0.count)" })
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(live.prefix(shown).enumerated()), id: \.offset) { _, agent in liveRow(agent) }
            }
            if live.count > shown {
                Text(Copy.Agents.more(live.count - shown)).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
            if live.contains(where: \.stale) {
                Text(Copy.Agents.liveNote).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pageCard(allStale ? .separator : .accent)
    }

    /// One running subagent on a faint rule: type, the task that started it, how long it has run or when last heard from.
    func liveRow(_ agent: AgentsSummary.LiveAgent) -> some View {
        let task = agent.inLatestTask ? Copy.Agents.thisTask : Copy.Agents.fromTask(Self.started(agent.taskStartedAt, now: now, zone: zone, locale: locale))
        let state = agent.stale ? Copy.Agents.lastSeen(Formatting.age(of: agent.lastSeen, now: now, zone: zone, locale: locale))
            : Copy.Agents.runningFor(Self.elapsed(since: agent.startedAt, now: now))
        return HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.spacious)) {
            Text(agent.type).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                .lineLimit(1).frame(width: AgentsMetrics.liveType, alignment: .leading)
            Text(task).font(theme.font(.supporting)).monospacedDigit().foregroundStyle(theme.color(.textSecondary, scheme))
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(state).font(theme.font(.label)).monospacedDigit()
                .foregroundStyle(theme.color(agent.stale ? .textSecondary : .accent, scheme))
                .lineLimit(1).frame(width: AgentsMetrics.liveState, alignment: .trailing)
        }
        .padding(.vertical, theme.spacing(.standard))
        .overlay(alignment: .top) { Rectangle().fill(theme.color(.separator, scheme).opacity(0.5)).frame(height: theme.stroke(.hairline)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([agent.type, task, state].joined(separator: ", "))
    }

    /// "From 3 tasks · Oldest started 00:43", or the one agent's start time.
    func liveWhen(_ live: [AgentsSummary.LiveAgent]) -> String {
        let tasks = Set(live.map(\.taskStartedAt)).count
        let oldest = live.map(\.startedAt).min() ?? now
        let time = Self.started(oldest, now: now, zone: zone, locale: locale)
        return [Copy.Agents.fromTasks(tasks), live.count > 1 ? Copy.Agents.oldestStarted(time) : Copy.Agents.started(time)]
            .joined(separator: " · ")
    }

    /// Counts per display name, in the order the types come in Clepso's type order: built-in types, then approved custom
    /// names (A to Z), then Custom.
    nonisolated static func typeCounts(_ names: [String]) -> [(name: String, count: Int)] {
        let order = OverviewProjection.agentTypeOrder.map(OverviewProjection.agentTypeName)
        let custom = order.count - 1                                   // Custom is last in the type order
        func rank(_ name: String) -> Int { order.firstIndex(of: name).map { $0 == custom ? custom + 1 : $0 } ?? custom }
        let counts = Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.keys.sorted { (rank($0), $0) < (rank($1), $1) }.map { ($0, counts[$0] ?? 0) }
    }

    /// "under 1m", "14m", "1h 5m": how long a subagent has run, to the minute (the page refreshes about once a minute).
    nonisolated static func elapsed(since start: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        guard s >= 60 else { return "under 1m" }
        return s >= 3600 ? "\(s / 3600)h \(s % 3600 / 60)m" : "\(s / 60)m"
    }

    /// The newest task: its count large, in progress or done in words, its types as tags at the top right and how many
    /// have finished at the bottom right, on the same line as when it started (founder review, 19 Oct 2026).
    func latestCard(_ task: AgentsSummary.Task, othersRunning: Bool = false) -> some View {
        HStack(alignment: .top, spacing: theme.spacing(.spacious)) {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                Text(Copy.Agents.latest).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
                HStack(alignment: .center, spacing: theme.spacing(.standard) + theme.spacing(.compact)) {
                    Text((task.agents > 0 ? Copy.Agents.count(task.agents) : othersRunning ? Copy.Agents.noneNew : Copy.Agents.none).uppercased())
                        .font(theme.font(.metricHero))
                        .foregroundStyle(theme.color(.textPrimary, scheme)).lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.vertical, -theme.spacing(.compact))
                    RunTag(text: task.running ? Copy.Agents.inProgress : Copy.Agents.done, lit: task.running)
                }
                Spacer(minLength: 0)
                Text(when(task)).font(theme.font(.supporting)).monospacedDigit().foregroundStyle(theme.color(.textSecondary, scheme))
            }
            .frame(maxHeight: .infinity, alignment: .top)
            Spacer(minLength: theme.spacing(.spacious))
            if task.agents > 0 {
                VStack(alignment: .trailing, spacing: theme.spacing(.standard)) {
                    FlowTags(tags: task.byType.map { "\($0.name.uppercased()) \($0.count)" })
                    Spacer(minLength: 0)
                    // Text first and as tall as the left's "Started" line in the same font, so the two baselines meet.
                    HStack(alignment: .center, spacing: theme.spacing(.standard)) {
                        Text(finishedLine(task)).font(theme.font(.supporting)).monospacedDigit()
                            .foregroundStyle(theme.color(.textSecondary, scheme)).lineLimit(1)
                        PixelBar(fraction: Double(task.finished) / Double(max(1, task.agents)), role: .accent, pattern: .solid,
                                 segments: min(max(task.agents, 4), 12))
                            .frame(width: AgentsMetrics.finishedBar, height: AgentsMetrics.finishedBarHeight)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pageCard(task.running ? .accent : .separator)
        .accessibilityElement(children: .combine)
    }

    /// "2 of 3 finished", plus any whose stop never came.
    func finishedLine(_ task: AgentsSummary.Task) -> String {
        ([Copy.Agents.finished(task.finished, of: task.agents)] + (task.noStopSeen > 0 ? [Copy.Agents.noStopSeen(task.noStopSeen)] : []))
            .joined(separator: " · ")
    }

    /// Recent tasks as a table: when, how many (a meter scaled to the busiest, and the number), which types, how long.
    func recent(_ s: AgentsSummary) -> some View {
        let top = max(1, s.recent.map(\.agents).max() ?? 1)
        return VStack(alignment: .leading, spacing: 0) {
            Text(Copy.Agents.recent).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
                .padding(.bottom, theme.spacing(.standard))
            row(Text(Copy.Agents.colStarted.uppercased()), agents: nil, count: Text(Copy.Agents.colAgents.uppercased()),
                types: Text(Copy.Agents.colTypes.uppercased()), duration: Text(Copy.Agents.colDuration.uppercased()), header: true)
                .accessibilityHidden(true)
            ForEach(s.recent) { task in
                let types = (task.byType.map { "\($0.name) \($0.count)" } + agentStates(task) + reviews(task)).joined(separator: " · ")
                row(Text(Self.started(task.startedAt, now: now, zone: zone, locale: locale)),
                    agents: Double(task.agents) / Double(top),
                    count: Text("\(task.agents)"),
                    types: Text(types.isEmpty ? Copy.Agents.none : types),
                    duration: Text(task.running ? Copy.Agents.inProgress : duration(task) ?? "—"),
                    header: false, running: task.running, empty: task.agents == 0)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.started(task.startedAt, now: now, zone: zone, locale: locale) + ": " + line(task))
            }
        }
    }

    /// When a task started: the time today, and the day too for an earlier day, so yesterday's 23:50 never reads as today's.
    nonisolated static func started(_ date: Date, now: Date, zone: TimeZone, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let time = Formatting.clock(date, zone: zone, locale: locale)
        guard !calendar.isDate(date, inSameDayAs: now) else { return time }
        let day = DateFormatter()
        day.locale = locale
        day.timeZone = zone
        day.setLocalizedDateFormatFromTemplate(now.timeIntervalSince(date) < 6 * 86_400 ? "EEE" : "d MMM")
        return day.string(from: date) + " " + time
    }

    /// One table row on a faint rule; the header row is small capitals in the secondary colour.
    func row(_ started: Text, agents: Double?, count: Text, types: Text, duration: Text, header: Bool,
             running: Bool = false, empty: Bool = false) -> some View {
        let cell: Font = header ? theme.font(.micro) : theme.font(.label)
        let secondary = theme.color(.textSecondary, scheme), primary = theme.color(.textPrimary, scheme)
        return HStack(alignment: .center, spacing: theme.spacing(.spacious)) {
            started.font(cell).monospacedDigit().foregroundStyle(header ? secondary : primary)
                .frame(width: AgentsMetrics.time, alignment: .leading)
            HStack(spacing: theme.spacing(.standard)) {
                if let agents {
                    PixelBar(fraction: agents, role: .accent, pattern: .solid, segments: 16).frame(width: AgentsMetrics.bar)
                }
                count.font(cell).monospacedDigit().foregroundStyle(header || empty ? secondary : primary)
                    .frame(minWidth: AgentsMetrics.count, alignment: .leading)
            }
            .frame(width: AgentsMetrics.agents, alignment: .leading)
            types.font(header ? cell : theme.font(.supporting)).foregroundStyle(secondary).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            duration.font(cell).monospacedDigit().foregroundStyle(header ? secondary : running ? theme.color(.accent, scheme) : primary)
                .frame(width: AgentsMetrics.duration, alignment: .trailing)
        }
        .padding(.vertical, header ? theme.spacing(.compact) : theme.spacing(.standard) + theme.spacing(.compact) / 2)
        .overlay(alignment: .top) {
            if !header { Rectangle().fill(theme.color(.separator, scheme).opacity(0.5)).frame(height: theme.stroke(.hairline)) }
        }
    }

    func duration(_ task: AgentsSummary.Task) -> String? {
        task.endedAt.map { Formatting.duration(milliseconds: Int64($0.timeIntervalSince(task.startedAt) * 1000)) }
    }

    func when(_ task: AgentsSummary.Task) -> String {
        let start = Copy.Agents.started(Formatting.clock(task.startedAt, zone: zone, locale: locale))
        let took = task.running ? nil : duration(task)
        return ([start] + [took].compactMap { $0 } + reviews(task)).joined(separator: " · ")
    }

    /// Subagents of a task still running or never heard from again, in words, when there are any.
    func agentStates(_ task: AgentsSummary.Task) -> [String] {
        (task.stillRunning > 0 ? [Copy.Agents.stillRunning(task.stillRunning)] : [])
            + (task.noStopSeen > 0 ? [Copy.Agents.noStopSeen(task.noStopSeen)] : [])
    }

    /// Codex's auto-reviews as words, when it ran any; never part of the agent counts.
    func reviews(_ task: AgentsSummary.Task) -> [String] {
        task.reviews > 0 ? [Copy.Agents.reviews(task.reviews)] : []
    }

    func line(_ task: AgentsSummary.Task) -> String {
        let count = task.agents == 0 ? Copy.Agents.none : Copy.Agents.count(task.agents)
        let types = task.byType.map { "\($0.name) \($0.count)" }.joined(separator: ", ")
        let took = task.running ? Copy.Agents.inProgress : duration(task)
        return ([count, types.isEmpty ? nil : types, took].compactMap { $0 } + agentStates(task) + reviews(task)).joined(separator: " · ")
    }
}

/// Column widths of the recent-tasks table, so every row lines up.
enum AgentsMetrics {
    static let time: CGFloat = 64
    static let bar: CGFloat = 150
    static let count: CGFloat = 28
    static let agents: CGFloat = 190
    static let duration: CGFloat = 96
    static let finishedBar: CGFloat = 90
    static let finishedBarHeight: CGFloat = 10
    static let liveType: CGFloat = 170
    static let liveState: CGFloat = 170
}

/// A state in words and shape (never colour alone): lit for running or in progress, outlined for done or last seen.
struct RunTag: View {
    let text: String
    let lit: Bool
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let px = theme.stroke(.hairline) * 2
        Text(text.uppercased()).font(theme.font(.micro)).tracking(1)
            .foregroundStyle(theme.color(lit ? .background : .textSecondary, scheme))
            .padding(.horizontal, theme.spacing(.standard)).padding(.vertical, theme.spacing(.compact) / 2)
            .background(PixelRect(step: px).fill(lit ? theme.color(.accent, scheme) : Color.clear))
            .overlay(PixelRect(step: px).strokeBorder(theme.color(lit ? .accent : .separator, scheme), lineWidth: theme.stroke(.hairline)))
    }
}

/// Small lit tags that wrap onto new lines, set flush right in the latest-task card.
struct FlowTags: View {
    let tags: [String]
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // At most a handful of types: rows of three keep them readable.
        VStack(alignment: .trailing, spacing: theme.spacing(.compact)) {
            ForEach(Array(stride(from: 0, to: tags.count, by: 3)), id: \.self) { start in
                HStack(spacing: theme.spacing(.compact)) {
                    ForEach(tags[start..<min(start + 3, tags.count)], id: \.self) { tag in
                        Text(tag).font(theme.font(.micro)).foregroundStyle(theme.color(.background, scheme))
                            .padding(.horizontal, theme.spacing(.compact) * 1.5).padding(.vertical, theme.spacing(.compact) / 2)
                            .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.accent, scheme)))
                    }
                }
            }
        }
    }
}
