import Foundation
import Testing
@testable import ShimProtocol

/// Approved agent names (founder decision 19 Oct 2026): the hook frame carries a custom agent's type verbatim only when
/// it is exactly, letter for letter, a name the user approved; every other custom type is "custom".
@Suite("Hook frame: approved agent names")
struct HookFrameApprovedNamesTests {
    func type(_ agentType: String, approved: Set<String>) -> JSONValue? {
        let json = #"{"hook_event_name": "SubagentStart", "session_id": "s", "agent_id": "a", "agent_type": "\#(agentType)"}"#
        guard case .frame(let frame) = HookFrame.build(stdin: Data(json.utf8), now: Date(timeIntervalSince1970: 1_792_159_200),
                                                       shimVersion: "t", hmacKey: Data(repeating: 9, count: 32),
                                                       approvedAgentTypes: approved) else { return nil }
        return frame["agent_type"]
    }

    @Test("Approved: sent exactly. Not approved, a different case, or nothing approved: custom. Built-in types unchanged")
    func gate() {
        let approved: Set<String> = ["code-reviewer", "db_migrator2"]
        #expect(type("code-reviewer", approved: approved) == .string("code-reviewer"))
        #expect(type("db_migrator2", approved: approved) == .string("db_migrator2"))
        #expect(type("Code-Reviewer", approved: approved) == .string("custom"), "case-sensitive")
        #expect(type("code-reviewer ", approved: approved) == .string("custom"), "exact: no trimming")
        #expect(type("secret-project-x", approved: approved) == .string("custom"))
        #expect(type("code-reviewer", approved: []) == .string("custom"))
        #expect(type("Explore", approved: []) == .string("Explore"))
        #expect(type("Plan", approved: approved) == .string("Plan"))
    }

    @Test("An approved list can't open the gate to text that isn't an agent name")
    func approvedFreeTextStillBlocked() {
        let hostile: Set<String> = ["refactor the billing module", "/Users/sam/project", "a.b", "unknown", "Custom", String(repeating: "x", count: 41)]
        for name in hostile { #expect(type(name, approved: hostile) == .string("custom"), "\(name)") }
    }

    @Test("Approvable names: 1–40 of A–Z a–z 0–9 _ -, not built in, not custom or unknown in any case")
    func shape() {
        for good in ["code-reviewer", "A", "x_1", String(repeating: "z", count: 40), "Explorer", "PLAN"] {
            #expect(HookFrame.isApprovableAgentName(good), "\(good)")
        }
        for bad in ["", " code", "code reviewer", "code.reviewer", "naïve", "agent/x", String(repeating: "z", count: 41),
                    "Explore", "general-purpose", "custom", "CUSTOM", "Unknown", "emoji🙂"] {
            #expect(!HookFrame.isApprovableAgentName(bad), "\(bad)")
        }
    }

    @Test("The app decodes an approved name, and refuses a type that isn't an agent name's shape")
    func decode() {
        func decoded(_ type: String) -> String? {
            HookFrame.decode(.object(["kind": .string(HookFrame.kind), "event": .string("SubagentStart"), "session_ref": .string("0123456789abcdef"),
                                      "emitted_at_ms": .number(1_792_159_200_000), "agent_type": .string(type)]))?.agentType
        }
        #expect(decoded("code-reviewer") == "code-reviewer")
        #expect(decoded("custom") == "custom" && decoded("Explore") == "Explore")
        #expect(decoded("two words") == nil && decoded("/Users/x") == nil)
    }
}
