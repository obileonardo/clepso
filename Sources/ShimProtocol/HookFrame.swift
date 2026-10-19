import Foundation

/// Agents per task (increment 1.9): the frame the helper sends for a Claude Code hook event.
///
/// Claude Code gives every hook the whole event on stdin, including the user's prompt, the last reply and file
/// paths. Like the status-line frame, this one is built from an allowlist inside the helper, so nothing else can
/// reach the app: the event name, the session as an HMAC reference, the subagent as an HMAC reference, and the
/// subagent's type reduced to Claude Code's built-in names or "custom" (founder decision 17 Oct 2026: a custom
/// agent's own name can say what a project is about, so it is not sent). The one exception is a name the user has
/// approved in Settings, letter for letter (founder decision 19 Oct 2026): the app writes the approved list into the
/// helper's config, and the helper sends a custom type verbatim only when it is exactly one of them. `Stop` and
/// `SubagentStop` also carry what Claude Code still has running in the background, as counts by type and status only
/// (founder decision 19 Oct 2026, sheet item 9; `Background`).
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
        if event == .stopped || event == .subagentStopped, let background = background(input["background_tasks"], approved: approvedAgentTypes) {
            frame["background"] = background.json
        }
        return .frame(.object(frame))
    }

    // MARK: - Background work (decision 19 Oct 2026, sheet item 9)

    /// What Claude Code still has in flight in the session, as counts only. `Stop` and `SubagentStop` carry
    /// `background_tasks`, one entry per in-flight background task of the parent session (Claude Code hooks reference,
    /// "Stop input"; https://code.claude.com/docs/en/hooks): `id`, `type`, `status`, `description` and, by type,
    /// `command`, `agent_type`, `server`, `tool`, `name`. Only `type`, `status` and a subagent's `agent_type` are read,
    /// each mapped onto a closed set, and only how many of each leaves the helper; the ids, descriptions, commands,
    /// server, tool and workflow names are never copied.
    public struct Background: Sendable, Equatable {
        /// Claude Code's documented type labels; anything else (a future or internal type) is `other`.
        public enum TaskType: String, Sendable, CaseIterable {
            case shell, subagent, monitor, workflow, teammate, cloudSession = "cloud_session", mcpTask = "mcp_task", other
        }
        /// The reference documents no status values; Claude Code lists in-flight work, which it describes as running or
        /// pending. Any other status is `other`.
        public enum Status: String, Sendable, CaseIterable { case running, pending, other }

        /// Every in-flight task by type and status.
        public var tasks: [TaskType: [Status: Int]]
        /// The `subagent` tasks again, by agent type under the approved-names rule (built-in, approved, else "custom").
        /// A subagent entry without an agent type is counted only in `tasks`.
        public var agents: [String: [Status: Int]]

        public init(tasks: [TaskType: [Status: Int]] = [:], agents: [String: [Status: Int]] = [:]) {
            self.tasks = tasks
            self.agents = agents
        }

        /// Subagents in flight (any status) by agent type.
        public var agentsInFlight: [String: Int] { agents.mapValues { $0.values.reduce(0, +) } }

        var json: JSONValue {
            func counts(_ map: [String: [Status: Int]]) -> JSONValue {
                .object(map.mapValues { statuses in .object(Dictionary(uniqueKeysWithValues: statuses.map { ($0.key.rawValue, .number(Double($0.value))) })) })
            }
            return .object(["tasks": counts(Dictionary(uniqueKeysWithValues: tasks.map { ($0.key.rawValue, $0.value) })), "agents": counts(agents)])
        }
    }

    static let taskTypeLabels: [String: Background.TaskType] = [
        "shell": .shell, "subagent": .subagent, "monitor": .monitor, "workflow": .workflow, "teammate": .teammate,
        "cloud session": .cloudSession, "MCP task": .mcpTask,
    ]
    /// Each count stops here; the frame stays far below `FrameCodec.maxPayloadBytes` whatever Claude Code lists.
    public static let maxBackgroundCount = 9999
    /// At most this many agent types; the smallest beyond it are folded into "custom", so the frame's size is bounded.
    public static let maxBackgroundAgentTypes = 16

    /// The counts, or nil when `value` isn't a list (an older Claude Code, or its task registry unreachable): then the
    /// app keeps inferring from SubagentStart and SubagentStop. An empty list is an exact "nothing in flight".
    public static func background(_ value: Any?, approved: Set<String>) -> Background? {
        guard let list = value as? [Any] else { return nil }
        var result = Background()
        for case let entry as [String: Any] in list {
            let type = (entry["type"] as? String).flatMap { taskTypeLabels[$0] } ?? .other
            let status = (entry["status"] as? String).flatMap(Background.Status.init(rawValue:)) ?? .other
            result.tasks[type, default: [:]][status, default: 0] += 1
            if type == .subagent, let agent = entry["agent_type"] as? String, !agent.isEmpty {
                result.agents[reportedAgentType(agent, approved: approved), default: [:]][status, default: 0] += 1
            }
        }
        if result.agents.count > maxBackgroundAgentTypes {
            let ranked = result.agents.filter { $0.key != customAgentType }
                .sorted { ($0.value.values.reduce(0, +), $1.key) > ($1.value.values.reduce(0, +), $0.key) }
            var kept = Dictionary(uniqueKeysWithValues: ranked.prefix(maxBackgroundAgentTypes - 1).map { ($0.key, $0.value) })
            var custom = result.agents[customAgentType] ?? [:]
            for (_, statuses) in ranked.dropFirst(maxBackgroundAgentTypes - 1) { custom.merge(statuses, uniquingKeysWith: +) }
            kept[customAgentType] = custom
            result.agents = kept
        }
        func clamp(_ s: [Background.Status: Int]) -> [Background.Status: Int] { s.mapValues { min($0, maxBackgroundCount) } }
        result.tasks = result.tasks.mapValues(clamp)
        result.agents = result.agents.mapValues(clamp)
        return result
    }

    /// The app's check of a frame's `background`: known task types and statuses, agent types that pass the same gate as
    /// `agent_type`, whole counts from 1 to `maxBackgroundCount`. Anything else drops the whole object (the event is kept).
    static func decodeBackground(_ value: JSONValue?) -> Background? {
        guard case .object(let members)? = value, Set(members.keys) == ["tasks", "agents"],
              case .object(let tasks)? = members["tasks"], case .object(let agents)? = members["agents"],
              agents.count <= maxBackgroundAgentTypes else { return nil }
        func statuses(_ value: JSONValue) -> [Background.Status: Int]? {
            guard case .object(let map) = value, !map.isEmpty else { return nil }
            var out: [Background.Status: Int] = [:]
            for (key, count) in map {
                guard let status = Background.Status(rawValue: key), case .number(let n) = count, n.isFinite, n == n.rounded(),
                      (1...Double(maxBackgroundCount)).contains(n) else { return nil }
                out[status] = Int(n)
            }
            return out
        }
        var result = Background()
        for (key, value) in tasks {
            guard let type = Background.TaskType(rawValue: key), let s = statuses(value) else { return nil }
            result.tasks[type] = s
        }
        for (key, value) in agents {
            guard builtInAgentTypes.contains(key) || key == customAgentType || isApprovableAgentName(key), let s = statuses(value) else { return nil }
            result.agents[key] = s
        }
        return result
    }

    /// The app's side: a decoded hook frame, or nil when it isn't one or a field is out of shape.
    public struct Decoded: Sendable, Equatable {
        public let event: Event
        public let sessionRef: String
        public let agentRef: String?
        public let agentType: String?
        public let emittedAt: Date
        /// `Stop` and `SubagentStop` only: Claude Code's in-flight background work, as counts; nil when not sent.
        public let background: Background?

        public init(event: Event, sessionRef: String, agentRef: String?, agentType: String?, emittedAt: Date, background: Background? = nil) {
            self.event = event
            self.sessionRef = sessionRef
            self.agentRef = agentRef
            self.agentType = agentType
            self.emittedAt = emittedAt
            self.background = background
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
        let background = event == .stopped || event == .subagentStopped ? decodeBackground(frame["background"]) : nil
        return Decoded(event: event, sessionRef: session, agentRef: agent, agentType: type, emittedAt: Date(timeIntervalSince1970: ms / 1000),
                       background: background)
    }
}
