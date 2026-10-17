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

    @State private var selected: GoalStatus.Kind = .activeDays

    /// Monarch's grid of goal cards (1.12); the chosen one opens Charma's detail: progress, the last seven days, and a
    /// sidebar with its state, streak and target.
    var body: some View {
        let statuses = Dictionary(model.goalStatuses.map { ($0.kind, $0) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            HStack(alignment: .top, spacing: theme.spacing(.spacious)) {
                ForEach(GoalStatus.Kind.allCases, id: \.self) { kind in card(kind, statuses[kind]) }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: theme.spacing(.spacious)) {
                PixelPanel { detail(selected, statuses[selected]) }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                PixelPanel { sidebar(selected, statuses[selected]) }.frame(width: DetailsMetrics.sideColumn + theme.spacing(.spacious) * 2)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(Copy.Goals.note).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { model.loadStats() }
    }

    /// A Monarch card: a big pixel emblem, the goal, its value and a thin bar; lit when chosen.
    func card(_ kind: GoalStatus.Kind, _ status: GoalStatus?) -> some View {
        let on = selected == kind
        return Button { selected = kind } label: {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                HStack(alignment: .top) {
                    Image(systemName: symbol(kind)).font(theme.font(.metricMedium)).foregroundStyle(theme.color(.accent, scheme))
                        .frame(width: theme.spacing(.spacious) * 3, height: theme.spacing(.spacious) * 3)
                        .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.surfaceMuted, scheme)))
                    Spacer()
                    if let status { StateTag(state: status.state) } else { Text(Copy.Goals.off.uppercased()).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme)) }
                }
                Text(Self.title(kind).uppercased()).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                Text(status?.value ?? "—").font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textPrimary, scheme))
                PixelBar(fraction: status.flatMap { $0.state == .noData ? nil : $0.fraction }, role: status.map { Self.role($0.state) } ?? .statusUnknown,
                         pattern: status?.state == .noData || status == nil ? .outline : .solid, segments: 20)
            }
            .padding(theme.spacing(.windowPadding))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(on ? .surfaceMuted : .surfaceElevated, scheme)))
            .overlay(PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(on ? .accent : .separator, scheme),
                                                                               lineWidth: on ? theme.stroke(.emphasis) : theme.stroke(.hairline)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    func detail(_ kind: GoalStatus.Kind, _ status: GoalStatus?) -> some View {
        let pools = model.snapshot.provider?.pools ?? []
        let five = pools.first { $0.poolKey.hasSuffix("five_hour") }?.history ?? []
        let seven = pools.first { $0.poolKey.hasSuffix("seven_day") }?.history ?? []
        let active = Set((model.statsFile?.days ?? []).filter { $0.messages > 0 }.map(\.date))
        let days = GoalHistory.days(kind, goals: model.goals, fiveHour: five, sevenDay: seven, activeDays: active,
                                    now: model.environment.clock.now(), zone: model.environment.timeZone)
        return VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(Self.title(kind).uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
            if let status {
                HStack(alignment: .lastTextBaseline, spacing: theme.spacing(.standard)) {
                    Text(status.value).font(theme.font(.metricHero)).foregroundStyle(theme.color(.textPrimary, scheme))
                    Text("/ " + status.target).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
                PixelBar(fraction: status.state == .noData ? nil : status.fraction, role: Self.role(status.state),
                         pattern: status.state == .noData ? .outline : .solid, segments: 40)
                Text(status.detail).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(Copy.Goals.lastSeven).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme)).padding(.top, theme.spacing(.standard))
            ForEach(days) { day in
                HStack(spacing: theme.spacing(.standard)) {
                    Image(systemName: day.met == true ? "checkmark.square.fill" : day.met == false ? "xmark.square" : "square.dashed")
                        .foregroundStyle(theme.color(day.met == true ? .statusSuccess : day.met == false ? .statusBlocked : .textSecondary, scheme))
                        .accessibilityHidden(true)
                    Text(StatsFormat.weekday(day.day) + " " + StatsFormat.day(day.day)).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                    Spacer()
                    Text(Copy.Goals.dayValue(kind, day.value, day.met)).font(theme.font(.supporting)).monospacedDigit()
                        .foregroundStyle(theme.color(.textSecondary, scheme))
                }
                .padding(.vertical, theme.spacing(.compact))
                .accessibilityElement(children: .combine)
            }
        }
    }

    func sidebar(_ kind: GoalStatus.Kind, _ status: GoalStatus?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Copy.Goals.details).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme)).padding(.bottom, theme.spacing(.standard))
            sideRow(Copy.Goals.status) { status.map { AnyView(StateTag(state: $0.state)) } ?? AnyView(Text(Copy.Goals.off).font(theme.font(.label))) }
            sideRow(Copy.Goals.streakLabel) {
                AnyView(Text(status?.streak.map { Copy.Goals.streak($0) } ?? "—").font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme)))
            }
            sideRow(Copy.Goals.target) { AnyView(editor(kind)) }
        }
    }

    func sideRow(_ label: String, _ value: () -> AnyView) -> some View {
        HStack(alignment: .center) {
            Text(label).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
            Spacer()
            value()
        }
        .padding(.vertical, theme.spacing(.standard))
        .overlay(alignment: .top) { Rectangle().fill(theme.color(.separator, scheme).opacity(0.6)).frame(height: theme.stroke(.hairline)) }
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
