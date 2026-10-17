import Domain
import Foundation
import Storage

/// Demo mode (UX_SPEC §2.8, onboarding `demoCta`): a fixed scenario run through the real store and engine,
/// so the demo shows exactly what real readings would. Every screen badges it; a real reading ends it.
enum DemoData {
    static func input(now: Date) async throws -> OverviewInput {
        let store = try Store.inMemory(now: now)
        let at = now.addingTimeInterval(-60)
        func observation(_ subject: SubjectKey, _ kind: MetricKind, _ value: MetricValue) -> IncomingObservation {
            IncomingObservation(subject: subject, sessionRef: "demo", modelID: "demo-model", kind: kind, value: value,
                                observedAt: at, receivedAt: at, evidence: .officialLocalTelemetry, quality: .reported,
                                sourceVersion: "demo", dedupeKey: "demo|\(subject.canonical)|\(kind.rawValue)")
        }
        let fiveHour = SubjectKey.pool(providerPoolKey: "claude-code.rate_limits.five_hour")
        let sevenDay = SubjectKey.pool(providerPoolKey: "claude-code.rate_limits.seven_day")
        let session = SubjectKey.session(sessionRef: "demo")
        _ = try await store.ingest([
            observation(fiveHour, .quotaUsedPct, .percent(83)),
            observation(fiveHour, .resetAt, .instant(now.addingTimeInterval(2 * 3600 + 14 * 60))),
            observation(sevenDay, .quotaUsedPct, .percent(21)),
            observation(sevenDay, .resetAt, .instant(now.addingTimeInterval(2 * 86_400))),
            observation(session, .contextUsedPct, .percent(41)),
            observation(session, .contextTokens, .tokens(82_000)),
            observation(session, .contextWindowSize, .tokens(200_000)),
        ], session: Store.SessionMeta(sessionRef: "demo", modelID: "demo-model", modelDisplayName: "Demo model"))
        var input = try await AppModel.read(store)
        input.isDemo = true
        return input
    }
}
