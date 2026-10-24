import Foundation
import Testing
@testable import IntegrationSnapshot

@Suite("Companion relay and expected reset plan") struct CompanionReminderTests {
    let now = Date(timeIntervalSince1970: 1_792_665_600)
    func envelope(source: UsageSnapshot.Source = .automatic, state: UsageSnapshot.State = .reported,
                  observationAge: Double = 0, resetOffset: Double = 3600, expired: Bool = false) -> RelayEnvelope {
        let row = UsageSnapshot.Limit(provider: .codex, window: .fiveHour, source: source, usedPercent: 90,
                                     observedAt: now.addingTimeInterval(-observationAge), resetsAt: now.addingTimeInterval(resetOffset), state: state)
        return RelayEnvelope(snapshot: UsageSnapshot(generatedAt: now, limits: [row]), receivedAt: now,
                             expiresAt: now.addingTimeInterval(expired ? -1 : 900))
    }
    @Test func freshReportPlansExpectedTimeAndRetainsSourceDate() {
        let reminders = CompanionReminderPlan.make(envelope(), enabled: true, leadMinutes: 5, now: now)
        #expect(reminders.count == 1 && reminders[0].fireAt == now.addingTimeInterval(3300))
        #expect(reminders[0].reportedReset == now.addingTimeInterval(3600))
        #expect(reminders[0].id == CompanionReminderPlan.prefix + "codex.fiveHour")
    }
    @Test func staleManualExpiredResetAndDisabledNeverSchedule() {
        for value in [envelope(source: .manual), envelope(state: .resetExpected), envelope(observationAge: 601),
                      envelope(resetOffset: -1), envelope(resetOffset: 8 * 86400), envelope(expired: true)] {
            #expect(CompanionReminderPlan.make(value, enabled: true, leadMinutes: 0, now: now).isEmpty)
        }
        #expect(CompanionReminderPlan.make(envelope(), enabled: false, leadMinutes: 0, now: now).isEmpty)
        #expect(CompanionReminderPlan.make(envelope(), enabled: true, leadMinutes: 999, now: now).isEmpty)
    }
    @Test func decodesPostgRESTFractionalTimestampsWithoutAcceptingDemo() throws {
        let value = envelope(), data = try UsageSnapshot.encoder().encode(value)
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "00Z", with: "00.123456Z")
        let decoded = try RelayEnvelope.decoder().decode(RelayEnvelope.self, from: Data(text.utf8))
        #expect(decoded.valid)
        let demo = RelayEnvelope(snapshot: UsageSnapshot(generatedAt: now, demo: true, limits: []), receivedAt: now, expiresAt: now.addingTimeInterval(900))
        #expect(!demo.valid && !envelope(expired: true).valid)
    }
}
