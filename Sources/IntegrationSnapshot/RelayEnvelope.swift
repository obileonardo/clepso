import Foundation

/// The bounded mobile relay response. Provider values remain reported observations, never proof of availability.
public struct RelayEnvelope: Codable, Equatable, Sendable {
    public let snapshot: UsageSnapshot
    public let receivedAt: Date
    public let expiresAt: Date
    public init(snapshot: UsageSnapshot, receivedAt: Date, expiresAt: Date) {
        self.snapshot = snapshot; self.receivedAt = receivedAt; self.expiresAt = expiresAt
    }
    public var valid: Bool {
        snapshot.valid && !snapshot.demo && receivedAt.timeIntervalSince1970.isFinite && expiresAt.timeIntervalSince1970.isFinite &&
        expiresAt > receivedAt && expiresAt.timeIntervalSince(receivedAt) <= 3600 &&
        snapshot.generatedAt <= receivedAt.addingTimeInterval(300)
    }
    public func isCurrent(at now: Date) -> Bool {
        valid && now < expiresAt && receivedAt <= now.addingTimeInterval(60) &&
        now.timeIntervalSince(snapshot.generatedAt) < 600
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { value in
            let c = try value.singleValueContainer(), text = try c.decode(String.self)
            if let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
                ?? (try? Date.ISO8601FormatStyle().parse(text)) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid relay timestamp")
        }
        return decoder
    }
}

public enum CompanionReminderPlan {
    public struct Reminder: Equatable, Sendable {
        public let id: String
        public let provider: UsageSnapshot.Provider
        public let window: UsageSnapshot.Window
        public let fireAt: Date
        public let reportedReset: Date
        public let observedAt: Date
    }
    public static let prefix = "clepso.mobile.expected-reset."
    /// Scheduling uses a current automatic report. Notifications describe an expected time, not renewed quota.
    /// Fresh snapshots replace/cancel requests; an offline device cannot guarantee receipt of a cancellation.
    public static func make(_ envelope: RelayEnvelope?, enabled: Bool, leadMinutes: Int, now: Date) -> [Reminder] {
        guard enabled, [0, 5, 15].contains(leadMinutes), let envelope, envelope.isCurrent(at: now) else { return [] }
        var latest: [String: UsageSnapshot.Limit] = [:]
        for row in envelope.snapshot.limits where row.source == .automatic && row.state == .reported && row.freshness(at: now) == "fresh" {
            let key = row.provider.rawValue + "." + row.window.rawValue
            if let old = latest[key], (old.observedAt ?? .distantPast) >= (row.observedAt ?? .distantPast) { continue }
            latest[key] = row
        }
        return latest.keys.sorted().compactMap { key in
            guard let row = latest[key], let observed = row.observedAt, let reset = row.resetsAt,
                  reset > now, reset <= now.addingTimeInterval(7 * 86400) else { return nil }
            let fire = reset.addingTimeInterval(-Double(leadMinutes * 60))
            guard fire > now.addingTimeInterval(5) else { return nil }
            return Reminder(id: prefix + key, provider: row.provider, window: row.window, fireAt: fire,
                            reportedReset: reset, observedAt: observed)
        }.prefix(24).map { $0 }
    }
}

public extension UsageSnapshot.Provider {
    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .claudeChat: "Claude Chat"
        case .chatgpt: "ChatGPT"
        case .gemini: "Gemini"
        case .grok: "Grok"
        case .cursor: "Cursor"
        case .copilot: "Copilot"
        case .windsurf: "Windsurf"
        }
    }
}
public extension UsageSnapshot.Window {
    var displayName: String {
        switch self { case .fiveHour: "5-hour"; case .weekly: "7-day"; case .daily: "Daily" }
    }
}
