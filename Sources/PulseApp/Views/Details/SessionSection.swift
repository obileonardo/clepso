import DesignSystem
import Domain
import SwiftUI

/// Session (1.8b; 1.14 in Account's structure): the chosen session's headline figures, its facts, agents per task,
/// recent sessions to choose from, and sessions by model.
struct SessionSection: View {
    let snapshot: OverviewSnapshot
    let zone: TimeZone
    let locale: Locale
    var openProviders: () -> Void = {}
    @State private var selected: String?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        PageColumn {
            if let sessions = snapshot.provider?.sessions, !sessions.isEmpty {
                let current = sessions.first { $0.id == selected } ?? sessions[0]
                PageSection(Copy.SessionPage.current, subtitle(current)) { detail(current) }
                PageSection(Copy.SessionPage.detailsTitle, Copy.SessionPage.detailsSub) { facts(current) }
                PageSection(Copy.Agents.titleShort, Copy.Agents.taskLabel) { agents }
                PageSection(Copy.SessionPage.recentTitle, Copy.SessionPage.recentSub) { list(sessions, current: current) }
                if let groups = snapshot.provider?.models, !groups.isEmpty {
                    PageSection(Copy.SessionPage.byModelTitle, Copy.Details.byModelNote) { byModel(groups) }
                }
            } else {
                PageSection(Copy.SessionPage.current, nil) {
                    Text(Copy.Empty.noSessions).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
                PageSection(Copy.Agents.titleShort, Copy.Agents.taskLabel) { agents }
            }
        }
    }

    func subtitle(_ s: SessionDetail) -> String {
        [s.modelName, s.lastSeen.map { Formatting.age(of: $0, now: snapshot.now, zone: zone, locale: locale) }].compactMap { $0 }.joined(separator: " · ")
    }

    var agents: some View {
        AgentsPanel(summary: snapshot.agents, now: snapshot.now, zone: zone, locale: locale, openProviders: openProviders)
    }

    func list(_ sessions: [SessionDetail], current: SessionDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sessions.prefix(8)) { s in
                let on = s.id == current.id
                Button { selected = s.id } label: {
                    HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
                        Rectangle().fill(on ? theme.color(.accent, scheme) : Color.clear).frame(width: theme.stroke(.emphasis) * 2, height: theme.spacing(.spacious))
                        Text(s.modelName ?? Copy.Details.unknownModel).font(theme.font(.label)).foregroundStyle(theme.color(on ? .textPrimary : .textSecondary, scheme))
                        Text(s.lastSeen.map { Formatting.age(of: $0, now: snapshot.now, zone: zone, locale: locale) } ?? "")
                            .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                        Spacer()
                        Text(lines(s)).font(theme.font(.supporting)).monospacedDigit().foregroundStyle(theme.color(.textSecondary, scheme))
                        Text(s.costUSD.map(money) ?? "—").font(theme.font(.label)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme))
                    }
                    .padding(.vertical, theme.spacing(.standard))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    func detail(_ s: SessionDetail) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                HStack(alignment: .lastTextBaseline) {
                    Text(Copy.Details.context.uppercased()).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                    Spacer()
                    Text(contextLine(s)).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                }
                PixelBar(fraction: s.contextPct.map { NSDecimalNumber(decimal: $0).doubleValue / 100 }, role: .accent, pattern: .solid, segments: 40)
            }
            HStack(alignment: .top, spacing: theme.spacing(.spacious)) {
                Figure(value: s.costUSD.map(money) ?? "—", caption: Copy.Details.costEstimate)
                Figure(value: lines(s), caption: Copy.Details.lines)
                Figure(value: s.cacheHitPct.map(Formatting.percent) ?? "—", caption: Copy.Details.cacheHits)
                Figure(value: s.apiMs.map { Formatting.duration(milliseconds: $0) } ?? "—", caption: Copy.Details.apiTime)
            }
            Text(Copy.Details.costNote).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func facts(_ s: SessionDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FactRow(label: Copy.SessionPage.window, value: s.contextWindow.map { Formatting.compact($0) } ?? "—")
            FactRow(label: Copy.Details.wallTime, value: s.wallMs.map { Formatting.duration(milliseconds: $0) } ?? "—")
            FactRow(label: Copy.Details.apiTime, value: s.apiMs.map { Formatting.duration(milliseconds: $0) } ?? "—"
                    + ((s.wallMs ?? 0) > 0 ? " · " + Copy.SessionPage.apiShare(Int((Double(s.apiMs ?? 0) / Double(s.wallMs ?? 1) * 100).rounded())) : ""))
            FactRow(label: Copy.Details.cacheState, value: s.cacheWarm.map { $0 ? Copy.Details.warm : Copy.Details.cold } ?? "—")
            FactRow(label: Copy.SessionPage.requests, value: s.cacheRequests.map { "\($0) · \(s.cacheMisses ?? 0) miss" } ?? "—")
        }
    }

    func byModel(_ groups: [ModelGroup]) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            ForEach(groups) { g in
                VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                    HStack {
                        Text(g.name).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                        Spacer()
                        Text(Copy.Details.groupLine(sessions: g.sessions, cost: money(g.costUSD), lines: Formatting.compact(g.linesAdded),
                                                    api: Formatting.duration(milliseconds: g.apiMs), share: Int((g.share * 100).rounded())))
                            .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    }
                    PixelBar(fraction: g.share, role: .accent, pattern: .solid, segments: 40)
                }
                .accessibilityElement(children: .combine)
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
