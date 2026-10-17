import Foundation
import Testing
@testable import ShimProtocol

// SYNTHETIC inputs from FIXTURES (F06, F08). Clock: 2026-10-16T14:00:00Z.
let fixtureNow = Date(timeIntervalSince1970: 1_792_159_200)
let testKey = Data(repeating: 7, count: 32)

let f06Stdin = """
{"cwd":"/fixture/home/projects/sample-app","session_id":"fixture-f06-session-0001",
 "transcript_path":"/fixture/home/.claude/projects/sample-app/transcript.jsonl",
 "model":{"id":"claude-opus-5-5","display_name":"Opus"},
 "workspace":{"current_dir":"/fixture/home/projects/sample-app","project_dir":"/fixture/home/projects/sample-app","added_dirs":[]},
 "version":"2.1.301","output_style":{"name":"default"},
 "cost":{"total_cost_usd":0.0412,"total_duration_ms":180000,"total_api_duration_ms":9000,"total_lines_added":12,"total_lines_removed":3},
 "context_window":{"total_input_tokens":68000,"total_output_tokens":2100,"context_window_size":200000,"used_percentage":34,
   "remaining_percentage":66,"current_usage":{"input_tokens":12000,"output_tokens":2100,"cache_creation_input_tokens":6000,"cache_read_input_tokens":50000}},
 "exceeds_200k_tokens":false,
 "prompt_cache":{"warm":true,"caching_observed":true,"ttl":"5m","expires_at":1792159500,"requests":3,"misses":0,"expected_rebuilds":0,
   "hit_ratio":0.73,"cache_write_tokens":6000,"miss_recache_tokens":0,"last_miss_at":null,"last_miss_cause":null,"miss_causes":{},"recache_tokens_if_cold":18000},
 "effort":{"level":"high"}}
"""

let f08SessionAStdin = """
{"cwd":"/fixture/home/projects/app-one","session_id":"fixture-f08-session-a",
 "transcript_path":"/fixture/home/.claude/projects/app-one/transcript.jsonl",
 "model":{"id":"claude-opus-5-5","display_name":"Opus"},"version":"2.1.301",
 "context_window":{"total_input_tokens":82000,"total_output_tokens":6100,"context_window_size":200000,"used_percentage":41,"remaining_percentage":59,
   "current_usage":{"input_tokens":9000,"output_tokens":6100,"cache_creation_input_tokens":3000,"cache_read_input_tokens":70000}},
 "exceeds_200k_tokens":false,"effort":{"level":"high"},"cost":{"total_cost_usd":1.9},
 "rate_limits":{"five_hour":{"used_percentage":80,"resets_at":1792167300},"seven_day":{"used_percentage":20,"resets_at":1792330800}}}
"""

func build(_ stdin: String, forwardCost: Bool = true, key: Data? = testKey) -> FrameBuilder.Outcome {
    FrameBuilder.build(stdin: Data(stdin.utf8), now: fixtureNow,
                       options: .init(shimVersion: "0.1.0", forwardCost: forwardCost, hmacKey: key, originalPresent: true))
}

func frame(_ stdin: String, forwardCost: Bool = true, key: Data? = testKey) throws -> JSONValue {
    guard case .frame(let f) = build(stdin, forwardCost: forwardCost, key: key) else {
        Issue.record("expected a frame")
        throw CancellationError()
    }
    return f
}

func payloadText(_ f: JSONValue) throws -> String {
    String(decoding: try FrameCodec.payload(f), as: UTF8.self)
}

@Suite("Frame v1 from status-line stdin")
struct FrameBuilderTests {
    @Test("F06: absent rate_limits stays absent, never 0")
    func f06AbsentRateLimits() throws {
        let f = try frame(f06Stdin)
        #expect(f.lookup(["rate_limits"]) == .absent)
        #expect(f.lookup(["context", "used_pct"]) == .value(.number(34)))
        #expect(f.lookup(["context", "remaining_pct"]) == .value(.number(66)))
        #expect(f.lookup(["model", "display_name"]) == .value(.string("Opus")))
        #expect(f.lookup(["source_version"]) == .value(.string("2.1.301")))
        #expect(f.lookup(["session", "effort_level"]) == .value(.string("high")))
        #expect(f.lookup(["prompt_cache", "hit_ratio"]) == .value(.number(0.73)))
        #expect(f.lookup(["health", "scrub_count"]) == .value(.number(0)))
        #expect(f.lookup(["health", "unknown_top_level_keys"]) == .value(.number(0)))
        #expect(f.lookup(["health", "unknown_rate_limit_windows"]) == .value(.number(0)), "no rate_limits at all counts 0")
    }

    @Test("An unknown rate-limit window is counted, never copied or named")
    func unknownRateLimitWindow() throws {
        let stdin = f08SessionAStdin.replacingOccurrences(
            of: #""seven_day":{"used_percentage":20,"resets_at":1792330800}}"#,
            with: #""seven_day":{"used_percentage":20,"resets_at":1792330800},"seven_day_fable":{"used_percentage":36,"resets_at":1792330800}}"#)
        #expect(stdin != f08SessionAStdin)
        let f = try frame(stdin)
        #expect(f.lookup(["health", "unknown_rate_limit_windows"]) == .value(.number(1)))
        #expect(f.lookup(["rate_limits", "seven_day", "used_pct"]) == .value(.number(20)))
        let text = try payloadText(f)
        #expect(!text.contains("fable") && !text.contains("36"), "\(text)")
        #expect(try frame(f08SessionAStdin).lookup(["health", "unknown_rate_limit_windows"]) == .value(.number(0)))
    }

    @Test("Never-forward fields and raw session id do not appear anywhere in the frame bytes")
    func neverForward() throws {
        let text = try payloadText(try frame(f06Stdin))
        for forbidden in ["/fixture", "sample-app", "transcript", "cwd", "workspace", "output_style",
                          "fixture-f06-session-0001", "total_lines_added", "total_duration_ms",
                          "miss_causes", "recache_tokens_if_cold", "cache_write_tokens"] {
            #expect(!text.contains(forbidden), "frame leaked \(forbidden)")
        }
    }

    @Test("Session id becomes a 16-hex-character HMAC reference")
    func sessionRef() throws {
        let f = try frame(f06Stdin)
        guard case .value(.string(let ref)) = f.lookup(["session_ref"]) else {
            Issue.record("no session_ref"); return
        }
        #expect(ref.count == 16)
        #expect(ref.allSatisfy { $0.isHexDigit })
        #expect(ref == FrameBuilder.sessionRef("fixture-f06-session-0001", key: testKey))
        #expect(ref != FrameBuilder.sessionRef("fixture-f06-session-0001", key: Data(repeating: 8, count: 32)))
    }

    @Test("Without the key file, no session_ref and health.no_key is set")
    func noKey() throws {
        let f = try frame(f06Stdin, key: nil)
        #expect(f.lookup(["session_ref"]) == .absent)
        #expect(f.lookup(["health", "no_key"]) == .value(.bool(true)))
    }

    @Test("Cost estimate is forwarded by default (A5) and omitted when the user turns it off")
    func costEstimate() throws {
        #expect(try frame(f06Stdin).lookup(["cost_usd_estimate"]) == .value(.number(0.0412)))
        #expect(try frame(f06Stdin, forwardCost: false).lookup(["cost_usd_estimate"]) == .absent)
    }

    @Test("F08: both windows copied with epoch-second reset times; spend_limit absent")
    func f08Windows() throws {
        let f = try frame(f08SessionAStdin)
        #expect(f.lookup(["rate_limits", "five_hour", "used_pct"]) == .value(.number(80)))
        #expect(f.lookup(["rate_limits", "five_hour", "resets_at"]) == .value(.number(1_792_167_300)))
        #expect(f.lookup(["rate_limits", "seven_day", "used_pct"]) == .value(.number(20)))
        #expect(f.lookup(["rate_limits", "spend_limit"]) == .absent)
        #expect(try payloadText(f).contains("\"resets_at\":1792167300"), "epoch seconds must encode as an integer")
        #expect(try FrameCodec.payload(f).count < FrameCodec.maxPayloadBytes)
    }

    @Test("A provider null stays null; a missing key stays absent")
    func nullVersusAbsent() throws {
        let f = try frame(#"{"session_id":"s","context_window":{"used_percentage":null,"current_usage":null,"context_window_size":200000}}"#)
        #expect(f.lookup(["context", "used_pct"]) == .null)
        #expect(f.lookup(["context", "current_usage"]) == .null)
        #expect(f.lookup(["context", "remaining_pct"]) == .absent)
        #expect(f.lookup(["context", "window_size"]) == .value(.number(200_000)))
    }

    @Test("Wrong types, negatives and path-like strings become null and are counted")
    func hostileFields() throws {
        let f = try frame(#"""
        {"model":{"id":"claude-opus-5-5","display_name":"/Users/someone/Opus"},
         "context_window":{"used_percentage":"high","total_input_tokens":-5,"context_window_size":1.5},
         "effort":{"level":"turbo"},"exceeds_200k_tokens":"no"}
        """#)
        #expect(f.lookup(["model", "id"]) == .value(.string("claude-opus-5-5")))
        #expect(f.lookup(["model", "display_name"]) == .null)
        #expect(f.lookup(["context", "used_pct"]) == .null)
        #expect(f.lookup(["context", "total_input_tokens"]) == .null)
        #expect(f.lookup(["context", "window_size"]) == .null)
        #expect(f.lookup(["session", "effort_level"]) == .null)
        #expect(f.lookup(["context", "exceeds_200k"]) == .null)
        #expect(f.lookup(["health", "scrub_count"]) == .value(.number(6)))
        #expect(!(try payloadText(f).contains("someone")))
    }

    @Test("A window whose resets_at fails the transport bound is dropped whole")
    func implausibleWindow() throws {
        let farFuture = Int(fixtureNow.timeIntervalSince1970) + 500 * 86_400
        let f = try frame(#"{"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":\#(farFuture)},"seven_day":{"used_percentage":10,"resets_at":1792330800}}}"#)
        #expect(f.lookup(["rate_limits", "five_hour"]) == .absent)
        #expect(f.lookup(["rate_limits", "seven_day", "used_pct"]) == .value(.number(10)))
        #expect(f.lookup(["health", "scrub_count"]) == .value(.number(1)))
    }

    @Test("Unknown top-level keys are counted, never copied or named")
    func unknownKeys() throws {
        let f = try frame(#"{"session_id":"s","hook_event_name":"Status","future_field":{"x":1}}"#)
        #expect(f.lookup(["health", "unknown_top_level_keys"]) == .value(.number(2)))
        let text = try payloadText(f)
        #expect(!text.contains("hook_event_name") && !text.contains("future_field"))
    }

    @Test("No frame for non-objects, garbage, excessive depth or oversized stdin")
    func noFrame() {
        #expect(build("[1,2,3]") == .noFrame(.notObject))
        #expect(build("not json\u{0}") == .noFrame(.notJSON))
        #expect(build(#"{"a":{"b":{"c":{"d":{"e":1}}}}}"#) == .noFrame(.tooDeep))
        if case .noFrame = build(#"{"a":{"b":{"c":{"d":1}}}}"#) { Issue.record("depth 4 must be accepted") }
        let big = "{\"pad\":\"" + String(repeating: "x", count: FrameBuilder.maxParsedStdinBytes) + "\"}"
        #expect(build(big) == .noFrame(.stdinTooLarge))
    }
}

@Suite("Frame codec")
struct FrameCodecTests {
    @Test("Round trip with a big-endian length prefix")
    func roundTrip() throws {
        let f = try frame(f08SessionAStdin)
        let wire = try FrameCodec.encode(f)
        let declared = wire.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        #expect(declared == wire.count - 4)
        #expect(try FrameCodec.decode(wire) == f)
    }

    @Test("Decoder rejects oversize, mismatched, wrong-version and wrong-kind frames")
    func rejects() throws {
        #expect(throws: FrameCodec.DecodeError.truncatedPrefix) { try FrameCodec.decode(Data([0, 0])) }
        #expect(throws: FrameCodec.DecodeError.oversize) { try FrameCodec.decode(Data([0, 0, 0x10, 0x01]) + Data(count: 4097)) }
        #expect(throws: FrameCodec.DecodeError.lengthMismatch) { try FrameCodec.decode(Data([0, 0, 0, 9]) + Data("{}".utf8)) }
        let wrongVersion = try FrameCodec.encode(.object(["v": .number(2), "kind": .string(FrameBuilder.kind)]))
        #expect(throws: FrameCodec.DecodeError.wrongVersion) { try FrameCodec.decode(wrongVersion) }
        let wrongKind = try FrameCodec.encode(.object(["v": .number(1), "kind": .string("other")]))
        #expect(throws: FrameCodec.DecodeError.wrongKind) { try FrameCodec.decode(wrongKind) }
        let huge = JSONValue.object(["pad": .string(String(repeating: "x", count: 5000))])
        #expect(throws: FrameCodec.DecodeError.oversize) { try FrameCodec.encode(huge) }
    }
}

@Suite("String scrubber")
struct ScrubberTests {
    @Test("Model names pass; paths, emails and secret shapes are dropped",
          arguments: [
            ("claude-opus-5-5", true), ("Opus", true), ("task-runner", true),
            ("claude-3-5-sonnet-20241022-extended-thinking", true),
            ("sk-ant-api03-abc", false), ("sk-live", false), ("x sk-abc", false), ("user@example", false),  // secret-scan: allow (synthetic scrubber input)
            ("/Users/someone", false), ("a\\b", false), ("$HOME", false), ("Bearer abc", false),
            ("AKIAABCDEFGHIJKLMNOP", false), (String(repeating: "A1b2", count: 10), false),  // secret-scan: allow (synthetic scrubber input)
            ("tab\there", false), (String(repeating: "m", count: 65), false),
          ])
    func scrub(input: String, accepted: Bool) {
        #expect(Scrubber.isAcceptable(input, maxLength: 64) == accepted)
    }
}
