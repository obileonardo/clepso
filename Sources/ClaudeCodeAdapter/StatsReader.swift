import Foundation

/// Claude Code's local usage statistics, the data behind `/stats` (increment 1.7d). Read from
/// `~/.claude/stats-cache.json`, a file Claude Code writes and Anthropic does not document, so every field passes an
/// allowlist: dates, counts, model ids and token totals only. The longest session's id is never read. Clepso reads
/// the file on demand after the user turns the feature on, and does not copy it into its own database.
public struct ClaudeCodeStats: Sendable, Equatable {
    public struct Day: Sendable, Equatable {
        public let date: String                 // YYYY-MM-DD as Claude Code writes it
        public let messages: Int
        public let sessions: Int
        public let toolCalls: Int
    }

    public struct DayTokens: Sendable, Equatable {
        public let date: String
        public let byModel: [String: Int64]     // model id → tokens that day, as Claude Code counts them
    }

    public struct ModelTotals: Sendable, Equatable {
        public let model: String
        public let input: Int64
        public let output: Int64
        public let cacheRead: Int64
        public let cacheWrite: Int64
        public var total: Int64 { input + output + cacheRead + cacheWrite }
    }

    public let formatVersion: Int?
    public let computedThrough: String?         // the last day Claude Code has folded in
    public let days: [Day]
    public let dailyTokens: [DayTokens]
    public let models: [ModelTotals]
    public let totalSessions: Int?
    public let totalMessages: Int?
    public let longestSessionMs: Int64?
    public let longestSessionMessages: Int?
    public let firstSessionDate: String?        // YYYY-MM-DD, from Claude Code's first-session timestamp
    public let hourCounts: [Int: Int]           // hour of day 0–23 → sessions started

    /// Fields the reader dropped because they failed the allowlist; shown in Diagnostics, never their values.
    public let rejected: Int
}

public enum StatsReader {
    public enum Problem: Error, Equatable { case missing, unreadable, notAnObject }

    /// The file's location for a given home folder.
    public static func url(home: URL) -> URL { home.appendingPathComponent(".claude/stats-cache.json") }

    public static func read(home: URL) -> Result<ClaudeCodeStats, Problem> {
        let url = url(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return .failure(.missing) }
        guard let data = try? Data(contentsOf: url, options: .uncached), data.count < 16 * 1024 * 1024 else { return .failure(.unreadable) }
        return parse(data)
    }

    public static func parse(_ data: Data) -> Result<ClaudeCodeStats, Problem> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failure(.notAnObject) }
        var rejected = 0

        func count(_ value: Any?) -> Int? {
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            let d = n.doubleValue
            guard d.isFinite, d >= 0, d.rounded() == d, d < 9.0e15 else { return nil }
            return Int(d)
        }
        func required(_ value: Any?) -> Int? {
            let n = count(value)
            if n == nil, value != nil { rejected += 1 }
            return n
        }
        func day(_ value: Any?) -> String? {
            guard let s = value as? String, s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
            return s
        }
        func model(_ id: String) -> String? {
            id.range(of: #"^[a-z0-9][a-z0-9.\-]{0,63}$"#, options: .regularExpression) != nil ? id : nil
        }

        let days: [ClaudeCodeStats.Day] = (root["dailyActivity"] as? [Any] ?? []).compactMap { item in
            guard let o = item as? [String: Any], let date = day(o["date"]) else { rejected += 1; return nil }
            return .init(date: date, messages: required(o["messageCount"]) ?? 0, sessions: required(o["sessionCount"]) ?? 0,
                         toolCalls: required(o["toolCallCount"]) ?? 0)
        }
        let dailyTokens: [ClaudeCodeStats.DayTokens] = (root["dailyModelTokens"] as? [Any] ?? []).compactMap { item in
            guard let o = item as? [String: Any], let date = day(o["date"]), let byModel = o["tokensByModel"] as? [String: Any] else { rejected += 1; return nil }
            var tokens: [String: Int64] = [:]
            for (id, value) in byModel {
                guard let id = model(id), let n = count(value) else { rejected += 1; continue }
                tokens[id] = Int64(n)
            }
            return .init(date: date, byModel: tokens)
        }
        let models: [ClaudeCodeStats.ModelTotals] = (root["modelUsage"] as? [String: Any] ?? [:]).compactMap { id, value in
            guard let id = model(id), let o = value as? [String: Any] else { rejected += 1; return nil }
            return .init(model: id, input: Int64(required(o["inputTokens"]) ?? 0), output: Int64(required(o["outputTokens"]) ?? 0),
                         cacheRead: Int64(required(o["cacheReadInputTokens"]) ?? 0), cacheWrite: Int64(required(o["cacheCreationInputTokens"]) ?? 0))
        }.sorted { $0.total > $1.total }
        let longest = root["longestSession"] as? [String: Any]               // `sessionId` is deliberately never read
        var hours: [Int: Int] = [:]
        for (key, value) in root["hourCounts"] as? [String: Any] ?? [:] {
            guard let hour = Int(key), (0...23).contains(hour), let n = count(value) else { rejected += 1; continue }
            hours[hour] = n
        }
        let first = (root["firstSessionDate"] as? String).flatMap { String($0.prefix(10)) }.flatMap(day)

        return .success(ClaudeCodeStats(
            formatVersion: count(root["version"]), computedThrough: day(root["lastComputedDate"]),
            days: days.sorted { $0.date < $1.date }, dailyTokens: dailyTokens.sorted { $0.date < $1.date }, models: models,
            totalSessions: count(root["totalSessions"]), totalMessages: count(root["totalMessages"]),
            longestSessionMs: count(longest?["duration"]).map(Int64.init), longestSessionMessages: count(longest?["messageCount"]),
            firstSessionDate: first, hourCounts: hours, rejected: rejected))
    }

    /// "claude-opus-5-5" → "Opus 5.5", "claude-haiku-4-5-20251001" → "Haiku 4.5". Unknown shapes are returned as given.
    public static func displayName(_ id: String) -> String {
        let parts = id.split(separator: "-").map(String.init)
        guard parts.count >= 3, parts[0] == "claude" else { return id }
        let family = parts[1].prefix(1).uppercased() + parts[1].dropFirst()
        let version = parts.dropFirst(2).filter { $0.count <= 2 && Int($0) != nil }
        return version.isEmpty ? family : "\(family) \(version.joined(separator: "."))"
    }
}
