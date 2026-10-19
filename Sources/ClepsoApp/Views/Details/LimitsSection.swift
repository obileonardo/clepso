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
                        FactRow(label: Copy.Inspector.codexVersion, value: codex.pools.first?.origin.version ?? "—")
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

    /// Nil once the reported reset time has passed without a fresh reading: "Resets Fri 23:23" read on a Monday looks
    /// like a reset still to come, and the status line already says "Reset expected · awaiting next update".
    func resetLine(_ row: PoolRow) -> String? {
        guard row.model.card != .resetExpected else { return nil }
        return row.model.resetsAt.value.map { Copy.Limits.resets(Formatting.resetTime($0, now: snapshot.now, zone: model.environment.timeZone,
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
            // 2.5: weekly resets only, and only while Calendar actions are on (hidden in Stage A).
            if model.environment.calendarActions, model.calendarEvent(for: row) != nil {
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
                    Button(Copy.CalendarAction.add) { model.addResetToCalendar(row) }.buttonStyle(PixelButtonStyle())
                    Text(Copy.CalendarAction.addSub).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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

/// The span of a limit's chart that no reading covers: from shortly after the newest reading to NOW (founder decision
/// 19 Oct 2026, decision sheet §2, option D). A 3-day-old 100% drawn solid to NOW looked like a live 100%, so the chart
/// hatches this span as it hatches "not watching yet", and shows whether the window's reported reset passed inside it.
struct UnmeasuredSpan: Equatable {
    /// The newest reading.
    let lastReading: Date
    /// Where the hatch starts: a reading stands for the staleness span after it (10 minutes), so ordinary gaps between
    /// turns stay solid.
    let from: Date
    /// The window's reported reset, when it fell after the newest reading and has passed.
    let resetPassed: Date?

    /// Nil while the newest reading is fresh, or when there is none.
    static func make(lastReading: Date?, resetsAt: Date?, now: Date, staleAfter: TimeInterval) -> UnmeasuredSpan? {
        guard let last = lastReading, now.timeIntervalSince(last) > staleAfter else { return nil }
        let reset = resetsAt.flatMap { $0 > last && $0 <= now ? $0 : nil }
        return UnmeasuredSpan(lastReading: last, from: last.addingTimeInterval(staleAfter), resetPassed: reset)
    }

    /// The chart's time axis: the window the reported reset closes (`ChartAxis.window`); when that reset passed less
    /// than a window ago, carried on to NOW, so the reset and NOW are both on the chart.
    static func axis(length: TimeInterval, resetsAt: Date?, now: Date) -> ClosedRange<Date> {
        if let reset = resetsAt, reset < now, reset > now.addingTimeInterval(-length) { return reset.addingTimeInterval(-length)...now }
        return ChartAxis.window(length: length, resetsAt: resetsAt, now: now)
    }
}

/// One limit's window, start to reset: a 0–100% scale, threshold bands at 80% and 95%, the readings as a filled step
/// line, the span before Clepso had readings shaded, NOW where it is, and the pace projection dashed to the reset.
/// After a stale reading the span to NOW is hatched and labelled, never carried on as a line (`UnmeasuredSpan`); a
/// reset that passed in it is a dashed drop, with "reset passed" under NOW.
struct WindowChart: View {
    let row: PoolRow
    let now: Date
    let zone: TimeZone
    let locale: Locale
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var length: TimeInterval { row.poolKey.hasSuffix("five_hour") ? 5 * 3600 : 7 * 86_400 }

    /// The newest reading: the card's measured value, or the history's last point if that is newer.
    var lastReading: Date? { [row.model.used.observedAt, row.history.last?.at].compactMap { $0 }.max() }

    var unmeasured: UnmeasuredSpan? {
        UnmeasuredSpan.make(lastReading: lastReading, resetsAt: row.model.resetsAt.value, now: now, staleAfter: Freshness.localTelemetryTTL)
    }

    var body: some View {
        let window = UnmeasuredSpan.axis(length: length, resetsAt: row.model.resetsAt.value, now: now)
        let points = row.history.filter { $0.at >= window.lowerBound && $0.at <= now }
        let gap = unmeasured
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
            // A span without readings: hatched, labelled where the label fits clear of the scale.
            let hatchColor = theme.color(.separator, scheme).opacity(0.6), micro = theme.font(.micro), clearance = theme.spacing(.spacious) * 2
            func hatch(from: Date, to: Date, label: String) {
                let rect = CGRect(x: x(from), y: plot.minY, width: x(to) - x(from), height: plot.height).intersection(plot)
                guard !rect.isNull, rect.width > 0 else { return }
                var area = context                                      // a copy, so the clip stays with this span
                area.clip(to: Path(rect))
                var lines = Path()
                var x0 = rect.minX - rect.height
                while x0 < rect.maxX { lines.move(to: CGPoint(x: x0, y: rect.maxY)); lines.addLine(to: CGPoint(x: x0 + rect.height, y: rect.minY)); x0 += px * 4 }
                area.stroke(lines, with: .color(hatchColor), lineWidth: px / 2)
                let note = area.resolve(Text(label).font(micro).foregroundColor(secondary))
                if note.measure(in: size).width + clearance < rect.width {
                    area.draw(note, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
                }
            }
            // Before the first reading inside the window: Clepso was not watching. When the newest reading is older than
            // the whole window, the window is all "no reading since" instead.
            let firstAt = points.first?.at ?? (gap == nil ? now : window.lowerBound)
            if firstAt > window.lowerBound { hatch(from: window.lowerBound, to: firstAt, label: Copy.Details.notWatching) }
            if let gap {
                hatch(from: max(gap.from, window.lowerBound), to: min(now, window.upperBound), label: Copy.Details.noReadingSince(pastTime(gap.lastReading)))
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
                let nowX = x(min(max(now, window.lowerBound), window.upperBound))
                // The line runs to NOW while the newest reading is fresh; after a stale one it stops where the hatch starts.
                let solidEnd = gap.map { min(max($0.from, window.lowerBound), now) } ?? now
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
                    let end = max(solidEnd, last.at)
                    line.addLine(to: CGPoint(x: x(end), y: y(last.usedPct)))
                    area.addLine(to: CGPoint(x: x(end), y: y(last.usedPct))); area.addLine(to: CGPoint(x: x(end), y: plot.maxY)); area.closeSubpath()
                    context.fill(area, with: .color(accent.opacity(0.18)))
                    context.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: px, lineCap: .square, lineJoin: .miter))
                    if let gap {
                        // The newest reading as one pixel block, so a reading minutes long still shows beside the hatch.
                        context.fill(Path(CGRect(x: x(last.at) - px, y: y(last.usedPct) - px, width: px * 2, height: px * 2)), with: .color(accent))
                        // The reset that passed since: a dashed drop to 0% (the window ended; Clepso has no reading after it).
                        if let reset = gap.resetPassed, window.contains(reset) {
                            var drop = Path()
                            drop.move(to: CGPoint(x: x(reset), y: y(last.usedPct))); drop.addLine(to: CGPoint(x: x(reset), y: y(0)))
                            context.stroke(drop, with: .color(theme.color(.textSecondary, scheme)), style: StrokeStyle(lineWidth: px, dash: [px * 2, px * 2]))
                        }
                    } else {
                        // Projection: only from a fresh reading.
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
                }
                // NOW, labelled where it is; "reset passed" just under it when the window's reset passed with no reading since.
                context.fill(Path(CGRect(x: nowX, y: plot.minY, width: px / 2, height: plot.height)), with: .color(theme.color(.textPrimary, scheme).opacity(0.6)))
                // Kept inside the chart when NOW is its right edge (a window that ends now).
                let nowLabel = context.resolve(Text(Copy.Details.now).font(theme.font(.micro)).foregroundColor(theme.color(.textPrimary, scheme)))
                let half = nowLabel.measure(in: size).width / 2
                context.draw(nowLabel, at: CGPoint(x: min(nowX, size.width - half), y: plot.minY - px), anchor: .bottom)
                if gap?.resetPassed != nil {
                    let note = context.resolve(Text(Copy.Details.resetPassed).font(theme.font(.micro)).foregroundColor(theme.color(.textPrimary, scheme)))
                    let width = note.measure(in: size).width + px * 4
                    let left = nowX - width - px * 2 >= plot.minX            // beside NOW, inside the plot, on whichever side fits
                    let origin = CGPoint(x: left ? nowX - px * 2 - width : nowX + px * 2, y: plot.minY + px * 2)
                    let box = CGRect(origin: origin, size: CGSize(width: width, height: note.measure(in: size).height + px * 2))
                    context.fill(Path(box), with: .color(theme.color(.surfaceElevated, scheme)))
                    context.stroke(Path(box), with: .color(theme.color(.separator, scheme)), lineWidth: px / 2)
                    context.draw(note, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
                }
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

    /// A time in the past: the clock today, weekday and time within six days, the date beyond.
    func pastTime(_ date: Date) -> String {
        now.timeIntervalSince(date) < 6 * 86_400 ? Formatting.resetTime(date, now: now, zone: zone, locale: locale)
            : Formatting.age(of: date, now: now, zone: zone, locale: locale)
    }

    /// What VoiceOver reads: the readings in the window, then, after a stale reading, that the span to now is not
    /// measured and whether the window's reset passed in it.
    func summary(_ points: [UsagePoint]) -> String {
        let gap = unmeasured
        var parts: [String]
        if let first = points.first, let last = points.last {
            parts = [Copy.Details.historySummary(scope: row.model.scope, from: Int(first.usedPct.rounded()), to: Int(last.usedPct.rounded()), readings: points.count)]
        } else {
            parts = [gap == nil ? Copy.Details.noHistory(row.model.scope) : Copy.Details.noReadingsInWindow(row.model.scope)]
        }
        if let gap {
            parts.append(Copy.Details.notMeasuredSince(pastTime(gap.lastReading)))
            if let reset = gap.resetPassed { parts.append(Copy.Details.resetPassedAt(pastTime(reset))) }
        }
        return parts.joined(separator: "; ")
    }
}
