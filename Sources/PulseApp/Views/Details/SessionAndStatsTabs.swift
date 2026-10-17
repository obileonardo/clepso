import ClaudeCodeAdapter
import DesignSystem
import Domain
import SwiftUI

/// The newest session in full, then recent sessions grouped by main model.
struct SessionTab: View {
    let snapshot: OverviewSnapshot
    let zone: TimeZone
    let locale: Locale
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            if let session = snapshot.provider?.sessions.first {
                current(session)
                if let groups = snapshot.provider?.models, !groups.isEmpty { byModel(groups) }
            } else {
                Text(Copy.Empty.noSessions).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
        }
    }

    func current(_ s: SessionDetail) -> some View {
        PixelPanel {
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                HStack(alignment: .firstTextBaseline) {
                    Text((s.modelName ?? Copy.Details.unknownModel).uppercased()).font(theme.font(.title))
                        .foregroundStyle(theme.color(.background, scheme))
                        .padding(.horizontal, theme.spacing(.standard)).padding(.vertical, theme.spacing(.compact))
                        .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.accent, scheme)))
                    DemoTag()
                    Spacer()
                    if let seen = s.lastSeen {
                        Text(Formatting.age(of: seen, now: snapshot.now, zone: zone, locale: locale).uppercased())
                            .font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                    }
                }
                if let pct = s.contextPct {
                    VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                        HStack {
                            Text(Copy.Details.context).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                            Spacer()
                            Text(Formatting.percent(pct)).font(theme.font(.label).weight(.semibold)).foregroundStyle(theme.color(.textPrimary, scheme))
                        }
                        PixelBar(fraction: NSDecimalNumber(decimal: pct).doubleValue / 100, role: .accent, pattern: .solid, segments: 40)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: theme.spacing(.spacious), verticalSpacing: theme.spacing(.spacious)) {
                    GridRow {
                        PixelStat(s.tokensIn.map(Formatting.compact) ?? "—", Copy.Details.tokensIn)
                        PixelStat(s.tokensOut.map(Formatting.compact) ?? "—", Copy.Details.tokensOut)
                        PixelStat(s.costUSD.map(money) ?? "—", Copy.Details.costEstimate)
                        PixelStat(s.cacheHitPct.map(Formatting.percent) ?? "—", Copy.Details.cacheHits)
                    }
                    GridRow {
                        PixelStat(s.apiMs.map { Formatting.duration(milliseconds: $0) } ?? "—", Copy.Details.apiTime)
                        PixelStat(s.wallMs.map { Formatting.duration(milliseconds: $0) } ?? "—", Copy.Details.wallTime)
                        PixelStat(lines(s), Copy.Details.lines)
                        PixelStat(cache(s), Copy.Details.cacheState)
                    }
                }
                Text(Copy.Details.costNote).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func byModel(_ groups: [ModelGroup]) -> some View {
        PixelPanel {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                Text(Copy.Details.byModel).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                ForEach(groups) { g in
                    VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                        HStack {
                            Text(g.name.uppercased()).font(theme.font(.micro)).foregroundStyle(theme.color(.textPrimary, scheme))
                            Spacer()
                            Text(Copy.Details.groupLine(sessions: g.sessions, tokens: Formatting.compact(g.tokens), cost: money(g.costUSD),
                                                        share: Int((g.share * 100).rounded())))
                                .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                        }
                        PixelBar(fraction: g.share, role: .accent, pattern: .solid, segments: 40)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(Copy.Details.byModelNote).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func money(_ d: Decimal) -> String { d.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) }
    func lines(_ s: SessionDetail) -> String {
        guard s.linesAdded != nil || s.linesRemoved != nil else { return "—" }
        return "+\(Formatting.compact(s.linesAdded ?? 0)) −\(Formatting.compact(s.linesRemoved ?? 0))"
    }
    func cache(_ s: SessionDetail) -> String {
        let warm = s.cacheWarm.map { $0 ? Copy.Details.warm : Copy.Details.cold } ?? "—"
        guard let requests = s.cacheRequests else { return warm }
        return "\(warm) · \(requests) req · \(s.cacheMisses ?? 0) miss"
    }
}

/// Stats like Claude Code's /stats, from its own statistics file, after the user agrees.
struct StatsTab: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            if !model.statsEnabled {
                explainer
            } else {
                switch model.stats {
                case .failure(let problem)?:
                    Text(problem == .missing ? Copy.Stats.missing : Copy.Stats.unreadable).font(theme.font(.label))
                        .foregroundStyle(theme.color(.textSecondary, scheme))
                case nil:
                    ProgressView()
                case .success?:
                    if let summary = model.statsSummary(model.statsRange) { content(summary) }
                }
            }
        }
        .task { model.loadStats() }
    }

    var explainer: some View {
        PixelPanel {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                Text(Copy.Stats.explainerTitle).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                Text(Copy.Stats.explainerBody).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Button(Copy.Stats.enable) { Task { await model.setStatsEnabled(true) } }.buttonStyle(PixelButtonStyle(prominent: true))
            }
        }
    }

    @ViewBuilder func content(_ s: StatsSummary) -> some View {
        HStack {
            PixelTabs([(AppModel.StatsPage.overview, Copy.Stats.overview), (.models, Copy.Stats.models)], selection: $model.statsPage)
            Spacer()
            PixelTabs([(StatsSummary.Range.allTime, Copy.Stats.allTime), (.last30, Copy.Stats.last30), (.last7, Copy.Stats.last7)],
                      selection: $model.statsRange)
        }
        switch model.statsPage {
        case .overview: overview(s)
        case .models: models(s)
        }
        if let through = s.computedThrough {
            Text(Copy.Stats.through(dayLabel(through))).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func overview(_ s: StatsSummary) -> some View {
        PixelPanel {
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                PixelHeatmap(weeks: weeks(s), months: months(s), summary: Copy.Stats.heatmapSummary(active: s.activeDays, of: s.dayCount))
                Grid(alignment: .leading, horizontalSpacing: theme.spacing(.spacious), verticalSpacing: theme.spacing(.spacious)) {
                    GridRow {
                        PixelStat(s.favorite?.name ?? "—", Copy.Stats.favorite, large: true)
                        PixelStat(Formatting.compact(s.totalTokens), Copy.Stats.totalTokens, large: true)
                        PixelStat("\(s.sessions)", Copy.Stats.sessions, large: true)
                        PixelStat(s.longestSessionMs.map { Formatting.duration(milliseconds: $0) } ?? "—", Copy.Stats.longestSession, large: true)
                    }
                    GridRow {
                        PixelStat("\(s.activeDays)/\(s.dayCount)", Copy.Stats.activeDays, large: true)
                        PixelStat("\(s.currentStreak)", Copy.Stats.currentStreak, large: true)
                        PixelStat("\(s.longestStreak)", Copy.Stats.longestStreak, large: true)
                        PixelStat(s.mostActiveDay.map(dayLabel) ?? "—", Copy.Stats.mostActive, large: true)
                    }
                }
            }
        }
    }

    func models(_ s: StatsSummary) -> some View {
        let palette: [ColorToken] = [.accent, .statusAttention, .statusBlocked, .textPrimary, .statusStale, .statusUnknown]
        let roles = Dictionary(uniqueKeysWithValues: s.models.enumerated().map { ($0.element.model, palette[$0.offset % palette.count]) })
        let days = s.dailyTokens
        let series = s.models.map { m in
            ChartSeries(id: m.model, points: days.enumerated().map { (x: Double($0.offset), y: Double($0.element.byModel[m.model] ?? 0)) },
                        role: roles[m.model] ?? .accent)
        }
        let maxY = days.flatMap { $0.byModel.values }.max().map(Double.init) ?? 1
        return PixelPanel {
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                Text(Copy.Stats.tokensPerDay).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                PixelLineChart(series: series, xRange: 0...Double(max(days.count - 1, 1)), yRange: 0...max(maxY, 1),
                               summary: Copy.Stats.chartSummary(days: days.count, models: s.models.count))
                    .frame(height: DetailsMetrics.chartHeight * 1.3)
                ForEach(s.models) { m in
                    VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                        HStack {
                            Rectangle().fill(theme.color(roles[m.model] ?? .accent, scheme)).frame(width: theme.spacing(.standard), height: theme.spacing(.standard))
                                .accessibilityHidden(true)
                            Text(m.name.uppercased()).font(theme.font(.micro)).foregroundStyle(theme.color(.textPrimary, scheme))
                            Spacer()
                            Text(String(format: "%.1f%%", m.share * 100)).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                        }
                        if let t = m.totals, s.range == .allTime {
                            Text(Copy.Stats.modelBreakdown(input: Formatting.compact(t.input), output: Formatting.compact(t.output),
                                                           read: Formatting.compact(t.cacheRead), write: Formatting.compact(t.cacheWrite)))
                                .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Columns of weeks (Monday first) ending this week; nil outside the range.
    func weeks(_ s: StatsSummary) -> [[Int?]] {
        guard let today = StatsSummary.Day.date(s.today) else { return [] }
        let calendar = StatsSummary.Day.calendar
        let weekday = (calendar.component(.weekday, from: today) + 5) % 7          // Monday = 0
        let first = StatsSummary.Day.adding(-(s.dayCount - 1), to: s.today)
        let columns = max(1, Int(ceil(Double(s.dayCount + (6 - weekday)) / 7)))
        let lastSunday = StatsSummary.Day.adding(6 - weekday, to: s.today)
        return (0..<columns).map { c in
            (0..<7).map { d in
                let day = StatsSummary.Day.adding(-((columns - 1 - c) * 7 + (6 - d)), to: lastSunday)
                guard day >= first, day <= s.today else { return nil }
                return s.heatmap[day] ?? 0
            }
        }
    }

    /// The column where each month's first day falls, labelled with the month's short name.
    func months(_ s: StatsSummary) -> [(column: Int, label: String)] {
        let grid = weeks(s), columns = grid.count
        let weekday = (StatsSummary.Day.calendar.component(.weekday, from: StatsSummary.Day.date(s.today) ?? .distantPast) + 5) % 7
        let lastSunday = StatsSummary.Day.adding(6 - weekday, to: s.today)
        var labels: [(Int, String)] = []
        for c in 0..<columns {
            let monday = StatsSummary.Day.adding(-((columns - 1 - c) * 7 + 6), to: lastSunday)
            let days = (0..<7).map { StatsSummary.Day.adding($0, to: monday) }
            if let first = days.first(where: { $0.hasSuffix("-01") }) ?? (c == 0 ? days.first : nil), let date = StatsSummary.Day.date(first) {
                labels.append((c, date.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).month(.abbreviated))))
            }
        }
        // Drop a label that would collide with the next one (a month starting in the second column).
        return labels.enumerated().filter { i, l in i + 1 >= labels.count || labels[i + 1].0 - l.0 >= 3 }.map(\.element)
    }

    func dayLabel(_ day: String) -> String {
        guard let date = StatsSummary.Day.date(day) else { return day }
        return date.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).month(.abbreviated).day())
    }
}
