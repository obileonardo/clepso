# Claude desktop mod live check — 21 October 2026

Source: `29e40a0` (merged PR #15). Claude terminal CLI 2.1.305; Claude desktop app 2.42304.2;
the received desktop frames identify its embedded Claude Code as 2.1.299. These are separate versions.
Public Clepso remains alpha 5/build 222, with the desktop/IDE Settings feature hidden.

The owner explicitly approved temporary installation, two short test prompts, removal and settings restoration.
The session used an empty temporary workspace. No additional model prompts were sent.

## Method

- `scripts/mod-check.sh`: isolated HOME/config, strict marketplace/plugin validation, pinned five API calls;
  all nine tests passed. The current validator also reports an optional listing-icon warning.
- Clepso's menu-only app could not be attached through computer use. A private driver linked the existing
  `ClaudeModInstaller` API and used the installed signed helper. No installer logic, helper, app binary or feature
  flag was changed. The reviewed source mod matched the existing debug bundle's mod bytes.
- Saved a private settings backup and fingerprint before installation. Used the normal reversible install and
  uninstall API. Read the live database read-only; no production rows were edited to manufacture a passing result.
- Used computer use for the actual desktop restart, Code session, two replies, usage popover and plugin manager.
  CLI plugin lists were inspected separately. Evidence excludes settings contents, raw session ids and unrelated chats.

## Results

| Check | Observed result |
| --- | --- |
| Desktop helper execution, spec Q1 | Pass: three `channel=mod` context observations reached the running app |
| First session, Q3 | Pass on this environment: the first new local session after installation delivered |
| Context values | Context percentage, token count and window size were retained |
| Model label, part of Q4 | Stored full model id agrees with the desktop's selected model label; no separate display name |
| Hook/session identity, Q6 | Two hook tasks match the same stored session as the mod readings |
| Status-line observations on test session | None retained for that session; concurrent terminal sessions remained active |
| Five-hour/weekly pool adoption | Not independently proven: current aggregate readings agreed with the desktop usage display, but no pool row labelled `mod` was retained |
| Second reply | Completed normally; the short-interval repeat retained no additional context rows, consistent with ledger compaction |
| Desktop plugin manager | Directory-backed Clepso mod was not listed before or after the two replies, despite successful runtime delivery |
| CLI plugin listing | Present/enabled during installation; one cached entry remained disabled after removal |
| Removal | Installer returned `restoredExactly`; original settings bytes, SHA-256 and file mode match |
| Cleanup | Marketplace folder, handoff script and install record removed; Claude quit after the check |
| VS Code, Q5 | Not run: no VS Code/Cursor application found in the inspected application locations |

The app's ledger compacts unchanged pool values for up to 120 seconds and session values for at least 60 seconds
(`Store.LedgerPolicy`). Pool reduction also gives a fresh terminal source priority over mod readings
(`PoolReducer`). Those mechanisms prevent treating absence of a retained pool row as proof that the mod omitted
it. Conversely, context delivery alone does not prove desktop-only quota freshness or the menu-bar update.

## Follow-up: isolated desktop quotas

The owner approved two additional short replies and a private local collector. Both replies were used; no
further model prompts were sent. The received frames and the local `/status` command identify the embedded
Code engine as **2.1.304** for this check, rather than the first check's 2.1.299.

The normal `ClaudeModInstaller` temporarily installed the unchanged mod with a private test helper. That helper
was linked from the existing `StatusLineShim` object and called its existing `modMain`, passing a test-only home
in the environment dictionary. Its private config pointed to a separate Unix socket and HMAC key. The process's
real HOME, terminal status-line configuration and production listener were left unchanged. The existing fixture
listener collected the sanitized wire frames. `FrameMapper.map` then fed a real in-memory `Store` configured
with `LedgerPolicy.everyReading`, with no terminal observations in that test store. The verifier did not modify
the production database. This isolates desktop quota reduction from terminal priority and unchanged-value compaction.

| Check | Observed result |
| --- | --- |
| Real desktop capture | Two complete `via=mod`, `surface=desktop` frames |
| Quota adoption | Both five-hour and seven-day readings adopted by the normal mapper/store path |
| Reset adoption | Both reset instants retained; wire values are Unix seconds, store instants use milliseconds |
| Native usage comparison | Weekly percentage matched exactly; five-hour percentage within one point |
| Native reset comparison | Weekly local day/time matched; five-hour countdown within two minutes of capture |
| Model comparison | Canonical id `claude-fable-5-1` agrees with the selected Fable 5.1 label; `/model` exposes only the label |
| Version comparison | Frame source version matches the native local `/status` command |
| Cleanup | Installer returned `restoredExactly`; settings bytes and mode match; mod directory, handoff and install record removed; collector stopped |

Private raw frames, account/session details, settings backups and the HMAC key are excluded from source and
recovery archives. Safe receipts retain check results rather than raw quota/session data. No mod, helper or app
source changed. This proves real desktop telemetry and its isolated mapper/store adoption; it does not prove the
shipping app's menu-bar presentation or takeover while a competing terminal source is active.

## Remaining checks

Verify the shipping menu-bar values/reset presentation, compare canonical model ids across surfaces, and test a
current VS Code panel. `/model` alone cannot provide an independent canonical-id comparison in the tested desktop.
Confirm removal/discoverability in the supported plugin UI. Do not flip `ReleaseFeatures.shipping.claudeMod` yet.
See the [live runbook](../runbooks/v0.3-live-mod-test.md) and [integration plan](../specs/v0.3-integration-plan.md).
