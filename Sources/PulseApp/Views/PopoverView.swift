import AppKit
import DesignSystem
import Domain
import SwiftUI

/// The `MenuBarExtra` window (depth 1–2): overview, provider detail and the provenance inspector
/// as pages of one panel, so Escape always steps back one level and focus stays inside the popover.
///
/// 1.15 layout: every page has the same frame. A demo strip on top when the data is demo data; the page's header; its
/// content in cards on one grid; and one action bar at the bottom: DASHBOARD (the only primary), the page's own actions
/// as secondary buttons of one height, a refresh beside the freshness line, then QUIT as a framed, unlit button at the end.
public struct PopoverView: View {
    let model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var refreshing = false

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            if snapshot.isDemo { demoStrip }
            switch model.popoverRoute {
            case .overview:
                header(snapshot)
                problemBanner
                overview(snapshot)
            case .detail:
                if let provider = snapshot.provider { ProviderDetailView(model: model, provider: provider, now: snapshot.now) }
                else { header(snapshot); overview(snapshot) }
            case .inspector(let key, _):
                if let inspector = inspector(snapshot, key) { inspector } else { header(snapshot); overview(snapshot) }
            }
            actionBar(snapshot)
        }
        .padding(theme.spacing(.windowPadding))
        .frame(width: PopoverMetrics.width, alignment: .topLeading)
        .background(theme.color(.background, scheme))
        .overlay(PixelScanlines())
        // The demo strip marks the whole panel, so rows and titles don't repeat the DEMO tag.
        .environment(\.isFixtureData, false)
        .environment(\.displayTimeZone, model.environment.timeZone)
        .onExitCommand { back() }
    }

    func inspector(_ snapshot: OverviewSnapshot, _ key: String) -> InspectorView? {
        guard case .inspector(_, let fromDetail) = model.popoverRoute,
              let row = (snapshot.provider?.pools ?? []).first(where: { $0.poolKey == key })
                ?? snapshot.codex?.pools.first(where: { $0.poolKey == key }) else { return nil }
        return InspectorView(row: row, provider: key.hasPrefix("codex.") ? nil : snapshot.provider, isDemo: snapshot.isDemo, now: snapshot.now,
                             zone: model.environment.timeZone, locale: model.environment.locale) {
            model.popoverRoute = fromDetail ? .detail : .overview
        }
    }

    // MARK: - Chrome

    /// One thin line instead of a DEMO tag on every title, with the way out beside it.
    var demoStrip: some View {
        HStack(spacing: theme.spacing(.standard)) {
            Text("DEMO").font(theme.font(.micro).weight(.bold)).foregroundStyle(theme.color(.background, scheme))
                .padding(.horizontal, theme.spacing(.compact) * 1.5)
                .background(PixelRect(step: theme.stroke(.hairline)).fill(theme.color(.accent, scheme)))
                .accessibilityHidden(true)
            Text(Copy.Demo.strip).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme)).lineLimit(1)
            Spacer(minLength: theme.spacing(.standard))
            Button(Copy.Demo.exitShort) { Task { await model.setDemo(false) } }
                .buttonStyle(PixelQuietButtonStyle())
                .accessibilityLabel(Copy.Demo.exit)
        }
        .padding(.leading, theme.spacing(.standard))
        .padding(.vertical, theme.spacing(.compact) / 2)
        .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.surfaceMuted, scheme)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.Demo.header)
    }

    /// Title on the left; the provider and its plan on the right as one button into provider detail. The aggregate
    /// line is the icon's accessibility label and help text, so it isn't repeated here.
    func header(_ snapshot: OverviewSnapshot) -> some View {
        HStack(alignment: .center, spacing: theme.spacing(.standard)) {
            Text(Copy.Header.title.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                .fixedSize().accessibilityAddTraits(.isHeader)
            Spacer(minLength: theme.spacing(.standard))
            if let provider = snapshot.provider {
                Button { model.popoverRoute = .detail } label: {
                    HStack(spacing: theme.spacing(.standard)) {
                        Text(provider.identity.wordmark.uppercased()).font(theme.font(.micro)).tracking(1)
                            .foregroundStyle(theme.color(.textPrimary, scheme)).fixedSize()
                        PlanPill(planName: provider.planName.map(PopoverMetrics.shortPlan), provenance: provider.plan).fixedSize()
                        PixelIcon(.chevronRight).foregroundStyle(theme.color(.textSecondary, scheme)).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(provider.header)
                .accessibilityHint("Shows provider details")
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
            EmptyCard(glyph: .link, title: Copy.Empty.noProviderTitle, message: Copy.Empty.noProviderBody) {
                Button(Copy.Empty.noProviderCTA) { openOnboarding(at: .provider) }.buttonStyle(PixelButtonStyle(prominent: true))
                Button(Copy.Onboarding.firstReadingDemo) { Task { await model.setDemo(true) } }.buttonStyle(PixelButtonStyle())
            }
        case .waitingForFirstReading:
            EmptyCard(glyph: .clock, title: nil, message: Copy.Onboarding.firstReadingWaiting) {
                Button(Copy.Onboarding.firstReadingDemo) { Task { await model.setDemo(true) } }.buttonStyle(PixelButtonStyle())
            }
        case nil:
            if let provider = snapshot.provider {
                VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                    LimitCards(model: model, pools: provider.pools, now: snapshot.now, fromDetail: false)
                    if let session = provider.sessions.first { SessionStrip(session: session, agents: snapshot.agents) }
                    if let codex = snapshot.codex { CodexCards(model: model, section: codex, now: snapshot.now) }
                }
            }
        }
        // Someone who uses only Codex still sees it while Claude Code isn't connected.
        if snapshot.empty != nil, let codex = snapshot.codex {
            CodexCards(model: model, section: codex, now: snapshot.now)
        }
    }

    // MARK: - Action bar and navigation

    /// One row, one height: DASHBOARD is the page's primary action, the page's own actions are secondary, freshness or
    /// nothing fills the middle (with a refresh beside it), and QUIT is framed at the end so it reads as an action.
    func actionBar(_ snapshot: OverviewSnapshot) -> some View {
        HStack(spacing: theme.spacing(.standard)) {
            Button { openDashboard(.home) } label: { PixelLabel(Copy.Details.dashboard, glyph: .grid) }
                .buttonStyle(PixelButtonStyle(prominent: true)).fixedSize()
            switch model.popoverRoute {
            case .overview:
                EmptyView()
            case .detail:
                Button { NSWorkspace.shared.open(ProviderDetailView.usageURL) } label: { PixelLabel(Copy.Detail.openUsageShort, glyph: .external) }
                    .buttonStyle(PixelButtonStyle()).fixedSize()
                    .help(Copy.Detail.openUsage)
                    .accessibilityLabel(Copy.Detail.openUsage)
                Button(Copy.Detail.changePlan) { openDashboard(.account) }.buttonStyle(PixelButtonStyle()).fixedSize()
            case .inspector(let key, _):
                if let inspector = inspector(snapshot, key) {
                    Button(Copy.Inspector.copy) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(inspector.details, forType: .string)
                    }
                    .buttonStyle(PixelButtonStyle()).fixedSize()
                }
            }
            Spacer(minLength: 0)
            if model.popoverRoute == .overview, let updated = snapshot.updatedAt {
                HStack(spacing: 0) {
                    Button { refreshNow() } label: { PixelIcon(.refresh).opacity(refreshing ? 0.35 : 1) }
                        .buttonStyle(PixelQuietButtonStyle()).fixedSize()
                        .disabled(refreshing)
                        .help(Copy.Footer.refreshHelp)
                        .accessibilityLabel(Copy.Footer.refresh)
                    Text(Copy.Header.updated(Formatting.age(of: updated, now: snapshot.now, zone: model.environment.timeZone,
                                                            locale: model.environment.locale)).uppercased())
                        .font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme)).lineLimit(1)
                }
                .padding(.trailing, theme.spacing(.compact))     // a little air before QUIT's frame
            }
            // Quitting is an action, not a label: framed like DASHBOARD but unlit, so it reads as a button without competing.
            Button { NSApp.terminate(nil) } label: { PixelLabel(Copy.Footer.quit, glyph: .power) }
                .buttonStyle(PixelButtonStyle()).fixedSize()
                .help(Copy.Footer.quitHelp)
        }
        .padding(.top, theme.spacing(.standard) + theme.spacing(.compact))
        .overlay(alignment: .top) { Rectangle().fill(theme.color(.separator, scheme)).frame(height: theme.stroke(.hairline)) }
    }

    /// Checks again now instead of at the next tick. Claude Code's limits still arrive only when Claude Code runs; the
    /// icon stays dimmed for at least half a second so the click is seen even when nothing changed.
    func refreshNow() {
        refreshing = true
        Task {
            async let minimum: Void = { try? await Task.sleep(for: .milliseconds(500)) }()
            await model.refreshNow()
            await minimum
            refreshing = false
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

/// Item 8: the first popover open after launch paid for one-time work on the main thread: Swift type metadata for the
/// popover's views, the pixel faces' tables and glyphs, and the first date formatters (Time Profiler, first open ≈ 2× a
/// later one). Rendering the popover once off screen, right after launch while nothing waits on it, does that work
/// before the first click (Release, first open p50 132 → 106 ms). Nothing is shown and no state changes; callers throw the
/// image away (tests look at it).
@MainActor
enum PopoverWarmUp {
    @discardableResult
    static func run(_ model: AppModel) -> CGImage? {
        let renderer = ImageRenderer(content: PopoverView(model: model).themed(model))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.cgImage
    }
}

enum PopoverMetrics {
    /// Wide rather than tall (founder review, 17 Oct): the two limits sit side by side.
    static let width: CGFloat = 580
    /// "Claude Max 5×" → "Max 5×": the card already names the provider.
    static func shortPlan(_ name: String) -> String { name.hasPrefix("Claude ") ? String(name.dropFirst("Claude ".count)) : name }
}

/// Increment 3.4: Codex's limits under Claude Code's, with the same cards and a one-line label above them.
struct CodexCards: View {
    let model: AppModel
    let section: AgentLimitsSection
    let now: Date
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            HStack(spacing: theme.spacing(.standard)) {
                PixelIcon(symbol: "terminal").foregroundStyle(theme.color(.accent, scheme)).accessibilityHidden(true)
                Text(section.name.uppercased()).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textPrimary, scheme))
                if let plan = section.plan {
                    Text(plan.uppercased()).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
                Spacer(minLength: 0)
                if let model = section.model {
                    Text(model).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme)).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            LimitCards(model: model, pools: section.pools, now: now, fromDetail: false)
        }
        .padding(.top, theme.spacing(.compact))
    }
}

/// The limits as equal cards side by side; each opens the inspector for its number.
struct LimitCards: View {
    let model: AppModel
    let pools: [PoolRow]
    let now: Date
    let fromDetail: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing(.standard)) {
            ForEach(pools) { row in
                Button { model.popoverRoute = .inspector(poolKey: row.poolKey, fromDetail: fromDetail) } label: {
                    PixelLimitRow(model: row.model, now: now, pace: PaceText.short(row.pace, model: model))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .pulseCard()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows where this number comes from")
            }
        }
        .fixedSize(horizontal: false, vertical: true)          // equal heights: each card stretches to the taller one
    }
}

/// The popover's card: elevated fill and a hairline pixel frame, with one inner padding everywhere.
struct PulseCard: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let px = theme.stroke(.hairline) * 2
        content
            .padding(theme.spacing(.windowPadding))
            .background(PixelRect(step: px).fill(theme.color(.surfaceElevated, scheme)))
            .overlay(PixelRect(step: px).strokeBorder(theme.color(.separator, scheme), lineWidth: theme.stroke(.hairline)))
    }
}

extension View {
    func pulseCard() -> some View { modifier(PulseCard()) }
}

/// An empty or waiting state: an icon, at most a title and a line, and its buttons in one row.
struct EmptyCard<Actions: View>: View {
    let glyph: PixelGlyph
    let title: String?
    let message: String
    @ViewBuilder let actions: () -> Actions
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing(.windowPadding)) {
            PixelIcon(glyph, size: 24).foregroundStyle(theme.color(.accent, scheme)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                if let title { Text(title.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme)) }
                Text(message).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: theme.spacing(.standard)) { actions() }.padding(.top, theme.spacing(.compact))
            }
            Spacer(minLength: 0)
        }
        .pulseCard()
    }
}

/// One problem line with an optional fix.
struct Banner: View {
    let text: String
    let action: String?
    let perform: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let px = theme.stroke(.hairline) * 2
        HStack(alignment: .center, spacing: theme.spacing(.standard)) {
            PixelIcon(.warning).foregroundStyle(theme.color(.statusBlocked, scheme)).accessibilityHidden(true)
            Text(text).font(theme.font(.supporting)).foregroundStyle(theme.color(.textPrimary, scheme)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: theme.spacing(.standard))
            if let action { Button(action, action: perform).buttonStyle(PixelButtonStyle()) }
        }
        .padding(.horizontal, theme.spacing(.windowPadding))
        .padding(.vertical, theme.spacing(.standard))
        .background(PixelRect(step: px).fill(theme.color(.surfaceMuted, scheme)))
        .overlay(PixelRect(step: px).strokeBorder(theme.color(.statusBlocked, scheme), lineWidth: theme.stroke(.hairline)))
        .accessibilityElement(children: .combine)
    }
}

/// The newest session in one glance: the model and its context on top, then four figures on an even grid
/// (cost estimate, cache hits, lines, API time) and, when counted, the last task's agents.
struct SessionStrip: View {
    let session: SessionDetail
    var agents: AgentsSummary? = nil
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard) + theme.spacing(.compact)) {
            HStack(alignment: .center, spacing: theme.spacing(.standard)) {
                ModelChip(name: session.modelName)
                Spacer(minLength: theme.spacing(.standard))
                Text(Copy.Details.context).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
                Text(session.contextPct.map(Formatting.percent) ?? "—").font(theme.font(.title)).monospacedDigit()
                    .foregroundStyle(theme.color(.textPrimary, scheme))
            }
            PixelBar(fraction: session.contextPct.map { NSDecimalNumber(decimal: $0).doubleValue / 100 }, role: .accent,
                     pattern: session.contextPct == nil ? .outline : .solid, segments: 32)
            HStack(alignment: .top, spacing: 0) {
                stat(session.costUSD.map { $0.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) } ?? "—", Copy.Details.costEstimate, first: true)
                stat(session.cacheHitPct.map(Formatting.percent) ?? "—", Copy.Details.cacheHits)
                stat(session.linesAdded.map { "+" + Formatting.compact($0) } ?? "—", Copy.Details.lines)
                stat(session.apiMs.map { Formatting.duration(milliseconds: $0) } ?? "—", Copy.Details.apiTime)
                if let latest = agents?.latest {
                    stat("\(latest.agents)", Copy.Agents.statShort)
                        .help(Copy.Agents.strip(latest.agents, latest.byType.map { "\($0.name) \($0.count)" }.joined(separator: ", ")))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .pulseCard()
        .accessibilityElement(children: .combine)
    }

    /// One figure in its column; columns after the first are set off by a hairline.
    func stat(_ value: String, _ label: String, first: Bool = false) -> some View {
        PixelStat(value, label)
            .padding(.leading, first ? 0 : theme.spacing(.standard) + theme.spacing(.compact))
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .leading) {
                if !first { Rectangle().fill(theme.color(.separator, scheme)).frame(width: theme.stroke(.hairline)).accessibilityHidden(true) }
            }
    }
}
