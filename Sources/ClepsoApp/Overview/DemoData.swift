import Domain
import Foundation
import Storage

/// Demo mode (onboarding `demoCta`): a fixed scenario run through the real store and engine,
/// so the demo shows exactly what real readings would. Every screen badges it; a real reading ends it.
/// Increment 1.7: an hour of rising 5-hour usage (history and pace) and a session with every detail.
enum DemoData {
    static func input(now: Date) async throws -> OverviewInput {
        let store = try Store.inMemory(now: now)
        let fiveHour = SubjectKey.pool(providerPoolKey: "claude-code.rate_limits.five_hour")
        let sevenDay = SubjectKey.pool(providerPoolKey: "claude-code.rate_limits.seven_day")
        let session = SubjectKey.session(sessionRef: "demo")
        let meta = Store.SessionMeta(sessionRef: "demo", modelID: "demo-model", modelDisplayName: "Demo model")
        for step in 0...12 {                                         // every 5 minutes for the last hour
            let at = now.addingTimeInterval(Double(step - 12) * 300)
            func o(_ subject: SubjectKey, _ kind: MetricKind, _ value: MetricValue) -> IncomingObservation {
                IncomingObservation(subject: subject, sessionRef: "demo", modelID: "demo-model", kind: kind, value: value,
                                    observedAt: at, receivedAt: at, evidence: .officialLocalTelemetry, quality: .reported,
                                    sourceVersion: "demo", dedupeKey: "demo|\(subject.canonical)|\(kind.rawValue)|\(step)")
            }
            let used = Decimal(59 + step * 2)                        // 59% → 83%
            _ = try await store.ingest([
                o(fiveHour, .quotaUsedPct, .percent(used)),
                o(fiveHour, .resetAt, .instant(now.addingTimeInterval(2 * 3600 + 14 * 60))),
                o(sevenDay, .quotaUsedPct, .percent(Decimal(19 + step / 6))),
                o(sevenDay, .resetAt, .instant(now.addingTimeInterval(2 * 86_400))),
                o(session, .contextUsedPct, .percent(Decimal(30 + step))),
                o(session, .contextTokens, .tokens(Int64(60_000 + step * 2_000))),
                o(session, .sessionOutputTokens, .tokens(Int64(9_000 + step * 700))),
                o(session, .contextWindowSize, .tokens(200_000)),
                o(session, .apiCostUSD, .usd(Decimal(string: "4.20")! + Decimal(step) * Decimal(string: "0.35")!)),
                o(session, .apiDuration, .duration(milliseconds: Int64(1_800_000 + step * 60_000))),
                o(session, .wallDuration, .duration(milliseconds: Int64(5_400_000 + step * 300_000))),
                o(session, .linesAdded, .count(Int64(820 + step * 40))),
                o(session, .linesRemoved, .count(Int64(95 + step * 3))),
                o(session, .cacheHitPct, .percent(97)),
                o(session, .cacheRequests, .count(Int64(140 + step * 6))),
                o(session, .cacheMisses, .count(1)),
                o(session, .cacheWarm, .flag(true)),
            ], session: meta)
        }
        // Agents per task: four prompts in the last hour, the latest still running.
        let plan: [(Double, Double?, [String])] = [(-55, -41, ["Explore", "Explore", "Plan"]), (-38, -30, []),
                                                   (-27, -12, ["general-purpose", "Explore", "custom", "Explore", "Plan"]), (-6, nil, ["Explore", "Plan"])]
        for (i, task) in plan.enumerated() {
            let start = now.addingTimeInterval(task.0 * 60)
            try await store.record(.init(kind: .promptSubmitted, sessionRef: "demo", agentRef: nil, agentType: nil, at: start))
            for (j, type) in task.2.enumerated() {
                let ref = "demo-\(i)-\(j)"
                try await store.record(.init(kind: .subagentStarted, sessionRef: "demo", agentRef: ref, agentType: type, at: start.addingTimeInterval(Double(20 + j * 15))))
                if task.1 != nil || j == 0 {
                    try await store.record(.init(kind: .subagentStopped, sessionRef: "demo", agentRef: ref, agentType: type, at: start.addingTimeInterval(Double(200 + j * 40))))
                }
            }
            if let end = task.1 { try await store.record(.init(kind: .stopped, sessionRef: "demo", agentRef: nil, agentType: nil, at: now.addingTimeInterval(end * 60))) }
        }
        var input = try await AppModel.read(store, now: now)
        input.agentsTracking = true
        input.isDemo = true
        return input
    }
}
