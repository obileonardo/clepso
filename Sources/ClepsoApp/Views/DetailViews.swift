import AppKit
import DesignSystem
import Domain
import Storage
import SwiftUI

/// Provider detail (depth 2): every pool with its reset and pace, the session, connection health.
/// 1.15: a breadcrumb with the plan on one line; the limits as rows of one card; the session card; then one strip of
/// status chips (connection, sessions, which limits are covered) where a sentence used to be. The page's actions live
/// in the popover's action bar.
struct ProviderDetailView: View {
    let model: AppModel
    let provider: ProviderSection
    let now: Date
    @State private var showsCoverage = false
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// Claude's own usage page, opened in the user's browser; Clepso itself makes no request.
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
                    .buttonStyle(PixelPlainButtonStyle())
                    .accessibilityHint("Shows where this number comes from")
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(theme.color(.separator, scheme)).frame(height: theme.stroke(.hairline)) }
                    }
                }
            }
            .clepsoCard()
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
            .buttonStyle(PixelPlainButtonStyle())
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
            .buttonStyle(PixelPlainButtonStyle())
            .accessibilityLabel("Back to \(parent)")
            Text("/").font(theme.font(.micro)).foregroundStyle(theme.color(.separator, scheme)).accessibilityHidden(true)
            Text(title.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                .lineLimit(1).accessibilityAddTraits(.isHeader)
        }
    }
}

/// "Where this number comes from". Every field is selectable text; nothing is fetched on open.
/// 1.15: the number itself first, then its facts as a ruled table, its freshness rule as a chip, and the last
/// readings as rows; Copy details is in the action bar.
struct InspectorView: View {
    let row: PoolRow
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
            .clepsoCard()
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
                .fixedSize()
            Spacer(minLength: theme.spacing(.standard))
            // A long value (a reading's age, "Reset passed …") wraps under itself rather than being cut off.
            Text(value).font(valueFirst ? theme.font(.supporting).monospacedDigit() : theme.font(.supporting))
                .foregroundStyle(theme.color(valueFirst ? .textSecondary : .textPrimary, scheme))
                .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .padding(.vertical, theme.spacing(.compact) + theme.stroke(.hairline))
        .overlay(alignment: .top) {
            if rule { Rectangle().fill(theme.color(.separator, scheme).opacity(0.5)).frame(height: theme.stroke(.hairline)) }
        }
        .accessibilityElement(children: .combine)
    }

    var fields: [(String, String)] {
        let used = row.model.used
        // Founder decision 19 Oct 2026 (decision sheet §3): the reading's age on the row that holds its time, and a row
        // saying its window has already ended, only when it has, so a live reading reads as before.
        let measured = used.observedAt.map { Copy.Inspector.measured(stamp($0), age: Copy.Inspector.ago(now.timeIntervalSince($0))) }
        return [
            (row.model.scope, used.value.map(Formatting.percent) ?? Copy.Inspector.absent),
            (Copy.Inspector.field, row.providerField),
            (Copy.Inspector.source, isDemo ? Copy.Inspector.sourceDemo("(built-in)") : row.origin.source),
            (Copy.Inspector.observedAt, measured ?? "—"),
        ] + (resetPassed.map { [(Copy.Inspector.window, Copy.Inspector.resetPassed(resetStamp($0)))] } ?? []) + [
            (Copy.Inspector.receivedAt, row.receivedAt.map(stamp) ?? "—"),
            (Copy.Inspector.quality, Copy.Inspector.quality(used.value == nil ? .unknown : used.quality)),
            (Copy.Inspector.adapterVersion, row.origin.adapter),
            (row.origin.versionLabel, row.origin.version ?? "—"),
        ]
    }

    /// The reading's reported reset, when it has passed after the reading: the number is from a window that has ended.
    var resetPassed: Date? {
        guard let reset = row.model.resetsAt.value, reset <= now else { return nil }
        if let measured = row.model.used.observedAt, measured >= reset { return nil }
        return reset
    }

    /// A reset time to the minute: "16 Oct 2026 at 22:23" (en_GB).
    func resetStamp(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: zone))
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
