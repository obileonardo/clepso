import AppKit
import ClaudeCodeAdapter
import DesignSystem
import Domain
import SwiftUI
import UsageEngine

/// The Details window (increments 1.7e–f, reorganised in 1.8c): a sidebar of sections, a title row with that
/// section's controls, and content laid out to use the window's width.
public struct DetailsView: View {
    @Bindable var model: AppModel
    @State private var pageWidth: CGFloat = 0
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        let snapshot = model.snapshot
        HStack(spacing: 0) {
            DetailsSidebar(model: model)
            Rectangle().fill(theme.color(.separator, scheme)).frame(width: theme.stroke(.hairline)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                // Zero height and as wide as the pane offers: its width is the window's, never the content's.
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
                    .padding(.bottom, -theme.spacing(.spacious))
                PageColumn { header }                   // the title and controls share the page column's edges
                ScrollView {
                    Group {
                        switch model.detailsSection {
                        case .home: HomeSection(model: model)
                        case .card: StatsGate(model: model) { _, _ in CardSection(model: model) }
                        case .goals: GoalsSection(model: model)
                        case .account: AccountSection(model: model)
                        case .settings: SettingsSection(model: model)
                        case .limits: LimitsSection(model: model, snapshot: snapshot)
                        case .session:
                            SessionSection(snapshot: snapshot, zone: model.environment.timeZone, locale: model.environment.locale) {
                                model.detailsSection = .settings
                            }
                        case .overview: StatsGate(model: model) { summary, file in OverviewSection(model: model, summary: summary, file: file) }
                        case .models: StatsGate(model: model) { summary, file in ModelsSection(model: model, summary: summary, file: file) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.bottom, theme.spacing(.spacious))
                    .environment(\.isFixtureData, false)       // the header's DEMO tag covers the page, and stays in view
                }
            }
            .padding(theme.spacing(.spacious))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.pageWidth, pageWidth)
        }
        .frame(minWidth: DetailsMetrics.minWidth, minHeight: DetailsMetrics.minHeight, alignment: .topLeading)
        .background(WindowFitter())
        .background(theme.color(.background, scheme))
        .overlay(PixelScanlines())
        .environment(\.isFixtureData, snapshot.isDemo)
        .environment(\.displayTimeZone, model.environment.timeZone)
    }

    /// Section title, a one-line explanation, and the section's own controls on the right.
    var header: some View {
        HStack(alignment: .center, spacing: theme.spacing(.standard)) {
            VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                HStack(spacing: theme.spacing(.standard)) {
                    Text((model.detailsSection == .home ? model.greeting : DetailsSidebar.title(model.detailsSection)).uppercased())
                        .font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textPrimary, scheme))
                    DemoTag()
                }
                Text(DetailsSidebar.subtitle(model.detailsSection)).font(theme.font(.supporting))
                    .foregroundStyle(theme.color(.textSecondary, scheme))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            if model.detailsSection == .overview || model.detailsSection == .models {
                PixelSegmented(Copy.Stats.rangeLabel, options: [(StatsSummary.Range.allTime, Copy.Stats.allTime), (.last30, Copy.Stats.last30),
                                                                (.last7, Copy.Stats.last7)], selection: $model.statsRange)
            }
            if model.detailsSection == .models {
                PixelSegmented(Copy.Stats.viewLabel, options: [(AppModel.ModelsView.arena, Copy.Stats.arena), (.chart, Copy.Stats.chart)],
                               selection: $model.modelsView)
            }
        }
    }
}

enum DetailsMetrics {
    static let minWidth: CGFloat = 1100                 // 1.12: room for a side inspector beside a full year
    static let defaultWidth: CGFloat = 1320
    static let minHeight: CGFloat = 660
    static let sidebarWidth: CGFloat = 200
    static let sideColumn: CGFloat = 260
    static let chartHeight: CGFloat = 200
    static let settingsColumn: CGFloat = 760
}

/// Primary navigation: every section one click away, with the selected one lit and marked for VoiceOver.
struct DetailsSidebar: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    static func title(_ s: AppModel.DetailsSection) -> String {
        switch s {
        case .home: Copy.Home.title
        case .card: Copy.Card.title
        case .goals: Copy.Goals.title
        case .account: Copy.Account.title
        case .settings: Copy.SettingsPage.title
        case .limits: Copy.Details.limits
        case .session: Copy.Details.session
        case .overview: Copy.Stats.overview
        case .models: Copy.Stats.models
        }
    }
    static func subtitle(_ s: AppModel.DetailsSection) -> String {
        switch s {
        case .home: Copy.Home.subtitle
        case .card: Copy.Card.subtitle
        case .goals: Copy.Goals.subtitle
        case .account: Copy.Account.subtitle
        case .settings: Copy.SettingsPage.subtitle
        case .limits: Copy.Details.limitsSubtitle
        case .session: Copy.Details.sessionSubtitle
        case .overview: Copy.Stats.overviewSubtitle
        case .models: Copy.Stats.modelsSubtitle
        }
    }
    static func symbol(_ s: AppModel.DetailsSection) -> String {
        switch s {
        case .home: "house"
        case .card: "person.text.rectangle"
        case .goals: "target"
        case .account: "person.crop.circle"
        case .settings: "gearshape"
        case .limits: "gauge.with.dots.needle.50percent"
        case .session: "terminal"
        case .overview: "calendar"
        case .models: "person.3"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            // Name and version, like a title screen.
            VStack(alignment: .leading, spacing: theme.spacing(.compact) / 2) {
                Text(Product.name.uppercased()).font(theme.font(.metricMedium)).foregroundStyle(theme.color(.accent, scheme))
                Text("v\(model.environment.appVersion)").font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
            .accessibilityElement(children: .combine)
            .padding(.bottom, theme.spacing(.standard))
            group(nil, [.home])
            group(Copy.Details.usage, [.limits, .session])
            group(Copy.Details.stats, [.overview, .models, .card])
            group(Copy.Details.you, [.goals, .account, .settings])
            Spacer(minLength: theme.spacing(.spacious))
            planBadge
        }
        .padding(theme.spacing(.spacious))
        .frame(width: DetailsMetrics.sidebarWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.color(.surfaceElevated, scheme))
    }

    /// The plan, pinned at the bottom like a badge; opens Account.
    var planBadge: some View {
        let name = model.plan?.displayName
        return Button { model.detailsSection = .account } label: {
            Text((name ?? Copy.Account.planNotSet).uppercased()).font(theme.font(.micro)).lineLimit(1)
                .foregroundStyle(theme.color(name == nil ? .textSecondary : .background, scheme))
                .padding(.horizontal, theme.spacing(.standard)).padding(.vertical, theme.spacing(.compact) + 1)
                .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(name == nil ? Color.clear : theme.color(.accent, scheme)))
                .overlay(PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(name == nil ? .separator : .accent, scheme),
                                                                                   lineWidth: theme.stroke(.hairline)))
        }
        .buttonStyle(PixelPlainButtonStyle())
        .accessibilityLabel(Copy.Account.plan + ": " + (name ?? Copy.Account.planNotSet))
    }

    func group(_ title: String?, _ sections: [AppModel.DetailsSection]) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            if let title {
                Text(title.uppercased()).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .padding(.top, theme.spacing(.standard)).accessibilityAddTraits(.isHeader)
            }
            ForEach(sections, id: \.self) { section in
                let selected = model.detailsSection == section
                Button { model.detailsSection = section } label: {
                    HStack(spacing: theme.spacing(.standard)) {
                        PixelIcon(symbol: Self.symbol(section)).frame(width: theme.spacing(.spacious)).accessibilityHidden(true)
                        Text(Self.title(section)).font(theme.font(.label))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(theme.color(selected ? .textPrimary : .textSecondary, scheme))
                    .padding(.vertical, theme.spacing(.standard) + theme.spacing(.compact))
                    .padding(.horizontal, theme.spacing(.standard) + theme.spacing(.compact))
                    .background(selected ? theme.color(.surfaceMuted, scheme) : Color.clear)
                    .overlay(alignment: .leading) {
                        if selected { Rectangle().fill(theme.color(.accent, scheme)).frame(width: theme.stroke(.emphasis) * 2).accessibilityHidden(true) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PixelPlainButtonStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Stats sections need the user's agreement and a readable file; this shows the explainer or the problem first.
struct StatsGate<Content: View>: View {
    let model: AppModel
    @ViewBuilder let content: (StatsSummary, ClaudeCodeStats) -> Content
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if !model.statsEnabled {
                PixelPanel {
                    VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                        Text(Copy.Stats.explainerTitle).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                        Text(Copy.Stats.explainerBody).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                            .fixedSize(horizontal: false, vertical: true)
                        Button(Copy.Stats.enable) { Task { await model.setStatsEnabled(true) } }.buttonStyle(PixelButtonStyle(prominent: true))
                    }
                }
            } else {
                switch model.stats {
                case .failure(let problem)?:
                    Text(problem == .missing ? Copy.Stats.missing : Copy.Stats.unreadable).font(theme.font(.label))
                        .foregroundStyle(theme.color(.textSecondary, scheme))
                case .success(let file)?:
                    if let summary = model.statsSummary(model.statsRange) {
                        VStack(alignment: .leading, spacing: 0) {    // the last section's own air sits above the rule
                            content(summary, file)
                            if let through = summary.computedThrough {
                                PageColumn {                                                        // the rule spans the column
                                    Text(Copy.Stats.through(StatsFormat.day(through))).font(theme.font(.supporting))
                                        .foregroundStyle(theme.color(.textSecondary, scheme)).fixedSize(horizontal: false, vertical: true)
                                        .padding(.top, theme.spacing(.spacious))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .overlay(alignment: .top) { Rectangle().fill(theme.color(.separator, scheme)).frame(height: theme.stroke(.hairline)) }
                                }
                            }
                        }
                    }
                case nil:
                    ProgressView()
                }
            }
        }
        .task { model.loadStats() }
    }
}

enum StatsFormat {
    /// "2026-10-13" → "Oct 13".
    static func day(_ day: String) -> String {
        guard let date = StatsSummary.Day.date(day) else { return day }
        return date.formatted(Date.FormatStyle(timeZone: StatsSummary.Day.calendar.timeZone).month(.abbreviated).day())
    }
    static func month(_ day: String) -> String {
        guard let date = StatsSummary.Day.date(day) else { return day }
        return date.formatted(Date.FormatStyle(timeZone: StatsSummary.Day.calendar.timeZone).month(.abbreviated))
    }
    static func weekday(_ day: String) -> String {
        guard let date = StatsSummary.Day.date(day) else { return day }
        return date.formatted(Date.FormatStyle(timeZone: StatsSummary.Day.calendar.timeZone).weekday(.abbreviated))
    }
}

/// 1.17 (founder review): the Dashboard opens filling the screen's visible area (below the menu bar, beside the Dock),
/// never taller than the screen. It runs each time the window appears, so a resize lasts while the window is open.
struct WindowFitter: NSViewRepresentable {
    func makeNSView(context: Context) -> FittingView { FittingView() }
    func updateNSView(_ view: FittingView, context: Context) {}

    final class FittingView: NSView {
        /// The saved frame's name: macOS keeps the size and place the user last left the Dashboard at under it.
        nonisolated static let autosaveName = "ClepsoDashboard"
        /// The first open, before the user has sized it (founder review, 18 Oct 2026: not the full screen).
        nonisolated static let openFraction: CGFloat = 0.75

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // After SwiftUI has placed the window, so this frame wins. Reopens where the user left it; the first time,
            // three quarters of the screen, centred, which the user can then make bigger or smaller.
            DispatchQueue.main.async {
                guard window.frameAutosaveName != Self.autosaveName else { return }
                let restored = window.setFrameUsingName(Self.autosaveName)
                window.setFrameAutosaveName(Self.autosaveName)
                guard !restored, let screen = window.screen ?? NSScreen.main else { return }
                window.setFrame(Self.frame(for: screen.visibleFrame, minimum: window.minSize), display: true, animate: false)
            }
        }

        /// Three quarters of the visible area, centred; never smaller than the window's minimum, never larger than the
        /// screen.
        nonisolated static func frame(for visible: NSRect, minimum: NSSize) -> NSRect {
            let w = min(max(visible.width * openFraction, minimum.width), max(visible.width, minimum.width))
            let h = min(max(visible.height * openFraction, minimum.height), visible.height)
            return NSRect(x: visible.midX - w / 2, y: visible.midY - h / 2, width: w, height: h).integral
        }
    }
}
