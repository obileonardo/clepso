import Foundation
import Testing
@testable import ShimProtocol

/// Sheet item 9 (founder decision 19 Oct 2026): `Stop` and `SubagentStop` carry Claude Code's in-flight background work
/// (`background_tasks`, Claude Code hooks reference, "Stop input"), and the frame keeps only counts by type and status.
/// Ids, descriptions, commands, MCP server and tool names and workflow names never reach it.
@Suite("Hook frame: background work as counts")
struct HookFrameBackgroundTests {
    static let markers = ["canary", "424242", "/users/", "sk-ant-", "task-0"]
    static let fakeToken = "sk-" + "ant-api03-canaryCANARY"

    /// One background task, every free-text field marked, in the shape the reference documents.
    static func task(_ type: Any?, status: Any? = "running", agentType: String? = nil, n: Int = 0) -> [String: Any] {
        var entry: [String: Any] = ["id": "task-0\(n)-canary", "description": "canary refactor 424242 \(fakeToken) … [+12 chars]",
                                    "command": "rm -rf /Users/canary/project", "server": "canary-mcp", "tool": "canary_tool",
                                    "name": "canary-workflow"]
        if let type { entry["type"] = type }
        if let status { entry["status"] = status }
        if let agentType { entry["agent_type"] = agentType }
        return entry
    }

    func frame(_ event: String, background: Any?, approved: Set<String> = []) throws -> JSONValue {
        var input: [String: Any] = ["hook_event_name": event, "session_id": "s", "agent_id": "a", "agent_type": "Explore",
                                    "last_assistant_message": "canary reply", "session_crons": [["id": "c", "prompt": "canary cron"]]]
        if let background { input["background_tasks"] = background }
        let outcome = HookFrame.build(stdin: try JSONSerialization.data(withJSONObject: input), now: Date(timeIntervalSince1970: 1_792_159_200),
                                      shimVersion: "t", hmacKey: Data(repeating: 9, count: 32), approvedAgentTypes: approved)
        guard case .frame(let frame) = outcome else { Issue.record("no frame: \(outcome)"); return .null }
        return frame
    }

    @Test("Documented types and statuses are counted; anything else is \"other\"; subagents again by type under the approved-names rule")
    func counts() throws {
        let list: [[String: Any]] = [
            Self.task("shell"), Self.task("shell", status: "pending"), Self.task("monitor"), Self.task("workflow"),
            Self.task("teammate"), Self.task("cloud session"), Self.task("MCP task"), Self.task("dream"), Self.task(nil), Self.task(42),
            Self.task("subagent", agentType: "Explore"), Self.task("subagent", agentType: "Explore", n: 1),
            Self.task("subagent", status: "pending", agentType: "code-reviewer"), Self.task("subagent", agentType: "canary-db-migrator"),
            Self.task("subagent", status: "completed", agentType: "Plan"), Self.task("subagent", agentType: ""),
        ]
        let frame = try frame("Stop", background: list, approved: ["code-reviewer"])
        let background = try #require(HookFrame.decode(try FrameCodec.decode(try FrameCodec.encode(frame)))?.background)
        #expect(background.tasks == [.shell: [.running: 1, .pending: 1], .monitor: [.running: 1], .workflow: [.running: 1],
                                     .teammate: [.running: 1], .cloudSession: [.running: 1], .mcpTask: [.running: 1],
                                     .other: [.running: 3], .subagent: [.running: 4, .pending: 1, .other: 1]])
        #expect(background.agents == ["Explore": [.running: 2], "code-reviewer": [.pending: 1], "custom": [.running: 1], "Plan": [.other: 1]],
                "the untyped subagent is counted only among the tasks")
        #expect(background.agentsInFlight == ["Explore": 2, "code-reviewer": 1, "custom": 1, "Plan": 1])
    }

    @Test("No free text from any task reaches the frame: ids, descriptions, commands, servers, tools, names, crons")
    func noFreeText() throws {
        let list = ["shell", "subagent", "monitor", "workflow", "MCP task", "cloud session", "teammate"].enumerated()
            .map { Self.task($0.element, agentType: $0.element == "subagent" ? "canary-agent" : nil, n: $0.offset) }
        for event in ["Stop", "SubagentStop"] {
            let wire = String(decoding: try FrameCodec.encode(try frame(event, background: list)), as: UTF8.self).lowercased()
            for marker in Self.markers + ["migrator", "canary-agent", "rm -rf", "mcp-"] { #expect(!wire.contains(marker), "\(event): \(marker)") }
            #expect(wire.contains("\"background\""))
        }
    }

    @Test("Only Stop and SubagentStop carry it; a missing or malformed list sends none; an empty list is an exact nothing")
    func presence() throws {
        #expect(try frame("UserPromptSubmit", background: [Self.task("shell")])["background"] == nil)
        #expect(try frame("SubagentStart", background: [Self.task("shell")])["background"] == nil)
        #expect(try frame("Stop", background: nil)["background"] == nil, "an older Claude Code, or its registry unreachable")
        #expect(try frame("Stop", background: "shell")["background"] == nil)
        #expect(try frame("Stop", background: ["shell": 1])["background"] == nil)
        let empty = try frame("SubagentStop", background: [Any]())
        #expect(empty["background"] == .object(["tasks": .object([:]), "agents": .object([:])]))
        #expect(HookFrame.decode(empty)?.background == HookFrame.Background())
        // Entries that aren't objects are skipped, not counted.
        #expect(HookFrame.decode(try frame("Stop", background: [1, "x", NSNull(), Self.task("shell")]))?.background?.tasks == [.shell: [.running: 1]])
    }

    @Test("Bounded: counts stop at 9999, at most 16 agent types (the rest fold into custom), and the worst case fits a frame")
    func bounded() throws {
        let shells = (0..<12_000).map { _ in Self.task("shell") }
        #expect(HookFrame.decode(try frame("Stop", background: shells))?.background?.tasks[.shell] == [.running: 9999])

        let approved = Set((0..<50).map { String(format: "agent-name-padded-to-forty-chars-x%06d", $0) })
        #expect(approved.allSatisfy { $0.utf8.count == 40 && HookFrame.isApprovableAgentName($0) })
        var many: [[String: Any]] = []
        for name in approved.sorted() + Array(HookFrame.builtInAgentTypes) + ["unapproved"] {
            for status in ["running", "pending", "weird"] { many += Array(repeating: Self.task("subagent", status: status, agentType: name), count: 3) }
        }
        let folded = try #require(HookFrame.decode(try frame("SubagentStop", background: many, approved: approved))?.background)
        #expect(folded.agents.count == HookFrame.maxBackgroundAgentTypes)
        #expect(folded.agentsInFlight.values.reduce(0, +) == 56 * 9, "folding into custom loses no agent")

        // The largest frame there can be: every task type and status at 9999, sixteen 40-character agent types likewise
        // (2086 bytes on 19 Oct 2026, against the 4096-byte limit).
        let all = Dictionary(uniqueKeysWithValues: HookFrame.Background.Status.allCases.map { ($0, HookFrame.maxBackgroundCount) })
        let worst = HookFrame.Background(tasks: Dictionary(uniqueKeysWithValues: HookFrame.Background.TaskType.allCases.map { ($0, all) }),
                                         agents: Dictionary(uniqueKeysWithValues: approved.sorted().prefix(16).map { ($0, all) }))
        guard case .object(var members) = try frame("SubagentStop", background: [Any]()) else { Issue.record("no frame"); return }
        members["background"] = worst.json
        let wire = try FrameCodec.encode(.object(members))
        #expect(wire.count < FrameCodec.maxPayloadBytes, "\(wire.count) bytes")
        #expect(HookFrame.decode(try FrameCodec.decode(wire))?.background == worst)
    }

    @Test("The app drops a background object out of shape, and keeps the event")
    func decodeGate() throws {
        func decoded(_ background: JSONValue, event: String = "Stop") -> HookFrame.Decoded? {
            HookFrame.decode(.object(["kind": .string(HookFrame.kind), "event": .string(event), "session_ref": .string("0123456789abcdef"),
                                      "emitted_at_ms": .number(1_792_159_200_000), "background": background]))
        }
        func bg(tasks: [String: JSONValue] = [:], agents: [String: JSONValue] = [:]) -> JSONValue {
            .object(["tasks": .object(tasks), "agents": .object(agents)])
        }
        let good = bg(tasks: ["shell": .object(["running": .number(2)])], agents: ["Explore": .object(["pending": .number(1)])])
        #expect(decoded(good)?.background == .init(tasks: [.shell: [.running: 2]], agents: ["Explore": [.pending: 1]]))
        #expect(decoded(good, event: "UserPromptSubmit")?.background == nil, "only stops carry it")
        let bad: [JSONValue] = [
            bg(tasks: ["cloud session": .object(["running": .number(1)])]),         // the label, not the frame's key
            bg(tasks: ["shell": .object(["done": .number(1)])]),
            bg(tasks: ["shell": .object(["running": .number(0)])]),
            bg(tasks: ["shell": .object(["running": .number(10_000)])]),
            bg(tasks: ["shell": .object(["running": .number(1.5)])]),
            bg(tasks: ["shell": .object(["running": .string("1")])]),
            bg(tasks: ["shell": .object([:])]),
            bg(agents: ["refactor the billing module": .object(["running": .number(1)])]),
            bg(agents: ["unknown": .object(["running": .number(1)])]),
            .object(["tasks": .object([:])]),
            .object(["tasks": .object([:]), "agents": .object([:]), "ids": .array([.string("task-01")])]),
            .string("shell"),
        ]
        for value in bad {
            let event = try #require(decoded(value), "the event itself is kept")
            #expect(event.background == nil, "\(value)")
        }
    }
}
