import AppKit
import DesignSystem
import Domain
import Storage
import SwiftUI

/// Provider detail (UX_SPEC §3 depth 2): every pool with its reset, the session, connection health.
struct ProviderDetailView: View {
    let model: AppModel
    let provider: ProviderSection
    let now: Date
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    /// Claude's own usage page, opened in the user's browser; Pulse itself makes no request.
    static let usageURL = URL(string: "https://claude.ai/settings/usage")!

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            BackButton(title: Copy.Header.title) { model.popoverRoute = .overview }
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
                DemoTag()
                Text(provider.header).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(provider.pools) { row in
                Button { model.popoverRoute = .inspector(poolKey: row.poolKey, fromDetail: true) } label: {
                    PixelLimitRow(model: row.model, now: now, pace: PaceText.make(row.pace, model: model)).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows where this number comes from")
            }
            if let session = provider.sessions.first { SessionStrip(session: session) }
            if let first = provider.pools.first {
                ConnectionHealth(source: first.model.source, lastSeen: provider.lastSeen,
                                 state: first.model.valueState(now: now, staleAfter: Freshness.localTelemetryTTL), now: now)
            }
            Label(provider.unreadLimitWindows > 0 ? Copy.Detail.unreadLimits(provider.unreadLimitWindows) : Copy.Detail.otherLimits,
                  systemImage: provider.unreadLimitWindows > 0 ? "exclamationmark.circle" : "info.circle")
                .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
            Text(provider.sessionCount == 0 ? Copy.Empty.noSessions : Copy.Detail.sessions(provider.sessionCount))
                .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {          // stacked: the pixel face is wide
                Button(Copy.Detail.openUsage) { NSWorkspace.shared.open(Self.usageURL) }.buttonStyle(PixelButtonStyle())
                Button(Copy.Detail.changePlan) {
                    model.settingsTab = .plan
                    dismiss()
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .buttonStyle(PixelButtonStyle())
            }
        }
    }
}

/// "Where this number comes from" (UX_SPEC §2.6). Every field is selectable text; nothing is fetched on open.
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
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            BackButton(title: Copy.Header.title, action: back)
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
                DemoTag()
                Text(Copy.Inspector.title.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: theme.spacing(.spacious), verticalSpacing: theme.spacing(.compact)) {
                ForEach(fields, id: \.0) { label, value in
                    GridRow {
                        Text(label).foregroundStyle(theme.color(.textSecondary, scheme))
                        Text(value).foregroundStyle(theme.color(.textPrimary, scheme)).textSelection(.enabled)
                    }
                }
            }
            .font(theme.font(.supporting))
            Text(Copy.Inspector.ttl).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
            VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                Text(Copy.Inspector.recent).font(theme.font(.label).weight(.semibold)).foregroundStyle(theme.color(.textPrimary, scheme))
                ForEach(Array(row.recent.enumerated()), id: \.offset) { _, reading in
                    Text(describe(reading)).font(theme.font(.supporting).monospacedDigit()).foregroundStyle(theme.color(.textPrimary, scheme))
                        .textSelection(.enabled)
                }
            }
            Button(Copy.Inspector.copy) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(details, forType: .string)
            }
            .buttonStyle(PixelButtonStyle())
        }
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

    func describe(_ reading: Store.Reading) -> String {
        let value: String = switch reading.value {
        case .percent(let d): Formatting.percent(d)
        case .absent: Copy.Inspector.absent
        default: "—"
        }
        return "\(value) · \(stamp(reading.observedAt))"
    }

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
        Button(action: action) { Label(title, systemImage: "chevron.backward") }
            .buttonStyle(.borderless)
            .font(theme.font(.label))
            .accessibilityLabel("Back to \(title)")
    }
}
