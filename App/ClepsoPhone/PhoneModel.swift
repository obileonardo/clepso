import Foundation
import IntegrationSnapshot
import Observation
import Sync
import UserNotifications

@MainActor @Observable final class PhoneModel {
    var envelope: RelayEnvelope?
    var email = ""
    var signedInEmail: String?
    var signedIn = false
    var pendingEmail: String?
    var message: String?
    var busy = false
    var now: Date
    var reminders = false
    var leadMinutes = 0
    let client: SyncClient
    let push: PhonePushController
    let link = CompanionWatchLink()
    private let clock: @Sendable () -> Date
    private let cache: URL
    private var generation = 0
    private var changingAccount = false
    private var reminderChoice = 0
    private let reminderCoordinator = CompanionReminderCoordinator(client: PhoneReminderClient())
    init(client: SyncClient, cache: URL, clock: @escaping @Sendable () -> Date, push: PhonePushController? = nil) {
        self.client = client; self.cache = cache; self.clock = clock; now = clock()
        self.push = push ?? PhonePushController(client: client)
        let defaults = UserDefaults.standard
        reminders = defaults.bool(forKey: "companion.reminders")
        leadMinutes = [0,5,15].contains(defaults.integer(forKey: "companion.lead")) ? defaults.integer(forKey: "companion.lead") : 0
        link.onRefresh = { [weak self] in Task { await self?.refresh() } }
        self.push.refresh = { [weak self] in
            guard let self else { return false }
            self.link.start()
            let previous = self.envelope
            await self.refresh()
            return self.envelope != previous
        }
    }
    func start() async {
        link.start()
        signedIn = await client.session != nil
        signedInEmail = await client.session?.email
        pendingEmail = await client.pendingEmail
        if let account = await client.session?.userID {
            if let size = (try? FileManager.default.attributesOfItem(atPath: cache.path)[.size]) as? NSNumber, size.intValue <= 128 * 1024,
               let data = try? Data(contentsOf: cache), let value = try? RelayEnvelope.decoder().decode(CompanionCache.self, from: data) {
                envelope = value.reading(for: account)
            }
            if envelope == nil { try? FileManager.default.removeItem(at: cache) }
        } else { clearSnapshot() }
        // Reconcile persisted-off and signed-out state after crashes, before any network suspension.
        await reconcileReminders()
        await push.start()
        await refresh()
    }
    func requestLink() async {
        guard !busy, !changingAccount else { return }; busy = true; defer { busy = false }
        do {
            try await client.requestEmailLink(email.trimmingCharacters(in: .whitespacesAndNewlines))
            pendingEmail = await client.pendingEmail
            message = "Open the email link on this iPhone to finish signing in."
        } catch { message = "The sign-in link could not be requested. Try again when connected." }
    }
    func callback(_ url: URL) async {
        guard url.scheme == SyncConfig.urlScheme, url.host == SyncConfig.redirectURL.host else { return }
        guard await client.hasPendingSignIn else { message = "Request a sign-in link on this iPhone first."; return }
        guard !push.busy, !changingAccount else { message = "Wait for the background refresh change to finish, then open the sign-in link again."; return }
        changingAccount = true
        defer { changingAccount = false }
        generation += 1
        clearSnapshot(); link.send(nil)
        await push.setEnabled(false)
        do {
            signedInEmail = try await client.handleCallback(url).email; signedIn = true; pendingEmail = nil; message = nil
            changingAccount = false
            await refresh()
        } catch {
            signedIn = await client.session != nil; signedInEmail = await client.session?.email
            message = "This sign-in link could not be completed. Request a fresh link on this iPhone."
        }
    }
    func refresh() async {
        now = clock()
        guard !busy, !changingAccount, await client.session != nil else { return }
        busy = true; defer { busy = false }
        let current = generation
        do {
            let value = try await client.mobileRelay()
            let account = await client.session?.userID
            guard current == generation, let account else { return }
            envelope = value; message = value == nil ? "Enable mobile sharing in Clepso on your Mac." : nil
            if let value,
               let data = try? UsageSnapshot.encoder().encode(CompanionCache(accountID: account, envelope: value)) {
                try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: cache, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } else { try? FileManager.default.removeItem(at: cache) }
            link.send(value)
            await reconcileReminders()
        } catch SyncError.notSignedIn {
            guard current == generation else { return }
            signedIn = false; signedInEmail = nil; clearSnapshot(); link.send(nil)
            push.clearLocally()
            await reconcileReminders()
            message = "Your session ended. Sign in again on this iPhone."
        } catch {
            guard current == generation else { return }
            message = "Could not refresh. The previous reading may be old."
        }
    }
    func signOut() async {
        guard !push.busy, !changingAccount else { message = "Wait for the background refresh change to finish, then sign out."; return }
        changingAccount = true
        defer { changingAccount = false }
        generation += 1
        signedIn = false; signedInEmail = nil; pendingEmail = nil
        clearSnapshot(); link.send(nil)
        await reconcileReminders()
        await push.setEnabled(false)
        await client.signOut()
    }
    func clearSnapshot() { envelope = nil; try? FileManager.default.removeItem(at: cache) }
    func setReminders(_ enabled: Bool) async {
        reminderChoice += 1
        let choice = reminderChoice
        if enabled {
            do {
                guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound,.badge]) else {
                    message = "Notifications are not allowed. You can enable them in iPhone Settings."; return
                }
            } catch { message = "Notification permission could not be requested."; return }
        }
        guard choice == reminderChoice else { return }
        reminders = enabled
        UserDefaults.standard.set(enabled, forKey: "companion.reminders")
        await reconcileReminders()
    }
    func setLead(_ value: Int) async {
        guard [0,5,15].contains(value) else { return }
        leadMinutes = value; UserDefaults.standard.set(value, forKey: "companion.lead")
        await reconcileReminders()
    }
    func reconcileReminders() async {
        let plan = CompanionReminderPlan.make(envelope, enabled: reminders, leadMinutes: leadMinutes, now: clock())
        do { try await reminderCoordinator.replace(plan) }
        catch { message = "Reset reminders could not be updated. Check notification permissions and refresh to retry." }
    }
}
