import Foundation

/// Agents per task (increment 1.9): the frame the helper sends for a Claude Code hook event.
///
/// Claude Code gives every hook the whole event on stdin, including the user's prompt, the last reply and file
/// paths. Like the status-line frame, this one is built from an allowlist inside the helper, so nothing else can
/// reach the app: the event name, the session as an HMAC reference, the subagent as an HMAC reference, and the
/// subagent's type reduced to Claude Code's built-in names or "custom" (founder decision 17 Oct 2026: a custom
/// agent's own name can say what a project is about, so it is not sent). The one exception is a name the user has
/// approved in Settings, letter for letter (founder decision 19 Oct 2026): the app writes the approved list into the
/// helper's config, and the helper sends a custom type verbatim only when it is exactly one of them.
public enum HookFrame {
    public static let kind = "claude_code.hook"

    /// The four events Clepso registers: a task starts with the prompt and ends when Claude stops; subagents start
    /// and stop in between.
    public enum Event: String, Sendable, CaseIterable {
        case promptSubmitted = "UserPromptSubmit"
        case subagentStarted = "SubagentStart"
        case subagentStopped = "SubagentStop"
        case stopped = "Stop"
    }

    /// Claude Code's built-in subagent types, sent by name. Anything else, including plugin agents, is "custom".
    public static let builtInAgentTypes: Set<String> = ["general-purpose", "Explore", "Plan", "statusline-setup", "claude-code-guide"]
    public static let customAgentType = "custom"

    /// Approved names: the shape of a Claude Code agent name (`[A-Za-z0-9_-]`, 1–40 characters), so nothing with spaces,
    /// slashes or dots, no path or sentence, can be approved. "custom" and "unknown" (in any case) are Clepso's own
    /// buckets and a built-in type is already shown by name, so neither can be approved.
    public static let maxAgentNameLength = 40
    public static let maxApprovedAgentNames = 50

    public static func isApprovableAgentName(_ name: String) -> Bool {
        let bytes = name.utf8
        guard (1...maxAgentNameLength).contains(bytes.count), bytes.allSatisfy({ byte in
            (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-")
        }) else { return false }
        let lowered = name.lowercased()
        return !builtInAgentTypes.contains(name) && lowered != customAgentType && lowered != "unknown"
    }

    /// The type a frame carries: a built-in type as is; any other type verbatim only if it is exactly (case-sensitive)
    /// one of `approved` and has an agent name's shape; otherwise "custom".
    public static func reportedAgentType(_ type: String, approved: Set<String>) -> String {
        if builtInAgentTypes.contains(type) { return type }
        return approved.contains(type) && isApprovableAgentName(type) ? type : customAgentType
    }

    public enum NoFrameReason: String, Sendable, Equatable {
        case stdinTooLarge, notJSON, notObject, unknownEvent, noSession
    }

    public enum Outcome: Sendable, Equatable {
        case frame(JSONValue)
        case noFrame(NoFrameReason)
    }

    /// Parsing stops here; a larger event (a huge pasted prompt) sends nothing rather than risk the helper's budget.
    public static let maxParsedStdinBytes = 4 << 20

    /// Pure: no I/O, no clock read. Without a key nothing is sent, because events can't be grouped into tasks.
    /// `approvedAgentTypes`: the names the user approved (the helper's config); empty, every custom type is "custom".
    public static func build(stdin: Data, now: Date, shimVersion: String, hmacKey: Data?,
                             approvedAgentTypes: Set<String> = []) -> Outcome {
        guard stdin.count <= maxParsedStdinBytes else { return .noFrame(.stdinTooLarge) }
        guard let parsed = try? JSONSerialization.jsonObject(with: stdin) else { return .noFrame(.notJSON) }
        guard let input = parsed as? [String: Any] else { return .noFrame(.notObject) }
        guard let name = input["hook_event_name"] as? String, let event = Event(rawValue: name) else { return .noFrame(.unknownEvent) }
        guard let key = hmacKey, let session = input["session_id"] as? String, !session.isEmpty else { return .noFrame(.noSession) }

        var frame: [String: JSONValue] = [
            "v": .number(Double(FrameBuilder.version)),
            "kind": .string(kind),
            "emitted_at_ms": .number((now.timeIntervalSince1970 * 1000).rounded(.down)),
            "shim_version": .string(shimVersion),
            "event": .string(event.rawValue),
            "session_ref": .string(FrameBuilder.sessionRef(session, key: key)),
        ]
        if event == .subagentStarted || event == .subagentStopped {
            if let agent = input["agent_id"] as? String, !agent.isEmpty {
                frame["agent_ref"] = .string(FrameBuilder.sessionRef("agent:" + agent, key: key))
            }
            if let type = input["agent_type"] as? String, !type.isEmpty {
                frame["agent_type"] = .string(reportedAgentType(type, approved: approvedAgentTypes))
            }
        }
        return .frame(.object(frame))
    }

    /// The app's side: a decoded hook frame, or nil when it isn't one or a field is out of shape.
    public struct Decoded: Sendable, Equatable {
        public let event: Event
        public let sessionRef: String
        public let agentRef: String?
        public let agentType: String?
        public let emittedAt: Date

        public init(event: Event, sessionRef: String, agentRef: String?, agentType: String?, emittedAt: Date) {
            self.event = event
            self.sessionRef = sessionRef
            self.agentRef = agentRef
            self.agentType = agentType
            self.emittedAt = emittedAt
        }
    }

    public static func decode(_ frame: JSONValue) -> Decoded? {
        func string(_ key: String) -> String? { if case .string(let s)? = frame[key] { s } else { nil } }
        func isRef(_ s: String) -> Bool { s.count == 16 && s.allSatisfy { $0.isHexDigit && !$0.isUppercase } }
        guard string("kind") == kind, let event = string("event").flatMap(Event.init(rawValue:)),
              let session = string("session_ref"), isRef(session),
              case .number(let ms)? = frame["emitted_at_ms"], ms.isFinite, ms > 0 else { return nil }
        let agent = string("agent_ref").flatMap { isRef($0) ? $0 : nil }
        let type = string("agent_type").flatMap { builtInAgentTypes.contains($0) || $0 == customAgentType || isApprovableAgentName($0) ? $0 : nil }
        return Decoded(event: event, sessionRef: session, agentRef: agent, agentType: type, emittedAt: Date(timeIntervalSince1970: ms / 1000))
    }
}
