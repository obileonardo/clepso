import Foundation

/// Codex's limits as it records them in its own session files (increment 3.4). Codex writes
/// `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, one JSON object per line. The files also hold prompts, replies and
/// paths, so this parser decodes only two line types and skips every other line without decoding it:
/// - `event_msg` whose payload `type` is `token_count`: rate limits, plan type, session token totals, context window;
/// - `turn_context`: the model name.
/// Plus Codex's version from the file's first line, looked up by its bytes without decoding (`version(inHead:)`).
/// From those it keeps an allowlist of numbers and short identifiers; nothing else leaves this file.
public struct CodexReading: Sendable, Equatable {
    public struct Window: Sendable, Equatable {
        public let usedPct: Decimal?
        public let windowMinutes: Int?
        public let resetsAt: Date?
    }

    public struct Tokens: Sendable, Equatable {
        public let input: Int64
        public let cachedInput: Int64
        public let cacheWrite: Int64
        public let output: Int64
        public let reasoningOutput: Int64
    }

    public let observedAt: Date
    public let limitID: String?
    public let plan: String?
    public let primary: Window?
    public let secondary: Window?
    public let sessionTokens: Tokens?
    public let contextWindow: Int64?
    public let model: String?
    /// Codex's version as its session file records it (`session_meta.cli_version`); nil when not found.
    public var version: String?
}

public enum CodexRollout {
    /// Lines longer than this are never token counts (those are well under 2 KB); they are skipped undecoded.
    static let maxLine = 16 * 1024

    /// Codex's own allowance: `limit_id` "codex", or no id at all (a Codex that writes none). Codex also reports
    /// other buckets in the same event, with their own windows or none (seen on the founder's Mac, 16 Oct 2026:
    /// "premium" with both windows null, "base_model_inference" with only a 10080-minute window at 84%). Those are other
    /// limits, so they never stand in for the 5-hour and weekly numbers.
    public static let limitID = "codex"

    /// The latest reading in `data` (the tail of a rollout file), or nil if it holds no token count with limits.
    /// Only Codex's own allowance counts (`limitID`), and only a token count that reports at least one window: one
    /// with both windows null says nothing about them. The first line may be cut by the tail read; it fails to decode
    /// and is skipped like any malformed line.
    public static func latest(in data: Data) -> CodexReading? {
        var model: String?
        var plan: String?
        var best: CodexReading?
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard line.count <= maxLine else { continue }
            // Cheap byte checks first, so lines carrying prompts or replies are never handed to the JSON decoder.
            if contains(line, #""turn_context""#) {
                if let m = decodeModel(Data(line)) { model = m }
            } else if contains(line, #""token_count""#), let reading = decodeTokenCount(Data(line), model: model),
                      reading.limitID == nil || reading.limitID == limitID, reading.primary != nil || reading.secondary != nil {
                if let p = reading.plan { plan = p }
                if best == nil || reading.observedAt >= best!.observedAt { best = reading }
            }
        }
        guard let b = best else { return nil }
        // The model line can follow the token count it belongs to; Codex sometimes writes a token count with no plan.
        return CodexReading(observedAt: b.observedAt, limitID: b.limitID, plan: b.plan ?? plan, primary: b.primary,
                            secondary: b.secondary, sessionTokens: b.sessionTokens, contextWindow: b.contextWindow,
                            model: b.model ?? model)
    }

    /// Codex's version from the head of a session file: its first line (`session_meta`) names it within the first few
    /// hundred bytes, before the instructions. Looked up by its bytes like `CodexAgents` does; nothing is decoded.
    public static func version(inHead head: Data) -> String? {
        head.withUnsafeBytes { raw -> String? in
            guard CodexBytes.find(Array(#""type":"session_meta""#.utf8), in: raw, limit: 512) != nil,
                  case .string(let v)? = CodexBytes.scalar(Array(#""cli_version":"#.utf8), in: raw, limit: raw.count) else { return nil }
            return v
        }
    }

    static func contains(_ line: Data.SubSequence, _ needle: String) -> Bool {
        line.firstRange(of: Data(needle.utf8)) != nil
    }

    static func decodeModel(_ line: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any], root["type"] as? String == "turn_context",
              let payload = root["payload"] as? [String: Any] else { return nil }
        return identifier(payload["model"])
    }

    static func decodeTokenCount(_ line: Data, model: String?) -> CodexReading? {
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any], root["type"] as? String == "event_msg",
              let payload = root["payload"] as? [String: Any], payload["type"] as? String == "token_count",
              let at = timestamp(root["timestamp"]) else { return nil }
        let limits = payload["rate_limits"] as? [String: Any]
        guard limits != nil else { return nil }             // a token count without limits says nothing about them
        let info = payload["info"] as? [String: Any]
        let total = info?["total_token_usage"] as? [String: Any]
        let tokens = total.flatMap { t -> CodexReading.Tokens? in
            guard let input = count(t["input_tokens"]), let output = count(t["output_tokens"]) else { return nil }
            return CodexReading.Tokens(input: input, cachedInput: count(t["cached_input_tokens"]) ?? 0,
                                       cacheWrite: count(t["cache_write_input_tokens"]) ?? 0, output: output,
                                       reasoningOutput: count(t["reasoning_output_tokens"]) ?? 0)
        }
        return CodexReading(observedAt: at, limitID: identifier(limits?["limit_id"]), plan: identifier(limits?["plan_type"]),
                            primary: window(limits?["primary"]), secondary: window(limits?["secondary"]),
                            sessionTokens: tokens, contextWindow: count(info?["model_context_window"]), model: model)
    }

    static func window(_ any: Any?) -> CodexReading.Window? {
        guard let w = any as? [String: Any] else { return nil }
        let used = (w["used_percent"] as? NSNumber).flatMap { n -> Decimal? in
            let d = n.doubleValue
            return d.isFinite && d >= 0 && d <= 1000 ? Decimal(string: String(format: "%.2f", d)) : nil
        }
        let minutes = (w["window_minutes"] as? NSNumber).map(\.intValue).flatMap { $0 > 0 && $0 <= 525_600 ? $0 : nil }
        let resets = (w["resets_at"] as? NSNumber).flatMap { n -> Date? in
            let s = n.doubleValue                              // epoch seconds; years 2020–2100 only
            return s > 1_577_836_800 && s < 4_102_444_800 ? Date(timeIntervalSince1970: s) : nil
        }
        return CodexReading.Window(usedPct: used, windowMinutes: minutes, resetsAt: resets)
    }

    static func count(_ any: Any?) -> Int64? {
        guard let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let v = n.int64Value
        return v >= 0 && v < 1_000_000_000_000_000 ? v : nil
    }

    /// A short identifier: letters, digits, `.`, `-`, `_`, at most 48 characters. Anything else is dropped.
    static func identifier(_ any: Any?) -> String? {
        guard let s = any as? String, !s.isEmpty, s.count <= 48,
              s.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII || "._-".unicodeScalars.contains($0) }) else { return nil }
        return s
    }

    static func timestamp(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        return TimestampParser.shared.date(from: s)
    }
}

/// Item 8: two ISO 8601 parsers made once. Making one per line was about half the cost of reading Codex's files: the tails
/// of three long sessions took 95 ms, now 45; a full scan of them 1.45 s, now 0.64 (debug build). The lock keeps each
/// parser on one thread at a time (a scan and a tail read can run concurrently).
final class TimestampParser: @unchecked Sendable {
    static let shared = TimestampParser()
    private let lock = NSLock()
    private let fractional = ISO8601DateFormatter()
    private let whole = ISO8601DateFormatter()

    init() {
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        whole.formatOptions = [.withInternetDateTime]
    }

    func date(from s: String) -> Date? {
        lock.withLock { fractional.date(from: s) ?? whole.date(from: s) }
    }
}
