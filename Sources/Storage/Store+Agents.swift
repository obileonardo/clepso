import Foundation
import GRDB

/// Agents per task (increment 1.9): hook events folded into tasks and subagent runs.
extension Store {
    public struct AgentEvent: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case promptSubmitted, subagentStarted, subagentStopped, stopped }
        public let kind: Kind
        public let sessionRef: String
        public let agentRef: String?
        public let agentType: String?
        public let at: Date
        /// A stop's report of Claude Code's in-flight background work (sheet item 9), or nil when the frame had none.
        public let background: BackgroundCounts?

        public init(kind: Kind, sessionRef: String, agentRef: String?, agentType: String?, at: Date, background: BackgroundCounts? = nil) {
            self.kind = kind
            self.sessionRef = sessionRef
            self.agentRef = agentRef
            self.agentType = agentType
            self.at = at
            self.background = background
        }
    }

    /// Claude Code's in-flight background work as a `Stop` or `SubagentStop` reported it: counts by task type
    /// (`shell`, `subagent`, `monitor`, `workflow`, `teammate`, `cloud_session`, `mcp_task`, `other`) and status
    /// (`running`, `pending`, `other`), and the subagents again by agent type. Labels outside those sets are dropped
    /// here as well as by the table's CHECKs.
    public struct BackgroundCounts: Sendable, Equatable {
        public var tasks: [String: [String: Int]]
        public var agents: [String: [String: Int]]

        public init(tasks: [String: [String: Int]] = [:], agents: [String: [String: Int]] = [:]) {
            self.tasks = tasks
            self.agents = agents
        }

        public static let taskTypes: Set<String> = ["shell", "subagent", "monitor", "workflow", "teammate", "cloud_session", "mcp_task", "other"]
        public static let statuses: Set<String> = ["running", "pending", "other"]
    }

    /// A session's latest exact report of background work (`agent_background`), within `backgroundSnapshots(since:)`.
    public struct BackgroundSnapshot: Sendable, Equatable {
        public let sessionRef: String
        public let reportedAt: Date
        /// Subagents in flight at `reportedAt`, any status, by agent type.
        public let agentsInFlight: [String: Int]
        /// Of the session's subagents, by type, those whose stop Clepso received at or after `reportedAt` and that had
        /// started before it (or whose start it never saw): they were in flight at the report and have finished since.
        public let stoppedSince: [String: Int]
        /// Other background work in flight at `reportedAt`, any status, by task type (`subagent` left out).
        public let otherWork: [String: Int]
        /// The newest hook event Clepso has from the session (as `OpenAgentRun.sessionLastEvent`), never before `reportedAt`.
        public let sessionLastEvent: Date

        public init(sessionRef: String, reportedAt: Date, agentsInFlight: [String: Int], stoppedSince: [String: Int], otherWork: [String: Int],
                    sessionLastEvent: Date? = nil) {
            self.sessionRef = sessionRef
            self.reportedAt = reportedAt
            self.agentsInFlight = agentsInFlight
            self.stoppedSince = stoppedSince
            self.otherWork = otherWork
            self.sessionLastEvent = max(reportedAt, sessionLastEvent ?? reportedAt)
        }
    }

    static let agentTypes: Set<String> = ["general-purpose", "Explore", "Plan", "statusline-setup", "claude-code-guide", "custom"]

    /// A type the store keeps: a built-in type, "custom", or a name of a Claude Code agent name's shape (an approved
    /// custom agent; the helper sends no other). Mirrors `HookFrame.isApprovableAgentName`, which Storage doesn't
    /// depend on; the `agent_runs` CHECK enforces the same shape.
    static func storableAgentType(_ type: String) -> Bool {
        if agentTypes.contains(type) { return true }
        let bytes = type.utf8, lowered = type.lowercased()
        return (1...40).contains(bytes.count) && lowered != "custom" && lowered != "unknown" && bytes.allSatisfy { byte in
            (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-")
        }
    }

    /// The user took a name off the approved list: its runs become "custom", so the name is no longer kept anywhere.
    /// Returns the number of runs changed. Built-in types and Clepso's own buckets are never touched.
    @discardableResult
    public func forgetAgentName(_ name: String) throws -> Int {
        guard !Self.agentTypes.contains(name), name != "unknown" else { return 0 }
        return try writer.write { db in
            try db.execute(sql: "UPDATE agent_runs SET agent_type = 'custom' WHERE agent_type = ?", arguments: [name])
            let changed = db.changesCount
            // Its background counts join the session's Custom counts.
            try db.execute(sql: """
                INSERT INTO agent_background_counts (session_ref, task_type, agent_type, status, count)
                  SELECT session_ref, task_type, 'custom', status, count FROM agent_background_counts WHERE agent_type = ? AND true
                ON CONFLICT (session_ref, task_type, agent_type, status) DO UPDATE SET count = MIN(9999, count + excluded.count)
                """, arguments: [name])
            try db.execute(sql: "DELETE FROM agent_background_counts WHERE agent_type = ?", arguments: [name])
            return changed
        }
    }

    /// A prompt opens a task (closing the session's previous one if Claude never reported stopping); Claude stopping
    /// closes it. A subagent belongs to the session's latest task that started before it; with none, a task is opened
    /// for it (`fromPrompt` false: Clepso missed the prompt, for instance because the hooks were added mid-task).
    /// Hooks run in the background, so a stop can arrive before its start: either order lands on the same run.
    ///
    /// A stop's background report (sheet item 9) replaces the session's earlier one when it is exact: Claude stopped, or
    /// a subagent stopped while none of the session's prompts was in progress. Background work is all Claude Code lists,
    /// so during a prompt a subagent working in the foreground would be missing from it; such a report is not kept.
    public func record(_ event: AgentEvent) throws {
        try writer.write { db in
            let at = ms(event.at)
            if let background = event.background, event.kind == .stopped || event.kind == .subagentStopped {
                let promptInProgress = try event.kind == .subagentStopped && (Bool.fetchOne(db, sql: """
                    SELECT EXISTS (SELECT 1 FROM agent_tasks WHERE session_ref = ? AND ended_at IS NULL AND started_at <= ? AND started_at > ?)
                    """, arguments: [event.sessionRef, at, at - Int64(6 * 3_600_000)]) ?? false)
                if !promptInProgress { try recordBackground(db, background, session: event.sessionRef, at: at, kind: event.kind) }
            }
            switch event.kind {
            case .promptSubmitted:
                try db.execute(sql: "UPDATE agent_tasks SET ended_at = ? WHERE session_ref = ? AND ended_at IS NULL AND started_at <= ?",
                               arguments: [at, event.sessionRef, at])
                try insertTask(db, session: event.sessionRef, at: at, fromPrompt: true)
            case .stopped:
                try db.execute(sql: """
                    UPDATE agent_tasks SET ended_at = ? WHERE id = (
                      SELECT id FROM agent_tasks WHERE session_ref = ? AND ended_at IS NULL AND started_at <= ? ORDER BY started_at DESC LIMIT 1)
                    """, arguments: [at, event.sessionRef, at])
            case .subagentStarted, .subagentStopped:
                guard let agent = event.agentRef else { return }
                let type = event.agentType.flatMap { Self.storableAgentType($0) ? $0 : nil } ?? "unknown"
                if let existing = try String.fetchOne(db, sql: """
                    SELECT r.task_id FROM agent_runs r JOIN agent_tasks t ON t.id = r.task_id WHERE t.session_ref = ? AND r.agent_ref = ?
                    """, arguments: [event.sessionRef, agent]) {
                    if event.kind == .subagentStopped {
                        try db.execute(sql: "UPDATE agent_runs SET stopped_at = ? WHERE task_id = ? AND agent_ref = ?", arguments: [at, existing, agent])
                    } else {
                        try db.execute(sql: "UPDATE agent_runs SET started_at = MIN(started_at, ?) WHERE task_id = ? AND agent_ref = ?",
                                       arguments: [at, existing, agent])
                    }
                    return
                }
                let task = try String.fetchOne(db, sql: """
                    SELECT id FROM agent_tasks WHERE session_ref = ? AND started_at <= ? ORDER BY started_at DESC LIMIT 1
                    """, arguments: [event.sessionRef, at]) ?? insertTask(db, session: event.sessionRef, at: at, fromPrompt: false)
                try db.execute(sql: "INSERT INTO agent_runs (task_id, agent_ref, agent_type, started_at, stopped_at) VALUES (?, ?, ?, ?, ?)",
                               arguments: [task, agent, type, at, event.kind == .subagentStopped ? at : nil])
            }
        }
    }

    /// Keeps `background` as the session's latest report, unless a later one is already stored (hooks run in the
    /// background, so their frames can arrive out of order).
    func recordBackground(_ db: Database, _ background: BackgroundCounts, session: String, at: Int64, kind: AgentEvent.Kind) throws {
        if let stored = try Int64.fetchOne(db, sql: "SELECT reported_at FROM agent_background WHERE session_ref = ?", arguments: [session]),
           stored > at { return }
        try db.execute(sql: "DELETE FROM agent_background WHERE session_ref = ?", arguments: [session])      // counts cascade
        try db.execute(sql: "INSERT INTO agent_background (session_ref, connection_id, reported_at, event) VALUES (?, ?, ?, ?)",
                       arguments: [session, connectionID.uuidString, at, kind == .stopped ? "Stop" : "SubagentStop"])
        func insert(_ taskType: String, _ agentType: String, _ statuses: [String: Int]) throws {
            for (status, count) in statuses where BackgroundCounts.statuses.contains(status) && count > 0 {
                try db.execute(sql: "INSERT INTO agent_background_counts (session_ref, task_type, agent_type, status, count) VALUES (?, ?, ?, ?, ?)",
                               arguments: [session, taskType, agentType, status, min(count, 9999)])
            }
        }
        for (type, statuses) in background.tasks where BackgroundCounts.taskTypes.contains(type) { try insert(type, "", statuses) }
        for (type, statuses) in background.agents where Self.storableAgentType(type) { try insert("subagent", type, statuses) }
    }

    /// Each session's latest exact background report made since `since`, with the subagent stops Clepso received
    /// since it. Claude Code's internal agents ("unknown") are never counted.
    public func backgroundSnapshots(since: Date) throws -> [BackgroundSnapshot] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT session_ref, reported_at FROM agent_background WHERE reported_at >= ? ORDER BY reported_at DESC",
                             arguments: [ms(since)]).map { row in
                let session: String = row["session_ref"], reported: Int64 = row["reported_at"]
                var agents: [String: Int] = [:], other: [String: Int] = [:], stopped: [String: Int] = [:]
                for count in try Row.fetchAll(db, sql: """
                    SELECT task_type, agent_type, SUM(count) AS n FROM agent_background_counts WHERE session_ref = ? GROUP BY task_type, agent_type
                    """, arguments: [session]) {
                    let task: String = count["task_type"], agent: String = count["agent_type"], n: Int = count["n"]
                    if !agent.isEmpty { agents[agent, default: 0] += n } else if task != "subagent" { other[task, default: 0] += n }
                }
                for run in try Row.fetchAll(db, sql: """
                    SELECT r.agent_type, COUNT(*) AS n FROM agent_runs r JOIN agent_tasks t ON t.id = r.task_id
                    WHERE t.session_ref = ? AND r.agent_type != 'unknown' AND r.stopped_at >= ? AND (r.started_at < ? OR r.started_at = r.stopped_at)
                    GROUP BY r.agent_type
                    """, arguments: [session, reported, reported]) {
                    stopped[run["agent_type"]] = run["n"]
                }
                return BackgroundSnapshot(sessionRef: session, reportedAt: date(reported), agentsInFlight: agents, stoppedSince: stopped, otherWork: other,
                                          sessionLastEvent: try Self.lastEvent(db, session: session).map(date))
            }
        }
    }

    @discardableResult
    func insertTask(_ db: Database, session: String, at: Int64, fromPrompt: Bool) throws -> String {
        let id = UUID().uuidString
        try db.execute(sql: "INSERT INTO agent_tasks (id, connection_id, session_ref, started_at, ended_at, from_prompt) VALUES (?, ?, ?, ?, NULL, ?)",
                       arguments: [id, connectionID.uuidString, session, at, fromPrompt ? 1 : 0])
        return id
    }

    public struct AgentTask: Sendable, Equatable, Identifiable {
        public let id: String
        public let sessionRef: String
        public let startedAt: Date
        public let endedAt: Date?
        public let fromPrompt: Bool
        /// Subagents by type: built-in names, approved custom names, or "custom"/"unknown".
        public let byType: [String: Int]
        public let finished: Int
        public var agents: Int { byType.values.reduce(0, +) }

        public init(id: String, sessionRef: String, startedAt: Date, endedAt: Date?, fromPrompt: Bool, byType: [String: Int], finished: Int) {
            self.id = id
            self.sessionRef = sessionRef
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.fromPrompt = fromPrompt
            self.byType = byType
            self.finished = finished
        }
    }

    /// A subagent with a start and no stop yet: possibly still working, whichever task it was started in. Claude Code
    /// sends nothing while a subagent works, so `sessionLastEvent` (the newest hook event Clepso has from its session:
    /// a prompt, a stop, any subagent starting or stopping) is the latest sign of life there is.
    public struct OpenAgentRun: Sendable, Equatable {
        public let taskID: String
        public let sessionRef: String
        public let agentType: String
        public let startedAt: Date
        public let taskStartedAt: Date
        public let sessionLastEvent: Date

        public init(taskID: String, sessionRef: String, agentType: String, startedAt: Date, taskStartedAt: Date, sessionLastEvent: Date) {
            self.taskID = taskID
            self.sessionRef = sessionRef
            self.agentType = agentType
            self.startedAt = startedAt
            self.taskStartedAt = taskStartedAt
            self.sessionLastEvent = sessionLastEvent
        }
    }

    /// Every subagent started since `since` that has no stop, in any task, newest first. Claude Code's internal agents
    /// (stored as "unknown") are left out: they are only ever stored from a stop.
    public func openAgentRuns(since: Date) throws -> [OpenAgentRun] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT r.task_id, t.session_ref, r.agent_type, r.started_at, t.started_at AS task_started_at
                FROM agent_runs r JOIN agent_tasks t ON t.id = r.task_id
                WHERE r.stopped_at IS NULL AND r.agent_type != 'unknown' AND r.started_at >= ?
                ORDER BY r.started_at DESC
                """, arguments: [ms(since)])
            var lastEvent: [String: Int64] = [:]
            for session in Set(rows.map { $0["session_ref"] as String }) { lastEvent[session] = try Self.lastEvent(db, session: session) }
            return rows.map { row in
                let session: String = row["session_ref"]
                let started: Int64 = row["started_at"]
                return OpenAgentRun(taskID: row["task_id"], sessionRef: session, agentType: row["agent_type"], startedAt: date(started),
                                    taskStartedAt: date(row["task_started_at"]), sessionLastEvent: date(max(started, lastEvent[session] ?? started)))
            }
        }
    }

    /// The newest hook event Clepso has from a session: a prompt, a stop, any subagent starting or stopping, a background report.
    static func lastEvent(_ db: Database, session: String) throws -> Int64? {
        try Int64.fetchOne(db, sql: """
            SELECT MAX(v) FROM (
              SELECT MAX(started_at, COALESCE(ended_at, 0)) AS v FROM agent_tasks WHERE session_ref = ?
              UNION ALL
              SELECT MAX(r.started_at, COALESCE(r.stopped_at, 0)) FROM agent_runs r JOIN agent_tasks t ON t.id = r.task_id
              WHERE t.session_ref = ?
              UNION ALL
              SELECT reported_at FROM agent_background WHERE session_ref = ?)
            """, arguments: [session, session, session])
    }

    /// The most recent tasks, newest first.
    public func agentTasks(limit: Int) throws -> [AgentTask] {
        try writer.read { db in
            let tasks = try Row.fetchAll(db, sql: "SELECT * FROM agent_tasks ORDER BY started_at DESC LIMIT ?", arguments: [limit])
            return try tasks.map { row in
                let id: String = row["id"]
                var byType: [String: Int] = [:]
                var finished = 0
                for run in try Row.fetchAll(db, sql: "SELECT agent_type, stopped_at FROM agent_runs WHERE task_id = ?", arguments: [id]) {
                    byType[run["agent_type"], default: 0] += 1
                    if (run["stopped_at"] as Int64?) != nil { finished += 1 }
                }
                return AgentTask(id: id, sessionRef: row["session_ref"], startedAt: date(row["started_at"]),
                                 endedAt: (row["ended_at"] as Int64?).map(date), fromPrompt: (row["from_prompt"] as Int64) == 1,
                                 byType: byType, finished: finished)
            }
        }
    }
}
