@testable import CodexAdapter
import Foundation
import Testing

/// Item 4: agents per task for Codex. Synthetic rollout files in the shape Codex writes (surveyed 18 Oct 2026 on the
/// founder's Mac, key names and counts only): one file per thread, `session_meta` first, turns attributed by
/// `root_turn_id`. Instructions, paths, nicknames, prompts and replies carry canaries; none may come back out.
struct CodexAgentsTests {
    static let canary = "CANARY-7f3a /Users/someone/secret-project"
    static let roleCanary = "canary_role_7f3a"

    enum Kind { case main, spawned(role: String?, from: Int), guardian(from: Int) }

    static func at(_ minute: Int) -> String { String(format: "2026-10-16T10:%02d:00.000Z", minute) }

    static func meta(_ kind: Kind) -> String {
        let source: String, thread: String, start: String
        switch kind {
        case .main:
            (source, thread, start) = (#""vscode""#, "user", "")
        case .spawned(let role, let from):
            let r = role.map { "\"\($0)\"" } ?? "null"
            source = #"{"subagent":{"thread_spawn":{"parent_thread_id":"p","depth":1,"agent_path":"/root/\#(canary)","agent_nickname":"\#(canary)","agent_role":\#(r)}}}"#
            (thread, start) = ("subagent", #","subagent_history_start_ordinal":\#(from)"#)
        case .guardian(let from):
            (source, thread, start) = (#"{"subagent":{"other":"guardian"}}"#, "guardian_review", #","subagent_history_start_ordinal":\#(from)"#)
        }
        // Instructions first, with the keys Clepso looks for written inside the text (escaped, as JSON requires).
        return #"{"timestamp":"\#(at(0))","ordinal":0,"type":"session_meta","payload":{"base_instructions":{"text":"\#(canary) \"agent_role\":\"explorer\" \"thread_spawn\":{}"},"id":"t","cwd":"\#(canary)","git":{"branch":"\#(canary)"},"source":\#(source),"thread_source":"\#(thread)"\#(start)}}"#
    }

    static func started(_ ordinal: Int, _ minute: Int, turn: String, parent: String? = nil, root: String? = nil,
                        trigger: String = "user") -> String {
        let p = parent.map { "\"\($0)\"" } ?? "null", r = root ?? turn
        return #"{"timestamp":"\#(at(minute))","ordinal":\#(ordinal),"type":"event_msg","payload":{"type":"task_started","turn_attribution":{"initiating_agent_path":"/root/\#(canary)","parent_turn_id":\#(p),"root_turn_id":"\#(r)","turn_id":"\#(turn)","turn_trigger":"\#(trigger)"},"turn_id":"\#(turn)","root_turn_id":"\#(r)","started_at":1792144800,"model_context_window":258400,"collaboration_mode_kind":"default"}}"#
    }

    static func complete(_ ordinal: Int, _ minute: Int, turn: String, root: String? = nil) -> String {
        #"{"timestamp":"\#(at(minute))","ordinal":\#(ordinal),"type":"event_msg","payload":{"type":"task_complete","root_turn_id":"\#(root ?? turn)","turn_id":"\#(turn)","last_agent_message":"\#(canary) done","started_at":1792144800,"completed_at":1792145400,"duration_ms":600000}}"#
    }

    static func aborted(_ ordinal: Int, _ minute: Int, turn: String) -> String {
        #"{"timestamp":"\#(at(minute))","ordinal":\#(ordinal),"type":"event_msg","payload":{"type":"turn_aborted","root_turn_id":"\#(turn)","turn_id":"\#(turn)","reason":"interrupted","started_at":1792144800,"completed_at":1792145400,"duration_ms":1}}"#
    }

    /// A prompt that quotes an event line: escaped inside the string, so it must never count.
    static func prompt(_ ordinal: Int) -> String {
        #"{"timestamp":"\#(at(1))","ordinal":\#(ordinal),"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"\#(canary) {\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"fake\",\"parent_turn_id\":null}}"}]}}"#
    }

    func home(_ files: [String: [String]]) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-agents-\(UUID().uuidString)")
        for (name, lines) in files { try write(lines, to: url(home, name)) }
        return home
    }
    func url(_ home: URL, _ name: String) -> URL {
        CodexReader.sessionsURL(home: home).appendingPathComponent("2026/10/16/rollout-\(name).jsonl")
    }
    func write(_ lines: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
    func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }
    func scan(_ home: URL, into usage: inout CodexUsage) -> [CodexAgents.Task] {
        usage.scan(home: home)
        return usage.agents.tasks
    }
    func date(_ minute: Int) -> Date { CodexRollout.timestamp(Self.at(minute))! }

    /// The founder's case: a thread with two prompts; the first spawns two agents, the second one more; an auto-reviewer
    /// checks commands in both. One sub-agent is reused in the second task (it still counts once, for the first) and
    /// spawns a nested agent there, whose file starts with a copy of its parent's history.
    @Test func twoTasksWithSpawnedNestedAndReviewers() throws {
        let home = try home([
            "main": [Self.meta(.main), Self.prompt(1), Self.started(2, 0, turn: "T1"), Self.complete(3, 10, turn: "T1"),
                     Self.prompt(4), Self.started(5, 20, turn: "T2")],
            "a": [Self.meta(.spawned(role: nil, from: 3)), Self.meta(.main), Self.started(2, 0, turn: "T1"),       // parent's copy
                  Self.started(3, 1, turn: "a1", parent: "T1", root: "T1"), Self.complete(4, 5, turn: "a1", root: "T1"),
                  Self.started(5, 21, turn: "a2", parent: "T2", root: "T2"), Self.complete(6, 23, turn: "a2", root: "T2")],
            "b": [Self.meta(.spawned(role: "explorer", from: 1)), Self.started(1, 2, turn: "b1", parent: "T1", root: "T1")],
            // Nested: spawned by `a` during T2; its copy of `a`'s history includes a turn for T1, which isn't its own.
            "d": [Self.meta(.spawned(role: Self.roleCanary, from: 3)), Self.started(1, 1, turn: "a1", parent: "T1", root: "T1"),
                  Self.complete(2, 5, turn: "a1", root: "T1"),
                  Self.started(3, 22, turn: "d1", parent: "a2", root: "T2"), Self.complete(4, 24, turn: "d1", root: "T2")],
            "g": [Self.meta(.guardian(from: 1)),
                  Self.started(1, 3, turn: "g1", parent: "T1", root: "T1", trigger: "guardian_review"), Self.complete(2, 3, turn: "g1", root: "T1"),
                  Self.started(3, 4, turn: "g2", parent: "T1", root: "T1", trigger: "guardian_review"), Self.complete(4, 4, turn: "g2", root: "T1"),
                  Self.started(5, 22, turn: "g3", parent: "T2", root: "T2", trigger: "guardian_review")],
        ])
        defer { try? FileManager.default.removeItem(at: home) }
        var usage = CodexUsage(zone: TimeZone(identifier: "UTC")!)
        let tasks = scan(home, into: &usage)
        #expect(tasks.map(\.id) == ["T2", "T1"])
        let t2 = tasks[0], t1 = tasks[1]
        #expect(t1.fromPrompt && t1.startedAt == date(0) && t1.endedAt == date(10))
        #expect(t1.byRole == ["default": 1, "explorer": 1] && t1.finished == 1 && t1.reviews == 2)
        #expect(t2.fromPrompt && t2.startedAt == date(20) && t2.endedAt == nil, "Codex hasn't finished the second prompt")
        #expect(t2.byRole == ["custom": 1] && t2.finished == 1 && t2.reviews == 1, "the nested agent, its own role unread")
    }

    @Test func aSubAgentWhoseUserTurnIsMissingStillMakesATask() throws {
        let home = try home(["e": [Self.meta(.spawned(role: "worker", from: 1)), Self.started(1, 30, turn: "e1", parent: "T9", root: "T9"),
                                   Self.complete(2, 35, turn: "e1", root: "T9")]])
        defer { try? FileManager.default.removeItem(at: home) }
        var usage = CodexUsage(zone: TimeZone(identifier: "UTC")!)
        let task = try #require(scan(home, into: &usage).first)
        #expect(task.id == "T9" && !task.fromPrompt && task.startedAt == date(30) && task.endedAt == date(35))
        #expect(task.byRole == ["worker": 1] && task.finished == 1)
    }

    @Test func aTurnEndsWhenAbortedOrWhenTheNextOneStarts() throws {
        let home = try home(["main": [Self.meta(.main), Self.started(1, 0, turn: "T1"), Self.started(2, 5, turn: "T2"),
                                      Self.aborted(3, 7, turn: "T2"), Self.started(4, 9, turn: "T3")]])
        defer { try? FileManager.default.removeItem(at: home) }
        var usage = CodexUsage(zone: TimeZone(identifier: "UTC")!)
        let tasks = scan(home, into: &usage)
        #expect(tasks.map(\.id) == ["T3", "T2", "T1"])
        #expect(tasks.map(\.endedAt) == [nil, date(7), date(5)])
        #expect(tasks.allSatisfy { $0.agents == 0 && $0.reviews == 0 })
    }

    @Test func appendedLinesAreReadOnceAndHalfLinesWait() throws {
        let home = try home(["main": [Self.meta(.main), Self.started(1, 0, turn: "T1")],
                             "a": [Self.meta(.spawned(role: nil, from: 1))]])
        defer { try? FileManager.default.removeItem(at: home) }
        var usage = CodexUsage(zone: TimeZone(identifier: "UTC")!)
        #expect(scan(home, into: &usage).map(\.agents) == [0])
        let next = Self.started(1, 1, turn: "a1", parent: "T1", root: "T1")
        try append(String(next.prefix(60)), to: url(home, "a"))                         // Codex mid-write
        #expect(scan(home, into: &usage).map(\.agents) == [0])
        try append(String(next.dropFirst(60)) + "\n", to: url(home, "a"))
        var task = try #require(scan(home, into: &usage).first)
        #expect(task.agents == 1 && task.finished == 0 && task.endedAt == nil)
        try append(Self.complete(2, 4, turn: "a1", root: "T1") + "\n", to: url(home, "a"))
        try append(Self.complete(2, 6, turn: "T1") + "\n", to: url(home, "main"))
        _ = scan(home, into: &usage)
        task = try #require(scan(home, into: &usage).first)                              // nothing new: nothing twice
        #expect(task.agents == 1 && task.finished == 1 && task.endedAt == date(6))
    }

    @Test func aRewrittenFileIsReadAgainFromTheStart() throws {
        let home = try home(["main": [Self.meta(.main), Self.started(1, 0, turn: "T1"), Self.complete(2, 3, turn: "T1"),
                                      Self.started(3, 4, turn: "T2")]])
        defer { try? FileManager.default.removeItem(at: home) }
        var usage = CodexUsage(zone: TimeZone(identifier: "UTC")!)
        #expect(scan(home, into: &usage).count == 2)
        try write([Self.meta(.main), Self.started(1, 8, turn: "T5")], to: url(home, "main"))
        #expect(scan(home, into: &usage).map(\.id) == ["T5"])
    }

    /// Nothing from instructions, paths, nicknames, prompts or replies is kept, in the tasks or anywhere in the state.
    @Test func canariesNeverComeOut() throws {
        let home = try home([
            "main": [Self.meta(.main), Self.prompt(1), Self.started(2, 0, turn: "T1"), Self.complete(3, 10, turn: "T1")],
            "b": [Self.meta(.spawned(role: Self.roleCanary, from: 1)), Self.prompt(1), Self.started(2, 2, turn: "b1", parent: "T1", root: "T1")],
        ])
        defer { try? FileManager.default.removeItem(at: home) }
        var usage = CodexUsage(zone: TimeZone(identifier: "UTC")!)
        let tasks = scan(home, into: &usage)
        #expect(tasks.map(\.id) == ["T1"], "the quoted event inside the prompt isn't a turn")
        let everything = String(reflecting: tasks) + String(reflecting: usage)
        for leak in ["CANARY", "secret-project", "/Users", Self.roleCanary, "fake", "/root"] {
            #expect(!everything.contains(leak), "\(leak) leaked")
        }
        #expect(tasks.first?.byRole == ["custom": 1])
    }

    @Test func byteLookupsReadOnlyShortPlainValues() {
        let line = Data(#"{"a":"plain-1.2_x:Z+","b":"has \"quote\"","c":null,"d":1234,"e":{"x":1},"f":"\#(String(repeating: "x", count: 65))","g":""}"#.utf8)
        func key(_ k: String) -> [UInt8] { Array("\"\(k)\":".utf8) }
        func scalar(_ k: String) -> CodexBytes.Scalar? { line.withUnsafeBytes { CodexBytes.scalar(key(k), in: $0, limit: line.count) } }
        #expect(scalar("a") == .string("plain-1.2_x:Z+"))
        #expect(scalar("b") == nil)
        #expect(scalar("c") == .null)
        #expect(scalar("d") == .int(1234))
        #expect(scalar("e") == nil)
        #expect(scalar("f") == nil)
        #expect(scalar("g") == nil)
        #expect(scalar("quote") == nil, "escaped text is never a key")
        #expect(line.withUnsafeBytes { CodexBytes.find(key("d"), in: $0, limit: 20) } == nil, "beyond the limit")
    }
}
