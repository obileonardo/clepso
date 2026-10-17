import AppKit
import DesignSystem
import Domain
import SwiftUI

/// The `MenuBarExtra` window (UX_SPEC §3 depth 1–2): overview, provider detail and the provenance inspector
/// as pages of one panel, so Escape always steps back one level and focus stays inside the popover.
public struct PopoverView: View {
    let model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            switch model.popoverRoute {
            case .overview:
                header(snapshot)
                problemBanner
                overview(snapshot)
            case .detail:
                if let provider = snapshot.provider { ProviderDetailView(model: model, provider: provider, now: snapshot.now) }
                else { header(snapshot); overview(snapshot) }
            case .inspector(let key, let fromDetail):
                if let row = snapshot.provider?.pools.first(where: { $0.poolKey == key }) {
                    InspectorView(row: row, provider: snapshot.provider, isDemo: snapshot.isDemo, now: snapshot.now,
                                  zone: model.environment.timeZone, locale: model.environment.locale) {
                        model.popoverRoute = fromDetail ? .detail : .overview
                    }
                } else { header(snapshot); overview(snapshot) }
            }
            footer(snapshot)
        }
        .padding(theme.spacing(.windowPadding))
        .frame(width: PopoverMetrics.width, alignment: .topLeading)
        .background(theme.color(.background, scheme))
        .overlay(PixelScanlines())
        .environment(\.isFixtureData, snapshot.isDemo)
        .environment(\.displayTimeZone, model.environment.timeZone)
        .onExitCommand { back() }
    }

    // MARK: - Overview

    /// One line: name, provider and plan (opens provider detail), and freshness. The aggregate line is the icon's
    /// accessibility label and the help text, so it isn't repeated here.
    func header(_ snapshot: OverviewSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
            DemoTag()
            Text(Copy.Header.title.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
            if let provider = snapshot.provider {
                Button { model.popoverRoute = .detail } label: {
                    HStack(spacing: theme.spacing(.compact)) {
                        Text("· " + provider.identity.wordmark).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                        PlanPill(planName: provider.planName.map(PopoverMetrics.shortPlan), provenance: provider.plan).fixedSize()
                        Image(systemName: "chevron.right").font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows provider details")
            }
            Spacer(minLength: theme.spacing(.standard))
            if let updated = snapshot.updatedAt {
                Text(Copy.Header.updated(Formatting.age(of: updated, now: snapshot.now, zone: model.environment.timeZone,
                                                        locale: model.environment.locale)).uppercased())
                    .font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme)).lineLimit(1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder var problemBanner: some View {
        switch model.problem {
        case .socket:
            Banner(text: Copy.Problem.socket, action: Copy.Problem.socketCTA) { model.reconnect() }
        case .storage:
            Banner(text: Copy.Problem.storage, action: nil) {}
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder func overview(_ snapshot: OverviewSnapshot) -> some View {
        switch snapshot.empty {
        case .notConnected:
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                Text(Copy.Empty.noProviderTitle).font(theme.font(.label).weight(.semibold))
                Text(Copy.Empty.noProviderBody).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                HStack {
                    Button(Copy.Empty.noProviderCTA) { openOnboarding(at: .provider) }.buttonStyle(PixelButtonStyle(prominent: true))
                    Button(Copy.Onboarding.firstReadingDemo) { Task { await model.setDemo(true) } }.buttonStyle(PixelButtonStyle())
                }
            }
        case .waitingForFirstReading:
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                Text(Copy.Onboarding.firstReadingWaiting).font(theme.font(.supporting)).fixedSize(horizontal: false, vertical: true)
                Button(Copy.Onboarding.firstReadingDemo) { Task { await model.setDemo(true) } }.buttonStyle(PixelButtonStyle())
            }
        case nil:
            if let provider = snapshot.provider {
                // The header's DEMO tag marks the whole panel; rows don't repeat it.
                VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                    // Limits side by side: the panel grows sideways instead of downwards.
                    HStack(alignment: .top, spacing: theme.spacing(.spacious)) {
                        ForEach(provider.pools) { row in
                            Button { model.popoverRoute = .inspector(poolKey: row.poolKey, fromDetail: false) } label: {
                                PixelLimitRow(model: row.model, now: snapshot.now, pace: PaceText.make(row.pace, model: model))
                                    .padding(theme.spacing(.standard) + theme.spacing(.compact))
                                    .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.surfaceElevated, scheme)))
                                    .overlay(PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(.separator, scheme), lineWidth: theme.stroke(.hairline)))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .top)
                            .accessibilityHint("Shows where this number comes from")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if let session = provider.sessions.first { SessionStrip(session: session, agents: snapshot.agents) }
                }
                .environment(\.isFixtureData, false)
            }
        }
    }

    // MARK: - Footer and navigation

    /// DASHBOARD opens the window, where settings, notifications and stats live; QUIT is the only other action here.
    func footer(_ snapshot: OverviewSnapshot) -> some View {
        HStack(spacing: theme.spacing(.standard)) {
            Button(Copy.Details.dashboard) { openDashboard(.home) }.buttonStyle(PixelButtonStyle(prominent: true))
            if snapshot.isDemo {
                Button(Copy.Demo.exit) { Task { await model.setDemo(false) } }.buttonStyle(PixelButtonStyle())
            }
            Spacer()
            Button(Copy.Footer.quit) { NSApp.terminate(nil) }
                .buttonStyle(.borderless).font(theme.font(.micro)).textCase(.uppercase)
                .foregroundStyle(theme.color(.textSecondary, scheme))
        }
    }

    /// Opens the Dashboard window on a section.
    func openDashboard(_ section: AppModel.DetailsSection) {
        model.detailsSection = section
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: PulseScenes.detailsID)
    }

    func back() {
        switch model.popoverRoute {
        case .overview: dismiss()
        case .detail: model.popoverRoute = .overview
        case .inspector(_, let fromDetail): model.popoverRoute = fromDetail ? .detail : .overview
        }
    }

    func openOnboarding(at step: AppModel.OnboardingStep) {
        model.onboardingStep = step
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: PulseScenes.onboardingID)
    }
}

enum PopoverMetrics {
    /// Wide rather than tall (founder review, 17 Oct): the two limits sit side by side.
    static let width: CGFloat = 580
    /// "Claude Max 5×" → "Max 5×": the card already names the provider.
    static func shortPlan(_ name: String) -> String { name.hasPrefix("Claude ") ? String(name.dropFirst("Claude ".count)) : name }
}

/// One problem line with an optional fix (UX_SPEC §2.5).
struct Banner: View {
    let text: String
    let action: String?
    let perform: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(theme.color(.statusBlocked, scheme)).accessibilityHidden(true)
            Text(text).font(theme.font(.supporting)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action { Button(action, action: perform) }
        }
        .padding(theme.spacing(.standard))
        .background(RoundedRectangle(cornerRadius: theme.radius(.control)).fill(theme.color(.surfaceMuted, scheme)))
        .accessibilityElement(children: .combine)
    }
}

/// The newest session in one glance: model, context, cost estimate, cache hits, lines and API time.
struct SessionStrip: View {
    let session: SessionDetail
    var agents: AgentsSummary? = nil
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            HStack(spacing: theme.spacing(.standard)) {
                Text((session.modelName ?? Copy.Details.unknownModel).uppercased()).font(theme.font(.title))
                    .foregroundStyle(theme.color(.background, scheme)).lineLimit(1).fixedSize()
                    .padding(.horizontal, theme.spacing(.compact) * 1.5).padding(.vertical, theme.spacing(.compact) / 2)
                    .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.accent, scheme)))
                if let pct = session.contextPct {
                    PixelBar(fraction: NSDecimalNumber(decimal: pct).doubleValue / 100, role: .accent, pattern: .solid, segments: 24)
                    Text(Copy.Details.contextShort(Formatting.percent(pct))).font(theme.font(.supporting)).lineLimit(1).fixedSize()
                        .foregroundStyle(theme.color(.textSecondary, scheme))
                } else {
                    Spacer()
                }
            }
            HStack(alignment: .top, spacing: theme.spacing(.spacious)) {
                PixelStat(session.costUSD.map { $0.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) } ?? "—", Copy.Details.costEstimate)
                PixelStat(session.cacheHitPct.map(Formatting.percent) ?? "—", Copy.Details.cacheHits)
                PixelStat(session.linesAdded.map { "+" + Formatting.compact($0) } ?? "—", Copy.Details.lines)
                PixelStat(session.apiMs.map { Formatting.duration(milliseconds: $0) } ?? "—", Copy.Details.apiTime)
                if let latest = agents?.latest {
                    PixelStat("\(latest.agents)", Copy.Agents.lastTaskShort)
                        .help(Copy.Agents.strip(latest.agents, latest.byType.map { "\($0.name) \($0.count)" }.joined(separator: ", ")))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(theme.spacing(.standard) + theme.spacing(.compact))
        .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.surfaceElevated, scheme)))
        .overlay(PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(.separator, scheme), lineWidth: theme.stroke(.hairline)))
        .accessibilityElement(children: .combine)
    }
}
