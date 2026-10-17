import DesignSystem
import Domain
import SwiftUI
import UsageEngine

/// Every limit: figures on the left, its window drawn on the right (increment 1.8d).
struct LimitsSection: View {
    let model: AppModel
    let snapshot: OverviewSnapshot
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            if let provider = snapshot.provider, !provider.pools.isEmpty {
                ForEach(provider.pools) { row in
                    PixelPanel {
                        HStack(alignment: .top, spacing: theme.spacing(.spacious) * 1.5) {
                            PixelLimitRow(model: row.model, now: snapshot.now, pace: PaceText.make(row.pace, model: model))
                                .frame(width: DetailsMetrics.sideColumn, alignment: .topLeading)
                            WindowChart(row: row, now: snapshot.now, zone: model.environment.timeZone, locale: model.environment.locale)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                Label(provider.unreadLimitWindows > 0 ? Copy.Detail.unreadLimits(provider.unreadLimitWindows) : Copy.Detail.otherLimits,
                      systemImage: "info.circle")
                    .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme)).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Copy.Details.noLimits).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
        }
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
