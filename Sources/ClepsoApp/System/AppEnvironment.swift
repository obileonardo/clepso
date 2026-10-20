#if canImport(AppKit)
import AppKit
#endif
import Domain
import Foundation
import Sync
import enum UsageEngine.ReminderPlanner
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
    public var dataDirectory: URL                // ~/Library/Application Support/Clepso
    /// The data folder from before the rename to Clepso (`~/Library/Application Support/Pulse`), moved into
    /// `dataDirectory` at launch. nil: nothing to move (tests, and debug runs on an explicit `-ClepsoDataDirectory`).
    public var legacyDataDirectory: URL?
    public var home: URL                          // where ~/.claude lives
    public var shimPath: String                   // Clepso.app/Contents/Helpers/clepso-statusline
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
    /// 2.5 Calendar actions. Off: UX_SPEC hides them in Stage A. Debug builds turn them on with `-ClepsoCalendarActions YES`.
    public var calendarActions = false
    /// Where Add to Calendar writes its `.ics` file (temporary: Calendar copies the event when the user adds it).
    public var calendarDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("\(Product.name) Calendar")
    /// Opens a file in its default app (Calendar, for `.ics`). Tests record the call instead.
    public var openFile: @MainActor @Sendable (URL) -> Void = { url in
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
    /// Opens a web page in the user's browser (the What's new card's changelog link). Tests record the call instead.
    public var openLink: @MainActor @Sendable (URL) -> Void = { url in
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
    /// The Mac account's full name, for Home's default greeting (the user can change the name in Account).
    public var fullUserName: String
    /// Clepso accounts. Off (no project, no requests) unless the build carries a `SyncConfig`; tests and previews get
    /// an unconfigured client unless they pass their own.
    public var sync: SyncClient
    /// A debug run on another home or data folder (`-ClepsoHome`, `-ClepsoDataDirectory`, `-ClepsoProbeOutput`). macOS
    /// sees it as the installed Clepso (same bundle identifier), so everything macOS keeps per app gets a stand-in
    /// (`live(bundle:flag:)`): no login item, no notification centre, no Keychain, sign-in kept in memory, no sign-in link
    /// taken unless this run started that sign-in, no window size or open window saved.
    public var isolated = false
    /// Whether Clepso may rewrite its own files in `home/.claude` without a click: re-pointing the status line and hooks
    /// at launch after a move, regenerating the helper's config after a setting changes. Off for an isolated run that
    /// reads the real home (`-ClepsoDataDirectory` alone): its helper and socket are not the installed app's, so a
    /// repair would point the user's status line and hooks at this run.
    public var rewritesHome = true
    /// What this build shows (`ReleaseFeatures`): everything unless `live()` says otherwise, so tests see every section.
    public var features = ReleaseFeatures.all
    /// Clepso's Claude Code mod as bundled (`Contents/Resources/claude-code`); nil: beside `shimPath` in the app bundle.
    /// Tests point it at the repository's `mod/claude-code`.
    public var claudeModDirectory: URL?

    public init(dataDirectory: URL, home: URL, shimPath: String, clock: any WallClock = SystemClock(),
                loginItem: any LoginItemControlling, notifications: any NotificationAuthorizing,
                keychain: any KeychainCleaning = SystemKeychain(), appVersion: String = "dev",
                timeZone: TimeZone = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent, tickInterval: Duration = .seconds(30),
                fullUserName: String = NSFullUserName(), sync: SyncClient? = nil, legacyDataDirectory: URL? = nil) {
        self.dataDirectory = dataDirectory
        self.legacyDataDirectory = legacyDataDirectory
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

    public var databaseURL: URL { dataDirectory.appendingPathComponent(LegacyDataMigration.databaseName) }
    public var diagnosticsURL: URL { dataDirectory.appendingPathComponent("diagnostics.jsonl") }
    /// ARCHITECTURE §3: the helper connects here.
    public var socketPath: String { dataDirectory.appendingPathComponent("run/agent.sock").path }

    /// The real app. Debug builds accept `-ClepsoDataDirectory <path>` and `-ClepsoHome <path>` so a
    /// verification run never touches the real Application Support folder or ~/.claude. `-ClepsoHome` alone stands in
    /// for the whole home folder: the data folder is then `<home>/Library/Application Support/Clepso`, and an old
    /// `<home>/Library/Application Support/Pulse` there is migrated like the real one.
    public static func live(bundle: Bundle = .main) -> AppEnvironment {
        #if DEBUG
        if let problem = launchProblem(flag: debugFlag) {
            FileHandle.standardError.write(Data((problem + "\n").utf8))
            exit(64)
        }
        #endif
        return live(bundle: bundle, flag: debugFlag)
    }

    /// `live()` with the launch arguments read through `flag` (tests pass their own).
    static func live(bundle: Bundle, flag: (String) -> String?) -> AppEnvironment {
        #if DEBUG
        let homeFlag = flag("ClepsoHome"), dataFlag = flag("ClepsoDataDirectory")
        #else
        let homeFlag: String? = nil, dataFlag: String? = nil   // release builds take no debug launch arguments
        #endif
        let isolated = isIsolated(flag: flag)
        let home = homeFlag.map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
        let data = dataFlag.map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent("Library/Application Support/Clepso")
        let legacyData = dataFlag == nil ? home.appendingPathComponent("Library/Application Support/Pulse") : nil
        // The real account lives in the Keychain; a debug run on another home or data folder (the probe, demo screenshots)
        // gets a private in-memory one, so it can never upload to, or sign out of, the user's real account.
        let authStore: any AuthStore = isolated ? MemoryAuthStore() : KeychainAuthStore()
        let shim = bundle.bundleURL.appendingPathComponent("Contents/Helpers/clepso-statusline").path
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        var environment = AppEnvironment(dataDirectory: data, home: home, shimPath: shim,
                                          loginItem: isolated ? IsolatedLoginItem() : SystemLoginItem(),
                                          notifications: isolated ? IsolatedNotifications() : SystemNotifications(),
                                          keychain: isolated ? IsolatedKeychain() as any KeychainCleaning
                                                             : SystemKeychain(service: bundle.bundleIdentifier ?? "com.elvisobi.clepso"),
                                          appVersion: version,
                                          sync: SyncClient(config: SyncConfig(infoDictionary: bundle.infoDictionary ?? [:]), store: authStore,
                                                           now: { SystemClock().now() }),
                                          legacyDataDirectory: legacyData)
        environment.isolated = isolated
        environment.rewritesHome = !isolated || homeFlag != nil
        environment.features = ReleaseFeatures.current(debugFlag: flag)
        #if DEBUG
        environment.calendarActions = UserDefaults.standard.bool(forKey: "ClepsoCalendarActions")
        #endif
        return environment
    }

    /// Any of the three debug flags that move Clepso off the installed app's files (`isolated`).
    /// Release builds compile none of the flag names, so the shipped binary carries no debug launch argument
    /// (`scripts/release.sh` checks its strings).
    static func isIsolated(flag: (String) -> String?) -> Bool {
        #if DEBUG
        ["ClepsoHome", "ClepsoDataDirectory", "ClepsoProbeOutput"].contains { flag($0) != nil }
        #else
        false
        #endif
    }

    /// This process, from its launch arguments; always false in release builds. For AppKit code without the model.
    static let isIsolatedRun = isIsolated(flag: debugFlag)

    /// Why a debug launch must stop before it touches anything, or nil. A probe on the real data folder would bind the
    /// installed app's socket, write its preferences (demo, theme, profile name) and repair its status line.
    static func launchProblem(flag: (String) -> String?) -> String? {
        #if DEBUG
        guard flag("ClepsoProbeOutput") != nil, flag("ClepsoHome") == nil, flag("ClepsoDataDirectory") == nil else { return nil }
        return "-ClepsoProbeOutput needs -ClepsoHome or -ClepsoDataDirectory: a probe must never run on the installed app's data."
        #else
        nil
        #endif
    }

    /// A `-Clepso…` launch argument; always nil in release builds.
    static func debugFlag(_ key: String) -> String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: key)
        #else
        nil
        #endif
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

/// An isolated run's login item (`AppEnvironment.isolated`): the switch works on screen, and macOS never hears of it
/// (`SMAppService.mainApp` is the installed app's login item: same bundle identifier).
public final class IsolatedLoginItem: LoginItemControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    public init() {}
    public var isEnabled: Bool { lock.withLock { enabled } }
    public func setEnabled(_ enabled: Bool) throws { lock.withLock { self.enabled = enabled } }
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
    /// 2.3: adds a request that fires at `alert.fireAt`; a pending request with the same identifier is replaced.
    func schedule(_ alert: ScheduledAlert) async throws
    /// 2.3: the reset reminders the notification center still holds (`ReminderPlanner.isReminder` identifiers).
    func pendingReminders() async -> [ScheduledAlert]
    func removePending(_ identifiers: [String]) async
    func deliveredSchedules() async -> [DeliveredSchedule]
}

extension NotificationAuthorizing {
    public func deliver(_ alert: AlertNotification) async {}
    public func onAction(_ handler: @escaping @Sendable (AlertAction) -> Void) {}
    public func schedule(_ alert: ScheduledAlert) async throws {}
    public func pendingReminders() async -> [ScheduledAlert] { [] }
    public func removePending(_ identifiers: [String]) async {}
    public func deliveredSchedules() async -> [DeliveredSchedule] { [] }
}

/// One limit alert as the notification center shows it (NOTIFICATIONS_AND_SCHEDULING §1.9).
public struct AlertNotification: Sendable, Equatable {
    public let identifier: String          // the dedup key: one crossing is one notification
    public let title: String
    public let body: String
    public let threadID: String            // one thread per pool
    public let relevance: Double
    public let snoozable: Bool             // approaching and limit-reached alerts carry "Snooze 1 h"
    /// §1.6: during quiet hours, `.passive` and no sound.
    public var passive = false
}

/// A notification the center holds until `fireAt` (a reset reminder, §2).
public struct ScheduledAlert: Sendable, Equatable {
    public let notification: AlertNotification
    public let fireAt: Date
}

public struct DeliveredSchedule: Sendable, Equatable {
    public let identifier: String
    public let deliveredAt: Date
    public init(identifier: String, deliveredAt: Date) { self.identifier = identifier; self.deliveredAt = deliveredAt }
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
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "clepso.test", content: content, trigger: nil))
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
        content.interruptionLevel = alert.passive ? .passive : .active
        content.sound = alert.passive ? nil : .default
        try? await center.add(UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil))
        #endif
    }

    /// §2: the trigger is the absolute instant written as UTC calendar components, so a zone or daylight-saving change
    /// on the Mac cannot move it (F16, F17).
    public static func triggerComponents(for instant: Date) -> DateComponents {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var components = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
        components.calendar = utc
        components.timeZone = utc.timeZone
        return components
    }

    static let fireAtKey = "fireAt"

    public func schedule(_ alert: ScheduledAlert) async throws {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        let note = alert.notification
        content.title = note.title
        content.body = note.body
        content.threadIdentifier = note.threadID
        content.categoryIdentifier = Self.infoCategory
        content.relevanceScore = note.relevance
        content.interruptionLevel = note.passive ? .passive : .active
        content.sound = note.passive ? nil : .default
        content.userInfo = [Self.fireAtKey: alert.fireAt.timeIntervalSince1970]
        let trigger = UNCalendarNotificationTrigger(dateMatching: Self.triggerComponents(for: alert.fireAt), repeats: false)
        try await center.add(UNNotificationRequest(identifier: note.identifier, content: content, trigger: trigger))
        #endif
    }

    public func pendingReminders() async -> [ScheduledAlert] {
        #if canImport(UserNotifications)
        return await UNUserNotificationCenter.current().pendingNotificationRequests().compactMap { request in
            guard ReminderPlanner.isScheduled(request.identifier),
                  let seconds = request.content.userInfo[Self.fireAtKey] as? Double else { return nil }
            let c = request.content
            return ScheduledAlert(notification: AlertNotification(identifier: request.identifier, title: c.title, body: c.body,
                                                                  threadID: c.threadIdentifier, relevance: c.relevanceScore,
                                                                  snoozable: false, passive: c.interruptionLevel == .passive),
                                  fireAt: Date(timeIntervalSince1970: seconds))
        }
        #else
        return []
        #endif
    }

    public func removePending(_ identifiers: [String]) async {
        #if canImport(UserNotifications)
        guard !identifiers.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        #endif
    }

    public func deliveredSchedules() async -> [DeliveredSchedule] {
        #if canImport(UserNotifications)
        return await UNUserNotificationCenter.current().deliveredNotifications().compactMap { note in
            guard ReminderPlanner.isScheduled(note.request.identifier) else { return nil }
            return DeliveredSchedule(identifier: note.request.identifier, deliveredAt: note.date)
        }
        #else
        return []
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

/// An isolated run's notifications (`AppEnvironment.isolated`). The notification centre is the installed app's (same
/// bundle identifier): a probe's reminder reconciliation would cancel its pending reset reminders, and its alerts would
/// appear as the real app's. Permission reads as given, so Settings looks as it does for most users; nothing is shown,
/// scheduled, removed or listened to (the protocol's defaults are no-ops).
public struct IsolatedNotifications: NotificationAuthorizing {
    public init() {}
    public func status() async -> NotificationAuthorization { .authorized }
    public func request() async -> NotificationAuthorization { .authorized }
    public func sendTest(title: String, body: String) async {}
    public func removeAll() async {}
}

#if canImport(UserNotifications)
/// Shows alerts while the app is frontmost too, and turns the user's choice into an `AlertAction`.
final class AlertDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    nonisolated(unsafe) static var current: AlertDelegate?
    let handler: @Sendable (AlertAction) -> Void
    init(handler: @escaping @Sendable (AlertAction) -> Void) { self.handler = handler }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        notification.request.content.interruptionLevel == .passive ? [.list] : [.banner, .list, .sound]   // §1.6 quiet hours
    }

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

/// Removes every Keychain item Clepso owns. Stage A stores none yet: the session key lives in the 0600 file the
/// helper reads, because the data-protection Keychain (PRIVACY_AND_SECURITY §4) needs the provisioning profile
/// that arrives with Developer ID signing. The sweep runs anyway so a later build's items go too.
public protocol KeychainCleaning: Sendable {
    func deleteAll()
}

public struct SystemKeychain: KeychainCleaning {
    public let service: String
    public init(service: String = "com.elvisobi.clepso") { self.service = service }
    public func deleteAll() {
        #if canImport(Security)
        _ = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        #endif
    }
}

/// An isolated run's Keychain (`AppEnvironment.isolated`): Delete everything leaves the installed app's items alone.
public struct IsolatedKeychain: KeychainCleaning {
    public init() {}
    public func deleteAll() {}
}
