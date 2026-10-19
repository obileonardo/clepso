import Foundation
import GRDB
import Testing
@testable import Storage

/// Sheet item 9 (founder decision 19 Oct 2026): each session's latest exact report of Claude Code's in-flight
/// background work, kept as counts, and the subagent stops received since it.
@Suite("Agents: background reports")
struct AgentBackgroundTests {
    let t0 = Date(timeIntervalSince1970: 1_792_159_200)
    let s = "aaaaaaaaaaaaaaaa"
    func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }
    func event(_ kind: Store.AgentEvent.Kind, _ seconds: Double, session: String? = nil, agent: String? = nil, type: String? = nil,
               background: Store.BackgroundCounts? = nil) -> Store.AgentEvent {
        .init(kind: kind, sessionRef: session ?? s, agentRef: agent, agentType: type, at: at(seconds), background: background)
    }
    func report(_ agents: [String: Int], shells: Int = 0) -> Store.BackgroundCounts {
        let subagents = agents.values.reduce(0, +)
        var tasks: [String: [String: Int]] = [:]
        if subagents > 0 { tasks["subagent"] = ["running": subagents] }
        if shells > 0 { tasks["shell"] = ["running": shells] }
        return .init(tasks: tasks, agents: agents.mapValues { ["running": $0] })
    }

    @Test("A stop's report is kept, with the stops received since; other work by task type")
    func stopReport() async throws {
        let store = try Store.inMemory(now: t0)
        for e in [event(.promptSubmitted, 0), event(.subagentStarted, 5, agent: "a", type: "general-purpose"),
                  event(.subagentStarted, 6, agent: "b", type: "general-purpose"), event(.subagentStarted, 7, agent: "c", type: "Explore"),
                  event(.subagentStopped, 20, agent: "c", type: "Explore"),
                  event(.stopped, 30, background: report(["general-purpose": 2], shells: 1)),
                  event(.subagentStopped, 90, agent: "a", type: "general-purpose")] { try await store.record(e) }
        let reports = try await store.backgroundSnapshots(since: t0)
        #expect(reports == [Store.BackgroundSnapshot(sessionRef: s, reportedAt: at(30), agentsInFlight: ["general-purpose": 2],
                                                     stoppedSince: ["general-purpose": 1], otherWork: ["shell": 1], sessionLastEvent: at(90))])
    }

    @Test("A subagent's stop during a prompt isn't kept (foreground subagents aren't listed); after the prompt it is")
    func subagentStopReports() async throws {
        let store = try Store.inMemory(now: t0)
        try await store.record(event(.promptSubmitted, 0))
        try await store.record(event(.subagentStarted, 5, agent: "a", type: "Plan"))
        try await store.record(event(.subagentStopped, 10, agent: "a", type: "Plan", background: report([:])))
        #expect(try await store.backgroundSnapshots(since: t0).isEmpty, "a prompt was in progress")
        try await store.record(event(.stopped, 20, background: report(["Explore": 1])))
        // A background subagent finishes after the prompt ended: its own stop still lists it (its stop hook runs before it ends).
        try await store.record(event(.subagentStopped, 60, agent: "x", type: "Explore", background: report(["Explore": 1])))
        let kept = try #require(try await store.backgroundSnapshots(since: t0).first)
        #expect(kept.reportedAt == at(60) && kept.agentsInFlight == ["Explore": 1])
        #expect(kept.stoppedSince == ["Explore": 1], "its own stop, at the report's time, counts as stopped since")
    }

    @Test("Hooks arrive out of order: an older report never replaces a newer one")
    func outOfOrder() async throws {
        let store = try Store.inMemory(now: t0)
        try await store.record(event(.stopped, 50, background: report(["Plan": 1])))
        try await store.record(event(.stopped, 40, background: report(["Explore": 3])))
        #expect(try await store.backgroundSnapshots(since: t0).map(\.agentsInFlight) == [["Plan": 1]])
        try await store.record(event(.stopped, 70, background: report([:])))
        #expect(try await store.backgroundSnapshots(since: t0).map(\.agentsInFlight) == [[:]], "an empty report is kept: nothing in flight")
    }

    @Test("Labels outside the closed sets are dropped before they reach the table")
    func labels() async throws {
        let store = try Store.inMemory(now: t0)
        try await store.record(event(.stopped, 10, background: .init(
            tasks: ["shell": ["running": 1, "finished": 4], "rm -rf /Users/x": ["running": 1], "monitor": ["pending": 2]],
            agents: ["Explore": ["running": 1], "refactor the billing module": ["running": 1], "unknown": ["running": 1], "code-reviewer": ["other": 1]])))
        let kept = try #require(try await store.backgroundSnapshots(since: t0).first)
        #expect(kept.otherWork == ["shell": 1, "monitor": 2])
        #expect(kept.agentsInFlight == ["Explore": 1, "code-reviewer": 1])
        let text = try await store.exportRows().filter { $0.table.hasPrefix("agent_background") }.flatMap(\.rows).flatMap(\.values)
            .map { "\($0)" }.joined()
        #expect(text.contains("monitor"))
        for leak in ["Users", "billing", "finished", "unknown"] { #expect(!text.contains(leak), "\(leak)") }
    }

    @Test("The CHECKs refuse free text and out-of-range counts even when written directly")
    func checks() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator().migrate(queue)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO accounts (id, provider_id, kind, label, created_at) VALUES ('a', 'anthropic', 'personalSubscription', 'This Mac', 1)")
            try db.execute(sql: "INSERT INTO connections (id, account_id, adapter_id, state) VALUES ('c', 'a', 'claude-code.statusline', 'connected')")
            try db.execute(sql: "INSERT INTO agent_background (session_ref, connection_id, reported_at, event) VALUES ('s', 'c', 1, 'Stop')")
            try db.execute(sql: "INSERT INTO agent_background_counts (session_ref, task_type, agent_type, status, count) VALUES ('s', 'subagent', 'code-reviewer', 'running', 2)")
            let bad: [(String, String, String, Int)] = [("cloud session", "", "running", 1), ("shell", "", "done", 1), ("shell", "", "running", 0),
                                                        ("shell", "", "running", 10_000), ("subagent", "two words", "running", 1),
                                                        ("subagent", "path/to", "running", 1), ("subagent", String(repeating: "y", count: 41), "running", 1)]
            for (type, agent, status, count) in bad {
                #expect(throws: (any Error).self, "\(type) \(agent) \(status) \(count)") {
                    try db.execute(sql: "INSERT INTO agent_background_counts (session_ref, task_type, agent_type, status, count) VALUES ('s', ?, ?, ?, ?)",
                                   arguments: [type, agent, status, count])
                }
            }
            #expect(throws: (any Error).self) {
                try db.execute(sql: "INSERT INTO agent_background (session_ref, connection_id, reported_at, event) VALUES ('t', 'c', 1, 'UserPromptSubmit')")
            }
            try db.execute(sql: "DELETE FROM agent_background WHERE session_ref = 's'")
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM agent_background_counts") == 0, "counts go with their report")
        }
    }

    @Test("v4 → v5 adds the two tables and changes nothing else; an existing database is backed up first")
    func migration() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mig5-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("clepso.sqlite")
        let dump = "SELECT task_id || '|' || agent_ref || '|' || agent_type || '|' || started_at FROM agent_runs ORDER BY rowid"
        let before: [String]
        do {
            let queue = try DatabaseQueue(path: url.path)
            try Migrations.migrator().migrate(queue, upTo: "v4_agent_type_approved_names")
            try await queue.write { db in
                try db.execute(sql: "INSERT INTO accounts (id, provider_id, kind, label, created_at) VALUES ('a', 'anthropic', 'personalSubscription', 'This Mac', 1)")
                try db.execute(sql: "INSERT INTO connections (id, account_id, adapter_id, state) VALUES ('c', 'a', 'claude-code.statusline', 'connected')")
                try db.execute(sql: "INSERT INTO agent_tasks (id, connection_id, session_ref, started_at, from_prompt) VALUES ('t', 'c', 's', 1, 1)")
                try db.execute(sql: "INSERT INTO agent_runs (task_id, agent_ref, agent_type, started_at) VALUES ('t', 'r', 'code-reviewer', 1)")
            }
            before = try await queue.read { try String.fetchAll($0, sql: dump) }
        }
        let store = try Store.onDisk(at: url, now: t0)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("clepso.sqlite.pre-v5_agent_background.bak").path))
        #expect(try await store.backgroundSnapshots(since: .distantPast).isEmpty)
        let queue = try DatabaseQueue(path: url.path)
        #expect(try await queue.read { try String.fetchAll($0, sql: dump) } == before)
        #expect(try await queue.read { try Migrations.migrator().appliedIdentifiers($0) }.contains("v5_agent_background"))
    }

    @Test("Taking a name off the list folds its background counts into Custom; retention and export include the tables")
    func forgetRetainExport() async throws {
        let store = try Store.inMemory(now: t0)
        try await store.record(event(.stopped, 10, background: .init(tasks: ["subagent": ["running": 3]],
                                                                    agents: ["code-reviewer": ["running": 2], "custom": ["running": 1]])))
        try await store.forgetAgentName("code-reviewer")
        #expect(try await store.backgroundSnapshots(since: t0).first?.agentsInFlight == ["custom": 3])
        #expect(Store.exportTables.contains("agent_background") && Store.exportTables.contains("agent_background_counts"))
        _ = try await store.purge(now: at(31 * 86_400))
        #expect(try await store.backgroundSnapshots(since: .distantPast).isEmpty, "30 days, like the tasks")
    }
}
