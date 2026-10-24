import CryptoKit
import Foundation
import Observation
import Sync
import UIKit

@MainActor @Observable final class PhonePushController {
    private struct Choice: Codable {
        var enabled = false
        var accountDigest: String?
        var lease: UUID?
        var pendingRemoval = false
    }
    private var choice: Choice
    private let client: SyncClient
    private let device: UUID
    private let environment: SyncClient.PushEnvironment
    private let defaults: UserDefaults
    private let registerWithApple: () -> Void
    private let unregisterFromApple: () -> Void
    private var revision = 0
    var busy = false
    var message: String?
    var refresh: (@MainActor @Sendable () async -> Bool)?
    var enabled: Bool { choice.enabled }
    init(client: SyncClient, defaults: UserDefaults = .standard,
         register: @escaping () -> Void = { UIApplication.shared.registerForRemoteNotifications() },
         unregister: @escaping () -> Void = { UIApplication.shared.unregisterForRemoteNotifications() }) {
        self.client = client
        self.defaults = defaults
        registerWithApple = register; unregisterFromApple = unregister
        device = defaults.string(forKey: "companion.push.device").flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(device.uuidString, forKey: "companion.push.device")
        choice = defaults.data(forKey: "companion.push.choice").flatMap { try? JSONDecoder().decode(Choice.self, from: $0) } ?? Choice()
        environment = SyncClient.PushEnvironment(rawValue: Bundle.main.object(forInfoDictionaryKey: "ClepsoPushEnvironment") as? String ?? "") ?? .development
    }
    private func digest(_ id: String) -> String { SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func save() { defaults.set(try? JSONEncoder().encode(choice), forKey: "companion.push.choice") }
    func start() async {
        guard let account = await client.session?.userID else { return }
        guard choice.accountDigest == digest(account) else {
            if choice.enabled { choice.enabled = false; choice.lease = nil; save() }
            return
        }
        if choice.pendingRemoval { await setEnabled(false); return }
        guard choice.enabled, choice.lease != nil, !busy else { return }
        // A cached On choice never creates a new server lease on launch. A remote opt-out must remain revoked.
        busy = true
        let current = revision
        defer { busy = false }
        do {
            try await client.checkMobilePush(environment)
            guard current == revision, choice.enabled else { return }
            registerWithApple()
            message = "Registering this iPhone for background refresh…"
        } catch { message = "Background refresh is unavailable. Check your connection and retry." }
    }
    func setEnabled(_ enabled: Bool) async {
        guard !busy else { return }
        busy = true; revision += 1
        let current = revision
        defer { busy = false }
        if !enabled {
            choice.enabled = false; choice.pendingRemoval = choice.accountDigest != nil
            choice.lease = nil; save() // No future callback can register locally after this point.
            unregisterFromApple()
            if choice.accountDigest == nil { message = "Background refresh is off."; return }
        }
        guard let account = await client.session?.userID, enabled || choice.accountDigest == digest(account) else {
            message = enabled ? "Sign in before enabling background refresh." : "Background refresh is off. Server token removal is pending until you reconnect to the same account; tokens expire after 30 days."
            return
        }
        do {
            if enabled { try await client.checkMobilePush(environment) }
            let lease = try await client.setMobileDevice(device, enabled: enabled)
            guard current == revision, await client.session?.userID == account else { return }
            choice = Choice(enabled: enabled, accountDigest: digest(account), lease: enabled ? lease : nil)
            save()
            if enabled {
                registerWithApple()
                message = "Registering this iPhone for background refresh…"
            } else { message = "Background refresh is off and its server token was removed." }
        } catch {
            message = enabled ? "Background refresh is unavailable. Check your connection and try again later." :
                "Background refresh is off. Server token removal is pending; tokens expire after 30 days."
        }
    }
    func register(_ data: Data) async {
        let current = revision
        guard choice.enabled, let lease = choice.lease, let account = await client.session?.userID,
              current == revision, choice.enabled, choice.lease == lease, choice.accountDigest == digest(account) else { return }
        let token = data.map { String(format: "%02x", $0) }.joined()
        do {
            try await client.registerMobileDevice(device, generation: lease, token: token, environment: environment)
            guard current == revision, choice.enabled else { return }
            message = "Registered for background refresh. Apple decides when background updates are delivered."
        } catch {
            guard current == revision else { return }
            if case SyncError.http(status: 403, code: _) = error {
                choice.enabled = false; choice.lease = nil; choice.pendingRemoval = false; save()
                message = "Background refresh permission ended. Enable it again to give fresh consent."
            } else { message = "Background refresh could not register. Turn it off and on to retry." }
        }
    }
    func failedRegistration() {
        guard choice.enabled else { return }
        message = "Apple could not register background refresh. Check your connection and retry."
    }
    func clearLocally() {
        revision += 1
        choice.enabled = false; choice.lease = nil; choice.pendingRemoval = choice.accountDigest != nil
        save()
        unregisterFromApple()
    }
    func receive() async -> Bool {
        let current = revision
        guard choice.enabled, let account = await client.session?.userID, choice.accountDigest == digest(account),
              current == revision, choice.enabled, let refresh else { return false }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await refresh() }
            group.addTask { try? await Task.sleep(for: .seconds(20)); return false }
            let changed = await group.next() ?? false
            group.cancelAll()
            return changed
        }
    }
}

@MainActor final class PhonePushDelegate: NSObject, UIApplicationDelegate {
    weak var controller: PhonePushController?
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await controller?.register(deviceToken) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        controller?.failedRegistration()
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let signal = (userInfo["aps"] as? [String: Any])?["content-available"] as? Int == 1
        guard signal else { completionHandler(.noData); return }
        Task { completionHandler(await controller?.receive() == true ? .newData : .noData) }
    }
}
