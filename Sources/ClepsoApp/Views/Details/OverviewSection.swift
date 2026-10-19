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
            if model.codexEnabled, let days = model.codexDays {
                if let codex = CodexStats.make(days, range: summary.range, today: summary.today) {
                    PageSection(Copy.OverviewPage.codexTitle, Copy.OverviewPage.codexSub) { codexView(codex) }
                }
            } else if model.codexEnabled {
                PageSection(Copy.OverviewPage.codexTitle, Copy.OverviewPage.codexSub) {
                    Text(Copy.OverviewPage.codexReading).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
        })
    }

    /// Increment 3.4b: Codex's figures for the same range, then its tokens per day by model.
    func codexView(_ codex: CodexStats) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            StatCardRow {
                StatCard(caption: Copy.Stats.totalTokens, value: Formatting.compact(codex.total), detail: rangeName)
                StatCard(caption: Copy.OverviewPage.codexOutput, value: Formatting.compact(codex.output), detail: Copy.OverviewPage.codexOutputDetail)
                StatCard(caption: Copy.Stats.activeDays, value: "\(codex.activeDays)/\(codex.dayCount)", detail: rangeName)
                StatCard(caption: Copy.OverviewPage.codexTop, value: codex.topModel ?? "—",
                         detail: codex.topModel == nil ? rangeName : Copy.OverviewPage.codexShare(codex.topShare))
            }
            StackedModelChart(series: codex.series, from: codex.from, to: codex.to, stacked: true, height: DetailsMetrics.chartHeight)
        }
    }

    var activityLine: String {
        switch summary.range {
        case .allTime: Copy.OverviewPage.activityYear
        case .last30: Copy.Stats.last30
        case .last7: Copy.Stats.last7
        }
    }

    /// The range's headline numbers as four cards (founder review, 18 Oct 2026); each card's context line carries
    /// the fact that pairs with it, so all eight are still shown.
    var glance: some View {
        let fact = Copy.OverviewPage.fact
        return StatCardRow {
            StatCard(caption: Copy.Stats.totalTokens, value: Formatting.compact(summary.totalTokens),
                     detail: fact(Copy.Stats.favorite, summary.favorite?.name ?? "—"))
            StatCard(caption: Copy.Stats.sessions, value: "\(summary.sessions)",
                     detail: fact(Copy.Stats.longestSession, summary.longestSessionMs.map { Formatting.duration(milliseconds: $0) } ?? "—"))
            StatCard(caption: Copy.Stats.activeDays, value: "\(summary.activeDays)/\(summary.dayCount)",
                     detail: fact(Copy.Stats.mostActive, summary.mostActiveDay.map(StatsFormat.day) ?? "—"))
            StatCard(caption: Copy.Stats.currentStreak, value: Copy.Card.days(summary.currentStreak),
                     detail: fact(Copy.Stats.longestStreak, Copy.Card.days(summary.longestStreak)))
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
        let year = StatsCalendar.shownYear(model.statsYear, of: years)
        let all = StatsSummary.make(file, range: .allTime, today: summary.today)
        let grid = StatsCalendar.year(year, stats: file, levels: all.heatmap, today: summary.today, firstDay: file.firstSessionDate)
        let cell = CalendarGridView.cell(fitting: contentWidth, weeks: grid.weeks.count, theme: theme)
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
            CalendarGridView(grid: grid, cell: cell, showDayNumbers: false, selected: selectedDay, onSelect: { selectedDay = $0 })
            CalendarLegend(size: cell)
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
        return PixelDensity.tile(fitting: min(max(fit, theme.spacing(.spacious) * 2), theme.spacing(.spacious) * 3.5), px: theme.stroke(.hairline) * 2)
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
    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// GitHub's proportions: a 10-point day has a 3-point gap.
    static let gapRatio: CGFloat = 0.25
    var gap: CGFloat { Self.gap(cell, theme) }
    /// Whole points, so every square starts on a device pixel at 1× and 2×.
    static func gap(_ cell: CGFloat, _ theme: Theme) -> CGFloat { max(theme.stroke(.hairline) * 2, (cell * gapRatio).rounded()) }
    /// The weekday labels' column (year view).
    var labelColumn: CGFloat { Self.labelColumn(theme) }
    static func labelColumn(_ theme: Theme) -> CGFloat { theme.spacing(.spacious) * 2 }

    /// The largest square that fits `weeks` columns and the label column in `width`, up to a readable maximum. A square
    /// is a pixel tile (`PixelDensity.tile`): an odd number of whole 2 pt pixels (10, 14, 18 … points), or of hairline
    /// pixels below 10 points. The drawn width is the label column, a gap, and a cell and a gap per week (`gap`), so a
    /// fitted year never runs past `width`; the smallest tile (5 points) is the floor.
    static func cell(fitting width: CGFloat, weeks: Int, theme: Theme) -> CGFloat {
        let w = CGFloat(max(1, weeks)), px = theme.stroke(.hairline) * 2
        var cell = PixelDensity.tile(fitting: theme.spacing(.spacious) * 1.6, px: px)
        while cell > px * 2.5, labelColumn(theme) + gap(cell, theme) + w * (cell + gap(cell, theme)) > width {
            cell = PixelDensity.tile(fitting: cell - 1, px: px)
        }
        return cell
    }

    /// Item 9: a calendar a day can be chosen in takes keyboard focus as one control (not 365 Tab stops): ← → ↑ ↓
    /// move the chosen day along the grid as drawn (a week sideways in the year view, a day sideways in the month
    /// view), from the latest day on the first press; Return or Space chooses the latest day when none is chosen.
    var body: some View {
        if let onSelect {
            squares
                .focusable()
                .focused($focused)
                .focusEffectDisabled()                   // the pixel ring instead of the system's rounded one
                .pixelFocusRing(focused)
                .onMoveCommand { direction in
                    let (days, weeks): (Int, Int) = switch direction {
                    case .left: transposed ? (-1, 0) : (0, -1)
                    case .right: transposed ? (1, 0) : (0, 1)
                    case .up: transposed ? (0, -1) : (-1, 0)
                    case .down: transposed ? (0, 1) : (1, 0)
                    @unknown default: (0, 0)
                    }
                    if let day = grid.day(from: selected, days: days, weeks: weeks) { onSelect(day) }
                }
                .onKeyPress(keys: [.space, .return]) { _ in
                    guard selected == nil, let day = grid.day(from: nil) else { return .ignored }
                    onSelect(day)
                    return .handled
                }
                .accessibilityElement(children: .contain)
        } else {
            squares
        }
    }

    @ViewBuilder var squares: some View {
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
        if let c, let onSelect, case .level = c.state {
            // A day that can be chosen is a button for VoiceOver too (its own action, and selected when chosen).
            dayCell(c).accessibilityAddTraits(selected == c.date ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { onSelect(c.date) }
        } else if let c {
            dayCell(c)
        } else {
            Color.clear.frame(width: cell, height: cell).accessibilityHidden(true)
        }
    }

    /// The level as pixel density (`PixelLevelTile`); "no data" is the tile's outline. In the month view the figures
    /// sit on a plate of the tile's ground, so the dither never runs through them.
    func dayCell(_ c: StatsCalendar.Cell) -> some View {
        let px = theme.stroke(.hairline) * 2
        let level: Int? = if case .level(let l) = c.state { l } else { nil }
        return ZStack {
            PixelLevelTile(level: level)
            if showDayNumbers {
                VStack(spacing: 0) {
                    Text(String(c.date.suffix(2))).font(theme.font(.micro))
                    if let level, level > 0 { Text(Formatting.compact(Int64(c.messages))).font(theme.font(.micro)).opacity(0.8) }
                }
                .foregroundStyle(theme.color(.textPrimary, scheme))
                .padding(.horizontal, px)
                .background { if let level, level > 0 { Rectangle().fill(theme.color(.surfaceMuted, scheme)) } }
            }
        }
        .frame(width: cell, height: cell)
        .overlay {
            if selected == c.date {
                PixelTile(px: px).strokeBorder(theme.color(.textPrimary, scheme), lineWidth: max(px, (cell * 0.12 / px).rounded(.down) * px))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if case .level = c.state { onSelect?(c.date) } }
        .help(tooltip(c))
        .accessibilityElement()
        .accessibilityLabel(tooltip(c))
    }

    func tooltip(_ c: StatsCalendar.Cell) -> String {
        switch c.state {
        case .noData: Copy.Stats.noDataDay(StatsFormat.day(c.date))
        case .level: Copy.Stats.dayTooltip(StatsFormat.day(c.date), messages: c.messages, sessions: c.sessions)
        }
    }
}

/// The calendar's key: the "no data" outline, then the five levels as the same pixel tiles as the days.
struct CalendarLegend: View {
    /// The calendar's square, so the key matches it pixel for pixel; nil for the 10-point tile.
    var size: CGFloat?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let size = PixelDensity.tile(fitting: min(size ?? theme.spacing(.standard) + theme.spacing(.compact), theme.spacing(.spacious)),
                                     px: theme.stroke(.hairline) * 2)
        HStack(spacing: theme.spacing(.compact)) {
            PixelLevelTile(level: nil).frame(width: size, height: size)
            Text(Copy.Stats.noData).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                .padding(.trailing, theme.spacing(.standard))
            Text(Copy.Stats.less).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            ForEach(0..<5, id: \.self) { PixelLevelTile(level: $0).frame(width: size, height: size) }
            Text(Copy.Stats.more).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
        }
        .accessibilityHidden(true)
    }
}

/// Sessions started per hour of the day, from Claude Code's own counts, with a readout of the hour under the pointer
/// or the keyboard cursor (`chartKeyboard`).
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
                let plot = PixelColumns.plot(CGRect(x: 0, y: 0, width: size.width, height: size.height - footer))
                let slot = plot.width / 24
                let px = theme.stroke(.hairline) * 2
                for h in 0..<24 {
                    let n = counts[h] ?? 0
                    let x = CGFloat(h) * slot
                    if hover == h { context.fill(Path(PixelColumns.slot(h, of: 24, in: plot)), with: .color(theme.color(.surfaceMuted, scheme))) }
                    // The same pixel bars as Home's last 30 days; an hour with none is a faint one-pixel stub.
                    let bar = PixelColumns.bar(h, of: 24, in: plot, share: 0.72, px: px)
                    PixelColumns.fill(&context, x: bar.x, width: bar.width, height: n == 0 ? px : PixelColumns.height(Double(n) / Double(top), of: plot.height, px: px),
                                      baseline: plot.maxY, px: px, color: theme.color(.accent, scheme).opacity(n == 0 ? 0.2 : 1))
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
            .chartKeyboard($hover, count: 24, readout: hover.map { Copy.Stats.hourTooltip($0, counts[$0] ?? 0) })
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
