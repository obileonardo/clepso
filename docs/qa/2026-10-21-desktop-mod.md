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

## Remaining checks

Run a controlled desktop-only quota check during a quiet terminal interval, verify menu-bar values and resets,
compare the exact model id through `/model`, and test a current VS Code panel. Confirm removal/discoverability
in the supported plugin UI. Do not flip `ReleaseFeatures.shipping.claudeMod` based on this partial result.
See the [live runbook](../runbooks/v0.3-live-mod-test.md) and [integration plan](../specs/v0.3-integration-plan.md).
