import DesignSystem
import Foundation
import IntegrationSnapshot
import SwiftUI

struct CompanionLimitsView: View {
    let envelope: RelayEnvelope?
    let now: Date
    let emptyMessage: String
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            if let envelope {
                Text(envelope.isCurrent(at: now) ? "Latest shared reading" : "OLD SNAPSHOT · Awaiting refresh")
                    .font(theme.font(.supporting)).foregroundStyle(theme.color(envelope.isCurrent(at: now) ? .textSecondary : .statusStale, scheme))
                ForEach(Array(envelope.snapshot.limits.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                        Text(row.provider.displayName.uppercased()).font(theme.font(.title))
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.window.displayName).font(theme.font(.label)).fixedSize()
                                Spacer(minLength: theme.spacing(.compact))
                                percentage(row).fixedSize()
                            }
                            VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                                Text(row.window.displayName).font(theme.font(.label))
                                percentage(row)
                            }
                        }
                        HStack(spacing: theme.stroke(.hairline)) {
                            ForEach(0..<20) { index in
                                Rectangle().fill(theme.color(envelope.isCurrent(at: now) && row.state == .reported && row.freshness(at: now) == "fresh" && row.usedPercent.map { Double(index) / 20 < min(max($0 / 100, 0), 1) } == true ? .accent : .separator, scheme))
                            }
                        }.frame(height: theme.spacing(.standard))
                            .accessibilityHidden(true)
                        Text(detail(row, current: envelope.isCurrent(at: now)))
                            .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(theme.spacing(.standard))
                    .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.surfaceMuted, scheme)))
                    .accessibilityElement(children: .combine)
                }
                if envelope.snapshot.limits.isEmpty {
                    Text("Waiting for a reported limit. Connect a reader on the Mac.").font(theme.font(.label))
                }
            } else {
                Text(emptyMessage).font(theme.font(.label)).fixedSize(horizontal: false, vertical: true)
            }
        }.foregroundStyle(theme.color(.textPrimary, scheme))
    }
    private func percentage(_ row: UsageSnapshot.Limit) -> some View {
        Text(row.usedPercent.map { Formatting.percent(Decimal($0)) } ?? "—")
            .font(theme.font(.metricMedium)).monospacedDigit()
    }
    func detail(_ row: UsageSnapshot.Limit, current: Bool) -> String {
        var parts = [row.source == .manual ? "Entered manually" : "Automatic reading"]
        switch row.effectiveState(at: now) {
        case .resetExpected: parts.append("Reset expected · awaiting a reading")
        case .disconnected: parts.append("Reader disconnected · waiting for a report")
        case .invalid: parts.append("Reader error · any value shown is a previous report")
        case .missing: parts.append("Usage not reported")
        case .reported:
            if row.usedPercent == nil { parts.append("Usage not reported") }
            if let reset = row.resetsAt { parts.append("Expected reset " + reset.formatted(date: .abbreviated, time: .shortened)) }
        }
        if !current || row.freshness(at: now) == "stale" { parts.append("Old reading") }
        if let observed = row.observedAt { parts.append("Read " + observed.formatted(date: .abbreviated, time: .shortened)) }
        else { parts.append("Never read") }
        return parts.joined(separator: " · ")
    }
}
