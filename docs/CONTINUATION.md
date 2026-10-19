# Continuation — 19–20 October 2026

The founder authorised completing unfinished work needing no further information, pushing it to GitHub, and publishing a downloadable DMG. Work began at `9c617a9` on `feat/autonomous-release-completion`.

## Implemented

- Manual allowance snapshots for Claude Chat, ChatGPT, Gemini, Grok, Cursor, Copilot and Windsurf. Explicit user-entered provenance, measurement timestamps, stale and reset-expected states, catalog plan selection, user-confirmed overage, update/removal and export. They stay local, separate from automatic pools, and do not generate automatic alerts.
- Catalog 1.1.0: 13 additional current Cursor/Copilot plan names from official pages; original entries preserved. A catalog name never verifies the user's subscription or supplies an invented quota.
- Reset schedules persist with source observations, versions and status. OS-delivered reminders qualify Ready again; scheduled or elapsed notices do not. Rescheduling, disable, disconnect and fresh recovery cancel obsolete reminders. Expected-reset notices remain age-checked on the app tick; they are not scheduled with the OS, whose calendar trigger has no expiration deadline.
- Shorter retention choices, persisted preferences, immediate cleanup and truthful export metadata. Defaults remain 90/30/30/7 days. Manual readings and schedules are included in export and deletion.
- Settings-backup expiry after 30 days disconnected, cleaned on a later launch only when no connection is active. Edited/unrecognised files are preserved.
- Mac/web Apple, Google and GitHub sign-in wiring with PKCE, exposed only for explicitly configured providers. No accounts configuration is in the public alpha; external OAuth apps still need console setup.
- CI now retains Swift test output and xUnit results. The socket test harness reports the real errno instead of misreporting every bind failure as address-in-use. This is diagnostic work, not a claim that the remote CI failure has been fixed.
- Reconciled architecture/data/privacy/release/account/catalog records and draft v0.2 notes. Earlier private notes saying v0.2/v0.3 and fixes were awaiting merge were stale: they were already on main before this continuation.

## Verification

405 selected tests across 75 suites pass with compiler warnings treated as errors. This includes the new production mapper → store → app-model → injected-notifications flows, precise weekly Calendar export, v5→v6 migration with a checked pre-migration backup, manual history ordering/removal, real-delivery receipt checks, retention, provider PKCE configuration and backup preservation. The selection excludes Unix socket integration because this execution sandbox rejects bind with EPERM; it does not disable those tests in CI.

The optimized ClepsoApp module and status-line helper compile with warnings treated as errors. The existing ten source/privacy/design/mod/email gates pass. JavaScript syntax, Python syntax and Git whitespace checks pass. A rendered manual-card component was inspected; a full-window ImageRenderer result cannot substitute for native ScrollView/keyboard testing.

Full baseline socket/app integration tests were attempted and are blocked by the environment. The latest remote main CI failure predates this work; its detailed log and a new remote run are still needed. Full CI and the signed app-bundle release gate are not claimed green.

## Host access and release verification

The original restricted executor could not reach GitHub, use the signing/notary Keychain, bind local sockets or
create disk images. After the client enabled normal escalation approval, `make doctor` passed every check using
approved execution outside the sandbox. No credentials were replaced and no macOS security settings were weakened.
The continuation branch is pushed and PR #9 runs hosted CI.

The first full strict local gate passed the build, helper linkage, release debug-code audit, ten static gates, mod
validation and signed app-bundle checks. The full tests caught a long-sleep regression in the newly added OS
expected-reset scheduling. That scheduling was removed: expected-reset alerts stay on the app tick, where their
15-minute maximum age is enforceable. Persistent opt-in reset reminders and actual delivery receipts remain.
The targeted timezone, sleep, app-flow and schedule-store regression tests pass. The complete gate is being rerun
before the signed/notarized `v0.2.0-alpha.1` candidate is published.

The old remote main failure was a timeout waiting for a timezone/relaunch reading. That test passes in the local full
run and targeted regression run; a successful hosted run is still required before describing remote CI as fixed.

## Remaining external work

Branded email/domain registration, OAuth console credentials, legal identity/address and paid-service decisions need owner information or setup. The production desktop/VS Code mod install/use/remove check and physical keyboard/Calendar import checks need working native surfaces and permissions; the shipping mod remains disabled. Automatic Gemini/other-agent adapters need validated telemetry and authorised access. Phone/Watch/widgets, relay/push, announcements and updates remain future work with platform, service and verification prerequisites; they are not described as completed here.
