import ClaudeCodeAdapter
import ClepsoApp
import Domain
import Foundation
import ShimProtocol
import Testing
import TestFixtures

/// v0.3 (docs/specs/mod-bridge.md): the real helper in mod mode (`clepso-statusline --mod`), fed what Clepso's Claude
/// Code mod hands it. The 19 Oct desktop-app records replay into readings; nothing outside the hand-off's allowlist
/// reaches the socket, the database, the export or the log; and the helper never prints or fails.
@Suite("Mod mode", .serialized)
struct ModModeTests {
    static let markers = ["canary", "/users/", "424242", "sk-ant-"]
    static let fakeToken = "sk-" + "ant-api03-canaryCANARY"

    /// The three desktop measurements of 19 Oct 2026, as the mod would hand them over (fixture `mod/spike-19oct-desktop.json`).
    static var spike: [Data] {
        get throws {
            let url = Fixtures.claudeCodeRoot.appendingPathComponent("mod/spike-19oct-desktop.json")
            let doc = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let measures = try #require(doc["measures"] as? [[String: Any]])
            return try measures.map { try JSONSerialization.data(withJSONObject: try #require($0["handoff"])) }
        }
    }

    /// A hand-off with a marker in every place a careless helper might copy from.
    static let hostile = Data("""
    {"v": 1, "surface": "/Users/canary-surface", "session_id": "canary-session-7f3a \(fakeToken)", "version": "2.1.299",
     "prompt": "please refactor canary module 424242", "cwd": "/Users/canary-cwd", "transcript_path": "/Users/canary/t.jsonl",
     "rate_limits": [{"kind": "five_hour", "percent_used": 26, "resets_at": "2026-10-19T14:30:00.000Z", "label": "canary-label"},
                     {"kind": "canary_window_424242", "percent_used": 12},
                     {"kind": "seven_day", "percent_used": 70, "resets_at": "2026-10-22T04:00:00.000Z", "note": "\(fakeToken)"}],
     "other_windows": 0,
     "context": {"tokens": 88744, "window": 1000000, "percent": 9, "breakdown": {"canary": "/Users/canary-file"}}}
    """.utf8)

    @Test("The 19 Oct desktop records → real helper: three frames with the recorded numbers, marked via mod")
    func spikeReplay() throws {
        let harness = try ShimHarness(); defer { harness.cleanUp() }
        try harness.writeConfig(originalCommand: nil)
        let agent = try FakeAgent(path: harness.socketPath, mode: .readAll); defer { agent.stop() }
        for handoff in try Self.spike {
            let result = try harness.run(stdin: handoff, arguments: ["--mod"])
            #expect(result.status == 0 && result.stdout.isEmpty)
        }
        for _ in 0..<100 where agent.frames.count < 3 { Thread.sleep(forTimeInterval: 0.02) }
        let frames = try agent.frames.map { try FrameCodec.decode($0) }
        #expect(frames.count == 3)
        let fiveHour = frames.compactMap { f -> Double? in
            if case .value(.number(let n)) = f.lookup(["rate_limits", "five_hour", "used_pct"]) { return n }
            return nil
        }
        #expect(fiveHour == [26, 26, 27])
        for f in frames {
            #expect(f["via"] == .string("mod") && f["surface"] == .string("desktop"))
            #expect(f.lookup(["rate_limits", "seven_day", "used_pct"]) == .value(.number(70)))
            #expect(f["source_version"] == .string("2.1.299"))
        }
        // Mapped as the app maps them: pool readings on the mod channel, session context on the session.
        let batch = try #require(FrameMapper.map(frames[2], connectionID: UUID(), receivedAt: Date(timeIntervalSince1970: 1_792_159_201)))
        #expect(batch.observations.allSatisfy { $0.channel == .mod })
        #expect(batch.observations.contains { $0.subject == .pool(providerPoolKey: "claude-code.rate_limits.five_hour") && $0.value == .percent(27) })
        #expect(batch.observations.contains { $0.kind == .contextTokens && $0.value == .tokens(104_902) })
    }

    @Test("A hostile hand-off: no marker reaches the socket, and the numbers still do")
    func allowlist() throws {
        let harness = try ShimHarness(); defer { harness.cleanUp() }
        try harness.writeConfig(originalCommand: nil)
        let agent = try FakeAgent(path: harness.socketPath, mode: .readAll); defer { agent.stop() }
        let result = try harness.run(stdin: Self.hostile, arguments: ["--mod"])
        #expect(result.status == 0 && result.stdout.isEmpty)
        for _ in 0..<50 where agent.frames.isEmpty { Thread.sleep(forTimeInterval: 0.02) }
        let wire = try #require(agent.frames.first)
        let text = String(decoding: wire, as: UTF8.self).lowercased()
        for marker in Self.markers { #expect(!text.contains(marker), "\(marker) reached the socket") }
        let frame = try FrameCodec.decode(wire)
        #expect(frame.lookup(["rate_limits", "five_hour", "used_pct"]) == .value(.number(26)))
        #expect(frame["surface"] == .string("other"))
        #expect(frame.lookup(["health", "unknown_rate_limit_windows"]) == .value(.number(1)))
    }

    @Test("No app, no config, garbage, an old or future hand-off, 5 MB: still exit 0, nothing printed, quickly")
    func neverFails() throws {
        let harness = try ShimHarness(); defer { harness.cleanUp() }
        #expect(try harness.run(stdin: Self.hostile, arguments: ["--mod"]).status == 0)        // no config yet
        try harness.writeConfig(originalCommand: nil)
        for input in [Self.hostile, Data("not json".utf8), Data(), Data(#"{"v": 2}"#.utf8),
                      Data(#"{"v": 1, "pad": ""#.utf8) + Data(repeating: 0x61, count: 5 << 20) + Data(#""}"#.utf8)] {
            let result = try harness.run(stdin: input, arguments: ["--mod"])                     // no listener on the socket
            #expect(result.status == 0 && result.stdout.isEmpty)
            #expect(result.seconds < 2)
        }
    }

    @Test("The mod's command runs the hand-off script Clepso writes, and exits 0 silently when it's missing")
    func modCommand() throws {
        let harness = try ShimHarness(); defer { harness.cleanUp() }
        try harness.writeConfig(originalCommand: nil)
        let agent = try FakeAgent(path: harness.socketPath, mode: .readAll); defer { agent.stop() }
        // The exact command string from the mod's source, run the way $.process.run runs it (argv, no extra shell).
        let source = try String(contentsOf: Self.repo.appendingPathComponent("mod/claude-code/plugins/clepso-limits/hooks/handoff.js"), encoding: .utf8)
        let line = try #require(source.components(separatedBy: "\n").first { $0.contains("mod-handoff.sh") && $0.hasPrefix("  '") })
        let command = String(line.trimmingCharacters(in: .whitespaces).dropFirst().dropLast())
        func run() throws -> (Int32, String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.environment = ["HOME": harness.home.path, "PATH": "/usr/bin:/bin", "CLEPSO_SHIM_NOW_MS": String(ShimHarness.fixtureNowMs),
                                   "CLEPSO_SHIM_RELAXED_BUDGET": "1"]
            let out = Pipe(), input = Pipe()
            process.standardOutput = out
            process.standardError = out
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(try Self.spike[0])
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        #expect(try run() == (0, ""), "no script yet: nothing happens")
        #expect(agent.frames.isEmpty)
        let script = harness.home.appendingPathComponent(".claude/clepso/mod-handoff.sh")
        try Data("#!/bin/sh\nexec '\(ShimHarness.shimURL.path)' --mod\n".utf8).write(to: script)
        chmod(script.path, 0o700)
        #expect(try run() == (0, ""))
        for _ in 0..<50 where agent.frames.isEmpty { Thread.sleep(forTimeInterval: 0.02) }
        #expect(try agent.frames.first.map { try FrameCodec.decode($0)["via"] } == .string("mod"))
    }

    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

/// The mod path end to end into the app: markers are in no database, export or log, and the reading arrives on the mod
/// channel (the ledger's `metadata_json`).
@MainActor
@Suite("Canary: the mod's hand-off", .serialized)
struct ModCanaryTests {
    @Test("Hostile hand-off → real helper → app: no marker in clepso.sqlite, the export or diagnostics.jsonl")
    func noCanaryAnywhere() async throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        let model = AppModel(environment: AppEnvironment(
            dataDirectory: h.home.appendingPathComponent("d"), home: h.home, shimPath: ShimHarness.shimURL.path,
            loginItem: NoLoginItem(), notifications: NoNotifications(), keychain: NoKeychain(), appVersion: "0.3.0-test"))
        await model.start(); defer { model.stop() }

        let keyPath = h.home.appendingPathComponent(".claude/clepso/session.key")
        try Data((0..<32).map { _ in UInt8.random(in: 0...255) }).write(to: keyPath)
        let config: [String: Any] = ["v": 1, "socket": model.environment.socketPath, "forward_cost": true,
                                     "hmac_key_file": keyPath.path, "original_command": NSNull()]
        try JSONSerialization.data(withJSONObject: config).write(to: h.home.appendingPathComponent(".claude/clepso/config.json"))

        #expect(try h.run(stdin: ModModeTests.hostile, arguments: ["--mod"]).status == 0)
        let deadline = Date().addingTimeInterval(5)
        while model.snapshot.provider?.pools.first?.model.used.value != 26, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.snapshot.provider?.pools.contains { $0.model.used.value == 26 } == true, "the allowlisted reading did arrive")

        let export = h.home.appendingPathComponent("export.json")
        guard case .success = await model.export(to: export) else { Issue.record("export failed"); return }
        for (name, url) in [("database", model.environment.databaseURL), ("export", export), ("diagnostics log", model.environment.diagnosticsURL)] {
            let bytes = String(decoding: try Data(contentsOf: url), as: UTF8.self).lowercased()
            #expect(!bytes.isEmpty, "\(name) exists")
            for marker in ModModeTests.markers { #expect(!bytes.contains(marker), "\(name) contains \(marker)") }
        }
        let db = String(decoding: try Data(contentsOf: model.environment.databaseURL), as: UTF8.self)
        #expect(db.contains(#"{"channel":"mod"}"#), "stored on the mod channel")
    }
}
