import CryptoKit
import Domain
import Foundation

/// Finds Codex's newest session files and reads only their tails (increment 3.4). Codex appends a token count after
/// every turn, so the last 256 KB of the newest few files always hold the latest limits; older files and the rest of
/// each file (where prompts and replies are) are never opened or read.
public enum CodexReader {
    public static let tailBytes = 256 * 1024
    /// Day folders looked at, newest first: a week covers a Mac left idle over a weekend.
    public static let daysBack = 8
    public static let filesRead = 3

    public static func sessionsURL(home: URL) -> URL { home.appendingPathComponent(".codex/sessions") }

    /// Whether Codex has ever written a session on this Mac (for Settings: "Codex found" / "not found").
    public static func isInstalled(home: URL) -> Bool {
        FileManager.default.fileExists(atPath: sessionsURL(home: home).path)
    }

    /// The latest reading across the newest session files, or nil when there is none in the last `daysBack` days.
    public static func latest(home: URL, now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> CodexReading? {
        newestFiles(home: home, now: now, calendar: calendar).compactMap { CodexRollout.latest(in: tail($0)) }
            .max { $0.observedAt < $1.observedAt }
    }

    static func newestFiles(home: URL, now: Date, calendar: Calendar) -> [URL] {
        let root = sessionsURL(home: home), fm = FileManager.default
        var found: [(URL, Date)] = []
        // Codex names day folders by the local date; look at UTC and local both by widening one day.
        for back in 0...daysBack {
            guard let day = calendar.date(byAdding: .day, value: -back, to: now) else { continue }
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            guard let y = c.year, let m = c.month, let d = c.day else { continue }
            let folder = root.appendingPathComponent(String(format: "%04d/%02d/%02d", y, m, d))
            let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names where name.hasPrefix("rollout-") && name.hasSuffix(".jsonl") {
                let url = folder.appendingPathComponent(name)
                let modified = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
                found.append((url, modified))
            }
            if found.count >= filesRead * 4 { break }
        }
        return found.sorted { $0.1 > $1.1 }.prefix(filesRead).map(\.0)
    }

    static func tail(_ url: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        return (try? handle.readToEnd()) ?? Data()
    }
}

/// Turns a reading into the same observations the Claude Code status line produces, under `codex.*` pool keys.
public enum CodexMapper {
    public static let adapterID = "codex.sessions"
    public static let providerID = "openai"

    /// A window's pool key: `five_hour` and `seven_day` for the lengths Clepso already knows, so the charts, pace
    /// estimate and goals treat them like Claude Code's; any other length keeps its minutes in the key.
    public static func poolKey(_ window: CodexReading.Window?, fallback: String) -> String {
        switch window?.windowMinutes {
        case 300: "codex.rate_limits.five_hour"
        case 10_080: "codex.rate_limits.seven_day"
        case let m?: "codex.rate_limits.window_\(m)m"
        case nil: "codex.rate_limits.\(fallback)"
        }
    }

    public static func observations(_ reading: CodexReading, connectionID: UUID, receivedAt: Date) -> [IncomingObservation] {
        var out: [IncomingObservation] = []
        func emit(_ key: String, _ kind: MetricKind, _ value: MetricValue) {
            let quality: Quality = if case .absent = value { .unknown } else { .reported }
            let observedMs = Int64((reading.observedAt.timeIntervalSince1970 * 1000).rounded())
            let subject = SubjectKey.pool(providerPoolKey: key)
            let fingerprint = [connectionID.uuidString, subject.canonical, kind.rawValue, value.canonical, String(observedMs), "codex"]
                .joined(separator: "|")
            out.append(IncomingObservation(subject: subject, sessionRef: nil, modelID: reading.model, kind: kind, value: value,
                                           observedAt: reading.observedAt, receivedAt: receivedAt, evidence: .officialLocalTelemetry,
                                           quality: quality, sourceVersion: nil,
                                           dedupeKey: SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()))
        }
        for (window, fallback) in [(reading.primary, "primary"), (reading.secondary, "secondary")] {
            let key = poolKey(window, fallback: fallback)
            emit(key, .quotaUsedPct, window?.usedPct.map(MetricValue.percent) ?? .absent(window == nil ? .providerNull : .providerOmitted))
            emit(key, .resetAt, window?.resetsAt.map(MetricValue.instant) ?? .absent(window == nil ? .providerNull : .providerOmitted))
        }
        return out
    }
}
