# mod-bridge.md: plan limits from the Claude desktop app and the VS Code panel

| | |
|---|---|
| **Date** | 2026-10-19 |
| **Release** | v0.3.0-alpha "Claude, everywhere" (branch `feat/v0.3-claude-everywhere`) |
| **Status** | Built behind `ReleaseFeatures.claudeMod` (off in release builds) until the first live install (`docs/runbooks/v0.3-live-mod-test.md`) passes |
| **Normative source** | `mod/claude-code/` (the mod), `Sources/ShimProtocol/ModHandoff.swift` (hand-off allowlist), `Sources/StatusLineShim/StatusLineShim.swift` `modMain`, `Sources/ClaudeCodeAdapter/ClaudeModInstaller.swift`, `Sources/UsageEngine/PoolReducer.swift` (one source per window) |
| **Builds on** | `statusline-shim.md` (frame v1, §6), `hook-frame.md`, `PRIVACY_AND_SECURITY.md` §4 and §7, the 19 Oct mod test (planning docs `DESKTOP_AND_IDE_LIMITS.md` §0, `evidence/mod-spike-19oct/`) |

Labels: **[V]** verified (an official page fetched on 19 Oct 2026, the local Claude Code 2.1.303 CLI or its type
declarations, or an experiment run for this spec), **[I]** inference, **[?]** unknown until the live test.

If this file and the code disagree, the code wins and this file is corrected.

---

## 1. In one minute

- Claude Code's **status line** gives Clepso the plan limits in the terminal. The Claude desktop app's Code tab and
  the VS Code chat panel don't run it, so Clepso sees their tasks (hooks) but not their limits.
- A Claude Code **mod** does get the limits there: on 19 Oct a throwaway mod read `five_hour` 26 → 27 % and
  `seven_day` 70 % in the desktop Code tab [V spike].
- Clepso ships a mod of its own, `clepso-limits`. It has one hook (`session.measure`, after each turn), and from
  sessions that **no terminal draws** it hands Clepso's existing helper the limit percentages, reset times,
  context-window numbers and the session's model id (as the status line's `model.id`). The helper stays the only
  allowlist gate and sends a normal frame v1 with two extra optional fields (`via: "mod"`, `surface`).
- Opt-in, with its own consent screen. Clepso writes **two entries into `~/.claude/settings.json` itself**
  (`extraKnownMarketplaces.clepso`, `enabledPlugins["clepso-limits@clepso"]`), with the status-line installer's
  guarantees: backup, compare-and-swap, verify, and an exact byte restore on removal. It does not use
  `claude plugin install`, because that rewrites the whole file and changed an unrelated setting in our test (§3.1).
- No double counting: terminal sessions are skipped by the mod, and when a status line and the mod both report a
  limit, the status line holds that window for 60 s (§7).
- Where an organisation or the user turns mods off, nothing breaks: Clepso keeps "tasks yes, limits no" there and
  says so (§8).

---

## 2. Findings (Phase 1)

### 2.1 Where mods run, and what they receive

| # | Finding | Label | Source |
|---|---|---|---|
| F1 | "Mods work in the Claude Code CLI, the Code tab of the Claude Desktop app, and the VS Code extension." Hooks run in the Code tab (not in WSL sessions), the VS Code chat panel, `claude -p`/Agent SDK, and Remote Control. | V | https://code.claude.com/docs/en/plugins/mods/overview ("Where mods run") |
| F2 | Mods are on by default from 2.1.287 (terminal) and 2.1.286 (desktop app). Installed here: CLI 2.1.303, desktop app's bundled Claude Code 2.1.299. The founder's only Claude Code IDE extension (2.1.92, in Cursor) is too old. | V | same page; `claude --version`; DESKTOP_AND_IDE_LIMITS E9 |
| F3 | `session.measure` fires "after each turn, and when a plan limit's percent used changes". Its event carries `context` (`tokens`, `window`, `percent`) and `rateLimits` (`{ kind, percentUsed, resetsAt? }`), and `changed`. So the mod needs no `$.session.usage()` call. | V | 2.1.303 type declarations (`SessionMeasureInput`), written by the built-in `plugin-authoring` skill; https://code.claude.com/docs/en/plugins/mods/reference |
| F4 | `kind` is `five_hour`, `seven_day` or a gateway's `spend_limit`; `percentUsed` 0–100 "with at most one decimal"; `resetsAt` ISO 8601. `context.tokens` is "the status line's `total_input_tokens`", `window` its `context_window_size`, `percent` its `used_percentage` (whole). | V | 2.1.303 types (`SessionRateLimit`, `SessionContextUsage`) |
| F5 | In the desktop Code tab `surfaces` is `[]` at `session.start` and `["desktop"]` at `session.measure`; `rateLimits` is empty until the first reply. Only `five_hour` and `seven_day` arrived. | V | spike records `desktop-code-tab.json`, `terminal.json` |
| F6 | `$.session.surfaces()` returns each app drawing the session (`terminal`, `desktop`, `mobile`, `vscode`), "empty in a plain -p run". `$.session.id()` is "the session's id (the transcript file's name)". | V | 2.1.303 types |
| F7 | The mod's session id equals the status line's and the hooks' `session_id` (both are the transcript's name). | I | F6 + hooks/status-line docs; checked in the runbook |
| F8 | `$.process.run(argv, { cwd, env, stdin, timeoutMs })` runs a program by argument vector, no shell of its own, and resolves `{ exitCode, stdout, stderr }` for any exit code; it rejects if the program can't start or outlives the timeout (30 s default, 10 min max). The type comment says "CLI only". | V | 2.1.303 types (`ProcessRunInit`); https://code.claude.com/docs/en/plugins/mods/api |
| F9 | "CLI only" means the Claude Code engine (the desktop app and the VS Code extension each run their own copy of it), not "the terminal only". The spike's `$.fs.write`, which the same comment block calls "the engine's own process", worked in the Code tab. | I | F2, F5; must be confirmed live (runbook step D3) |
| F10 | VS Code panel: mods' hooks run there; drawing needs extension 2.1.299+ and feature-flag fetching. Our mod draws nothing. Whether the panel runs the `statusLine` command is undocumented. | V / ? | overview "Where mods run"; https://code.claude.com/docs/en/vs-code |
| F11 | `session.measure` carries no model. `$.session.model()` "Returns the main loop's model, as `/model` shows it" (a string); the docs list the model among what `$.session` gives. In the 2.1.303 engine it answers the host's `mainLoopModel`, which is the alias resolved to a full id (`opus` → `claude-opus-5-5`, plus `[1m]` for that variant); the status line's `model.id` is the same value (`Kg({ mainLoopModel, permissionMode })`, which differs only in plan mode under `opusplan`). No mod call gives the status line's `display_name`. | V (types, docs); V (2.1.303 binary, read 19 Oct); ? (the desktop app's value, runbook D5) | 2.1.303 types (`session.model`); https://code.claude.com/docs/en/plugins/mods/api ("Reach files, processes, and the network"); `strings` of the 2.1.303 binary |

### 2.2 (a) The supported install route, and how to remove it exactly

| # | Finding | Label | Source |
|---|---|---|---|
| R1 | "A mod installs as a plugin, from a marketplace." A marketplace can be a local directory holding `.claude-plugin/marketplace.json`. | V | mods overview; https://code.claude.com/docs/en/plugins/install ("Add a marketplace") |
| R2 | User-scope installs record `enabledPlugins` in `~/.claude/settings.json`; "The terminal, the desktop app's local sessions, and the VS Code extension on one computer read the same settings files, so a plugin you install at user scope in any of them is available in the other two." | V | plugins/install ("Choose an install scope") |
| R3 | `extraKnownMarketplaces` (scope "any file") takes a `directory` source with an absolute `path`; "Claude Code registers each marketplace it doesn't already know." The CLI's `marketplace add` writes the same key to user settings. | V | https://code.claude.com/docs/en/settings-reference (`extraKnownMarketplaces`); experiment E-A below |
| R4 | At session start Claude Code loads plugins from `installed_plugins.json` and its cache; "After the session starts, Claude Code checks the declared marketplaces in the background: a marketplace that settings declare but `known_marketplaces.json` lacks: Claude Code clones it, then reloads plugins and downloads enabled plugins that aren't cached yet." A relative-path plugin in a local-path marketplace "loads in place", and "needs no install record because it loads from the marketplace itself". | V | https://code.claude.com/docs/en/plugins/loading |
| R5 | This is the same pair of keys an organisation uses to deploy its own mods (in managed settings). | V | https://code.claude.com/docs/en/plugins/mods/admin ("Install your organization's mods") |
| R6 | Removing the plugin's `enabledPlugins` entry stops it: `claude plugin list` then reports it `"enabled": false`. Claude Code's own records (`known_marketplaces.json`, `installed_plugins.json`, a cache copy) stay until Claude Code or the user clears them. | V | experiment E-C |
| R7 | `claude plugin marketplace remove <name>` "uninstalls every plugin you installed from it and removes their `enabledPlugins` entries"; uninstalled versions get an `.orphaned_at` marker and are deleted 14 days later. | V | plugins/install, plugins/loading; experiment E-A |

**Experiments** (19 Oct 2026, Claude Code 2.1.303, all under a temporary `HOME` and `CLAUDE_CONFIG_DIR` in the
session's scratch folder, with `DISABLE_AUTOUPDATER=1` and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`):

- **Isolation [V].** SHA-256 of the real `~/.claude/settings.json` and every `~/.claude/plugins/*.json` was the same
  before and after. A controlled run (marker file, isolated `claude plugin list` and `marketplace list`, then
  `find ~/.claude -newer marker`) found only this session's own transcript changed. Files that changed earlier
  (`remote-settings.json`, `policy-limits.json`, `sessions/<pid>.json`) were written by the running interactive
  sessions, one minute before the first isolated command.
- **E-A, the CLI route [V].** `claude plugin marketplace add <dir>` and `claude plugin install clepso-limits@clepso`
  both succeeded (`--json`: `"outcome":"ok"`), wrote `known_marketplaces.json`, `installed_plugins.json` and a cache
  copy, and **rewrote the whole `settings.json`**: 4-space indent became 2, keys were reordered, and the unrelated
  `"model": "opus"` became `"opus[1m]"`. `claude plugin uninstall` plus `marketplace remove` left
  `"enabledPlugins": {}` and `"extraKnownMarketplaces": {}` behind, kept the rewrite, and the SHA-256 never returned to
  the original (`1b8488ee…` before, `8e16291c…` after).
- **E-B, keys already present [V].** With both entries already in the file, the CLI commands still re-serialised it.
  So any CLI write re-formats `settings.json`.
- **E-C, keys only [V].** With only the two entries written by hand, the read-only `claude plugin list` and
  `marketplace list` don't register the marketplace (that happens in a session, R4) and leave the file's bytes alone.
  After removing the entries again, the plugin showed `"enabled": false`.

**Decision.** Clepso writes the two documented settings entries itself (R3, R4, R5), with the same byte-preserving
scanner, backup, compare-and-swap, verification and exact restore as the status line and hooks (§9). Why not the CLI:

| | Clepso writes the entries (chosen) | `claude plugin install` |
|---|---|---|
| Supported | Yes: documented keys and loading rules (R2–R5) | Yes |
| Other bytes of `settings.json` | Unchanged | Whole file re-serialised, an unrelated value migrated (E-A) |
| Exact restore | Byte-identical when nothing else changed | Not possible through the CLI (E-A) |
| Needs the `claude` CLI | No (desktop-only users may not have it, and a GUI app has no shell `PATH`) | Yes |
| First activation | In the next session, after Claude Code's background registration, possibly after one more session or `/reload-plugins` [I, R4] | Next session [V docs] |
| Leftovers after removal | Claude Code's own records stay, plugin disabled (R6) | Cache copy for 14 days (R7) |

The uninstall leftovers are Claude Code's files, not settings: Clepso never edits them (they are undocumented
formats). The runbook checks what `/plugin` shows after removal; if Claude Code reports the missing marketplace as an
error, the remedy is `claude plugin marketplace remove clepso` (open question Q2).

**Behaviour per app.** Same settings files everywhere (R2), so one install covers the terminal, the desktop app's
local and SSH sessions, and the VS Code extension. Not in desktop cloud or WSL sessions (no plugins there [V
desktop docs]). The desktop app shows and toggles it under **+ › Plugins › Manage plugins**, VS Code under `/plugins`
[V]. The mod draws nothing, so every surface behaves the same.

### 2.3 (b) The API calls, and what "permission" means for a mod

There is no permission manifest: "Mods aren't sandboxed" and run "with your permissions" [V overview]. What a mod may
do is what its code calls, and `claude plugin validate` lists those calls statically; Claude Code "refuses to load a
mod that uses the mods API in a way this command can't read" [V admin]. Clepso's mod, validated with
`claude plugin validate --strict` (output saved in §11):

```text
  ❯ ./register.js hooks: session.measure
  ❯ ./register.js calls: $.process.run, $.session.id, $.session.model, $.session.surfaces, $.session.version
✔ Validation passed
```

- No `tool.call`, `prompt.submit`, `session.append` or `ui.*` hook: it never sees a prompt or tool call.
- No `$.fs`, `$.http`, `$.env`, `$.settings`, `$.model` (the completion calls), `$.store`, `$.session.messages`.
- `$.session.model` (added 19 Oct 2026, founder decision Q4) only reads the session's model id, so a desktop or VS Code
  session is labelled like a terminal one; it makes no request.
- `$.process.run` is the one powerful call. Its `argv` is a fixed string (§5.1), it gets the JSON on `stdin`, and
  a 5 s `timeoutMs`.
- `make ci` fails if the `hooks:` or `calls:` line ever changes (gate "Claude Code mod").

### 2.4 (c) When mods are off

| Setting or situation | Effect on Clepso's mod | Status line and hooks | Label |
|---|---|---|---|
| `allowManagedModsOnly` (managed `pluginConfigs` option on `cc-plugin-sec-default@builtin`) | Refused at load: debug log `refused by cc-plugin-sec-default: mods are limited to your organization's by policy (allowManagedModsOnly)` | Keep running ("Users' other customizations keep working: their hooks … status lines") | V admin, troubleshoot |
| `disableAllHooks: true` in the user's own settings | Stops "the mods you installed" | **Also off**: "any custom status line" and hooks | V settings-reference |
| `disableAllHooks` in managed settings | Every installed plugin's mod stops | Off | V |
| `allowManagedHooksOnly` (managed) | Not loaded (`only managed plugins and built-in plugins run`) | User hooks blocked; `statusLine` read from managed settings only | V |
| `--safe-mode`, `--bare` | Installed mods off for that session | — | V |
| Anthropic's remote rollout switch off | `hooks modules are turned off for installed plugins in this process: the rollout switch served off` | Keep running | V troubleshoot |
| Untrusted folder | No mod loads until the trust prompt is answered | Hooks: same trust rule | V admin |
| WSL session in the desktop app | No plugins | — | V |
| Workspace user signed in with Team/Enterprise | The built-in guard `sec-default` loads first; it only protects managed configuration, so this mod (no `tool.check`, no managed targets) is unaffected | — | V admin; the spike ran on a Team plan |

`claude plugin test`, run from a folder without a mod, reports `hooks modules are turned off here` when
`disableAllHooks` or a policy blocks mods; it does not report `allowManagedModsOnly` [V troubleshoot]. Clepso cannot
read managed settings delivered by MDM or the admin console (`statusline-shim.md` §8), so it infers (§8).

### 2.5 (d) One source per window

- Limits are per account, not per session: every session reports the same shared windows [V Help Center, desktop
  docs]. Clepso's pools are keyed by account and window and reduced latest-wins, never summed (DATA_MODEL §5, §6.1), so
  two sources can't add up. The risk is two sources taking turns: two readings of the same window from different
  sessions, each as of its own last API response.
- On 19 Oct the mod read 27 % at 11:31:33 in the desktop session while Clepso's status line showed 26 % at 11:32 from a
  terminal session. Both are plausible readings of the same window at different last responses; it is not shown to be
  rounding [I].
- Window identity is the reducer's (DATA_MODEL §6.3), so both sources feed one `PoolWindow`; the rule in §7 only
  decides which source's reading may move it.

---

## 3. Design

```text
 Claude desktop app (Code tab) / VS Code panel, running Claude Code ≥ 2.1.286
   └─ mod clepso-limits@clepso (~/.claude/clepso/claude-mod/plugins/clepso-limits, loaded in place)
        session.measure → skip if a terminal draws the session or nothing does
                        → $.process.run(["/bin/sh", "-c", <fixed>], { stdin: hand-off JSON, timeoutMs: 5000 })
 ══ B1 process boundary, same user ══
 ~/.claude/clepso/mod-handoff.sh        exec the helper if present, else exit 0
 Clepso.app/Contents/Helpers/clepso-statusline --mod
        reads ≤ 64 KiB, ModHandoff allowlist → status-line shape → FrameBuilder (frame v1) + via/surface
 ══ B2 Unix socket (same peer checks, same budget) ══
 Clepso.app: FrameMapper (channel = mod) → Store → PoolReducer (one source per window) / SessionReducer
```

| Component | Path | Owner, mode | Notes |
|---|---|---|---|
| Mod source in the repo | `mod/claude-code/` | — | `marketplace.json`, `plugins/clepso-limits/{.claude-plugin/plugin.json, hooks/hooks.json, hooks/register.js, hooks/handoff.js, tests/handoff.test.ts}` |
| Bundled copy | `Clepso.app/Contents/Resources/claude-code/` | signed with the app | Byte-identical to `mod/claude-code/` (`make ci` checks) |
| Installed marketplace | `~/.claude/clepso/claude-mod/` | app writes; dirs 0700, files 0600 | Copied from the bundle at install and by Repair when the bundle's copy changes; `settings.json` names this path, so moving the app never needs a settings edit |
| Hand-off script | `~/.claude/clepso/mod-handoff.sh` | 0700 | Same template as `hook.sh`; regenerated by Repair |
| Install record | `~/.claude/clepso/mod-state.json` | 0600 | `h0`, `h1`, backup path, which keys Clepso created, original mode |
| Backup | `~/.claude/clepso-backups/settings.json.<UTC>.<sha12>.pre-mod.bak` | 0600 | Exclusive create |

### 3.1 Why `/bin/sh -c` with a fixed string

The plugin folder holds only the static files from the repo (so its bytes can be compared with the published source).
The helper's location changes when the app moves, and Claude Code may load the plugin from its cache rather than in
place (E-A copied it), so the mod cannot point at a file inside its own folder. The fixed command finds the hand-off
script in Clepso's folder the way the hooks' command does:

```sh
f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/clepso/mod-handoff.sh"; [ -x "$f" ] && exec "$f"; exit 0
```

It reads no variable but `CLAUDE_CONFIG_DIR` and `HOME`, which Claude Code's process already has, and the mod makes no
`$.env` call. If Clepso is gone, the command exits 0 and the mod's `try` swallows any rejection.

---

## 4. The mod

`hooks/register.js` (one hook) and `hooks/handoff.js` (pure functions, tested):

1. `on('session.measure')`: `await next(e)` first, so Claude Code's own handling is never delayed or changed; the
   hook returns that result unchanged in every path.
2. `surfaces = $.session.surfaces()`. **Forward only if** the list is non-empty and has no `terminal`: a session a
   terminal draws has the status line; one nothing draws is `claude -p` or the SDK (Clepso's own tests and scripts
   included).
3. `$.session.id()`, `$.session.version()`, then `$.session.model()` in a `try` of its own, so a refusal there still
   sends the limits (without a model).
4. Build the hand-off **field by field** (§5): the model only as a non-empty string of at most 64 characters (the
   status line's `model.id` bound); kinds outside `five_hour`, `seven_day`, `spend_limit` are counted in
   `other_windows`, never named; `cost`, `changed`, `context.breakdown` and anything else the event carries are not
   read.
5. `$.process.run(["/bin/sh", "-c", FIXED], { stdin, timeoutMs: 5000 })` inside `try`; any failure is silent.

Hot-path cost: once per turn, one process start (the helper's own budget is 50 ms hard cap, `statusline-shim.md` §4).

---

## 5. Hand-off and frame

### 5.1 Mod → helper (stdin of `clepso-statusline --mod`), hand-off v1

```json
{
  "v": 1,
  "surface": "desktop",
  "session_id": "1f5e4b85-aff5-4060-9460-e347da1179ef",
  "version": "2.1.299",
  "model": { "id": "claude-opus-5-5" },
  "rate_limits": [
    { "kind": "five_hour", "percent_used": 26, "resets_at": "2026-10-19T14:30:00.000Z" },
    { "kind": "seven_day", "percent_used": 70, "resets_at": "2026-10-22T04:00:00.000Z" }
  ],
  "other_windows": 0,
  "context": { "tokens": 88744, "window": 1000000, "percent": 9 }
}
```

### 5.2 Helper (`ModHandoff`, the allowlist gate)

The helper accepts only this shape (`Sources/ShimProtocol/ModHandoff.swift`) and translates it into the status-line
input, then runs the unchanged `FrameBuilder`, so every bound, scrub and HMAC rule of `statusline-shim.md` §6 applies
as is:

| Hand-off field | Becomes (status-line path) | Rule |
|---|---|---|
| `v` | — | must be 1, else no frame |
| `session_id` | `session_id` → `session_ref` (HMAC, 16 hex) | string 1–128 bytes; the raw id never leaves the helper |
| `version` | `version` → `source_version` | the status line's string rule (≤ 32, printable, scrubbed) |
| `model.id` | `model.id` → frame `model.id` | the status line's `model.id` rule (≤ 64, printable, scrubbed; a rejected value becomes `null` and `scrub_count` + 1); any other member of `model` is dropped; `model` that isn't an object → dropped, `scrub_count` + 1. The frame has no `model.display_name` (the app then shows the id) |
| `rate_limits[].kind` | `rate_limits.<kind>` | only `five_hour`, `seven_day`, `spend_limit`; any other is counted in `health.unknown_rate_limit_windows`; at most 8 entries read |
| `rate_limits[].percent_used` | `.used_percentage` | number 0–1000 (FrameBuilder) |
| `rate_limits[].resets_at` | `.resets_at` | ISO 8601 (with or without fractional seconds) → whole epoch seconds, rounded down; unparseable → the window keeps no reset time and `scrub_count` + 1; then FrameBuilder's [now − 1 d, now + 400 d] bound |
| `other_windows` | `health.unknown_rate_limit_windows` (added) | integer 0–64 |
| `context.window` | `context_window.context_window_size` | integer 1–1e8 |
| `context.percent` | `context_window.used_percentage` | number 0–1000 |
| `context.tokens` | `context_window.total_input_tokens` | integer 0–2^53 |
| `surface` | frame `surface` | one of `desktop`, `vscode`, `mobile`, `other` (anything else → `other`) |
| anything else | dropped, counted in `health.unknown_top_level_keys` | never copied, never named |

Stdin above 64 KiB, invalid JSON, a non-object, depth over the JSON depth guard, or `v` ≠ 1: no frame. The helper
always exits 0 with nothing on stdout or stderr. No disk writes, no network. Cost is never forwarded from the mod path
(`forward_cost` does not apply; the mod doesn't send it).

### 5.3 Frame v1 with two optional fields

Same kind (`claude_code.statusline`), same `v: 1`, same 4 KiB cap; added only:

| Field | Value | Older apps |
|---|---|---|
| `via` | `"mod"` | ignore it (FrameMapper reads only the keys it knows) and treat the frame as a status-line reading |
| `surface` | `desktop`, `vscode`, `mobile` or `other` | ignore it |

`health.original_present` is `false`; `model` holds only `id` (§5.2), so the app labels a desktop session by its model
id where a terminal session shows the status line's display name. A hand-off from the 0.3.0 mod (no `model`) is still
accepted.

---

## 6. Privacy entry (PRIVACY_AND_SECURITY §4.4, opt-in)

> **Claude desktop app and VS Code panel (opt-in, v0.3).** Off by default, available once the status line is
> connected. Clepso adds its own Claude Code mod, `clepso-limits`, to `~/.claude/clepso/claude-mod/` and turns it on
> in `~/.claude/settings.json` (§7). A mod runs inside Claude Code with the user's permissions and is not sandboxed,
> so it is kept small and its calls are fixed: one hook, `session.measure` (after each turn), and the calls
> `$.session.surfaces`, `$.session.id`, `$.session.version`, `$.session.model` and `$.process.run` (`claude plugin
> validate`; `make ci` fails if that list changes). It never hooks prompts, tool calls or transcript rows, and reads
> no file, setting, environment variable or credential. In sessions that no terminal draws (the desktop app's Code
> tab, the VS Code panel), it hands Clepso's helper, on stdin, only: the session id, the Claude Code version, the
> session's model id, which app drew the session, each limit window's kind (`five_hour`, `seven_day`, `spend_limit`;
> others counted only), percent used and reset time, and the context window's size, fill percentage and token count.
> The helper applies its allowlist to that (`ModHandoff`), replaces the session id with its keyed hash and sends a
> frame v1 marked `via: "mod"`; nothing leaves the Mac. Terminal sessions are left to the status line. Turning it off
> removes both settings entries (byte-exact when nothing else changed) and Clepso's mod folder. Tests put marker
> strings in the event's other fields and in the hand-off's unknown fields and check none reaches the socket, the
> database, the export or the log.

---

## 7. One source per window (dedupe rule)

1. **In the mod (per session).** Only sessions no terminal draws are forwarded, so a terminal session reaches Clepso
   through its status line only. This holds whether or not F7 is true.
2. **In the reducer (per window).** Each observation carries a channel (`statusLine`, the default, or `mod`), stored
   in the ledger's `metadata_json` (`{"channel":"mod"}`) so a rebuild applies the same rule. `PoolState` keeps
   `lastStatusLineAt`. A `mod` reading observed less than **60 s** (`EngineConfig.sourceHoldOff`) after the pool's
   latest status-line reading is kept as history and does not move the snapshot, the window or any threshold. Outside
   that span the mod's reading is applied like any other, latest-wins. `SessionState` applies the same rule per
   session (it matters only if the VS Code panel turns out to run the status line too, F10).
3. Window identity stays the reducer's: both channels feed the same `PoolWindow`; a reset seen through either channel
   opens the next window exactly as today (G6, §6.3).

Why 60 s: while a terminal is in use its status line reports several times a minute (DATA_MODEL §6.4); an idle
terminal sends nothing, so the mod takes over within a minute of the terminal going quiet. Readings never sum, so the
worst case of the rule is a value up to 60 s older than the newest reading from the other app.

---

## 8. Fallback: "tasks yes, limits no"

- If the mod can't load (§2.4), the desktop app and VS Code keep sending hook events (unless hooks are off too), so
  Clepso still counts their tasks, and limit readings still arrive from any terminal session (limits are shared).
- Settings shows the mod's state honestly: **On · last desktop reading 3 min ago**, **On · no reading from the
  desktop app yet** (installed, but no `via: "mod"` frame since install), or **Off**. While none has arrived,
  the row says: "Nothing from the desktop app or VS Code yet. It starts with your next Claude session there. If your
  organisation turns Claude Code mods off, Clepso still counts tasks there, but not limits."
- Install is refused, touching nothing, when the user's own settings set `disableAllHooks: true` (the mod couldn't
  run, and neither would the status line).

---

## 9. Install and uninstall (`ClaudeModInstaller`, PRIVACY_AND_SECURITY §7)

**Install** (after the consent sheet):

1. Preconditions, each failure touching nothing: the status line is installed and verified (same check as hooks);
   not already installed; `settings.json` is valid JSON with an object at the top; `disableAllHooks` is not `true`;
   `extraKnownMarketplaces` and `enabledPlugins` are absent or objects the scanner can edit, with no `clepso` member
   and no `clepso-limits@clepso` member that isn't ours.
2. Back up the exact bytes (`H0 = sha256`) to `clepso-backups/…pre-mod.bak` (0600, exclusive).
3. Copy the bundled marketplace into `~/.claude/clepso/claude-mod/` (replacing an earlier copy), check every file's
   bytes against the bundle, and write `mod-handoff.sh`.
4. Compose new bytes: add `"clepso": {"source": {"source": "directory", "path": "<abs path>"}}` to
   `extraKnownMarketplaces` (or add that member, indented like the file), and `"clepso-limits@clepso": true` to
   `enabledPlugins` likewise. Every other byte is the original's.
5. Compare-and-swap (re-read, require `H0`), atomic replace with the original mode, re-read and verify: every other
   top-level key deep-equal; inside the two objects, every other member deep-equal; ours present. On failure write
   the original bytes back and remove the copied files.
6. Record `h0`, `h1`, the backup path, which of the two keys Clepso created, the original mode.

**Uninstall:**

1. Current bytes `Hc`. If `Hc == h1`, write the backup back (it must hash to `h0`), verify, report **Restored
   exactly**.
2. Otherwise remove only Clepso's two members, in place where the scanner can (and the containing key if Clepso created
   it and it is now empty), else rebuild from the parsed object and say the formatting changed. Compare-and-swap
   and verify that no other key changed. If neither member is left, settings stay as they are.
3. Delete `claude-mod/`, `mod-handoff.sh` and `mod-state.json`. Backups follow the existing retention.
4. Claude Code's own records of the marketplace stay (R6); the plugin is no longer enabled.

**Repair** (on launch, never touching `settings.json`): rewrite `mod-handoff.sh` when the helper path changed; re-copy
`claude-mod/` when its bytes differ from the bundle's (an app update with a new mod version).

**Remove from Claude Code / Delete all**: the mod goes first, then the hooks, then the status line (each calls the
helper through Clepso's folder).

---

## 10. Consent screen copy

Title: **Read limits from the desktop app?**

> Clepso adds its own small Claude Code mod, clepso-limits, and turns it on in **~/.claude/settings.json**. After each
> reply in the Claude desktop app's Code tab or the VS Code panel, it hands Clepso your plan-limit percentages, when
> they reset, how full the context window is, and which model the session uses. Nothing else: no prompts, replies,
> file paths, transcripts or passwords, and nothing leaves your Mac. Terminal sessions keep using the status line.

Shown verbatim (selectable): the two entries Clepso adds.

> A mod runs inside Claude Code with your permissions, so this one is kept to one hook and five calls:
> session.surfaces, session.id, session.version, session.model and process.run (to start Clepso's helper). Its source
> is in ~/.claude/clepso/claude-mod.

> It starts with your next Claude session. Turning it off takes both entries out again; if nothing else changed,
> settings.json is restored byte for byte. If your organisation turns Claude Code mods off, Clepso still counts tasks
> there, but not limits.

Buttons: **Cancel** (default, Escape) · **Add the mod**.

---

## 11. Tests

| Test | What it proves |
|---|---|
| `mod/…/tests/handoff.test.ts` (`claude plugin test`, 9 tests) | Desktop: one hand-off, exact JSON with `model.id`, markers in `prompt`, `cwd`, a window's extra field, an unknown kind and `context.breakdown` never in stdin, no `usd`; VS Code + phone: forwarded as `vscode`; terminal: nothing; `-p` (no surface): nothing; helper missing: the event still completes; before the first reply: clean; `$.session.model` refused: limits still sent, no model (negative control: without its own `try` this test fails); a model over 64 characters not sent, exactly 64 sent |
| `claude plugin validate --strict` (gate) | `hooks: session.measure`; `calls: $.process.run, $.session.id, $.session.model, $.session.surfaces, $.session.version`; the marketplace validates |
| `ModHandoffTests` | Mapping of every field (`model.id` included; only `id`, the status line's 64-byte scrubbed rule, a non-object `model` scrubbed, a hand-off without `model` accepted), ISO parsing, bounds, unknown kinds counted not named, unknown keys dropped and counted, oversize/invalid/`v`≠1 → no frame, frame within 4 KiB, `via`/`surface` |
| `ModModeTests` (real helper binary) | Spike records replayed through `clepso-statusline --mod`: frame values; canary markers in every unknown field never reach the socket; exit 0 and empty stdout/stderr in every case, app absent included |
| `ClaudeModInstallerTests`, `ClaudeModTests` (app) | Fixture settings corpus plus settings with plugins of their own (absent keys, existing objects, CRLF, BOM, compact, odd indent, unicode, `disableAllHooks`, conflicting entries, invalid JSON): byte-preserving install, verify, exact restore, surgical removal after the user edited, created keys removed, CAS refusal, files and modes, repair |
| `SourceHoldOffTests`, `ChannelStoreTests` | One source per window: a mod reading within 60 s of a status-line reading is history only; after 60 s it applies; resets through either channel; sessions likewise; the channel round-trips through `metadata_json`; rebuild equals live with mixed channels; negative control: with the hold set to 0 these fail |
| `ModCanaryTests` | Markers through the real helper into the database, export and log (a marker in `model.display_name` and an extra `model` member included); the reading arrives on the mod channel; the model id is stored on the session |
| Probe screenshots | The consent sheet and the Settings row, light and dark |

---

## 12. Open questions

| # | Question | How it gets answered |
|---|---|---|
| Q1 | Does `$.process.run` work in the desktop Code tab (F9)? | Runbook D3: a `via: "mod"` frame arrives from a desktop session |
| Q2 | After removal, does `/plugin` show the deleted marketplace as an error? | Runbook U4; if so, the uninstall note suggests `claude plugin marketplace remove clepso` (which rewrites settings.json formatting, so Clepso does not run it) |
| Q3 | Does the first session after install load the mod, or only the next one (R4)? | Runbook D2 |
| Q4 | Should the mod also send the model name (`$.session.model()`, a fifth call) so desktop sessions are labelled? | **Answered 19 Oct 2026: yes** (founder decision). The mod sends `model.id` only (F11, §5.2); confirm in runbook D5 that a desktop session's value matches the terminal's status-line `model.id` |
| Q5 | VS Code panel: are `surfaces` `["vscode"]`, does it run the status line (then rule §7.2 applies), and does the extension version matter? | Runbook V1–V3, needs VS Code with the extension ≥ 2.1.299 |
| Q6 | Is the mod's session id the status line's and the hooks' (F7)? A desktop session's hook tasks and limit readings then share one session row | Runbook D4 |
| Q7 | Mods are new and change almost every release; `session.measure`'s shape could change | `ModHandoff` drops unknown shapes silently; the gate pins the calls; re-test on each Claude Code minor release |
