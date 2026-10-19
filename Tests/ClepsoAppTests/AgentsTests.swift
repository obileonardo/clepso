import CryptoKit
import DesignSystem
import Foundation
import ShimProtocol
import Storage
import Testing
@testable import ClepsoApp

/// A hook frame as the helper sends it.
func hookBytes(_ event: HookFrame.Event, at: Date, session: String = "0123456789abcdef", agent: String? = nil, type: String? = nil) throws -> Data {
    var frame: [String: JSONValue] = ["v": .number(1), "kind": .string(HookFrame.kind), "emitted_at_ms": .number((at.timeIntervalSince1970 * 1000).rounded()),
                                      "shim_version": .string("0.1.0"), "event": .string(event.rawValue), "session_ref": .string(session)]
    if let agent { frame["agent_ref"] = .string(agent) }
    if let type { frame["agent_type"] = .string(type) }
    return try FrameCodec.encode(.object(frame))
}

/// Increment 1.9: agents per task through the app, in a throwaway home.
@MainActor
@Suite("Agents per task", .serialized)
struct AgentsTests {
    static let original = Data("{\n  \"model\": \"opus\",\n  \"hooks\": {\n    \"Stop\": [{\"hooks\": [{\"type\": \"command\", \"command\": \"echo done\"}]}]\n  }\n}\n".utf8)

    @Test("Connect, add hooks, count a task's subagents, then remove the connection: settings come back byte for byte")
    func endToEnd() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try Self.original.write(to: box.settings)
        let clock = TestClock()
        let model = box.model(clock: clock)
        await model.start(); defer { model.stop() }
        #expect(await model.setAgentsCounting(true) == .failed(reason: Copy.Agents.needsConnection), "hooks need the connection")
        #expect(try Data(contentsOf: box.settings) == Self.original)

        guard case .installed = await model.install() else { Issue.record("install failed"); return }
        #expect(await model.setAgentsCounting(true) == .added)
        #expect(model.agentsCounting)
        let text = String(decoding: try Data(contentsOf: box.settings), as: UTF8.self)
        #expect(text.contains("echo done") && text.contains("SubagentStart") && text.contains("hook.sh"))

        let path = model.environment.socketPath
        let now = clock.now()
        for frame in [try hookBytes(.promptSubmitted, at: now),
                      try hookBytes(.subagentStarted, at: now + 2, agent: "aaaaaaaaaaaaaaaa", type: "Explore"),
                      try hookBytes(.subagentStarted, at: now + 3, agent: "bbbbbbbbbbbbbbbb", type: "Plan"),
                      try hookBytes(.subagentStopped, at: now + 9, agent: "aaaaaaaaaaaaaaaa", type: "Explore")] {
            #expect(send(path, frame))
        }
        #expect(await eventually { model.snapshot.agents?.latest?.agents == 2 && model.snapshot.agents?.latest?.finished == 1 })   // frames arrive in parallel
        let latest = try #require(model.snapshot.agents?.latest)
        #expect(latest.byType.map(\.name) == ["Explore (research)", "Plan"] && latest.finished == 1 && latest.running)
        #expect(model.snapshot.agents?.live.map(\.type) == ["Plan"], "the Plan agent, with no stop, is running now")

        #expect(await model.uninstall() == .restoredExactly)
        #expect(try Data(contentsOf: box.settings) == Self.original, "hooks and status line both gone, bytes as before")
        #expect(!model.agentsCounting)
        #expect(model.diagnostics.entries.contains { $0.code == "agents.hooks" && !$0.text.contains("/") })
    }

    @Test("Delete all takes the hooks out too")
    func deleteAll() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try Self.original.write(to: box.settings)
        let model = box.model(clock: TestClock())
        await model.start()
        guard case .installed = await model.install() else { Issue.record("install failed"); return }
        #expect(await model.setAgentsCounting(true) == .added)
        let report = await model.deleteAll(includeBackups: false, relaunch: false)
        #expect(report.failure == nil)
        #expect(try Data(contentsOf: box.settings) == Self.original)
    }

    @Test("Summary: newest first, types in display order, a task without a stop counts as running for six hours")
    func projection() {
        func task(_ id: String, _ start: Double, _ end: Double?, _ types: [String: Int], finished: Int = 0) -> Store.AgentTask {
            Store.AgentTask(id: id, sessionRef: "s", startedAt: t0 + start, endedAt: end.map { t0 + $0 }, fromPrompt: true, byType: types, finished: finished)
        }
        let now = t0 + 7 * 3600
        let summary = OverviewProjection.agents([task("a", 0, nil, ["Plan": 1]), task("b", 6.5 * 3600, nil, ["custom": 1, "Explore": 2, "general-purpose": 1]),
                                                 task("c", 3600, 3700, [:]), task("old", -40 * 86_400, -40 * 86_400 + 60, ["Explore": 9])], now: now)
        #expect(summary.recent.map(\.id) == ["b", "c", "a", "old"])
        #expect(summary.latest?.byType.map(\.name) == ["Explore (research)", "General", "Custom"])
        #expect(summary.latest?.running == true && summary.recent[2].running == false, "over six hours without a stop: not running")
        #expect(summary.tasks == 3 && summary.tasksWithAgents == 2 && summary.totalAgents == 5 && summary.mostInOneTask == 4)
        #expect(abs(summary.averagePerTask - 5.0 / 3) < 1e-9)
    }

    @Test("Claude Code's internal agents (a stop with no type, stored as unknown) aren't counted as a task's subagents")
    func internalAgentsLeftOut() {
        func task(_ id: String, _ start: Double, _ types: [String: Int], finished: Int) -> Store.AgentTask {
            Store.AgentTask(id: id, sessionRef: "s", startedAt: t0 + start, endedAt: t0 + start + 60, fromPrompt: true, byType: types, finished: finished)
        }
        let summary = OverviewProjection.agents([task("a", 0, ["Explore": 2, "unknown": 27], finished: 28),
                                                 task("b", 600, ["unknown": 3], finished: 3)], now: t0 + 3600)
        #expect(summary.recent.map(\.agents) == [0, 2])
        #expect(summary.recent.map(\.finished) == [0, 1])
        #expect(summary.recent.flatMap { $0.byType.map(\.name) } == ["Explore (research)"], "no Unknown chip")
        #expect(summary.tasks == 2 && summary.tasksWithAgents == 1 && summary.totalAgents == 2 && summary.mostInOneTask == 2)
    }
}

/// Subagents running now, across tasks (founder review, 19 Oct 2026): a lead agent's background subagents outlive the
/// prompt that started them, so the latest task's "no subagents" must not read as "nothing is running".
struct LiveAgentsTests {
    let t0 = Date(timeIntervalSince1970: 1_792_324_800)
    func task(_ id: String, _ start: Double, _ end: Double?, _ types: [String: Int], finished: Int = 0) -> Store.AgentTask {
        Store.AgentTask(id: id, sessionRef: "s", startedAt: t0 + start, endedAt: end.map { t0 + $0 }, fromPrompt: true, byType: types, finished: finished)
    }
    func open(_ task: String, _ type: String, _ start: Double, taskStart: Double, lastEvent: Double) -> Store.OpenAgentRun {
        .init(taskID: task, sessionRef: "s", agentType: type, startedAt: t0 + start, taskStartedAt: t0 + taskStart, sessionLastEvent: t0 + lastEvent)
    }

    @Test("Background subagents from an earlier task count as running now; the newer task still started none")
    func acrossTasks() {
        let tasks = [task("a", 0, 60, ["general-purpose": 3], finished: 1), task("b", 120, nil, [:])]
        let open = [open("a", "general-purpose", 20, taskStart: 0, lastEvent: 130), open("a", "general-purpose", 25, taskStart: 0, lastEvent: 130)]
        let summary = OverviewProjection.agents(tasks, open: open, now: t0 + 300)
        #expect(summary.latest?.id == "b" && summary.latest?.agents == 0, "the newest prompt started no subagents of its own")
        #expect(summary.live.count == 2 && summary.live.allSatisfy { !$0.inLatestTask && !$0.stale && $0.type == "General" })
        #expect(summary.live.map(\.startedAt) == [t0 + 25, t0 + 20], "newest first")
        let a = summary.recent.first { $0.id == "a" }
        #expect(a?.stillRunning == 2 && a?.noStopSeen == 0 && a?.finished == 1 && a?.running == false, "the task is done; two of its agents aren't")
        #expect(summary.totalAgents == 3 && summary.mostInOneTask == 3, "running agents stay with the task that started them")
    }

    @Test("Ten quiet minutes in the session: still counted, labelled last seen")
    func staleAfterTenMinutes() {
        let tasks = [task("a", 0, 60, ["Explore": 1])]
        let open = [open("a", "Explore", 10, taskStart: 0, lastEvent: 60)]
        let fresh = OverviewProjection.agents(tasks, open: open, now: t0 + 60 + 9 * 60)
        let quiet = OverviewProjection.agents(tasks, open: open, now: t0 + 60 + 10 * 60)
        #expect(fresh.live.first?.stale == false)
        #expect(quiet.live.count == 1 && quiet.live.first?.stale == true && quiet.live.first?.lastSeen == t0 + 60)
        #expect(quiet.live.first?.type == "Explore (research)")
    }

    @Test("A subagent whose stop never came stops counting six hours after it started: neither running nor finished")
    func noStopAfterSixHours() {
        let tasks = [task("old", 0, 600, ["general-purpose": 2], finished: 1), task("new", 7 * 3600, nil, [:])]
        let open = [open("old", "general-purpose", 30, taskStart: 0, lastEvent: 7 * 3600)]   // the session is busy, the agent silent
        let summary = OverviewProjection.agents(tasks, open: open, now: t0 + 7 * 3600 + 60)
        #expect(summary.live.isEmpty)
        let old = summary.recent.first { $0.id == "old" }
        #expect(old?.stillRunning == 0 && old?.noStopSeen == 1 && old?.finished == 1)
        // Just inside the cap it is still running.
        #expect(OverviewProjection.agents(tasks, open: open, now: t0 + 30 + OverviewProjection.agentRunCap - 1).live.count == 1)
    }

    @Test("Type names are Claude Code's own, made readable; the live card counts them in display order")
    func typeNames() {
        let names = ["general-purpose", "Explore", "Plan", "statusline-setup", "claude-code-guide", "custom"].map(OverviewProjection.agentTypeName)
        #expect(names == ["General", "Explore (research)", "Plan", "Status line setup", "Claude Code guide", "Custom"])
        let counts = AgentsPanel.typeCounts(["General", "Custom", "Explore (research)", "General", "Plan"])
        #expect(counts.map(\.name) == ["Explore (research)", "Plan", "General", "Custom"] && counts.map(\.count) == [1, 1, 2, 1])
    }

    @Test func elapsedIsToTheMinute() {
        #expect(AgentsPanel.elapsed(since: t0, now: t0 + 59) == "under 1m")
        #expect(AgentsPanel.elapsed(since: t0, now: t0 + 14 * 60 + 59) == "14m")
        #expect(AgentsPanel.elapsed(since: t0, now: t0 + 3900) == "1h 5m")
    }

    @Test("Codex has no start and stop events: nothing is ever shown as running now")
    func codexHasNoLive() {
        #expect(OverviewProjection.codexAgents([], now: t0).live.isEmpty)
    }
}

/// Recent tasks name the day when it isn't today (founder review, 18 Oct 2026).
struct AgentStartedLabelTests {
    @Test func todayIsTheTimeEarlierDaysAddTheDay() {
        let utc = TimeZone(identifier: "UTC")!, gb = Locale(identifier: "en_GB")
        let now = Date(timeIntervalSince1970: 1_792_324_800)               // Sun 18 Oct 2026 12:00 UTC
        let today = AgentsPanel.started(now - 3600, now: now, zone: utc, locale: gb)
        let yesterday = AgentsPanel.started(now - 13 * 3600, now: now, zone: utc, locale: gb)
        let older = AgentsPanel.started(now - 10 * 86_400, now: now, zone: utc, locale: gb)
        #expect(today == Formatting.clock(now - 3600, zone: utc, locale: gb))
        #expect(yesterday.hasPrefix("Sat ") && yesterday.hasSuffix(Formatting.clock(now - 13 * 3600, zone: utc, locale: gb)))
        #expect(older.hasPrefix("8 Oct "))
    }
}

