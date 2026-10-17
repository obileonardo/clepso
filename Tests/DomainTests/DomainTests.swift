import Foundation
import Testing
@testable import Domain

@Suite("Domain contracts")
struct DomainTests {
    let t0 = Date(timeIntervalSince1970: 1_792_159_200)

    @Test("MetricValue round-trips through Codable, absence included",
          arguments: [MetricValue.percent(83.5), .percent(104), .tokens(68_000), .usd(Decimal(string: "0.0412")!),
                      .instant(Date(timeIntervalSince1970: 1_792_167_300)), .absent(.providerOmitted), .absent(.providerNull)])
    func metricValueCodable(value: MetricValue) throws {
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(MetricValue.self, from: data) == value)
    }

    @Test("Freshness has two tiers: live under 10 minutes, stale from 10 minutes")
    func freshnessTiers() {
        let ttl = Freshness.localTelemetryTTL
        #expect(Freshness.of(lastMeasured: t0, at: t0.addingTimeInterval(599), ttl: ttl) == .live)
        #expect(Freshness.of(lastMeasured: t0, at: t0.addingTimeInterval(600), ttl: ttl) == .stale(age: 600))
        #expect(Freshness.of(lastMeasured: nil, at: t0, ttl: ttl) == .never)
    }

    @Test("Provenanced carries either a value or a reason, never both")
    func provenancedShape() {
        let measured = Provenanced<Decimal>.measured(83, evidence: .officialLocalTelemetry, quality: .reported,
                                                     observedAt: t0, observationID: nil)
        #expect(measured.value == 83 && measured.absence == nil)
        let absent = Provenanced<Decimal>.absent(.providerOmitted, evidence: .officialLocalTelemetry,
                                                 observedAt: t0, observationID: nil)
        #expect(absent.value == nil && absent.absence == .providerOmitted && absent.quality == .unknown)
    }

    @Test("Snapshot freshness is computed from lastProviderMeasured, not stored")
    func snapshotFreshness() {
        let absent = Provenanced<Decimal>.absent(.providerOmitted, evidence: .officialLocalTelemetry, observedAt: nil, observationID: nil)
        let snapshot = PoolSnapshot(poolID: UUID(), accountID: UUID(), windowID: nil, usedPct: absent, remainingPct: absent,
                                    resetsAt: .absent(.providerOmitted, evidence: .officialLocalTelemetry, observedAt: nil, observationID: nil),
                                    state: .unknown, lastKnownState: nil, lastProviderMeasured: t0, lastSeen: t0,
                                    omittedSince: nil, highWaterUsedPct: nil, version: 1)
        #expect(snapshot.freshness(at: t0.addingTimeInterval(60)) == .live)
        #expect(snapshot.freshness(at: t0.addingTimeInterval(14 * 60)) == .stale(age: 14 * 60))
    }

    @Test("Evidence tie-break priority follows DATA_MODEL §2.1")
    func evidencePriority() {
        #expect(EvidenceKind.officialAPI.priority > EvidenceKind.officialLocalTelemetry.priority)
        #expect(EvidenceKind.officialLocalTelemetry.priority > EvidenceKind.userConfirmed.priority)
        #expect(EvidenceKind.inferred.priority == 0)
    }
}
