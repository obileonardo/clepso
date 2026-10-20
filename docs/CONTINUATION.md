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

The complete test suite passes: **534 tests across 106 suites**, with real Unix socket integration enabled.
All **16 strict local CI gates pass**, including pinned toolchain, compiler warnings as errors, helper linkage,
no debug-only code in release objects, source/privacy/design checks, strict mod validation and the signed app bundle.
All six hosted PR checks pass at `e0c5d0d`: SwiftPM build/tests, contributor gates and four CodeQL languages.

The 200-round helper performance gate passes: paired status-line overhead p95 12.13 ms (budget 20 ms), with 200/200
frames delivered. Hook overhead p95 1.02 ms, also 200/200 frames delivered. The manual card was rendered and inspected.
A signed debug app launches with a separate test home/database and starts its listener. Native UI automation timed
out while attaching, so a complete keyboard/form/Calendar-import run is not claimed.

The first unrestricted full suite caught late expected-reset notifications after a long sleep. The OS expected-reset
trigger was removed: these notices stay on the app tick, where the 15-minute maximum age is enforceable. Persistent
opt-in reset reminders and actual delivery receipts remain. Full and targeted regression tests now pass.

## Host access and release

The initial restricted executor could not reach GitHub, use the signing/notary Keychain, bind local sockets or
create disk images. After the client enabled normal escalation approval, `make doctor` passed every check using
approved execution outside the sandbox. No credentials were replaced and no macOS security settings were weakened.
The continuation is pushed in PR #9. Xcode now resolves the local package and builds the signed app successfully.

The old main CI failure was a timeout waiting for a timezone/relaunch reading; that test passes in the complete
local and hosted continuation runs. The `v0.2.0-alpha.1` candidate still needs its signed archive, notarized/stapled
DMG and public release. Use `docs/RELEASE.md`; passing host diagnostics alone is not a publication gate.

## Remaining external work

Branded email/domain registration, OAuth console credentials, legal identity/address and paid-service decisions need owner information or setup. The production desktop/VS Code mod install/use/remove check and physical keyboard/Calendar import checks need working native surfaces and permissions; the shipping mod remains disabled. Automatic Gemini/other-agent adapters need validated telemetry and authorised access. Phone/Watch/widgets, relay/push, announcements and updates remain future work with platform, service and verification prerequisites; they are not described as completed here.

## Packaging correction

An automatically sized DMG failed verification even before signing; the same checked app in an explicitly sized
64 MiB HFS+/UDZO image passed. Release packaging now sizes the staged payload plus 16 MiB metadata headroom in
64 MiB increments, verifies the unsigned image, then retains the signature, integrity and read-only mount checks.
The host diagnostic checks its temporary image's integrity too. This changes packaging, not the app's behavior.
