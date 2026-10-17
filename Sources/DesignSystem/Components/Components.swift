import Domain
import SwiftUI

// The first six components, the DEMO badge and the pattern fill.
// Rules (enforced by `make ci`): no literal colours, paddings or font sizes here; values come from `Theme`.
// Public initializers, labels and accessibility text are locked; layout and styling are the founder's to change.

/// "· Claude Code · 4m ago" or "· last seen 42m ago". Freshness is never omitted.
public struct DataSourceLabel: View {
    let source: SourceDescriptor
    let observedAt: Date?
    let state: ValueState
    let showsSource: Bool
    let now: Date
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayTimeZone) private var zone
    @Environment(\.locale) private var locale

    public init(source: SourceDescriptor, observedAt: Date?, state: ValueState, showsSource: Bool, now: Date) {
        self.source = source
        self.observedAt = observedAt
        self.state = state
        self.showsSource = showsSource
        self.now = now
    }

    public var body: some View {
        Text(text)
            .font(theme.font(.supporting))
            .foregroundStyle(theme.color(state == .stale ? .statusStale : .textSecondary, scheme))
            .lineLimit(1)
    }

    var text: String {
        var parts: [String] = []
        if showsSource { parts.append(source.isEnteredByUser ? "entered by you" : source.displayName) }
        if let observedAt {
            let age = Formatting.age(of: observedAt, now: now, zone: zone, locale: locale)
            parts.append(state == .stale ? "last seen \(age)" : age)
        }
        return parts.joined(separator: " · ")
    }
}

/// One allowance pool: scope, value, bar, source and status. A missing value shows its state in words and an
/// outlined empty bar; there is no way to draw 0% for data that does not exist.
public struct QuotaProgress: View {
    let model: PoolCardModel
    let now: Date
    let showsSource: Bool
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.staleAfter) private var staleAfter
    @Environment(\.displayTimeZone) private var zone
    @Environment(\.locale) private var locale
    @Environment(\.isFixtureData) private var isDemo

    public init(model: PoolCardModel, now: Date, showsSource: Bool = true) {
        self.model = model
        self.now = now
        self.showsSource = showsSource
    }

    public var body: some View {
        let state = model.valueState(now: now, staleAfter: staleAfter)
        let card = StatusStyles.of(model.card)
        let pattern: FillPattern = state == .stale ? .hatched : (model.used.value == nil ? StatusStyles.of(state).pattern : card.pattern)
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.scope).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                Spacer(minLength: theme.spacing(.standard))
                valueText(state)
            }
            PatternBar(fraction: model.used.value.map { min(max(NSDecimalNumber(decimal: $0).doubleValue / 100, 0), 1) },
                       role: state == .stale ? .statusStale : card.role, pattern: pattern)
            HStack(spacing: theme.spacing(.compact)) {
                StatusGlyph(style: card)
                Text(card.label).font(theme.font(.supporting)).foregroundStyle(theme.color(card.role, scheme)).lineLimit(2)
                Spacer(minLength: theme.spacing(.compact))
                DataSourceLabel(source: model.source, observedAt: model.used.observedAt ?? model.resetsAt.observedAt,
                                state: state, showsSource: showsSource, now: now)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityText.poolRow(model, now: now, staleAfter: staleAfter, zone: zone, locale: locale, isDemo: isDemo))
    }

    @ViewBuilder func valueText(_ state: ValueState) -> some View {
        if let used = model.used.value, state == .live || state == .stale {
            Text("\(Formatting.percent(used)) used").font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textPrimary, scheme))
        } else {
            Text(StatusStyles.of(state).label).font(theme.font(.label)).foregroundStyle(theme.color(.statusUnknown, scheme))
        }
    }
}

/// "Resets 5:15 PM · in 2h 15m". At or after the reset time it says "Reset expected · awaiting next update",
/// never "Ready": only a fresh reading can say that.
public struct ResetCountdown: View {
    let resetsAt: Provenanced<Date>
    let card: CardState
    let now: Date
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayTimeZone) private var zone
    @Environment(\.locale) private var locale

    public init(resetsAt: Provenanced<Date>, card: CardState, now: Date) {
        self.resetsAt = resetsAt
        self.card = card
        self.now = now
    }

    public var body: some View {
        HStack(spacing: theme.spacing(.compact)) {
            PixelIcon(symbol: symbol).imageScale(.small)
            Text(text).monospacedDigit()
        }
        .font(theme.font(.supporting))
        .foregroundStyle(theme.color(card == .resetExpected ? .statusAttention : .textSecondary, scheme))
        .accessibilityElement(children: .combine)
    }

    var symbol: String { card == .resetExpected ? StatusStyles.of(CardState.resetExpected).symbol : "arrow.counterclockwise" }

    var text: String {
        if card == .resetExpected { return StatusStyles.of(CardState.resetExpected).label }
        guard let date = resetsAt.value else { return "Reset time not reported" }
        guard let remaining = Formatting.countdown(to: date, now: now) else { return StatusStyles.of(CardState.resetExpected).label }
        return "Resets \(Formatting.resetTime(date, now: now, zone: zone, locale: locale)) · \(remaining)"
    }
}

/// "Max 5× · User confirmed". The plan never sits beside a number without saying how it is known.
public struct PlanPill: View {
    let planName: String?
    let provenance: PlanProvenance
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(planName: String?, provenance: PlanProvenance) {
        self.planName = planName
        self.provenance = provenance
    }

    public var body: some View {
        let style = StatusStyles.of(provenance)
        HStack(spacing: theme.spacing(.compact)) {
            PixelIcon(symbol: style.symbol).imageScale(.small)
            Text([planName, style.label].compactMap { $0 }.joined(separator: " · ")).lineLimit(1)
        }
        .font(theme.font(.micro))
        .foregroundStyle(theme.color(style.role, scheme))
        .padding(.horizontal, theme.spacing(.standard))
        .padding(.vertical, theme.spacing(.compact))
        .background(RoundedRectangle(cornerRadius: theme.radius(.pill)).fill(theme.color(.surfaceMuted, scheme)))
        .overlay(RoundedRectangle(cornerRadius: theme.radius(.pill)).strokeBorder(theme.color(.separator, scheme), style: StrokeStyle(lineWidth: theme.stroke(.hairline),
                                                                                              dash: style.pattern == .outline ? [3, 2] : [])))
        .accessibilityElement(children: .combine)
    }
}

/// "Connected · observed 4m ago". Never "100% connected".
public struct ConnectionHealth: View {
    let source: SourceDescriptor
    let lastSeen: Date?
    let state: ValueState
    let now: Date
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayTimeZone) private var zone
    @Environment(\.locale) private var locale

    public init(source: SourceDescriptor, lastSeen: Date?, state: ValueState, now: Date) {
        self.source = source
        self.lastSeen = lastSeen
        self.state = state
        self.now = now
    }

    public var body: some View {
        let style = StatusStyles.of(state)
        HStack(spacing: theme.spacing(.compact)) {
            PixelIcon(symbol: state == .live ? "checkmark.circle" : style.symbol)
            Text(text).lineLimit(1)
        }
        .font(theme.font(.supporting))
        .foregroundStyle(theme.color(state == .live ? .statusSuccess : style.role, scheme))
        .accessibilityElement(children: .combine)
    }

    var text: String {
        let age = lastSeen.map { Formatting.age(of: $0, now: now, zone: zone, locale: locale) }
        switch state {
        case .live: return "Connected · observed \(age ?? "just now")"
        case .stale: return "No new readings · last seen \(age ?? "never")"
        case .notConnected: return "Not connected"
        case .providerError: return "Couldn't read last update"
        case .notAvailable, .notReportedYet: return "Connected · \(StatusStyles.of(state).label.lowercased())"
        }
    }
}

/// One provider: identity and plan, one row per allowance pool, and the active session.
public struct ProviderCard: View {
    public enum Layout: Sendable { case compact, expanded }
    let identity: ProviderIdentity
    let planName: String?
    let plan: PlanProvenance
    let pools: [PoolCardModel]
    let session: SessionRowModel?
    let layout: Layout
    let now: Date
    let onHeader: (() -> Void)?
    let onPool: ((Int) -> Void)?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.staleAfter) private var staleAfter
    @Environment(\.locale) private var locale

    /// `onHeader` opens provider detail and `onPool` the provenance inspector; without them the card is static.
    public init(identity: ProviderIdentity, planName: String?, plan: PlanProvenance, pools: [PoolCardModel],
                session: SessionRowModel?, layout: Layout, now: Date,
                onHeader: (() -> Void)? = nil, onPool: ((Int) -> Void)? = nil) {
        self.identity = identity
        self.planName = planName
        self.plan = plan
        self.pools = pools
        self.session = session
        self.layout = layout
        self.now = now
        self.onHeader = onHeader
        self.onPool = onPool
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(layout == .compact ? .standard : .spacious)) {
            Tappable(action: onHeader, hint: "Shows provider details") { HStack(spacing: theme.spacing(.standard)) {
                Text(identity.monogram)
                    .font(theme.font(.title))
                    .foregroundStyle(theme.color(.surfaceElevated, scheme))
                    .frame(minWidth: theme.spacing(.spacious) + theme.spacing(.standard),
                           minHeight: theme.spacing(.spacious) + theme.spacing(.standard))
                    .background(Circle().fill(theme.color(.textPrimary, scheme)))
                    .accessibilityHidden(true)
                Text(identity.wordmark).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                Spacer(minLength: theme.spacing(.standard))
                PlanPill(planName: planName, provenance: plan)
            } }
            ForEach(Array(pools.enumerated()), id: \.offset) { index, pool in
                Tappable(action: onPool.map { open in { open(index) } }, hint: "Shows where this number comes from") {
                VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                    QuotaProgress(model: pool, now: now, showsSource: false)
                    // The status line already says "Reset expected"; the countdown adds the time only when there is one ahead.
                    if pool.card != .resetExpected, layout == .expanded || pool.card == .exhausted {
                        ResetCountdown(resetsAt: pool.resetsAt, card: pool.card, now: now)
                    }
                }
                }
            }
            if let session { sessionRow(session) }
            if layout == .expanded, let first = pools.first {
                ConnectionHealth(source: first.source, lastSeen: first.used.observedAt ?? first.resetsAt.observedAt,
                                 state: first.valueState(now: now, staleAfter: staleAfter), now: now)
            }
        }
        .padding(theme.spacing(.windowPadding))
        .background(RoundedRectangle(cornerRadius: theme.radius(.card)).fill(theme.color(.surfaceElevated, scheme)))
        .overlay(RoundedRectangle(cornerRadius: theme.radius(.card)).strokeBorder(theme.color(.separator, scheme), lineWidth: theme.stroke(.hairline)))
        .fixtureBadge()
    }

    func sessionRow(_ s: SessionRowModel) -> some View {
        let context: String = {
            guard let used = s.contextUsed.value else {
                return "Context " + StatusStyles.of(resolve(s.contextUsed, connection: .connected, now: now, staleAfter: staleAfter)).label.lowercased()
            }
            var text = "Context \(Formatting.percent(used))"
            if let tokens = s.contextTokens.value, let window = s.contextWindow.value {
                text += " · \(Formatting.tokens(tokens, locale: locale)) of \(Formatting.tokens(window, locale: locale)) tokens"
            }
            return text
        }()
        return HStack(spacing: theme.spacing(.standard)) {
            PixelIcon(symbol: "text.bubble")
            Text([s.modelName, context].compactMap { $0 }.joined(separator: " · ")).lineLimit(1)
        }
        .font(theme.font(.supporting))
        .foregroundStyle(theme.color(.textSecondary, scheme))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Building blocks

/// A plain button around `content` when there is an action (keyboard focusable, Return activates), else the content alone.
struct Tappable<Content: View>: View {
    let action: (() -> Void)?
    let hint: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        if let action {
            Button(action: action) { content().contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityHint(hint)
        } else {
            content()
        }
    }
}

/// The bar under a pool: fill by fraction plus a non-colour pattern. nil fraction draws only the outline.
struct PatternBar: View {
    let fraction: Double?
    let role: ColorToken
    let pattern: FillPattern
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let height = theme.spacing(.standard)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.color(.surfaceMuted, scheme))
                if let fraction {
                    Capsule()
                        .fill(theme.color(role, scheme))
                        .frame(width: max(geometry.size.width * fraction, fraction > 0 ? height : 0))
                        .overlay {
                            if pattern == .hatched {
                                Hatching(color: theme.color(.surfaceElevated, scheme)).clipShape(Capsule())
                            }
                        }
                }
                if fraction == nil || pattern == .outline || pattern == .dashed {
                    Capsule().strokeBorder(theme.color(role, scheme),
                                           style: StrokeStyle(lineWidth: theme.stroke(.hairline), dash: pattern == .dashed ? [4, 3] : []))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct Hatching: View {
    let color: Color
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 5
            }
            context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 1.5)
        }
    }
}

/// The state's symbol, with its badge when a family shares one shape.
struct StatusGlyph: View {
    let style: StatusStyle
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        PixelIcon(symbol: style.symbol)
            .overlay(alignment: .bottomTrailing) {
                if let badge = style.badge { PixelIcon(symbol: badge).font(theme.font(.micro)).offset(x: 4, y: 3) }
            }
            .foregroundStyle(theme.color(style.role, scheme))
            .font(theme.font(.supporting))
            .accessibilityHidden(true)
    }
}

/// "DEMO" on anything showing fixture or demo data (kickoff rule 8). Removed only by a real observation.
public struct FixtureBadge: ViewModifier {
    @Environment(\.isFixtureData) private var isDemo
    @Environment(\.theme) private var theme
    public func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if isDemo { DemoTag().offset(x: theme.spacing(.compact), y: -theme.spacing(.compact)) }
        }
    }
}

/// The DEMO tag itself, for placing inline beside a title where an overlay would cover text.
/// Renders nothing unless the environment says the data is demo data.
public struct DemoTag: View {
    @Environment(\.isFixtureData) private var isDemo
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        if isDemo {
            Text("DEMO")
                .font(theme.font(.micro).weight(.bold))
                .foregroundStyle(theme.color(.surfaceElevated, scheme))
                .padding(.horizontal, theme.spacing(.compact))
                .background(RoundedRectangle(cornerRadius: theme.radius(.pill)).fill(theme.color(.accent, scheme)))
                .accessibilityLabel("Demo data")
        }
    }
}

extension View {
    public func fixtureBadge() -> some View { modifier(FixtureBadge()) }
}
