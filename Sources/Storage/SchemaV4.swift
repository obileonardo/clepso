// Migration v4 (founder decision 19 Oct 2026): `agent_runs.agent_type` may also hold a custom agent name the user
// approved in Settings. The helper sends a custom type verbatim only when it is exactly an approved name; everything
// else still arrives as "custom". The CHECK keeps the column to an agent name's shape (1–40 of A–Z a–z 0–9 _ -), so
// no sentence, path or other free text can be stored there whatever reaches the database. SQLite cannot change a CHECK,
// so the table is rebuilt with every row copied unchanged (DATA_MODEL §4 rule 3).
enum SchemaV4 {
    static let agentRunsRebuild = """
    CREATE TABLE agent_runs_v4 (
      task_id        TEXT NOT NULL REFERENCES agent_tasks(id) ON DELETE CASCADE,
      agent_ref      TEXT NOT NULL,
      agent_type     TEXT NOT NULL CHECK (
        agent_type IN ('general-purpose','Explore','Plan','statusline-setup','claude-code-guide','custom','unknown')
        OR (length(agent_type) BETWEEN 1 AND 40 AND agent_type NOT GLOB '*[^A-Za-z0-9_-]*')),
      started_at     INTEGER NOT NULL,
      stopped_at     INTEGER,
      PRIMARY KEY (task_id, agent_ref)
    );
    INSERT INTO agent_runs_v4 (rowid, task_id, agent_ref, agent_type, started_at, stopped_at)
      SELECT rowid, task_id, agent_ref, agent_type, started_at, stopped_at FROM agent_runs ORDER BY rowid;
    DROP TABLE agent_runs;
    ALTER TABLE agent_runs_v4 RENAME TO agent_runs;
    """
}
