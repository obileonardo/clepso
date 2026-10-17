import ClaudeCodeAdapter
import DesignSystem
import SwiftUI

/// Tokens per model (increment 1.8f), two ways: Arena, a pixel character per model showing what it spent its tokens
/// on; and Chart, tokens per day stacked by model on a real date axis.
struct ModelsSection: View {
    @Bindable var model: AppModel
    let summary: StatsSummary
    let file: ClaudeCodeStats
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if summary.models.isEmpty {
            PageColumn {
                PageSection(Copy.Stats.models, nil) {
                    Text(Copy.Stats.noModels).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
        } else {
            // 1.14: Account's structure. The share, then the models (Arena) or tokens by day (Chart), then how levels work.
            PageColumn {
                PageSection(Copy.ModelsPage.distributionTitle, Copy.ModelsPage.distributionSub) { distribution }
                switch model.modelsView {
                case .arena: ModelArena(summary: summary)
                case .chart:
                    PageSection(Copy.Stats.tokensPerDay.capitalized, Copy.ModelsPage.chartSub) {
                        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                            StackedModelChart(summary: summary, from: first, to: summary.today)
                            ModelLegend(models: summary.models)
                        }
                    }
                }
            }
        }
    }

    /// Krea's "usage distribution" (1.12): the share of tokens as a ring with the total inside, beside a card per model.
    var distribution: some View {
        HStack(alignment: .center, spacing: theme.spacing(.spacious) * 1.5) {
            ZStack {
                PixelDonut(shares: summary.models.map(\.share))
                VStack(spacing: 0) {
                    Text(Formatting.compact(summary.totalTokens)).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                    Text(Copy.ModelsPage.tokens).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
            .frame(width: theme.spacing(.spacious) * 8, height: theme.spacing(.spacious) * 8)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(summary.models.enumerated()), id: \.element.id) { i, m in
                    HStack(spacing: theme.spacing(.standard)) {
                        Canvas { context, size in ModelStyle.fill(&context, CGRect(origin: .zero, size: size), index: i, theme: theme, scheme: scheme) }
                            .frame(width: theme.spacing(.standard) + theme.spacing(.compact), height: theme.spacing(.standard) + theme.spacing(.compact))
                            .accessibilityHidden(true)
                        FactRow(label: m.name, value: "\(Formatting.compact(m.tokens)) · \(String(format: "%.1f", m.share * 100))%")
                    }
                }
            }
        }
    }

    var first: String {
        switch summary.range {
        case .allTime: file.firstSessionDate ?? file.dailyTokens.map(\.date).min() ?? summary.today
        case .last30: StatsSummary.Day.adding(-29, to: summary.today)
        case .last7: StatsSummary.Day.adding(-6, to: summary.today)
        }
    }
}

/// How a model is drawn everywhere: a colour and a fill pattern. The first three differ in both, so series never
/// differ by colour alone; later ones reuse the colours with the other patterns.
enum ModelStyle {
    static let styles: [(ColorToken, Int)] = [(.accent, 0), (.statusAttention, 1), (.textPrimary, 2), (.accent, 1), (.statusAttention, 2), (.textPrimary, 0)]
    static func role(_ index: Int) -> ColorToken { styles[index % styles.count].0 }
    /// 0 solid, 1 striped, 2 half-tone.
    static func pattern(_ index: Int) -> Int { styles[index % styles.count].1 }

    static func fill(_ context: inout GraphicsContext, _ rect: CGRect, index: Int, theme: Theme, scheme: ColorScheme) {
        let color = theme.color(role(index), scheme)
        let px = theme.stroke(.hairline) * 2
        switch pattern(index) {
        case 1:
            context.fill(Path(rect), with: .color(color.opacity(0.3)))
            var y = rect.minY
            while y < rect.maxY { context.fill(Path(CGRect(x: rect.minX, y: y, width: rect.width, height: min(px / 2, rect.maxY - y))), with: .color(color)); y += px * 1.5 }
        case 2:
            context.fill(Path(rect), with: .color(color.opacity(0.25)))
            var y = rect.minY, row = 0
            while y < rect.maxY {
                var x = rect.minX + (row % 2 == 0 ? 0 : px / 2)
                while x < rect.maxX { context.fill(Path(CGRect(x: x, y: y, width: min(px / 2, rect.maxX - x), height: min(px / 2, rect.maxY - y))), with: .color(color)); x += px }
                y += px / 2; row += 1
            }
        default:
            context.fill(Path(rect), with: .color(color))
        }
    }
}

struct ModelLegend: View {
    let models: [StatsSummary.ModelShare]
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: theme.spacing(.spacious))], alignment: .leading, spacing: theme.spacing(.standard)) {
            ForEach(Array(models.enumerated()), id: \.element.id) { i, m in
                HStack(spacing: theme.spacing(.standard)) {
                    Canvas { context, size in ModelStyle.fill(&context, CGRect(origin: .zero, size: size), index: i, theme: theme, scheme: scheme) }
                        .frame(width: theme.spacing(.spacious) * 0.8, height: theme.spacing(.spacious) * 0.8).accessibilityHidden(true)
                    Text(m.name).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                    Spacer(minLength: theme.spacing(.standard))
                    Text("\(Formatting.compact(m.tokens)) · \(Int((m.share * 100).rounded()))%").font(theme.font(.supporting)).monospacedDigit()
                        .foregroundStyle(theme.color(.textSecondary, scheme))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Tokens per day (or per week over long ranges) stacked by model, every calendar day on the axis whether or not
/// there was activity, a labelled scale, and a hover readout of the day under the pointer.
struct StackedModelChart: View {
    let summary: StatsSummary
    let from: String
    let to: String
    /// False draws one series (all models together) in the accent colour.
    var stacked = true
    var height = DetailsMetrics.chartHeight * 1.5
    @State private var hover: Int?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    struct Bucket { let start: String; let end: String; let byModel: [Int64] }

    var buckets: [Bucket] {
        let order = summary.models.map(\.model)
        let byDate = Dictionary(summary.dailyTokens.map { ($0.date, $0.byModel) }, uniquingKeysWith: { a, _ in a })
        let days = StatsSummary.Day.between(from, to) + 1
        let width = days > 120 ? 7 : 1
        return stride(from: 0, to: days, by: width).map { offset in
            let start = StatsSummary.Day.adding(offset, to: from)
            let end = StatsSummary.Day.adding(min(offset + width, days) - 1, to: from)
            var totals = Array(repeating: Int64(0), count: order.count)
            for d in 0..<width where offset + d < days {
                for (i, id) in order.enumerated() { totals[i] += byDate[StatsSummary.Day.adding(offset + d, to: from)]?[id] ?? 0 }
            }
            return Bucket(start: start, end: end, byModel: stacked ? totals : [totals.reduce(0, +)])
        }
    }

    var body: some View {
        let buckets = buckets
        let top = Self.niceCeiling(buckets.map { $0.byModel.reduce(0, +) }.max() ?? 0)
        let weekly = buckets.first.map { $0.start != $0.end } ?? false
        let gutter = theme.spacing(.spacious) * 2.4
        let footer = theme.spacing(.spacious) * 1.2
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(weekly ? Copy.Stats.tokensPerWeek : Copy.Stats.tokensPerDay).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
            Canvas { context, size in
                let plot = CGRect(x: gutter, y: theme.spacing(.standard), width: size.width - gutter, height: size.height - footer - theme.spacing(.standard))
                let slot = plot.width / CGFloat(max(1, buckets.count))
                let barWidth = max(1, slot * 0.72)
                let px = theme.stroke(.hairline) * 2
                let secondary = theme.color(.textSecondary, scheme)
                func y(_ v: Int64) -> CGFloat { plot.maxY - CGFloat(Double(v) / Double(max(1, top))) * plot.height }
                for step in 0...4 {
                    let v = top / 4 * Int64(step)
                    var x0 = plot.minX
                    while x0 < plot.maxX { context.fill(Path(CGRect(x: x0, y: y(v), width: px / 2, height: px / 2)), with: .color(theme.color(.separator, scheme))); x0 += px * 3 }
                    context.draw(Text(Formatting.compact(v)).font(theme.font(.micro)).foregroundColor(secondary), at: CGPoint(x: plot.minX - theme.spacing(.standard), y: y(v)), anchor: .trailing)
                }
                if let hover, hover < buckets.count {
                    context.fill(Path(CGRect(x: plot.minX + CGFloat(hover) * slot, y: plot.minY, width: slot, height: plot.height)),
                                 with: .color(theme.color(.surfaceMuted, scheme)))
                }
                var lastLabelX = -CGFloat.infinity
                for (i, b) in buckets.enumerated() {
                    let x = plot.minX + CGFloat(i) * slot + (slot - barWidth) / 2
                    var base = plot.maxY
                    for (m, v) in b.byModel.enumerated() where v > 0 {
                        let h = max(px / 2, plot.maxY - y(v))
                        ModelStyle.fill(&context, CGRect(x: x, y: base - h, width: barWidth, height: h), index: m, theme: theme, scheme: scheme)
                        base -= h
                    }
                    // Month starts (or every 7th day in short ranges) on the axis, never overlapping.
                    let marks = buckets.count <= 45 ? i % 7 == 0 : (i > 0 && b.start.prefix(7) != buckets[i - 1].start.prefix(7))
                    let label = buckets.count <= 45 ? StatsFormat.day(b.start).uppercased() : StatsFormat.month(b.start).uppercased()
                    if marks || i == 0, x - lastLabelX > theme.spacing(.spacious) * 3.2 {
                        context.fill(Path(CGRect(x: x + barWidth / 2, y: plot.maxY, width: px / 2, height: px * 2)), with: .color(theme.color(.separator, scheme)))
                        ChartLabel.draw(context, Text(label).font(theme.font(.micro)).foregroundColor(secondary),
                                        centeredAt: x + barWidth / 2, top: plot.maxY + px * 3, width: size.width)
                        lastLabelX = x
                    }
                }
            }
            .frame(minHeight: height, maxHeight: .infinity)
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    // The same geometry as the canvas: the plot starts after the gutter.
                    hover = nil
                    let width = chartWidth
                    guard width > gutter, p.x >= gutter else { return }
                    hover = min(buckets.count - 1, Int((p.x - gutter) / ((width - gutter) / CGFloat(max(1, buckets.count)))))
                case .ended: hover = nil
                }
            }
            .background(GeometryReader { geo in Color.clear.preference(key: ChartWidthKey.self, value: geo.size.width) })
            .onPreferenceChange(ChartWidthKey.self) { chartWidth = $0 }
            .accessibilityElement()
            .accessibilityLabel(Copy.Stats.chartSummary(days: StatsSummary.Day.between(from, to) + 1, models: summary.models.count))
            Text(readout(buckets)).font(theme.font(.label)).monospacedDigit().lineLimit(1).truncationMode(.middle)
                .foregroundStyle(theme.color(hover == nil ? .textSecondary : .textPrimary, scheme))
                .accessibilityHidden(hover == nil)
        }
    }

    @State private var chartWidth: CGFloat = 0

    func readout(_ buckets: [Bucket]) -> String {
        guard let hover, hover < buckets.count else { return Copy.Stats.hoverHint }
        let b = buckets[hover]
        let when = b.start == b.end ? StatsFormat.day(b.start) : "\(StatsFormat.day(b.start))–\(StatsFormat.day(b.end))"
        guard stacked else { return "\(when) · \(Copy.Stats.tokensTotal(Formatting.compact(b.byModel.reduce(0, +))))" }
        let parts = zip(summary.models, b.byModel).filter { $0.1 > 0 }.map { "\($0.0.name) \(Formatting.compact($0.1))" }
        return parts.isEmpty ? "\(when) · \(Copy.Stats.noTokens)" : "\(when) · \(parts.joined(separator: " · "))"
    }

    /// 1, 2 or 5 × a power of ten at or above `v`, so the scale reads in round numbers.
    static func niceCeiling(_ v: Int64) -> Int64 {
        guard v > 4 else { return 4 }
        var p: Int64 = 1
        while p * 10 <= v { p *= 10 }
        // Steps in tenths of p; only those divisible by four, so the quarter lines are whole round numbers too.
        for m in [10, 12, 16, 20, 24, 30, 40, 50, 60, 80, 100] as [Int64] where (m * p) % 10 == 0 {
            let top = m * p / 10
            if top >= v, top % 4 == 0 { return top }
        }
        return (v + 3) / 4 * 4
    }
}

private struct ChartWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Arena

/// One pixel character per model. Its level grows each time its tokens double; its bars show what it spent them on
/// (all time, from Claude Code's per-model totals). Idle animation only when Reduce Motion is off.
struct ModelArena: View {
    let summary: StatsSummary
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ForEach(Array(ranked.enumerated()), id: \.element.share.id) { rank, entry in
            let specialty = ModelSpecialty.of(entry.share.totals, party: summary.models.compactMap(\.totals))
            PageSection("#\(rank + 1) " + entry.share.name, specialty.map { Copy.Stats.specialty($0.kind.doing, times: $0.ratio) } ?? Copy.Stats.activityUnknown) {
                FighterCard(share: entry.share, index: entry.index, rank: rank + 1, daysActive: daysActive(entry.share.model), range: summary.range,
                            specialty: specialty)
            }
        }
        PageSection(Copy.Stats.legendTitle.capitalized, summary.range == .allTime ? Copy.Stats.arenaNote : Copy.Stats.arenaRangeNote) {
            LevelLegend(models: ranked.compactMap { entry in entry.share.totals.map { (entry.share.name, ModelLevel(output: $0.output)) } })
        }
    }

    func daysActive(_ id: String) -> Int { summary.dailyTokens.filter { ($0.byModel[id] ?? 0) > 0 }.count }

    /// Ranked by level, so the rank and the level never disagree: most output first, then most tokens. `index` is the
    /// model's place in the chart's legend, which keeps its colour the same in both views.
    var ranked: [(share: StatsSummary.ModelShare, index: Int)] {
        summary.models.enumerated().map { (share: $0.element, index: $0.offset) }
            .sorted { ($0.share.totals?.output ?? -1, $0.share.tokens) > ($1.share.totals?.output ?? -1, $1.share.tokens) }
    }
}

struct FighterCard: View {
    let share: StatsSummary.ModelShare
    let index: Int
    let rank: Int
    let daysActive: Int
    let range: StatsSummary.Range
    let specialty: ModelSpecialty?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// Nil when Claude Code has no tokens-by-kind record for the model, so its output is unknown.
    var level: ModelLevel? { share.totals.map { ModelLevel(output: $0.output) } }

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing(.spacious) * 1.5) {
            VStack(spacing: theme.spacing(.compact)) {
                ModelSprite(family: ModelSprite.Family(share.model), role: ModelStyle.role(index))
                    .frame(width: theme.spacing(.spacious) * 4.8, height: theme.spacing(.spacious) * 4.8)
                    .background(theme.color(.surfaceMuted, scheme))
                Text(level.map { Copy.Stats.level($0.level) } ?? Copy.Stats.levelUnknown).font(theme.font(.title))
                    .foregroundStyle(theme.color(ModelStyle.role(index), scheme))
            }
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                if let level {
                    VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                        HStack {
                            Text(Copy.Stats.progressTo(level.level + 1)).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                            Spacer()
                            Text(Copy.Stats.outputOf(Formatting.compact(level.output), Formatting.compact(level.next), toGo: Formatting.compact(level.next - level.output)))
                                .font(theme.font(.supporting)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme))
                        }
                        PixelBar(fraction: level.progress, role: ModelStyle.role(index), pattern: .solid, segments: 40)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Copy.Stats.levelLabel(level.level, output: Formatting.compact(level.output), next: Formatting.compact(level.next)))
                }
                if let t = share.totals, t.total > 0 {
                    Grid(alignment: .leading, horizontalSpacing: theme.spacing(.standard), verticalSpacing: theme.spacing(.compact)) {
                        stat(Copy.Stats.input, t.input, of: t.total)
                        stat(Copy.Stats.output, t.output, of: t.total)
                        stat(Copy.Stats.cacheRead, t.cacheRead, of: t.total)
                        stat(Copy.Stats.cacheWrite, t.cacheWrite, of: t.total)
                    }
                }
                Text(Copy.Stats.tokensLine(Formatting.compact(share.tokens), Int((share.share * 100).rounded()), days: daysActive, allTime: range == .allTime))
                    .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    func stat(_ name: String, _ n: Int64, of total: Int64) -> some View {
        GridRow {
            Text(name.uppercased()).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                .gridColumnAlignment(.leading)
            PixelBar(fraction: Double(n) / Double(total), role: ModelStyle.role(index), pattern: .solid, segments: 24)
            Text(Formatting.compact(n)).font(theme.font(.label)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme))
                .gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The token kind a model leans on most compared with all models together: its share of that kind over the party's
/// share. Every model mostly reads from cache, so the plain largest kind would say the same thing on every card.
struct ModelSpecialty: Equatable {
    enum Kind: CaseIterable {
        case input, output, cacheRead, cacheWrite
        var doing: String {
            switch self {
            case .input: Copy.Stats.doingRead
            case .output: Copy.Stats.doingWrite
            case .cacheRead: Copy.Stats.doingRecall
            case .cacheWrite: Copy.Stats.doingStore
            }
        }
        func of(_ t: ClaudeCodeStats.ModelTotals) -> Int64 {
            switch self {
            case .input: t.input
            case .output: t.output
            case .cacheRead: t.cacheRead
            case .cacheWrite: t.cacheWrite
            }
        }
    }
    let kind: Kind
    let ratio: Double

    static func of(_ totals: ClaudeCodeStats.ModelTotals?, party: [ClaudeCodeStats.ModelTotals]) -> ModelSpecialty? {
        guard let totals, totals.total > 0 else { return nil }
        let all = party.reduce(Int64(0)) { $0 + $1.total }
        guard all > 0 else { return nil }
        let ranked = Kind.allCases.compactMap { kind -> ModelSpecialty? in
            let partyKind = party.reduce(Int64(0)) { $0 + kind.of($1) }
            guard partyKind > 0, kind.of(totals) > 0 else { return nil }
            return ModelSpecialty(kind: kind, ratio: (Double(kind.of(totals)) / Double(totals.total)) / (Double(partyKind) / Double(all)))
        }
        return ranked.max { $0.ratio < $1.ratio }
    }
}

/// A model's level comes from its output tokens (what it wrote, all time). Each level has a fixed target on a
/// 1-2-5 ladder — 1K, 2K, 5K, 10K, 20K, 50K… — so the next target is always a round, readable number. Cache reads
/// don't count: they are the conversation being re-read on every turn, not work the model produced.
struct ModelLevel: Equatable {
    let output: Int64
    let level: Int
    /// Output at which this level began (0 for level 1) and the next level's target.
    let floor: Int64
    let next: Int64
    var progress: Double { next > floor ? Double(output - floor) / Double(next - floor) : 1 }

    /// The targets for level 2, 3, 4… in order.
    static let targets: [Int64] = {
        var all: [Int64] = []
        var decade: Int64 = 1_000
        while decade <= 1_000_000_000_000_000 {
            all += [decade, decade * 2, decade * 5]
            decade *= 10
        }
        return all
    }()

    init(output: Int64) {
        let output = max(0, output)
        let reached = Self.targets.prefix { $0 <= output }.count
        self.output = output
        self.level = reached + 1
        self.floor = reached == 0 ? 0 : Self.targets[reached - 1]
        self.next = reached < Self.targets.count ? Self.targets[reached] : Self.targets[reached - 1]
    }
}

/// "How levels work": the ladder of output targets with each model placed on it, what each kind of token is, and how
/// rank and specialty are worked out. The same rules are published on the documentation site (Metrics page).
struct LevelLegend: View {
    let models: [(name: String, level: ModelLevel)]
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// Levels 1 to 20, or further when a model has gone past 20.
    var shown: Int { max(20, (models.map(\.level.level).max() ?? 0) + 1) }

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing(.spacious) * 1.5) {
            ladder.frame(maxWidth: .infinity, alignment: .topLeading)
            definitions.frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    var ladder: some View {
        let half = (shown + 1) / 2
        return VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(Copy.Stats.ladderTitle).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            HStack(alignment: .top, spacing: theme.spacing(.spacious)) {
                column(1...half)
                column((half + 1)...shown)
            }
            Text(Copy.Stats.ladderNote).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func column(_ levels: ClosedRange<Int>) -> some View {
        Grid(alignment: .leading, horizontalSpacing: theme.spacing(.standard), verticalSpacing: theme.spacing(.compact)) {
            ForEach(Array(levels), id: \.self) { level in
                let here = models.filter { $0.level.level == level }.map(\.name)
                GridRow {
                    Text(Copy.Stats.level(level)).font(theme.font(.label)).monospacedDigit()
                        .foregroundStyle(theme.color(here.isEmpty ? .textSecondary : .accent, scheme))
                    Text(level == 1 ? "0" : Formatting.compact(ModelLevel.targets[level - 2])).font(theme.font(.label)).monospacedDigit()
                        .foregroundStyle(theme.color(here.isEmpty ? .textSecondary : .textPrimary, scheme))
                        .gridColumnAlignment(.trailing)
                    Text(here.joined(separator: ", ")).font(theme.font(.supporting)).foregroundStyle(theme.color(.accent, scheme))
                        .lineLimit(1).truncationMode(.tail)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    var definitions: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(Copy.Stats.kindsTitle).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            ForEach(Copy.Stats.kindDefinitions, id: \.0) { name, meaning, counts in
                VStack(alignment: .leading, spacing: theme.spacing(.compact) / 2) {
                    HStack(spacing: theme.spacing(.standard)) {
                        Text(name.uppercased()).font(theme.font(.label).weight(.semibold)).foregroundStyle(theme.color(.textPrimary, scheme))
                        Text(counts ? Copy.Stats.countsForLevel : Copy.Stats.notForLevel).font(theme.font(.micro))
                            .foregroundStyle(theme.color(counts ? .accent : .textSecondary, scheme))
                    }
                    Text(meaning).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Text(Copy.Stats.rankRule).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
            Text(Copy.Stats.specialtyRule).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A 12×12 pixel character per model family, drawn from a bitmap, with a one-pixel idle bob.
struct ModelSprite: View {
    enum Family {
        case opus, sonnet, haiku, fable, other
        init(_ id: String) {
            let id = id.lowercased()
            self = id.contains("opus") ? .opus : id.contains("sonnet") ? .sonnet : id.contains("haiku") ? .haiku : id.contains("fable") ? .fable : .other
        }
    }
    let family: Family
    let role: ColorToken
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.6)) { timeline in
            let frame = reduceMotion ? 0 : Int(timeline.date.timeIntervalSinceReferenceDate / 0.6) % 2
            Canvas { context, size in
                let rows = Self.bitmap(family)
                let unit = floor(min(size.width, size.height) / CGFloat(rows.count + 2))
                let origin = CGPoint(x: (size.width - unit * 12) / 2, y: (size.height - unit * 12) / 2 + CGFloat(frame) * unit / 2)
                for (r, row) in rows.enumerated() {
                    for (c, ch) in row.enumerated() {
                        let color: Color? = switch ch {
                        case "a": theme.color(role, scheme)
                        case "b": theme.color(.textPrimary, scheme)
                        case "c": theme.color(role, scheme).opacity(0.45)
                        case "d": theme.color(.background, scheme)
                        default: nil
                        }
                        if let color { context.fill(Path(CGRect(x: origin.x + CGFloat(c) * unit, y: origin.y + CGFloat(r) * unit, width: unit, height: unit)), with: .color(color)) }
                    }
                }
                // Shadow under the feet, steady while the body bobs.
                context.fill(Path(CGRect(x: origin.x + unit * 3, y: (size.height + unit * 12) / 2 + unit * 0.6, width: unit * 6, height: unit / 2)),
                             with: .color(theme.color(.separator, scheme)))
            }
        }
        .accessibilityHidden(true)
    }

    static func bitmap(_ f: Family) -> [[Character]] {
        let rows: [String] = switch f {
        case .opus: [   // a wizard with a staff
            ".....aa.....", "....aaaa....", "...aaaaaa...", "..aaaaaaaa..", "....bbbb....", "....bdbd....",
            "....bbbb...c", "...aaaaaa..c", "..aaaaaaaa.c", "..a.aaaa.a.c", "....aaaa...c", "...aa..aa..."]
        case .sonnet: [ // a knight with a sword
            "....bbbb....", "...bbbbbb...", "...bddddb...", "...bbbbbb...", "....bbbb..b.", "..aaaaaaaa.b",
            ".aaaaaaaaa.b", ".a.aaaaaa.ab", ".c.aaaaaa...", "...aaaaaa...", "...aa..aa...", "..aaa..aaa.."]
        case .haiku: [  // a winged sprite
            "............", ".....bb.....", "....bbbb....", ".c..bdbd..c.", ".cc.bbbb.cc.", ".ccc.aa.ccc.",
            "..ccaaaacc..", "...caaaac...", "....aaaa....", "....a..a....", "............", "............"]
        case .fable: [  // a bard in a feathered hat
            "..aaaaa.....", ".aaaaaaac...", "....bbbb....", "....bdbd....", "....bbbb....", "...aaaaaa.c.",
            "..aaaaaaacc.", "..a.aaaaccc.", "....aaaa.c..", "....aaaa....", "...aa..aa...", "............"]
        case .other: [  // a robot
            ".....c......", ".....a......", "..aaaaaaaa..", "..abbaabba..", "..abdaadba..", "..aaaaaaaa..",
            "...a.aa.a...", ".aaaaaaaaaa.", ".a.aaaaaa.a.", "...aaaaaa...", "...a....a...", "..aa....aa.."]
        }
        return rows.map(Array.init)
    }
}

/// A ring of square pixels split into consecutive arcs, one per share, in each model's colour (Krea's donut).
struct PixelDonut: View {
    let shares: [Double]
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let count = 48
            let radius = min(size.width, size.height) / 2 - theme.spacing(.standard)
            let block = radius * 0.17
            let total = max(shares.reduce(0, +), 0.0001)
            var bounds: [Int] = []
            var acc = 0.0
            for share in shares { acc += share / total; bounds.append(Int((acc * Double(count)).rounded())) }
            for i in 0..<count {
                let angle = Double(i) / Double(count) * 2 * .pi - .pi / 2
                let center = CGPoint(x: size.width / 2 + radius * cos(angle), y: size.height / 2 + radius * sin(angle))
                let rect = CGRect(x: (center.x - block / 2).rounded(), y: (center.y - block / 2).rounded(), width: block, height: block)
                if let index = bounds.firstIndex(where: { i < $0 }) {
                    var ctx = context
                    ModelStyle.fill(&ctx, rect, index: index, theme: theme, scheme: scheme)
                } else {
                    context.fill(Path(rect), with: .color(theme.color(.surfaceMuted, scheme)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
