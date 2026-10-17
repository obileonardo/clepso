import DesignSystem
import Domain
import SwiftUI

/// The current session in full, recent sessions beside it, and sessions grouped by main model (increment 1.8b).
struct SessionSection: View {
    let snapshot: OverviewSnapshot
    let zone: TimeZone
    let locale: Locale
    var openProviders: () -> Void = {}
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let sessions = snapshot.provider?.sessions, let current = sessions.first {
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                HStack(alignment: .top, spacing: theme.spacing(.spacious)) {
                    currentCard(current).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    recent(sessions).frame(width: DetailsMetrics.sideColumn + theme.spacing(.spacious) * 2)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .fixedSize(horizontal: false, vertical: true)
                agents
                if let groups = snapshot.provider?.models, !groups.isEmpty { byModel(groups) }
            }
        } else {
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                Text(Copy.Empty.noSessions).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                agents
            }
        }
    }

    var agents: some View {
        AgentsPanel(summary: snapshot.agents, now: snapshot.now, zone: zone, locale: locale, openProviders: openProviders)
    }

    func currentCard(_ s: SessionDetail) -> some View {
        PixelPanel {
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                HStack(alignment: .firstTextBaseline) {
                    ModelChip(name: s.modelName)
                    Spacer()
                    if let seen = s.lastSeen {
                        Text(Formatting.age(of: seen, now: snapshot.now, zone: zone, locale: locale)).font(theme.font(.supporting))
                            .foregroundStyle(theme.color(.textSecondary, scheme))
                    }
                }
                VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                    HStack(alignment: .lastTextBaseline) {
                        Text(Copy.Details.context.uppercased()).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                        Spacer()
                        Text(contextLine(s)).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                    }
                    PixelBar(fraction: s.contextPct.map { NSDecimalNumber(decimal: $0).doubleValue / 100 }, role: .accent, pattern: .solid, segments: 40)
                }
                Grid(alignment: .topLeading, horizontalSpacing: theme.spacing(.spacious), verticalSpacing: theme.spacing(.spacious)) {
                    GridRow {
                        PixelStat(s.costUSD.map(money) ?? "—", Copy.Details.costEstimate, large: true)
                        PixelStat(s.apiMs.map { Formatting.duration(milliseconds: $0) } ?? "—", Copy.Details.apiTime, large: true)
                        PixelStat(lines(s), Copy.Details.lines, large: true)
                    }
                    GridRow {
                        PixelStat(s.cacheHitPct.map(Formatting.percent) ?? "—", Copy.Details.cacheHits)
                        PixelStat(s.cacheWarm.map { $0 ? Copy.Details.warm : Copy.Details.cold } ?? "—", cacheLabel(s))
                        PixelStat(s.wallMs.map { Formatting.duration(milliseconds: $0) } ?? "—", Copy.Details.wallTime)
                    }
                }
                Text(Copy.Details.costNote).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func recent(_ sessions: [SessionDetail]) -> some View {
        PixelPanel {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                Text(Copy.Details.recentSessions).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                ForEach(sessions.prefix(8)) { s in
                    VStack(alignment: .leading, spacing: theme.spacing(.compact) / 2) {
                        HStack {
                            Text(s.modelName ?? Copy.Details.unknownModel).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                            Spacer()
                            Text(s.costUSD.map(money) ?? "—").font(theme.font(.label)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme))
                        }
                        Text([s.lastSeen.map { Formatting.age(of: $0, now: snapshot.now, zone: zone, locale: locale) }, Optional(lines(s))]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    }
                    .padding(.vertical, theme.spacing(.compact))
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    func byModel(_ groups: [ModelGroup]) -> some View {
        PixelPanel {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                Text(Copy.Details.byModel).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                ForEach(groups) { g in
                    VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                        HStack {
                            Text(g.name).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                            Spacer()
                            Text(Copy.Details.groupLine(sessions: g.sessions, cost: money(g.costUSD), lines: Formatting.compact(g.linesAdded),
                                                        api: Formatting.duration(milliseconds: g.apiMs), share: Int((g.share * 100).rounded())))
                                .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                        }
                        PixelBar(fraction: g.share, role: .accent, pattern: .solid, segments: 48)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(Copy.Details.byModelNote).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func contextLine(_ s: SessionDetail) -> String {
        let pct = s.contextPct.map(Formatting.percent) ?? "—"
        guard let used = s.tokensIn, let window = s.contextWindow else { return pct }
        return "\(Formatting.compact(used)) of \(Formatting.compact(window)) · \(pct)"
    }
    func money(_ d: Decimal) -> String { d.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) }
    func lines(_ s: SessionDetail) -> String {
        guard s.linesAdded != nil || s.linesRemoved != nil else { return "—" }
        return "+\(Formatting.compact(s.linesAdded ?? 0)) −\(Formatting.compact(s.linesRemoved ?? 0))"
    }
    func cacheLabel(_ s: SessionDetail) -> String {
        guard let requests = s.cacheRequests else { return Copy.Details.cacheState }
        return Copy.Details.cacheCounts(requests: requests, misses: s.cacheMisses ?? 0)
    }
}

/// The model's name in a lit pixel tag.
struct ModelChip: View {
    let name: String?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: theme.spacing(.standard)) {
            Text((name ?? Copy.Details.unknownModel).uppercased()).font(theme.font(.title))
                .foregroundStyle(theme.color(.background, scheme))
                .padding(.horizontal, theme.spacing(.standard)).padding(.vertical, theme.spacing(.compact))
                .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.accent, scheme)))
        }
    }
}
