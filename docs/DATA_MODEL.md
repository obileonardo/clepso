# Data model

How Clepso represents what it reads, how it stores it, and how it derives the states it shows. Section numbers are
stable: code comments cite them (for example `DATA_MODEL §5.1`).

Source of truth: the code. Types live in `Sources/Domain`, the schema and migrations in `Sources/Storage`, the state
machines in `Sources/UsageEngine`, and the frame mapping in `Sources/ClaudeCodeAdapter/FrameMapper.swift`.

## 1. The invariant

Every value Clepso shows traces back to one immutable observation that carries its source, its scope and the instant
it was measured. A missing value is recorded as a fact ("absent, and why") and is never shown as zero.

Two layers follow from that:

1. **Ledger**: the `observations` table, append-only. Only retention deletes rows.
2. **Projections**: `pool_snapshots`, `session_snapshots`, `pool_windows` and `derived_events`, rebuildable from the
   ledger plus the current time (§9).

Freshness is computed from the last measured instant, the current time and a time-to-live; it is never stored.

## 2. Domain contracts

All domain types are `Sendable` value types in `Sources/Domain` and import neither AppKit nor GRDB. Instants are
`Date` in memory and epoch milliseconds in SQLite (§8). Percentages and money are `Decimal`, never `Double`.

### 2.1 Identity and evidence

`EvidenceKind` is the one provenance vocabulary for every value:

| Case | Meaning | Tie-break priority |
|---|---|---|
| `officialAPI` | A provider API | 60 |
| `officialLocalTelemetry` | A provider's own local output (the Claude Code status line, Codex session files) | 50 |
| `userConfirmed` | The user said so (for example paid overage) | 40 |
| `officialAnnouncement` | A provider announcement | 30 |
| `userSelectedUnverified` | A plan the user picked that no source has confirmed | 20 |
| `thirdPartyUnverified` | Someone else's report | 10 |
| `inferred` | Derived by Clepso's engine; never provider truth | 0 |

Priority only breaks ties between observations with the same `observedAt` (§6.1). `Quality` is `verified`,
`reported`, `estimated` or `unknown`. An `Account` has a provider id and a user-chosen label (never an email); a
`Connection` is one adapter feeding one account (for example `claude-code.statusline` or `codex.sessions`) with a
`ConnectionState` of `notConnected`, `connected`, `paused`, `providerError` or `disconnected`.

### 2.2 Typed value and the observation

`MetricValue` keeps the unit and the value together, so they cannot drift apart:

```swift
enum MetricValue { case percent(Decimal), tokens(Int64), usd(Decimal), instant(Date),
                        count(Int64), duration(milliseconds: Int64), flag(Bool), absent(AbsenceReason) }
enum AbsenceReason { case providerOmitted, providerNull, notExposedBySource, rejectedBySanitizer }
```

How absence reads in the interface: `providerOmitted` and `notExposedBySource` show as "Not available";
`providerNull` as "Not reported yet"; `rejectedBySanitizer` as "Couldn't read last update". "Not connected" comes from
the connection's state, never from an observation. The resolution order is connection first, then absence reason,
then freshness (`Sources/DesignSystem/State/States.swift`).

An `Observation` is one ledger entry: account, connection, subject (`.pool(id)` for an account-level allowance or
`.session(id)` for one session), optional model id, `MetricKind`, `MetricValue`, `observedAt` (when the source
measured it), `receivedAt` (when the app ingested it), evidence, quality, the source's version string, and a
`dedupeKey` (§6.2). Metric kinds cover limits (`quotaUsedPct`, `resetAt`), context (`contextUsedPct`, `contextTokens`,
`contextWindowSize`), tokens and cache (`requestInputTokens`, `requestOutputTokens`, `cacheReadTokens`,
`cacheCreationTokens`, `sessionOutputTokens`, `cacheHitPct`, `cacheRequests`, `cacheMisses`, `cacheWarm`), cost
(`apiCostUSD`), and activity (`wallDuration`, `apiDuration`, `linesAdded`, `linesRemoved`).

### 2.4 Derived projections

`LimitState` is `unknown`, `available`, `approaching(warning | critical)`, `exhausted`, `paidOverage` or
`resetExpected`. `Freshness` has two tiers only: `live` and `stale(age:)` (plus `never` when nothing was measured).

`PoolSnapshot` is the rebuildable view of one allowance pool: used %, reset time (each with its provenance), state,
the last known state (kept while the provider omits the window), last measured and last seen instants, when the
provider started omitting the window, the high-water mark in the current window (for crossing detection), and a
monotonic version. `SessionSnapshot` holds a session's context and token figures the same way.

### 2.8 Events and receipts

The engine emits events (`windowOpened`, `thresholdCrossed`, `exhausted`, `readyAgain`, `resetExpected`,
`staleSource`, among others) into `derived_events`. `notification_receipts` records which events led to a
notification decision, so a rebuild never notifies twice. Limit notifications themselves are not implemented yet.

## 3. SQL schema

SQLite through GRDB, one writer (the app), file `~/Library/Application Support/Clepso/clepso.sqlite`. Tables created by
migration v1 (`Sources/Storage/SchemaV1.swift`):

| Group | Tables |
|---|---|
| Identity | `accounts`, `connections`, `sessions`, `allowance_pools` |
| Ledger | `observations` (append-only; UNIQUE `dedupe_key`) |
| Projections | `pool_windows`, `pool_snapshots`, `session_snapshots`, `derived_events` |
| Notifications | `notification_receipts`, `alert_suppressions` |
| Plans | `subscription_identities`, `plan_catalog_versions`, `entitlements`, `entitlement_pool_links` |
| Reserved for later features | `reset_schedules`, `calendar_sync_receipts`, `devices`, `sync_cursors` |
| Operations | `connector_health`, `preferences` |

Instants are `INTEGER` epoch milliseconds (UTC). Projections store a JSON snapshot with a schema version.

### 3.1 Migration v3: agents per task

`agent_tasks(id, connection_id, session_ref, started_at, ended_at, from_prompt)`: one row per prompt; `from_prompt` is
0 when a subagent arrived before Clepso saw a prompt for that session. `agent_runs(task_id, agent_ref, agent_type,
started_at, stopped_at)`, primary key `(task_id, agent_ref)`, with `agent_type` limited to Claude Code's built-in
names plus `custom` and `unknown` (since v4, also an approved custom agent name: §3.2). A prompt closes the session's open task and opens a new one; `Stop` closes the
latest open task; a subagent joins the session's latest task that started before it; a run is matched by
`agent_ref`, so a stop that arrives before its start still makes one run. Purged with sessions at 30 days.

Running now (derived, never stored; `Store.openAgentRuns`, `OverviewProjection.agents`): a run with no stop is running,
whichever task started it, so a background subagent that outlives its prompt still counts; it stays with the task that
started it. Claude Code sends nothing while a subagent works, so its last sign of life is the newest hook event from
its session; after 10 minutes without one (the telemetry TTL) it is shown as "last seen". A run with no stop stops
counting as running 6 hours after it started (Claude Code closed or crashed, or a hook event was lost) and is shown
as "no stop seen" in its task, neither finished nor running.

### 3.2 Migration v4: approved agent names

`agent_runs` is rebuilt (rows copied unchanged) so `agent_type` may also hold a custom agent name the user approved in
Settings (founder decision 19 Oct 2026): its CHECK allows the built-in names, `custom` and `unknown`, or 1–40
characters of `A–Z a–z 0–9 _ -` and nothing else, so no sentence or path can be stored whatever arrives. The approved
list itself is the preference `claudeCode.approvedAgentNames`. Taking a name off the list rewrites its runs to `custom`
(`Store.forgetAgentName`). The account sync counts approved names under `custom`, so they never leave the Mac.
The same list names Codex's agent roles (sheet item 10); Codex is read in the app and its roles are never stored.

### 3.3 Migration v5: background reports (sheet item 9, 19 Oct 2026)

`Stop` and `SubagentStop` frames carry Claude Code's in-flight background work as counts (`docs/specs/hook-frame.md`,
PRIVACY_AND_SECURITY §4.2). `agent_background(session_ref, connection_id, reported_at, event)` keeps one row per
session: its latest **exact** report, from a `Stop`, or from a `SubagentStop` while none of the session's prompts was
in progress (during a prompt a foreground subagent isn't on Claude Code's list, so such a report is not kept). An older
report never replaces a newer one. `agent_background_counts(session_ref, task_type, agent_type, status, count)` holds
its counts: `task_type` one of `shell subagent monitor workflow teammate cloud_session mcp_task other`, `status` one of
`running pending other`, `count` 1–9999, and `agent_type` `''` for the per-type rows or, for subagents, a built-in
name, `custom` or an approved name (same shape CHECK as `agent_runs`). Counts cascade with their report. Purged at 30
days; in export and delete-all. Taking a name off the list folds its counts into `custom`.

Running now with a report (`Store.backgroundSnapshots`, `OverviewProjection.agents`): of a session's subagents that
started before its report, exactly as many of each type run as the report listed, less the stops received at or
after it (a background subagent is still listed at its own `SubagentStop`); extra open runs are "no stop seen", and a
shortfall is shown as running with its start not seen. Subagents started after the report, and sessions without one,
use the start-and-stop rule above.

**Before the rename to Clepso** the folder was `~/Library/Application Support/Pulse` and the file `pulse.sqlite`. At
launch, before the database, the diagnostics log or the socket is opened, `LegacyDataMigration`
(`Sources/ClepsoApp/System/LegacyDataMigration.swift`) renames the folder (never over an existing `Clepso` folder:
then the old one is left in place and noted in the diagnostics log), then `pulse.sqlite`'s `-wal`, `-shm` and `-journal`
companions and finally `pulse.sqlite` itself to `clepso.sqlite`, and the pre-migration copies
`pulse.sqlite.pre-*.bak` to `clepso.sqlite.pre-*.bak`. Each step is a `rename(2)` in one folder and is repeated at the
next launch until done. If another copy of the app still listens in the old folder, or a rename fails, nothing more
moves and the database stays closed for that launch.

## 4. Migration policy

1. GRDB `DatabaseMigrator`, forward-only, named `v<N>_<slug>`, never edited after release.
2. Additive first: new columns are nullable or defaulted.
3. The ledger is sacred: no migration reinterprets `observations` rows; a new encoding adds a value kind.
4. Projections are disposable: they can be truncated and rebuilt (§9). Receipts are never truncated.
5. Backup before migrate: when a pending migration would touch an existing database, Clepso first writes a
   `VACUUM INTO` copy beside it. Delete all removes those copies.
6. Every migration has a test; v2 is checked row for row (every row and rowid kept).

Applied: `v1_initial`; `v2_value_kinds_count_duration_flag` (adds the `count`, `duration` and `flag` value kinds);
`v3_agent_tasks` (§3.1); `v4_agent_type_approved_names` (§3.2); `v5_agent_background` (§3.3).

Retention: limit readings and engine events 90 days; sessions, agent tasks and notification receipts 30 days;
diagnostics 7 days. It runs at launch and daily. A session row goes only once no reading references it.

## 5. Session-to-pool resolution

The Claude Code status line carries a session id, the model, context figures and optional `rate_limits.five_hour` /
`seven_day` (used % and reset time). It carries **no account identifier and no timestamp**.

- A pool is keyed by `(account, providerPoolKey)`, never by session, so two concurrent Claude Code sessions report
  into the same pool row, and ordering (§6) decides, never a sum.
- Claude Code pools are `claude-code.rate_limits.five_hour`, `.seven_day` and `.spend_limit`. Codex pools are
  `codex.rate_limits.five_hour` and `.seven_day` (windows of 300 and 10,080 minutes), or `window_<n>m` for other lengths.
- Context and token figures are session-scoped and never aggregated across sessions.

### 5.1 Frame-to-observation mapping

Input is a frame v1 from the helper (field list: `docs/PRIVACY_AND_SECURITY.md` §4). Every observation carries
`observedAt` = the helper's read time (`emitted_at_ms`), `receivedAt` = ingest time, evidence
`officialLocalTelemetry`, the source version and the model id. Quality is `reported` for values, `unknown` for
absences and `estimated` for the cost estimate. A JSON `null` becomes `.absent(.providerNull)`.

| Frame field | Subject | Metric kind | When the key is missing |
|---|---|---|---|
| `rate_limits.five_hour.used_pct`, `rate_limits.seven_day.used_pct` | pool | `quotaUsedPct` (`.percent`) | `.absent(.providerOmitted)`, also when the window or the whole `rate_limits` object is missing |
| `rate_limits.<window>.resets_at` | same pool | `resetAt` (`.instant`, epoch seconds) | `.absent(.providerOmitted)` |
| `rate_limits.spend_limit.used_pct`, `.resets_at` | pool `…spend_limit` | `quotaUsedPct`, `resetAt` | nothing emitted |
| `context.used_pct` | session | `contextUsedPct` | nothing emitted |
| `context.total_input_tokens` | session | `contextTokens` | nothing emitted |
| `context.window_size` | session | `contextWindowSize` | nothing emitted |
| `context.current_usage.*` (input, output, cache read, cache creation) | session | `requestInputTokens`, `requestOutputTokens`, `cacheReadTokens`, `cacheCreationTokens` | nothing emitted; `current_usage: null` gives four `.absent(.providerNull)` |
| `cost_usd_estimate` | session | `apiCostUSD` (`.usd`, quality `estimated`) | nothing emitted |
| `context.total_output_tokens` | session | `sessionOutputTokens` | nothing emitted |
| `activity.wall_ms`, `activity.api_ms` | session | `wallDuration`, `apiDuration` | nothing emitted |
| `activity.lines_added`, `activity.lines_removed` | session | `linesAdded`, `linesRemoved` | nothing emitted |
| `prompt_cache.hit_ratio` | session | `cacheHitPct` (ratio × 100) | nothing emitted |
| `prompt_cache.requests`, `.misses` | session | `cacheRequests`, `cacheMisses` | nothing emitted |
| `prompt_cache.warm` | session | `cacheWarm` (`.flag`) | nothing emitted |

`model.*` and session settings (effort, thinking, fast mode) are stored on the session row, not as metrics. A frame
without `session_ref` (the helper had no key) yields pool observations only; its session observations are dropped
and counted. Numbers convert to `Decimal` through their shortest decimal text, so `0.0412` stays exactly `0.0412`. A
frame whose `emitted_at_ms` is more than 5 minutes from arrival is flagged (§8 rule 8).

Known limit of frame v1: a value the helper scrubbed arrives as `null`, indistinguishable from a provider `null`;
only `health.scrub_count` reveals that something was scrubbed.

## 6. Ordering, deduplication and windows

### 6.1 Latest-wins ordering

Per pool and metric kind, the snapshot holds the observation with the greatest
`(observedAt, evidence priority, receivedAt, rowid)`. Older arrivals are kept for history but never win. Values are
never summed.

### 6.2 Dedupe key

`dedupeKey = sha256(connectionID | subject | metricKind | canonical(value) | observedAt_ms | sourceVersion)`, with the
subject written as its provider key. A UNIQUE index drops double delivery silently. The status line has no event id,
so a content hash is the only stable identity.

### 6.3 Windows

The reducer owns window identity, and window ids are derived (never random), so a rebuild reproduces them:

- A new window opens when the pool has none, when a fresh reset time differs from the current window's by **more than
  15 minutes**, or when a qualifying reset is observed (§7.1 G6).
- Within that tolerance the reset time is updated in place and the window's version increases.
- A pool that never reports a reset time keeps one window until a qualifying decrease.

### 6.4 What the ledger keeps

Claude Code refreshes its status line several times a minute and most values repeat. The store keeps a **change or a
check-in**: a pool's used % and reset time are stored together when either changes, otherwise every 120 seconds; a
session metric when it changes and 60 seconds have passed since its last stored row, otherwise every 120 seconds. A
reading older than the newest stored one is always kept (history). The reducers apply only stored rows, so live state
and a rebuild agree (tested). Check-ins every 2 minutes stay well inside the 10-minute freshness time-to-live.

## 7. State machines

Guards use: `fresh` = the observation is within the time-to-live (10 minutes for local telemetry), thresholds warning
80, critical 95, exhausted 100, hysteresis 3 points, and the pool's current window.

### 7.1 Limit state (per pool)

| # | From | To | Guard |
|---|---|---|---|
| G1 | unknown | available / approaching / exhausted | first fresh percentage for the pool |
| G2 | available | approaching (warning) | fresh used ≥ 80 and high-water < 80 |
| G3 | available / approaching (warning) | approaching (critical) | fresh used ≥ 95 and high-water < 95 |
| G4 | below exhausted | exhausted | fresh used ≥ 100 and high-water < 100 |
| G5 | exhausted | paid overage | only with overage evidence (today: the user's confirmation) |
| G6 | exhausted / paid overage / reset expected / approaching | available | a fresh percentage observed after the window's reset time **and** a drop of at least 5 points or a value under 80 |
| G7 | approaching (critical) | approaching (warning) | fresh used ≤ 92 (hysteresis) |
| G8 | approaching (warning) | available | fresh used ≤ 77, no reset involved |
| G9 | any measured state | reset expected | the reset time has passed and no fresh percentage since |
| G10 | any measured state | unchanged, "omitted since" set | the provider stops sending a window it sent before |
| G11 | unknown | unknown | absent with no earlier measured value |
| G12 | any | unknown | connection disconnected, or the source never exposes the value |
| G13 | any measured state | unchanged, shown as stale | freshness is computed, never a transition; the stale-source event fires only when the source itself goes silent |

Threshold events fire only on an upward crossing of the window's high-water mark. G6 is the **only** path back to
"available again": 100 → 99 is not a reset.

### 7.2 Reset expectation (per window)

| From | To | Guard |
|---|---|---|
| armed (reset time in the future) | reset expected | the reset time has passed, no fresh percentage since |
| reset expected | available again | G6 |
| reset expected | reset expected | indefinitely, labelled as waiting for the next update; never flips by itself |
| armed / reset expected | armed | a new reset time within 15 minutes updates the same window; beyond it opens a new one |

The menu bar icon (founder decision, 19 Oct 2026) shows the flatline for "reset expected" only when that window reached
its limit (its high-water mark hit 100 %), and keeps it until G6. A window whose reset passed without reaching its limit
still reads "reset expected" on its card, but counts for the icon as an old reading: it can bring the clock, never the
flatline, and never outranks a live reading.

## 8. Time-handling rules

1. Storage: epoch milliseconds, UTC. No time-zone columns.
2. Display: the user's current time zone at render time.
3. For the status line, `observedAt` is the helper's read time (the payload has no timestamp), and quality is
   `reported`, never `verified`.
4. No synthetic resets: a reset time comes only from the source, never from "last event + 5 hours".
5. Freshness: `live` while age < time-to-live, `stale` after. Local telemetry: 10 minutes.
6. Daylight-saving changes alter text, not stored bytes.
7. Implausible reset times: the helper drops a whole limit window whose `resets_at` is earlier than one day ago or
   later than 400 days ahead (`FrameBuilder.isPlausibleTransportEpoch`), so the app sees that window as omitted.
   Values of the wrong type become `.absent(.rejectedBySanitizer)`.
8. Clock skew: when `receivedAt − observedAt` exceeds 5 minutes, the frame is flagged and arrival time is trusted.
9. Monotonic versions order snapshots and windows; timestamps order observations only.
10. `resets_at` is integer Unix epoch seconds (observed on Claude Code 2.1.302).

## 9. Snapshot rebuild

Projections are a pure function of the ledger. A rebuild truncates `pool_snapshots`, `session_snapshots`,
`pool_windows` and `derived_events` (receipts untouched), then, for each pool, replays its observations **in arrival
order** (`received_at`, then rowid), reducing each frame's group with the clock it had when it arrived, and finally
applies the reset-expectation and freshness checks at the current time. Arrival order matters: live ingest sees a
late, older sample after a newer one, and latest-wins ignores it; replaying in measurement order would leave
different bookkeeping. Tests check that rebuild equals live state.
