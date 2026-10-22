> Public source handoff. Private configuration, credentials and raw account frames are deliberately excluded. Distribution changes after this snapshot require a fresh release/install receipt.

# Clepso — current handoff for Claude or Codex

Updated: 22 October 2026. Read this before older continuation reports. This is an evidence-based snapshot, not a claim that future features are already complete. Keep the progress ledger below current as work proceeds.

## Latest user instruction and authorized scope

The user now requests implementation of **every remaining item** in the inventory below, publication of completed work, and installation of the updated Mac app. **Domain purchase is explicitly excluded and remains on hold.** The user requested this handoff file before implementation. Commit/push, GitHub releases, website deployment, Homebrew updates and app installation are authorized. Preserve existing data, accounts, consent and tracking settings. Work procedurally and provide a completed-task table after each completed batch.

Do not invent credentials, business/legal identity, device verification, supported provider telemetry or test results. Do not expose secrets or commit local configuration. Existing approvals for test emails and model replies have been consumed; no fresh email or model test prompts are currently authorized. Existing persistent desktop/IDE tracking remains authorized and enabled. The user explicitly authorized macOS `open` to reopen Clepso when computer use fails.

## Current verified distribution

| Surface | Current verified state |
| --- | --- |
| App repository | `app/`, GitHub `obileonardo/clepso`; clean main `dace9a2ebdf3d1a40c43296787b07d62572fb160` at this handoff's creation |
| Exact signed source | `v0.3.0-alpha.3` at `1ff1e1443aaa2a89ce5ca81dc9e589a3d529669e`; merged main has the identical tree |
| Public release | https://github.com/obileonardo/clepso/releases/tag/v0.3.0-alpha.3 ; public Latest, title/tag explicitly alpha |
| Direct DMG | https://github.com/obileonardo/clepso/releases/download/v0.3.0-alpha.3/Clepso-0.3.0-alpha.3.dmg |
| DMG SHA-256 | `e34982f0a34c48694aa0da5ba77ecf883efb78b421753e59d8c740e6eab596fd` |
| Installed app | `~/Applications/Clepso.app`, version `0.3.0`, build **232**, Homebrew-managed and verified running |
| Homebrew repository | `homebrew-clepso/`, GitHub `obileonardo/homebrew-clepso`; clean main `1d61f492d99999c3321d18c0d3f064c1958678a9` |
| Homebrew installation | Named cask `obileonardo/clepso/clepso`, receipt `0.3.0-alpha.3`; actual tap at `/opt/homebrew/Library/Taps/obileonardo/homebrew-clepso` |
| Website | https://clepso-app.vercel.app ; character page `/characters/`, documentation `/docs/`, dashboard `/app/` |
| Vercel deployment | `dpl_7Bpxg76A2gCRGC4FAHoigsMZmo32`, project `clepso`, scope `obileonardos-projects`, project ID `prj_ZTZiAhmv5oejW0DcgdzavbllW2qT` |
| Latest completed PRs | App #20 and tap #3 merged; no open PRs at the end of that release |

The workspace root is **not** a Git repository. Run app build/test/Git operations from `app/`, tap operations from `homebrew-clepso/`, website deployment from **`app/site/`**, not the app repository root. The original `~/Developer/clepso` checkout and six historical worktree sources were preserved. Their untracked items are generated cache symlinks, not hidden source changes.

## Project purpose, stack and boundaries

Clepso is a native SwiftUI macOS menu-bar app for usage limits, reset times, context, sessions, models, goals and activity. It is local-first; optional email accounts upload documented daily summaries to the web dashboard. It does not upload prompts, replies, project/file paths or raw session identifiers. The public app targets Apple silicon and macOS 14 or later. The helper is universal Intel/Apple silicon, but that does not make the Mac app universal.

Swift Package Manager modules include Domain, UsageEngine, Storage (GRDB/SQLite), ShimProtocol, StatusLineShim, ClaudeCodeAdapter, CodexAdapter, SubscriptionCatalog, DesignSystem, Sync and ClepsoApp. The Xcode app is a thin `@main` under `App/ClepsoMac`. XcodeGen configuration and Makefile drive builds. Networking is confined to Sync; the fixed Claude helper must link no networking. Themes supply UI type, color, spacing and motion tokens. The Clepso Pixel display and Clepso Mono body fonts ship with licenses. Website pages are generated static HTML/CSS/JS, with the existing account dashboard and Supabase backend/config/templates under the repository.

## Completed features and project work so far

| Area | Implemented and shipped behavior |
| --- | --- |
| Claude terminal tracking | Reversible settings/hooks integration, bounded validated frames, fixed local helper/socket, provenance/freshness and usage/session/context ingestion |
| Claude desktop and VS Code | Opt-in reviewed `clepso-limits@clepso` mod; fixed installed signed helper; local allowlisted usage/context/model fields; session identifiers hashed; feature exposed and persistently enabled on this Mac |
| Live tracking verification | Earlier isolated desktop and IDE checks verified both quota windows/reset times; later two production replies verified context/model/session handoff. Shared terminal pools retain priority; do not claim a new isolated takeover test |
| Codex | Automatic session-file reading and limits/context/session views, with user setting enabled on this Mac |
| Manual provider allowances | Claude Chat, ChatGPT, Gemini, Grok, Cursor, Copilot and Windsurf snapshots; explicit manual provenance/time, stale/reset states, plan selection, overage confirmation, editing/removal/export. Catalog names do not verify subscriptions or create quotas |
| Dynamic menu-bar pill | Claude/Codex five-hour and seven-day rotation, pinned/summary modes, fresh/stale/reset/missing states, stable centered width; reduced side padding, uppercase Clepso display type and color; Reduce Motion/VoiceOver/hover pause behavior |
| Native dashboard | Home/Limits/Session/Overview/Models/Player Card/Goals/Account/Settings, keyboard and focus helpers, charts/activity, themes/appearance, pixel controls |
| Goals | Right-aligned target toggle and +/- buttons; balanced pixel cross/minus glyphs. Included since alpha 1/build 228, retained thereafter |
| Toggle refinement | Shared inner thumb uses an inset stepped outline that follows the track vocabulary in On/Off and disabled states; shipped alpha 2/build 230 |
| Account layout | Compact upload status/action row, concise summary, expandable full privacy disclosure, connected-account wording; shipped alpha 2/build 230 |
| Models art | Native owl maestro, fox storyteller, poet/verse keeper and paper crane in portrait, roster and level track; Opus 5/5.5 and Fable 5/5.1 distinct silhouettes/costumes/books; neutral unknown-family robot; shipped alpha 3/build 232 |
| Models motion/explanation | Four authored poses, anchored feet, gestures/blinks; only selected portrait animates; Pause/Resume, system Reduce Motion, hidden/inactive schedule suspension; About explains literary meanings and version vs usage level |
| Notifications | Persistent opt-in reset reminders, OS delivery receipts, freshness/recovery cancellation and snooze. Expected-reset notices stay on the app tick with a 15-minute age bound after a real regression was caught; no unbounded OS expected-reset schedule |
| Calendar | Explicit user-triggered weekly reset export, without automatic calendar event creation |
| Data/privacy | Local SQLite, retention choices/cleanup, export and deletion coverage including manual observations/schedules, safe backup expiry preserving edited/unrecognized files |
| Email accounts | Optional email-link authentication, existing callback/Keychain/account sync; branded sender `contact@elvisobi.com` through the existing mailbox and configured SMTP. Approved Protocol email design uses blended enlarged logo and rendered Clepso Pixel headings; inbox approved |
| Website | Product homepage, Homebrew/install/download/privacy/docs links, preserved documentation, interactive literary guild with original art, edition controls/pose comparisons/research notes, dashboard and changelog |
| Release engineering | Signing, notarization, stapling, Gatekeeper/image integrity/mounted payload checks, exact tagged source, monotonic build numbers across squash merges, public DMG+SHA256SUMS, GitHub Latest metadata |
| Homebrew | Dedicated public tap, bounded updater validates GitHub release metadata/digests/download sizes/manifest; CI performs style/online audit and clean Apple silicon signed installation/removal |
| Host reliability | Normal approved escalation resolved sandbox DNS/signing/notary/disk-service failures. Explicit DMG sizing and internal temporary mounts fixed actual image failures. Existing read-only GH token explicitly mapped to Homebrew's API-token variable to avoid anonymous rate limits |
| Cache/storage | Generated caches from historical worktrees moved to the external volume with inventory verification and symlinks; source untouched. Doctor/release check separate build-volume and temporary-volume requirements |
| Recovery/docs | Git-only source ZIP/bundles/binary patch, tap ZIP/bundle and checksum manifest refreshed; current public implementation inventory `app/docs/STATUS.md`; old contradictory handoffs marked historical |

Important sequencing: PR #17 was verification documentation only. PR #18/alpha 1/build 228 shipped the previously tested v0.3 features and Goals glyph correction. PR #19/alpha 2/build 230 shipped toggle/Account refinement and website. PR #20/alpha 3/build 232 finally integrated the approved character study into native Models. Do not repeat the mistake of treating a website study, committed source, or merged PR as an installed app update.

## Remaining inventory — now explicitly requested for implementation/shipping

| ID | Item | Starting state / actual prerequisite |
| --- | --- | --- |
| R1 | Automatic Gemini/Grok/Cursor/Copilot/Windsurf tracking | Manual entries ship. Automatic adapters need supported, validated real telemetry, provenance/freshness and privacy design; never invent percentage limits from token counts |
| R2 | Clepso MCP server | Assessed in `app/docs/specs/v0.3-integration-plan.md`; no server ships. Needs a read-only bounded snapshot contract, explicit disclosure/consent and real-client verification |
| R3 | Mobile alarms, iPhone/Watch, relay/push | Not implemented. Needs apps, pairing/notification delivery, device/service configuration, privacy controls and end-to-end verification; do not silently buy services |
| R4 | Production widgets | Starting audit found no extension source in alpha 3. Implemented real extension in the new branch; distribution verification pending. |
| R5 | Apple/Google/GitHub sign-in | PKCE/provider wiring exists; signed release has no enabled OAuth providers. Founder-owned console configuration/credentials/verification are required for live auth; never embed provider secrets in the app |
| R6 | Automatic in-app updates | Not enabled. DMG/Homebrew upgrades work; select a signed/notarized update design and validate feed/signature/installation/recovery before shipping |
| R7 | Extra character work | Website level-up flourish is demo-only; other editions use base-family art. Implement native celebration/edition handling without manufacturing model-version or capability claims; respect motion/accessibility |
| R8 | Legal/privacy identity details | Publisher Elvis Obi, Lagos, Nigeria, contact@elvisobi.com confirmed; factual notice updated. External legal review is not claimed. |
| R9 | Domain purchase | **EXCLUDED BY USER. Do not buy a domain or treat it as needed for existing branded email** |
| R10 | Additional QA | Physical/VoiceOver/focus, native plugin workflows/freshness/takeover, real sleep/restart notification lifecycle and older/clean macOS remain unverified observations; injected tests/renderings are not substitutes |

## Verified checks and known limitations

Alpha 3 exact source passed **17 strict local gates**, **544 tests across 108 suites**, 18 focused Models/character tests, and all six hosted checks (SwiftPM build/tests, contributor gates, four CodeQL languages). Both required helper budget tests passed with 200/200 frames each. Actual SwiftUI offscreen renderings cover all six model characters, poses, light/dark and 1x/2x placement. Browser checks cover desktop/mobile, keyboard selection, clipboard, painted canvases, pause/reduced motion and existing routes with no page errors. Eighteen public website pages/scripts/styles/email assets were byte-matched to release source.

App and DMG notarization submissions were Accepted; tickets stapled; Gatekeeper and disk/mounted-code checks passed. Installed app and helper code matched released bundle; one installed process; SQLite `quick_check` ok; all user preferences preserved (only the account's operational sync timestamp advanced); all Claude settings matched the pre-upgrade baseline. Menu preferences are `menubar.showPercent=true`, `menubar.display=rotating`, `codex.readSessionFiles=true`.

Native computer use repeatedly fails with **`Sky Computer Use native pipe startup failed`** (earlier also ScreenCaptureKit/audio-video failures). Do not claim fresh physical UI/VoiceOver verification. Use CUA for UI; do not bypass it using AppleScript/AX/CGEvents shell automation. User approved only the alternate normal `open` app relaunch method. A separate supported OS/device cannot be simulated by a unit test and called tested.

## Where to continue

- Product/source inventory: `app/docs/STATUS.md`; current release report: `ALPHA3_RELEASE_REPORT.md`.
- Architecture/privacy/data/release/specs: `app/docs/`, root `docs/`, especially `ARCHITECTURE`, `PRIVACY_AND_SECURITY`, `DATA_MODEL`, `RELEASE.md`, `specs/mod-bridge.md`, `specs/v0.3-integration-plan.md`, `docs/widgets.md` if present.
- Original foundation/role reports: `team/reports/`; root ROADMAP/DECISIONS/PENDING/QUEUED_REQUESTS retain historical context. Date-check them against this snapshot.
- Native Models: `app/Sources/ClepsoApp/Views/Details/{ModelCharacter,ModelCharacterAtlas,ModelDossier,ModelsSection,LevelTrack}.swift`.
- Artwork source: `app/scripts/site/characters/sprites.js`; generator `node scripts/build-character-art.mjs`; `--check` is a strict parity gate; UI palette inks in DesignSystem/Theme/Tokens.swift.
- Website generation: `app/scripts/build-site.py`, `public_site.py`, `scripts/site/`; deploy **only `app/site/`**. Existing reviewed Vercel project/scope above; verify target before mutation. Stage without promoting download links until release is public.
- Signing/account configuration: ignored `app/Config/Signing.local.xcconfig`, `Sync.local.xcconfig`. Developer ID team `DD8UY75RZT`, existing Keychain notary profile `clepso-notary`. Never print/copy their contents or private keys into reports or Git.
- Build: from `app/`, `make ci`, `make perf`, release `scripts/release.sh <tag> --with-accounts`; inspect `docs/RELEASE.md`. Runtime sandbox/cache/network failures require approved escalation, not weakening tests or security.
- Current distributable: `releases/v0.3.0-alpha.3/`; detailed build: `app/build/release/v0.3.0-alpha.3/`.
- Safe evidence: `verification/2026-10-21/alpha3/`, `native-characters/`, `alpha2/`, `v03-release/`; dates reflect implementation start even if publication completed later.
- Last app/database backup: `~/Library/Application Support/Clepso Update Backups/20261022T025325Z/`.
- Recovery: `RECOVERY_MANIFEST.json` and five named archives/bundles/patch at workspace root. A stale manifest string mislabels the original Goals fix as alpha 2/build 228; actual first shipment was alpha 1/build 228. Reconcile that label when refreshing records, without altering historical artifacts.
- Private raw test frames/settings/keys remain in protected temporary locations and outside Git. Do not paste sign-in links, passwords or API keys.

## Founder details supplied during this implementation

- Legal publisher: **Elvis Obi**.
- Public contact/service location, as specifically instructed: **Lagos, Nigeria**. Do not invent a street address.
- Existing public contact email: **contact@elvisobi.com**.
- Physical test devices available: **iPhone and Apple Watch**; OS versions/connection/signing still to be verified.
- Provider accounts: **Grok and Cursor**, **Copilot uncertain**, **no Windsurf account**. Gemini was not confirmed.
- Audit correction: the alpha 3 app branch contains widget planning documents but no WidgetKit extension source. The previous description “development prototype exists” was overstated; actual widget implementation starts here.

## Implementation progress ledger for the new request

| Batch | Status | Evidence / next action |
| --- | --- | --- |
| Handoff before implementation | Created this file first | Snapshot grounded in current release reports, manifest and clean app checkout |
| Remaining-feature implementation | Not started at file creation | Inspect existing implementations, specs, configuration and real available provider/device services; define observable acceptance criteria |
| Publish/install next release | Not started | Run required checks, merge/publish exact source, update tap/website, back up and install, verify actual signed code/settings |

Update this ledger after each batch. Record exact changed files, commands/results, decisions, blockers and immediate next steps. Keep local/private evidence local, while committing sanitized source, specifications, current status and user-facing documents to the public repositories. **Do not call a feature complete just because a scaffold or prototype compiles.**

### Batch 1 — implementation in progress (22 October)

Branch: `app/feat/complete-product-integrations` (not committed/published/installed yet).
- Added `IntegrationSnapshot`, `ClepsoMCP`, embedded signed CLI, Settings per-client disclosure/grants/revocation.
- Six MCP boundary tests passed. Official TypeScript MCP SDK **1.32.1** successfully initialized, listed/called both tools, filtered providers, verified stale/reset handling, rejected arbitrary arguments and observed immediate revocation. No model prompts sent.
- Real-client testing caught a pipe-read deadlock that unit request dispatch did not: replaced exact-length FileHandle reads with bounded POSIX streaming reads. Re-run passed.
- Added real small/medium WidgetKit extension, opt-in shared aggregate snapshot, stale/reset timelines, Limits deep link, team-prefixed Mac app group. Xcode build passed with one extension version warning; metadata corrected, revalidation pending. Physical widget gallery still untested.
- Device inventory sees two paired iPhones (iOS 27.2 / 27.0), no connected Watch. Do not publish device identifiers.
- New docs: `app/docs/integrations/mcp.md`, `app/docs/widgets.md`.
- Downloaded official Sparkle **2.10.0** archive into ignored `.tools/sparkle/2.10.0`; SHA-256 matched GitHub's published digest `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`. Updater integration not yet implemented.
- Public/installed distribution remains alpha 3/build 232. Do not report this batch shipped until release/upgrade evidence exists.

### Batch 2 — release preparation

- Full strict local CI: **17/17 gates passed**, **557 tests / 111 suites**. Five new integration lifecycle tests and two native level-transition tests supplement the six MCP tests.
- Both helper perf checks passed with **200/200 frames**; paired app-present added p95 status line **5.37 ms**, hook **0.30 ms**.
- Added native level-up flourish, suppressed for selection/range/demo/replay/hidden updates; moving effect obeys Pause/Reduce Motion. No claim of additional edition costumes yet.
- Real widget source rendered offscreen small/medium light/dark. Corrected wrapped ages and truncated reset labels; re-rendered. Real Settings and flourish source rendered with synthetic data. Native TextField offscreen placeholders are a renderer limitation, not physical interaction proof.
- Sparkle 2.10.0 integrated in the signed Xcode host. Manual/automatic settings ship; both automatic choices initially off. `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` required; no system profile. Update-signing private key generated **in Keychain**, never exported; public key pinned in source. Feed preparation script added; real notarized feed generation/publication still pending release artifact.
- Website source/generated pages target **v0.4.0-alpha.1** locally. Integration setup page and updated publisher/privacy disclosures added. Desktop/mobile browser checks passed: download target, clipboard, painting, keyboard, pause/Reduce Motion, all routes, no errors/failed requests. Do not deploy changed download links until the new DMG is public.
- OAuth audit: Apple/Google/GitHub are disabled and have no configured client IDs/secrets. **User confirmed no OAuth applications have been registered.** Console setup is a real remaining external prerequisite; no broken provider buttons were enabled.
- Computer-use recheck: no apps/browsers; same native-pipe startup failure. Physical widget/VoiceOver/focus/updater/lifecycle checks remain unverified.
- No automatic Gemini/Grok/Cursor/Copilot/Windsurf adapter, mobile/Watch/relay/push implementation or live OAuth has been added in these two batches. Continue them after the first completed release; domain purchase remains excluded.
- New source docs: `docs/qa/2026-10-22-integrations.md`, `docs/PUBLISHER.md`, `docs/in-app-updates.md`, `docs/integrations/mcp.md`, `docs/widgets.md`, release notes. Sanitized fixture images will ship with source.

### Live release checkpoint — 22 October

- Batch pushed in **PR #21**: https://github.com/obileonardo/clepso/pull/21 . Initial commit `65200c65ea64ab00e6c54e802ee2fc426c033997`; current exact source **`f3ef338d5892949743a9d2d7cfa6e40cf03f92f4`** after a release-audit correction.
- First Developer ID export correctly stopped because Sparkle's Autoupdate carries a preserved application-identifier entitlement. Inspected all nine exported Mach-Os. Only that Sparkle executable has `com.apple.application-identifier=org.sparkle-project.Sparkle.Autoupdate`; the four other Sparkle binaries have no entitlements. Added the exact role-specific allowlist; all binaries still require our Developer ID, runtime and timestamp. No broad exception.
- Rebuilding **v0.4.0-alpha.1, build 235**, from f3ef338 with `scripts/release.sh ... --with-accounts`. Release console `/private/tmp/clepso-040-release-console.log`; build session 98875. Not notarized/published/installed yet at this checkpoint.
- Xcode writes a Sparkle pin into root `Package.resolved` during its resolution, while the SwiftPM manifest has only GRDB. This is generated noise. After build, inspect and restore only this known generated lockfile to the committed GRDB-only version before tagging/merging; do not discard unrelated changes. Sparkle is pinned exactly 2.10.0 in project.yml.
- Hosted checks on the initial commit passed SwiftPM (including the committed official MCP SDK runner), actions/JS/Python CodeQL; Swift/contributor checks were still running before the audit-only push started a fresh check run. Wait for all six checks on f3ef338 before merge.
- Homebrew checkout now branch **release/0.4.0-alpha.1**, with prepared `auto_updates true`, embedded `clepso` CLI binary stanza and README upgrade guidance (`--greedy`). Eight validator tests and Ruby syntax passed. **Version/checksum still alpha 3 until new public release assets are verified.** No tap commit/push yet.
- Installation must use the normal Homebrew upgrade with `--greedy`, back up current app/SQLite/preferences, preserve all Claude settings/persistent mod and user reader/menu settings. Allow only operational `account.lastSync` and `whatsNew.lastSeenVersion` preference changes. User already authorized normal `open` of installed Clepso.
- Public feed preparation: run `python3 scripts/prepare-update-feed.py v0.4.0-alpha.1` after final notarized DMG/SHA256SUMS exist. Tool uses Keychain account `com.elvisobi.clepso.updates`; no exported private key. Verify appcast/archive signatures with official `sign_update --verify`, including a tampered-byte rejection, then copy signed bytes to `site/updates/`. Publish GitHub DMG before promoting website links/feed. Website deploy only from app/site to existing project clepso/scope obileonardos-projects.
- The local website server on 127.0.0.1:8768 is session 68511. Website QA passed. Native visual evidence under `verification/2026-10-22/040-integrations`; sanitized widget/flourish images committed. Scripts `/private/tmp/clepso-040-{web-qa.mjs,render-widgets.py,render-native.py}` are reproducible local runners. Offscreen Settings text fields have renderer placeholders; physical UI still unverified.

### Superseding privacy correction — do not publish build 235

Before installation, final review found that widget publication could interleave an awaited off-preference write. Added a busy guard, persisted-off crash reconciliation, and direct external-snapshot cleanup in data deletion (works even if SQLite could not open). **Seven sharing lifecycle tests pass**, including concurrent refresh/opt-out and interrupted-off restart. Full final strict CI is running: session **28714**; inspect `/private/tmp/clepso-040-final-ci.log` and latest tool output. New code is not committed yet; commit only after checking results, then rebuild exact final source (expected next build 236). **The signed build 235 and its feed are superseded; do not publish them.** Installed app remains 232.

The earlier 235 artifact's feed/archive signatures verified with the official Sparkle verifier; a changed signed download URL and a replaced archive were rejected. A trailing XML comment is outside the signed payload and is not an appropriate negative test. Repeat actual signature checks for the final artifact. Official MCP SDK also passed against the 235 embedded signed CLI; repeat against final release CLI. Private verifier `/private/tmp/clepso-040-verify-feed.py` currently hardcodes build 235: update to actual final build before running. Upgrade/installed-verify scripts `/private/tmp/clepso-040-install.py` and `...-final-verify.py` likewise currently expect 235 and must be updated to final build.

### Final source freeze — privacy correction verified

- Final strict CI completed successfully: **17 gates**, **559 tests across 111 suites**. Seven sharing lifecycle tests include concurrent refresh/opt-out and interrupted-off cleanup. Source now ready to commit and rebuild; build 235 remains superseded.
- User confirmed Grok and Cursor are **personal subscriptions**, not API/team administrator accounts. Do not substitute admin billing APIs for their consumer quota readings. Supported local token/context readings must remain distinct from account limits.
- Root Package.resolved restored only the known Xcode-generated Sparkle resolution noise. project.yml retains the exact Sparkle pin.
