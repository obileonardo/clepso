import enum Domain.Product
import protocol Domain.WallClock
import Foundation
import Observation
import OSLog
import ShimProtocol

/// Something worth recording for the Diagnostics drawer (PRIVACY_AND_SECURITY §5). Cases carry numbers, enum
/// names and fingerprints only: there is no case that takes free text, so a path, prompt or payload cannot be logged.
public enum DiagnosticEvent: Sendable, Equatable {
    case appStarted(version: String)
    case listening
    case socketFailed(errno: Int32?)
    case ingestRejected(otherUser: Int, malformed: Int, oversize: Int, rateLimited: Int, unmappable: Int)
    case clockSkew(frames: Int)
    case unreadLimitWindows(count: Int)
    case storageFailed(sqliteCode: Int32?)
    case installed(keptExisting: Bool, backupFingerprint: String?)
    case installRefused(reason: String)               // an `InstallError` case name
    case removed(outcome: String)                     // an `UninstallOutcome` / `RemoveOutcome` case name
    case planChanged(catalogID: String?, confirmed: Bool)
    case demo(on: Bool)
    case loginItem(on: Bool)
    case notifications(status: String)
    case exported(rows: Int, scrubbed: Int)
    case purged(readings: Int, sessions: Int)

    var level: DiagnosticsLog.Entry.Level {
        switch self {
        case .socketFailed, .storageFailed, .installRefused: .error
        case .ingestRejected, .clockSkew, .unreadLimitWindows: .warning
        default: .info
        }
    }

    var code: String {
        switch self {
        case .appStarted: "app.started"
        case .listening: "socket.listening"
        case .socketFailed: "socket.failed"
        case .ingestRejected: "ingest.rejected"
        case .clockSkew: "ingest.clockSkew"
        case .unreadLimitWindows: "ingest.unreadLimitWindows"
        case .storageFailed: "storage.failed"
        case .installed: "claudeCode.installed"
        case .installRefused: "claudeCode.installRefused"
        case .removed: "claudeCode.removed"
        case .planChanged: "plan.changed"
        case .demo: "demo.changed"
        case .loginItem: "loginItem.changed"
        case .notifications: "notifications.changed"
        case .exported: "data.exported"
        case .purged: "data.purged"
        }
    }

    /// Plain ASCII so every line passes the same scrub the helper applies.
    var text: String {
        switch self {
        case .appStarted(let version): "\(Product.name) \(version) started"
        case .listening: "Listening for Claude Code updates"
        case .socketFailed(let code): "Couldn't listen for updates" + (code.map { " (errno \($0))" } ?? "")
        case let .ingestRejected(otherUser, malformed, oversize, rateLimited, unmappable):
            "Updates set aside: \(otherUser) from another user, \(malformed) malformed, \(oversize) too large, "
                + "\(rateLimited) over the rate limit, \(unmappable) unreadable"
        case .clockSkew(let n): "\(n) update(s) had a clock more than 5 minutes off"
        case .unreadLimitWindows(let n): n == 0 ? "Claude Code no longer sends limits Pulse can't read"
            : "Claude Code sends \(n) limit(s) Pulse doesn't read yet; see the usage screen in Claude Code"
        case .storageFailed(let code): "Data file error" + (code.map { " (SQLite \($0))" } ?? "")
        case let .installed(kept, backup):
            "Connected to Claude Code" + (kept ? ", your status line still runs first" : "") + (backup.map { ", backup \($0)" } ?? "")
        case .installRefused(let reason): "Connect refused, nothing changed: \(reason)"
        case .removed(let outcome): "Removed from Claude Code: \(outcome)"
        case let .planChanged(id, confirmed): "Plan set to \(id ?? "not sure")" + (confirmed ? ", confirmed" : "")
        case .demo(let on): on ? "Demo data on" : "Demo data off"
        case .loginItem(let on): on ? "Open at login on" : "Open at login off"
        case .notifications(let status): "Notifications: \(status)"
        case let .exported(rows, scrubbed): "Exported \(rows) rows, \(scrubbed) value(s) removed by the scrub"
        case let .purged(readings, sessions): "Removed \(readings) reading(s) and \(sessions) session(s) past their keep time"
        }
    }
}

/// Append-only JSON-lines file for the Diagnostics drawer: at most 1 MB and 7 days (PRIVACY_AND_SECURITY §6).
/// Each line is scrubbed again on write; a line that fails keeps only its code.
@MainActor @Observable
public final class DiagnosticsLog {
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public enum Level: String, Codable, Sendable { case info, warning, error }
        public let at: Date
        public let level: Level
        public let code: String
        public let text: String
        public var id: String { "\(at.timeIntervalSince1970)|\(code)|\(text)" }
    }

    public static let maxBytes = 1_000_000
    public static let maxAge: TimeInterval = 7 * 86_400
    @ObservationIgnored static let logger = Logger(subsystem: "dev.tokone.pulse", category: "diagnostics")

    @ObservationIgnored public let url: URL
    public private(set) var entries: [Entry] = []
    @ObservationIgnored private let clock: any WallClock

    public init(url: URL, clock: any WallClock) {
        self.url = url
        self.clock = clock
        entries = Self.read(url)
        prune()
    }

    public func record(_ event: DiagnosticEvent) {
        let text = Scrubber.isAcceptable(event.text, maxLength: 512) ? event.text : "(details removed)"
        let entry = Entry(at: clock.now(), level: event.level, code: event.code, text: text)
        entries.append(entry)
        Self.logger.log("\(entry.code, privacy: .public) \(entry.text, privacy: .private)")
        guard let line = Self.encode(entry) else { return }
        append(line)
        if fileSize() > Self.maxBytes { prune(force: true) }
    }

    /// "Clear diagnostics".
    public func clear() {
        entries = []
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - File

    private func append(_ line: Data) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }

    /// Drops entries older than 7 days, then the oldest until the file is under half the cap.
    private func prune(force: Bool = false) {
        let cutoff = clock.now().addingTimeInterval(-Self.maxAge)
        var kept = entries.filter { $0.at >= cutoff }
        var lines = kept.compactMap(Self.encode)
        var size = lines.reduce(0) { $0 + $1.count }
        while size > Self.maxBytes / 2, !lines.isEmpty {
            size -= lines.removeFirst().count
            kept.removeFirst()
        }
        guard force || kept.count != entries.count else { return }
        entries = kept
        let data = lines.reduce(into: Data()) { $0.append($1) }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func fileSize() -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
    }

    static func encode(_ entry: Entry) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard var data = try? encoder.encode(entry) else { return nil }
        data.append(0x0A)
        return data
    }

    static func read(_ url: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(Entry.self, from: Data($0)) }
    }
}
