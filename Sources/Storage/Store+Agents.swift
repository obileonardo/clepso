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

        public init(kind: Kind, sessionRef: String, agentRef: String?, agentType: String?, at: Date) {
            self.kind = kind
            self.sessionRef = sessionRef
            self.agentRef = agentRef
            self.agentType = agentType
            self.at = at
        }
    }

    static let agentTypes: Set<String> = ["general-purpose", "Explore", "Plan", "statusline-setup", "claude-code-guide", "custom"]

    /// A prompt opens a task (closing the session's previous one if Claude never reported stopping); Claude stopping
    /// closes it. A subagent belongs to the session's latest task that started before it; with none, a task is opened
    /// for it (`fromPrompt` false: Pulse missed the prompt, for instance because the hooks were added mid-task).
    /// Hooks run in the background, so a stop can arrive before its start: either order lands on the same run.
    public func record(_ event: AgentEvent) throws {
        try writer.write { db in
            let at = ms(event.at)
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
                let type = event.agentType.flatMap { Self.agentTypes.contains($0) ? $0 : nil } ?? "unknown"
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
        /// Subagents by type, built-in names or "custom"/"unknown".
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
