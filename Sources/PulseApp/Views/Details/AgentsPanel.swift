import DesignSystem
import Domain
import SwiftUI

/// Agents per task (increment 1.9) on the Session page: the latest task, 30-day totals and recent tasks. Counts and
/// types only; when the hooks aren't installed, what turning them on would do and where.
struct AgentsPanel: View {
    let summary: AgentsSummary?
    let now: Date
    let zone: TimeZone
    let locale: Locale
    let openProviders: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        PixelPanel {
            if let summary {
                VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                    VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                        Text(Copy.Agents.title).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme)).accessibilityAddTraits(.isHeader)
                        Text(Copy.Agents.taskLabel).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    }
                    if let latest = summary.latest {
                        HStack(alignment: .top, spacing: theme.spacing(.spacious) * 1.5) {
                            latestBlock(latest).frame(width: DetailsMetrics.sideColumn, alignment: .topLeading)
                            totals(summary).frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        recent(summary)
                    } else {
                        Text(Copy.Agents.noTasks).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                    Text(Copy.Agents.offTitle).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                    Text(Copy.Agents.offBody).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(Copy.Agents.openSettings, action: openProviders).buttonStyle(PixelButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func latestBlock(_ task: AgentsSummary.Task) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(Copy.Agents.latest).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            Text((task.agents == 0 ? Copy.Agents.none : Copy.Agents.count(task.agents)).uppercased()).font(theme.font(.metricMedium))
                .foregroundStyle(theme.color(.textPrimary, scheme))
            Text(when(task)).font(theme.font(.supporting)).foregroundStyle(theme.color(task.running ? .accent : .textSecondary, scheme))
            if !task.byType.isEmpty {
                FlowTags(tags: task.byType.map { "\($0.name.uppercased()) \($0.count)" })
                if task.agents > 0 {
                    Text(Copy.Agents.finished(task.finished, of: task.agents)).font(theme.font(.supporting))
                        .foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    func totals(_ s: AgentsSummary) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(Copy.Agents.month).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            Grid(alignment: .topLeading, horizontalSpacing: theme.spacing(.spacious), verticalSpacing: theme.spacing(.spacious)) {
                GridRow {
                    PixelStat("\(s.tasks)", Copy.Agents.tasks, large: true)
                    PixelStat(s.tasks > 0 ? "\(Int((Double(s.tasksWithAgents) / Double(s.tasks) * 100).rounded()))%" : "—", Copy.Agents.withAgents, large: true)
                }
                GridRow {
                    PixelStat(String(format: "%.1f", s.averagePerTask), Copy.Agents.average, large: true)
                    PixelStat("\(s.mostInOneTask)", Copy.Agents.most, large: true)
                }
            }
        }
    }

    func recent(_ s: AgentsSummary) -> some View {
        let top = max(1, s.recent.map(\.agents).max() ?? 1)
        return VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(Copy.Agents.recent).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            ForEach(s.recent) { task in
                HStack(spacing: theme.spacing(.spacious)) {
                    Text(Formatting.clock(task.startedAt, zone: zone, locale: locale)).font(theme.font(.label)).monospacedDigit()
                        .foregroundStyle(theme.color(.textPrimary, scheme)).frame(width: DetailsMetrics.sideColumn * 0.35, alignment: .leading)
                    PixelBar(fraction: Double(task.agents) / Double(top), role: .accent, pattern: .solid, segments: 16)
                        .frame(width: DetailsMetrics.sideColumn * 0.8)
                    Text(line(task)).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    func when(_ task: AgentsSummary.Task) -> String {
        let start = Formatting.clock(task.startedAt, zone: zone, locale: locale)
        if task.running { return "\(Copy.Agents.running) · \(start)" }
        guard let end = task.endedAt else { return start }
        return "\(Formatting.duration(milliseconds: Int64(end.timeIntervalSince(task.startedAt) * 1000))) · \(start)"
    }

    func line(_ task: AgentsSummary.Task) -> String {
        let count = task.agents == 0 ? Copy.Agents.none : Copy.Agents.count(task.agents)
        let types = task.byType.map { "\($0.name) \($0.count)" }.joined(separator: ", ")
        let duration = task.running ? Copy.Agents.running
            : task.endedAt.map { Formatting.duration(milliseconds: Int64($0.timeIntervalSince(task.startedAt) * 1000)) }
        return [count, types.isEmpty ? nil : types, duration].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Small lit tags that wrap onto new lines.
struct FlowTags: View {
    let tags: [String]
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // At most a handful of types: rows of three keep them readable in the side column.
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
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
