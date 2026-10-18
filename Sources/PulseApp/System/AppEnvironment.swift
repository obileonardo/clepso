#if canImport(AppKit)
import AppKit
#endif
import Domain
import Foundation
import Sync
#if canImport(ServiceManagement)
import ServiceManagement
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(Security)
import Security
#endif

/// Everything the app touches outside its own memory, injected so tests run against a temporary
/// home and fakes, and so no system prompt or login-item change happens without an explicit user action.
public struct AppEnvironment: Sendable {
    public var dataDirectory: URL                // ~/Library/Application Support/Pulse
    public var home: URL                          // where ~/.claude lives
    public var shimPath: String                   // Pulse.app/Contents/Helpers/pulse-statusline
    public var clock: any WallClock
    public var loginItem: any LoginItemControlling
    public var notifications: any NotificationAuthorizing
    public var keychain: any KeychainCleaning
    public var appVersion: String
    /// Auto-updating by default: `TimeZone.current` and `Locale.current` are snapshots, so after the Mac changes zone
    /// (or its 12/24-hour setting) every reset time would keep the old one until a relaunch (TEST_PLAN §5, F16).
    public var timeZone: TimeZone
    public var locale: Locale
    public var tickInterval: Duration
    /// 2.5 Calendar actions. Off: UX_SPEC hides them in Stage A. Debug builds turn them on with `-PulseCalendarActions YES`.
    public var calendarActions = false
    /// Where Add to Calendar writes its `.ics` file (temporary: Calendar copies the event when the user adds it).
    public var calendarDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("\(Product.name) Calendar")
    /// Opens a file in its default app (Calendar, for `.ics`). Tests record the call instead.
    public var openFile: @MainActor @Sendable (URL) -> Void = { url in
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
    /// The Mac account's full name, for Home's default greeting (the user can change the name in Account).
    public var fullUserName: String
    /// Pulse accounts. Off (no project, no requests) unless the build carries a `SyncConfig`; tests and previews get
    /// an unconfigured client unless they pass their own.
    public var sync: SyncClient

    public init(dataDirectory: URL, home: URL, shimPath: String, clock: any WallClock = SystemClock(),
                loginItem: any LoginItemControlling, notifications: any NotificationAuthorizing,
                keychain: any KeychainCleaning = SystemKeychain(), appVersion: String = "dev",
                timeZone: TimeZone = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent, tickInterval: Duration = .seconds(30),
                fullUserName: String = NSFullUserName(), sync: SyncClient? = nil) {
        self.dataDirectory = dataDirectory
        self.home = home
        self.shimPath = shimPath
        self.clock = clock
        self.loginItem = loginItem
        self.notifications = notifications
        self.keychain = keychain
        self.appVersion = appVersion
        self.timeZone = timeZone
        self.locale = locale
        self.tickInterval = tickInterval
        self.fullUserName = fullUserName
        self.sync = sync ?? SyncClient(config: nil, transport: OfflineTransport(), store: MemoryAuthStore(), now: { [clock] in clock.now() })
    }

    public var databaseURL: URL { dataDirectory.appendingPathComponent("pulse.sqlite") }
    public var diagnosticsURL: URL { dataDirectory.appendingPathComponent("diagnostics.jsonl") }
    /// ARCHITECTURE §3: the helper connects here.
    public var socketPath: String { dataDirectory.appendingPathComponent("run/agent.sock").path }

    /// The real app. Debug builds accept `-PulseDataDirectory <path>` and `-PulseHome <path>` so a
    /// verification run never touches the real Application Support folder or ~/.claude.
    public static func live(bundle: Bundle = .main) -> AppEnvironment {
        var data = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Pulse")
        var home = FileManager.default.homeDirectoryForCurrentUser
        #if DEBUG
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "PulseDataDirectory") { data = URL(fileURLWithPath: path) }
        if let path = defaults.string(forKey: "PulseHome") { home = URL(fileURLWithPath: path) }
        #endif
        // The real account lives in the Keychain; a debug run on another data folder (the probe, demo screenshots) gets a
        // private in-memory one, so it can never upload to, or sign out of, the user's real account.
        var authStore: any AuthStore = KeychainAuthStore()
        #if DEBUG
        if UserDefaults.standard.string(forKey: "PulseDataDirectory") != nil { authStore = MemoryAuthStore() }
        #endif
        let shim = bundle.bundleURL.appendingPathComponent("Contents/Helpers/pulse-statusline").path
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        var environment = AppEnvironment(dataDirectory: data, home: home, shimPath: shim,
                                          loginItem: SystemLoginItem(), notifications: SystemNotifications(),
                                          keychain: SystemKeychain(service: bundle.bundleIdentifier ?? "dev.tokone.pulse"), appVersion: version,
                                          sync: SyncClient(config: SyncConfig(infoDictionary: bundle.infoDictionary ?? [:]), store: authStore,
                                                           now: { SystemClock().now() }))
        #if DEBUG
        environment.calendarActions = UserDefaults.standard.bool(forKey: "PulseCalendarActions")
        #endif
        return environment
    }
}

// MARK: - Login item (ARCHITECTURE §1, SMAppService only, after in-app consent)

public protocol LoginItemControlling: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

public struct SystemLoginItem: LoginItemControlling {
    public init() {}
    public var isEnabled: Bool {
        #if canImport(ServiceManagement)
        SMAppService.mainApp.status == .enabled
        #else
        false
        #endif
    }
    public func setEnabled(_ enabled: Bool) throws {
        #if canImport(ServiceManagement)
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        #endif
    }
}

// MARK: - Notification permission (asked only after a real observation)

public enum NotificationAuthorization: String, Sendable { case notDetermined, denied, authorized }

public protocol NotificationAuthorizing: Sendable {
    func status() async -> NotificationAuthorization
    func request() async -> NotificationAuthorization
    func sendTest(title: String, body: String) async
    /// Delete-all step 2: nothing scheduled or shown survives.
    func removeAll() async
    /// 2.1: shows one limit alert now.
    func deliver(_ alert: AlertNotification) async
    /// 2.1: what to do when the user picks an alert's action ("Snooze 1 h") or clicks it.
    func onAction(_ handler: @escaping @Sendable (AlertAction) -> Void)
}

extension NotificationAuthorizing {
    public func deliver(_ alert: AlertNotification) async {}
    public func onAction(_ handler: @escaping @Sendable (AlertAction) -> Void) {}
}

/// One limit alert as the notification center shows it (NOTIFICATIONS_AND_SCHEDULING §1.9).
public struct AlertNotification: Sendable, Equatable {
    public let identifier: String          // the dedup key: one crossing is one notification
    public let title: String
    public let body: String
    public let threadID: String            // one thread per pool
    public let relevance: Double
    public let snoozable: Bool             // approaching and limit-reached alerts carry "Snooze 1 h"
}

public enum AlertAction: Sendable, Equatable { case open, snoozeOneHour }

public struct SystemNotifications: NotificationAuthorizing {
    public init() {}
    public func status() async -> NotificationAuthorization {
        #if canImport(UserNotifications)
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional: return .authorized
        case .denied: return .denied
        default: return .notDetermined
        }
        #else
        return .denied
        #endif
    }
    public func request() async -> NotificationAuthorization {
        #if canImport(UserNotifications)
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        #endif
        return await status()
    }
    public func sendTest(title: String, body: String) async {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pulse.test", content: content, trigger: nil))
        #endif
    }
    public func removeAll() async {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        #endif
    }

    #if canImport(UserNotifications)
    static let limitCategory = "LIMIT_ALERT", infoCategory = "LIMIT_INFO", snoozeAction = "SNOOZE_1H"
    #endif

    public func deliver(_ alert: AlertNotification) async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 1 h", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.limitCategory, actions: [snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.infoCategory, actions: [], intentIdentifiers: []),
        ])
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.threadIdentifier = alert.threadID
        content.categoryIdentifier = alert.snoozable ? Self.limitCategory : Self.infoCategory
        content.relevanceScore = alert.relevance
        content.interruptionLevel = .active
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil))
        #endif
    }

    public func onAction(_ handler: @escaping @Sendable (AlertAction) -> Void) {
        #if canImport(UserNotifications)
        let delegate = AlertDelegate(handler: handler)
        AlertDelegate.current = delegate                     // the center holds its delegate weakly
        UNUserNotificationCenter.current().delegate = delegate
        #endif
    }
}

#if canImport(UserNotifications)
/// Shows alerts while the app is frontmost too, and turns the user's choice into an `AlertAction`.
final class AlertDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    nonisolated(unsafe) static var current: AlertDelegate?
    let handler: @Sendable (AlertAction) -> Void
    init(handler: @escaping @Sendable (AlertAction) -> Void) { self.handler = handler }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .list, .sound] }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        switch response.actionIdentifier {
        case SystemNotifications.snoozeAction: handler(.snoozeOneHour)
        case UNNotificationDefaultActionIdentifier: handler(.open)
        default: break
        }
    }
}
#endif

// MARK: - Keychain (delete-all step 4)

/// Removes every Keychain item Pulse owns. Stage A stores none yet: the session key lives in the 0600 file the
/// helper reads, because the data-protection Keychain (PRIVACY_AND_SECURITY §4) needs the provisioning profile
/// that arrives with Developer ID signing. The sweep runs anyway so a later build's items go too.
public protocol KeychainCleaning: Sendable {
    func deleteAll()
}

public struct SystemKeychain: KeychainCleaning {
    public let service: String
    public init(service: String = "dev.tokone.pulse") { self.service = service }
    public func deleteAll() {
        #if canImport(Security)
        _ = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        #endif
    }
}
