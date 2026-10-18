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
        #expect(latest.byType.map(\.name) == ["Explore", "Plan"] && latest.finished == 1 && latest.running)

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
        #expect(summary.latest?.byType.map(\.name) == ["Explore", "General", "Custom"])
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
        #expect(summary.recent.flatMap { $0.byType.map(\.name) } == ["Explore"], "no Unknown chip")
        #expect(summary.tasks == 2 && summary.tasksWithAgents == 1 && summary.totalAgents == 2 && summary.mostInOneTask == 2)
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

