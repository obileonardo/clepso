import DesignSystem
import SwiftUI

/// Increment 1.10d: goals the user sets, each checked against what Claude Code reports, with its state in words.
struct GoalsSection: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    nonisolated static func title(_ kind: GoalStatus.Kind) -> String {
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

    /// 1.14: Account's structure. A section per goal: its value and state, a bar, the last seven days as squares, and
    /// the target on the right.
    var body: some View {
        let statuses = Dictionary(model.goalStatuses.map { ($0.kind, $0) }, uniquingKeysWith: { a, _ in a })
        PageColumn {
            ForEach(GoalStatus.Kind.allCases, id: \.self) { kind in
                PageSection(Self.title(kind), statuses[kind]?.detail ?? Copy.Goals.off) { goal(kind, statuses[kind]) }
            }
            PageSection(Copy.Goals.aboutTitle, nil) {
                Text(Copy.Goals.note).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { model.loadStats() }
    }

    func goal(_ kind: GoalStatus.Kind, _ status: GoalStatus?) -> some View {
        let pools = model.snapshot.provider?.pools ?? []
        let five = pools.first { $0.poolKey.hasSuffix("five_hour") }?.history ?? []
        let seven = pools.first { $0.poolKey.hasSuffix("seven_day") }?.history ?? []
        let active = Set((model.statsFile?.days ?? []).filter { $0.messages > 0 }.map(\.date))
        let days = GoalHistory.days(kind, goals: model.goals, fiveHour: five, sevenDay: seven, activeDays: active,
                                    knownThrough: model.statsFile?.computedThrough, now: model.environment.clock.now(), zone: model.environment.timeZone)
        return HStack(alignment: .top, spacing: theme.spacing(.spacious) * 1.5) {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                HStack(alignment: .lastTextBaseline, spacing: theme.spacing(.standard)) {
                    Text(status?.value ?? "—").font(theme.font(.metricHero)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme))
                        .padding(.vertical, -theme.spacing(.compact))           // the pixel face's tall line box, trimmed
                    if let status {
                        Text("/ " + status.target).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                        StateTag(state: status.state)
                    }
                }
                PixelBar(fraction: status.flatMap { $0.state == .noData ? nil : $0.fraction }, role: status.map { Self.role($0.state) } ?? .statusUnknown,
                         pattern: status == nil || status?.state == .noData ? .outline : .solid, segments: 30)
                HStack(spacing: theme.spacing(.compact)) {
                    ForEach(days) { day in
                        VStack(spacing: theme.spacing(.compact)) {
                            Rectangle().fill(theme.color(day.met == true ? .accent : day.met == false ? .statusBlocked : .surfaceMuted, scheme))
                                .frame(width: theme.spacing(.spacious) * 1.4, height: theme.spacing(.spacious) * 1.4)
                            Text(String(StatsFormat.weekday(day.day).prefix(2)).uppercased()).font(theme.font(.micro))
                                .foregroundStyle(theme.color(.textSecondary, scheme))
                        }
                        .help(StatsFormat.day(day.day) + " · " + Copy.Goals.dayValue(kind, day.value, day.met))
                        .accessibilityElement().accessibilityLabel(StatsFormat.day(day.day) + ": " + Copy.Goals.dayValue(kind, day.value, day.met))
                    }
                    if let streak = status?.streak, streak > 0 {
                        Text(Copy.Goals.streak(streak)).font(theme.font(.supporting)).foregroundStyle(theme.color(.accent, scheme))
                            .padding(.leading, theme.spacing(.standard))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            editor(kind).frame(width: PageMetrics.labelColumn * 0.7, alignment: .topLeading).pageCard()
        }
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
                HStack {
                    Text(Copy.Goals.target).font(theme.font(.supporting))
                    Spacer(minLength: theme.spacing(.compact))
                }
            }
            .toggleStyle(PixelToggleStyle())
            .accessibilityLabel(Copy.Goals.targetFor(Self.title(kind)))
            if let value {
                HStack(spacing: theme.spacing(.standard)) {
                    Text("\(value)\(unit)").font(theme.font(.title)).monospacedDigit()
                        .foregroundStyle(theme.color(.textPrimary, scheme))
                        .accessibilityLabel(Copy.Goals.targetFor(Self.title(kind)))
                        .accessibilityValue("\(value)\(unit)")
                    Spacer(minLength: theme.spacing(.standard))
                    HStack(spacing: theme.spacing(.standard)) {
                        Button { set(max(range.lowerBound, value - step)) } label: {
                            PixelIcon(.minus).frame(width: 12, height: 12)
                        }
                            .buttonStyle(PixelButtonStyle())
                            .disabled(value <= range.lowerBound)
                            .accessibilityLabel(Copy.Goals.decrease(Self.title(kind)))
                        Button { set(min(range.upperBound, value + step)) } label: {
                            PixelIcon(.plus).frame(width: 12, height: 12)
                        }
                            .buttonStyle(PixelButtonStyle())
                            .disabled(value >= range.upperBound)
                            .accessibilityLabel(Copy.Goals.increase(Self.title(kind)))
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }
}
