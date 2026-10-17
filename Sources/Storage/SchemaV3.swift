// Migration v3 (increment 1.9): agents per task. A task is one prompt, from the moment it is sent until Claude stops;
// each subagent started in between is one run. Only counts and types are kept: the session and agent columns hold
// the helper's HMAC references, and the type is a built-in name or "custom" (founder decision, 17 Oct 2026).
enum SchemaV3 {
    static let agentTasks = """
    CREATE TABLE agent_tasks (
      id             TEXT PRIMARY KEY,
      connection_id  TEXT NOT NULL REFERENCES connections(id) ON DELETE CASCADE,
      session_ref    TEXT NOT NULL,
      started_at     INTEGER NOT NULL,
      ended_at       INTEGER,
      from_prompt    INTEGER NOT NULL CHECK (from_prompt IN (0, 1))
    );
    CREATE INDEX idx_agent_tasks_session ON agent_tasks(session_ref, started_at DESC);
    CREATE INDEX idx_agent_tasks_started ON agent_tasks(started_at DESC);
    CREATE TABLE agent_runs (
      task_id        TEXT NOT NULL REFERENCES agent_tasks(id) ON DELETE CASCADE,
      agent_ref      TEXT NOT NULL,
      agent_type     TEXT NOT NULL CHECK (agent_type IN ('general-purpose','Explore','Plan','statusline-setup','claude-code-guide','custom','unknown')),
      started_at     INTEGER NOT NULL,
      stopped_at     INTEGER,
      PRIMARY KEY (task_id, agent_ref)
    );
    """
}
