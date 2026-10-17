# Fixture corpus

Fixtures pin down how Pulse handles Claude Code's status-line JSON, end to end: what the helper forwards, which
observations the app derives, and the resulting state. They live in
`Sources/TestFixtures/Resources/claude-code/`, are listed in `manifest.json`, and are used by
`Tests/ShimIntegrationTests/` (which runs the built helper against a temporary `HOME`) and
`Tests/ClaudeCodeAdapterTests/`. Section numbers are stable: code comments cite them.

## 1. Layout

```
claude-code/
  manifest.json                 every fixture id with its status (active, covered elsewhere, or deferred)
  synthetic/Fxx-<slug>/         hand-written: meta.json, stdin/*.json (or .bin for hostile input), expected.json
  captured/<version>/Cxx-<slug>/ real captures, scrubbed before commit
  settings/                     settings.json corpus for the installer (refused-* must be refused untouched;
                                every other file must round-trip byte for byte)
```

`stdin/` holds the exact bytes piped to the helper, one file per status-line refresh, in order.

## 2. `meta.json`

| Field | Meaning |
|---|---|
| `fixtureSchema` | Header format version (1) |
| `id`, `slug` | `Fxx` (synthetic) or `Cxx` (captured); stable for life |
| `origin` | `synthetic` or `captured` |
| `scrubbed`, `scrubCount` | Must be `true` for captured fixtures; how many fields the scrubber dropped |
| `providerSchema` | Claude Code's status-line schema name, version, documentation URL and when it was checked |
| `clock` | `start` (instant of event 1), `renderAt` (when the interface is rendered for assertions), `displayTimeZone` |
| `events` | Ordered `{ file, atOffsetSeconds, originalCommandStdout }`; the helper's clock is pinned to `start + offset` |
| `history` | `{ date, by, why }` for every change to `expected.json` |

## 3. `expected.json`

| Key | Content |
|---|---|
| `parser` | Whether each event was accepted, unknown top-level keys, health counters |
| `forwarded` | The exact set of field paths that left the helper (the allowlist in `PRIVACY_AND_SECURITY.md` §4, intersected with what was present), and `droppedByConstruction` (every other field present). Compared as sets |
| `shim` | `framesDelivered` |
| `observations` | What `FrameMapper` must produce (`DATA_MODEL.md` §5.1): subject (`pool` with its provider key, or `session`), metric kind, and a tagged value such as `{"kind":"percent","value":"34"}` or `{"kind":"absent","reason":"providerOmitted"}`. Decimals are strings. Compared as a multiset |
| `snapshot`, `events`, `ui`, `notifications` | Later sections; `pendingSections` names the ones not yet checked |

`scripts/fixture-oracle.py` regenerates the `observations` sections from the raw stdin independently of the Swift
code, so the two implementations check each other.

## 4. The corpus

| Id | What it covers | Status |
|---|---|---|
| F01 | 5-hour limit at 12%, no reset time | active |
| F02 | 5-hour at 79% with a reset time | active |
| F03 | 5-hour rising from 79% to 95% | active |
| F04 | 5-hour at 100% with a reset time | active |
| F05 | 7-day at 100%, then the reset passes | active |
| F06 | No `rate_limits` at all (accounts or moments without limits) | active |
| F07 | `current_usage: null` | active |
| F08 | Two concurrent sessions reporting one allowance pool (session A, then session B) | active |
| F09 | Out-of-order arrival | covered by reducer tests |
| F10 | Hostile input (oversized, invalid, secret-shaped strings) | active |
| F11 | Paid overage | covered by reducer tests |
| F12 | Older and newer status-line schema versions | active |
| F13 | `settings.json` install/uninstall corpus (`settings/`) | active |
| F14 | The app is not running | active |
| F15–F19 | Plan label, time-zone change, daylight saving, manual reset entry, no Claude Code installed | deferred to later features |
| C01 | One real Claude Code 2.1.302 session, scrubbed: paths replaced by `/fixture/path`, ids and names redacted | active |

## 5. Adding a fixture

1. Synthetic: write `meta.json` and `stdin/` by hand with obviously fake values (paths under `/fixture/…`).
2. Captured: record with `pulse-fixture listen`/`capture-shim`, then run `pulse-fixture scrub`; read every remaining
   string before committing. Never commit an unscrubbed capture.
3. Write `expected.json` and add the id to `manifest.json`. `python3 -I scripts/fixture-oracle.py --check` exits
   non-zero if the oracle disagrees with any `expected.json` (without `--check` it rewrites the rows it owns).
