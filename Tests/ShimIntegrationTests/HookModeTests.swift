import Foundation
import ShimProtocol
import Testing

/// Increment 1.9: the real helper in hook mode. Claude Code hands every hook the whole event, prompt and reply
/// included; only the event name, hashed ids and a built-in agent type may reach the socket, and the helper must
/// never print or fail (exit 2 would block Claude Code; stdout can become context).
@Suite("Hook mode", .serialized)
struct HookModeTests {
    static let markers = ["canary", "/users/", "424242", "sk-ant-"]
    static let fakeToken = "sk-" + "ant-api03-canaryCANARY"

    static func event(_ name: String, agentType: String = "Explore") -> Data {
        Data("""
        {
          "session_id": "canary-session-7f3a",
          "prompt_id": "canary-prompt-id",
          "transcript_path": "/Users/canary/transcript.jsonl",
          "agent_transcript_path": "/Users/canary/subagents/agent.jsonl",
          "cwd": "/Users/canary-cwd",
          "scratchpad_dir": "/private/tmp/canary-scratch",
          "permission_mode": "default",
          "hook_event_name": "\(name)",
          "prompt": "please refactor canary module 424242 \(fakeToken)",
          "last_assistant_message": "Done with canary",
          "stop_hook_active": false,
          "agent_id": "agent-canary-1",
          "agent_type": "\(agentType)",
          "background_tasks": [{"id": "canary-task", "description": "canary description", "command": "rm canary"}],
          "session_crons": [{"id": "c", "prompt": "canary cron prompt"}]
        }
        """.utf8)
    }

    @Test("Each event sends only allowlisted fields, prints nothing and exits 0", arguments: HookFrame.Event.allCases.map(\.rawValue))
    func allowlist(eventName: String) throws {
        let harness = try ShimHarness(); defer { harness.cleanUp() }
        try harness.writeConfig(originalCommand: nil)
        let agent = try FakeAgent(path: harness.socketPath, mode: .readAll); defer { agent.stop() }

        let result = try harness.run(stdin: Self.event(eventName), arguments: ["--hook"])
        #expect(result.status == 0 && result.stdout.isEmpty)
        for _ in 0..<50 where agent.frames.isEmpty { Thread.sleep(forTimeInterval: 0.02) }
        let wire = try #require(agent.frames.first)
        let text = String(decoding: wire, as: UTF8.self).lowercased()
        for marker in Self.markers { #expect(!text.contains(marker), "\(eventName): \(marker) reached the socket") }

        let frame = try FrameCodec.decode(wire)
        let decoded = try #require(HookFrame.decode(frame))
        #expect(decoded.event.rawValue == eventName)
        guard case .object(let members) = frame else { Issue.record("not an object"); return }
        let subagent = eventName.hasPrefix("Subagent")
        let base: Set<String> = ["v", "kind", "emitted_at_ms", "shim_version", "event", "session_ref"]
        let expectedKeys = base.union(subagent ? ["agent_ref", "agent_type"] : [])
        #expect(Set(members.keys) == expectedKeys)
        if subagent { #expect(decoded.agentType == "Explore" && decoded.agentRef?.count == 16) }
    }

    @Test("A custom agent's name never leaves the helper: it arrives as \"custom\"")
    func customType() throws {
        let harness = try ShimHarness(); defer { harness.cleanUp() }
        try harness.writeConfig(originalCommand: nil)
        let agent = try FakeAgent(path: harness.socketPath, mode: .readAll); defer { agent.stop() }
        _ = try harness.run(stdin: Self.event("SubagentStart", agentType: "canary-db-migrator"), arguments: ["--hook"])
        for _ in 0..<50 where agent.frames.isEmpty { Thread.sleep(forTimeInterval: 0.02) }
        let wire = try #require(agent.frames.first)
        #expect(!String(decoding: wire, as: UTF8.self).contains("migrator"))
        #expect(HookFrame.decode(try FrameCodec.decode(wire))?.agentType == "custom")
    }

    /// One SubagentStart through the real helper with `approved` in its config; the wire bytes and the decoded type.
    func sendAgent(_ agentType: String, approved: Any?) throws -> (wire: String, type: String?) {
        let harness = try ShimHarness(); defer { harness.cleanUp() }
        try harness.writeConfig(originalCommand: nil, approvedAgentTypes: approved)
        let agent = try FakeAgent(path: harness.socketPath, mode: .readAll); defer { agent.stop() }
        let result = try harness.run(stdin: Self.event("SubagentStart", agentType: agentType), arguments: ["--hook"])
        #expect(result.status == 0 && result.stdout.isEmpty)
        for _ in 0..<50 where agent.frames.isEmpty { Thread.sleep(forTimeInterval: 0.02) }
        let wire = try #require(agent.frames.first)
        return (String(decoding: wire, as: UTF8.self), HookFrame.decode(try FrameCodec.decode(wire))?.agentType)
    }

    @Test("An approved custom agent arrives by its exact name; an unapproved one, or another case, still arrives as \"custom\"")
    func approvedName() throws {
        let approved = ["code-reviewer", "db-helper"]
        let ok = try sendAgent("code-reviewer", approved: approved)
        #expect(ok.type == "code-reviewer" && ok.wire.contains("\"code-reviewer\""))
        for blocked in ["canary-db-migrator", "Code-Reviewer"] {
            let sent = try sendAgent(blocked, approved: approved)
            #expect(sent.type == "custom")
            #expect(!sent.wire.lowercased().contains("migrator") && !sent.wire.contains("Code-Reviewer"), "\(blocked) reached the socket")
            for marker in Self.markers { #expect(!sent.wire.lowercased().contains(marker)) }
        }
    }

    @Test("A malformed approved list approves nothing and breaks nothing: the frame is still sent, typed \"custom\"")
    func malformedApprovedList() throws {
        for value: Any in ["code-reviewer", 42, ["code-reviewer": true], [1, 2], NSNull()] {
            #expect(try sendAgent("code-reviewer", approved: value).type == "custom", "\(value)")
        }
        // The status line reads the same config: a malformed list must not stop it running the user's command or sending.
        let harness = try ShimHarness(); defer { harness.cleanUp() }
        try harness.writeConfig(originalCommand: "printf 'still here'", approvedAgentTypes: ["oops": 1])
        let agent = try FakeAgent(path: harness.socketPath, mode: .readAll); defer { agent.stop() }
        let result = try harness.run(stdin: f08Stdin)
        #expect(result.text == "still here" && result.status == 0)
        for _ in 0..<50 where agent.frames.isEmpty { Thread.sleep(forTimeInterval: 0.02) }
        #expect(!agent.frames.isEmpty, "the status-line frame was still sent")
    }

    @Test("No app, no config, garbage or a 5 MB prompt: still exit 0, nothing printed")
    func neverFails() throws {
        let harness = try ShimHarness(); defer { harness.cleanUp() }
        #expect(try harness.run(stdin: Self.event("Stop"), arguments: ["--hook"]).status == 0)        // no config
        try harness.writeConfig(originalCommand: nil)
        for input in [Self.event("Stop"), Data("not json".utf8), Data(),
                      Data(#"{"hook_event_name": "UserPromptSubmit", "session_id": "s", "prompt": ""#.utf8) + Data(repeating: 0x61, count: 5 << 20) + Data(#""}"#.utf8)] {
            let result = try harness.run(stdin: input, arguments: ["--hook"])                     // no listener on the socket
            #expect(result.status == 0 && result.stdout.isEmpty)
            #expect(result.seconds < 2)
        }
    }

    @Test("Builder: unknown events and missing keys send nothing; a session is grouped by its HMAC reference")
    func builder() throws {
        let key = Data(repeating: 9, count: 32)
        func build(_ json: String, key: Data? = Data(repeating: 9, count: 32)) -> HookFrame.Outcome {
            HookFrame.build(stdin: Data(json.utf8), now: Date(timeIntervalSince1970: 1_792_159_200), shimVersion: "t", hmacKey: key)
        }
        #expect(build(#"{"hook_event_name": "PreToolUse", "session_id": "s"}"#) == .noFrame(.unknownEvent))
        #expect(build(#"{"hook_event_name": "Stop", "session_id": "s"}"#, key: nil) == .noFrame(.noSession))
        #expect(build(#"{"hook_event_name": "Stop"}"#) == .noFrame(.noSession))
        #expect(build("[1]") == .noFrame(.notObject))
        guard case .frame(let a) = build(#"{"hook_event_name": "Stop", "session_id": "abc"}"#),
              case .frame(let b) = build(#"{"hook_event_name": "UserPromptSubmit", "session_id": "abc"}"#) else {
            Issue.record("expected frames"); return
        }
        #expect(a["session_ref"] == b["session_ref"])
        #expect(a["session_ref"] == .string(FrameBuilder.sessionRef("abc", key: key)))
        #expect(a["agent_ref"] == nil, "only subagent events carry an agent reference")
    }
}
