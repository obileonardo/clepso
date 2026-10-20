import Domain
import Foundation
import Testing

struct ManualAllowanceTests {
    let now = Date(timeIntervalSince1970: 1_792_159_200)
    @Test("The whole percentage must parse, including locale decimals; trailing text is rejected")
    func parsing() {
        #expect(ManualAllowance.parsePercent("83.25", locale: Locale(identifier: "en_US")) == Decimal(string: "83.25"))
        #expect(ManualAllowance.parsePercent("83,25", locale: Locale(identifier: "fr_FR")) == Decimal(string: "83.25"))
        for text in ["83 percent", "1e2", "1.2.3", "101", "-1", "NaN", ".", ""] {
            #expect(ManualAllowance.parsePercent(text, locale: Locale(identifier: "en_US")) == nil)
        }
    }
    @Test("Manual values are user-confirmed and a passed reset never fabricates a new reading")
    func provenance() throws {
        let value = try ManualAllowance(providerID: "cursor", window: .weekly, usedPercent: 100,
                                         resetsAt: now + 3600, observedAt: now, enteredAt: now, paidOverage: true)
        #expect(value.evidence == .userConfirmed && !value.isStale(at: now + 599))
        #expect(value.isStale(at: now + 600) && value.resetPassed(at: now + 3600))
        #expect(value.usedPercent == 100)
    }
    @Test("Invalid values, future observations and empty readings are refused")
    func refusesInvalid() {
        for percent in [Decimal(-1), 101, Decimal.nan] {
            #expect(throws: ManualAllowance.Invalid.percent) {
                try ManualAllowance(providerID: "cursor", window: .daily, usedPercent: percent, resetsAt: nil, observedAt: now, enteredAt: now)
            }
        }
        #expect(throws: ManualAllowance.Invalid.observedAt) {
            try ManualAllowance(providerID: "grok", window: .weekly, usedPercent: 20, resetsAt: nil, observedAt: now + 1, enteredAt: now)
        }
        #expect(throws: ManualAllowance.Invalid.empty) {
            try ManualAllowance(providerID: "chatgpt", window: .weekly, usedPercent: nil, resetsAt: nil, observedAt: now, enteredAt: now)
        }
    }
}
