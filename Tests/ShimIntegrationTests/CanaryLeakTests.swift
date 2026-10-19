import Domain
import Foundation
import ClepsoApp
import Testing

/// Increment 1.5 proof ("no allowlist-external field in DB, logs or export"). A payload carrying a marked
/// value in every field Clepso must never keep goes through the real helper binary into the real app model; the
/// database file, the export and the diagnostics log are then searched byte for byte for any marker.
@MainActor
@Suite("Canary: nothing outside the allowlist reaches the database, the log or the export", .serialized)
struct CanaryLeakTests {
    /// Lower-cased markers. Numbers are ones no allowlisted field carries in this payload. Durations and lines of
    /// code are allowlisted since increment 1.7 (A4 amended), so they carry ordinary values and are checked to arrive.
    static let markers = ["canary", "987654321", "424242", "/users/", "@example", "sk-ant-", "akiaz", "ghp_"]

    /// Secret-shaped fakes, assembled at run time so the repository's secret scan has nothing to flag.
    static let fakeToken = "sk-" + "ant-api03-canaryCANARYcanary"
    static let fakeAWS = "AKI" + "AZCANARY0000000000"

    static func payload(nowSeconds: Int64) -> Data {
        Data("""
        {
          "session_id": "CANARY-raw-session-0f9e8d7c",
          "cwd": "/Users/canary-cwd/project",
          "transcript_path": "/Users/canary-transcript/session.jsonl",
          "session_name": "canary-session-name",
          "prompt_id": "canary-prompt-id",
          "scratchpad_dir": "/private/tmp/canary-scratchpad",
          "output_style": {"name": "canary-style"},
          "workspace": {"current_dir": "/Users/canary-ws", "project_dir": "/Users/canary-project", "added_dirs": ["/Users/canary-added"]},
          "vim": {"mode": "canary-vim"},
          "agent": {"name": "canary-agent"},
          "pr": {"url": "https://example.com/canary-pr", "number": 424242},
          "worktree": {"name": "canary-worktree", "path": "/Users/canary-worktree"},
          "hook_event_name": "canary-hook",
          "a_future_key": {"secret": "canary-future", "token": "\(fakeToken)"},
          "version": "2.1.302",
          "model": {"id": "claude-opus-5-5", "display_name": "/Users/canary-model/name"},
          "effort": {"level": "canary-effort"},
          "thinking": {"enabled": true},
          "context_window": {"context_window_size": 1000000, "used_percentage": 41, "remaining_percentage": 59,
                             "total_input_tokens": 410000, "total_output_tokens": 1200,
                             "current_usage": {"input_tokens": 2, "output_tokens": 30, "cache_read_input_tokens": 409000,
                                               "cache_creation_input_tokens": 100, "note": "canary-usage-note"}},
          "rate_limits": {"five_hour": {"used_percentage": 41, "resets_at": \(nowSeconds + 9000), "label": "canary-label"},
                          "seven_day": {"used_percentage": 12, "resets_at": \(nowSeconds + 400_000)},
                          "seven_day_canary": {"used_percentage": 77, "resets_at": \(nowSeconds + 400_000), "name": "canary-window"}},
          "cost": {"total_cost_usd": 0.12, "total_duration_ms": 5271359, "total_api_duration_ms": 2762182,
                   "total_lines_added": 4740, "total_lines_removed": 20, "total_tokens_canary": 987654321},
          "email": "canary@example.com", "aws": "\(fakeAWS)"
        }
        """.utf8)
    }

    @Test("Hostile payload → real helper → app: no marker in clepso.sqlite, the export or diagnostics.jsonl")
    func noCanaryAnywhere() async throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        let model = AppModel(environment: AppEnvironment(
            dataDirectory: h.home.appendingPathComponent("d"), home: h.home, shimPath: ShimHarness.shimURL.path,
            loginItem: NoLoginItem(), notifications: NoNotifications(), keychain: NoKeychain(), appVersion: "0.1.0-test"))
        await model.start(); defer { model.stop() }

        // The helper's config points at the app's socket; the session key is the installer's kind of file.
        let keyPath = h.home.appendingPathComponent(".claude/clepso/session.key")
        try Data((0..<32).map { _ in UInt8.random(in: 0...255) }).write(to: keyPath)
        let config: [String: Any] = ["v": 1, "socket": model.environment.socketPath, "forward_cost": true,
                                     "hmac_key_file": keyPath.path, "original_command": NSNull()]
        try JSONSerialization.data(withJSONObject: config).write(to: h.home.appendingPathComponent(".claude/clepso/config.json"))

        let result = try h.run(stdin: Self.payload(nowSeconds: ShimHarness.fixtureNowMs / 1000))
        #expect(result.status == 0)
        let deadline = Date().addingTimeInterval(5)
        while model.snapshot.provider?.pools.first?.model.used.value != 41, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.snapshot.provider?.pools.first?.model.used.value == 41, "the allowlisted reading did arrive")

        let export = h.home.appendingPathComponent("export.json")
        guard case .success = await model.export(to: export) else { Issue.record("export failed"); return }
        let places: [(String, URL)] = [("database", model.environment.databaseURL), ("export", export),
                                       ("diagnostics log", model.environment.diagnosticsURL)]
        for (name, url) in places {
            let bytes = String(decoding: try Data(contentsOf: url), as: UTF8.self).lowercased()
            #expect(!bytes.isEmpty, "\(name) exists")
            for marker in Self.markers {
                #expect(!bytes.contains(marker), "\(name) contains \(marker)")
            }
            #expect(!bytes.contains("canary-raw-session".lowercased()), "\(name) contains the raw session id")
        }
        // The fields allowlisted in 1.7 do arrive (so the test above is not passing by dropping everything).
        let db = String(decoding: try Data(contentsOf: model.environment.databaseURL), as: UTF8.self)
        for value in ["5271359", "2762182", "4740"] { #expect(db.contains(value), "allowlisted value \(value) stored") }
        // The helper's own status line went to Claude Code, not to Clepso; it must not echo markers either.
        #expect(!result.text.lowercased().contains("canary"), "\(result.text)")
    }

    /// One hook event as Claude Code sends it, content fields marked.
    static func hookEvent(_ name: String, agent: String? = nil, type: String? = nil) -> Data {
        var event: [String: Any] = ["session_id": "CANARY-raw-session-0f9e8d7c", "hook_event_name": name,
                                    "transcript_path": "/Users/canary-transcript/session.jsonl", "cwd": "/Users/canary-cwd",
                                    "prompt": "refactor canary module 424242 \(fakeToken)", "last_assistant_message": "canary reply",
                                    "agent_transcript_path": "/Users/canary/agent.jsonl"]
        if let agent { event["agent_id"] = agent }
        if let type { event["agent_type"] = type }
        return (try? JSONSerialization.data(withJSONObject: event)) ?? Data()
    }

    @Test("Hook events → real helper → app: an unapproved custom agent's name is in no database, export or log; an approved one is kept exactly")
    func hookCanary() async throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        let model = AppModel(environment: AppEnvironment(
            dataDirectory: h.home.appendingPathComponent("d"), home: h.home, shimPath: ShimHarness.shimURL.path,
            loginItem: NoLoginItem(), notifications: NoNotifications(), keychain: NoKeychain(), appVersion: "0.1.0-test"))
        await model.start(); defer { model.stop() }
        #expect(await model.approveAgentName("code-reviewer") == .added)

        // The helper's config as the installer writes it, with the approved list.
        let keyPath = h.home.appendingPathComponent(".claude/clepso/session.key")
        try Data((0..<32).map { _ in UInt8.random(in: 0...255) }).write(to: keyPath)
        let config: [String: Any] = ["v": 1, "socket": model.environment.socketPath, "forward_cost": true, "hmac_key_file": keyPath.path,
                                     "original_command": NSNull(), "approved_agent_types": ["code-reviewer"]]
        try JSONSerialization.data(withJSONObject: config).write(to: h.home.appendingPathComponent(".claude/clepso/config.json"))

        for event in [Self.hookEvent("UserPromptSubmit"),
                      Self.hookEvent("SubagentStart", agent: "agent-canary-1", type: "canary-db-migrator"),
                      Self.hookEvent("SubagentStart", agent: "agent-canary-2", type: "code-reviewer"),
                      Self.hookEvent("SubagentStart", agent: "agent-canary-3", type: "Code-Reviewer"),
                      Self.hookEvent("SubagentStop", agent: "agent-canary-1", type: "canary-db-migrator"),
                      Self.hookEvent("Stop")] {
            let result = try h.run(stdin: event, arguments: ["--hook"])
            #expect(result.status == 0 && result.stdout.isEmpty)
        }

        let export = h.home.appendingPathComponent("hook-export.json")
        var exported = ""
        let deadline = Date().addingTimeInterval(5)
        repeat {
            try await Task.sleep(for: .milliseconds(50))
            guard case .success = await model.export(to: export) else { continue }
            exported = String(decoding: try Data(contentsOf: export), as: UTF8.self)
        } while !(exported.contains("\"code-reviewer\"") && exported.components(separatedBy: "\"custom\"").count == 3) && Date() < deadline
        #expect(exported.contains("\"code-reviewer\""), "the approved name arrived exactly")
        #expect(exported.components(separatedBy: "\"custom\"").count == 3, "the unapproved name and the other case arrived as custom")

        let database = model.environment.databaseURL
        let places: [(String, URL)] = [("database", database), ("database WAL", URL(fileURLWithPath: database.path + "-wal")),
                                       ("export", export), ("diagnostics log", model.environment.diagnosticsURL)]
        for (name, url) in places {
            guard let data = try? Data(contentsOf: url) else { continue }
            let bytes = String(decoding: data, as: UTF8.self)
            for marker in Self.markers + ["migrator"] { #expect(!bytes.lowercased().contains(marker), "\(name) contains \(marker)") }
            #expect(!bytes.contains("Code-Reviewer"), "\(name) contains the unapproved spelling")
        }
    }
}

struct NoLoginItem: LoginItemControlling {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}

struct NoNotifications: NotificationAuthorizing {
    func status() async -> NotificationAuthorization { .notDetermined }
    func request() async -> NotificationAuthorization { .notDetermined }
    func sendTest(title: String, body: String) async {}
    func removeAll() async {}
}

struct NoKeychain: KeychainCleaning {
    func deleteAll() {}
}
