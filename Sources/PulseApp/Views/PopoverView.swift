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
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
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
            Rectangle().fill(theme.color(.separator, scheme)).frame(height: theme.stroke(.hairline) * 2).accessibilityHidden(true)
            footer
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

    func header(_ snapshot: OverviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
                DemoTag()
                Text(Copy.Header.title.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                Spacer()
                if let updated = snapshot.updatedAt {
                    Text(Copy.Header.updated(Formatting.age(of: updated, now: snapshot.now, zone: model.environment.timeZone,
                                                            locale: model.environment.locale)).uppercased())
                        .font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
            Text(snapshot.aggregateLine)
                .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
                    Button(Copy.Empty.noProviderCTA) { openOnboarding(at: .provider) }.buttonStyle(.borderedProminent)
                    Button(Copy.Onboarding.firstReadingDemo) { Task { await model.setDemo(true) } }
                }
            }
        case .waitingForFirstReading:
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                Text(Copy.Onboarding.firstReadingWaiting).font(theme.font(.supporting)).fixedSize(horizontal: false, vertical: true)
                Button(Copy.Onboarding.firstReadingDemo) { Task { await model.setDemo(true) } }
            }
        case nil:
            if let provider = snapshot.provider {
                VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                    Button { model.popoverRoute = .detail } label: {
                        HStack(spacing: theme.spacing(.standard)) {
                            Text(provider.identity.wordmark.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                            Spacer(minLength: theme.spacing(.standard))
                            PlanPill(planName: provider.planName.map(PopoverMetrics.shortPlan), provenance: provider.plan)
                            Image(systemName: "chevron.right").foregroundStyle(theme.color(.textSecondary, scheme)).accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows provider details")
                    ForEach(provider.pools) { row in
                        Button { model.popoverRoute = .inspector(poolKey: row.poolKey, fromDetail: false) } label: {
                            PixelLimitRow(model: row.model, now: snapshot.now, pace: PaceText.make(row.pace, model: model)).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows where this number comes from")
                    }
                    if let session = provider.sessions.first { SessionStrip(session: session) }
                    HStack(spacing: theme.spacing(.standard)) {
                        Button(Copy.Details.open) { openDetails(.limits) }.buttonStyle(PixelButtonStyle(prominent: true))
                        Button(Copy.Details.openStats) { openDetails(.stats) }.buttonStyle(PixelButtonStyle())
                        Spacer()
                    }
                }
            }
            if snapshot.isDemo {
                Button(Copy.Demo.exit) { Task { await model.setDemo(false) } }.buttonStyle(PixelButtonStyle())
            }
        }
    }

    // MARK: - Footer and navigation

    var footer: some View {
        HStack(spacing: theme.spacing(.standard)) {
            Button(Copy.Footer.notifications) { showSettings(.notifications) }
            Button(Copy.Footer.settings) { showSettings(.general) }
            Spacer()
            Button(Copy.Footer.quit) { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(theme.font(.micro))
        .textCase(.uppercase)
        .foregroundStyle(theme.color(.textSecondary, scheme))
    }

    /// DETAILS and STATS open the Details window on that tab.
    func openDetails(_ tab: AppModel.DetailsTab) {
        model.detailsTab = tab
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

    func showSettings(_ tab: AppModel.SettingsTab) {
        model.settingsTab = tab
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    func openOnboarding(at step: AppModel.OnboardingStep) {
        model.onboardingStep = step
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: PulseScenes.onboardingID)
    }
}

enum PopoverMetrics {
    static let width: CGFloat = 340
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
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            HStack {
                Text((session.modelName ?? Copy.Details.unknownModel).uppercased()).font(theme.font(.title))
                    .foregroundStyle(theme.color(.background, scheme))
                    .padding(.horizontal, theme.spacing(.compact) * 1.5).padding(.vertical, theme.spacing(.compact) / 2)
                    .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.accent, scheme)))
                Spacer()
                if let pct = session.contextPct {
                    Text("CTX \(Formatting.percent(pct))").font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
            if let pct = session.contextPct {
                PixelBar(fraction: NSDecimalNumber(decimal: pct).doubleValue / 100, role: .accent, pattern: .solid, segments: 32)
            }
            HStack {
                PixelStat(session.costUSD.map { $0.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) } ?? "—", Copy.Details.costEstimate)
                PixelStat(session.cacheHitPct.map(Formatting.percent) ?? "—", Copy.Details.cacheHits)
                PixelStat(session.linesAdded.map { "+" + Formatting.compact($0) } ?? "—", Copy.Details.lines)
                PixelStat(session.apiMs.map { Formatting.duration(milliseconds: $0) } ?? "—", Copy.Details.apiTime)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
