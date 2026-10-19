import Darwin
import Foundation
import Testing
import ShimProtocol
import ClaudeCodeAdapter
import Domain

// SYNTHETIC payload from FIXTURES F08 session A. The harness pins the helper's clock
// to the fixture date (debug builds only), so the fixed reset times never age out of the transport bound.
let f08Stdin = Data(#"""
{"cwd":"/fixture/home/projects/app-one","session_id":"fixture-f08-session-a",
 "transcript_path":"/fixture/home/.claude/projects/app-one/transcript.jsonl",
 "model":{"id":"claude-opus-5-5","display_name":"Opus"},"version":"2.1.301",
 "context_window":{"total_input_tokens":82000,"total_output_tokens":6100,"context_window_size":200000,"used_percentage":41,
   "remaining_percentage":59,"current_usage":{"input_tokens":9000,"output_tokens":6100,"cache_creation_input_tokens":3000,"cache_read_input_tokens":70000}},
 "exceeds_200k_tokens":false,"effort":{"level":"high"},"cost":{"total_cost_usd":1.9},
 "rate_limits":{"five_hour":{"used_percentage":80,"resets_at":1792167300},"seven_day":{"used_percentage":20,"resets_at":1792330800}}}
"""#.utf8)

/// Each test owns its temporary HOME; `.serialized` keeps process-heavy tests from skewing timings.
@Suite("clepso-statusline as a real process", .serialized)
struct ShimIntegrationTests {
    @Test("The user's command receives the exact stdin bytes and its output is passed through unchanged")
    func passthroughIsByteIdentical() throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        try h.writeConfig(originalCommand: "cat")
        let result = try h.run(stdin: f08Stdin)
        #expect(result.stdout == f08Stdin)
        #expect(result.status == 0)
    }

    @Test("The user's command's exit status is forwarded")
    func exitStatusForwarded() throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        try h.writeConfig(originalCommand: "printf 'mine'; exit 3")
        let result = try h.run(stdin: f08Stdin)
        #expect(result.text == "mine")
        #expect(result.status == 3)
    }

    @Test("A frame reaches the agent: allowlisted, hashed, no paths")
    func frameDelivered() throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        try h.writeConfig(originalCommand: "cat >/dev/null")
        let agent = try FakeAgent(path: h.socketPath, mode: .readAll); defer { agent.stop() }
        _ = try h.run(stdin: f08Stdin)
        try waitUntil { !agent.frames.isEmpty }
        let wire = try #require(agent.frames.first)
        let frame = try FrameCodec.decode(wire)
        #expect(frame.lookup(["rate_limits", "five_hour", "used_pct"]) == .value(.number(80)))
        #expect(frame.lookup(["source_version"]) == .value(.string("2.1.301")))
        #expect(frame.lookup(["cost_usd_estimate"]) == .value(.number(1.9)))
        #expect(frame.lookup(["health", "original_present"]) == .value(.bool(true)))
        guard case .value(.string(let ref)) = frame.lookup(["session_ref"]) else { Issue.record("no session_ref"); return }
        #expect(ref.count == 16)
        let text = String(decoding: wire, as: UTF8.self)
        #expect(!text.contains("/fixture") && !text.contains("fixture-f08-session-a") && !text.contains("transcript"))
    }

    @Test("With the app absent, the status line still prints and exits 0")
    func appAbsent() throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        try h.writeConfig(originalCommand: "printf 'still here'")
        let result = try h.run(stdin: f08Stdin)
        #expect(result.text == "still here")
        #expect(result.status == 0)
    }

    @Test("A listener that accepts and never reads cannot stall the status line")
    func hungAgent() throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        try h.writeConfig(originalCommand: "printf 'ok'")
        let agent = try FakeAgent(path: h.socketPath, mode: .acceptAndHang); defer { agent.stop() }
        let result = try h.run(stdin: f08Stdin, realBudget: true)
        #expect(result.text == "ok")
        #expect(result.seconds < 1.0)
    }

    @Test("A socket path that is a symlink is not followed")
    func symlinkSocketRefused() throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        try h.writeConfig(originalCommand: "cat >/dev/null")
        let realPath = h.home.appendingPathComponent("r.sock").path
        let agent = try FakeAgent(path: realPath, mode: .readAll); defer { agent.stop() }
        try FileManager.default.createSymbolicLink(atPath: h.socketPath, withDestinationPath: realPath)
        _ = try h.run(stdin: f08Stdin)
        Thread.sleep(forTimeInterval: 0.2)
        #expect(agent.frames.isEmpty)
    }

    @Test("Without its config the helper prints nothing and exits 0")
    func noConfig() throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        let result = try h.run(stdin: f08Stdin)
        #expect(result.stdout.isEmpty)
        #expect(result.status == 0)
    }

    @Test("With no original status line, the helper prints its own one-line summary")
    func ownLine() throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        try h.writeConfig(originalCommand: nil)
        let result = try h.run(stdin: f08Stdin)
        #expect(result.text == "[Opus] · ctx 41% · 5h 80% · 7d 20%\n")
        #expect(result.status == 0)
    }

    @Test("stdin above 1 MiB reaches the user's command truncated, and no frame is sent")
    func hugeStdin() throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        try h.writeConfig(originalCommand: "wc -c")
        let agent = try FakeAgent(path: h.socketPath, mode: .readAll); defer { agent.stop() }
        let result = try h.run(stdin: Data(repeating: UInt8(ascii: "x"), count: 3 << 20))
        #expect(result.text.trimmingCharacters(in: .whitespacesAndNewlines) == "1048576")
        #expect(result.status == 0)
        Thread.sleep(forTimeInterval: 0.2)
        #expect(agent.frames.isEmpty)
    }

    @Test("SIGTERM is forwarded to the user's command and the helper exits 143")
    func sigtermForwarded() throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        try h.writeConfig(originalCommand: "sleep 5")
        let result = try h.run(stdin: f08Stdin) { process in
            Thread.sleep(forTimeInterval: 0.15)
            kill(process.processIdentifier, SIGTERM)
        }
        #expect(result.status == 143)
        #expect(result.seconds < 2.0)
    }
}

func waitUntil(timeout: Double = 2, _ condition: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { Issue.record("condition not met within \(timeout)s"); return }
        Thread.sleep(forTimeInterval: 0.01)
    }
}

/// ARCHITECTURE §3 budget: shim-added overhead ≤ 20 ms p95, ≤ 50 ms max, measured against a `/bin/sh -c` baseline.
/// Opt-in because it times 1,260 launches: `make perf` (`CLEPSO_PERF=1 swift test -c release --filter Overhead`).
///
/// Each round runs the baseline, the helper with the app absent and the helper with the app present once, in a shuffled
/// order, and the overhead is each helper run minus its own round's baseline. Pairing is what makes the number mean
/// something on a busy Mac: load that comes and goes over seconds hits both halves of a pair, so it cancels instead of
/// landing on whichever path happened to run during it (comparing the p95s of separately timed loops went negative).
/// A stall inside a helper run still counts against the helper, so the estimate errs high, never low.
/// The ≤ 50 ms max is reported, not asserted: on a shared Mac any launch, the baseline's included, now and then stalls
/// for ~70 ms; inside the helper the frame path is cut off at 48 ms by construction (§3).
@Suite("Overhead budget", .serialized, .enabled(if: ProcessInfo.processInfo.environment["CLEPSO_PERF"] == "1"))
struct OverheadTests {
    static let rounds = 200
    static let warmUpRounds = 10                       // first launches pay for cold caches; not timed
    static let p95BudgetMs = 20.0

    @Test("200 paired rounds: baseline, app absent, app present")
    func overhead() throws {
        // The helper drops a frame it could not build within 10 ms of starting (§3 step 3).
        try Self.measure(name: "status line", stdin: f08Stdin, arguments: [], originalCommand: "cat >/dev/null", dropDeadlineMs: 10)
    }

    /// Hook mode (sheet item 9 added the background counts): a `Stop` with 40 in-flight background tasks, against the
    /// same baseline. The helper runs async in Claude Code, but the budget is the same.
    @Test("200 paired hook-mode rounds: baseline, app absent, app present")
    func hookOverhead() throws {
        let tasks = (0..<40).map { i -> [String: Any] in
            ["id": "task-\(i)", "type": ["shell", "subagent", "monitor", "MCP task"][i % 4], "status": i % 5 == 0 ? "pending" : "running",
             "description": String(repeating: "d", count: 1000), "command": String(repeating: "c", count: 1000), "agent_type": "general-purpose"]
        }
        let event: [String: Any] = ["session_id": "perf-session", "hook_event_name": "Stop", "transcript_path": "/tmp/t.jsonl", "cwd": "/tmp",
                                    "last_assistant_message": String(repeating: "r", count: 20_000), "stop_hook_active": false,
                                    "background_tasks": tasks, "session_crons": []]
        // Hook mode has no parse deadline: it drops a frame only when connecting takes longer than 20 ms.
        try Self.measure(name: "hook", stdin: try JSONSerialization.data(withJSONObject: event), arguments: ["--hook"],
                         originalCommand: nil, dropDeadlineMs: 20)
    }

    /// `dropDeadlineMs`: the shortest real-time deadline whose miss makes the helper drop its frame. A run faster than
    /// that cannot have missed it, so a frame lost by such a run is a delivery bug, not the by-design gap under load.
    static func measure(name: String, stdin: Data, arguments: [String], originalCommand: String?, dropDeadlineMs: Double) throws {
        // Two homes with the same config: one's socket path is never bound (the app is not running), the other's has a
        // listener for the whole test, so absent and present runs can alternate.
        let absentHome = try ShimHarness(); defer { absentHome.cleanUp() }
        let presentHome = try ShimHarness(); defer { presentHome.cleanUp() }
        try absentHome.writeConfig(originalCommand: originalCommand)
        try presentHome.writeConfig(originalCommand: originalCommand)
        let agent = try FakeAgent(path: presentHome.socketPath, mode: .readAll); defer { agent.stop() }
        let shell = URL(fileURLWithPath: "/bin/sh")

        var baseline: [Double] = [], absent: [Double] = [], present: [Double] = [], droppedMs: [Double] = []
        for round in 0..<(warmUpRounds + rounds) {
            var times = [0.0, 0.0, 0.0]
            for path in [0, 1, 2].shuffled() {
                switch path {
                case 0: times[0] = try absentHome.run(stdin: stdin, executable: shell, arguments: ["-c", "cat >/dev/null"]).seconds
                case 1: times[1] = try absentHome.run(stdin: stdin, arguments: arguments, realBudget: true).seconds
                default:
                    let before = agent.frames.count
                    times[2] = try presentHome.run(stdin: stdin, arguments: arguments, realBudget: true).seconds
                    // The agent reads on its own thread, after the helper has exited: wait for it instead of racing it.
                    if !agent.waitForFrames(before + 1, timeout: 1), round >= warmUpRounds { droppedMs.append(times[2] * 1000) }
                }
            }
            guard round >= warmUpRounds else { continue }
            baseline.append(times[0]); absent.append(times[1]); present.append(times[2])
        }

        var load = [0.0, 0.0, 0.0]
        getloadavg(&load, 3)
        print(String(format: "OVERHEAD %@ rounds=%d stdin=%d bytes, load %.1f %.1f %.1f", name, rounds, stdin.count, load[0], load[1], load[2]))
        let rows = [("\(name) baseline (/bin/sh -c)", baseline), ("\(name) helper, app absent", absent), ("\(name) helper, app present", present)]
        for (label, seconds) in rows {
            let ms = seconds.map { $0 * 1000 }
            print(String(format: "OVERHEAD %-36@ p50 %6.2f ms  p95 %6.2f ms  max %6.2f ms", label as NSString,
                         quantile(ms, 0.5), quantile(ms, 0.95), quantile(ms, 1)))
        }
        // When the baseline alone spreads by more than the budget, the Mac is too busy for any verdict on the helper.
        let baselineMs = baseline.map { $0 * 1000 }
        let spread = quantile(baselineMs, 0.95) - quantile(baselineMs, 0.5)
        let busy = spread > p95BudgetMs
            ? String(format: "; the baseline alone spreads %.1f ms (p50 to p95, load %.1f): too busy to measure, rerun on a quiet Mac", spread, load[0]) : ""
        for (label, seconds) in rows.dropFirst() {
            let added = zip(seconds, baseline).map { ($0 - $1) * 1000 }
            let p95 = quantile(added, 0.95)
            print(String(format: "OVERHEAD %@: added p50 %.2f  p95 %.2f  max %.2f ms (paired); %d of %d rounds over 50 ms", label,
                         quantile(added, 0.5), p95, quantile(added, 1), added.filter { $0 > 50 }.count, rounds))
            #expect(p95 <= p95BudgetMs, "\(label): paired p95 overhead \(p95) ms exceeds \(p95BudgetMs) ms\(busy)")
        }

        // Under the real budget a frame may be dropped (an honest gap, §3 step 4), but only by a run slow enough to have
        // missed a deadline, and rarely: more than 1% means the frame path no longer fits its budget on this Mac.
        let droppedBy = droppedMs.isEmpty ? "" : "; dropped by runs of " + droppedMs.map { String(format: "%.1f ms", $0) }.joined(separator: ", ")
        print("OVERHEAD \(name): frames delivered \(rounds - droppedMs.count) of \(rounds)\(droppedBy)")
        #expect(droppedMs.allSatisfy { $0 >= dropDeadlineMs }, "\(name): a run under \(dropDeadlineMs) ms dropped its frame: \(droppedMs)")
        #expect(droppedMs.count <= rounds / 100, "\(name): \(droppedMs.count) of \(rounds) app-present runs dropped their frame")
    }

    /// Nearest-rank quantile; `q == 1` is the maximum.
    static func quantile(_ values: [Double], _ q: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * q))]
    }
}

@Suite("End to end: installer, wrapper, helper", .serialized)
struct EndToEndTests {
    @Test("Installed wrapper runs the real helper: the user's line prints, a frame arrives, uninstall restores bytes")
    func installRunUninstall() throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        let settings = h.home.appendingPathComponent(".claude/settings.json")
        let original = Data("{\n  \"statusLine\": {\n    \"type\": \"command\",\n    \"command\": \"printf 'mine'\"\n  }\n}\n".utf8)
        try original.write(to: settings)
        // The harness pre-creates ~/.claude/clepso; the installer must start from a clean slate.
        try FileManager.default.removeItem(at: h.home.appendingPathComponent(".claude/clepso"))

        let installer = SettingsInstaller(paths: .init(home: h.home), shimPath: ShimHarness.shimURL.path,
                                          socketPath: h.socketPath)
        _ = try installer.install()
        let agent = try FakeAgent(path: h.socketPath, mode: .readAll); defer { agent.stop() }

        let wrapper = h.home.appendingPathComponent(".claude/clepso/statusline.sh")
        let result = try h.run(stdin: f08Stdin, executable: URL(fileURLWithPath: "/bin/sh"), arguments: [wrapper.path])
        #expect(result.text == "mine")
        #expect(result.status == 0)
        try waitUntil { !agent.frames.isEmpty }
        let frame = try FrameCodec.decode(try #require(agent.frames.first))
        #expect(frame.lookup(["rate_limits", "five_hour", "used_pct"]) == .value(.number(80)))
        #expect(frame.lookup(["health", "original_present"]) == .value(.bool(true)))

        #expect(try installer.uninstall() == .restoredExactly)
        #expect(try Data(contentsOf: settings) == original)
    }
}

/// Collects batches handed over by the Ingestor.
final class BatchCollector: IngestSink, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [IngestBatch] = []
    func ingest(_ batch: IngestBatch) async { lock.withLock { stored.append(batch) } }
    var batches: [IngestBatch] { lock.withLock { stored } }
}

@Suite("End to end: real helper into the app's IngestSocket", .serialized)
struct HelperToIngestTests {
    @Test("Two concurrent sessions reach the app as two batches on the same pools (F08 shape)")
    func helperToIngestor() async throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        try h.writeConfig(originalCommand: nil)
        let socket = try IngestSocket(path: h.socketPath)
        let collector = BatchCollector()
        let ingestor = Ingestor(connectionID: UUID(), sink: collector)
        socket.start()
        let task = Task { await ingestor.consume(socket.frames) }

        let sessionB = Data(String(decoding: f08Stdin, as: UTF8.self)
            .replacingOccurrences(of: "fixture-f08-session-a", with: "fixture-f08-session-b")
            .replacingOccurrences(of: "\"used_percentage\":80", with: "\"used_percentage\":83").utf8)
        _ = try h.run(stdin: f08Stdin)
        _ = try h.run(stdin: sessionB, nowMs: ShimHarness.fixtureNowMs + 30_000)
        try waitUntil { collector.batches.count == 2 }
        socket.stop()
        await task.value

        let fiveHour = SubjectKey.pool(providerPoolKey: "claude-code.rate_limits.five_hour")
        let used = collector.batches.flatMap { $0.observations }.filter { $0.subject == fiveHour && $0.kind == .quotaUsedPct }.map(\.value)
        #expect(used == [.percent(80), .percent(83)], "same pool key from both sessions, never summed")
        let refs = Set(collector.batches.compactMap(\.sessionRef))
        #expect(refs.count == 2, "two distinct hashed session references")
        #expect(socket.currentHealth.accepted == 2 && socket.currentHealth.rejectedFrame == 0)
    }
}
