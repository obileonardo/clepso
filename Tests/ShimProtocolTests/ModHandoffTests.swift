import Foundation
import Testing
@testable import ShimProtocol

/// v0.3 (docs/specs/mod-bridge.md §5): the helper's allowlist for the Claude Code mod's hand-off. It reads only the
/// hand-off's own fields, translates them to the status-line input and lets FrameBuilder build frame v1 unchanged.
@Suite("Mod hand-off")
struct ModHandoffTests {
    static let now = Date(timeIntervalSince1970: 1_792_159_200)       // 2026-10-16T14:00:00Z, the fixture clock
    static let key = Data(repeating: 7, count: 32)

    func build(_ json: String, key: Data? = ModHandoffTests.key) -> ModHandoff.Outcome {
        ModHandoff.build(stdin: Data(json.utf8), now: Self.now, shimVersion: "0.1.0", hmacKey: key)
    }

    func frame(_ json: String) throws -> JSONValue {
        guard case .frame(let frame) = build(json) else { throw Failure.noFrame }
        return frame
    }

    enum Failure: Error { case noFrame }

    /// The desktop app's second measurement on 19 Oct 2026 (evidence/mod-spike-19oct), as the mod hands it over.
    static let desktop = """
    {"v": 1, "surface": "desktop", "session_id": "00000000-0000-4000-8000-00000000d351", "version": "2.1.299",
     "rate_limits": [{"kind": "five_hour", "percent_used": 26, "resets_at": "2026-10-19T14:30:00.000Z"},
                     {"kind": "seven_day", "percent_used": 70, "resets_at": "2026-10-22T04:00:00.000Z"}],
     "other_windows": 0, "context": {"tokens": 93615, "window": 1000000, "percent": 9}}
    """

    @Test("Every field maps to its status-line counterpart; the frame is v1 with via and surface")
    func mapping() throws {
        let f = try frame(Self.desktop)
        #expect(f["v"] == .number(1) && f["kind"] == .string("claude_code.statusline"))
        #expect(f["via"] == .string("mod") && f["surface"] == .string("desktop"))
        #expect(f.lookup(["rate_limits", "five_hour", "used_pct"]) == .value(.number(26)))
        #expect(f.lookup(["rate_limits", "five_hour", "resets_at"]) == .value(.number(1_792_420_200)))   // 2026-10-19T14:30:00Z
        #expect(f.lookup(["rate_limits", "seven_day", "used_pct"]) == .value(.number(70)))
        #expect(f.lookup(["rate_limits", "seven_day", "resets_at"]) == .value(.number(1_792_641_600)))   // 2026-10-22T04:00:00Z
        #expect(f.lookup(["context", "window_size"]) == .value(.number(1_000_000)))
        #expect(f.lookup(["context", "used_pct"]) == .value(.number(9)))
        #expect(f.lookup(["context", "total_input_tokens"]) == .value(.number(93615)))
        #expect(f["source_version"] == .string("2.1.299"))
        #expect(f["session_ref"] == .string(FrameBuilder.sessionRef("00000000-0000-4000-8000-00000000d351", key: Self.key)))
        #expect(f["model"] == nil && f["cost_usd_estimate"] == nil, "the mod sends neither")
        #expect(f.lookup(["health", "original_present"]) == .value(.bool(false)))
        #expect(f.lookup(["health", "scrub_count"]) == .value(.number(0)))
        #expect(f.lookup(["health", "unknown_top_level_keys"]) == .value(.number(0)))
        #expect(f.lookup(["health", "stdin_bytes"]) == .value(.number(Double(Self.desktop.utf8.count))))
        let wire = try FrameCodec.encode(f)
        #expect(try FrameCodec.decode(wire) == f, "the app's codec accepts it")
        #expect(!String(decoding: wire, as: UTF8.self).contains("00000000-0000"), "the raw session id never leaves")
    }

    @Test("Unknown kinds, keys and window fields are counted, never named; a surface outside the list is other")
    func unknowns() throws {
        let f = try frame("""
        {"v": 1, "surface": "canary-app", "session_id": "s", "canary_key": "canary-value", "prompt": "canary prompt",
         "rate_limits": [{"kind": "five_hour", "percent_used": 41.5, "label": "canary-label"},
                         {"kind": "canary_weekly_opus", "percent_used": 9},
                         {"kind": "five_hour", "percent_used": 99},
                         "canary-not-an-object"],
         "other_windows": 2,
         "context": {"tokens": 10, "window": 200000, "percent": 0, "breakdown": {"canary": 1}}}
        """)
        let text = String(decoding: try FrameCodec.payload(f), as: UTF8.self)
        #expect(!text.contains("canary"), "\(text)")
        #expect(f["surface"] == .string("other"))
        #expect(f.lookup(["rate_limits", "five_hour", "used_pct"]) == .value(.number(41.5)), "the first five_hour wins")
        #expect(f.lookup(["rate_limits", "five_hour", "label"]) == .absent)
        // Two stated by the mod, plus the unknown kind, the duplicate and the non-object.
        #expect(f.lookup(["health", "unknown_rate_limit_windows"]) == .value(.number(5)))
        #expect(f.lookup(["health", "unknown_top_level_keys"]) == .value(.number(2)))
    }

    @Test("Bounds: out-of-range numbers are scrubbed by FrameBuilder's rules, a bad reset time drops only itself")
    func bounds() throws {
        let f = try frame("""
        {"v": 1, "surface": "vscode", "session_id": "s",
         "rate_limits": [{"kind": "five_hour", "percent_used": -3, "resets_at": "tomorrow"},
                         {"kind": "seven_day", "percent_used": "70", "resets_at": "2031-01-01T00:00:00Z"}],
         "other_windows": 9999, "context": {"tokens": 1.5, "window": 0, "percent": 1e9}}
        """)
        #expect(f.lookup(["rate_limits", "five_hour", "used_pct"]) == .null)
        #expect(f.lookup(["rate_limits", "five_hour", "resets_at"]) == .absent, "an unparseable time is dropped")
        #expect(f.lookup(["rate_limits", "seven_day"]) == .absent, "a reset beyond now + 400 days drops the window (statusline-shim §6)")
        #expect(f.lookup(["context", "total_input_tokens"]) == .null && f.lookup(["context", "window_size"]) == .null)
        #expect(f.lookup(["context", "used_pct"]) == .null)
        guard case .value(.number(let scrubs)) = f.lookup(["health", "scrub_count"]) else { Issue.record("no scrub count"); return }
        #expect(scrubs >= 6)
    }

    @Test("Resets with and without fractional seconds; a window without one keeps its percent")
    func instants() throws {
        let f = try frame(#"{"v": 1, "surface": "desktop", "rate_limits": [{"kind": "five_hour", "percent_used": 1, "resets_at": "2026-10-19T14:30:00Z"}, {"kind": "seven_day", "percent_used": 2}]}"#)
        #expect(f.lookup(["rate_limits", "five_hour", "resets_at"]) == .value(.number(1_792_420_200)))
        #expect(f.lookup(["rate_limits", "seven_day", "used_pct"]) == .value(.number(2)))
        #expect(f.lookup(["rate_limits", "seven_day", "resets_at"]) == .absent)
        #expect(ModHandoff.parseInstant("2026-10-19T14:30:00.999Z").map { $0.timeIntervalSince1970.rounded(.down) } == 1_792_420_200)
    }

    @Test("Before the first reply: no windows, no fill, still one frame (the session is seen)")
    func empty() throws {
        let f = try frame(#"{"v": 1, "surface": "desktop", "session_id": "s", "rate_limits": [], "other_windows": 0, "context": {"window": 1000000}}"#)
        #expect(f["rate_limits"] == nil)
        #expect(f.lookup(["context", "window_size"]) == .value(.number(1_000_000)))
    }

    @Test("No frame for: too large, not JSON, not an object, too deep, another version")
    func noFrame() {
        #expect(ModHandoff.build(stdin: Data(repeating: 0x20, count: ModHandoff.maxStdinBytes + 1), now: Self.now, shimVersion: "t", hmacKey: nil)
                == .noFrame(.stdinTooLarge))
        #expect(build("not json") == .noFrame(.notJSON))
        #expect(build("[1, 2]") == .noFrame(.notObject))
        #expect(build(#"{"v": 1, "context": {"a": {"b": {"c": {"d": 1}}}}}"#) == .noFrame(.tooDeep))
        #expect(build(#"{"v": 2, "surface": "desktop"}"#) == .noFrame(.unsupportedVersion))
        #expect(build(#"{"surface": "desktop"}"#) == .noFrame(.unsupportedVersion))
    }

    @Test("Without the session key: pool readings only, flagged no_key")
    func noKey() throws {
        guard case .frame(let f) = build(Self.desktop, key: nil) else { Issue.record("expected a frame"); return }
        #expect(f["session_ref"] == nil)
        #expect(f.lookup(["health", "no_key"]) == .value(.bool(true)))
        #expect(f.lookup(["rate_limits", "five_hour", "used_pct"]) == .value(.number(26)))
    }

    @Test("The largest hand-off the mod can produce stays inside the 4 KiB frame")
    func size() throws {
        let windows = (0..<8).map { i in #"{"kind": "\#(["five_hour", "seven_day", "spend_limit"][i % 3])", "percent_used": 100.5, "resets_at": "2026-10-19T14:30:00.000Z"}"# }
        let f = try frame(#"{"v": 1, "surface": "desktop", "session_id": "\#(String(repeating: "a", count: 128))", "version": "\#(String(repeating: "9", count: 32))", "rate_limits": [\#(windows.joined(separator: ","))], "other_windows": 64, "context": {"tokens": 9007199254740991, "window": 100000000, "percent": 1000}}"#)
        #expect(try FrameCodec.payload(f).count <= FrameCodec.maxPayloadBytes)
    }
}
