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
                    Text(Copy.Details.context.uppercased()).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
                    Spacer()
                    Text(contextLine(s)).font(theme.font(.label)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme))
                }
                PixelBar(fraction: s.contextPct.map { NSDecimalNumber(decimal: $0).doubleValue / 100 }, role: .accent, pattern: .solid, segments: 40)
            }
            StatCardRow {
                StatCard(caption: Copy.Details.costEstimate, value: s.costUSD.map(money) ?? "—")
                StatCard(caption: Copy.Details.lines, value: lines(s))
                StatCard(caption: Copy.Details.cacheHits, value: s.cacheHitPct.map(Formatting.percent) ?? "—")
                StatCard(caption: Copy.Details.apiTime, value: s.apiMs.map { Formatting.duration(milliseconds: $0) } ?? "—")
            }
            PixelLabel(Copy.Details.costNote, glyph: .info).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
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

    /// 1.15: one aligned table instead of a sentence per model: figures in columns, the share as a meter.
    func byModel(_ groups: [ModelGroup]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: theme.spacing(.spacious), verticalSpacing: theme.spacing(.standard)) {
            GridRow {
                ForEach([Copy.SessionPage.colModel, Copy.SessionPage.colSessions, Copy.SessionPage.colCost, Copy.SessionPage.colLines,
                         Copy.SessionPage.colAPI, Copy.SessionPage.colShare], id: \.self) { head in
                    Text(head.uppercased()).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
            .accessibilityHidden(true)
            ForEach(groups) { g in
                GridRow {
                    Text(g.name).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                    figure("\(g.sessions)")
                    figure(money(g.costUSD))
                    figure("+" + Formatting.compact(g.linesAdded))
                    figure(Formatting.duration(milliseconds: g.apiMs))
                    HStack(spacing: theme.spacing(.standard)) {
                        PixelBar(fraction: g.share, role: .accent, pattern: .solid, segments: 12)
                        Text("\(Int((g.share * 100).rounded()))%").font(theme.font(.label)).monospacedDigit()
                            .foregroundStyle(theme.color(.textPrimary, scheme)).fixedSize()
                    }
                    .gridColumnAlignment(.leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(g.name + ": " + Copy.Details.groupLine(sessions: g.sessions, cost: money(g.costUSD), lines: Formatting.compact(g.linesAdded),
                                                                         api: Formatting.duration(milliseconds: g.apiMs), share: Int((g.share * 100).rounded())))
            }
        }
    }

    func figure(_ text: String) -> some View {
        Text(text).font(theme.font(.label)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme)).lineLimit(1).fixedSize()
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
