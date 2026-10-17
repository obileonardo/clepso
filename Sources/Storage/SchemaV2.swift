// Migration v2 (increment 1.7, DATA_MODEL §4): widen `observations.value_kind` to count, duration and flag.
// The table is rebuilt because SQLite cannot change a CHECK constraint; columns, rows, row order and indexes are
// carried over exactly, and `StorageTests` proves the copy is row-for-row identical.
enum SchemaV2 {
    static let observationsRebuild = """
    CREATE TABLE observations_v2 (
      id             TEXT PRIMARY KEY,
      account_id     TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      connection_id  TEXT NOT NULL REFERENCES connections(id) ON DELETE CASCADE,
      pool_id        TEXT REFERENCES allowance_pools(id) ON DELETE CASCADE,
      session_id     TEXT REFERENCES sessions(id) ON DELETE CASCADE,
      subject_kind   TEXT NOT NULL CHECK (subject_kind IN ('pool','session')),
      model_id       TEXT,
      metric_kind    TEXT NOT NULL,
      value_kind     TEXT NOT NULL CHECK (value_kind IN ('percent','tokens','usd','instant','count','duration','flag','absent')),
      value_text     TEXT,
      absence_reason TEXT CHECK (absence_reason IN ('providerOmitted','providerNull','notExposedBySource','rejectedBySanitizer')),
      observed_at    INTEGER NOT NULL,
      received_at    INTEGER NOT NULL,
      evidence       TEXT NOT NULL,
      quality        TEXT NOT NULL CHECK (quality IN ('verified','reported','estimated','unknown')),
      source_version TEXT,
      dedupe_key     TEXT NOT NULL,
      metadata_json  TEXT,
      CHECK ((subject_kind = 'pool' AND pool_id IS NOT NULL) OR (subject_kind = 'session' AND session_id IS NOT NULL)),
      CHECK ((value_kind = 'absent') = (value_text IS NULL)),
      CHECK ((value_kind = 'absent') = (absence_reason IS NOT NULL))
    );
    INSERT INTO observations_v2 (rowid, id, account_id, connection_id, pool_id, session_id, subject_kind, model_id, metric_kind,
      value_kind, value_text, absence_reason, observed_at, received_at, evidence, quality, source_version, dedupe_key, metadata_json)
      SELECT rowid, id, account_id, connection_id, pool_id, session_id, subject_kind, model_id, metric_kind,
      value_kind, value_text, absence_reason, observed_at, received_at, evidence, quality, source_version, dedupe_key, metadata_json
      FROM observations ORDER BY rowid;
    DROP TABLE observations;
    ALTER TABLE observations_v2 RENAME TO observations;
    CREATE UNIQUE INDEX uq_observations_dedupe ON observations(dedupe_key);
    CREATE INDEX idx_obs_pool_time    ON observations(pool_id, metric_kind, observed_at DESC);
    CREATE INDEX idx_obs_session_time ON observations(session_id, metric_kind, observed_at DESC);
    CREATE INDEX idx_obs_received     ON observations(received_at);
    """
}
