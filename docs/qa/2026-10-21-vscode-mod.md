# VS Code mod live check — 21 October 2026

Source implementation: merged PR #16, `ce9a4ac`; no app, mod or helper source changes for this check.
The owner approved installing official VS Code and Anthropic's extension, temporary mod access and up to two
short model replies. Exactly two replies were used, each explicitly requesting no tools or file access.

## Environment and method

- VS Code **1.142.0**, Apple silicon, downloaded from Microsoft's official update service. Archive SHA-256
  matched Microsoft's metadata; deep/strict code-signature verification passed; Gatekeeper accepted the app as
  Notarized Developer ID. Installed in `~/Applications/Visual Studio Code.app`.
- Official Marketplace extension **`anthropic.claude-code` 2.1.305**, verified publisher Anthropic. The graphical
  panel ran with `claudeCode.useTerminal=false` in a temporary profile and an empty, test-only trusted folder.
  VS Code telemetry and extension auto-updates were disabled in that profile. No project source was opened.
- The normal reversible `ClaudeModInstaller` installed the unchanged mod. As in the
  [isolated desktop check](2026-10-21-desktop-mod.md#follow-up-isolated-desktop-quotas), a private helper called
  the existing `StatusLineShim.modMain` implementation with a test-only configuration dictionary. A separate local
  socket/key collected sanitized frames while normal terminal tracking continued.
- The normal `FrameMapper` and an in-memory `Store` with `LedgerPolicy.everyReading` verified adoption without
  competing terminal observations or ledger compaction. The verifier did not write the production database.
- To compare hook identity, matched session **filename metadata only** to the captured HMAC reference, then used
  the production helper's key to query that same session read-only. No transcript body, raw session id or key
  material was exported.

## Results

| Check | Observed result |
| --- | --- |
| Plugin discoverability before use | Native IDE manager listed `clepso-limits@clepso`, enabled at user scope |
| First new session | First approved reply delivered through the mod; both replies completed normally |
| Surface and version | Three frames, all `via=mod`, `surface=vscode`, source version 2.1.305 |
| Quotas and resets | All three frames contained both windows; normal mapper/store adopted both percentages and reset instants |
| Native usage comparison | Both captured percentages within one point of the later native IDE display; other terminal usage continued |
| Reset comparison | Reset instants agreed with the IDE's coarse hour/day countdowns; no exact native timestamp comparison claimed |
| Model | `claude-fable-5-1` matches the isolated desktop capture and the IDE's selected Fable 5.1 label |
| Hook/session identity | Two production hook tasks match the captured IDE session after accounting for the independent test HMAC key |
| Status-line observations | No status-line observation retained for that IDE session; this does not prove the panel never invokes the command |
| Removal | Installer removed its entries/files and preserved the model selection that Claude changed during the test |
| Original settings | After separately restoring that test-selected model, original settings bytes and mode match exactly; terminal status-line setting unchanged |
| Collector/runtime | Collector stopped; IDE quit verified by process inspection |
| Removal in native plugin UI | Unverified: post-test capture repeatedly failed with ScreenCaptureKit errors -3812/-3811, including after relaunch |

## Settings restoration detail

Selecting Fable in the IDE changed the shared settings' `model` from `opus` to `fable`. Therefore uninstall correctly
returned `removedEntries(formattingChanged: false)` rather than overwriting that change with the old backup.
After removal, comparison showed **only** `model` differed semantically. A private guarded restoration refused
any other or concurrent change, saved the post-removal file privately, and atomically restored the pre-test bytes
and original mode. Both were rechecked after the IDE relaunch. This final byte match is a separate restoration
step, not an assertion that the installer itself returned `restoredExactly` for this test.

The installed VS Code app and official extension remain available. No temporary Clepso mod, handoff script,
install record or collector remains active. Safe receipts stay in the private planning workspace; settings
backups, raw frames and HMAC keys are excluded from Git and recovery archives. No additional model prompts or
emails are authorized by this completed test.

## Remaining release gates

The installed shipping app's menu-bar and Settings presentation, takeover after a terminal source becomes quiet,
and native plugin removal/discoverability still need verification. Full VoiceOver, long sleep/restart and
older/clean macOS checks remain separate QA. Keep `ReleaseFeatures.shipping.claudeMod` off; this check changes
neither the public app version nor the DMG.
