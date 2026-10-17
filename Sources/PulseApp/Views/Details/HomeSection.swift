import DesignSystem
import Domain
import SwiftUI

/// Home (1.10, reworked in 1.12 after the founder's picks): Delphi's hero chart with a metric switch and a level card
/// with tier progress; Deel's "For you today" list of things to act on, most urgent first.
struct HomeSection: View {
    @Bindable var model: AppModel
    @State private var metric: HomeMetric = .tokens
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow

    enum HomeMetric: Hashable { case tokens, messages, sessions }

    /// 1.14: Account's structure. Today first (what needs you), then the limits, the last 30 days, and the level.
    var body: some View {
        PageColumn {
            PageSection(Copy.HomePage.today, Copy.HomePage.todaySub) { forYou }
            PageSection(Copy.Home.limits, Copy.HomePage.limitsSub) { limitsGlance }
            PageSection(Copy.ForYou.last30, Copy.HomePage.monthSub) { hero }
            PageSection(Copy.ForYou.level, Copy.HomePage.levelSub) { levelCard }
        }
        .task { model.loadStats() }
    }

    // MARK: Hero (Delphi)

    var series: [(day: String, value: Int64)] {
        guard let file = model.statsFile, let today = model.statsSummary(.last30)?.today else { return [] }
        let days = (0..<30).map { StatsSummary.Day.adding($0 - 29, to: today) }
        let byDay = Dictionary(file.days.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let tokens = Dictionary(file.dailyTokens.map { ($0.date, $0.byModel.values.reduce(0, +)) }, uniquingKeysWith: { a, _ in a })
        return days.map { day in
            let value: Int64 = switch metric {
            case .tokens: tokens[day] ?? 0
            case .messages: Int64(byDay[day]?.messages ?? 0)
            case .sessions: Int64(byDay[day]?.sessions ?? 0)
            }
            return (day, value)
        }
    }

    var metricName: String {
        switch metric {
        case .tokens: Copy.ForYou.tokens
        case .messages: Copy.ForYou.messages
        case .sessions: Copy.ForYou.sessions
        }
    }

    @ViewBuilder var hero: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            PixelSegmented(Copy.ForYou.metric, options: [(HomeMetric.tokens, Copy.ForYou.tokens), (.messages, Copy.ForYou.messages),
                                                         (.sessions, Copy.ForYou.sessions)], selection: $metric)
            let data = series
            if data.isEmpty {
                Text(Copy.Card.needsStats).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Button(Copy.Home.turnOn) { Task { await model.setStatsEnabled(true) } }.buttonStyle(PixelButtonStyle(prominent: true))
            } else {
                Text(Copy.ForYou.total(Formatting.compact(data.map(\.value).reduce(0, +)), metricName).uppercased())
                    .font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textPrimary, scheme))
                DailyBars(values: data, unit: metricName).frame(height: DetailsMetrics.chartHeight)
            }
        }
    }

    // MARK: For you today (Deel)

    var items: [ForYouItem] {
        let snapshot = model.snapshot
        var input = ForYou.Input()
        input.limits = (snapshot.provider?.pools ?? []).map { row in
            let pct = row.model.used.value.map { NSDecimalNumber(decimal: $0).doubleValue }
            let state: GoalStatus.State = switch row.model.card {
            case .critical, .exhausted, .exhaustedNoReset, .exhaustedOverage: .missed
            case .approaching: .atRisk
            default: .onTrack
            }
            return (row.model.scope, pct, state)
        }
        input.goals = model.goalStatuses
        input.runningTask = snapshot.agents?.latest.flatMap { $0.running ? $0 : nil }
        input.connected = snapshot.empty != .notConnected || snapshot.isDemo
        input.statsOn = model.statsEnabled
        input.agentsOn = snapshot.agents != nil
        if case .signedIn = model.account { input.signedIn = true } else { input.signedIn = false }
        return ForYou.make(input)
    }

    var forYou: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                IconRow(glyph: Self.symbol(item.kind), title: item.title, subtitle: item.detail.isEmpty ? nil : item.detail, role: Self.role(item.kind)) {
                    if let action = item.action { Button(action) { perform(item) }.buttonStyle(PixelButtonStyle()) }
                }
            }
        }
    }

    func perform(_ item: ForYouItem) {
        switch item.kind {
        case .connect:
            model.onboardingStep = .consent
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: PulseScenes.onboardingID)
        case .stats: Task { await model.setStatsEnabled(true) }
        default: if let section = item.section { model.detailsSection = section }
        }
    }

    static func symbol(_ kind: ForYouItem.Kind) -> String {
        switch kind {
        case .limit: "gauge.with.dots.needle.67percent"
        case .goal: "target"
        case .task: "person.3"
        case .connect: "link"
        case .stats: "chart.bar.xaxis"
        case .agents: "person.3"
        case .account: "person.crop.circle"
        case .allClear: "checkmark"
        }
    }

    static func role(_ kind: ForYouItem.Kind) -> ColorToken {
        switch kind {
        case .limit, .goal: .statusAttention
        default: .accent
        }
    }

    // MARK: Level (Delphi's score card)

    @ViewBuilder var levelCard: some View {
        if let card = model.playerCard {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Copy.Card.levelBar(card.level.level, card.levelName)).font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textPrimary, scheme))
                    Spacer()
                    Button(Copy.HomePage.openCard) { model.detailsSection = .card }.buttonStyle(PixelButtonStyle())
                }
                PixelBar(fraction: card.level.progress, role: .accent, pattern: .solid, segments: 30)
                HStack {
                    Text(Formatting.compact(card.level.floor)).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    Spacer()
                    Text(Copy.Card.toNext(Formatting.compact(card.level.next - card.level.output), card.level.level + 1))
                        .font(theme.font(.supporting)).foregroundStyle(theme.color(.accent, scheme))
                    Spacer()
                    Text(Formatting.compact(card.level.next)).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
        } else {
            Text(Copy.Card.needsStats).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder var limitsGlance: some View {
        if let pools = model.snapshot.provider?.pools, !pools.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                ForEach(pools) { row in LimitMeterRow(row: row, now: model.snapshot.now, model: model) }
            }
        } else {
            Text(Copy.Details.noLimits).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}

/// A limit in one row (after the founder's StackAI pick): name and its reset on the left, a segmented meter and the
/// percentage on the right.
struct LimitMeterRow: View {
    let row: PoolRow
    let now: Date
    let model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pct = row.model.used.value.map { NSDecimalNumber(decimal: $0).doubleValue }
        let role: ColorToken = switch row.model.card {
        case .approaching: .statusAttention
        case .critical, .exhausted, .exhaustedNoReset, .exhaustedOverage: .statusBlocked
        default: StatusStyles.of(row.model.card).role        // 1.15: the same state colour as the popover in every theme
        }
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.model.scope.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                Spacer()
                Text(pct.map { "\(Int($0.rounded()))%" } ?? "—").font(theme.font(.title)).monospacedDigit().foregroundStyle(theme.color(role, scheme))
            }
            PixelBar(fraction: pct.map { $0 / 100 }, role: role, pattern: pct == nil ? .outline : .solid, segments: 20)
            if let reset = row.model.resetsAt.value {
                Text(Copy.Limits.resets(Formatting.resetTime(reset, now: now, zone: model.environment.timeZone, locale: model.environment.locale)))
                    .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
        }
        .padding(.vertical, theme.spacing(.compact))
        .accessibilityElement(children: .combine)
    }
}

/// Daily bars for one value over a range, a scale, every 7th day labelled, and a hover readout.
struct DailyBars: View {
    let values: [(day: String, value: Int64)]
    let unit: String
    @State private var hover: Int?
    @State private var width: CGFloat = 0
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let top = StackedModelChart.niceCeiling(values.map(\.value).max() ?? 0)
        let gutter = theme.spacing(.spacious) * 2.4, footer = theme.spacing(.spacious) * 1.2
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            Canvas { context, size in
                let plot = CGRect(x: gutter, y: theme.spacing(.standard), width: size.width - gutter, height: size.height - footer - theme.spacing(.standard))
                let slot = plot.width / CGFloat(max(1, values.count))
                let px = theme.stroke(.hairline) * 2
                let secondary = theme.color(.textSecondary, scheme)
                func y(_ v: Int64) -> CGFloat { plot.maxY - CGFloat(Double(v) / Double(max(1, top))) * plot.height }
                for step in 0...4 {
                    let v = top / 4 * Int64(step)
                    var x0 = plot.minX
                    while x0 < plot.maxX { context.fill(Path(CGRect(x: x0, y: y(v), width: px / 2, height: px / 2)), with: .color(theme.color(.separator, scheme))); x0 += px * 3 }
                    context.draw(Text(Formatting.compact(v)).font(theme.font(.micro)).foregroundColor(secondary), at: CGPoint(x: plot.minX - theme.spacing(.standard), y: y(v)), anchor: .trailing)
                }
                for (i, item) in values.enumerated() {
                    let x = plot.minX + CGFloat(i) * slot
                    if hover == i { context.fill(Path(CGRect(x: x, y: plot.minY, width: slot, height: plot.height)), with: .color(theme.color(.surfaceMuted, scheme))) }
                    let h = max(px / 2, plot.maxY - y(item.value))
                    context.fill(Path(CGRect(x: x + slot * 0.15, y: plot.maxY - h, width: slot * 0.7, height: h)),
                                 with: .color(theme.color(.accent, scheme).opacity(item.value == 0 ? 0.2 : 1)))
                    if (i % 7 == 0 && values.count - 1 - i >= 4) || i == values.count - 1 {     // never two labels side by side
                        ChartLabel.draw(context, Text(StatsFormat.day(item.day).uppercased()).font(theme.font(.micro)).foregroundColor(secondary),
                                        centeredAt: x + slot / 2, top: plot.maxY + px * 3, width: size.width)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onContinuousHover { phase in
                if case .active(let p) = phase, width > gutter, p.x >= gutter {
                    hover = min(values.count - 1, Int((p.x - gutter) / ((width - gutter) / CGFloat(max(1, values.count)))))
                } else { hover = nil }
            }
            .accessibilityElement()
            .accessibilityLabel(Copy.ForYou.total(Formatting.compact(values.map(\.value).reduce(0, +)), unit))
            Text(hover.map { "\(StatsFormat.day(values[$0].day)) · \(Formatting.compact(values[$0].value)) \(unit.lowercased())" } ?? Copy.Stats.hoverHint)
                .font(theme.font(.supporting)).monospacedDigit().foregroundStyle(theme.color(hover == nil ? .textSecondary : .textPrimary, scheme))
        }
    }
}

/// A lit or outlined pixel pill holding one line of text.
struct PixelChip: View {
    let text: String
    var lit = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text).font(theme.font(.label)).monospacedDigit().lineLimit(1)
            .foregroundStyle(theme.color(lit ? .background : .textPrimary, scheme))
            .padding(.horizontal, theme.spacing(.standard) + theme.spacing(.compact)).padding(.vertical, theme.spacing(.compact) + 1)
            .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(lit ? .accent : .surfaceElevated, scheme)))
            .overlay(PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(lit ? .accent : .separator, scheme), lineWidth: theme.stroke(.hairline)))
    }
}

/// One suggested next step, with its button.
struct NextStepBanner: View {
    let title: String
    let message: String
    let action: String
    let perform: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: theme.spacing(.spacious)) {
            VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                Text(title).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                Text(message).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action, action: perform).buttonStyle(PixelButtonStyle(prominent: true))
        }
        .padding(theme.spacing(.windowPadding))
        .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.surfaceMuted, scheme)))
        .overlay(PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(.accent, scheme).opacity(0.5), lineWidth: theme.stroke(.hairline)))
    }
}

/// A goal's state in words, with a colour (never colour alone).
struct StateTag: View {
    let state: GoalStatus.State
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let (text, role): (String, ColorToken) = switch state {
        case .met: (Copy.Goals.met, .statusSuccess)
        case .onTrack: (Copy.Goals.onTrack, .statusSuccess)
        case .atRisk: (Copy.Goals.atRisk, .statusAttention)
        case .missed: (Copy.Goals.missed, .statusBlocked)
        case .noData: (Copy.Goals.noData, .textSecondary)
        }
        Text(text).font(theme.font(.micro)).foregroundStyle(theme.color(role, scheme))
            .padding(.horizontal, theme.spacing(.compact) * 1.5).padding(.vertical, theme.spacing(.compact) / 2)
            .overlay(PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(role, scheme), lineWidth: theme.stroke(.hairline)))
    }
}
