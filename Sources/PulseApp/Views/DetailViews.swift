import AppKit
import DesignSystem
import Domain
import Storage
import SwiftUI

/// Provider detail (UX_SPEC §3 depth 2): every pool with its reset and pace, the session, connection health.
/// 1.15: a breadcrumb with the plan on one line; the limits as rows of one card; the session card; then one strip of
/// status chips (connection, sessions, which limits are covered) where a sentence used to be. The page's actions live
/// in the popover's action bar.
struct ProviderDetailView: View {
    let model: AppModel
    let provider: ProviderSection
    let now: Date
    @State private var showsCoverage = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// Claude's own usage page, opened in the user's browser; Pulse itself makes no request.
    static let usageURL = URL(string: "https://claude.ai/settings/usage")!

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard) + theme.spacing(.compact)) {
            HStack(alignment: .center, spacing: theme.spacing(.standard)) {
                Breadcrumb(parent: Copy.Header.title, title: provider.identity.wordmark) { model.popoverRoute = .overview }
                Spacer(minLength: theme.spacing(.standard))
                PlanPill(planName: provider.planName.map(PopoverMetrics.shortPlan), provenance: provider.plan).fixedSize()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(provider.header)
            .padding(.bottom, theme.spacing(.compact))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(provider.pools.enumerated()), id: \.element.id) { index, row in
                    Button { model.popoverRoute = .inspector(poolKey: row.poolKey, fromDetail: true) } label: {
                        PixelLimitRow(model: row.model, now: now, pace: PaceText.make(row.pace, model: model))
                            .padding(.vertical, theme.spacing(.standard))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows where this number comes from")
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(theme.color(.separator, scheme)).frame(height: theme.stroke(.hairline)) }
                    }
                }
            }
            .pulseCard()
            if let session = provider.sessions.first { SessionStrip(session: session) }
            statusStrip
            if showsCoverage || provider.unreadLimitWindows > 0 {
                Text(coverageSentence).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }

    var coverageSentence: String {
        provider.unreadLimitWindows > 0 ? Copy.Detail.unreadLimits(provider.unreadLimitWindows) : Copy.Detail.otherLimits
    }

    /// Connection on the left; how many sessions and which limits this source covers on the right, as chips.
    var statusStrip: some View {
        HStack(alignment: .center, spacing: theme.spacing(.standard)) {
            if let first = provider.pools.first {
                ConnectionHealth(source: first.model.source, lastSeen: provider.lastSeen,
                                 state: first.model.valueState(now: now, staleAfter: Freshness.localTelemetryTTL), now: now)
            }
            Spacer(minLength: theme.spacing(.standard))
            MetaChip(glyph: .terminal, text: provider.sessionCount == 0 ? Copy.Detail.sessionsShort(0) : Copy.Detail.sessionsShort(provider.sessionCount))
                .help(provider.sessionCount == 0 ? Copy.Empty.noSessions : Copy.Detail.sessions(provider.sessionCount))
            Button { withAnimation(theme.motion(.stateChange, reduceMotion: reduceMotion)) { showsCoverage.toggle() } } label: {
                MetaChip(glyph: provider.unreadLimitWindows > 0 ? .circleAlert : .info,
                         text: provider.unreadLimitWindows > 0 ? Copy.Detail.unreadShort(provider.unreadLimitWindows) : Copy.Detail.coverage,
                         role: provider.unreadLimitWindows > 0 ? .statusAttention : .textSecondary, active: showsCoverage)
            }
            .buttonStyle(.plain)
            .help(coverageSentence)
            .accessibilityLabel(coverageSentence)
            .accessibilityHint(Copy.Detail.moreInfo)
        }
    }
}

/// A small fact as a chip: a pixel glyph and a few words in small capitals.
struct MetaChip: View {
    let glyph: PixelGlyph
    let text: String
    var role: ColorToken = .textSecondary
    var active = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let px = theme.stroke(.hairline) * 2
        HStack(spacing: theme.spacing(.compact) + px / 2) {
            PixelIcon(glyph).accessibilityHidden(true)
            Text(text.uppercased()).font(theme.font(.micro)).lineLimit(1).fixedSize()
        }
        .foregroundStyle(theme.color(role, scheme))
        .padding(.horizontal, theme.spacing(.standard))
        .padding(.vertical, theme.spacing(.compact))
        .background(PixelRect(step: px).fill(theme.color(active ? .surfaceMuted : .surfaceElevated, scheme)))
        .overlay(PixelRect(step: px).strokeBorder(theme.color(active ? role : .separator, scheme), lineWidth: theme.stroke(.hairline)))
        .accessibilityElement(children: .combine)
    }
}

/// "‹ AI CAPACITY / CLAUDE": the way back and where you are, on one line.
struct Breadcrumb: View {
    let parent: String
    let title: String
    let back: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: theme.spacing(.standard)) {
            Button(action: back) {
                HStack(spacing: theme.spacing(.compact)) {
                    PixelIcon(.chevronBack)
                    Text(parent.uppercased()).font(theme.font(.micro)).tracking(1)
                }
                .foregroundStyle(theme.color(.textSecondary, scheme))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to \(parent)")
            Text("/").font(theme.font(.micro)).foregroundStyle(theme.color(.separator, scheme)).accessibilityHidden(true)
            Text(title.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                .lineLimit(1).accessibilityAddTraits(.isHeader)
        }
    }
}

/// "Where this number comes from" (UX_SPEC §2.6). Every field is selectable text; nothing is fetched on open.
/// 1.15: the number itself first, then its facts as a ruled table, its freshness rule as a chip, and the last
/// readings as rows; Copy details is in the action bar.
struct InspectorView: View {
    let row: PoolRow
    let provider: ProviderSection?
    let isDemo: Bool
    let now: Date
    let zone: TimeZone
    let locale: Locale
    let back: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard) + theme.spacing(.compact)) {
            Breadcrumb(parent: Copy.Header.title, title: Copy.Inspector.title, back: back)
                .padding(.bottom, theme.spacing(.compact))
            HStack(alignment: .lastTextBaseline, spacing: theme.spacing(.standard)) {
                Text(row.model.scope.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                Spacer(minLength: theme.spacing(.standard))
                Text(fields[0].1).font(theme.font(.metricMedium)).monospacedDigit()
                    .foregroundStyle(theme.color(row.model.used.value == nil ? .statusUnknown : .textPrimary, scheme))
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(fields.dropFirst().enumerated()), id: \.offset) { index, field in ruled(field.0, field.1, rule: index > 0) }
            }
            .pulseCard()
            HStack(spacing: theme.spacing(.standard)) {
                MetaChip(glyph: .clock, text: Copy.Inspector.ttl)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(Copy.Inspector.recent.uppercased()).font(theme.font(.micro)).tracking(1)
                    .foregroundStyle(theme.color(.textSecondary, scheme)).padding(.bottom, theme.spacing(.compact))
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(row.recent.enumerated()), id: \.offset) { _, reading in
                    ruled(value(reading), stamp(reading.observedAt), valueFirst: true)
                }
            }
        }
    }

    /// A label and a value on one line, with a faint rule above.
    func ruled(_ label: String, _ value: String, valueFirst: Bool = false, rule: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.spacious)) {
            Text(label).font(valueFirst ? theme.font(.label).monospacedDigit() : theme.font(.supporting))
                .foregroundStyle(theme.color(valueFirst ? .textPrimary : .textSecondary, scheme))
            Spacer(minLength: theme.spacing(.standard))
            Text(value).font(valueFirst ? theme.font(.supporting).monospacedDigit() : theme.font(.supporting))
                .foregroundStyle(theme.color(valueFirst ? .textSecondary : .textPrimary, scheme))
                .multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .padding(.vertical, theme.spacing(.compact) + theme.stroke(.hairline))
        .overlay(alignment: .top) {
            if rule { Rectangle().fill(theme.color(.separator, scheme).opacity(0.5)).frame(height: theme.stroke(.hairline)) }
        }
        .accessibilityElement(children: .combine)
    }

    var fields: [(String, String)] {
        let used = row.model.used
        return [
            (row.model.scope, used.value.map(Formatting.percent) ?? Copy.Inspector.absent),
            (Copy.Inspector.field, row.providerField),
            (Copy.Inspector.source, isDemo ? Copy.Inspector.sourceDemo("(built-in)") : Copy.Inspector.sourceStatusLine),
            (Copy.Inspector.observedAt, used.observedAt.map(stamp) ?? "—"),
            (Copy.Inspector.receivedAt, row.receivedAt.map(stamp) ?? "—"),
            (Copy.Inspector.quality, Copy.Inspector.quality(used.value == nil ? .unknown : used.quality)),
            (Copy.Inspector.adapterVersion, "Claude Code status line, frame v1"),
            (Copy.Inspector.providerVersion, provider?.sourceVersion ?? "—"),
        ]
    }

    /// Absolute time with seconds and zone, so two readings never look identical.
    func stamp(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale, timeZone: zone))
    }

    func value(_ reading: Store.Reading) -> String {
        switch reading.value {
        case .percent(let d): Formatting.percent(d)
        case .absent: Copy.Inspector.absent
        default: "—"
        }
    }

    func describe(_ reading: Store.Reading) -> String { "\(value(reading)) · \(stamp(reading.observedAt))" }

    /// `Copy details`: the same facts as plain text. Contains no paths, prompts or session ids.
    var details: String {
        (fields.map { "\($0): \($1)" } + [Copy.Inspector.ttl, Copy.Inspector.recent + ":"] + row.recent.map { "  " + describe($0) })
            .joined(separator: "\n")
    }
}

struct BackButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.theme) private var theme
    var body: some View {
        Button(action: action) { PixelLabel(title, symbol: "chevron.backward") }
            .buttonStyle(.borderless)
            .font(theme.font(.label))
            .accessibilityLabel("Back to \(title)")
    }
}
