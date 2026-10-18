import ClaudeCodeAdapter
import DesignSystem
import SwiftUI

/// Stats overview (increment 1.8e): a layout per range, so each fills the window. All time is a GitHub-style year
/// with a year switcher; 30 days a month calendar; 7 days one column per day.
struct OverviewSection: View {
    @Bindable var model: AppModel
    let summary: StatsSummary
    let file: ClaudeCodeStats
    /// The content width, measured, so the calendars fill it instead of overflowing it.
    @State private var width: CGFloat = DetailsMetrics.minWidth - DetailsMetrics.sidebarWidth
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// Room inside a panel: its padding and frame on both sides.
    var inner: CGFloat { max(0, width - (theme.spacing(.windowPadding) + theme.spacing(.standard)) * 2) }

    @State private var selectedDay: String?

    /// 1.14: Account's structure. Activity (the calendar for the range, and a chosen day under it), the range at a
    /// glance, when you work, and tokens by kind.
    var body: some View {
        PageColumn(fitting: { contentWidth in
            PageSection(Copy.OverviewPage.activity, activityLine) {
                VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                    switch summary.range {
                    case .allTime: yearView(contentWidth)
                    case .last30: monthView(contentWidth)
                    case .last7: weekView
                    }
                    if let day = selectedDay { dayFacts(day) }
                }
            }
            if summary.range != .allTime {
                PageSection(Copy.OverviewPage.tokensTitle, Copy.OverviewPage.tokensSub) {
                    StackedModelChart(summary: summary, from: StatsSummary.Day.adding(summary.range == .last30 ? -29 : -6, to: summary.today),
                                      to: summary.today, stacked: false, height: DetailsMetrics.chartHeight)
                }
            }
            PageSection(Copy.OverviewPage.glance, rangeName) { glance }
            PageSection(Copy.OverviewPage.hoursTitle, Copy.OverviewPage.hoursSub) { HourChart(counts: summary.hourCounts, showsTitle: false) }
            PageSection(Copy.OverviewPage.kindsTitle, Copy.Stats.allTimeNote) { tokenBreakdown }
        })
    }

    var activityLine: String {
        switch summary.range {
        case .allTime: Copy.OverviewPage.activityYear
        case .last30: Copy.Stats.last30
        case .last7: Copy.Stats.last7
        }
    }

    /// The range's headline numbers, in two columns of fact rows.
    var glance: some View {
        let rows: [(String, String)] = [
            (Copy.Stats.favorite, summary.favorite?.name ?? "—"), (Copy.Stats.totalTokens, Formatting.compact(summary.totalTokens)),
            (Copy.Stats.sessions, "\(summary.sessions)"), (Copy.Stats.longestSession, summary.longestSessionMs.map { Formatting.duration(milliseconds: $0) } ?? "—"),
            (Copy.Stats.activeDays, "\(summary.activeDays)/\(summary.dayCount)"), (Copy.Stats.currentStreak, Copy.Card.days(summary.currentStreak)),
            (Copy.Stats.longestStreak, Copy.Card.days(summary.longestStreak)), (Copy.Stats.mostActive, summary.mostActiveDay.map(StatsFormat.day) ?? "—"),
        ]
        return Grid(alignment: .leading, horizontalSpacing: theme.spacing(.spacious) * 1.5, verticalSpacing: 0) {
            ForEach(0..<4, id: \.self) { r in
                GridRow {
                    FactRow(label: rows[r * 2].0, value: rows[r * 2].1)
                    FactRow(label: rows[r * 2 + 1].0, value: rows[r * 2 + 1].1)
                }
            }
        }
    }

    /// The chosen day, as fact rows under the calendar.
    func dayFacts(_ day: String) -> some View {
        let record = file.days.first { $0.date == day }
        let tokens = file.dailyTokens.first { $0.date == day }?.byModel ?? [:]
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((StatsFormat.weekday(day) + " " + StatsFormat.day(day)).uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                Spacer()
                Button(Copy.OverviewPage.clear) { selectedDay = nil }.buttonStyle(PixelButtonStyle())
            }
            .padding(.bottom, theme.spacing(.standard))
            FactRow(label: Copy.OverviewPage.messages, value: "\(record?.messages ?? 0)")
            FactRow(label: Copy.Stats.sessions, value: "\(record?.sessions ?? 0)")
            FactRow(label: Copy.OverviewPage.toolCalls, value: "\(record?.toolCalls ?? 0)")
            ForEach(tokens.sorted { $0.value > $1.value }, id: \.key) { id, n in
                FactRow(label: StatsReader.displayName(id), value: Formatting.compact(n) + " tokens")
            }
        }
    }

    var rangeName: String {
        switch summary.range {
        case .allTime: Copy.Stats.allTime
        case .last30: Copy.Stats.last30
        case .last7: Copy.Stats.last7
        }
    }

    // MARK: - All time: one calendar year

    func yearView(_ contentWidth: CGFloat) -> some View {
        let years = StatsCalendar.years(firstDay: file.firstSessionDate, today: summary.today)
        let year = model.statsYear ?? years.last ?? Int(summary.today.prefix(4)) ?? 0
        let all = StatsSummary.make(file, range: .allTime, today: summary.today)
        let grid = StatsCalendar.year(year, stats: file, levels: all.heatmap, today: summary.today, firstDay: file.firstSessionDate)
        let active = grid.weeks.flatMap { $0 }.compactMap { $0 }.filter { if case .level(let l) = $0.state { l > 0 } else { false } }.count
        return VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            HStack(spacing: theme.spacing(.standard)) {
                Text(Copy.Stats.activityIn(active, year)).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                Spacer()
                Button { model.statsYear = year - 1 } label: { PixelIcon(symbol: "chevron.left") }
                    .buttonStyle(PixelButtonStyle()).disabled(!years.contains(year - 1)).accessibilityLabel(Copy.Stats.previousYear)
                Text(String(year)).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme)).monospacedDigit()
                Button { model.statsYear = year + 1 } label: { PixelIcon(symbol: "chevron.right") }
                    .buttonStyle(PixelButtonStyle()).disabled(!years.contains(year + 1)).accessibilityLabel(Copy.Stats.nextYear)
            }
            CalendarGridView(grid: grid, cell: CalendarGridView.cell(fitting: contentWidth, weeks: grid.weeks.count, theme: theme), showDayNumbers: false,
                             selected: selectedDay, onSelect: { selectedDay = $0 })
            CalendarLegend()
        }
    }

    // MARK: - 30 days: a month calendar with large cells

    func monthView(_ contentWidth: CGFloat) -> some View {
        let grid = StatsCalendar.recent(30, stats: file, levels: summary.heatmap, today: summary.today, firstDay: file.firstSessionDate)
        return VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            CalendarGridView(grid: grid, cell: monthCell(contentWidth), showDayNumbers: true, transposed: true, selected: selectedDay, onSelect: { selectedDay = $0 })
            CalendarLegend()
        }
    }

    /// Day squares sized so the calendar takes about half the width, never smaller than two lines of figures.
    func monthCell(_ contentWidth: CGFloat) -> CGFloat {
        let fit = contentWidth / (7 + 6 * CalendarGridView.gapRatio)
        return min(max(fit, theme.spacing(.spacious) * 2), theme.spacing(.spacious) * 3.5)
    }

    // MARK: - 7 days: one column per day

    var weekView: some View {
        let days = (0..<7).map { StatsSummary.Day.adding($0 - 6, to: summary.today) }
        let byDate = Dictionary(file.days.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let tokens = Dictionary(file.dailyTokens.map { ($0.date, $0.byModel.values.reduce(0, +)) }, uniquingKeysWith: { a, _ in a })
        let maxMessages = max(1, days.compactMap { byDate[$0]?.messages }.max() ?? 1)
        return Group {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                HStack(alignment: .bottom, spacing: theme.spacing(.standard)) {
                    ForEach(days, id: \.self) { day in
                        let d = byDate[day]
                        let pending = day > (file.computedThrough ?? day)
                        VStack(spacing: theme.spacing(.compact)) {
                            Text(pending ? "…" : Formatting.compact(Int64(d?.messages ?? 0))).font(theme.font(.label)).monospacedDigit()
                                .foregroundStyle(theme.color(.textPrimary, scheme))
                            GeometryReader { geo in
                                VStack {
                                    Spacer(minLength: 0)
                                    Rectangle().fill(theme.color(.accent, scheme).opacity(pending ? 0.25 : 1))
                                        .frame(height: max(theme.stroke(.hairline) * 2, geo.size.height * CGFloat(d?.messages ?? 0) / CGFloat(maxMessages)))
                                }
                            }
                            .frame(height: DetailsMetrics.chartHeight)
                            Text(StatsFormat.weekday(day).uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                            Text(StatsFormat.day(day)).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                            Text(pending ? Copy.Stats.pending : Copy.Stats.dayDetail(sessions: d?.sessions ?? 0, tokens: Formatting.compact(tokens[day] ?? 0)))
                                .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme)).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
                Text(Copy.Stats.messagesPerDay).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
        }
    }

    // MARK: - Shared

    var tokenBreakdown: some View {
        let totals = file.models
        let input = totals.map(\.input).reduce(0, +), output = totals.map(\.output).reduce(0, +)
        let read = totals.map(\.cacheRead).reduce(0, +), write = totals.map(\.cacheWrite).reduce(0, +)
        let all = max(1, input + output + read + write)
        return VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            ForEach([(Copy.Stats.cacheRead, read), (Copy.Stats.cacheWrite, write), (Copy.Stats.output, output), (Copy.Stats.input, input)], id: \.0) { name, n in
                VStack(alignment: .leading, spacing: theme.spacing(.compact) / 2) {
                    HStack {
                        Text(name).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                        Spacer()
                        Text(Formatting.compact(n)).font(theme.font(.label)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme))
                    }
                    PixelBar(fraction: Double(n) / Double(all), role: .accent, pattern: .solid, segments: 30)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A calendar of squares. Sunday on top like GitHub (or as rows of weeks when transposed, for the month view).
/// Each square has a tooltip and a VoiceOver label with its date and counts; "no data" days are outlines.
struct CalendarGridView: View {
    let grid: StatsCalendar.Grid
    let cell: CGFloat
    let showDayNumbers: Bool
    var transposed = false
    /// Steep's inspector (1.12): a day can be chosen to see it in full beside the calendar.
    var selected: String? = nil
    var onSelect: ((String) -> Void)? = nil
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    static let gapRatio: CGFloat = 0.16
    var gap: CGFloat { max(theme.stroke(.hairline) * 2, cell * Self.gapRatio) }
    /// The weekday labels' column (year view).
    var labelColumn: CGFloat { Self.labelColumn(theme) }
    static func labelColumn(_ theme: Theme) -> CGFloat { theme.spacing(.spacious) * 2 }

    /// The largest square that fits `weeks` columns and the label column in `width`, within readable bounds.
    /// The drawn width is the label column, a gap, and a cell and a gap per week, where the gap is `gapRatio` of a cell
    /// but never under two hairlines; both are counted, so a fitted year never runs past `width`.
    static func cell(fitting width: CGFloat, weeks: Int, theme: Theme) -> CGFloat {
        let w = CGFloat(max(1, weeks)), floorGap = theme.stroke(.hairline) * 2, room = width - labelColumn(theme)
        var fit = room / (w * (1 + gapRatio) + gapRatio)
        if fit * gapRatio < floorGap { fit = (room - floorGap * (w + 1)) / w }
        return min(max(fit, theme.spacing(.standard) - theme.stroke(.hairline)), theme.spacing(.spacious) * 1.6)
    }

    var body: some View {
        if transposed {
            VStack(alignment: .leading, spacing: gap) {
                HStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { d in
                        Text(Self.weekdays[d]).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme)).frame(width: cell)
                    }
                }
                ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: gap) { ForEach(0..<7, id: \.self) { d in square(week[d]) } }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: gap) {
                ZStack(alignment: .topLeading) {
                    Color.clear.frame(width: CGFloat(grid.weeks.count) * (cell + gap) + labelColumn, height: theme.spacing(.spacious))
                    ForEach(Array(grid.months.enumerated()), id: \.offset) { _, m in
                        Text(m.label.uppercased()).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                            .fixedSize().offset(x: labelColumn + gap + CGFloat(m.column) * (cell + gap))
                    }
                }
                HStack(alignment: .top, spacing: gap) {
                    VStack(alignment: .trailing, spacing: gap) {
                        ForEach(0..<7, id: \.self) { d in
                            Text(d % 2 == 1 ? Self.weekdays[d] : "").font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                                .frame(width: labelColumn, height: cell, alignment: .trailing).fixedSize()
                        }
                    }
                    ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: gap) { ForEach(0..<7, id: \.self) { d in square(week[d]) } }
                    }
                }
            }
        }
    }

    static let weekdays = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    @ViewBuilder func square(_ c: StatsCalendar.Cell?) -> some View {
        if let c {
            ZStack {
                switch c.state {
                case .noData:
                    Rectangle().strokeBorder(theme.color(.separator, scheme).opacity(0.6), lineWidth: theme.stroke(.hairline))
                case .level(let level):
                    Rectangle().fill(CalendarLegend.color(level, theme: theme, scheme: scheme))
                }
                if showDayNumbers {
                    VStack(spacing: 0) {
                        Text(String(c.date.suffix(2))).font(theme.font(.micro))
                        if case .level(let l) = c.state, l > 0 { Text(Formatting.compact(Int64(c.messages))).font(theme.font(.micro)).opacity(0.8) }
                    }
                    .foregroundStyle(theme.color(isBright(c) ? .background : .textPrimary, scheme))
                }
            }
            .frame(width: cell, height: cell)
            .overlay {
                if selected == c.date {
                    Rectangle().strokeBorder(theme.color(.textPrimary, scheme), lineWidth: max(theme.stroke(.hairline) * 2, cell * 0.12))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if case .level = c.state { onSelect?(c.date) } }
            .accessibilityAddTraits(onSelect == nil ? [] : .isButton)
            .help(tooltip(c))
            .accessibilityElement()
            .accessibilityLabel(tooltip(c))
        } else {
            Color.clear.frame(width: cell, height: cell).accessibilityHidden(true)
        }
    }

    func isBright(_ c: StatsCalendar.Cell) -> Bool { if case .level(let l) = c.state { l >= 3 } else { false } }

    func tooltip(_ c: StatsCalendar.Cell) -> String {
        switch c.state {
        case .noData: Copy.Stats.noDataDay(StatsFormat.day(c.date))
        case .level: Copy.Stats.dayTooltip(StatsFormat.day(c.date), messages: c.messages, sessions: c.sessions)
        }
    }
}

struct CalendarLegend: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    static func color(_ level: Int, theme: Theme, scheme: ColorScheme) -> Color {
        level == 0 ? theme.color(.surfaceMuted, scheme) : theme.color(.accent, scheme).opacity([0, 0.3, 0.55, 0.8, 1][min(level, 4)])
    }

    var body: some View {
        let size = theme.spacing(.standard) + theme.spacing(.compact)
        HStack(spacing: theme.spacing(.compact)) {
            Rectangle().strokeBorder(theme.color(.separator, scheme), lineWidth: theme.stroke(.hairline)).frame(width: size, height: size)
            Text(Copy.Stats.noData).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                .padding(.trailing, theme.spacing(.standard))
            Text(Copy.Stats.less).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            ForEach(0..<5, id: \.self) { Rectangle().fill(Self.color($0, theme: theme, scheme: scheme)).frame(width: size, height: size) }
            Text(Copy.Stats.more).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
        }
        .accessibilityHidden(true)
    }
}

/// Sessions started per hour of the day, from Claude Code's own counts, with a hover readout.
struct HourChart: View {
    let counts: [Int: Int]
    var showsTitle = true
    @State private var hover: Int?
    @State private var width: CGFloat = 0
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let top = max(1, counts.values.max() ?? 1)
        let footer = theme.spacing(.spacious) * 1.2
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            if showsTitle { Text(Copy.Stats.hours).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme)) }
            Canvas { context, size in
                let plot = CGRect(x: 0, y: 0, width: size.width, height: size.height - footer)
                let slot = plot.width / 24
                let px = theme.stroke(.hairline) * 2
                for h in 0..<24 {
                    let n = counts[h] ?? 0
                    let x = CGFloat(h) * slot
                    if hover == h { context.fill(Path(CGRect(x: x, y: plot.minY, width: slot, height: plot.height)), with: .color(theme.color(.surfaceMuted, scheme))) }
                    let height = max(px / 2, plot.height * CGFloat(n) / CGFloat(top))
                    context.fill(Path(CGRect(x: x + slot * 0.14, y: plot.maxY - height, width: slot * 0.72, height: height)),
                                 with: .color(theme.color(.accent, scheme).opacity(n == 0 ? 0.2 : 1)))
                    if h % 6 == 0 {
                        ChartLabel.draw(context, Text(String(format: "%02d", h)).font(theme.font(.micro)).foregroundColor(theme.color(.textSecondary, scheme)),
                                        centeredAt: x + slot / 2, top: plot.maxY + px * 3, width: size.width)
                    }
                }
            }
            .frame(height: DetailsMetrics.chartHeight * 0.8)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onContinuousHover { phase in
                if case .active(let p) = phase, width > 0 { hover = min(23, max(0, Int(p.x / (width / 24)))) } else { hover = nil }
            }
            .accessibilityElement()
            .accessibilityLabel(Copy.Stats.hoursSummary(peak: counts.max { $0.value < $1.value }?.key ?? 0))
            Text(hover.map { Copy.Stats.hourTooltip($0, counts[$0] ?? 0) } ?? Copy.Stats.hoverHint).font(theme.font(.label)).monospacedDigit()
                .foregroundStyle(theme.color(hover == nil ? .textSecondary : .textPrimary, scheme)).lineLimit(1)
                .accessibilityHidden(hover == nil)
        }
    }
}

/// A year-style calendar that sizes its squares to the width it is given (Home, Account).
struct FittedCalendar: View {
    let grid: StatsCalendar.Grid
    @State private var width: CGFloat = 600
    @Environment(\.theme) private var theme

    var body: some View {
        CalendarGridView(grid: grid, cell: CalendarGridView.cell(fitting: width, weeks: grid.weeks.count, theme: theme), showDayNumbers: false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
