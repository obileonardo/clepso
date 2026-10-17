# Tokone

Code for the AI capacity monitor (working name "Pulse"). Specifications, decisions and ADRs live in the
Tokone docs folder on the external drive (`docs/`, `ADR/`); this repository holds only code.

Build and test (Swift 6.4, Xcode 27.1 selected with `xcode-select`):

    make ci      # every quality gate with a pass/fail summary; run before asking for review
    make test    # tests only
    make perf    # helper overhead budget (ADR-003), release build, 200 runs
    make app     # Pulse.app: pinned XcodeGen (scripts/bootstrap.sh) → xcodebuild → signature check

Run the app against a throwaway home and data folder (debug builds only; never touches ~/.claude):

    build/DerivedData/Build/Products/Debug/Pulse.app/Contents/MacOS/Pulse \
        -PulseDataDirectory /tmp/pulse-data -PulseHome /tmp/pulse-home

Popover timing (DESIGN_SYSTEM §9): add `-PulseProbeOutput <dir> -PulseMeasurePopover 40 -PulseProbeDemo YES`,
then run `swift scripts/probe-popover.swift <dir> 40` (posts real clicks; needs Accessibility for the terminal).

`make ci` checks: pinned toolchain, strict build (warnings are errors), all tests, the release helper
links no networking library or symbol, no networking API in Sources/, no direct clock read in the
pure layers and the app (inject `WallClock`; `SystemClock` is the one marked exception), Theme tokens only in
components and screens, a secret scan, and the app bundle (signature, embedded helper, entitlements, no networking).
Logs land in `.build/ci-logs/`.

Milestone 0: `Domain`, `ShimProtocol` (field allowlist, frame v1), `StatusLineShim` + `pulse-statusline`
(the helper Claude Code runs), `ClaudeCodeAdapter` (reversible settings install), `Storage` (schema v1),
`TestFixtures` (F01–F19 corpus). Progress and evidence: `docs/ROADMAP.md` in the Tokone docs folder.
