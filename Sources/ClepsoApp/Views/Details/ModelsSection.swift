import ClaudeCodeAdapter
import DesignSystem
import SwiftUI

/// Tokens per model, as the founder chose it on 19 Oct 2026 (docs/design-concepts/models, proposal A "Roster +
/// Dossier", drawn from his five references: Revolut Business, Life Reset, Duolingo, Nike Run Club, Azar): every model
/// in a ranked roster on the left with the range's total at its head, the chosen model's dossier (Arena) or tokens per
/// day with that model picked out (Chart) on the right, and "How levels work" as a track with each model standing at
/// its level. The numbers come from `ModelsRoster`.
struct ModelsSection: View {
    @Bindable var model: AppModel
    let summary: StatsSummary
    let file: ClaudeCodeStats
    /// The model the user chose. Kept across range changes; `ModelsRoster.resolve` falls back to #1 when it has gone.
    @State private var selected: String? = Self.initialSelection
    /// The right-hand pane's height: the roster scrolls on its own when it is taller.
    @State private var paneHeight: CGFloat = 0
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let roster = ModelsRoster(summary)
        if let chosen = roster.resolve(selected) {
            PageColumn {
                split(roster, chosen)
                if model.modelsView == .arena {
                    LevelTrack(roster: roster, selected: chosen.id) { selected = $0 }
                }
            }
        } else {
            PageColumn {
                PageSection(Copy.Stats.models, nil) {
                    Text(Copy.Stats.noModels).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
        }
    }

    /// The roster in the page's label column, the dossier or the chart in its content side. One model: no list to
    /// choose from, so the total sits over the dossier and the dossier takes the width.
    func split(_ roster: ModelsRoster, _ chosen: ModelsRoster.Entry) -> some View {
        HStack(alignment: .top, spacing: theme.spacing(.spacious) * 1.5) {
            if roster.showsRoster {
                RosterList(roster: roster, selected: chosen.id, height: paneHeight) { selected = $0 }
                    .frame(width: PageMetrics.labelColumn)
            }
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                if !roster.showsRoster { RosterTotal(roster: roster) }
                switch model.modelsView {
                case .arena:
                    ModelDossier(entry: chosen, range: summary.range, activity: ModelsRoster.activity(chosen.id, summary: summary, from: first),
                                 weekly: StatsSummary.Day.between(first, summary.today) + 1 > 120, from: first)
                case .chart:
                    StackedModelChart(summary: summary, from: first, to: summary.today, highlight: roster.showsRoster ? chosen.id : nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { paneHeight = $0 }
        }
        .padding(.vertical, theme.spacing(.section))
        .overlay(alignment: .top) { Rectangle().fill(theme.color(.separator, scheme)).frame(height: theme.stroke(.hairline)) }
    }

    var first: String {
        switch summary.range {
        case .allTime: file.firstSessionDate ?? file.dailyTokens.map(\.date).min() ?? summary.today
        case .last30: StatsSummary.Day.adding(-29, to: summary.today)
        case .last7: StatsSummary.Day.adding(-6, to: summary.today)
        }
    }

    /// Debug builds: `-ClepsoProbeModel <model id>` opens the page on that model, for screenshots of a later row.
    static var initialSelection: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "ClepsoProbeModel")
        #else
        nil
        #endif
    }
}

/// The range's total tokens over the roster (Revolut's "All · 2" list header, with the figure).
struct RosterTotal: View {
    let roster: ModelsRoster
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            Text(Copy.ModelsPage.rosterTitle(roster.entries.count)).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
                Text(Formatting.compact(roster.total)).font(theme.font(.metricMedium)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme))
                Text(Copy.ModelsPage.totalIn(roster.range)).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Every model in rank order (Revolut's compact list, Duolingo's ranked rows): rank, sprite, name and share; its
/// pattern swatch, tokens and level chip. Divided where output crosses 1K, 1M, 1B (Duolingo's promotion zone). One
/// keyboard stop: ↑ ↓ move the choice and the dossier follows, Home and End jump to the ends, a letter jumps to the
/// next model starting with it.
struct RosterList: View {
    let roster: ModelsRoster
    let selected: String
    /// The pane beside it; the list scrolls within this height.
    let height: CGFloat
    let onSelect: (String) -> Void
    @State private var headerHeight: CGFloat = 0
    @State private var listHeight: CGFloat = 0
    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            RosterTotal(roster: roster)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                        ForEach(Array(roster.zones.enumerated()), id: \.offset) { _, zone in
                            ZoneDivider(zone: zone)
                            ForEach(zone.entries) { entry in
                                RosterRow(entry: entry, chosen: entry.id == selected)
                                    .id(entry.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelect(entry.id) }
                                    .accessibilityAction { onSelect(entry.id) }
                            }
                        }
                    }
                    .padding(theme.stroke(.focus) * 3)            // room for the focus ring inside the scroll view
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .frame(height: Self.listFrame(content: listHeight, pane: height - headerHeight - theme.spacing(.standard),
                                              rows: roster.entries.count, floor: theme.spacing(.spacious) * 10))
                .onChange(of: selected) { _, id in proxy.scrollTo(id) }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()                                 // the pixel ring instead of the system's rounded one
            .pixelFocusRing(focused)
            .onMoveCommand { direction in
                switch direction {
                case .up: if let id = roster.step(selected, by: -1) { onSelect(id) }
                case .down: if let id = roster.step(selected, by: 1) { onSelect(id) }
                default: break
                }
            }
            .onKeyPress(keys: [.home, .end]) { press in
                guard let id = press.key == .home ? roster.firstID : roster.lastID else { return .ignored }
                onSelect(id)
                return .handled
            }
            .onKeyPress(characters: .letters, phases: .down) { press in
                guard let id = roster.typeSelect(press.characters, after: selected) else { return .ignored }
                onSelect(id)
                return .handled
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Copy.ModelsPage.rosterLabel)
            .accessibilityHint(Copy.ModelsPage.rosterHint)
        }
    }
}

extension RosterList {
    /// The list's height: all of it while there are at most `fullRows` models (no half-cut row beside a short pane);
    /// beyond that, the pane's height (never under `floor`), and the list scrolls.
    nonisolated static func listFrame(content: CGFloat, pane: CGFloat, rows: Int, floor: CGFloat, fullRows: Int = 8) -> CGFloat {
        rows <= fullRows ? max(content, floor) : min(content, max(pane, floor))
    }
}

/// Duolingo's "PROMOTION ZONE" line, for output: hairlines either side of the zone's floor.
struct ZoneDivider: View {
    let zone: ModelsRoster.Zone
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let target = zone.floorLevel.map { Formatting.compact(ModelsRoster.target(of: $0)) } ?? ""
        let color = theme.color(zone.floorLevel == nil ? .textSecondary : .accent, scheme)
        HStack(spacing: theme.spacing(.standard)) {
            Rectangle().fill(color.opacity(0.5)).frame(height: theme.stroke(.hairline))
            Text(Copy.ModelsPage.zoneLabel(floorLevel: zone.floorLevel, target: target)).font(theme.font(.micro)).tracking(1)
                .foregroundStyle(color).lineLimit(1).fixedSize()
            Rectangle().fill(color.opacity(0.5)).frame(height: theme.stroke(.hairline))
        }
        .padding(.vertical, theme.spacing(.compact))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.ModelsPage.zoneSpoken(floorLevel: zone.floorLevel, target: ModelsRoster.spoken(ModelsRoster.target(of: zone.floorLevel ?? 1))))
        .accessibilityAddTraits(.isHeader)
    }
}

struct RosterRow: View {
    let entry: ModelsRoster.Entry
    let chosen: Bool
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let px = theme.stroke(.hairline) * 2
        let role = ModelStyle.role(entry.style)
        HStack(alignment: .center, spacing: theme.spacing(.standard)) {
            Text("\(entry.rank)").font(theme.font(.title)).monospacedDigit()
                .foregroundStyle(theme.color(chosen ? .textPrimary : .textSecondary, scheme))
                .frame(minWidth: theme.spacing(.spacious) * 1.25, alignment: .center)
            ModelSprite(modelID: entry.id)
                .frame(width: theme.spacing(.spacious) * 2.25, height: theme.spacing(.spacious) * 2.25)
            VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
                    Text(entry.name.uppercased()).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text(ModelsRoster.percent(entry.share.share)).font(theme.font(.label)).monospacedDigit()
                        .foregroundStyle(theme.color(.textPrimary, scheme))
                }
                HStack(alignment: .center, spacing: theme.spacing(.standard)) {
                    Canvas { context, size in ModelStyle.fill(&context, CGRect(origin: .zero, size: size), index: entry.style, theme: theme, scheme: scheme) }
                        .frame(width: theme.spacing(.standard) + theme.spacing(.compact), height: theme.spacing(.standard) + theme.spacing(.compact))
                    Text(Formatting.compact(entry.share.tokens)).font(theme.font(.supporting)).monospacedDigit()
                        .foregroundStyle(theme.color(.textSecondary, scheme))
                    Spacer(minLength: 0)
                    LevelChip(level: entry.level?.level, role: role)
                }
            }
        }
        .padding(.vertical, theme.spacing(.standard))
        .padding(.horizontal, theme.spacing(.standard))
        .background {
            if chosen {
                PixelRect(step: px).fill(theme.color(.surfaceMuted, scheme))
                PixelRect(step: px).strokeBorder(theme.color(.separator, scheme), lineWidth: px / 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.ModelsPage.rowLabel(rank: entry.rank, name: entry.name, level: entry.level?.level,
                                                     tokens: ModelsRoster.spoken(entry.share.tokens), share: ModelsRoster.spokenPercent(entry.share.share)))
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// Azar's level chip: "LV 14" in the model's colour on a tint of it ("LV —" when the level is unknown).
struct LevelChip: View {
    let level: Int?
    let role: ColorToken
    var large = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let px = theme.stroke(.hairline) * 2
        let color = theme.color(level == nil ? .textSecondary : role, scheme)
        Text(level.map { Copy.Stats.level($0) } ?? Copy.Stats.levelUnknown)
            .font(large ? theme.font(.title) : theme.font(.micro)).monospacedDigit().foregroundStyle(color)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, large ? theme.spacing(.standard) + theme.spacing(.compact) : theme.spacing(.standard))
            .padding(.vertical, large ? theme.spacing(.compact) : theme.spacing(.compact) / 2)
            .background(PixelRect(step: px).fill(color.opacity(0.16)))
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

/// Tokens per day (or per week over long ranges) stacked by model, every calendar day on the axis whether or not
/// there was activity, a labelled scale, and a hover readout of the day under the pointer.
/// Tokens per day by model, for `StackedModelChart`: Claude Code's from its stats file, Codex's from its session files.
struct TokenSeries {
    /// Model ids, largest first, and their display names in the same order.
    let ids: [String]
    let names: [String]
    /// date → model id → tokens.
    let byDate: [String: [String: Int64]]

    init(ids: [String], names: [String], byDate: [String: [String: Int64]]) {
        self.ids = ids; self.names = names; self.byDate = byDate
    }

    init(_ summary: StatsSummary) {
        self.init(ids: summary.models.map(\.model), names: summary.models.map(\.name),
                  byDate: Dictionary(summary.dailyTokens.map { ($0.date, $0.byModel) }, uniquingKeysWith: { a, _ in a }))
    }
}

extension StackedModelChart {
    init(summary: StatsSummary, from: String, to: String, stacked: Bool = true, height: CGFloat = DetailsMetrics.chartHeight * 1.5,
         highlight: String? = nil) {
        self.init(series: TokenSeries(summary), from: from, to: to, stacked: stacked, height: height, highlight: highlight)
    }
}

struct StackedModelChart: View {
    let series: TokenSeries
    let from: String
    let to: String
    /// False draws one series (all models together) in the accent colour.
    var stacked = true
    var height = DetailsMetrics.chartHeight * 1.5
    /// A model id to pick out (Models › Chart, the roster's choice): the other models' parts are dimmed and the
    /// readout leads with it.
    var highlight: String? = nil
    @State private var hover: Int?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    struct Bucket { let start: String; let end: String; let byModel: [Int64] }

    var buckets: [Bucket] {
        let order = series.ids
        let byDate = series.byDate
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
            // The bucket as a quiet caption (the section's name is the heading): long ranges count by week.
            Text(weekly ? Copy.Stats.tokensPerWeek : Copy.Stats.tokensPerDay).font(theme.font(.micro)).tracking(1)
                .foregroundStyle(theme.color(.textSecondary, scheme))
            Canvas { context, size in
                let plot = PixelColumns.plot(CGRect(x: gutter, y: theme.spacing(.standard), width: size.width - gutter,
                                                    height: size.height - footer - theme.spacing(.standard)))
                let px = theme.stroke(.hairline) * 2
                let secondary = theme.color(.textSecondary, scheme)
                func y(_ v: Int64) -> CGFloat { plot.maxY - PixelColumns.height(Double(v) / Double(max(1, top)), of: plot.height, px: px) }
                for step in 0...4 {
                    let v = top / 4 * Int64(step)
                    var x0 = plot.minX
                    while x0 < plot.maxX { context.fill(Path(CGRect(x: x0, y: y(v), width: px / 2, height: px / 2)), with: .color(theme.color(.separator, scheme))); x0 += px * 3 }
                    context.draw(Text(Formatting.compact(v)).font(theme.font(.micro)).foregroundColor(secondary), at: CGPoint(x: plot.minX - theme.spacing(.standard), y: y(v)), anchor: .trailing)
                }
                if let hover, hover < buckets.count {
                    context.fill(Path(PixelColumns.slot(hover, of: buckets.count, in: plot)), with: .color(theme.color(.surfaceMuted, scheme)))
                }
                var lastLabelX = -CGFloat.infinity
                for (i, b) in buckets.enumerated() {
                    let (x, barWidth) = PixelColumns.bar(i, of: buckets.count, in: plot, share: 0.72, px: px)
                    // A pixel bar: each model's part ends on the pixel grid (at least one pixel tall), and the whole stack
                    // takes the stepped top of the other bar charts.
                    var base = plot.maxY, sum: Int64 = 0
                    var parts: [(index: Int, rect: CGRect)] = []
                    for (m, v) in b.byModel.enumerated() where v > 0 {
                        sum += v
                        let top = min(y(sum), base - px)
                        parts.append((m, CGRect(x: x, y: top, width: barWidth, height: base - top)))
                        base = top
                    }
                    if !parts.isEmpty {
                        context.drawLayer { layer in
                            layer.clip(to: PixelColumns.shape(CGRect(x: x, y: base, width: barWidth, height: plot.maxY - base), px: px))
                            for part in parts {
                                guard let highlight, stacked, series.ids[part.index] != highlight else {
                                    ModelStyle.fill(&layer, part.rect, index: part.index, theme: theme, scheme: scheme); continue
                                }
                                layer.drawLayer { dim in
                                    dim.opacity = 0.3
                                    ModelStyle.fill(&dim, part.rect, index: part.index, theme: theme, scheme: scheme)
                                }
                            }
                        }
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
            .accessibilityLabel(Copy.Stats.chartSummary(days: StatsSummary.Day.between(from, to) + 1, models: series.ids.count))
            .chartKeyboard($hover, count: buckets.count, readout: hover == nil ? nil : readout(buckets))
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
        if let highlight, let i = series.ids.firstIndex(of: highlight), i < b.byModel.count {
            return Copy.ModelsPage.chartHighlight(when, name: series.names[i], value: Formatting.compact(b.byModel[i]),
                                                  all: Formatting.compact(b.byModel.reduce(0, +)))
        }
        let parts = zip(series.names, b.byModel).filter { $0.1 > 0 }.map { "\($0.0) \(Formatting.compact($0.1))" }
        return parts.isEmpty ? "\(when) · \(Copy.Stats.noTokens)" : "\(when) · \(parts.joined(separator: " · "))"
    }

    /// 1, 2 or 5 × a power of ten at or above `v`, so the scale reads in round numbers.
    nonisolated static func niceCeiling(_ v: Int64) -> Int64 {
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
