/// The platform adapter replaces only Clepso's expected-reset notifications, preserving unrelated requests.
public protocol CompanionReminderClient: Sendable {
    func replace(_ reminders: [CompanionReminderPlan.Reminder]) async throws
}

/// OS notification calls suspend. Queue complete replacements so an older add cannot outlive a later opt-out.
/// Caller cancellation does not cancel the queued cleanup; a failed replacement remains retryable.
public actor CompanionReminderCoordinator {
    private let client: any CompanionReminderClient
    private var tail: Task<Void, Error>?
    private var applied: [String: Double]?

    public init(client: any CompanionReminderClient) { self.client = client }

    public func replace(_ reminders: [CompanionReminderPlan.Reminder]) async throws {
        let previous = tail
        let next = Task {
            _ = try? await previous?.value
            try await self.apply(reminders)
        }
        tail = next
        try await next.value
    }

    private func apply(_ reminders: [CompanionReminderPlan.Reminder]) async throws {
        let signature = Dictionary(reminders.map { ($0.id, $0.fireAt.timeIntervalSince1970) }, uniquingKeysWith: { _, latest in latest })
        guard signature != applied else { return }
        do {
            try await client.replace(reminders)
            applied = signature
        } catch {
            applied = nil
            throw error
        }
    }
}
