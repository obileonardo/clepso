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
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.window.displayName).font(theme.font(.label))
                            Spacer(minLength: theme.spacing(.compact))
                            Text(row.usedPercent.map { Formatting.percent(Decimal($0)) } ?? "—")
                                .font(theme.font(.metricMedium)).monospacedDigit()
                        }
                        HStack(spacing: theme.stroke(.hairline)) {
                            ForEach(0..<20) { index in
                                Rectangle().fill(theme.color(row.usedPercent.map { Double(index) / 20 < min(max($0 / 100, 0), 1) } == true ? .accent : .surfaceMuted, scheme))
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
    func detail(_ row: UsageSnapshot.Limit, current: Bool) -> String {
        var parts = [row.source == .manual ? "Entered manually" : "Automatic reading"]
        if row.effectiveState(at: now) == .resetExpected { parts.append("Reset expected · awaiting a reading") }
        else if row.usedPercent == nil { parts.append("Usage not reported") }
        else if let reset = row.resetsAt { parts.append("Expected reset " + reset.formatted(date: .abbreviated, time: .shortened)) }
        if !current || row.freshness(at: now) == "stale" { parts.append("Old reading") }
        if let observed = row.observedAt { parts.append("Read " + observed.formatted(date: .abbreviated, time: .shortened)) }
        return parts.joined(separator: " · ")
    }
}
