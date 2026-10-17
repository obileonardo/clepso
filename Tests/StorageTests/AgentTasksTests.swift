import Foundation
import GRDB
import Testing
@testable import Storage

/// Increment 1.9: hook events become tasks (one per prompt) with their subagent runs.
@Suite("Agents per task")
struct AgentTasksTests {
    let t0 = Date(timeIntervalSince1970: 1_792_159_200)
    func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }
    func event(_ kind: Store.AgentEvent.Kind, _ seconds: Double, session: String = "aaaaaaaaaaaaaaaa", agent: String? = nil,
               type: String? = nil) -> Store.AgentEvent {
        .init(kind: kind, sessionRef: session, agentRef: agent, agentType: type, at: at(seconds))
    }

    @Test("A prompt's subagents are counted by type, finished ones too, and Claude stopping ends the task")
    func oneTask() async throws {
        let store = try Store.inMemory(now: t0)
        for e in [event(.promptSubmitted, 0), event(.subagentStarted, 5, agent: "a1", type: "Explore"),
                  event(.subagentStarted, 6, agent: "a2", type: "Plan"), event(.subagentStarted, 7, agent: "a3", type: "Explore"),
                  event(.subagentStopped, 30, agent: "a1", type: "Explore"), event(.subagentStopped, 31, agent: "a2", type: "Plan"),
                  event(.stopped, 40)] { try await store.record(e) }
        let tasks = try await store.agentTasks(limit: 10)
        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.byType == ["Explore": 2, "Plan": 1] && task.agents == 3 && task.finished == 2)
        #expect(task.startedAt == at(0) && task.endedAt == at(40) && task.fromPrompt)
    }

    @Test("The next prompt closes a task Claude never reported stopping; tasks without subagents count as tasks")
    func nextPrompt() async throws {
        let store = try Store.inMemory(now: t0)
        for e in [event(.promptSubmitted, 0), event(.promptSubmitted, 60), event(.subagentStarted, 65, agent: "b", type: "general-purpose")] {
            try await store.record(e)
        }
        let tasks = try await store.agentTasks(limit: 10)
        #expect(tasks.map(\.agents) == [1, 0])
        #expect(tasks.last?.endedAt == at(60) && tasks.first?.endedAt == nil)
    }

    @Test("Out of order, repeated or missing events: each subagent is one run")
    func robustness() async throws {
        let store = try Store.inMemory(now: t0)
        try await store.record(event(.promptSubmitted, 0))
        try await store.record(event(.subagentStopped, 9, agent: "x", type: "Explore"))      // the stop arrives first
        try await store.record(event(.subagentStarted, 8, agent: "x", type: "Explore"))
        try await store.record(event(.subagentStarted, 8, agent: "x", type: "Explore"))      // and the start twice
        try await store.record(event(.subagentStarted, 10, agent: nil, type: "Plan"))        // no agent reference: ignored
        try await store.record(event(.subagentStarted, 11, agent: "y", type: "db-migrator")) // not a known type
        let task = try #require(try await store.agentTasks(limit: 1).first)
        #expect(task.byType == ["Explore": 1, "unknown": 1] && task.finished == 1)
    }

    @Test("A subagent with no prompt seen gets a task of its own; sessions never mix")
    func missedPrompt() async throws {
        let store = try Store.inMemory(now: t0)
        try await store.record(event(.subagentStarted, 5, session: "1111111111111111", agent: "a", type: "Plan"))
        try await store.record(event(.promptSubmitted, 6, session: "2222222222222222"))
        try await store.record(event(.subagentStarted, 7, session: "2222222222222222", agent: "a", type: "Explore"))
        let tasks = try await store.agentTasks(limit: 10)
        #expect(tasks.count == 2)
        let first = try #require(tasks.first { $0.sessionRef == "1111111111111111" })
        #expect(!first.fromPrompt && first.byType == ["Plan": 1])
        #expect(tasks.first { $0.sessionRef == "2222222222222222" }?.byType == ["Explore": 1])
    }

    @Test("Tasks go after 30 days, their runs with them")
    func retention() async throws {
        let store = try Store.inMemory(now: t0)
        try await store.record(event(.promptSubmitted, 0))
        try await store.record(event(.subagentStarted, 1, agent: "a", type: "Plan"))
        let report = try await store.purge(now: at(31 * 86_400))
        #expect(report.tasks == 1)
        #expect(try await store.agentTasks(limit: 10).isEmpty)
        #expect(try await store.count("SELECT COUNT(*) FROM agent_runs") == 0)
    }
}
