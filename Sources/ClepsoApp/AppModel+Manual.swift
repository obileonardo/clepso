import Domain
import Foundation
import SubscriptionCatalog

extension AppModel {
    public enum ManualEditError: Error { case unavailable }
    public func saveManualAllowance(providerID: String, window: ManualAllowance.Window, usedPercent: Decimal?,
                                    resetsAt: Date?, observedAt: Date, planID: String?, paidOverage: Bool) async throws {
        guard !demo, let store else { throw ManualEditError.unavailable }
        let publisher = ManualProvider.supported.first { $0.id == providerID }?.publisher ?? ""
        let plan = try PlanCatalog.bundled().subscriptionPlans(publisher: publisher).first { $0.id == planID }
        let value = try ManualAllowance(providerID: providerID, window: window, usedPercent: usedPercent, resetsAt: resetsAt,
                                        observedAt: observedAt, enteredAt: environment.clock.now(), planCatalogID: plan?.id,
                                        paidOverage: paidOverage)
        try await store.recordManualAllowance(value)
        manualAllowances = try await store.manualAllowances()
    }

    public func removeManualAllowance(_ value: ManualAllowance) async throws {
        guard !demo, let store else { throw ManualEditError.unavailable }
        try await store.removeManualAllowance(providerID: value.providerID, window: value.window)
        manualAllowances = try await store.manualAllowances()
    }
}
