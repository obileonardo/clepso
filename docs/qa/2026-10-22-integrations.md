# Widgets, MCP, updater and native level-up verification

Pre-release verification on 22 October 2026. Source is on `feat/complete-product-integrations` until merged.
This report distinguishes implementation checks from public distribution and physical UI observations.

| Check | Observed result |
| --- | --- |
| Strict local CI | All 17 gates passed; warnings-as-errors build and 559 tests across 111 suites |
| MCP dispatch/file boundary | Six tests: permission/revocation, symlink/mode/schema bounds, malformed/unknown requests, demo/missing/stale/reset handling |
| Real MCP client | Official TypeScript SDK 1.32.1 initialized, listed and called both tools, filtered, rejected arbitrary arguments and observed revocation; no model prompt |
| Integration lifecycle | Seven app tests: default off, real projection, demo exclusion, restart persistence, independent widget/MCP sharing and deletion |
| Native level-up trigger | Two tests: real new threshold only; selection/range/demo/hidden/replay/unknown-output cases suppressed |
| Widget build/signature | Signed embedded WidgetKit extension; version matches host; sandbox and exact team-prefixed group entitlements verified |
| Offscreen widget rendering | Actual widget source, small/medium and light/dark; fresh, old, reset-expected and missing fixtures |
| Website | Desktop/mobile, download version, clipboard, guild painting, keyboard selection, pause/Reduce Motion, new integrations/privacy pages and existing routes; no page errors or failed requests |

The first real SDK run exposed a pipe-read deadlock: exact-length FileHandle reads could wait for a full buffer.
The server now uses bounded POSIX streaming reads. The SDK rerun passed. Visual checks caught a wrapped age label
and truncated reset text; corrected before release. Offscreen rendering uses an explicit family input to the same
widget view that WidgetKit hosts; it does not claim a widget was added to the real desktop.

Sparkle 2.10.0's official tool archive matched the GitHub release SHA-256
`c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`.
The signing key was generated in Keychain; only its public key is in source. Feed generation, public-feed verification,
notarized release and installed upgrade are recorded separately after they complete.

The native computer-use tool still reports `Sky Computer Use native pipe startup failed`. Fresh physical widget
installation/gallery interaction, VoiceOver/focus traversal, old-to-new updater installation, long sleep/restart and
older/clean macOS remain unverified. No new sign-in emails or model prompts were sent. Existing persistent Claude
tracking settings were not edited by this implementation batch.

Visual evidence (synthetic, no account/session data): [small widget](2026-10-22-images/widget-small-dark.png),
[medium widget](2026-10-22-images/widget-medium-dark.png), [light widget](2026-10-22-images/widget-medium-light.png),
[native flourish frames](2026-10-22-images/native-level-flourish.png). Native TextFields are not faithfully rendered
by ImageRenderer, so an offscreen Settings capture is not treated as a real input/focus test.

Both release helper performance checks passed with 200/200 delivered frames. Paired app-present added latency:
status-line p95 5.37 ms; hook p95 0.30 ms, each under the 20 ms budget. This measures the status-line/hook path;
it does not measure widget refresh latency or updater download speed.

The first Developer ID export check correctly stopped on Sparkle Autoupdate's preserved
`com.apple.application-identifier=org.sparkle-project.Sparkle.Autoupdate` entitlement. Inspection of every exported
Mach-O confirmed this was the sole extra installer identifier; the exact role-specific allowlist now accepts it.
The other four Sparkle binaries have no entitlements. All binaries still require Clepso's Developer ID team,
hardened runtime, secure timestamp and the exact executable inventory. No arbitrary entitlement exemption was added.

Final privacy review added a publication guard across widget preference writes, startup reconciliation of an
interrupted opt-out, and direct snapshot cleanup during data deletion even when SQLite cannot open. Seven focused
sharing tests passed, including concurrent refresh/opt-out and a simulated crash boundary. These changes require
a new signed source build; the earlier build 235 artifact is superseded and must not be published.

On the earlier artifact, the official Sparkle verifier accepted the signed feed/archive and rejected a changed
signed download URL and a substituted archive. Appended XML comments are outside the signed payload, so the
negative feed test deliberately changes the enclosure URL. Repeat signature checks on the final artifact.

Final strict rerun after the opt-out correction: all 17 gates passed; 559 tests across 111 suites.
