import DesignSystem
import Foundation
import ShimProtocol
import Storage
import Testing
import UsageEngine
@testable import ClepsoApp

/// Approved agent names (founder decision 19 Oct 2026) through the app: Settings' list, the helper's config, the
/// ingest check, the store, the agents panel's labels, and the account sync (which never sees a name).
@MainActor
@Suite("Approved agent names", .serialized)
struct ApprovedAgentNamesTests {
    func config(_ box: Sandbox) throws -> [String]? {
        let data = try Data(contentsOf: box.home.appendingPathComponent(".claude/clepso/config.json"))
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["approved_agent_types"] as? [String]
    }

    @Test("Approve a name: the helper's config lists it, its runs show by name; remove it: config, store and panel forget it")
    func endToEnd() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try AgentsTests.original.write(to: box.settings)
        let clock = TestClock()
        let model = box.model(clock: clock)
        await model.start(); defer { model.stop() }
        #expect(await model.approveAgentName(" code-reviewer ") == .added, "surrounding spaces trimmed")
        guard case .installed = await model.install() else { Issue.record("install failed"); return }
        #expect(try config(box) == ["code-reviewer"], "install writes the list the user already approved")
        #expect(await model.setAgentsCounting(true) == .added)
        #expect(await model.approveAgentName("db-helper") == .added)
        #expect(try config(box) == ["code-reviewer", "db-helper"])
        #expect(model.approvedAgentNames == ["code-reviewer", "db-helper"])

        let path = model.environment.socketPath, now = clock.now()
        for frame in [try hookBytes(.promptSubmitted, at: now),
                      try hookBytes(.subagentStarted, at: now + 1, agent: "aaaaaaaaaaaaaaaa", type: "Explore"),
                      try hookBytes(.subagentStarted, at: now + 2, agent: "bbbbbbbbbbbbbbbb", type: "code-reviewer"),
                      try hookBytes(.subagentStarted, at: now + 3, agent: "cccccccccccccccc", type: "custom"),
                      // A helper with an old config (or anything else) sending a name that isn't approved: kept as Custom.
                      try hookBytes(.subagentStarted, at: now + 4, agent: "dddddddddddddddd", type: "not-approved")] {
            #expect(send(path, frame))
        }
        #expect(await eventually { model.snapshot.agents?.latest?.agents == 4 })
        #expect(model.snapshot.agents?.latest?.byType.map(\.name) == ["Explore (research)", "code-reviewer", "Custom"])
        #expect(model.snapshot.agents?.latest?.byType.map(\.count) == [1, 1, 2])
        #expect(Set(model.snapshot.agents?.live.map(\.type) ?? []) == ["Explore (research)", "code-reviewer", "Custom"])

        await model.removeApprovedAgentName("code-reviewer")
        #expect(try config(box) == ["db-helper"])
        #expect(model.approvedAgentNames == ["db-helper"])
        #expect(await eventually { model.snapshot.agents?.latest?.byType.map(\.name) == ["Explore (research)", "Custom"] })
        #expect(model.snapshot.agents?.latest?.byType.map(\.count) == [1, 3], "its stored run became Custom")

        // A restart reads the list back from preferences.
        model.stop()
        let again = box.model(clock: clock)
        await again.start(); defer { again.stop() }
        #expect(again.approvedAgentNames == ["db-helper"])
    }

    @Test("Adding checks the exact name: shape, built-in types, duplicates, the 50-name cap")
    func validation() {
        #expect(AppModel.checkAgentName("code-reviewer", existing: []) == .added)
        #expect(AppModel.checkAgentName("Code_Reviewer2", existing: ["code-reviewer"]) == .added, "case-sensitive: a different name")
        #expect(AppModel.checkAgentName("code-reviewer", existing: ["code-reviewer"]) == .duplicate)
        for bad in ["", "code reviewer", "code.reviewer", "a/b", String(repeating: "x", count: 41), "naïve"] {
            #expect(AppModel.checkAgentName(bad, existing: []) == .invalid, "\(bad)")
        }
        for reserved in ["Explore", "general-purpose", "custom", "Custom", "unknown"] {
            #expect(AppModel.checkAgentName(reserved, existing: []) == .builtIn, "\(reserved)")
        }
        #expect(AppModel.checkAgentName("one-more", existing: (0..<50).map { "a\($0)" }) == .full)
    }

    @Test("Find my agents: names from ~/.claude/agents frontmatter only, valid and not yet approved; nothing is approved")
    func suggestions() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let agents = box.home.appendingPathComponent(".claude/agents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let files = ["reviewer.md": "---\nname: code-reviewer\ndescription: Reviews canary code\n---\nYou review code.\n",
                     "quoted.md": "---\ndescription: x\nname: \"db-helper\"\n---\n",
                     "spaces.md": "---\nname: has spaces here\n---\n",
                     "nofront.md": "name: not-frontmatter\n",
                     "builtin.md": "---\nname: Explore\n---\n",
                     "notes.txt": "---\nname: from-a-txt\n---\n",
                     "approved.md": "---\nname: already-approved\n---\n"]
        for (name, text) in files { try Data(text.utf8).write(to: agents.appendingPathComponent(name)) }
        let model = box.model(clock: TestClock())
        await model.start(); defer { model.stop() }
        _ = await model.approveAgentName("already-approved")
        #expect(model.suggestedAgentNames() == ["code-reviewer", "db-helper"])
        #expect(model.approvedAgentNames == ["already-approved"], "suggesting approves nothing")
        #expect(AppModel.frontmatterName("---\nname: 'x-y'\n---") == "x-y")
        #expect(AppModel.frontmatterName("---\ndescription: a\n---\nname: late\n") == nil, "only inside the frontmatter")
    }

    @Test("Panel order: built-in types, approved names A to Z, then Custom; internal agents never")
    func order() {
        #expect(OverviewProjection.orderedAgentTypes(["custom", "zeta", "Plan", "unknown", "alpha", "Explore"]) == ["Explore", "Plan", "alpha", "zeta", "custom"])
        let counts = AgentsPanel.typeCounts(["Custom", "zeta", "General", "alpha", "zeta"])
        #expect(counts.map(\.name) == ["General", "alpha", "zeta", "Custom"] && counts.map(\.count) == [1, 1, 2, 1])
        #expect(OverviewProjection.agentTypeName("code-reviewer") == "code-reviewer", "shown exactly as approved")
    }

    @Test("Account sync never carries an approved name: it is counted under custom")
    func syncFoldsNames() {
        let now = Date(timeIntervalSince1970: 1_792_159_200)
        let task = Store.AgentTask(id: "t", sessionRef: "0123456789abcdef", startedAt: now - 3600, endedAt: nil, fromPrompt: true,
                                   byType: ["Explore": 2, "code-reviewer": 3, "custom": 1, "unknown": 4], finished: 1)
        let input = SyncPayloadBuilder.Input(profileName: "Sam", planLabel: nil, stats: nil, fiveHour: [], sevenDay: [], agentTasks: [task],
                                             goals: Goals(), goalStatuses: [], now: now, zone: TimeZone(identifier: "UTC")!)
        let payload = SyncPayloadBuilder.make(input)
        #expect(payload.agents.first?.byType == ["Explore": 2, "custom": 4])
        #expect(payload.agents.first?.agents == 6)
    }
}
