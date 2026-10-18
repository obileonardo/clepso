# Privacy and security design

What Clepso reads, what it keeps, what can leave the Mac, and how it protects the files it touches. Section numbers are
stable: code comments cite them (for example `PRIVACY_AND_SECURITY §4`). To report a vulnerability, see
[`SECURITY.md`](../SECURITY.md).

## 1. Data flow and trust boundaries

```text
 provider cloud ──(Claude Code's own connection; Clepso never touches it)──▶ Claude Code
                                                                │ status-line JSON on stdin   [untrusted]
 ══ B1 process boundary, same user ═════════════════════════════▼══
 ~/.claude/pulse/statusline.sh   runs the helper if present, else the user's original command
 Clepso.app/Contents/Helpers/pulse-statusline   [no network, no disk writes]
      1. runs the user's original status-line command with the exact input bytes
      2. builds an allowlisted frame (≤ 4 KiB), session ids replaced by keyed hashes
      3. one non-blocking send within its time budget; no reply, no retry
 ══ B2 Unix socket, same-user peers only ══
 Clepso.app: peer check → rate limit → decode → map → store
      ├─▶ pulse.sqlite and diagnostics.jsonl                       ── B3 disk (this user)
      ├─▶ local notifications
      ├─▶ Export (save panel, scrubbed)                             ── B4 user-initiated
      └─▶ Sync (optional, signed-in only): daily counts over HTTPS  ── B5 network
```

B1: the payload is untrusted input. B2: only processes running as the same user may connect (§3). B3: files are
readable by the same user. B4: only when the user asks. B5: exists only in builds configured with an accounts project
and only after the user signs in (§9); builds from source have no accounts project and never use the network.

## 2. Threat model

| # | Threat | Controls | Residual risk |
|---|---|---|---|
| T1 | A process running as the user sends fake readings | Same-user peer check, 4 KiB frames, 20 frames/s, strict decoding | Such a process could already edit `~/.claude` directly. The worst outcome is a wrong reading, never a privileged action. A code-signature check of the peer is planned (§3) |
| T2 | Hostile or malformed status-line input (huge, deeply nested, paths or secrets in strings, new fields) | 1 MiB stdin ceiling (4 MiB for hooks), allowlist decoding (§4), string limits, scrubbing; the user's own status line still runs | Unknown fields are dropped, never forwarded |
| T3 | Clepso reading more than it needs (paths, transcripts, prompts) | Allowlist applied inside the helper, so the app cannot receive what it must not store; canary tests over every content field | The session cost estimate is forwarded unless the user turns it off; it is labelled an estimate |
| T4 | Corrupting the user's Claude Code settings | Byte-exact backup, compare-and-swap, atomic rename, verification, rollback, exact restore (§7) | A concurrent write by Claude Code within milliseconds is detected and rolled back |
| T5 | Symlink or time-of-check races on Clepso's folders and files | `lstat` checks, symlinks refused, `O_NOFOLLOW`/`O_EXCL`, owner and mode checks | — |
| T6 | Network exposure | Networking code only in `Sources/Sync`, imported only by the app; the helper links no networking library (both checked by `make ci`); Sync off without an accounts project | Signed-in users send daily counts (§9) |
| T7 | Another local app reads Clepso's database | File permissions and FileVault | Same-user readable; the contents are usage metrics, not secrets |
| T8 | Tampered builds | Pinned dependencies (`Package.resolved`), SHA-256-checked XcodeGen download, hardened runtime in official builds | No notarized releases exist yet |

## 3. IPC peer validation

Transport: a Unix-domain stream socket at `~/Library/Application Support/Pulse/run/agent.sock`. The folder is created
with mode 0700 and must be a real directory owned by the user; the socket is 0600; only a stale socket may be
replaced, never a file or symlink (`Sources/ClaudeCodeAdapter/IngestSocket.swift`).

Per accepted connection, today:

1. `getpeereid` must return the app's own user id; otherwise the connection is closed and counted.
2. A token bucket allows 20 frames per second.
3. At most 4 KiB is read, with a 100 ms read timeout; the frame must decode as frame v1.

Planned: verify the peer's code signature (audit token → `SecCode` → a designated requirement naming the helper's
identifier and the team). The helper is already built with an embedded Info.plist so its signing identifier is its
bundle identifier, which such a requirement can name. Until then, any process running as the same user can send a
well-formed frame (T1).

The helper does not authenticate the app: it sends only non-secret, allowlisted data, and a fake socket can at most
delay it within its time budget.

## 4. Field allowlist and scrub rules

The helper builds frame v1 from exactly these status-line paths and ignores every other key
(`Sources/ShimProtocol/Allowlist.swift`, `FrameBuilder.swift`):

| Status-line path | Treatment |
|---|---|
| `session_id` | HMAC-SHA256 with the local key, first 8 bytes as 16 hex characters (`session_ref`); the raw id never leaves the helper |
| `version`, `model.id`, `model.display_name` | Printable strings up to 32 / 64 characters, scrubbed (below) |
| `context_window.{context_window_size, used_percentage, remaining_percentage, total_input_tokens, total_output_tokens, current_usage.*}`, `exceeds_200k_tokens` | Bounded numbers and a boolean; a `null` stays `null`; values above 100% are kept |
| `rate_limits.five_hour`, `.seven_day`, `.spend_limit` (`used_percentage`, `resets_at`) | Bounded numbers; a window whose `resets_at` is outside [now − 1 day, now + 400 days] is dropped. Other window names are counted, never copied |
| `prompt_cache.{warm, caching_observed, ttl, expires_at, hit_ratio, requests, misses}` | A subset; miss causes are never forwarded |
| `effort.level`, `thinking.enabled`, `fast_mode` | Closed set of values / booleans |
| `cost.total_cost_usd` | Forwarded unless the user turns it off in Settings; always labelled an estimate, never quota |
| `cost.total_duration_ms`, `cost.total_api_duration_ms`, `cost.total_lines_added`, `cost.total_lines_removed` | Bounded integers: time and line counts only |

**Never forwarded**, by construction: `cwd`, `workspace.*`, `transcript_path`, `session_name`, `prompt_id`,
`output_style`, `vim`, `agent`, `pr`, `worktree`, the raw `session_id`, and any key not listed above, including future
ones.

**Scrub rules** (a second layer, also applied again on export): an allowlisted string is dropped (set to null and
counted) if it contains `/`, `\`, `@`, `$HOME`, a control character, or a secret shape (`sk-ant-`, `sk-` at a token
start, `AKIA`, `ghp_`, `Bearer `, or a run of 32 or more base64 characters). Numbers are range-checked; NaN, infinity
and numbers sent as strings become null.

The HMAC key is 32 random bytes generated by the installer and stored at `~/.claude/pulse/session.key` (0600), where
the helper can read it. Its only purpose is that session ids in Clepso's data cannot be linked back to Claude Code's.

### 4.1 Claude Code's statistics file (opt-in)

`~/.claude/stats-cache.json` is written by Claude Code for `/stats` and is not documented by Anthropic. Clepso reads it
only after the user turns it on, on demand, in the app (never in the helper), through an allowlist: daily message,
session and tool-call counts; tokens per model per day; per-model input, output, cache-read and cache-write totals;
total sessions and messages; the longest session's duration and message count; the first session's date; sessions per
hour of day; the file's version and last computed date. **Never read:** the longest session's id, or any other or
future field. Model ids must match `^[a-z0-9][a-z0-9.-]{0,63}$`; anything else is dropped and counted. Nothing from the
file is stored in Clepso's database, logged or exported (`Sources/ClaudeCodeAdapter/StatsReader.swift`).

### 4.2 Claude Code hooks (opt-in)

Off by default, and available only once the status line is connected. Claude Code gives each hook the whole event on
stdin, including the prompt, the last assistant message, transcript paths and the working directory. The helper
(`pulse-statusline --hook`) parses at most 4 MiB (draining the rest) and keeps only: the event name
(`UserPromptSubmit`, `SubagentStart`, `SubagentStop`, `Stop`), the HMAC of the session id, the HMAC of the agent id,
and the agent type if it is one of Claude Code's built-in types (`general-purpose`, `Explore`, `Plan`,
`statusline-setup`, `claude-code-guide`), otherwise `custom`. It always exits 0 with nothing on stdout or stderr, so it
can never block Claude Code or add context to a conversation. The installed hook command is a no-op if the app is
gone. Stored as `agent_tasks` and `agent_runs` (`docs/DATA_MODEL.md` §3.1), kept 30 days, included in export and
delete all. Tests put canary markers in every content field of all four events and check none reaches the socket.

### 4.3 Codex session files (opt-in)

Off by default. Clepso lists `~/.codex/sessions/<year>/<month>/<day>/rollout-*.jsonl` for the last 8 days and reads
only the last 256 KB of the three newest files. It decodes only lines that are `token_count` events (5-hour and
weekly used %, reset time, plan) and the turn's model name; every other line, including prompts and replies, is
skipped before JSON decoding (`Sources/CodexAdapter/`).

For Codex's tokens per day (Stats), Clepso also reads every session file under `~/.codex/sessions` once, in the
background, and then only what Codex appends. The same rule holds: a line is decoded only when its bytes contain
`"token_count"` or `"turn_context"` and it is at most 16 KB; prompts, replies, paths and every other line are skipped
undecoded. It keeps only each day's token counts per model, in memory: nothing from these files is stored, logged,
exported or uploaded. Turning Codex off drops them.

Codex's agents per task (Session page) come from the same pass and decode nothing at all
(`Sources/CodexAdapter/CodexAgents.swift`). The lines they need hold private text too: a thread's first line
(`session_meta`) carries Codex's instructions, the working folder, git details and account ids, and a turn's
`task_complete` carries the final reply. So instead of decoding such a line and dropping most of it, Clepso looks up a
few keys by their bytes and reads only short plain values: a string of at most 64 letters, digits and `._:+-`, an
integer, or null; a value with an escape, a space or any other character is refused. An unescaped `"key":` can only be
a JSON key, because quotes inside strings are escaped, so text in a prompt or reply can't pass for one. Event lines are
searched only in their first 512 bytes, where Codex writes their type and ids. Read: the event type, turn ids with their
parent and root turn ids, the turn's trigger, timestamps and line numbers, whether a thread is a spawned agent, and the
agent's role (Codex's built-in role names; any other role is kept only as "custom"). Never read: prompts, replies,
instructions, paths, git details, account ids, agent nicknames and agent paths. Kept, in memory only like the token
counts: each task's times, its agents by role, how many finished and how many auto-reviews ran. They are not synced.

## 5. Logging and redaction

Never logged: raw status-line input, the original status line's output, environment variables, the home folder or
user name, the contents of `settings.json` (only its SHA-256), raw session ids, or frames. The diagnostics log
(`diagnostics.jsonl` in the data folder) keeps at most 1 MB and 7 days and can be cleared in Settings.

`Redacted<T>` (`Sources/Domain/Redacted.swift`) wraps values that must never reach a log or export in clear: its
description is `<redacted:label>`, it is deliberately not `Codable`, and `unsafeReveal(reason:)` is the only way out.
`make ci` fails if `unsafeReveal` is called outside `Storage` and the helper, or if `Redacted` gains a `Codable`
conformance.

## 6. Retention

| Data | Kept |
|---|---|
| Limit readings and engine events | 90 days |
| Sessions and their readings | 30 days |
| Agent tasks and runs | 30 days |
| Notification receipts | 30 days |
| Diagnostics log | 7 days, at most 1 MB |
| Settings backups (`~/.claude/pulse-backups/`) | Until the user deletes them (an option in Delete all) |
| Pre-migration database copies | Removed by Delete all |

Retention runs at launch and then at most once a day.

## 7. Changing `~/.claude/settings.json` safely

Install (`Sources/ClaudeCodeAdapter/SettingsInstaller.swift`):

1. Read the bytes and their SHA-256. Refuse if the file is not valid JSON, or if an existing `statusLine` is not a
   command Clepso can wrap.
2. Back the bytes up to `~/.claude/pulse-backups/` (0600, exclusive create, no symlinks) and append to
   `manifest.jsonl`.
3. Write the original `statusLine` verbatim to `~/.claude/pulse/original-statusline.json` (0600) and the wrapper
   `~/.claude/pulse/statusline.sh` (0700): it runs the helper if it exists, otherwise the original command (or exits 0
   if there was none).
4. Change only the value of `statusLine.command` (or add a `statusLine` member); every other byte stays.
5. Compare-and-swap: re-read and require the same SHA-256, write a temporary file with the original mode, rename it
   over the original, then re-read and verify; on failure write the original bytes back.

An install record (`install-state.json`) is updated after each step, so `pulse recover` (or the app) can finish or roll
back an interrupted install without guessing.

Removal restores the **original bytes exactly** when nothing else changed; otherwise it replaces only Clepso's status
line with the original one and says so. The hooks installer (§4.2) follows the same rules, adds its entries after the
user's own hooks, and removes only its own entries.

## 8. Export and delete all

**Export my data** writes one JSON file (0600) through a save panel: the tables `accounts`, `observations`,
`pool_snapshots`, `sessions`, `notification_receipts`, `preferences`, `agent_tasks` and `agent_runs`, with a header
(schema version, export time, app version, retention). Internal dedupe hashes are left out; every string is checked
again with the §4 scrub rules, and one that fails is exported as null and counted.

**Delete all** asks for confirmation, then: removes pending notifications; removes the hooks entries and restores
`settings.json` (and stops, deleting nothing, if that cannot be done safely); deletes `~/.claude/pulse/`; signs out of
the optional account on this Mac; deletes Clepso's Keychain items; deletes the database, its pre-migration copies, the
diagnostics log and the socket; optionally deletes the settings backups; and relaunches into first-run state. Files
in the data folder that Clepso did not create are left and named.

## 9. Optional accounts (Sync)

Sync is the only code that uses the network. It does nothing unless **both** are true:

1. The build carries an accounts project (`PulseSyncHost` and `PulseSyncPublishableKey` in Info.plist, from the
   uncommitted `Config/Sync.local.xcconfig`). Builds from source have none, so Sync is off: the Account page explains
   this, Home never suggests signing in, and no request is ever made (tested).
2. The user signs in with a one-time email link (PKCE; the verifier stays in this Mac's Keychain).

When signed in, Clepso uploads once an hour, and never while demo data is showing: the profile name and plan label;
per day: messages, sessions, whether the day was active, tokens per model, the 5-hour peak and 7-day end percentage,
agents per task by built-in type, goal targets and results; per model: total tokens by kind. No prompts, replies,
paths, project names or raw ids. The session is stored in the Keychain (this device only); requests use an ephemeral
session with no cookies or cache. The backend schema (`backend/supabase/migrations/`) forces row-level security on
every table so a user's token reaches only that user's rows, grants nothing to anonymous callers, and deletes every row
when the account is deleted. The publishable key in an official build identifies the project and grants nothing by
itself; no secret key is ever in the app (the app refuses `sb_secret_…` keys).

A sign-in link's own error text is never displayed, because any app can open the `dev.tokone.pulse://` URL scheme.

### 9.1 Web dashboard (`/app`)

A static page on the docs site (`scripts/site/app.js`, no libraries) that reads the signed-in user's own rows and can
sign out or delete the account. It talks only to Supabase Auth and REST with plain `fetch`. Its project URL and
publishable key come from `site/app/config.js`, generated at build time from `Config/Sync.local.xcconfig` and
gitignored; without it the page says accounts aren't configured and makes no request. Sign-in is the same email link
with PKCE: the verifier stays in that browser's `localStorage`, so a link works only in the browser that asked for it;
the returned `?code=` is exchanged at once and removed from the address bar. The session is kept in `localStorage`
(as supabase-js does), so the page loads no third-party script and sets a Content Security Policy (scripts from the
site only; connections to the site and `*.supabase.co`) and `no-referrer`. As on the Mac, an error in a returned link
is shown in the page's own words, never the link's text. Deleting the account asks the user to type DELETE first.

## 10. Entitlements

The app has no sandbox (it must read and edit files under `~/.claude`), no network entitlement and no exceptions;
debug builds add only `get-task-allow`. Hardened runtime is on for every target in official builds. `make ci` asserts
the entitlements, the embedded helper's identifier, and that the helper links no networking library or symbol.
