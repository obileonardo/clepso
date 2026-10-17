import DesignSystem
import Domain
import Foundation
import Storage
import UsageEngine

/// Store state → what the menu bar shows (UX_SPEC §1.2–§1.4). Pure: the clock, zone and locale are passed in.
public enum OverviewProjection {
    /// Display order of the Claude Code pools; unknown keys follow alphabetically.
    static let poolOrder = ["claude-code.rate_limits.five_hour", "claude-code.rate_limits.seven_day", "claude-code.rate_limits.spend_limit"]
    /// `card.availableAgain` reverts to `card.available` after 60 minutes (UX_SPEC §1.2).
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
        let provider = empty != nil ? nil : ProviderSection(
            identity: .claudeCode, planName: input.plan?.displayName, plan: plan,
            header: header(plan: input.plan, provenance: plan, metricsLive: anyLive),
            pools: rows, session: session(input, now: now), sessionCount: input.sessionSummaries.count,
            sourceVersion: input.sourceVersion, lastSeen: lastSeen, unreadLimitWindows: input.unreadLimitWindows,
            sessions: sessionDetails(input), models: modelGroups(sessionDetails(input)))

        let (icon, staleMark, text, line) = aggregate(rows.map(\.model), input: input, empty: empty, lastSeen: lastSeen,
                                                       now: now, staleAfter: staleAfter, zone: zone, locale: locale)
        return OverviewSnapshot(now: now, isDemo: input.isDemo, icon: icon, iconStaleMark: staleMark, iconText: text,
                                aggregateLine: line, updatedAt: lastSeen, provider: provider, empty: empty,
                                agents: input.agentsTracking ? agents(input.agentTasks, now: now) : nil,
                                codex: input.codexEnabled && !input.isDemo ? codex(input, now: now) : nil)
    }

    static let codexSource = SourceDescriptor(evidence: .officialLocalTelemetry, displayName: "Codex", version: nil)

    /// Codex's section: 5-hour first, then weekly, then any other window; nil until Codex has written a reading.
    static func codex(_ input: OverviewInput, now: Date) -> AgentLimitsSection? {
        guard !input.codexPools.isEmpty else { return nil }
        let order = ["five_hour", "seven_day"]
        let ordered = input.codexPools.sorted {
            (order.firstIndex(of: window(of: $0.poolKey)) ?? order.count, $0.poolKey) < (order.firstIndex(of: window(of: $1.poolKey)) ?? order.count, $1.poolKey)
        }
        let rows = ordered.map { state in
            PoolRow(poolKey: state.poolKey, providerField: "rate_limits.\(window(of: state.poolKey) == "five_hour" ? "primary" : "secondary").used_percent",
                    model: card(state, source: codexSource, connection: .connected, now: now),
                    receivedAt: state.latest?.receivedAt, recent: input.recent[state.poolKey] ?? [],
                    history: input.history[state.poolKey] ?? [],
                    pace: PaceEstimate.estimate(input.history[state.poolKey] ?? [], windowOpenedAt: state.window?.openedAt,
                                                resetsAt: state.resetsAt, now: now, lookback: paceLookback(state.poolKey)))
        }
        return AgentLimitsSection(name: "Codex", plan: input.codexPlan, model: input.codexModel, pools: rows,
                                  lastSeen: input.codexPools.compactMap(\.lastSeen).max())
    }

    static let agentTypeOrder = ["Explore", "Plan", "general-purpose", "claude-code-guide", "statusline-setup", "custom", "unknown"]

    /// Display names for the stored types.
    static func agentTypeName(_ type: String) -> String {
        switch type {
        case "general-purpose": Copy.Agents.general
        case "claude-code-guide": Copy.Agents.guide
        case "statusline-setup": Copy.Agents.statusLine
        case "custom": Copy.Agents.custom
        case "unknown": Copy.Agents.unknown
        default: type
        }
    }

    /// A task with no stop for 6 hours is treated as finished (Claude Code was closed mid-task).
    static func agents(_ tasks: [Store.AgentTask], now: Date) -> AgentsSummary {
        let mapped = tasks.sorted { $0.startedAt > $1.startedAt }.map { t in
            AgentsSummary.Task(id: t.id, startedAt: t.startedAt, endedAt: t.endedAt,
                               running: t.endedAt == nil && now.timeIntervalSince(t.startedAt) < 6 * 3600,
                               agents: t.agents, finished: t.finished,
                               byType: agentTypeOrder.compactMap { type in t.byType[type].map { (agentTypeName(type), $0) } })
        }
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
        return PoolCardModel(scope: scope(of: s.poolKey), source: source, used: used, resetsAt: resets, card: state, connection: connection)
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

    /// UX_SPEC §1.3 provider header, including F15 (metrics live, no plan).
    static func header(plan: Store.PlanIdentity?, provenance: PlanProvenance, metricsLive: Bool) -> String {
        guard let plan, provenance != .notSet else {
            return metricsLive ? "Claude Code metrics connected · plan not verified" : "Claude · Plan not set"
        }
        let short = plan.displayName.hasPrefix("Claude ") ? String(plan.displayName.dropFirst("Claude ".count)) : plan.displayName
        return "Claude · \(short) · \(StatusStyles.of(provenance).label)"
    }

    // MARK: - Aggregate (UX_SPEC §1.4)

    /// Precedence: demo > exhausted or reset expected > approaching or nearly exhausted > stale > ok.
    /// Stale adds a clock mark to the shape that is showing.
    static func aggregate(_ cards: [PoolCardModel], input: OverviewInput, empty: OverviewSnapshot.Empty?, lastSeen: Date?,
                          now: Date, staleAfter: TimeInterval, zone: TimeZone, locale: Locale)
        -> (OverviewSnapshot.Icon, Bool, String?, String) {
        if input.isDemo { return (.demo, false, "DEMO", "Demo data · not your account") }
        switch empty {
        case .notConnected: return (.stale, false, nil, "Not connected")
        case .waitingForFirstReading: return (.stale, false, nil, "Installed · waiting for first reading")
        case nil: break
        }
        let live = cards.filter { $0.valueState(now: now, staleAfter: staleAfter) == .live }
        let age = lastSeen.map { Formatting.age(of: $0, now: now, zone: zone, locale: locale) }
        // F06: Claude Code is reporting but sends no rate limits, so no pool has a value. That is "not available", not stale.
        let reporting = lastSeen.map { now.timeIntervalSince($0) < staleAfter } ?? false
        if live.isEmpty, reporting, cards.allSatisfy({ $0.used.value == nil }) {
            return (.ok, false, nil, "Account quota not available" + (age.map { " · updated \($0)" } ?? ""))
        }
        let staleSuffix = live.isEmpty ? age.map { " · last seen \($0)" } ?? "" : ""
        let highest = input.showPercent && !live.isEmpty ? live.compactMap(\.used.value).max().map(Formatting.percent) : nil
        let provider = ProviderIdentity.claudeCode.wordmark

        let blocked: [CardState] = [.exhausted, .exhaustedNoReset, .exhaustedOverage, .resetExpected]
        if let worst = blocked.lazy.compactMap({ state in cards.first { $0.card == state } }).first {
            let line: String = switch worst.card {
            case .exhausted:
                "\(provider) limit reached · reset expected " + (worst.resetsAt.value.map { Formatting.resetTime($0, now: now, zone: zone, locale: locale) } ?? "")
            case .exhaustedOverage: "\(provider) limit reached · paid usage may continue"
            case .resetExpected: "\(provider) reset expected · awaiting next update"
            default: "\(provider) limit reached · reset time not reported"
            }
            return (.exhausted, live.isEmpty, nil, line + staleSuffix)
        }
        let nearing = cards.filter { $0.card == .approaching || $0.card == .critical }.count
        if nearing > 0 {
            return (.approaching, live.isEmpty, highest, (nearing == 1 ? "1 limit nearing capacity" : "\(nearing) limits nearing capacity") + staleSuffix)
        }
        guard !live.isEmpty else { return (.stale, false, nil, age.map { "Last seen \($0)" } ?? "Not connected") }
        let allAvailable = cards.allSatisfy { [.available, .availableAgain, .availableAgainUser].contains($0.card) }
        let updated = age.map { " · updated \($0)" } ?? ""
        // C7: only the limits Claude Code reports are known; /usage can show others (a per-model weekly limit).
        return (.ok, false, highest, (allAvailable ? "Reported limits available" : "Account quota not available") + updated)
    }
}
