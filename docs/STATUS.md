# Implementation status — 0.4.0 alpha 1

This is the current feature inventory for this release source. Older continuation reports describe earlier builds;
they do not override the shipping flags in `Sources/ClepsoApp/System/ReleaseFeatures.swift`.

| Area | Implemented in this release |
| --- | --- |
| Native Models characters | Owl maestro, fox storyteller, poet and paper crane; Opus 5/5.5 and Fable 5/5.1 editions differ; unknown families get a neutral robot |
| Native character motion | Selected portrait only; Pause/Resume, system Reduce Motion, hidden/inactive-view schedule suspension; roster and level markers remain still |
| Native level-up flourish | Newly crossed output thresholds while the same model/range is visible; selection, demo, replay and inactive updates do not celebrate |
| Desktop widgets | Small/medium WidgetKit extension, opt-in aggregate sharing, source/freshness/reset labels and Limits deep link |
| Clepso MCP | Read-only stdio `get_limits` and `get_reader_health`, explicit grants/revocation, bounded private snapshot; verified with official SDK |
| Signed in-app updates | Sparkle 2.10.0, mandatory feed/archive signatures and verification before extraction; manual/automatic settings, no profile reporting |
| Publisher details | Elvis Obi, Lagos, Nigeria; contact@elvisobi.com; updated factual privacy disclosures |
| Character meanings | About explains each literary name, edition details and original-art provenance; levels and capabilities are separate |
| Goals controls | Right-aligned target toggle and +/- controls with balanced pixel cross/minus |
| Shared toggles | Stepped inner thumb follows the outer track vocabulary in both states |
| Account Upload | Compact status/action row, short summary and expandable full privacy disclosure |
| Menu-bar usage | Claude/Codex five-hour and seven-day readouts, rotation and pinning, freshness/reset/missing states |
| Claude desktop/IDE tracking | Shipping opt-in mod and fixed local signed helper; previously verified with real desktop and IDE replies |
| Codex and terminal tracking | Existing automatic readings and provenance retained |
| Calendar | User-triggered reported weekly-reset export; no automatic event creation |
| Branded email and web accounts | Optional email-link sign-in and daily-summary upload; approved Protocol templates and fonts |
| Other providers | Manual snapshots and catalog entries; not automatic adapters |
| Website | Product homepage, interactive characters, documentation and web dashboard |
| Distribution | Release workflow builds Developer ID signed/notarized/stapled app + DMG; public GitHub releases and dedicated Homebrew tap |

## Not implemented or not enabled live

| Item | Actual remaining work |
| --- | --- |
| Automatic Gemini CLI, Grok, Cursor, Copilot, Windsurf tracking | Validate real supported telemetry and access; manual entries are already available |
| iPhone/Watch app and mobile alarms | Separate app, pairing, push/delivery infrastructure, device credentials and end-to-end checks |
| Apple, Google and GitHub sign-in | Provider wiring exists, but founder-owned OAuth console applications/credentials/verification are not configured live |
| Additional model-version costumes | Known Opus 5.5 and Fable 5.1 editions have explicit variants; other versions retain the base family character |
| External legal review | Publisher details and factual privacy publication are supplied; no external legal sign-off is claimed |
| Domain purchase | Explicitly on hold; branded email already uses the existing mailbox |

## Verification still required

Full VoiceOver and physical focus traversal; real long sleep/restart/notification lifecycle; older supported macOS
and a clean user environment; further native mod removal/discoverability and terminal freshness/takeover checks.
Automated tests, offscreen actual SwiftUI renders and hosted clean Apple silicon installation do not replace those
observations. The current computer-use connection has failed to attach to the native app. No additional email or
model test-prompt allowance is assumed.

## Source versus distribution

A clean Git checkout or a merged PR does not update an installed Mac app. The release tag pins the signed source;
the release DMG and Homebrew receipt identify the distributable, while `CFBundleVersion` identifies the installed
build. Public release assets and an actual upgrade are checked separately before reporting an installation complete.
Private signing/accounts configuration, local settings, raw test data and generated build caches are intentionally
excluded from Git. They are not unpublished app features.
