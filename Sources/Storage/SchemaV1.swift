// Generated from DATA_MODEL §3, schema v1. Do not edit by hand;
// change the document and regenerate so the spec and the code cannot drift.
enum SchemaV1 {
    static let sql = """
-- identity
CREATE TABLE accounts (
  id            TEXT PRIMARY KEY,
  provider_id   TEXT NOT NULL,
  kind          TEXT NOT NULL CHECK (kind IN ('personalSubscription','organizationSeat','apiOrganization','apiProject')),
  label         TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  archived_at   INTEGER
);
CREATE TABLE connections (
  id              TEXT PRIMARY KEY,
  account_id      TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  adapter_id      TEXT NOT NULL,
  adapter_version TEXT,
  state           TEXT NOT NULL CHECK (state IN ('notConnected','connected','paused','providerError','disconnected')),
  last_event_at   INTEGER
);
CREATE INDEX idx_connections_account ON connections(account_id);

CREATE TABLE sessions (
  id                   TEXT PRIMARY KEY,
  account_id           TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  connection_id        TEXT NOT NULL REFERENCES connections(id) ON DELETE CASCADE,
  provider_session_key TEXT NOT NULL,
  model_id             TEXT,
  model_display_name   TEXT,
  first_seen_at        INTEGER NOT NULL,
  last_seen_at         INTEGER NOT NULL,
  project_alias        TEXT,
  UNIQUE (connection_id, provider_session_key)
);
CREATE INDEX idx_sessions_last_seen ON sessions(account_id, last_seen_at DESC);

CREATE TABLE allowance_pools (
  id                TEXT PRIMARY KEY,
  account_id        TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  provider_pool_key TEXT NOT NULL,
  name              TEXT NOT NULL,
  funding           TEXT NOT NULL CHECK (funding IN ('includedSubscription','prepaidCredits','promotionalAPICredit','billedOverage','apiPayAsYouGo','unknown')),
  window_type       TEXT NOT NULL CHECK (window_type IN ('rolling','scheduled','unknown')),
  eligible_products TEXT NOT NULL DEFAULT '[]',          -- JSON array
  overage_evidence  TEXT,                                 -- EvidenceKind or NULL
  created_at        INTEGER NOT NULL,
  UNIQUE (account_id, provider_pool_key)
);

CREATE TABLE pool_windows (
  id         TEXT PRIMARY KEY,
  pool_id    TEXT NOT NULL REFERENCES allowance_pools(id) ON DELETE CASCADE,
  opened_at  INTEGER NOT NULL,
  resets_at  INTEGER,
  closed_at  INTEGER,
  version    INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX idx_pool_windows_open ON pool_windows(pool_id, closed_at, opened_at DESC);

-- ledger (append-only; no UPDATE/DELETE outside retention)
CREATE TABLE observations (
  id             TEXT PRIMARY KEY,
  account_id     TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  connection_id  TEXT NOT NULL REFERENCES connections(id) ON DELETE CASCADE,
  pool_id        TEXT REFERENCES allowance_pools(id) ON DELETE CASCADE,
  session_id     TEXT REFERENCES sessions(id) ON DELETE CASCADE,
  subject_kind   TEXT NOT NULL CHECK (subject_kind IN ('pool','session')),
  model_id       TEXT,
  metric_kind    TEXT NOT NULL,
  value_kind     TEXT NOT NULL CHECK (value_kind IN ('percent','tokens','usd','instant','absent')),
  value_text     TEXT,                    -- canonical Decimal, Int64, or epoch-ms; NULL iff absent
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
CREATE UNIQUE INDEX uq_observations_dedupe ON observations(dedupe_key);         -- the dedupe index
CREATE INDEX idx_obs_pool_time    ON observations(pool_id, metric_kind, observed_at DESC);
CREATE INDEX idx_obs_session_time ON observations(session_id, metric_kind, observed_at DESC);
CREATE INDEX idx_obs_received     ON observations(received_at);                 -- retention sweep

-- projections (rebuildable)
CREATE TABLE pool_snapshots (
  pool_id                TEXT PRIMARY KEY REFERENCES allowance_pools(id) ON DELETE CASCADE,
  account_id             TEXT NOT NULL,
  window_id              TEXT REFERENCES pool_windows(id),
  snapshot_json          TEXT NOT NULL,   -- Codable PoolSnapshot, schemaVersion inside
  state                  TEXT NOT NULL,   -- denormalised for queries
  last_provider_measured INTEGER,
  last_seen              INTEGER,
  version                INTEGER NOT NULL
);
CREATE TABLE session_snapshots (
  session_id    TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
  snapshot_json TEXT NOT NULL,
  last_seen     INTEGER NOT NULL,
  version       INTEGER NOT NULL
);
CREATE TABLE derived_events (
  id              TEXT PRIMARY KEY,
  kind            TEXT NOT NULL,
  account_id      TEXT NOT NULL,
  pool_id         TEXT,
  window_id       TEXT,
  level           TEXT,
  observation_id  TEXT,
  occurred_at     INTEGER NOT NULL,
  dedupe_key      TEXT NOT NULL,
  payload_json    TEXT NOT NULL DEFAULT '{}'
);
CREATE INDEX idx_events_time ON derived_events(account_id, occurred_at DESC);
CREATE INDEX idx_events_dedupe ON derived_events(dedupe_key);

CREATE TABLE notification_receipts (     -- contract: NOTIFICATIONS_AND_SCHEDULING §1.4
  id             TEXT PRIMARY KEY,
  dedupe_key     TEXT NOT NULL,             -- NOTIFICATIONS §1.3
  channel        TEXT NOT NULL CHECK (channel IN ('localNotification','push','digest')),
  account_id     TEXT NOT NULL,
  pool_id        TEXT,
  window_id      TEXT,
  kind           TEXT NOT NULL,             -- NotificationKind case
  level          INTEGER,                   -- threshold percent
  event_id       TEXT,
  observation_id TEXT,                      -- evidence the candidate was built from
  schedule_id    TEXT,                      -- reminder and expected kinds
  device_id      TEXT,
  decided_at     INTEGER NOT NULL,
  outcome        TEXT NOT NULL CHECK (outcome IN ('delivered','coalesced','quiet_deferred','snoozed','stale_dropped','superseded')),
  version        INTEGER NOT NULL DEFAULT 1,
  UNIQUE (dedupe_key, channel)
);
CREATE TABLE alert_suppressions (           -- snooze and "Pause alerts"
  account_id TEXT NOT NULL,
  pool_id    TEXT,
  until      INTEGER NOT NULL,
  reason     TEXT NOT NULL
);

-- plan intelligence (Stage A picker, Stage B graph)
CREATE TABLE subscription_identities (
  id                 TEXT PRIMARY KEY,
  account_id         TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  provider_id        TEXT NOT NULL,
  account_kind       TEXT NOT NULL,
  plan_catalog_id    TEXT,
  display_plan_name  TEXT,
  seat_alias         TEXT,
  organization_alias TEXT,
  evidence           TEXT NOT NULL,
  verified_at        INTEGER,
  effective_from     INTEGER,
  effective_until    INTEGER,
  evidence_url       TEXT,
  metadata_json      TEXT
);
CREATE INDEX idx_subs_account_effective ON subscription_identities(account_id, effective_from DESC);
CREATE TABLE plan_catalog_versions (
  provider_id  TEXT NOT NULL,
  version      TEXT NOT NULL,
  effective_at INTEGER NOT NULL,
  checked_at   INTEGER NOT NULL,
  source_url   TEXT NOT NULL,
  catalog_json TEXT NOT NULL,
  PRIMARY KEY (provider_id, version)
);
CREATE TABLE entitlements (
  id                 TEXT PRIMARY KEY,
  subscription_id    TEXT NOT NULL REFERENCES subscription_identities(id) ON DELETE CASCADE,
  feature_key        TEXT NOT NULL,
  funding            TEXT NOT NULL,
  seat_kind          TEXT,
  hard_cap           INTEGER,             -- NULL unknown, 0/1
  expires_at         INTEGER,
  evidence           TEXT NOT NULL,
  source_ref         TEXT,
  last_reverified_at INTEGER
);
CREATE TABLE entitlement_pool_links (
  entitlement_id TEXT NOT NULL REFERENCES entitlements(id) ON DELETE CASCADE,
  pool_id        TEXT NOT NULL REFERENCES allowance_pools(id) ON DELETE CASCADE,
  evidence       TEXT NOT NULL,
  linked_at      INTEGER NOT NULL,
  PRIMARY KEY (entitlement_id, pool_id)
);

-- schedules
CREATE TABLE reset_schedules (
  id                    TEXT PRIMARY KEY,
  account_id            TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  pool_id               TEXT NOT NULL REFERENCES allowance_pools(id) ON DELETE CASCADE,
  window_id             TEXT,
  source_observation_id TEXT NOT NULL,
  reset_at              INTEGER NOT NULL,
  source_verified_at    INTEGER NOT NULL,
  channel               TEXT NOT NULL CHECK (channel IN ('localNotification','appleCalendar','appleReminder','iOSAlarm')),
  kind                  TEXT NOT NULL CHECK (kind IN ('resetReminder','resetExpected')),
  lead_minutes          INTEGER NOT NULL DEFAULT 0,
  mode                  TEXT NOT NULL CHECK (mode IN ('oneShot','managed')),
  status                TEXT NOT NULL,
  version               INTEGER NOT NULL DEFAULT 1,
  parent_schedule_id    TEXT,
  external_event_id     TEXT,
  writer_device_id      TEXT,
  cancellation_reason   TEXT,
  created_at            INTEGER NOT NULL,
  updated_at            INTEGER NOT NULL,
  UNIQUE (account_id, pool_id, reset_at, channel, kind)   -- PRD §23.4 composite key
);
CREATE INDEX idx_schedules_pending ON reset_schedules(status, reset_at);
CREATE TABLE calendar_sync_receipts (
  schedule_id                     TEXT PRIMARY KEY REFERENCES reset_schedules(id) ON DELETE CASCADE,
  target_calendar_id              TEXT NOT NULL,
  system_event_id                 TEXT NOT NULL,
  permission_seen                 TEXT NOT NULL,
  last_sync_result                TEXT NOT NULL,
  last_written_at                 INTEGER NOT NULL,
  last_known_external_modified_at INTEGER
);

-- operational
CREATE TABLE connector_health (
  connection_id     TEXT PRIMARY KEY REFERENCES connections(id) ON DELETE CASCADE,
  parser_rejections INTEGER NOT NULL DEFAULT 0,
  scrub_count       INTEGER NOT NULL DEFAULT 0,
  unknown_fields    INTEGER NOT NULL DEFAULT 0,
  last_skew_ms      INTEGER,
  last_error        TEXT,
  updated_at        INTEGER NOT NULL
);
CREATE TABLE preferences (key TEXT PRIMARY KEY, value_json TEXT NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE devices (id TEXT PRIMARY KEY, label TEXT NOT NULL, kind TEXT NOT NULL, paired_at INTEGER NOT NULL, revoked_at INTEGER);
CREATE TABLE sync_cursors (device_id TEXT NOT NULL, stream TEXT NOT NULL, cursor TEXT NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY (device_id, stream));
"""
}
