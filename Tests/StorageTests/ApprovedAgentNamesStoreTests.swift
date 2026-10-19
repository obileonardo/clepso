import Foundation
import GRDB
import Testing
@testable import Storage

/// Approved agent names (founder decision 19 Oct 2026): `agent_runs.agent_type` may hold a custom agent's name the user
/// approved, never free text; taking a name off the list turns its stored runs into Custom.
@Suite("Approved agent names in the store")
struct ApprovedAgentNamesStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_792_159_200)

    func started(_ agent: String, _ type: String?, at seconds: Double = 5) -> Store.AgentEvent {
        .init(kind: .subagentStarted, sessionRef: "aaaaaaaaaaaaaaaa", agentRef: agent, agentType: type, at: t0.addingTimeInterval(seconds))
    }

    @Test("An approved name is kept exactly; anything not shaped like an agent name is stored as unknown, never as text")
    func keepsOnlyNameShapes() async throws {
        let store = try Store.inMemory(now: t0)
        try await store.record(.init(kind: .promptSubmitted, sessionRef: "aaaaaaaaaaaaaaaa", agentRef: nil, agentType: nil, at: t0))
        for (i, type) in ["code-reviewer", "db_migrator2", "Custom", "please review /Users/x", "a.b", String(repeating: "x", count: 41), ""].enumerated() {
            try await store.record(started("a\(i)", type))
        }
        let task = try #require(try await store.agentTasks(limit: 1).first)
        #expect(task.byType == ["code-reviewer": 1, "db_migrator2": 1, "unknown": 5])
    }

    @Test("The table's CHECK refuses free text even when written directly")
    func checkConstraint() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator().migrate(queue)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO accounts (id, provider_id, kind, label, created_at) VALUES ('a', 'anthropic', 'personalSubscription', 'This Mac', 1)")
            try db.execute(sql: "INSERT INTO connections (id, account_id, adapter_id, state) VALUES ('c', 'a', 'claude-code.statusline', 'connected')")
            try db.execute(sql: "INSERT INTO agent_tasks (id, connection_id, session_ref, started_at, from_prompt) VALUES ('t', 'c', 's', 1, 1)")
            try db.execute(sql: "INSERT INTO agent_runs (task_id, agent_ref, agent_type, started_at) VALUES ('t', 'r1', 'code-reviewer', 1)")
            for (i, bad) in ["two words", "path/to", "dot.name", String(repeating: "y", count: 41), "", "naïve"].enumerated() {
                #expect(throws: (any Error).self, "\(bad)") {
                    try db.execute(sql: "INSERT INTO agent_runs (task_id, agent_ref, agent_type, started_at) VALUES ('t', ?, ?, 1)", arguments: ["b\(i)", bad])
                }
            }
        }
    }

    @Test("v3 → v4 keeps every run unchanged")
    func migrationKeepsRows() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator().migrate(queue, upTo: "v3_agent_tasks")
        let dump = "SELECT rowid || '|' || task_id || '|' || agent_ref || '|' || agent_type || '|' || started_at || '|' || IFNULL(stopped_at, '-') FROM agent_runs ORDER BY rowid"
        try queue.write { db in
            try db.execute(sql: "INSERT INTO accounts (id, provider_id, kind, label, created_at) VALUES ('a', 'anthropic', 'personalSubscription', 'This Mac', 1)")
            try db.execute(sql: "INSERT INTO connections (id, account_id, adapter_id, state) VALUES ('c', 'a', 'claude-code.statusline', 'connected')")
            try db.execute(sql: "INSERT INTO agent_tasks (id, connection_id, session_ref, started_at, from_prompt) VALUES ('t', 'c', 's', 1, 1)")
            for (i, type) in ["Explore", "custom", "unknown", "Plan"].enumerated() {
                try db.execute(sql: "INSERT INTO agent_runs (task_id, agent_ref, agent_type, started_at, stopped_at) VALUES ('t', ?, ?, ?, ?)",
                               arguments: ["r\(i)", type, 10 + i, i % 2 == 0 ? 20 + i : nil])
            }
            #expect(throws: (any Error).self, "v3 refuses a name") {
                try db.execute(sql: "INSERT INTO agent_runs (task_id, agent_ref, agent_type, started_at) VALUES ('t', 'x', 'code-reviewer', 1)")
            }
        }
        let before = try queue.read { try String.fetchAll($0, sql: dump) }
        try Migrations.migrator().migrate(queue)
        #expect(try queue.read { try String.fetchAll($0, sql: dump) } == before)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO agent_runs (task_id, agent_ref, agent_type, started_at) VALUES ('t', 'x', 'code-reviewer', 1)")
            try db.execute(sql: "DELETE FROM agent_tasks WHERE id = 't'")             // the cascade still holds after the rebuild
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM agent_runs") == 0)
        }
    }

    @Test("Forgetting a name turns its runs into Custom and leaves every other type alone")
    func forget() async throws {
        let store = try Store.inMemory(now: t0)
        try await store.record(.init(kind: .promptSubmitted, sessionRef: "aaaaaaaaaaaaaaaa", agentRef: nil, agentType: nil, at: t0))
        for (i, type) in ["code-reviewer", "code-reviewer", "db-migrator", "Explore", "custom"].enumerated() { try await store.record(started("a\(i)", type)) }
        #expect(try await store.forgetAgentName("code-reviewer") == 2)
        #expect(try await store.forgetAgentName("Explore") == 0, "built-in types are never relabelled")
        #expect(try await store.forgetAgentName("unknown") == 0)
        let task = try #require(try await store.agentTasks(limit: 1).first)
        #expect(task.byType == ["custom": 3, "db-migrator": 1, "Explore": 1])
    }
}
