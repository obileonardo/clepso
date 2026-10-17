import DesignSystem
import Domain
import SwiftUI
import UsageEngine

/// The Details window (increment 1.7e–f): Limits with history and pace, the Session in full, and Stats like Claude
/// Code's /stats. Opened from the popover's DETAILS and STATS buttons.
public struct DetailsView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
                Text(Copy.Header.title.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                DemoTag()
                Spacer()
                PixelTabs([(AppModel.DetailsTab.limits, Copy.Details.limits), (.session, Copy.Details.session), (.stats, Copy.Details.stats)],
                          selection: $model.detailsTab)
            }
            ScrollView {
                Group {
                    switch model.detailsTab {
                    case .limits: LimitsTab(model: model, snapshot: snapshot)
                    case .session: SessionTab(snapshot: snapshot, zone: model.environment.timeZone, locale: model.environment.locale)
                    case .stats: StatsTab(model: model)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, theme.spacing(.spacious))
            }
        }
        .padding(theme.spacing(.spacious))
        .frame(minWidth: DetailsMetrics.minWidth, minHeight: DetailsMetrics.minHeight, alignment: .topLeading)
        .background(theme.color(.background, scheme))
        .overlay(PixelScanlines())
        .environment(\.isFixtureData, snapshot.isDemo)
        .environment(\.displayTimeZone, model.environment.timeZone)
    }
}

enum DetailsMetrics {
    static let minWidth: CGFloat = 720
    static let minHeight: CGFloat = 600
    static let chartHeight: CGFloat = 140
}

/// Every limit with its history and the pace estimate.
struct LimitsTab: View {
    let model: AppModel
    let snapshot: OverviewSnapshot
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            if let provider = snapshot.provider, !provider.pools.isEmpty {
                ForEach(provider.pools) { row in
                    PixelPanel {
                        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                            PixelLimitRow(model: row.model, now: snapshot.now, pace: PaceText.make(row.pace, model: model))
                            HistoryChart(row: row, now: snapshot.now, zone: model.environment.timeZone, locale: model.environment.locale)
                        }
                    }
                }
                Label(provider.unreadLimitWindows > 0 ? Copy.Detail.unreadLimits(provider.unreadLimitWindows) : Copy.Detail.otherLimits,
                      systemImage: "info.circle")
                    .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme)).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Copy.Details.noLimits).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
        }
    }
}

/// Pace estimate in words; always says "Estimate".
enum PaceText {
    @MainActor
    static func make(_ pace: PaceEstimate, model: AppModel) -> String? {
        switch pace {
        case .reachesLimit(let at):
            Copy.Pace.reaches(Formatting.resetTime(at, now: model.environment.clock.now(), zone: model.environment.timeZone,
                                                   locale: model.environment.locale))
        case .belowAtReset(let pct): Copy.Pace.byReset(Formatting.percent(Decimal(pct.rounded())))
        case .notRising: Copy.Pace.notRising
        case .notEnoughData: nil
        case .atLimit: nil
        }
    }
}

/// Used % over the window so far: a step line, dotted 80/95/100 guides, NOW, and the dashed pace projection.
struct HistoryChart: View {
    let row: PoolRow
    let now: Date
    let zone: TimeZone
    let locale: Locale
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var span: TimeInterval { row.poolKey.hasSuffix("five_hour") ? 5 * 3600 : 7 * 86_400 }

    var body: some View {
        let start = now.addingTimeInterval(-span)
        let end = max(now, row.model.resetsAt.value ?? now).addingTimeInterval(span * 0.02)
        let points = row.history.filter { $0.at >= start }.map { (x: $0.at.timeIntervalSince1970, y: $0.usedPct) }
        let projection = projectionLine(lastPoint: points.last)
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            PixelLineChart(series: [ChartSeries(id: row.poolKey, points: points, role: .accent)],
                           xRange: start.timeIntervalSince1970...end.timeIntervalSince1970, yRange: 0...max(100, points.map(\.y).max() ?? 0),
                           guides: [80, 95, 100], guideLabel: { $0 == 95 ? "" : "\(Int($0))%" }, projection: projection, marker: now.timeIntervalSince1970,
                           summary: summary(points))
                .frame(height: DetailsMetrics.chartHeight)
            HStack {
                Text(Formatting.resetTime(start, now: now, zone: zone, locale: locale).uppercased())
                Spacer()
                Text(Copy.Details.now)
                Spacer()
                Text(row.model.resetsAt.value.map { Copy.Details.resets(Formatting.resetTime($0, now: now, zone: zone, locale: locale)) } ?? "")
            }
            .font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            .accessibilityHidden(true)
        }
    }

    func projectionLine(lastPoint: (x: Double, y: Double)?) -> (from: (x: Double, y: Double), to: (x: Double, y: Double))? {
        guard let last = lastPoint else { return nil }
        switch row.pace {
        case .reachesLimit(let at): return (last, (at.timeIntervalSince1970, 100))
        case .belowAtReset(let pct): return row.model.resetsAt.value.map { (last, ($0.timeIntervalSince1970, pct)) }
        default: return nil
        }
    }

    func summary(_ points: [(x: Double, y: Double)]) -> String {
        guard let first = points.first, let last = points.last else { return Copy.Details.noHistory(row.model.scope) }
        return Copy.Details.historySummary(scope: row.model.scope, from: Int(first.y.rounded()), to: Int(last.y.rounded()), readings: points.count)
    }
}
