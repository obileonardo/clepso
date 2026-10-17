import Domain
import SwiftUI

// Increment 1.7e–g: the Phosphor screens' building blocks. Wording, VoiceOver sentences and status rules come from
// the tested components (StatusStyles, ResetCountdown, DataSourceLabel, AccessibilityText); only the look is new.

/// One allowance pool in the pixel style: scope, big number, segmented bar, status, freshness, reset, and an
/// optional pace line. A missing value shows its state in words over an empty outlined bar, never 0%.
public struct PixelLimitRow: View {
    let model: PoolCardModel
    let now: Date
    let pace: String?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.staleAfter) private var staleAfter
    @Environment(\.displayTimeZone) private var zone
    @Environment(\.locale) private var locale
    @Environment(\.isFixtureData) private var isDemo

    public init(model: PoolCardModel, now: Date, pace: String? = nil) {
        self.model = model
        self.now = now
        self.pace = pace
    }

    public var body: some View {
        let state = model.valueState(now: now, staleAfter: staleAfter)
        let card = StatusStyles.of(model.card)
        let pattern: FillPattern = state == .stale ? .hatched : (model.used.value == nil ? StatusStyles.of(state).pattern : card.pattern)
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            HStack(alignment: .lastTextBaseline, spacing: theme.spacing(.standard)) {
                Text(model.scope.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                DemoTag()
                Spacer(minLength: theme.spacing(.standard))
                if let used = model.used.value, state == .live || state == .stale {
                    Text(String(Formatting.percent(used).dropLast())).font(theme.font(.metricHero)).monospacedDigit()
                        .foregroundStyle(theme.color(.textPrimary, scheme))
                    Text("%").font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textSecondary, scheme))
                } else {
                    Text(StatusStyles.of(state).label.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.statusUnknown, scheme))
                }
            }
            PixelBar(fraction: model.used.value.map { min(max(NSDecimalNumber(decimal: $0).doubleValue / 100, 0), 1) },
                     role: state == .stale ? .statusStale : card.role, pattern: pattern)
            HStack(spacing: theme.spacing(.compact)) {
                StatusGlyph(style: card)
                Text(card.label).font(theme.font(.supporting)).foregroundStyle(theme.color(card.role, scheme)).lineLimit(2)
                Spacer(minLength: theme.spacing(.compact))
                DataSourceLabel(source: model.source, observedAt: model.used.observedAt ?? model.resetsAt.observedAt,
                                state: state, showsSource: false, now: now)
            }
            if model.card != .quotaNotAvailable, model.card != .disconnected {
                ResetCountdown(resetsAt: model.resetsAt, card: model.card, now: now)
            }
            if let pace {
                PixelLabel(pace, symbol: "chart.line.uptrend.xyaxis").font(theme.font(.supporting))
                    .foregroundStyle(theme.color(.textSecondary, scheme))
            }
        }
        .fixedSize(horizontal: false, vertical: true)               // wraps; never truncated to fit a short popover
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityText.poolRow(model, now: now, staleAfter: staleAfter, zone: zone, locale: locale, isDemo: isDemo)
                            + (pace.map { ", " + $0 } ?? ""))
    }
}

/// A tab strip in the pixel-pack manner: the selected tab is lit, the rest are recessed. Keyboard: each tab is a button.
public struct PixelTabs<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(_ tabs: [(Tab, String)], selection: Binding<Tab>) {
        self.tabs = tabs
        self._selection = selection
    }

    public var body: some View {
        let px = theme.stroke(.hairline) * 2
        HStack(spacing: px * 2) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { _, tab in
                let selected = tab.0 == selection
                Button { selection = tab.0 } label: {
                    Text(tab.1.uppercased()).font(theme.font(.title))
                        .foregroundStyle(theme.color(selected ? .background : .textSecondary, scheme))
                        .padding(.horizontal, theme.spacing(.windowPadding)).padding(.vertical, theme.spacing(.compact) + px)
                        .background(PixelRect(step: px).fill(theme.color(selected ? .accent : .surfaceMuted, scheme)))
                        .overlay(PixelRect(step: px).strokeBorder(theme.color(.separator, scheme), lineWidth: px))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// A value with a small pixel caption under it.
public struct PixelStat: View {
    let value: String
    let label: String
    let large: Bool
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(_ value: String, _ label: String, large: Bool = false) {
        self.value = value
        self.label = label
        self.large = large
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact) / 2) {
            // The value always outranks its caption: pixel display face, larger than the caption's small caps.
            Text(value).font(large ? theme.font(.metricMedium) : theme.font(.title)).monospacedDigit()
                .foregroundStyle(theme.color(.textPrimary, scheme)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased()).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)       // wraps rather than truncating
        }
        .fixedSize(horizontal: false, vertical: true)               // never squeezed shorter, so figures keep their size
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Faint horizontal scanlines: a Matrix/CRT texture. Decorative, and absent when the user reduces transparency.
public struct PixelScanlines: View {
    @Environment(\.accessibilityReduceTransparency) private var reduce
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        if !reduce {
            Canvas { context, size in
                var y: CGFloat = 0
                let line = theme.color(.textPrimary, scheme).opacity(0.035)
                while y < size.height { context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(line)); y += 3 }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// One series for `PixelLineChart`.
public struct ChartSeries: Sendable, Identifiable {
    public let id: String
    public let points: [(x: Double, y: Double)]
    public let role: ColorToken
    public let opacity: Double
    public init(id: String, points: [(x: Double, y: Double)], role: ColorToken, opacity: Double = 1) {
        self.id = id
        self.points = points
        self.role = role
        self.opacity = opacity
    }
}

/// A step chart on a pixel grid: guide lines at given y values, solid series, and an optional dashed projection.
/// The caller passes an accessibility summary in words; the drawing itself is hidden from VoiceOver.
public struct PixelLineChart: View {
    let series: [ChartSeries]
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
    let guides: [Double]
    let projection: (from: (x: Double, y: Double), to: (x: Double, y: Double))?
    let marker: Double?
    let summary: String
    let guideLabel: ((Double) -> String)?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(series: [ChartSeries], xRange: ClosedRange<Double>, yRange: ClosedRange<Double>, guides: [Double] = [],
                guideLabel: ((Double) -> String)? = nil,
                projection: (from: (x: Double, y: Double), to: (x: Double, y: Double))? = nil, marker: Double? = nil, summary: String) {
        self.series = series
        self.xRange = xRange
        self.yRange = yRange
        self.guides = guides
        self.projection = projection
        self.marker = marker
        self.summary = summary
        self.guideLabel = guideLabel
    }

    public var body: some View {
        let px = theme.stroke(.hairline) * 2
        Canvas { context, size in
            let w = max(xRange.upperBound - xRange.lowerBound, 1e-9), h = max(yRange.upperBound - yRange.lowerBound, 1e-9)
            func point(_ x: Double, _ y: Double) -> CGPoint {
                let px0 = (x - xRange.lowerBound) / w * size.width, py0 = size.height - (y - yRange.lowerBound) / h * size.height
                return CGPoint(x: (px0 / px).rounded() * px, y: (py0 / px).rounded() * px)          // snap to the pixel grid
            }
            // Dotted guides (thresholds) and the frame.
            for g in guides where yRange.contains(g) {
                let y = point(xRange.lowerBound, g).y
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: px, height: px)), with: .color(theme.color(.separator, scheme)))
                    x += px * 3
                }
                if let label = guideLabel?(g), !label.isEmpty {               // drawn just under its line, never clipped
                    context.draw(Text(label).font(theme.font(.micro)).foregroundColor(theme.color(.textSecondary, scheme)),
                                 at: CGPoint(x: size.width, y: y + px * 2), anchor: .topTrailing)
                }
            }
            context.fill(Path(CGRect(x: 0, y: size.height - px, width: size.width, height: px)), with: .color(theme.color(.separator, scheme)))
            if let marker, xRange.contains(marker) {
                let x = point(marker, yRange.lowerBound).x
                context.fill(Path(CGRect(x: x, y: 0, width: px / 2, height: size.height)), with: .color(theme.color(.textSecondary, scheme).opacity(0.5)))
            }
            // Series as steps: hold each value until the next reading.
            for s in series where !s.points.isEmpty {
                var path = Path()
                let sorted = s.points.sorted { $0.x < $1.x }
                path.move(to: point(sorted[0].x, sorted[0].y))
                for (a, b) in zip(sorted, sorted.dropFirst()) {
                    path.addLine(to: point(b.x, a.y))
                    path.addLine(to: point(b.x, b.y))
                }
                context.stroke(path, with: .color(theme.color(s.role, scheme).opacity(s.opacity)), style: StrokeStyle(lineWidth: px, lineCap: .square, lineJoin: .miter))
            }
            if let projection {
                var path = Path()
                path.move(to: point(projection.from.x, projection.from.y))
                path.addLine(to: point(projection.to.x, projection.to.y))
                context.stroke(path, with: .color(theme.color(.statusAttention, scheme)), style: StrokeStyle(lineWidth: px / 2, dash: [px * 2, px * 2]))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(summary)
    }
}

/// A calendar heatmap like /stats: one column per week (Monday on top), small fixed squares, weekday and month labels,
/// and a Less → More legend. Levels 0 (none) … 4 (busiest); nil is outside the range.
public struct PixelHeatmap: View {
    let weeks: [[Int?]]
    let months: [(column: Int, label: String)]
    let summary: String
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(weeks: [[Int?]], months: [(column: Int, label: String)] = [], summary: String) {
        self.weeks = weeks
        self.months = months
        self.summary = summary
    }

    var cell: CGFloat { theme.spacing(.spacious) + theme.spacing(.compact) / 2 }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            HStack(alignment: .top, spacing: theme.spacing(.standard)) {
                VStack(alignment: .trailing, spacing: 0) {
                    Color.clear.frame(width: 1, height: cell)          // month row; fixed width so it never stretches
                    ForEach(0..<7, id: \.self) { d in
                        Text(["MON", "", "WED", "", "FRI", "", ""][d]).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                            .frame(height: cell)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        Color.clear.frame(width: cell * CGFloat(weeks.count), height: cell)
                        ForEach(Array(months.enumerated()), id: \.offset) { _, m in
                            Text(m.label.uppercased()).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                                .fixedSize().offset(x: cell * CGFloat(m.column))
                        }
                    }
                    Canvas { context, _ in
                        let gap = max(theme.stroke(.hairline), cell * 0.18)
                        for (w, week) in weeks.enumerated() {
                            for (d, level) in week.enumerated() {
                                guard let level else { continue }
                                let rect = CGRect(x: CGFloat(w) * cell, y: CGFloat(d) * cell, width: cell - gap, height: cell - gap)
                                context.fill(Path(rect), with: .color(color(level)))
                            }
                        }
                    }
                    .frame(width: cell * CGFloat(weeks.count), height: cell * 7)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: theme.spacing(.compact)) {
                Text("LESS").font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                ForEach(0..<5, id: \.self) { level in
                    Rectangle().fill(color(level)).frame(width: cell * 0.8, height: cell * 0.8)
                }
                Text("MORE").font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement()
        .accessibilityLabel(summary)
    }

    func color(_ level: Int) -> Color {
        level == 0 ? theme.color(.surfaceMuted, scheme) : theme.color(.accent, scheme).opacity([0, 0.3, 0.55, 0.8, 1][min(level, 4)])
    }
}

/// Secondary navigation (increment 1.8c): a compact connected control, visibly lighter than the primary sidebar and
/// tabs so the two levels never look alike. Each segment is a button; the selected one is lit.
public struct PixelSegmented<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option
    let label: String
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(_ label: String, options: [(Option, String)], selection: Binding<Option>) {
        self.label = label
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        let px = theme.stroke(.hairline) * 2
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.0 == selection
                Button { selection = option.0 } label: {
                    Text(option.1.uppercased()).font(theme.font(.micro))
                        .foregroundStyle(theme.color(selected ? .background : .textSecondary, scheme))
                        .padding(.horizontal, theme.spacing(.standard) + px).padding(.vertical, theme.spacing(.compact) + px / 2)
                        .background(selected ? theme.color(.accent, scheme) : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(px)
        .background(PixelRect(step: px).fill(theme.color(.surfaceMuted, scheme)))
        .overlay(PixelRect(step: px).strokeBorder(theme.color(.separator, scheme), lineWidth: px / 2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// A switch in the pixel style (increment 1.11): a stepped track with a square knob, lit when on, "ON"/"OFF" said in
/// words beside it so the state never rests on colour or position alone.
public struct PixelToggleStyle: ToggleStyle {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        let unit = theme.spacing(.compact) + theme.stroke(.hairline)            // 5 pt pixels
        return Button { configuration.isOn.toggle() } label: {
            HStack(spacing: theme.spacing(.standard)) {
                configuration.label
                Text(on ? "ON" : "OFF").font(theme.font(.micro)).foregroundStyle(theme.color(on ? .accent : .textSecondary, scheme))
                    .frame(width: unit * 6, alignment: .trailing)
                ZStack(alignment: on ? .trailing : .leading) {
                    PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(on ? .accent : .surfaceMuted, scheme).opacity(on ? 0.35 : 1))
                    PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(on ? .accent : .separator, scheme), lineWidth: theme.stroke(.hairline))
                    Rectangle().fill(theme.color(on ? .accent : .textSecondary, scheme))
                        .frame(width: unit * 2, height: unit * 2).padding(unit / 2)
                }
                .frame(width: unit * 5, height: unit * 3)
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}
