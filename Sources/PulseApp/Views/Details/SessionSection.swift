import DesignSystem
import Domain
import SwiftUI

/// Session (1.8b, reworked in 1.12 after the founder's Adaline and Gumloop picks): three panes. Sessions on the left;
/// the selected one in the middle (model, context, headline figures, agents per task); its facts on the right as a
/// key/value inspector with time split into API and the rest.
struct SessionSection: View {
    let snapshot: OverviewSnapshot
    let zone: TimeZone
    let locale: Locale
    var openProviders: () -> Void = {}
    @State private var selected: String?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let sessions = snapshot.provider?.sessions, !sessions.isEmpty {
            let current = sessions.first { $0.id == selected } ?? sessions[0]
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                HStack(alignment: .top, spacing: theme.spacing(.spacious)) {
                    PixelPanel { list(sessions, current: current) }.frame(width: DetailsMetrics.sideColumn).frame(maxHeight: .infinity, alignment: .top)
                    PixelPanel { detail(current) }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    PixelPanel { inspector(current) }.frame(width: DetailsMetrics.sideColumn + theme.spacing(.spacious)).frame(maxHeight: .infinity, alignment: .top)
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

    // MARK: Panes

    func list(_ sessions: [SessionDetail], current: SessionDetail) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            Text(Copy.Details.recentSessions).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                .padding(.bottom, theme.spacing(.compact))
            ForEach(sessions.prefix(10)) { s in
                let on = s.id == current.id
                Button { selected = s.id } label: {
                    VStack(alignment: .leading, spacing: theme.spacing(.compact) / 2) {
                        HStack {
                            Text(s.modelName ?? Copy.Details.unknownModel).font(theme.font(.label).weight(on ? .semibold : .regular))
                            Spacer()
                            Text(s.costUSD.map(money) ?? "—").font(theme.font(.label)).monospacedDigit()
                        }
                        .foregroundStyle(theme.color(on ? .textPrimary : .textSecondary, scheme))
                        Text([s.lastSeen.map { Formatting.age(of: $0, now: snapshot.now, zone: zone, locale: locale) }, Optional(lines(s))]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    }
                    .padding(theme.spacing(.standard))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(on ? theme.color(.surfaceMuted, scheme) : Color.clear)
                    .overlay(alignment: .leading) { if on { Rectangle().fill(theme.color(.accent, scheme)).frame(width: theme.stroke(.emphasis) * 2) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    func detail(_ s: SessionDetail) -> some View {
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
                    PixelStat(lines(s), Copy.Details.lines, large: true)
                }
                GridRow {
                    PixelStat(s.cacheHitPct.map(Formatting.percent) ?? "—", Copy.Details.cacheHits, large: true)
                    PixelStat(s.apiMs.map { Formatting.duration(milliseconds: $0) } ?? "—", Copy.Details.apiTime, large: true)
                }
            }
            Text(Copy.Details.costNote).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Gumloop's side sheet: every fact as a labelled row, and time as one bar split into API and the rest.
    func inspector(_ s: SessionDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Copy.SessionPage.details).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme)).padding(.bottom, theme.spacing(.standard))
            fact(Copy.SessionPage.model, s.modelName ?? Copy.Details.unknownModel)
            fact(Copy.SessionPage.window, s.contextWindow.map { Formatting.compact($0) } ?? "—")
            fact(Copy.Details.wallTime, s.wallMs.map { Formatting.duration(milliseconds: $0) } ?? "—")
            fact(Copy.Details.apiTime, s.apiMs.map { Formatting.duration(milliseconds: $0) } ?? "—")
            fact(Copy.Details.cacheState, s.cacheWarm.map { $0 ? Copy.Details.warm : Copy.Details.cold } ?? "—")
            fact(Copy.SessionPage.requests, s.cacheRequests.map { "\($0) · \(s.cacheMisses ?? 0) miss" } ?? "—")
            if let wall = s.wallMs, let api = s.apiMs, wall > 0 {
                VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                    Text(Copy.SessionPage.timeSplit).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                    PixelBar(fraction: min(1, Double(api) / Double(wall)), role: .accent, pattern: .solid, segments: 24)
                    Text(Copy.SessionPage.apiShare(Int((Double(api) / Double(wall) * 100).rounded()))).font(theme.font(.supporting))
                        .foregroundStyle(theme.color(.textSecondary, scheme))
                }
                .padding(.top, theme.spacing(.standard))
            }
            Spacer(minLength: 0)
        }
    }

    func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
            Spacer()
            Text(value).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme)).lineLimit(1)
        }
        .padding(.vertical, theme.spacing(.standard))
        .overlay(alignment: .top) { Rectangle().fill(theme.color(.separator, scheme).opacity(0.6)).frame(height: theme.stroke(.hairline)) }
        .accessibilityElement(children: .combine)
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
