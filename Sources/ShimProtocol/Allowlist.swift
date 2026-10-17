import Foundation

/// One allowlisted stdin path and how it lands in the frame. This table is
/// docs/specs/statusline-shim.md §6 as code (founder decision A4); anything not listed is
/// never copied, so new or unexpected Claude Code fields are dropped by construction.
public struct FieldRule: Sendable {
    public enum Kind: Sendable {
        case string(maxLength: Int)
        case integer(ClosedRange<Double>)
        case number(ClosedRange<Double>)
        case bool
        case oneOf(Set<String>)
    }

    public let source: [String]
    public let target: [String]
    public let kind: Kind

    init(_ source: String, _ target: String, _ kind: Kind) {
        self.source = source.split(separator: ".").map(String.init)
        self.target = target.split(separator: ".").map(String.init)
        self.kind = kind
    }
}

public enum Allowlist {
    static let maxTokens = 9_007_199_254_740_992.0   // 2^53
    static let percent: ClosedRange<Double> = 0...1000 // overage above 100 tolerated (PRD §9)

    /// Scalar fields copied one to one. Rate-limit windows, `current_usage`, `session_id` and the
    /// cost estimate have structural rules and are handled in `FrameBuilder`.
    public static let scalarRules: [FieldRule] = [
        FieldRule("version", "source_version", .string(maxLength: 32)),
        FieldRule("model.id", "model.id", .string(maxLength: 64)),
        FieldRule("model.display_name", "model.display_name", .string(maxLength: 64)),
        FieldRule("context_window.context_window_size", "context.window_size", .integer(1...100_000_000)),
        FieldRule("context_window.used_percentage", "context.used_pct", .number(percent)),
        FieldRule("context_window.remaining_percentage", "context.remaining_pct", .number(percent)),
        FieldRule("context_window.total_input_tokens", "context.total_input_tokens", .integer(0...maxTokens)),
        FieldRule("context_window.total_output_tokens", "context.total_output_tokens", .integer(0...maxTokens)),
        FieldRule("exceeds_200k_tokens", "context.exceeds_200k", .bool),
        FieldRule("prompt_cache.warm", "prompt_cache.warm", .bool),
        FieldRule("prompt_cache.caching_observed", "prompt_cache.caching_observed", .bool),
        FieldRule("prompt_cache.ttl", "prompt_cache.ttl", .oneOf(["5m", "1h"])),
        FieldRule("prompt_cache.expires_at", "prompt_cache.expires_at", .integer(0...maxTokens)),
        FieldRule("prompt_cache.hit_ratio", "prompt_cache.hit_ratio", .number(0...1)),
        FieldRule("prompt_cache.requests", "prompt_cache.requests", .integer(0...maxTokens)),
        FieldRule("prompt_cache.misses", "prompt_cache.misses", .integer(0...maxTokens)),
        FieldRule("effort.level", "session.effort_level", .oneOf(["low", "medium", "high", "xhigh", "max"])),
        FieldRule("thinking.enabled", "session.thinking_enabled", .bool),
        FieldRule("fast_mode", "session.fast_mode", .bool),
        // Founder decision 17 Oct 2026 (A4 amended for increment 1.7): session time and lines of code changed.
        // Counts and durations only; never file names, diffs or paths.
        FieldRule("cost.total_duration_ms", "activity.wall_ms", .integer(0...maxTokens)),
        FieldRule("cost.total_api_duration_ms", "activity.api_ms", .integer(0...maxTokens)),
        FieldRule("cost.total_lines_added", "activity.lines_added", .integer(0...maxTokens)),
        FieldRule("cost.total_lines_removed", "activity.lines_removed", .integer(0...maxTokens)),
    ]

    public static let currentUsageMembers = [
        "input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens",
    ]

    public static let rateLimitWindows = ["five_hour", "seven_day", "spend_limit"]

    /// Top-level keys the status-line doc describes (forwarded or deliberately dropped). Any other
    /// top-level key is counted in `health.unknown_top_level_keys`, never copied, never named.
    public static let documentedTopLevelKeys: Set<String> = [
        "session_id", "version", "model", "context_window", "exceeds_200k_tokens", "rate_limits",
        "prompt_cache", "effort", "thinking", "fast_mode", "cost",
        "cwd", "workspace", "transcript_path", "session_name", "prompt_id", "output_style",
        "vim", "agent", "pr", "worktree",
    ]
}

/// Second-layer string scrub (PRIVACY_AND_SECURITY.md §4): drop rather than redact.
public enum Scrubber {
    /// The app applies the same rule again to everything it logs or exports.
    public static func isAcceptable(_ string: String, maxLength: Int) -> Bool {
        guard string.utf8.count <= maxLength else { return false }
        guard string.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) }) else { return false }
        if string.contains("/") || string.contains("\\") || string.contains("@") || string.contains("$HOME") {
            return false
        }
        if string.contains("sk-ant-") || string.contains("AKIA") || string.contains("ghp_") || string.contains("Bearer ") {
            return false
        }
        // "sk-" only at a token start, so model names such as "task-…" are not caught.
        if string.range(of: #"(^|[^A-Za-z0-9])sk-"#, options: .regularExpression) != nil { return false }
        // Long base64 or hex runs. Hyphen and underscore are excluded so hyphenated model ids pass.
        if string.range(of: #"[A-Za-z0-9+/=]{32,}"#, options: .regularExpression) != nil { return false }
        return true
    }
}
