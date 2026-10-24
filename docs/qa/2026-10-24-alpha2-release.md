# Clepso 0.4.0 alpha 2 — released and installed, 24 October 2026

Public [release and DMG](https://github.com/obileonardo/clepso/releases/tag/v0.4.0-alpha.2). Installed **0.4.0/build 244**, Homebrew **0.4.0-alpha.2**. Gemini recording activity is opt-in, local token activity, not subscription quota. Existing tracking, widgets, MCP and updater remain available.

| Completed task | Evidence |
| --- | --- |
| Source | PR #26 merged at 5978cc81df0a66b049083e9dc377cc19fbdcf2e8; exact signed/tagged source 7590ce3354a30af8dd2431592a3ec66e4dd2995c |
| Checks | 17 strict gates; 566 tests/113 suites; seven focused reader/lifecycle checks; all six hosted checks passed |
| Visual validation | Real native Gemini view light/dark renders and browser checks; physical native UI remains unverified |
| Distribution | App and DMG notarization Accepted, stapled, Gatekeeper and mounted integrity checked |
| Update verification | Official Sparkle verifier accepted feed/archive and rejected tampered URL/substituted archive; official MCP SDK passed against the signed CLI |
| Website | Production dpl_3bsXhwBEPL7tLPMPLogtDKMPAsRY READY; 22 routes/assets, feed and email artwork byte-matched |
| Homebrew | PR #6 merged at e4413d2; style, strict online audit and hosted clean install/remove passed |
| Installed app | Normal Homebrew upgrade; build 244 code hashes match released app/helper/CLI/widget/framework; one process |
| Preserved state | SQLite quick_check ok; user preferences and all captured Claude files unchanged except permitted operational sync timestamp |
| Tracking settings | Codex reader true; menu usage true; rotating limits; persistent mod enabled and matches signed bundle |
| Clock | After user correction and restart, Apple NTP offset +0.003100 seconds; timestamp checking was never weakened |

DMG SHA-256: `81454a3f57eb10644500b10333da2e8bca67982b6e2ef523f3a543c39fba0fa9`.
App notarization: `cd43bcd4-b3d4-470a-88c3-12351f220e11`; DMG: `a6ea5307-82b0-4c37-984c-5f0945525921`.
Backup: `/Users/elvisobi/Library/Application Support/Clepso Update Backups/20261024T001556Z`.
Sanitized machine-readable receipts: workspace `verification/2026-10-24/gemini-release/`.

The computer restart cleared /private/tmp helper scripts. Durable source, signed release artifacts and pending phone/Watch source survived. Reconstructed verification scripts checked current remote and installed state rather than assuming interrupted operations finished. The website-only deployment guard confines uploads to site/ and checks the dry-run root/inventory. An earlier attempt from the repository root was rejected by Vercel's file limit; the successful deployment used site/.

Mobile/Watch/relay/push, other provider adapters, additional editions and physical QA continue separately. Social sign-in and domain purchase remain on hold. No new sign-in emails or model prompts were sent. The README visual refresh remains queued after the existing work.
