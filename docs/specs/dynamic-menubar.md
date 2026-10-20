# Dynamic menu bar readout

Founder request, 20 October 2026: follow Hearth's rotating status readout so Claude Code and Codex's individual
5-hour and 7-day windows are visible without opening the panel. Keep Clepso's existing pixel state family. Alpha 4 adds an opaque coloured capsule using the selected theme's
accent and status tokens, as requested in the founder's second visual review.

Default: rotate configured agents' windows every six seconds. Exhausted, critical and approaching windows lead
the cycle, in that order; every other configured window still gets a turn. Each frame's glyph describes that
frame's own reading. A change in the severity ordering restarts at the most pressing window. There is no tween,
flashing or heartbeat animation. Reserve a common width for all frames and future three-digit percentages.

Settings → General → Menu bar readout also offers Most pressing limit (the existing aggregate summary), or a
pinned Claude 5-hour, Claude 7-day, Codex 5-hour or Codex 7-day reading. The choice persists across launches and is
included with preferences in export/delete. Show usage switches the whole readout off for icon-only use.

| Frame | Meaning |
| --- | --- |
| `Claude 5h 12%` | Claude Code's measured percentage used in its 5-hour window |
| `Claude 7d 56%` | Claude Code's measured percentage used in its 7-day window |
| `Codex 5h 83%` | Codex's measured 5-hour used percentage; approaching glyph |
| `Codex 7d 100%` | Codex's measured 7-day used percentage; flatline glyph |
| `Codex 7d 100% OLD` | Last reported percentage, explicitly old; stale ring modifier |
| `Claude 5h RESET?` | Reset time passed; waiting for evidence, never inferred availability |
| `Claude 7d N/A` | Agent did not report that window; never fabricated as zero |
| `Codex 5h WAIT` | Reading enabled, but no first report yet |
| `Codex 5h OFF` | Agent is not connected/enabled; appears only when pinned, excluded from rotation |
| `Claude 5h ERROR` | The reading failed validation |
| `DEMO Claude 5h 83%` | Explicit fixture data, with the demo glyph; never includes real Codex readings |

Unlike the legacy aggregate summary, an attributed window can show its measured 100% beside the flatline, and an
old percentage with the explicit OLD suffix. This is the new founder-requested presentation; the old aggregate
no-percentage rules remain available in Most pressing limit. The state engine and reset verification rules do
not change. Manual allowance entries remain separate from automatic Claude Code/Codex telemetry.

Rotation pauses while hovering, with Reduce Motion, and with VoiceOver. Reduce Motion/VoiceOver keep the leading
frame stable; a pinned mode is a persistent stop control. The accessible label and help contain all four windows,
their freshness and reported reset times, so no information depends on waiting for a frame. The panel retains
its normal keyboard access to the complete readings. The menu bar label gets ReduceMotionRoot directly because
it lives outside the app's themed windows.

Verification: MenuBarReadoutTests covers the four-window cycle, attribution, urgent ordering, pinning, missing,
waiting, disabled, actual zero, stale, reset-passed and recovery states, plus template-image width stability.
AppModelTests covers persistence of the selected mode. Existing MenuBarStateTests protect the aggregate rules.

The isolated native probe samples the actual NSStatusBarButton images four times over approximately 20 seconds.
With the two-window Claude demo it verifies two distinct images and one width (155 points); Reduce Motion verifies
one image throughout. It reads only this process's own status item, so it needs neither screen recording nor
Accessibility permission. Run the signed debug app with `-ClepsoHome <temporary-home> -ClepsoProbeOutput <output-dir>
-ClepsoProbeMenuBar YES`; repeat with `-ClepsoProbeReduceMotion YES`. The resulting `menu-bar-report.json` must say
`passed: true`. The probe automatically exits and does not change the installed app's home, data or preferences.

Local verification on 20 October 2026: all 16 contributor CI gates pass, including warnings-as-errors,
538 tests across 107 suites, release debug-code exclusion, privacy/design/motion/keyboard checks and the signed
native app bundle. Both actual-status-button probe runs pass: normal rotation produces two distinct frames at a
fixed 155 × 16 points; Reduce Motion produces one stable frame at the same size. These are in-process native
image checks, not a claim that a full keyboard/form/Calendar-import or separate clean-user QA run was performed.

The founder's installed-app screenshot exposed a horizontal alignment regression in alpha 2: unused reserved
width sat entirely after the label. Alpha 3 centers the entire icon/label group within that canvas, snapping its
offset to whole points. The rendering test now measures the actual bitmap's left/right ink margins as well as
the common frame width, so a left-aligned label cannot pass on canvas dimensions alone.

Alpha 4 visual revision: visible labels are uppercase, with the actual bundled `ClepsoPixel-Regular` display face
at 10 pt. Spoken labels retain natural case. The coloured capsule is 20 pt tall with 6 pt horizontal content
padding (2 layout pixels less than the previous 8 pt inset). macOS still owns the status item's click target and
popover. Shorter frames remain centred in a shared width; the maximum normal reservation is `CLAUDE 5H 99.9% OLD`.
The dark palette's accent fills the normal capsule (Phosphor green by default); approaching and reached limits use
amber and coral, stale/waiting/off use their semantic tokens. Ink is whichever theme text/background token has
higher contrast against that fill. Tests require at least 4.5:1 for every state in every theme. The original
template renderer remains available for brand assets and keeps its custom-height behaviour.
