import CodexAdapter
import Foundation
import Testing
@testable import PulseApp

/// Item 4 in the app: Codex's agents per task on the Session page, while Codex is on and never in demo.
@MainActor
struct CodexAgentsModelTests {
    static func line(_ minute: Int, _ type: String, turn: String, parent: String? = nil, root: String? = nil, ordinal: Int) -> String {
        let at = String(format: "2026-10-16T14:%02d:00.000Z", minute), p = parent.map { "\"\($0)\"" } ?? "null", r = root ?? turn
        return #"{"timestamp":"\#(at)","ordinal":\#(ordinal),"type":"event_msg","payload":{"type":"\#(type)","turn_attribution":{"parent_turn_id":\#(p),"root_turn_id":"\#(r)","turn_id":"\#(turn)","turn_trigger":"user"},"turn_id":"\#(turn)","root_turn_id":"\#(r)"}}"#
    }
    static let mainMeta = #"{"timestamp":"2026-10-16T14:00:00.000Z","ordinal":0,"type":"session_meta","payload":{"id":"m","source":"vscode","thread_source":"user"}}"#
    static let subMeta = #"{"timestamp":"2026-10-16T14:00:00.000Z","ordinal":0,"type":"session_meta","payload":{"id":"s","source":{"subagent":{"thread_spawn":{"depth":1,"agent_role":"explorer"}}},"thread_source":"subagent","subagent_history_start_ordinal":1}}"#

    @Test func shownWhileOnDroppedWhenOff() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let folder = CodexReader.sessionsURL(home: box.home).appendingPathComponent("2026/10/16")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ([Self.mainMeta, Self.line(0, "task_started", turn: "T1", ordinal: 1), Self.line(9, "task_complete", turn: "T1", ordinal: 2)]
            .joined(separator: "\n") + "\n").write(to: folder.appendingPathComponent("rollout-m.jsonl"), atomically: true, encoding: .utf8)
        try ([Self.subMeta, Self.line(1, "task_started", turn: "s1", parent: "T1", root: "T1", ordinal: 1)]
            .joined(separator: "\n") + "\n").write(to: folder.appendingPathComponent("rollout-s.jsonl"), atomically: true, encoding: .utf8)

        let model = box.model(clock: TestClock())
        await model.start(); defer { model.stop() }
        await model.setDemo(false)
        #expect(!model.snapshot.codexAgentsShown && model.snapshot.codexAgents == nil, "off: nothing shown")
        await model.setCodexEnabled(true)
        #expect(model.snapshot.codexAgentsShown)
        #expect(await eventually { model.snapshot.codexAgents != nil })
        let latest = try #require(model.snapshot.codexAgents?.latest)
        #expect(latest.agents == 1 && latest.finished == 0 && latest.byType.map(\.name) == ["Explorer"])
        await model.setCodexEnabled(false)
        #expect(!model.snapshot.codexAgentsShown && model.snapshot.codexAgents == nil)
    }

    @Test func projectionOrdersRolesAndKeepsReviewsOutOfTheCounts() {
        let tasks = [CodexAgents.Task(id: "b", startedAt: t0 + 600, endedAt: nil, fromPrompt: true,
                                      byRole: ["custom": 1, "worker": 2, "default": 1], finished: 3, reviews: 40),
                     CodexAgents.Task(id: "a", startedAt: t0, endedAt: t0 + 60, fromPrompt: true, byRole: [:], finished: 0, reviews: 2)]
        let summary = OverviewProjection.codexAgents(tasks, now: t0 + 700)
        #expect(summary.recent.map(\.id) == ["b", "a"])
        #expect(summary.latest?.byType.map(\.name) == ["Default", "Worker", "Custom"] && summary.latest?.running == true)
        #expect(summary.latest?.reviews == 40 && summary.latest?.agents == 4)
        #expect(summary.tasks == 2 && summary.tasksWithAgents == 1 && summary.totalAgents == 4 && summary.mostInOneTask == 4)

        var input = OverviewInput()
        input.codexEnabled = true
        input.codexAgentTasks = tasks
        input.isDemo = true
        let demo = OverviewProjection.make(input, now: t0 + 700, staleAfter: 600, zone: .gmt, locale: Locale(identifier: "en_US"))
        #expect(!demo.codexAgentsShown && demo.codexAgents == nil, "never in demo")
    }
}
