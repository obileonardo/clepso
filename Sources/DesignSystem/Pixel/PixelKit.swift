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
                        .padding(.vertical, -theme.spacing(.compact) * 1.5)
                    Text("%").font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textSecondary, scheme))
                        .padding(.vertical, -theme.spacing(.compact) * 1.5)       // 1.15: the pixel face's tall line box, trimmed
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
                .buttonStyle(PixelPlainButtonStyle())
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
/// and a Less → More legend. Levels 0 (none) … 4 (busiest); nil is outside the range. Each day is a `PixelLevelTile`.
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

    /// The column pitch, and the tile inside it: an odd number of whole pixels, the rest is the gap.
    var cell: CGFloat { theme.spacing(.spacious) + theme.spacing(.compact) / 2 }
    var tile: CGFloat { PixelDensity.tile(fitting: cell - theme.stroke(.hairline) * 3, px: theme.stroke(.hairline) * 2) }

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
                        let px = theme.stroke(.hairline) * 2
                        for (w, week) in weeks.enumerated() {
                            for (d, level) in week.enumerated() {
                                guard let level else { continue }
                                let rect = CGRect(x: CGFloat(w) * cell, y: CGFloat(d) * cell, width: tile, height: tile)
                                context.fill(PixelTile(px: px).path(in: rect), with: .color(theme.color(.surfaceMuted, scheme)))
                                context.fill(PixelDither(level: level, px: px).path(in: rect), with: .color(theme.color(.accent, scheme)))
                            }
                        }
                    }
                    .frame(width: cell * CGFloat(weeks.count), height: cell * 7)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: theme.spacing(.compact)) {
                Text("LESS").font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                ForEach(0..<5, id: \.self) { level in PixelLevelTile(level: level).frame(width: tile, height: tile) }
                Text("MORE").font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement()
        .accessibilityLabel(summary)
    }
}

/// Activity as pixel density (founder, 19 Oct 2026: "make the squares look pixelated, from less to more"). A level is
/// drawn like a 1-bit ordered dither on the design system's 2 pt pixel grid (`PixelBar`'s dither and `PixelRect`'s
/// steps use the same pixel): level 1 is a few lit pixels, 2 a checkerboard, 3 solid with a few holes, 4 solid. The
/// pattern says the level without relying on shade, and the lit share (about 20, 55, 80 and 100 %) keeps the old
/// brightness ramp when the eye blends the pixels. Tiles are an odd number of pixels square, so every pattern sits
/// centred, and lose one pixel at each corner, pixel-art rounding.
public enum PixelDensity {
    /// Whether pixel (`column`, `row`) of an `count` × `count` tile is lit at `level` (0 none … 4 all).
    public static func isLit(level: Int, column c: Int, row r: Int, count n: Int) -> Bool {
        guard level > 0, (0..<n).contains(c), (0..<n).contains(r) else { return false }
        if (c == 0 || c == n - 1) && (r == 0 || r == n - 1) { return false }        // the notched corners
        let hole = c % 2 == 1 && r % 2 == 1                                           // the odd–odd lattice, centred
        switch level {
        case 1: return hole
        case 2: return (c + r) % 2 == 1
        case 3: return !hole
        default: return true
        }
    }

    /// The pixel for a tile `size` wide: the 2 pt pixel (`px`), or a hairline when five 2 pt pixels don't fit.
    public static func unit(for size: CGFloat, px: CGFloat) -> CGFloat { size >= px * 5 ? px : px / 2 }

    /// The largest tile no wider than `limit`: an odd number (at least five) of whole pixels.
    public static func tile(fitting limit: CGFloat, px: CGFloat) -> CGFloat {
        func odd(_ n: Int) -> Int { n % 2 == 0 ? n - 1 : n }
        let big = odd(Int((limit / px).rounded(.down)))
        if big >= 5 { return CGFloat(big) * px }
        return CGFloat(max(5, odd(Int((limit / (px / 2)).rounded(.down))))) * px / 2
    }

    /// The pixel grid inside `rect`: its pixel size, its count per side (odd), and its top-left corner on whole points,
    /// centred. A rect sized by `tile(fitting:px:)` is filled exactly.
    static func grid(in rect: CGRect, px: CGFloat) -> (origin: CGPoint, count: Int, unit: CGFloat) {
        let side = min(rect.width, rect.height), unit = unit(for: side, px: px)
        var n = max(1, Int((side / unit).rounded(.down)))
        if n % 2 == 0 { n -= 1 }
        let margin = CGPoint(x: ((rect.width - CGFloat(n) * unit) / 2).rounded(.down), y: ((rect.height - CGFloat(n) * unit) / 2).rounded(.down))
        return (CGPoint(x: rect.minX + margin.x, y: rect.minY + margin.y), n, unit)
    }
}

/// A square tile with one pixel cut from each corner, on `PixelDensity`'s grid: a day's ground, or its outline.
public struct PixelTile: InsettableShape {
    let px: CGFloat
    var inset: CGFloat = 0
    public init(px: CGFloat) { self.px = px }

    public func path(in rect: CGRect) -> Path {
        let g = PixelDensity.grid(in: rect, px: px), side = CGFloat(g.count) * g.unit, u = g.unit
        let r = CGRect(origin: g.origin, size: CGSize(width: side, height: side)).insetBy(dx: inset, dy: inset)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + u, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - u, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX - u, y: r.minY + u))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + u)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - u))
        p.addLine(to: CGPoint(x: r.maxX - u, y: r.maxY - u)); p.addLine(to: CGPoint(x: r.maxX - u, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + u, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX + u, y: r.maxY - u))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - u)); p.addLine(to: CGPoint(x: r.minX, y: r.minY + u))
        p.addLine(to: CGPoint(x: r.minX + u, y: r.minY + u)); p.closeSubpath()
        return p
    }

    public func inset(by amount: CGFloat) -> PixelTile { var copy = self; copy.inset += amount; return copy }
}

/// The lit pixels of a level (see `PixelDensity`), each a whole-point square.
public struct PixelDither: Shape {
    let level: Int
    let px: CGFloat
    public init(level: Int, px: CGFloat) {
        self.level = level
        self.px = px
    }

    public func path(in rect: CGRect) -> Path {
        let g = PixelDensity.grid(in: rect, px: px)
        var p = Path()
        for r in 0..<g.count {
            for c in 0..<g.count where PixelDensity.isLit(level: level, column: c, row: r, count: g.count) {
                p.addRect(CGRect(x: g.origin.x + CGFloat(c) * g.unit, y: g.origin.y + CGFloat(r) * g.unit, width: g.unit, height: g.unit))
            }
        }
        return p
    }
}

/// One day of an activity calendar: lit accent pixels for its level on a muted tile, or, with no level (no data:
/// before the history or after today), only the tile's outline. Size it with `PixelDensity.tile(fitting:px:)`.
public struct PixelLevelTile: View {
    let level: Int?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(level: Int?) { self.level = level }

    public var body: some View {
        let px = theme.stroke(.hairline) * 2
        if let level {
            ZStack {
                PixelTile(px: px).fill(theme.color(.surfaceMuted, scheme))
                PixelDither(level: level, px: px).fill(theme.color(.accent, scheme))
            }
        } else {
            PixelTile(px: px).strokeBorder(theme.color(.separator, scheme), lineWidth: theme.stroke(.hairline))
        }
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
                .buttonStyle(PixelPlainButtonStyle())
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
        .buttonStyle(PixelPlainButtonStyle())
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A checkbox in the pixel style: an empty box, or the ticked box in the accent colour, with its label beside it.
/// For choosing several things at once (what "Delete Clepso data" removes); a switch stays for settings.
public struct PixelCheckboxStyle: ToggleStyle {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
                PixelIcon(on ? .checkSquare : .square)
                    .foregroundStyle(theme.color(on ? .accent : .textSecondary, scheme))
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.bottom] - 1 }
                configuration.label
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PixelPlainButtonStyle())
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// 1.15: the quiet tier under `PixelButtonStyle`: no frame, small capitals in the secondary colour, brightening on hover
/// and press. For actions that should be reachable but never compete (Quit, Exit demo, Show more).
public struct PixelQuietButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { QuietBody(configuration: configuration) }

    struct QuietBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.theme) private var theme
        @Environment(\.colorScheme) private var scheme
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused

        var body: some View {
            let px = theme.stroke(.hairline) * 2
            configuration.label
                .font(theme.font(.micro))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(theme.color(hovering || configuration.isPressed ? .textPrimary : .textSecondary, scheme))
                .padding(.horizontal, theme.spacing(.standard))
                .padding(.vertical, theme.spacing(.compact) + px)
                .background(PixelRect(step: px).fill(theme.color(.surfaceMuted, scheme).opacity(hovering ? 1 : 0)))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }                  // hover-ok: brightens only; focus has its ring
                .pixelFocusRing(focused)
        }
    }
}
