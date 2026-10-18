import DesignSystem
import Domain
import SwiftUI
import UsageEngine

/// Limits (1.8d; 1.14 in Account's structure): a section per limit with a pixel ring of what's left beside the figure,
/// its status, reset and pace, and its window drawn underneath; then the plan and where the numbers come from.
struct LimitsSection: View {
    let model: AppModel
    let snapshot: OverviewSnapshot
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        PageColumn {
            if let provider = snapshot.provider, !provider.pools.isEmpty {
                ForEach(provider.pools) { row in
                    PageSection(row.model.scope, resetLine(row)) { limit(row) }
                }
                PageSection(Copy.LimitsPage.plan, Copy.LimitsPage.planSub) {
                    VStack(alignment: .leading, spacing: 0) {
                        FactRow(label: Copy.LimitsPage.planName, value: provider.planName ?? Copy.Account.planNotSet)
                        FactRow(label: Copy.LimitsPage.source, value: provider.identity.wordmark + (provider.sourceVersion.map { " " + $0 } ?? ""))
                        FactRow(label: Copy.LimitsPage.lastReading, value: provider.lastSeen.map {
                            Formatting.age(of: $0, now: snapshot.now, zone: model.environment.timeZone, locale: model.environment.locale) } ?? "—")
                        FactRow(label: Copy.LimitsPage.sessions, value: "\(provider.sessionCount)")
                        PixelLabel(provider.unreadLimitWindows > 0 ? Copy.Detail.unreadLimits(provider.unreadLimitWindows) : Copy.Detail.otherLimits,
                                   glyph: provider.unreadLimitWindows > 0 ? .circleAlert : .info)
                            .font(theme.font(.supporting))
                            .foregroundStyle(theme.color(provider.unreadLimitWindows > 0 ? .statusAttention : .textSecondary, scheme))
                            .fixedSize(horizontal: false, vertical: true).padding(.top, theme.spacing(.standard))
                    }
                }
            }
            if let codex = snapshot.codex {
                ForEach(codex.pools) { row in
                    PageSection(Copy.Codex.scope(row.model.scope), resetLine(row)) { limit(row) }
                }
                PageSection(Copy.Codex.factsTitle, Copy.Codex.factsSub) {
                    VStack(alignment: .leading, spacing: 0) {
                        FactRow(label: Copy.Codex.plan, value: codex.plan?.capitalized ?? Copy.Account.planNotSet)
                        FactRow(label: Copy.Codex.model, value: codex.model ?? "—")
                        FactRow(label: Copy.LimitsPage.source, value: Copy.Codex.source)
                        FactRow(label: Copy.Codex.lastReading, value: codex.lastSeen.map {
                            Formatting.age(of: $0, now: snapshot.now, zone: model.environment.timeZone, locale: model.environment.locale) } ?? "—")
                    }
                }
            }
            if (snapshot.provider?.pools.isEmpty ?? true) && snapshot.codex == nil {
                PageSection(Copy.Details.limits, nil) {
                    Text(Copy.Details.noLimits).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
        }
    }

    func resetLine(_ row: PoolRow) -> String? {
        row.model.resetsAt.value.map { Copy.Limits.resets(Formatting.resetTime($0, now: snapshot.now, zone: model.environment.timeZone,
                                                                              locale: model.environment.locale)) }
    }

    func limit(_ row: PoolRow) -> some View {
        let used = row.model.used.value.map { NSDecimalNumber(decimal: $0).doubleValue }
        let style = StatusStyles.of(row.model.card)
        return VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            HStack(alignment: .center, spacing: theme.spacing(.spacious)) {
                ZStack {
                    PixelRing(fraction: used.map { 1 - $0 / 100 }, role: style.role)
                    VStack(spacing: 0) {
                        Text(used.map { "\(max(0, 100 - Int($0.rounded())))%" } ?? "—").font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                        Text(Copy.LimitsPage.left).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                    }
                }
                .frame(width: theme.spacing(.spacious) * 5.5, height: theme.spacing(.spacious) * 5.5)
                VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                    // The figure at the popover card's hero size, its unit quiet beside it.
                    if let used {
                        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
                            Text("\(Int(used.rounded()))%").font(theme.font(.metricHero)).monospacedDigit()
                                .foregroundStyle(theme.color(.textPrimary, scheme)).padding(.vertical, -theme.spacing(.compact))
                            Text(Copy.LimitsPage.used).font(theme.font(.title)).foregroundStyle(theme.color(.textSecondary, scheme))
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        Text(Copy.LimitsPage.notReported).font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textPrimary, scheme))
                    }
                    Text(style.label).font(theme.font(.label)).foregroundStyle(theme.color(style.role, scheme))
                    if let pace = PaceText.make(row.pace, model: model) {
                        Text(pace).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    }
                }
            }
            WindowChart(row: row, now: snapshot.now, zone: model.environment.timeZone, locale: model.environment.locale)
        }
    }
}

/// A ring of square pixels, lit clockwise from the top for `fraction` (nil: outlined only).
struct PixelRing: View {
    let fraction: Double?
    let role: ColorToken
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let count = 36
            let radius = min(size.width, size.height) / 2 - theme.spacing(.standard)
            let block = radius * 0.16
            let lit = Int(((fraction ?? 0) * Double(count)).rounded())
            for i in 0..<count {
                let angle = Double(i) / Double(count) * 2 * .pi - .pi / 2
                let center = CGPoint(x: size.width / 2 + radius * cos(angle), y: size.height / 2 + radius * sin(angle))
                let rect = CGRect(x: (center.x - block / 2).rounded(), y: (center.y - block / 2).rounded(), width: block, height: block)
                if fraction != nil, i < lit {
                    context.fill(Path(rect), with: .color(theme.color(role, scheme)))
                } else {
                    context.fill(Path(rect), with: .color(theme.color(.surfaceMuted, scheme)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Pace estimate in words; always says "Estimate".
enum PaceText {
    @MainActor
    static func make(_ pace: PaceEstimate, model: AppModel) -> String? {
        switch pace {
        case .reachesLimit(let at):
            Copy.Pace.reaches(Formatting.resetTime(at, now: model.environment.clock.now(), zone: model.environment.timeZone,
                                                   locale: model.environment.locale))
        case .belowAtReset(let pct): Copy.Pace.byReset(Formatting.percent(Decimal(pct.rounded())))
        case .notRising: Copy.Pace.notRising
        case .notEnoughData: nil
        case .atLimit: nil
        }
    }

    /// The card form (1.15): one short line, still marked as an estimate.
    @MainActor
    static func short(_ pace: PaceEstimate, model: AppModel) -> String? {
        switch pace {
        case .reachesLimit(let at):
            Copy.Pace.reachesShort(Formatting.resetTime(at, now: model.environment.clock.now(), zone: model.environment.timeZone,
                                                        locale: model.environment.locale))
        case .belowAtReset(let pct): Copy.Pace.byResetShort(Formatting.percent(Decimal(pct.rounded())))
        case .notRising: Copy.Pace.notRisingShort
        case .notEnoughData, .atLimit: nil
        }
    }
}

/// One limit's window, start to reset: a 0–100% scale, threshold bands at 80% and 95%, the readings as a filled step
/// line, the span before Pulse had readings shaded, NOW where it is, and the pace projection dashed to the reset.
struct WindowChart: View {
    let row: PoolRow
    let now: Date
    let zone: TimeZone
    let locale: Locale
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var length: TimeInterval { row.poolKey.hasSuffix("five_hour") ? 5 * 3600 : 7 * 86_400 }

    var body: some View {
        let window = ChartAxis.window(length: length, resetsAt: row.model.resetsAt.value, now: now)
        let points = row.history.filter { $0.at >= window.lowerBound && $0.at <= now }
        let ticks = ChartAxis.ticks(window, zone: zone, maxTicks: length > 86_400 ? 8 : 6)
        let gutter = theme.spacing(.spacious) * 2.4                     // left: the % scale
        let footer = theme.spacing(.spacious) * 1.2                     // bottom: the time ticks
        let header = theme.spacing(.spacious)                           // top: the NOW label
        Canvas { context, size in
            let plot = CGRect(x: gutter, y: header, width: size.width - gutter, height: size.height - footer - header)
            let span = window.upperBound.timeIntervalSince(window.lowerBound)
            func x(_ d: Date) -> CGFloat { plot.minX + CGFloat(d.timeIntervalSince(window.lowerBound) / span) * plot.width }
            func y(_ pct: Double) -> CGFloat { plot.maxY - CGFloat(min(max(pct, 0), 100) / 100) * plot.height }
            let px = theme.stroke(.hairline) * 2
            let secondary = theme.color(.textSecondary, scheme)

            // Threshold bands (shape and words, not colour alone: the scale names them).
            context.fill(Path(CGRect(x: plot.minX, y: y(100), width: plot.width, height: y(95) - y(100))), with: .color(theme.color(.statusBlocked, scheme).opacity(0.10)))
            context.fill(Path(CGRect(x: plot.minX, y: y(95), width: plot.width, height: y(80) - y(95))), with: .color(theme.color(.statusAttention, scheme).opacity(0.08)))
            // Scale and grid.
            for pct in [0.0, 25, 50, 80, 100] {
                var x0 = plot.minX
                while x0 < plot.maxX {
                    context.fill(Path(CGRect(x: x0, y: y(pct), width: px / 2, height: px / 2)), with: .color(theme.color(.separator, scheme)))
                    x0 += px * 3
                }
                context.draw(Text("\(Int(pct))%").font(theme.font(.micro)).foregroundColor(secondary), at: CGPoint(x: plot.minX - theme.spacing(.standard), y: y(pct)),
                             anchor: .trailing)
            }
            for tick in ticks {
                context.fill(Path(CGRect(x: x(tick), y: plot.maxY, width: px / 2, height: px * 2)), with: .color(theme.color(.separator, scheme)))
                ChartLabel.draw(context, Text(label(tick)).font(theme.font(.micro)).foregroundColor(secondary),
                                centeredAt: x(tick), top: plot.maxY + px * 3, width: size.width)
            }
            // Before the first reading inside the window: Pulse was not watching (hatched, labelled).
            let firstAt = points.first?.at ?? now
            if firstAt > window.lowerBound {
                let gap = CGRect(x: plot.minX, y: plot.minY, width: x(firstAt) - plot.minX, height: plot.height)
                var hatch = Path()
                var x0 = gap.minX - gap.height
                while x0 < gap.maxX { hatch.move(to: CGPoint(x: x0, y: gap.maxY)); hatch.addLine(to: CGPoint(x: x0 + gap.height, y: gap.minY)); x0 += px * 4 }
                context.clip(to: Path(gap))
                context.stroke(hatch, with: .color(theme.color(.separator, scheme).opacity(0.6)), lineWidth: px / 2)
                let note = context.resolve(Text(Copy.Details.notWatching).font(theme.font(.micro)).foregroundColor(secondary))
                if note.measure(in: size).width + theme.spacing(.spacious) * 2 < gap.width {          // only where it fits clear of the scale
                    context.draw(note, at: CGPoint(x: gap.midX, y: gap.midY), anchor: .center)
                }
            }
        }
        .overlay {
            // Readings, fill, NOW and the projection are drawn in a second, unclipped layer.
            Canvas { context, size in
                let plot = CGRect(x: gutter, y: header, width: size.width - gutter, height: size.height - footer - header)
                let span = window.upperBound.timeIntervalSince(window.lowerBound)
                func x(_ d: Date) -> CGFloat { plot.minX + CGFloat(d.timeIntervalSince(window.lowerBound) / span) * plot.width }
                func y(_ pct: Double) -> CGFloat { plot.maxY - CGFloat(min(max(pct, 0), 100) / 100) * plot.height }
                let px = theme.stroke(.hairline) * 2
                let accent = theme.color(.accent, scheme)
                if let first = points.first {
                    var line = Path(), area = Path()
                    line.move(to: CGPoint(x: x(first.at), y: y(first.usedPct)))
                    area.move(to: CGPoint(x: x(first.at), y: plot.maxY)); area.addLine(to: CGPoint(x: x(first.at), y: y(first.usedPct)))
                    var last = first
                    for p in points.dropFirst() {
                        line.addLine(to: CGPoint(x: x(p.at), y: y(last.usedPct))); line.addLine(to: CGPoint(x: x(p.at), y: y(p.usedPct)))
                        area.addLine(to: CGPoint(x: x(p.at), y: y(last.usedPct))); area.addLine(to: CGPoint(x: x(p.at), y: y(p.usedPct)))
                        last = p
                    }
                    line.addLine(to: CGPoint(x: x(now), y: y(last.usedPct)))
                    area.addLine(to: CGPoint(x: x(now), y: y(last.usedPct))); area.addLine(to: CGPoint(x: x(now), y: plot.maxY)); area.closeSubpath()
                    context.fill(area, with: .color(accent.opacity(0.18)))
                    context.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: px, lineCap: .square, lineJoin: .miter))
                    // Projection.
                    let to: (Date, Double)? = switch row.pace {
                    case .reachesLimit(let at): (min(at, window.upperBound), at <= window.upperBound ? 100 : last.usedPct)
                    case .belowAtReset(let pct): (window.upperBound, pct)
                    default: nil
                    }
                    if let to {
                        var dash = Path()
                        dash.move(to: CGPoint(x: x(now), y: y(last.usedPct))); dash.addLine(to: CGPoint(x: x(to.0), y: y(to.1)))
                        context.stroke(dash, with: .color(theme.color(.statusAttention, scheme)), style: StrokeStyle(lineWidth: px, dash: [px * 2, px * 2]))
                    }
                }
                // NOW, labelled where it is.
                let nowX = x(min(max(now, window.lowerBound), window.upperBound))
                context.fill(Path(CGRect(x: nowX, y: plot.minY, width: px / 2, height: plot.height)), with: .color(theme.color(.textPrimary, scheme).opacity(0.6)))
                context.draw(Text(Copy.Details.now).font(theme.font(.micro)).foregroundColor(theme.color(.textPrimary, scheme)),
                             at: CGPoint(x: nowX, y: plot.minY - px), anchor: .bottom)
            }
            .allowsHitTesting(false)
        }
        .frame(height: DetailsMetrics.chartHeight)
        .accessibilityElement()
        .accessibilityLabel(summary(points))
    }

    func label(_ d: Date) -> String {
        var style = Date.FormatStyle(locale: locale, timeZone: zone)
        style = length > 86_400 ? style.weekday(.abbreviated) : style.hour().minute()
        return d.formatted(style).uppercased()
    }

    func summary(_ points: [UsagePoint]) -> String {
        guard let first = points.first, let last = points.last else { return Copy.Details.noHistory(row.model.scope) }
        return Copy.Details.historySummary(scope: row.model.scope, from: Int(first.usedPct.rounded()), to: Int(last.usedPct.rounded()), readings: points.count)
    }
}
