import CodexAdapter
import Foundation
import ShimProtocol
import Storage
import Testing
@testable import ClepsoApp

/// Sheet item 9: "Running now" from Claude Code's own list of in-flight background work, where a session has one, and
/// from start and stop events otherwise. Sheet item 10: the approved names apply to Codex's roles too.
struct ExactRunningNowTests {
    let t0 = Date(timeIntervalSince1970: 1_792_324_800)
    func task(_ id: String, _ start: Double, _ end: Double?, _ types: [String: Int], finished: Int = 0, session: String = "s") -> Store.AgentTask {
        Store.AgentTask(id: id, sessionRef: session, startedAt: t0 + start, endedAt: end.map { t0 + $0 }, fromPrompt: true, byType: types, finished: finished)
    }
    func open(_ task: String, _ type: String, _ start: Double, taskStart: Double, lastEvent: Double, session: String = "s") -> Store.OpenAgentRun {
        .init(taskID: task, sessionRef: session, agentType: type, startedAt: t0 + start, taskStartedAt: t0 + taskStart, sessionLastEvent: t0 + lastEvent)
    }
    func report(_ at: Double, _ agents: [String: Int], stopped: [String: Int] = [:], other: [String: Int] = [:], lastEvent: Double? = nil,
                session: String = "s") -> Store.BackgroundSnapshot {
        .init(sessionRef: session, reportedAt: t0 + at, agentsInFlight: agents, stoppedSince: stopped, otherWork: other,
              sessionLastEvent: lastEvent.map { t0 + $0 })
    }

    @Test("A run whose stop was lost stops counting at the next report; the task shows it as no stop seen")
    func phantomDropped() {
        let tasks = [task("a", 0, 60, ["Explore": 1, "general-purpose": 2]), task("b", 120, 180, [:])]
        let open = [open("a", "Explore", 5, taskStart: 0, lastEvent: 180), open("a", "general-purpose", 6, taskStart: 0, lastEvent: 180),
                    open("a", "general-purpose", 7, taskStart: 0, lastEvent: 180)]
        let inferred = OverviewProjection.agents(tasks, open: open, now: t0 + 240)
        #expect(inferred.live.count == 3 && inferred.liveExactAt == nil)
        let exact = OverviewProjection.agents(tasks, open: open, background: [report(180, ["general-purpose": 2], other: ["shell": 1])], now: t0 + 240)
        #expect(exact.live.map(\.type) == ["General", "General"] && exact.liveExactAt == t0 + 180)
        let a = exact.recent.first { $0.id == "a" }
        #expect(a?.stillRunning == 2 && a?.noStopSeen == 1)
        #expect(exact.backgroundOther == [.init(name: "Shell", count: 1)])
    }

    @Test("Listed but never seen starting: counted as running, start not seen; stops since the report subtract")
    func untrackedAndStoppedSince() {
        let tasks = [task("a", 0, 60, ["Plan": 1])]
        let open = [open("a", "Plan", 5, taskStart: 0, lastEvent: 60)]
        let summary = OverviewProjection.agents(tasks, open: open, background: [report(60, ["Plan": 1, "custom": 2], lastEvent: 70)], now: t0 + 120)
        #expect(summary.live.count == 3)
        #expect(summary.live.filter(\.untracked).map(\.type) == ["Custom", "Custom"])
        #expect(summary.live.filter(\.untracked).allSatisfy { $0.lastSeen == t0 + 70 && !$0.inLatestTask && !$0.stale })
        // One Custom agent stopped after the report (its start unseen, so a stop-only run).
        let later = OverviewProjection.agents(tasks, open: open, background: [report(60, ["Plan": 1, "custom": 2], stopped: ["custom": 1])], now: t0 + 120)
        #expect(later.live.count == 2 && later.live.filter(\.untracked).count == 1)
        // All of them stopped: nothing runs, and nothing is claimed exact.
        let done = OverviewProjection.agents(tasks, open: [], background: [report(60, ["Plan": 1], stopped: ["Plan": 1])], now: t0 + 120)
        #expect(done.live.isEmpty && done.liveExactAt == nil)
    }

    @Test("Subagents started after the report are counted from their own start; another session without a report stays inferred")
    func afterReportAndMixedSessions() {
        let tasks = [task("a", 0, 60, ["Explore": 1]), task("b", 100, nil, ["Plan": 1]), task("c", 0, nil, ["Explore": 1], session: "t")]
        let open = [open("b", "Plan", 110, taskStart: 100, lastEvent: 110), open("c", "Explore", 5, taskStart: 0, lastEvent: 5, session: "t")]
        let one = OverviewProjection.agents(Array(tasks.prefix(2)), open: [open[0]], background: [report(60, [:])], now: t0 + 130)
        #expect(one.live.map(\.type) == ["Plan"] && one.liveExactAt == t0 + 60, "the report said nothing ran; the Plan agent began after it")
        let mixed = OverviewProjection.agents(tasks, open: open, background: [report(60, [:])], now: t0 + 130)
        #expect(mixed.live.count == 2 && mixed.liveExactAt == nil, "session t has no report, so the count isn't exact")
    }

    @Test("A report older than the six-hour cap is ignored; the inference applies")
    func oldReportIgnored() {
        let tasks = [task("a", 7 * 3600, nil, ["Explore": 1])]
        let open = [open("a", "Explore", 7 * 3600 + 5, taskStart: 7 * 3600, lastEvent: 7 * 3600 + 5)]
        let summary = OverviewProjection.agents(tasks, open: open, background: [report(0, [:])], now: t0 + 7 * 3600 + 60)
        #expect(summary.live.count == 1 && summary.liveExactAt == nil)
    }

    @Test("Through the store: a stop's report, then the projection")
    func throughStore() async throws {
        let store = try Store.inMemory(now: t0)
        func e(_ kind: Store.AgentEvent.Kind, _ s: Double, agent: String? = nil, type: String? = nil, bg: Store.BackgroundCounts? = nil) -> Store.AgentEvent {
            .init(kind: kind, sessionRef: "s", agentRef: agent, agentType: type, at: t0 + s, background: bg)
        }
        for event in [e(.promptSubmitted, 0), e(.subagentStarted, 5, agent: "x", type: "Explore"), e(.subagentStarted, 6, agent: "y", type: "Explore"),
                      e(.stopped, 30, bg: .init(tasks: ["subagent": ["running": 1]], agents: ["Explore": ["running": 1]])),
                      e(.promptSubmitted, 40)] { try await store.record(event) }
        let summary = OverviewProjection.agents(try await store.agentTasks(limit: 10), open: try await store.openAgentRuns(since: t0),
                                                background: try await store.backgroundSnapshots(since: t0), now: t0 + 60)
        #expect(summary.live.count == 1 && summary.liveExactAt == t0 + 30)
        #expect(summary.recent.last?.stillRunning == 1 && summary.recent.last?.noStopSeen == 1)
    }

    @Test("Frame to store: the app re-checks each background agent type against its own list")
    func sinkRecheck() {
        let names = AgentNameAllowlist()
        names.set(["code-reviewer"])
        let counts = StoreSink.counts(names)(.init(tasks: [.subagent: [.running: 3], .shell: [.pending: 1]],
                                                   agents: ["code-reviewer": [.running: 1], "db-helper": [.running: 1], "custom": [.running: 1]]))
        #expect(counts.agents == ["code-reviewer": ["running": 1], "custom": ["running": 2]], "db-helper came off the list")
        #expect(counts.tasks == ["subagent": ["running": 3], "shell": ["pending": 1]])
    }

    @Test("Copy: Settings says the list applies to both agents; the Tasks card says report-back turns count")
    func copy() {
        #expect(Copy.Agents.namesSub.contains("in Claude Code and Codex"))
        #expect(Copy.Agents.tasksNote.contains("background agent reporting back"))
    }

    @Test("Codex roles on the approved list show by name, after the built-ins and before Custom")
    func codexApprovedRoles() {
        let tasks = [CodexAgents.Task(id: "T1", startedAt: t0, endedAt: t0 + 60, fromPrompt: true,
                                      byRole: ["custom": 1, "worker": 1, "reviewer": 2, "auditor": 1, "default": 1], finished: 6, reviews: 0)]
        let summary = OverviewProjection.codexAgents(tasks, now: t0 + 120)
        #expect(summary.latest?.byType.map(\.name) == ["Default", "Worker", "auditor", "reviewer", "Custom"])
    }
}
