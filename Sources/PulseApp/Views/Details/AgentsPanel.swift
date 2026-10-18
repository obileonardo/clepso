import DesignSystem
import Domain
import SwiftUI

/// Agents per task (increment 1.9; cards after the founder's review of 18 Oct 2026) on the Session page: the 30-day
/// figures as cards, the latest task as a card of its own, and the recent tasks as a table. Counts and types only;
/// when the hooks aren't installed, what turning them on would do and where.
struct AgentsPanel: View {
    let summary: AgentsSummary?
    let now: Date
    let zone: TimeZone
    let locale: Locale
    let openProviders: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// 1.14: content only; the page's section supplies the name and the line.
    var body: some View {
        if let summary {
            if let latest = summary.latest {
                VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                    totals(summary)
                    latestCard(latest)
                    if summary.recent.count > 1 { recent(summary) }
                }
            } else {
                Text(Copy.Agents.noTasks).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    /// The newest task: its count large, running or done in words, its types as tags and how many have finished.
    func latestCard(_ task: AgentsSummary.Task) -> some View {
        HStack(alignment: .top, spacing: theme.spacing(.spacious)) {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                Text(Copy.Agents.latest).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
                HStack(alignment: .center, spacing: theme.spacing(.standard) + theme.spacing(.compact)) {
                    Text((task.agents == 0 ? Copy.Agents.none : Copy.Agents.count(task.agents)).uppercased()).font(theme.font(.metricHero))
                        .foregroundStyle(theme.color(.textPrimary, scheme)).lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.vertical, -theme.spacing(.compact))
                    RunTag(running: task.running)
                }
                Text(when(task)).font(theme.font(.supporting)).monospacedDigit().foregroundStyle(theme.color(.textSecondary, scheme))
            }
            Spacer(minLength: theme.spacing(.spacious))
            if task.agents > 0 {
                VStack(alignment: .trailing, spacing: theme.spacing(.standard)) {
                    FlowTags(tags: task.byType.map { "\($0.name.uppercased()) \($0.count)" })
                    HStack(spacing: theme.spacing(.standard)) {
                        Text(Copy.Agents.finished(task.finished, of: task.agents)).font(theme.font(.supporting)).monospacedDigit()
                            .foregroundStyle(theme.color(.textSecondary, scheme))
                        PixelBar(fraction: Double(task.finished) / Double(max(1, task.agents)), role: .accent, pattern: .solid,
                                 segments: min(max(task.agents, 4), 12))
                            .frame(width: AgentsMetrics.finishedBar)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pageCard(task.running ? .accent : .separator)
        .accessibilityElement(children: .combine)
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
                let types = task.byType.map { "\($0.name) \($0.count)" }.joined(separator: " · ")
                row(Text(Formatting.clock(task.startedAt, zone: zone, locale: locale)),
                    agents: Double(task.agents) / Double(top),
                    count: Text("\(task.agents)"),
                    types: Text(types.isEmpty ? Copy.Agents.none : types),
                    duration: Text(task.running ? Copy.Agents.running : duration(task) ?? "—"),
                    header: false, running: task.running, empty: task.agents == 0)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Formatting.clock(task.startedAt, zone: zone, locale: locale) + ": " + line(task))
            }
        }
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
        guard !task.running, let took = duration(task) else { return start }
        return "\(start) · \(took)"
    }

    func line(_ task: AgentsSummary.Task) -> String {
        let count = task.agents == 0 ? Copy.Agents.none : Copy.Agents.count(task.agents)
        let types = task.byType.map { "\($0.name) \($0.count)" }.joined(separator: ", ")
        let took = task.running ? Copy.Agents.running : duration(task)
        return [count, types.isEmpty ? nil : types, took].compactMap { $0 }.joined(separator: " · ")
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
}

/// Running or done, in words and shape (never colour alone): running is a lit tag, done an outlined one.
struct RunTag: View {
    let running: Bool
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let px = theme.stroke(.hairline) * 2
        Text((running ? Copy.Agents.running : Copy.Agents.done).uppercased()).font(theme.font(.micro)).tracking(1)
            .foregroundStyle(theme.color(running ? .background : .textSecondary, scheme))
            .padding(.horizontal, theme.spacing(.standard)).padding(.vertical, theme.spacing(.compact) / 2)
            .background(PixelRect(step: px).fill(running ? theme.color(.accent, scheme) : Color.clear))
            .overlay(PixelRect(step: px).strokeBorder(theme.color(running ? .accent : .separator, scheme), lineWidth: theme.stroke(.hairline)))
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
