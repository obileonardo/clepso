import Foundation
import IntegrationSnapshot
import UserNotifications

struct PhoneReminderClient: CompanionReminderClient {
    func replace(_ reminders: [CompanionReminderPlan.Reminder]) async throws {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(CompanionReminderPlan.prefix) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: old)
        do {
            for row in reminders {
                let delay = row.fireAt.timeIntervalSinceNow
                guard delay > 1 else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Expected \(row.provider.displayName) \(row.window.displayName) reset"
                content.body = "Based on the last shared report. Open Clepso to check the latest reading."
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                try await center.add(UNNotificationRequest(identifier: row.id, content: content, trigger: trigger))
            }
        } catch {
            // A partial replacement must not retain only some of the intended plan.
            center.removePendingNotificationRequests(withIdentifiers: reminders.map(\.id))
            throw error
        }
    }
}
