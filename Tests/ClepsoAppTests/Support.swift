import Darwin
import Domain
import Foundation
import ShimProtocol
@testable import ClepsoApp

let t0 = Date(timeIntervalSince1970: 1_792_159_200)            // 16 Oct 2026 14:00 UTC
let utc = TimeZone(identifier: "UTC")!
let enUS = Locale(identifier: "en_US")

/// A clock tests move by hand.
final class TestClock: WallClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = t0) { current = start }
    func now() -> Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

/// Records every login-item call, so tests can prove nothing registers without consent.
final class FakeLoginItem: LoginItemControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool
    private(set) var calls: [Bool] = []
    /// `reportsEnabled` simulates the system claiming a login item that was never registered.
    init(reportsEnabled: Bool = false) { enabled = reportsEnabled }
    var isEnabled: Bool { lock.withLock { enabled } }
    func setEnabled(_ value: Bool) throws { lock.withLock { calls.append(value); enabled = value } }
}

final class FakeNotifications: NotificationAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0
    var requestCount: Int { lock.withLock { requests } }
    func status() async -> NotificationAuthorization { lock.withLock { requests > 0 ? .authorized : .notDetermined } }
    func request() async -> NotificationAuthorization { lock.withLock { requests += 1 }; return .authorized }
    func sendTest(title: String, body: String) async {}
    private var removals = 0
    var removeAllCount: Int { lock.withLock { removals } }
    func removeAll() async { lock.withLock { removals += 1; held = [:] } }
    private var shown: [AlertNotification] = []
    var delivered: [AlertNotification] { lock.withLock { shown } }
    func deliver(_ alert: AlertNotification) async { lock.withLock { shown.append(alert) } }

    // 2.3: the notification center's pending requests, as the OS keeps them (same identifier replaces).
    private var held: [String: ScheduledAlert] = [:]
    private var scheduleLog: [ScheduledAlert] = []
    private var removalLog: [String] = []
    /// What is pending now, soonest first.
    var pending: [ScheduledAlert] { lock.withLock { held.values.sorted { ($0.fireAt, $0.notification.identifier) < ($1.fireAt, $1.notification.identifier) } } }
    /// Every `schedule` call, in order.
    var scheduled: [ScheduledAlert] { lock.withLock { scheduleLog } }
    /// Every identifier removed from the pending list, in order.
    var removedPending: [String] { lock.withLock { removalLog } }
    func schedule(_ alert: ScheduledAlert) async { lock.withLock { held[alert.notification.identifier] = alert; scheduleLog.append(alert) } }
    func pendingReminders() async -> [ScheduledAlert] { pending }
    func removePending(_ identifiers: [String]) async {
        lock.withLock { for id in identifiers { held[id] = nil }; removalLog += identifiers }
    }
    /// The OS firing what came due while the Mac was awake: each due request becomes a shown notification.
    func fireDue(at now: Date) {
        lock.withLock {
            for alert in held.values.sorted(by: { $0.fireAt < $1.fireAt }) where alert.fireAt <= now {
                held[alert.notification.identifier] = nil
                shown.append(alert.notification)
            }
        }
    }
}

final class FakeKeychain: KeychainCleaning, @unchecked Sendable {
    private let lock = NSLock()
    private var sweeps = 0
    var sweepCount: Int { lock.withLock { sweeps } }
    func deleteAll() { lock.withLock { sweeps += 1 } }
}

/// A short temporary folder: Unix socket paths are limited to 104 bytes.
struct Sandbox {
    let root: URL
    init() {
        root = URL(fileURLWithPath: "/tmp").appendingPathComponent("pa-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("home/.claude"), withIntermediateDirectories: true)
    }
    var home: URL { root.appendingPathComponent("home") }
    var settings: URL { home.appendingPathComponent(".claude/settings.json") }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    @MainActor
    func model(clock: TestClock, login: FakeLoginItem = FakeLoginItem(), notifications: FakeNotifications = FakeNotifications(),
               keychain: FakeKeychain = FakeKeychain(), shimPath: String = "/Applications/Clepso.app/Contents/Helpers/clepso-statusline") -> AppModel {
        AppModel(environment: AppEnvironment(dataDirectory: data, home: home, shimPath: shimPath,
                                             clock: clock, loginItem: login, notifications: notifications, keychain: keychain,
                                             appVersion: "0.1.0-test", timeZone: utc, locale: enUS, tickInterval: .seconds(3600)))
    }

    var data: URL { root.appendingPathComponent("data") }

    /// Every file under `url`, relative paths, sorted: the before/after evidence for delete-all.
    static func inventory(_ url: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(atPath: url.path) else { return [] }
        return walker.compactMap { $0 as? String }.sorted()
    }
}

/// A frame as the helper sends it (PRIVACY_AND_SECURITY §4), stamped at `at`.
func frameBytes(at: Date, fiveHour: Double = 14, sevenDay: Double = 23.5, session: String = "0123456789abcdef",
                unreadWindows: Int = 0) throws -> Data {
    let ms = Int64(at.timeIntervalSince1970 * 1000)
    let json = """
    {"v":1,"kind":"claude_code.statusline","emitted_at_ms":\(ms),"shim_version":"0.1.0","source_version":"2.1.302",
     "session_ref":"\(session)","model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},
     "context":{"window_size":1000000,"used_pct":73,"total_input_tokens":729769},
     "rate_limits":{"five_hour":{"used_pct":\(fiveHour),"resets_at":\(Int64(at.timeIntervalSince1970) + 9000)},
                    "seven_day":{"used_pct":\(sevenDay),"resets_at":\(Int64(at.timeIntervalSince1970) + 400_000)}},
     "health":{"unknown_rate_limit_windows":\(unreadWindows)}}
    """
    return try FrameCodec.encode(try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
}

/// Writes bytes to a Unix socket the way the helper does.
func send(_ path: String, _ bytes: Data) -> Bool {
    var address = sockaddr_un()
    let p = Array(path.utf8)
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: p); raw[p.count] = 0 }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(fd) }
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    let ok = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard ok == 0 else { return false }
    return bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } == bytes.count
}

/// Polls a main-actor condition (the model updates asynchronously after a frame arrives).
@MainActor
func eventually(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
