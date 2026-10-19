import struct CodexAdapter.CodexAgents
import DesignSystem
import Domain
import Foundation
import Storage
import UsageEngine

/// Store state → what the menu bar shows. Pure: the clock, zone and locale are passed in.
public enum OverviewProjection {
    /// Display order of the Claude Code pools; unknown keys follow alphabetically.
    static let poolOrder = ["claude-code.rate_limits.five_hour", "claude-code.rate_limits.seven_day", "claude-code.rate_limits.spend_limit"]
    /// `card.availableAgain` reverts to `card.available` after 60 minutes.
    static let availableAgainFor: TimeInterval = 60 * 60

    static let claudeCode = SourceDescriptor(evidence: .officialLocalTelemetry, displayName: "Claude Code", version: nil)

    public static func scope(of poolKey: String) -> String {
        switch window(of: poolKey) {
        case "five_hour": "5-hour"
        case "seven_day": "7-day"
        case "spend_limit": "Spend limit"
        default: poolKey
        }
    }

    /// The Claude Code payload field this pool's percentage comes from (inspector `Provider field`).
    public static func providerField(of poolKey: String) -> String {
        "rate_limits.\(window(of: poolKey)).used_percentage"
    }

    /// The window part of any agent's pool key: `claude-code.rate_limits.five_hour` and `codex.rate_limits.five_hour`
    /// are both `five_hour`.
    static func window(of poolKey: String) -> String {
        guard let range = poolKey.range(of: ".rate_limits.") else { return poolKey }
        return String(poolKey[range.upperBound...])
    }

    public static func make(_ input: OverviewInput, now: Date, staleAfter: TimeInterval, zone: TimeZone, locale: Locale) -> OverviewSnapshot {
        let source = SourceDescriptor(evidence: .officialLocalTelemetry, displayName: "Claude Code", version: input.sourceVersion)
        let everSeen = input.lastEventAt != nil || !input.pools.isEmpty
        // Frames arriving now prove the helper is talking to us, whatever the install record says.
        let receiving = input.lastEventAt.map { now.timeIntervalSince($0) < staleAfter } ?? false
        let connection: ConnectionState = input.installed || input.isDemo || receiving ? .connected : (everSeen ? .disconnected : .notConnected)

        let ordered = input.pools.sorted { (rank($0.poolKey), $0.poolKey) < (rank($1.poolKey), $1.poolKey) }
        let rows = ordered.map { state in
            PoolRow(poolKey: state.poolKey, providerField: providerField(of: state.poolKey),
                    origin: .claudeCode(version: input.sourceVersion),
                    model: card(state, source: source, connection: connection, now: now),
                    receivedAt: state.latest?.receivedAt, recent: input.recent[state.poolKey] ?? [],
                    history: input.history[state.poolKey] ?? [],
                    pace: PaceEstimate.estimate(input.history[state.poolKey] ?? [], windowOpenedAt: state.window?.openedAt,
                                                resetsAt: state.resetsAt, now: now, lookback: paceLookback(state.poolKey)))
        }
        let lastSeen = ([input.lastEventAt] + input.pools.map(\.lastSeen)).compactMap { $0 }.max()

        let empty: OverviewSnapshot.Empty? = everSeen || input.isDemo ? nil : (input.installed ? .waitingForFirstReading : .notConnected)
        let plan = provenance(input.plan)
        let anyLive = rows.contains { $0.model.valueState(now: now, staleAfter: staleAfter) == .live }
        var provider = empty != nil ? nil : ProviderSection(
            identity: .claudeCode, planName: input.plan?.displayName, plan: plan,
            header: header(plan: input.plan, provenance: plan, metricsLive: anyLive),
            pools: rows, session: session(input, now: now), sessionCount: input.sessionSummaries.count,
            sourceVersion: input.sourceVersion, lastSeen: lastSeen, unreadLimitWindows: input.unreadLimitWindows,
            sessions: sessionDetails(input), models: modelGroups(sessionDetails(input)))
        provider?.lines = CodeLines.make(input.sessions, firstSeen: input.firstSessionSeen, now: now)

        // The menu bar summarises every agent Clepso reads (3.4): Codex's limits count toward the icon and its %.
        let codexSection = input.codexEnabled && !input.isDemo ? codex(input, now: now) : nil
        let codexCards = codexSection?.pools.map(\.model) ?? []
        let codexSeen = codexSection?.lastSeen
        let (icon, staleMark, text, line) = aggregate(rows.map(\.model) + codexCards, input: input,
                                                       empty: codexCards.isEmpty ? empty : nil,
                                                       lastSeen: [lastSeen, codexSeen].compactMap { $0 }.max(),
                                                       now: now, staleAfter: staleAfter, zone: zone, locale: locale)
        return OverviewSnapshot(now: now, isDemo: input.isDemo, icon: icon, iconStaleMark: staleMark, iconText: text,
                                aggregateLine: line, updatedAt: lastSeen, provider: provider, empty: empty,
                                agents: input.agentsTracking ? agents(input.agentTasks, open: input.openAgentRuns, background: input.backgroundSnapshots,
                                                                               now: now, staleAfter: staleAfter) : nil,
                                codex: codexSection, codexAgentsShown: input.codexEnabled && !input.isDemo,
                                codexAgents: input.codexEnabled && !input.isDemo ? input.codexAgentTasks.map { codexAgents($0, now: now) } : nil)
    }

    static let codexSource = SourceDescriptor(evidence: .officialLocalTelemetry, displayName: "Codex", version: nil)

    /// The Codex field a pool's percentage comes from: a `token_count` event's `rate_limits.primary` (the 5-hour
    /// window) or `.secondary` (the weekly one), as Codex writes them in its session files.
    static func codexField(of poolKey: String) -> String {
        "token_count › rate_limits.\(window(of: poolKey) == "five_hour" ? "primary" : "secondary").used_percent"
    }

    /// Codex's section: 5-hour first, then weekly, then any other window; nil until Codex has written a reading.
    static func codex(_ input: OverviewInput, now: Date) -> AgentLimitsSection? {
        guard !input.codexPools.isEmpty else { return nil }
        let order = ["five_hour", "seven_day"]
        let ordered = input.codexPools.sorted {
            (order.firstIndex(of: window(of: $0.poolKey)) ?? order.count, $0.poolKey) < (order.firstIndex(of: window(of: $1.poolKey)) ?? order.count, $1.poolKey)
        }
        let rows = ordered.map { state in
            PoolRow(poolKey: state.poolKey, providerField: codexField(of: state.poolKey),
                    origin: .codex(version: input.codexVersion),
                    model: card(state, source: codexSource, connection: .connected, now: now),
                    receivedAt: state.latest?.receivedAt, recent: input.recent[state.poolKey] ?? [],
                    history: input.history[state.poolKey] ?? [],
                    pace: PaceEstimate.estimate(input.history[state.poolKey] ?? [], windowOpenedAt: state.window?.openedAt,
                                                resetsAt: state.resetsAt, now: now, lookback: paceLookback(state.poolKey)))
        }
        return AgentLimitsSection(name: "Codex", plan: input.codexPlan, model: input.codexModel, pools: rows,
                                  lastSeen: input.codexPools.compactMap(\.lastSeen).max())
    }

    static let agentTypeOrder = ["Explore", "Plan", "general-purpose", "claude-code-guide", "statusline-setup", "custom"]

    /// The stored type of a run whose hook event carried no agent type. Claude Code fires SubagentStop, with an empty
    /// `agent_type` and no SubagentStart before it, when one of its own internal agents finishes (prompt suggestions,
    /// /btw side questions; Claude Code hooks reference, "SubagentStop input"). Every subagent Claude starts with the
    /// Agent tool carries its type, so a run without one is not a subagent of the task and isn't counted. On the
    /// founder's Mac, 18 Oct 2026: 370 such runs against 15 typed ones, each created by a stop alone, most of them
    /// minutes after Claude had already stopped.
    static let internalAgentType = "unknown"

    /// A task's types in display order: the built-in types, then custom agents the user approved by name (A to Z), then
    /// Custom. Claude Code's internal agents (`internalAgentType`) are left out.
    static func orderedAgentTypes(_ types: some Sequence<String>) -> [String] {
        let present = Set(types)
        let builtIn = agentTypeOrder.dropLast().filter(present.contains)
        let approved = present.subtracting(agentTypeOrder).subtracting([internalAgentType]).sorted()
        return builtIn + approved + agentTypeOrder.suffix(1).filter(present.contains)          // "custom", last
    }

    /// Display names for the types Claude Code sends, made readable: Claude Code's own names, with what Explore is for
    /// (its read-only research agent). A custom or plugin agent's own name reaches Clepso only when the user approved
    /// it in Settings, letter for letter (DECISIONS C8, amended 19 Oct 2026); it is shown exactly as approved.
    static func agentTypeName(_ type: String) -> String {
        switch type {
        case "general-purpose": Copy.Agents.general
        case "Explore": Copy.Agents.explore
        case "Plan": Copy.Agents.plan
        case "claude-code-guide": Copy.Agents.guide
        case "statusline-setup": Copy.Agents.statusLine
        case "custom": Copy.Agents.custom
        default: type
        }
    }

    /// How long a subagent with no stop counts as running, from its start. Claude Code sends a stop when a subagent
    /// finishes, background ones too (founder's Mac, 19 Oct 2026: stops arriving up to 10 minutes after the task that
    /// started them had ended), but nothing if Claude Code is closed or crashes first, and an async hook can be lost.
    /// The longest run seen there took under two hours; the same six hours as a task without a stop.
    static let agentRunCap: TimeInterval = 6 * 3600

    /// A task with no stop for 6 hours is treated as finished (Claude Code was closed mid-task). Claude Code's internal
    /// agents (`internalAgentType`) are left out of every count; they're stored only when a stop arrives, so each one
    /// is also one of the task's finished runs. `open` are the subagents with no stop yet, from any task: each one
    /// started under `agentRunCap` ago is running now, counted in `live` and in its own task's `stillRunning`, even
    /// when that task has ended; older ones are the task's `noStopSeen`.
    ///
    /// Exact counts (sheet item 9): `background` holds each session's latest exact report of Claude Code's in-flight
    /// background work. For such a session, of the subagents that started before the report, exactly as many of each
    /// type are running as the report listed, less the stops received since; any more open ones stopped without their
    /// stop reaching Clepso (they become the task's `noStopSeen`), and any fewer were started before Clepso saw them
    /// (shown as running, start not seen). Subagents started after the report are counted from their start and stop.
    /// Sessions without a report keep the start-and-stop inference.
    static func agents(_ tasks: [Store.AgentTask], open: [Store.OpenAgentRun] = [], background: [Store.BackgroundSnapshot] = [], now: Date,
                       staleAfter: TimeInterval = Freshness.localTelemetryTTL) -> AgentsSummary {
        let recent = open.filter { now.timeIntervalSince($0.startedAt) < agentRunCap }
        let reports = Dictionary(background.filter { now.timeIntervalSince($0.reportedAt) < agentRunCap }.map { ($0.sessionRef, $0) },
                                 uniquingKeysWith: { a, b in a.reportedAt >= b.reportedAt ? a : b })
        let bySession = Dictionary(grouping: recent, by: \.sessionRef)
        var counted = recent.filter { reports[$0.sessionRef] == nil }
        var untracked: [AgentsSummary.LiveAgent] = []
        var exactAt: [Date] = []
        for report in reports.values.sorted(by: { $0.sessionRef < $1.sessionRef }) {
            let runs = bySession[report.sessionRef] ?? []
            let after = runs.filter { $0.startedAt > report.reportedAt }
            let before = Dictionary(grouping: runs.filter { $0.startedAt <= report.reportedAt }, by: \.agentType)
            var running = after.count
            counted += after
            for type in Set(before.keys).union(report.agentsInFlight.keys).sorted() where type != internalAgentType {
                let still = max(0, (report.agentsInFlight[type] ?? 0) - (report.stoppedSince[type] ?? 0))
                let tracked = (before[type] ?? []).sorted { $0.startedAt > $1.startedAt }.prefix(still)
                counted += tracked
                running += still
                let lastSeen = report.sessionLastEvent
                untracked += Array(repeating: AgentsSummary.LiveAgent(type: agentTypeName(type), startedAt: report.reportedAt,
                                                                      taskStartedAt: report.reportedAt, inLatestTask: false, lastSeen: lastSeen,
                                                                      stale: now.timeIntervalSince(lastSeen) >= staleAfter, untracked: true),
                                    count: still - tracked.count)
            }
            if running > 0 { exactAt.append(report.reportedAt) }
        }
        let runningByTask = Dictionary(grouping: counted, by: \.taskID).mapValues(\.count)
        let mapped = tasks.sorted { $0.startedAt > $1.startedAt }.map { t in
            let internalRuns = t.byType[internalAgentType] ?? 0
            let agents = t.agents - internalRuns, finished = max(0, t.finished - internalRuns)
            let stillRunning = min(runningByTask[t.id] ?? 0, agents - finished)
            var task = AgentsSummary.Task(id: t.id, startedAt: t.startedAt, endedAt: t.endedAt,
                                          running: t.endedAt == nil && now.timeIntervalSince(t.startedAt) < 6 * 3600,
                                          agents: agents, finished: finished,
                                          byType: orderedAgentTypes(t.byType.keys).compactMap { type in t.byType[type].map { (agentTypeName(type), $0) } })
            task.stillRunning = stillRunning
            task.noStopSeen = max(0, agents - finished - stillRunning)
            return task
        }
        var result = summary(mapped, now: now)
        let latest = mapped.first?.id
        result.live = counted.sorted { $0.startedAt > $1.startedAt }.map { run in
            let lastSeen = max(run.startedAt, run.sessionLastEvent)
            return AgentsSummary.LiveAgent(type: agentTypeName(run.agentType), startedAt: run.startedAt, taskStartedAt: run.taskStartedAt,
                                           inLatestTask: run.taskID == latest, lastSeen: lastSeen,
                                           stale: now.timeIntervalSince(lastSeen) >= staleAfter)
        } + untracked
        // Exact only when every session with a subagent running now has a report.
        let inferred = Set(counted.map(\.sessionRef)).subtracting(reports.keys)
        result.liveExactAt = inferred.isEmpty ? exactAt.max() : nil
        result.backgroundOther = backgroundOrder.compactMap { type in
            let n = reports.values.map { $0.otherWork[type] ?? 0 }.reduce(0, +)
            return n > 0 ? AgentsSummary.BackgroundWork(name: backgroundTypeName(type), count: n) : nil
        }
        return result
    }

    /// Claude Code's other kinds of background work, in the order the Running now card lists them.
    static let backgroundOrder = ["shell", "monitor", "workflow", "teammate", "cloud_session", "mcp_task", "other"]

    static func backgroundTypeName(_ type: String) -> String {
        switch type {
        case "shell": Copy.Agents.bgShell
        case "monitor": Copy.Agents.bgMonitor
        case "workflow": Copy.Agents.bgWorkflow
        case "teammate": Copy.Agents.bgTeammate
        case "cloud_session": Copy.Agents.bgCloud
        case "mcp_task": Copy.Agents.bgMCP
        default: Copy.Agents.bgOther
        }
    }

    /// Codex's built-in roles first, then the user's own (Custom).
    static let codexRoleOrder = ["default", "explorer", "worker", "awaiter", CodexAgents.customRole]

    /// A role the user approved (sheet item 10) arrives by name and is shown as it is, like an approved Claude Code agent.
    static func codexRoleName(_ role: String) -> String {
        switch role {
        case "default": Copy.Agents.codexDefault
        case "explorer": Copy.Agents.codexExplorer
        case "worker": Copy.Agents.codexWorker
        case "awaiter": Copy.Agents.codexAwaiter
        case CodexAgents.customRole: Copy.Agents.custom
        default: role
        }
    }

    /// Codex's roles in display order: built-in, then approved names (A to Z), then Custom.
    static func orderedCodexRoles(_ roles: some Sequence<String>) -> [String] {
        let present = Set(roles)
        return codexRoleOrder.dropLast().filter(present.contains) + present.subtracting(codexRoleOrder).sorted()
            + codexRoleOrder.suffix(1).filter(present.contains)
    }

    /// Codex's tasks (item 4), with the same six-hour rule for a turn Codex never closed. Its auto-reviews ride along
    /// as `reviews` and count toward no agent figure.
    static func codexAgents(_ tasks: [CodexAgents.Task], now: Date) -> AgentsSummary {
        let mapped = tasks.sorted { $0.startedAt > $1.startedAt }.map { t in
            AgentsSummary.Task(id: t.id, startedAt: t.startedAt, endedAt: t.endedAt,
                               running: t.endedAt == nil && now.timeIntervalSince(t.startedAt) < 6 * 3600,
                               agents: t.agents, finished: t.finished,
                               byType: orderedCodexRoles(t.byRole.keys).compactMap { role in t.byRole[role].map { (codexRoleName(role), $0) } },
                               reviews: t.reviews)
        }
        return summary(mapped, now: now)
    }

    /// The latest task, the eight most recent, and the last 30 days' figures.
    static func summary(_ mapped: [AgentsSummary.Task], now: Date) -> AgentsSummary {
        let month = mapped.filter { now.timeIntervalSince($0.startedAt) <= 30 * 86_400 }
        return AgentsSummary(latest: mapped.first, recent: Array(mapped.prefix(8)), tasks: month.count,
                             tasksWithAgents: month.filter { $0.agents > 0 }.count, totalAgents: month.map(\.agents).reduce(0, +),
                             mostInOneTask: month.map(\.agents).max() ?? 0)
    }

    static func rank(_ key: String) -> Int { poolOrder.firstIndex(of: key) ?? poolOrder.count }

    /// How far back the pace line looks: recent enough to follow a change of pace, long enough to be steady.
    static func paceLookback(_ poolKey: String) -> TimeInterval {
        window(of: poolKey) == "five_hour" ? 90 * 60 : 24 * 3600
    }

    // MARK: - Cards

    static func card(_ s: PoolState, source: SourceDescriptor, connection: ConnectionState, now: Date) -> PoolCardModel {
        let used: Provenanced<Decimal>
        if let value = s.usedPct, let at = s.lastProviderMeasured {
            used = .measured(value, evidence: .officialLocalTelemetry, quality: .reported, observedAt: at, observationID: nil)
        } else {
            used = .absent(s.usedAbsence ?? .providerOmitted, evidence: .officialLocalTelemetry, observedAt: s.lastSeen, observationID: nil)
        }
        let resets: Provenanced<Date>
        if let reset = s.resetsAt, let at = s.lastProviderMeasured {
            resets = .measured(reset, evidence: .officialLocalTelemetry, quality: .reported, observedAt: at, observationID: nil)
        } else {
            resets = .absent(.providerOmitted, evidence: .officialLocalTelemetry, observedAt: s.lastSeen, observationID: nil)
        }
        let state = CardState(limit: s.limit, hasResetTime: s.resetsAt != nil, connected: connection == .connected,
                              availableAgain: availableAgain(s, now: now))
        var model = PoolCardModel(scope: scope(of: s.poolKey), source: source, used: used, resetsAt: resets, card: state, connection: connection)
        // The window's high-water mark (cleared when a window opens), or the last value for a state built without one.
        model.windowReachedLimit = [s.highWater, s.usedPct].compactMap { $0 }.max().map { $0 >= EngineConfig().exhausted } ?? false
        return model
    }

    /// "Available again" only from the reducer's verified G6 transition, only while that reading is still
    /// the newest one, for 60 minutes, and never over a higher limit state (an understatement is never shown).
    static func availableAgain(_ s: PoolState, now: Date) -> CardState.AvailableAgain? {
        guard s.limit == .available, let ready = s.readyAgainWindow, let window = s.window, window.id != ready,
              let measured = s.lastProviderMeasured, abs(measured.timeIntervalSince(window.openedAt)) < 0.001,
              now.timeIntervalSince(window.openedAt) < availableAgainFor else { return nil }
        return .verified
    }

    // MARK: - Session and plan

    static func session(_ input: OverviewInput, now: Date) -> SessionRowModel? {
        guard let summary = input.sessionSummaries.first,
              let state = input.sessions.first(where: { $0.sessionRef == summary.sessionRef }) else { return nil }
        func value<T>(_ kind: MetricKind, _ extract: (MetricValue) -> T?) -> Provenanced<T> {
            guard let v = state.values[kind] else {
                return .absent(.providerOmitted, evidence: .officialLocalTelemetry, observedAt: state.lastSeen, observationID: nil)
            }
            if case .absent(let reason) = v.value {
                return .absent(reason, evidence: .officialLocalTelemetry, observedAt: v.observedAt, observationID: nil)
            }
            guard let extracted = extract(v.value) else {
                return .absent(.rejectedBySanitizer, evidence: .officialLocalTelemetry, observedAt: v.observedAt, observationID: nil)
            }
            return .measured(extracted, evidence: .officialLocalTelemetry, quality: v.quality, observedAt: v.observedAt, observationID: nil)
        }
        return SessionRowModel(
            modelName: summary.modelDisplayName ?? state.modelID,
            contextUsed: value(.contextUsedPct) { if case .percent(let d) = $0 { d } else { nil } },
            contextTokens: value(.contextTokens) { if case .tokens(let n) = $0 { n } else { nil } },
            contextWindow: value(.contextWindowSize) { if case .tokens(let n) = $0 { n } else { nil } })
    }

    /// Every stored session in summary order (newest first), each value only if Claude Code reported it.
    static func sessionDetails(_ input: OverviewInput) -> [SessionDetail] {
        let states = Dictionary(input.sessions.map { ($0.sessionRef, $0) }, uniquingKeysWith: { a, _ in a })
        return input.sessionSummaries.compactMap { summary in
            guard let s = states[summary.sessionRef] else { return nil }
            func v(_ kind: MetricKind) -> MetricValue? { s.values[kind]?.value }
            func pct(_ kind: MetricKind) -> Decimal? { if case .percent(let d)? = v(kind) { d } else { nil } }
            func tokens(_ kind: MetricKind) -> Int64? { if case .tokens(let n)? = v(kind) { n } else { nil } }
            func count(_ kind: MetricKind) -> Int64? { if case .count(let n)? = v(kind) { n } else { nil } }
            func ms(_ kind: MetricKind) -> Int64? { if case .duration(let n)? = v(kind) { n } else { nil } }
            let warm: Bool? = if case .flag(let b)? = v(.cacheWarm) { b } else { nil }
            let cost: Decimal? = if case .usd(let d)? = v(.apiCostUSD) { d } else { nil }
            return SessionDetail(id: summary.sessionRef, modelName: summary.modelDisplayName ?? s.modelID, lastSeen: s.lastSeen,
                                 contextPct: pct(.contextUsedPct), tokensIn: tokens(.contextTokens), tokensOut: tokens(.sessionOutputTokens),
                                 contextWindow: tokens(.contextWindowSize), costUSD: cost, wallMs: ms(.wallDuration), apiMs: ms(.apiDuration),
                                 linesAdded: count(.linesAdded), linesRemoved: count(.linesRemoved), cacheHitPct: pct(.cacheHitPct),
                                 cacheRequests: count(.cacheRequests), cacheMisses: count(.cacheMisses), cacheWarm: warm)
        }
    }

    static func modelGroups(_ sessions: [SessionDetail]) -> [ModelGroup] {
        var groups: [String: (sessions: Int, cost: Decimal, lines: Int64, apiMs: Int64)] = [:]
        for s in sessions {
            let name = s.modelName ?? "Unknown model"
            var g = groups[name] ?? (0, 0, 0, 0)
            g.sessions += 1
            g.cost += s.costUSD ?? 0
            g.lines += s.linesAdded ?? 0
            g.apiMs += s.apiMs ?? 0
            groups[name] = g
        }
        let total = groups.values.map(\.cost).reduce(0, +)
        return groups.map { ModelGroup(name: $0.key, sessions: $0.value.sessions, costUSD: $0.value.cost, linesAdded: $0.value.lines,
                                       apiMs: $0.value.apiMs,
                                       share: total > 0 ? NSDecimalNumber(decimal: $0.value.cost / total).doubleValue : 0) }
            .sorted { ($0.costUSD, $1.name) > ($1.costUSD, $0.name) }
    }

    static func provenance(_ plan: Store.PlanIdentity?) -> PlanProvenance {
        switch plan?.evidence {
        case .officialAPI: .providerVerified
        case .userConfirmed: .userConfirmed
        case .userSelectedUnverified: .selectedUnverified
        default: .notSet
        }
    }

    /// provider header, including F15 (metrics live, no plan).
    static func header(plan: Store.PlanIdentity?, provenance: PlanProvenance, metricsLive: Bool) -> String {
        guard let plan, provenance != .notSet else {
            return metricsLive ? "Claude Code metrics connected · plan not verified" : "Claude · Plan not set"
        }
        let short = plan.displayName.hasPrefix("Claude ") ? String(plan.displayName.dropFirst("Claude ".count)) : plan.displayName
        return "Claude · \(short) · \(StatusStyles.of(provenance).label)"
    }

    // MARK: - Aggregate

    /// Precedence: demo > not connected or waiting for the first reading > exhausted or reset expected > approaching or
    /// nearly exhausted > stale > ok. When the shape showing is built from old readings, the stale mark opens its ring
    /// (design system, Menu bar: "A state built from old readings opens the ring at five o'clock and sets a dot in the
    /// gap"): the cards that put that shape there have no live reading, whatever the other cards say. A Codex limit
    /// reached two days ago shows the flatline with the mark even while Claude Code's readings are live.
    ///
    /// DECISIONS 19 Oct 2026 (founder): (1) a passed reset flatlines the icon only for a window that reached its limit;
    /// a window past its reset that never reached it is just an old reading to the icon, never above a live card.
    /// (2) No % beside the flatline. (3) The % is that of the cards behind the shape, from their live readings only, and
    /// the line ends "· last seen {age}" whenever the shape comes from old readings.
    static func aggregate(_ cards: [PoolCardModel], input: OverviewInput, empty: OverviewSnapshot.Empty?, lastSeen: Date?,
                          now: Date, staleAfter: TimeInterval, zone: TimeZone, locale: Locale)
        -> (OverviewSnapshot.Icon, Bool, String?, String) {
        if input.isDemo { return (.demo, false, "DEMO", "Demo data · not your account") }
        switch empty {
        case .notConnected: return (.notConnected, false, nil, "Not connected")
        case .waitingForFirstReading: return (.waiting, false, nil, "Installed · waiting for first reading")
        case nil: break
        }
        func isLive(_ card: PoolCardModel) -> Bool { card.valueState(now: now, staleAfter: staleAfter) == .live }
        // Decision 1: an idle window past its reset leaves the shape to the other cards.
        let shaping = cards.filter { $0.card != .resetExpected || $0.windowReachedLimit }
        let live = shaping.filter(isLive)
        let age = lastSeen.map { Formatting.age(of: $0, now: now, zone: zone, locale: locale) }
        // F06: Claude Code is reporting but sends no rate limits, so no pool has a value. That is "not available", not stale.
        let reporting = lastSeen.map { now.timeIntervalSince($0) < staleAfter } ?? false
        if live.isEmpty, reporting, cards.allSatisfy({ $0.used.value == nil }) {
            return (.ok, false, nil, "Account quota not available" + (age.map { " · updated \($0)" } ?? ""))
        }
        let blocked: [CardState] = [.exhausted, .exhaustedNoReset, .exhaustedOverage, .resetExpected]
        // True when none of the cards behind the shape showing has a live reading.
        func fromOldReadings(_ behind: [PoolCardModel]) -> Bool { !behind.contains(where: isLive) }
        // Decision 3: the highest live % among the cards behind the shape; none when they are all old.
        func percent(_ behind: [PoolCardModel]) -> String? {
            input.showPercent ? behind.filter(isLive).compactMap(\.used.value).max().map(Formatting.percent) : nil
        }
        // Decision 3: a shape from old readings says how old, by the newest reading behind it.
        func staleSuffix(_ behind: [PoolCardModel]) -> String {
            guard fromOldReadings(behind), let newest = behind.compactMap(\.used.observedAt).max() ?? lastSeen else { return "" }
            return " · last seen " + Formatting.age(of: newest, now: now, zone: zone, locale: locale)
        }
        if let worst = blocked.lazy.compactMap({ state in shaping.first { $0.card == state } }).first {
            let behind = shaping.filter { blocked.contains($0.card) }
            let provider = worst.source.displayName      // the agent whose limit it is: Claude Code or Codex
            let line: String = switch worst.card {
            case .exhausted:
                "\(provider) limit reached · reset expected " + (worst.resetsAt.value.map { Formatting.resetTime($0, now: now, zone: zone, locale: locale) } ?? "")
            case .exhaustedOverage: "\(provider) limit reached · paid usage may continue"
            case .resetExpected: "\(provider) reset expected · awaiting next update"
            default: "\(provider) limit reached · reset time not reported"
            }
            return (.exhausted, fromOldReadings(behind), nil, line + staleSuffix(behind))     // decision 2: no %
        }
        let nearingCards = shaping.filter { $0.card == .approaching || $0.card == .critical }
        let nearing = nearingCards.count
        if nearing > 0 {
            return (.approaching, fromOldReadings(nearingCards), percent(nearingCards),
                    (nearing == 1 ? "1 limit nearing capacity" : "\(nearing) limits nearing capacity") + staleSuffix(nearingCards))
        }
        guard !live.isEmpty else { return age.map { (.stale, false, nil, "Last seen \($0)") } ?? (.notConnected, false, nil, "Not connected") }
        // An idle window past its reset is left out: its reset has passed, so it is no reason to doubt availability.
        let allAvailable = shaping.allSatisfy { [.available, .availableAgain, .availableAgainUser].contains($0.card) }
        let updated = age.map { " · updated \($0)" } ?? ""
        // C7: only the limits Claude Code reports are known; /usage can show others (a per-model weekly limit).
        return (.ok, false, percent(live), (allAvailable ? "Reported limits available" : "Account quota not available") + updated)
    }
}
