import DesignSystem
import SwiftUI

/// Increment 1.10d: goals the user sets, each checked against what Claude Code reports, with its state in words.
struct GoalsSection: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    static func title(_ kind: GoalStatus.Kind) -> String {
        switch kind {
        case .activeDays: Copy.Goals.activeDays
        case .fiveHourPeak: Copy.Goals.fiveHourPeak
        case .weeklyFinish: Copy.Goals.weeklyFinish
        }
    }

    static func role(_ state: GoalStatus.State) -> ColorToken {
        switch state {
        case .met, .onTrack: .statusSuccess
        case .atRisk: .statusAttention
        case .missed: .statusBlocked
        case .noData: .statusUnknown
        }
    }

    var body: some View {
        let statuses = Dictionary(model.goalStatuses.map { ($0.kind, $0) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            ForEach(GoalStatus.Kind.allCases, id: \.self) { kind in
                PixelPanel { goal(kind, statuses[kind]) }
            }
            Text(Copy.Goals.note).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { model.loadStats() }
    }

    func goal(_ kind: GoalStatus.Kind, _ status: GoalStatus?) -> some View {
        HStack(alignment: .top, spacing: theme.spacing(.spacious) * 1.5) {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                HStack(spacing: theme.spacing(.standard)) {
                    Image(systemName: symbol(kind)).foregroundStyle(theme.color(.accent, scheme)).accessibilityHidden(true)
                    Text(Self.title(kind).uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                    if let status { StateTag(state: status.state) }
                }
                if let status {
                    HStack(alignment: .lastTextBaseline, spacing: theme.spacing(.standard)) {
                        Text(status.value).font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textPrimary, scheme))
                        Text("/ " + status.target).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                    }
                    PixelBar(fraction: status.state == .noData ? nil : status.fraction, role: Self.role(status.state),
                             pattern: status.state == .noData ? .outline : .solid, segments: 30)
                    Text(status.detail).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if let streak = status.streak, streak > 0 {
                        Text(Copy.Goals.streak(streak)).font(theme.font(.supporting)).foregroundStyle(theme.color(.accent, scheme))
                    }
                } else {
                    Text(Copy.Goals.off).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            editor(kind).frame(width: DetailsMetrics.sideColumn * 0.8, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
    }

    func symbol(_ kind: GoalStatus.Kind) -> String {
        switch kind {
        case .activeDays: "calendar"
        case .fiveHourPeak: "gauge.with.dots.needle.50percent"
        case .weeklyFinish: "flag.checkered"
        }
    }

    /// On or off, and the target, saved as soon as it changes.
    func editor(_ kind: GoalStatus.Kind) -> some View {
        let (value, range, step, unit): (Int?, ClosedRange<Int>, Int, String) = switch kind {
        case .activeDays: (model.goals.activeDaysPerWeek, 1...7, 1, "/7")
        case .fiveHourPeak: (model.goals.fiveHourPeakMax, 10...100, 5, "%")
        case .weeklyFinish: (model.goals.weeklyFinishMax, 10...100, 5, "%")
        }
        let defaults = Goals()
        func set(_ new: Int?) {
            var goals = model.goals
            switch kind {
            case .activeDays: goals.activeDaysPerWeek = new
            case .fiveHourPeak: goals.fiveHourPeakMax = new
            case .weeklyFinish: goals.weeklyFinishMax = new
            }
            Task { await model.setGoals(goals) }
        }
        let fallback: Int = switch kind {
        case .activeDays: defaults.activeDaysPerWeek ?? 5
        case .fiveHourPeak: defaults.fiveHourPeakMax ?? 80
        case .weeklyFinish: defaults.weeklyFinishMax ?? 90
        }
        return VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Toggle(isOn: Binding(get: { value != nil }, set: { set($0 ? fallback : nil) })) {
                Text(value == nil ? Copy.Goals.off : Copy.Goals.target).font(theme.font(.supporting))
            }
            .toggleStyle(PixelToggleStyle())
            if let value {
                Stepper(value: Binding(get: { value }, set: { set($0) }), in: range, step: step) {
                    Text("\(value)\(unit)").font(theme.font(.title)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme))
                }
                .accessibilityLabel(Self.title(kind))
            }
        }
    }
}
