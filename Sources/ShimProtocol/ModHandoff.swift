import Foundation

/// What Clepso's Claude Code mod hands the helper (`clepso-statusline --mod`) from the Claude desktop app's Code tab and
/// the VS Code panel (docs/specs/mod-bridge.md §5, PRIVACY_AND_SECURITY §4.4). Pure: no I/O, no clock read.
///
/// The helper is the allowlist gate, for the mod as for the status line: this reads only the hand-off fields below,
/// translates them into the status-line input they correspond to, and lets `FrameBuilder` build frame v1 with every
/// one of its bounds, scrubs and the session-id HMAC unchanged. The frame then carries two optional fields, `via: "mod"`
/// and `surface`, which older apps ignore.
public enum ModHandoff {
    public static let version = 1
    /// The hand-off is a few hundred bytes; anything larger is not one.
    public static let maxStdinBytes = 64 * 1024
    public static let via = "mod"
    /// The apps that draw a session the status line doesn't reach; anything else arrives as `other`.
    public static let surfaces: Set<String> = ["desktop", "vscode", "mobile", "other"]
    /// The windows the status line carries too (`Allowlist.rateLimitWindows`). Other kinds are counted, never named.
    static let kinds = Set(Allowlist.rateLimitWindows)
    static let maxWindows = 8
    static let maxOtherWindows = 64.0
    static let fields: Set<String> = ["v", "surface", "session_id", "version", "rate_limits", "other_windows", "context"]

    public enum NoFrameReason: String, Sendable, Equatable {
        case stdinTooLarge, notJSON, notObject, tooDeep, unsupportedVersion, frameOversize
    }

    public enum Outcome: Sendable, Equatable {
        case frame(JSONValue)
        case noFrame(NoFrameReason)
    }

    public static func build(stdin: Data, now: Date, shimVersion: String, hmacKey: Data?) -> Outcome {
        guard stdin.count <= maxStdinBytes else { return .noFrame(.stdinTooLarge) }
        let input: JSONValue
        do {
            input = try JSONDecoder().decode(JSONValue.self, from: stdin)
        } catch is JSONDepthExceeded {
            return .noFrame(.tooDeep)
        } catch {
            if "\(error)".contains("JSONDepthExceeded") { return .noFrame(.tooDeep) }
            return .noFrame(.notJSON)
        }
        guard case .object(let top) = input else { return .noFrame(.notObject) }
        guard top["v"] == .number(Double(version)) else { return .noFrame(.unsupportedVersion) }

        // The status-line input these fields stand for (statusline-shim.md §6, mod-bridge.md §5.2).
        var statusLine: [String: JSONValue] = [:]
        var scrubs = 0, otherWindows = 0

        if case .string(let id)? = top["session_id"], !id.isEmpty, id.utf8.count <= 128 {
            statusLine["session_id"] = .string(id)
        } else if top["session_id"] != nil {
            scrubs += 1
        }
        if let version = top["version"] { statusLine["version"] = version }       // FrameBuilder's string rule applies

        if case .array(let list)? = top["rate_limits"] {
            var windows: [String: JSONValue] = [:]
            for entry in list.prefix(maxWindows) {
                guard case .object(let window) = entry, case .string(let kind)? = window["kind"], kinds.contains(kind),
                      windows[kind] == nil else {
                    otherWindows += 1
                    continue
                }
                var out: [String: JSONValue] = [:]
                if let used = window["percent_used"] { out["used_percentage"] = used }
                if let reset = window["resets_at"] {
                    if case .string(let text) = reset, let date = parseInstant(text) {
                        out["resets_at"] = .number(date.timeIntervalSince1970.rounded(.down))
                    } else {
                        scrubs += 1
                    }
                }
                windows[kind] = .object(out)
            }
            otherWindows += max(0, list.count - maxWindows)
            if !windows.isEmpty { statusLine["rate_limits"] = .object(windows) }
        } else if top["rate_limits"] != nil {
            scrubs += 1
        }

        if let other = top["other_windows"] {
            if case .number(let n) = other, n.isFinite, n.rounded() == n, (0...maxOtherWindows).contains(n) {
                otherWindows += Int(n)
            } else {
                scrubs += 1
            }
        }

        if case .object(let context)? = top["context"] {
            var window: [String: JSONValue] = [:]
            if let size = context["window"] { window["context_window_size"] = size }
            if let percent = context["percent"] { window["used_percentage"] = percent }
            if let tokens = context["tokens"] { window["total_input_tokens"] = tokens }
            if !window.isEmpty { statusLine["context_window"] = .object(window) }
        } else if top["context"] != nil {
            scrubs += 1
        }

        let surface: String = if case .string(let s)? = top["surface"], surfaces.contains(s) { s } else { "other" }

        guard let translated = try? JSONEncoder().encode(JSONValue.object(statusLine)) else { return .noFrame(.notJSON) }
        let options = FrameBuilder.Options(shimVersion: shimVersion, forwardCost: false, hmacKey: hmacKey, originalPresent: false)
        guard case .frame(var frame) = FrameBuilder.build(stdin: translated, now: now, options: options) else {
            return .noFrame(.frameOversize)
        }
        frame.set(.string(via), at: ["via"])
        frame.set(.string(surface), at: ["surface"])
        // Health describes the hand-off itself: its size, its unknown keys (counted, never named) and what was scrubbed.
        let unknownKeys = top.keys.filter { !fields.contains($0) }.count
        frame.set(.number(Double(stdin.count)), at: ["health", "stdin_bytes"])
        frame.set(.number(Double(unknownKeys)), at: ["health", "unknown_top_level_keys"])
        frame.set(.number(Double(otherWindows)), at: ["health", "unknown_rate_limit_windows"])
        if case .value(.number(let built)) = frame.lookup(["health", "scrub_count"]) {
            frame.set(.number(built + Double(scrubs)), at: ["health", "scrub_count"])
        }
        guard let payload = try? FrameCodec.payload(frame), payload.count <= FrameCodec.maxPayloadBytes else {
            return .noFrame(.frameOversize)
        }
        return .frame(frame)
    }

    /// ISO 8601 with or without fractional seconds, as `resetsAt` arrives (`2026-10-19T14:30:00.000Z`).
    static func parseInstant(_ text: String) -> Date? {
        guard text.utf8.count <= 40 else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
