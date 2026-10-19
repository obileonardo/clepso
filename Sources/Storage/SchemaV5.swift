// Migration v5 (founder decision 19 Oct 2026, sheet item 9): what Claude Code still has running in the background, from
// the counts a `Stop` or `SubagentStop` hook frame carries. One row per session: its latest exact report (Claude stopped,
// or a subagent stopped while no prompt was in progress, so nothing in the foreground could be missing), and its counts
// by task type, agent type and status. Counts only: no task id, description, command or name exists in the frame. The
// CHECKs keep every label to its closed set, and `agent_type` to the same shape as `agent_runs.agent_type`. Additive:
// two new tables, nothing existing changes.
enum SchemaV5 {
    static let agentBackground = """
    CREATE TABLE agent_background (
      session_ref    TEXT PRIMARY KEY,
      connection_id  TEXT NOT NULL REFERENCES connections(id) ON DELETE CASCADE,
      reported_at    INTEGER NOT NULL,
      event          TEXT NOT NULL CHECK (event IN ('Stop','SubagentStop'))
    );
    CREATE TABLE agent_background_counts (
      session_ref    TEXT NOT NULL REFERENCES agent_background(session_ref) ON DELETE CASCADE,
      task_type      TEXT NOT NULL CHECK (task_type IN ('shell','subagent','monitor','workflow','teammate','cloud_session','mcp_task','other')),
      agent_type     TEXT NOT NULL DEFAULT '' CHECK (
        agent_type = '' OR agent_type IN ('general-purpose','Explore','Plan','statusline-setup','claude-code-guide','custom')
        OR (length(agent_type) BETWEEN 1 AND 40 AND agent_type NOT GLOB '*[^A-Za-z0-9_-]*')),
      status         TEXT NOT NULL CHECK (status IN ('running','pending','other')),
      count          INTEGER NOT NULL CHECK (count BETWEEN 1 AND 9999),
      PRIMARY KEY (session_ref, task_type, agent_type, status)
    );
    """
}
