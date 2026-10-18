import CryptoKit
import Foundation

/// Builds socket frame v1 from raw status-line stdin (ARCHITECTURE §3).
/// Pure: no I/O, no clock read. The shim supplies `now`, the HMAC key and its own health facts.
public enum FrameBuilder {
    public static let kind = "claude_code.statusline"
    public static let version = 1
    /// stdin above this size is passed through to the user's command but never parsed.
    public static let maxParsedStdinBytes = 64 * 1024

    public struct Options: Sendable {
        public var shimVersion: String
        public var forwardCost: Bool          // On by default
        public var hmacKey: Data?             // 32 bytes from ~/.claude/clepso/session.key
        public var originalPresent: Bool
        public var truncated: Bool

        public init(shimVersion: String, forwardCost: Bool = true, hmacKey: Data?,
                    originalPresent: Bool, truncated: Bool = false) {
            self.shimVersion = shimVersion
            self.forwardCost = forwardCost
            self.hmacKey = hmacKey
            self.originalPresent = originalPresent
            self.truncated = truncated
        }
    }

    public enum NoFrameReason: String, Sendable, Equatable {
        case stdinTooLarge, notJSON, notObject, tooDeep, frameOversize
    }

    public enum Outcome: Sendable, Equatable {
        case frame(JSONValue)
        case noFrame(NoFrameReason)
    }

    /// Coarse transport bound for `resets_at` (§6). Product plausibility is the app's job.
    static func isPlausibleTransportEpoch(_ seconds: Double, now: Date) -> Bool {
        let n = now.timeIntervalSince1970
        return seconds >= n - 86_400 && seconds <= n + 400 * 86_400
    }

    public static func build(stdin: Data, now: Date, options: Options) -> Outcome {
        guard stdin.count <= maxParsedStdinBytes else { return .noFrame(.stdinTooLarge) }
        let input: JSONValue
        do {
            input = try JSONDecoder().decode(JSONValue.self, from: stdin)
        } catch is JSONDepthExceeded {
            return .noFrame(.tooDeep)
        } catch {
            // A depth failure can surface wrapped in a DecodingError.
            if "\(error)".contains("JSONDepthExceeded") { return .noFrame(.tooDeep) }
            return .noFrame(.notJSON)
        }
        guard case .object(let top) = input else { return .noFrame(.notObject) }

        var frame = JSONValue.object([:])
        var scrubCount = 0

        frame.set(.number(Double(version)), at: ["v"])
        frame.set(.string(kind), at: ["kind"])
        frame.set(.number((now.timeIntervalSince1970 * 1000).rounded(.down)), at: ["emitted_at_ms"])
        frame.set(.string(options.shimVersion), at: ["shim_version"])

        for rule in Allowlist.scalarRules {
            copy(rule.source, from: input, to: rule.target, in: &frame, kind: rule.kind, scrubCount: &scrubCount)
        }

        copyCurrentUsage(from: input, into: &frame, scrubCount: &scrubCount)
        copyRateLimits(from: input, into: &frame, now: now, scrubCount: &scrubCount)

        var noKey = false
        if case .string(let sessionID) = input.lookup(["session_id"]).valueOrNil {
            if let key = options.hmacKey {
                frame.set(.string(sessionRef(sessionID, key: key)), at: ["session_ref"])
            } else {
                noKey = true
            }
        }

        if options.forwardCost {
            copy(["cost", "total_cost_usd"], from: input, to: ["cost_usd_estimate"], in: &frame,
                 kind: .number(0...1_000_000_000), scrubCount: &scrubCount)
        }

        let unknownTopLevel = top.keys.filter { !Allowlist.documentedTopLevelKeys.contains($0) }.count
        // A limit Claude Code starts sending under `rate_limits` (a per-model weekly window, say) is
        // counted so the app can say so; like unknown top-level keys it is never copied and never named.
        var unknownWindows = 0
        if case .value(.object(let windows)) = input.lookup(["rate_limits"]) {
            unknownWindows = windows.keys.filter { !Allowlist.rateLimitWindows.contains($0) }.count
        }
        var health: [String: JSONValue] = [
            "stdin_bytes": .number(Double(stdin.count)),
            "truncated": .bool(options.truncated),
            "unknown_top_level_keys": .number(Double(unknownTopLevel)),
            "unknown_rate_limit_windows": .number(Double(unknownWindows)),
            "scrub_count": .number(Double(scrubCount)),
            "deadline_parse": .bool(false),
            "original_present": .bool(options.originalPresent),
        ]
        if noKey { health["no_key"] = .bool(true) }
        frame.set(.object(health), at: ["health"])

        // Fit the 4 KiB cap by dropping optional sections in the documented order, else give up.
        for section in [nil, ["prompt_cache"], ["context", "current_usage"]] {
            if let section { frame.remove(at: section) }
            if let payload = try? FrameCodec.payload(frame), payload.count <= FrameCodec.maxPayloadBytes {
                return .frame(frame)
            }
        }
        return .noFrame(.frameOversize)
    }

    /// First 8 bytes of HMAC-SHA256(key, session_id) as 16 hex characters.
    public static func sessionRef(_ sessionID: String, key: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(sessionID.utf8), using: SymmetricKey(data: key))
        return mac.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Copy rules

    static func copy(_ source: [String], from input: JSONValue, to target: [String], in frame: inout JSONValue,
                     kind: FieldRule.Kind, scrubCount: inout Int) {
        switch input.lookup(source) {
        case .absent:
            return
        case .null:
            frame.set(.null, at: target)
        case .value(let raw):
            if let accepted = validate(raw, kind) {
                frame.set(accepted, at: target)
            } else {
                frame.set(.null, at: target)
                scrubCount += 1
            }
        }
    }

    static func validate(_ value: JSONValue, _ kind: FieldRule.Kind) -> JSONValue? {
        switch (kind, value) {
        case (.string(let maxLength), .string(let s)):
            return Scrubber.isAcceptable(s, maxLength: maxLength) ? value : nil
        case (.integer(let range), .number(let n)):
            return n.isFinite && n.rounded() == n && range.contains(n) ? value : nil
        case (.number(let range), .number(let n)):
            return n.isFinite && range.contains(n) ? value : nil
        case (.bool, .bool):
            return value
        case (.oneOf(let allowed), .string(let s)):
            return allowed.contains(s) ? value : nil
        default:
            return nil
        }
    }

    static func copyCurrentUsage(from input: JSONValue, into frame: inout JSONValue, scrubCount: inout Int) {
        let source = ["context_window", "current_usage"]
        switch input.lookup(source) {
        case .absent:
            return
        case .null:
            frame.set(.null, at: ["context", "current_usage"])     // null before the first call and after /compact
        case .value(.object):
            for member in Allowlist.currentUsageMembers {
                copy(source + [member], from: input, to: ["context", "current_usage", member], in: &frame,
                     kind: .integer(0...Allowlist.maxTokens), scrubCount: &scrubCount)
            }
        case .value:
            frame.set(.null, at: ["context", "current_usage"])
            scrubCount += 1
        }
    }

    /// Each window is independently absent. A window whose `resets_at` fails the transport bound is
    /// dropped whole (§6); `rate_limits` itself absent stays absent, never an empty object.
    static func copyRateLimits(from input: JSONValue, into frame: inout JSONValue, now: Date, scrubCount: inout Int) {
        guard case .value(.object) = input.lookup(["rate_limits"]) else { return }
        frame.set(.object([:]), at: ["rate_limits"])
        for window in Allowlist.rateLimitWindows {
            let source = ["rate_limits", window]
            guard case .value(.object) = input.lookup(source) else { continue }
            let target = ["rate_limits", window]

            if case .value(let raw) = input.lookup(source + ["resets_at"]) {
                guard case .number(let seconds) = raw, seconds.rounded() == seconds,
                      isPlausibleTransportEpoch(seconds, now: now) else {
                    scrubCount += 1
                    continue
                }
            }
            frame.set(.object([:]), at: target)
            copy(source + ["used_percentage"], from: input, to: target + ["used_pct"], in: &frame,
                 kind: .number(Allowlist.percent), scrubCount: &scrubCount)
            copy(source + ["resets_at"], from: input, to: target + ["resets_at"], in: &frame,
                 kind: .integer(0...Allowlist.maxTokens), scrubCount: &scrubCount)
            if window == "spend_limit" {
                copy(source + ["used_usd"], from: input, to: target + ["used_usd"], in: &frame,
                     kind: .number(0...1_000_000_000), scrubCount: &scrubCount)
                copy(source + ["limit_usd"], from: input, to: target + ["limit_usd"], in: &frame,
                     kind: .number(0...1_000_000_000), scrubCount: &scrubCount)
                copy(source + ["period"], from: input, to: target + ["period"], in: &frame,
                     kind: .oneOf(["daily", "weekly", "monthly"]), scrubCount: &scrubCount)
            }
        }
    }
}

extension FieldPresence {
    var valueOrNil: JSONValue? {
        if case .value(let v) = self { return v }
        return nil
    }
}
