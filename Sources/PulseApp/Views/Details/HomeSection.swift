import DesignSystem
import Domain
import SwiftUI

/// Increment 1.10 Home: the running total, both limits, the latest task and goals at a glance, and one useful next
/// step. Structure after the Aqua Voice reference; look from the Phosphor pixel layer.
struct HomeSection: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            chips
            if let prompt = nextStep { prompt }
            HStack(alignment: .top, spacing: theme.spacing(.spacious)) {
                PixelPanel {
                    VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                        heading(Copy.Home.limits, .limits)
                        if let pools = snapshot.provider?.pools, !pools.isEmpty {
                            ForEach(pools) { row in PixelLimitRow(model: row.model, now: snapshot.now, pace: PaceText.make(row.pace, model: model)) }
                        } else {
                            Text(Copy.Details.noLimits).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                    PixelPanel { latestTask(snapshot.agents) }
                    PixelPanel { goalsGlance }
                }
                .frame(width: DetailsMetrics.sideColumn + theme.spacing(.spacious) * 3)
            }
            .fixedSize(horizontal: false, vertical: true)
            if let file = model.statsFile, let summary = model.statsSummary(.allTime) {
                PixelPanel {
                    VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                        heading(Copy.Home.lastYear, .overview)
                        FittedCalendar(grid: StatsCalendar.recent(52 * 7, stats: file, levels: summary.heatmap, today: summary.today, firstDay: file.firstSessionDate))
                        CalendarLegend()
                    }
                }
            }
        }
        .task { model.loadStats() }
    }

    func heading(_ title: String, _ section: AppModel.DetailsSection) -> some View {
        HStack {
            Text(title).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme)).accessibilityAddTraits(.isHeader)
            Spacer()
            Button(Copy.Home.seeAll) { model.detailsSection = section }.buttonStyle(.plain)
                .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
        }
    }

    /// Like Aqua's "139,775 words and counting (+1,908)": the total, the newest day, and the level.
    @ViewBuilder var chips: some View {
        HStack(spacing: theme.spacing(.standard)) {
            if let total = model.runningTotal {
                PixelChip(text: Copy.Home.runningTotal(Formatting.compact(total.tokens))
                          + (total.lastDay.map { "  ·  " + Copy.Home.lastDay(Formatting.compact($0), StatsFormat.day(total.lastDayDate ?? "")) } ?? ""))
            } else {
                PixelChip(text: Copy.Home.watched(model.snapshot.provider?.sessions.count ?? 0))
            }
            if let card = model.playerCard {
                Button { model.detailsSection = .card } label: {
                    PixelChip(text: Copy.Card.levelBar(card.level.level, card.levelName), lit: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The first thing worth doing next, if any: connect, stats, then agents per task.
    var nextStep: AnyView? {
        if model.snapshot.empty == .notConnected, !model.snapshot.isDemo {
            return AnyView(NextStepBanner(title: Copy.Home.connectTitle, message: Copy.Home.connectBody, action: Copy.Home.connect) {
                model.onboardingStep = .consent
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: PulseScenes.onboardingID)
            })
        }
        if !model.statsEnabled {
            return AnyView(NextStepBanner(title: Copy.Home.statsTitle, message: Copy.Home.statsBody, action: Copy.Home.turnOn) {
                Task { await model.setStatsEnabled(true) }
            })
        }
        if model.snapshot.agents == nil {
            return AnyView(NextStepBanner(title: Copy.Home.agentsTitle, message: Copy.Home.agentsBody, action: Copy.Home.turnOn) {
                model.detailsSection = .settings
            })
        }
        return nil
    }

    @ViewBuilder func latestTask(_ agents: AgentsSummary?) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            heading(Copy.Home.latestTask, .session)
            if let task = agents?.latest {
                Text((task.agents == 0 ? Copy.Agents.none : Copy.Agents.count(task.agents)).uppercased()).font(theme.font(.metricMedium))
                    .foregroundStyle(theme.color(.textPrimary, scheme))
                Text(task.byType.map { "\($0.name) \($0.count)" }.joined(separator: " · "))
                    .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                Text(task.running ? Copy.Agents.running : Copy.Agents.finished(task.finished, of: task.agents))
                    .font(theme.font(.supporting)).foregroundStyle(theme.color(task.running ? .accent : .textSecondary, scheme))
            } else {
                Text(agents == nil ? Copy.Home.agentsBody : Copy.Agents.noTasks).font(theme.font(.supporting))
                    .foregroundStyle(theme.color(.textSecondary, scheme)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var goalsGlance: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            heading(Copy.Home.goals, .goals)
            ForEach(model.goalStatuses) { goal in
                VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                    HStack {
                        Text(GoalsSection.title(goal.kind)).font(theme.font(.supporting)).foregroundStyle(theme.color(.textPrimary, scheme))
                        Spacer()
                        StateTag(state: goal.state)
                    }
                    PixelBar(fraction: goal.state == .noData ? nil : goal.fraction, role: GoalsSection.role(goal.state), pattern: goal.state == .noData ? .outline : .solid, segments: 16)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A lit or outlined pixel pill holding one line of text.
struct PixelChip: View {
    let text: String
    var lit = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text).font(theme.font(.label)).monospacedDigit().lineLimit(1)
            .foregroundStyle(theme.color(lit ? .background : .textPrimary, scheme))
            .padding(.horizontal, theme.spacing(.standard) + theme.spacing(.compact)).padding(.vertical, theme.spacing(.compact) + 1)
            .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(lit ? .accent : .surfaceElevated, scheme)))
            .overlay(PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(lit ? .accent : .separator, scheme), lineWidth: theme.stroke(.hairline)))
    }
}

/// One suggested next step, with its button.
struct NextStepBanner: View {
    let title: String
    let message: String
    let action: String
    let perform: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: theme.spacing(.spacious)) {
            VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                Text(title).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                Text(message).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action, action: perform).buttonStyle(PixelButtonStyle(prominent: true))
        }
        .padding(theme.spacing(.windowPadding))
        .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.surfaceMuted, scheme)))
        .overlay(PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(.accent, scheme).opacity(0.5), lineWidth: theme.stroke(.hairline)))
    }
}

/// A goal's state in words, with a colour (never colour alone).
struct StateTag: View {
    let state: GoalStatus.State
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let (text, role): (String, ColorToken) = switch state {
        case .met: (Copy.Goals.met, .statusSuccess)
        case .onTrack: (Copy.Goals.onTrack, .statusSuccess)
        case .atRisk: (Copy.Goals.atRisk, .statusAttention)
        case .missed: (Copy.Goals.missed, .statusBlocked)
        case .noData: (Copy.Goals.noData, .textSecondary)
        }
        Text(text).font(theme.font(.micro)).foregroundStyle(theme.color(role, scheme))
            .padding(.horizontal, theme.spacing(.compact) * 1.5).padding(.vertical, theme.spacing(.compact) / 2)
            .overlay(PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(role, scheme), lineWidth: theme.stroke(.hairline)))
    }
}
