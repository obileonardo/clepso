# Contributing to Pulse

Thank you for your interest. Pulse is a small, privacy-sensitive macOS app: the helper it installs runs inside every
Claude Code session of the people who use it. That shapes how changes are proposed, reviewed and tested here.

> The project is pre-release. Some items below (labels, branch protection, hosted CI) describe how the project will
> work once it is public; until then, the maintainer applies them by hand.

## Ways to contribute

- **Report a bug**: open an issue with the *Bug report* form. Include your macOS version, Claude Code version
  (`claude --version`), Pulse version (shown under the name in the Dashboard sidebar), what you expected and what
  happened. If the diagnostics log (Settings › Diagnostics) helps, copy the relevant lines and **read them before
  posting**; the log is designed to hold no paths, prompts or ids, but you are the judge of what you share.
- **Propose a feature**: open an issue with the *Feature request* form first. Changes that make Pulse read a new
  source, forward a new field, or touch the network need agreement on the design before code (see
  [Changes that need a design discussion](#changes-that-need-a-design-discussion)).
- **Improve documentation**: the *Documentation* form, or a pull request directly for small fixes.
- **Security issues**: never in a public issue. Follow [`SECURITY.md`](SECURITY.md).

Good first contributions: documentation fixes, new synthetic fixtures for edge cases in Claude Code's status-line
JSON, accessibility (VoiceOver labels, contrast), and tests for existing behaviour. Issues suited to newcomers will be
labelled `good first issue`.

## Development setup

You need macOS with Xcode and a Swift 6 toolchain (the project is developed with Xcode 27.1 and Swift 6.4):

```sh
sudo xcode-select -s /Applications/Xcode.app
swift build
swift test
make ci-contributor      # every gate; any Swift 6 toolchain, ad-hoc signing, Sync off. Logs in .build/ci-logs/
```

`make ci-contributor` runs the same checks as the maintainer's strict `make ci`, except that it accepts your
toolchain version, an ad-hoc signature and a build without an accounts project. You need no signing certificate and
no configuration: without `Config/*.local.xcconfig`, `make app` signs ad hoc and the app's Sync stays off, so a
contributor build never talks to any server. The README's [Run it safely](README.md#run-it-safely) section shows how
to launch a debug build against a throwaway home folder.

Design references: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md),
[`docs/PRIVACY_AND_SECURITY.md`](docs/PRIVACY_AND_SECURITY.md) and [`docs/FIXTURES.md`](docs/FIXTURES.md). Code
comments cite their sections (for example `DATA_MODEL §5.1`).

Never point a development build at your real `~/.claude` unless you mean to; use `-PulseHome` and
`-PulseDataDirectory`.

## Before you open a pull request

1. Run `make ci-contributor` and paste the summary into the pull request.
2. Add or update tests for every behaviour change. A bug fix should come with a test that fails without the fix.
3. Update the README or other docs if behaviour, commands or requirements change.
4. Keep the change focused: one concern per pull request, no unrelated reformatting.
5. Fill in the pull request template, including the privacy and security section.

## Coding conventions

These are enforced by `make ci` where noted; reviewers check the rest.

- **Swift 6 language mode, warnings are errors** (`make ci`: strict build).
- **Inject time.** No `Date()` in `Domain`, `ClaudeCodeAdapter`, `ShimProtocol`, `UsageEngine`, `Storage` or
  `PulseApp`; take a clock (`WallClock`) instead. `SystemClock` is the one marked exception (`make ci`: clock injected).
- **Network only in `Sources/Sync`**, and only the app imports `Sync` (`make ci`: networking only in Sync). The helper
  must never link networking (`make ci`: helper links no networking).
- **Design tokens only.** Components and screens take colour, spacing and type from `Theme`, and icons from
  `PixelIcon`/`PixelLabel`, never system symbols (`make ci`: design tokens only).
- **Redaction.** Wrap sensitive values in `Redacted<T>`; call `unsafeReveal` only in `Storage` and `StatusLineShim`
  (`make ci`: redaction audit).
- **User-facing text** lives in `Sources/PulseApp/Copy/Copy.swift`. Say only what the source reports: a missing
  value is "not reported", never zero; estimates are labelled as estimates.
- **Accessibility.** Text is at least 12 pt; every state must be distinguishable without colour; text meets 4.5:1
  contrast in light and dark modes (tests in `DesignSystemTests`).
- **Formatting.** No formatter is configured yet. Match the surrounding code: four-space indentation, lines up to
  about 150 characters, doc comments that explain *why*.

## Tests

- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`).
- Anything that touches files runs in a throwaway folder: see `Sandbox` in `Tests/PulseAppTests/Support.swift` and
  `ShimHarness` in `Tests/ShimIntegrationTests/`. Integration tests run the built `pulse-statusline` with `HOME`
  pointed at a temporary folder. **No test may read or write the real `~/.claude`, `~/.codex`, Keychain or network.**
- Unix socket paths are limited to 104 bytes, which is why sandboxes live under `/tmp` with short names.
- **Fixtures** live in `Sources/TestFixtures/Resources/claude-code/`: `synthetic/Fxx-*` (hand-written) and
  `captured/<version>/Cxx-*` (real captures, scrubbed). Each has `meta.json`, `stdin/*.json` and `expected.json`;
  the format is in [`docs/FIXTURES.md`](docs/FIXTURES.md). `scripts/fixture-oracle.py --check` verifies expectations
  independently of the Swift code.
- **Never commit an unscrubbed capture.** Real captures go through `pulse-fixture` and its scrubber
  (`Sources/FixtureTools/CaptureScrubber.swift`), and `meta.json` must say `"scrubbed": true`. Review every string by
  eye before committing.
- **Canary tests** (`Tests/ShimIntegrationTests/CanaryLeakTests.swift`, `HookModeTests.swift`) put marker strings
  in every field that must not leave the helper. If you change the allowlist, extend them.
- Prefer a negative control: show that the test fails when the behaviour is removed.

## Changes that need a design discussion

Open an issue before writing code for any of these:

- Adding, removing or widening a field in `Sources/ShimProtocol/Allowlist.swift` or `HookFrame.swift`.
- Reading any new file or source on the user's machine.
- Anything that sends data off the machine, or changes what `Sync` uploads or the backend schema. Never commit an
  accounts project's host or key: they belong in the uncommitted `Config/Sync.local.xcconfig` (`make ci` checks).
- Changes to how `~/.claude/settings.json` is modified, backed up or restored.
- New dependencies. Pulse has one third-party package (GRDB); each new one needs a reason, a licence check and an
  exact pin in `Package.resolved`.
- Database migrations (`Sources/Storage/`): they must keep every existing row and come with a migration test.

## Screenshots

Regenerate screenshots with the debug probe (README, "Run it safely") against the synthetic home from
`scripts/probe-home.py` and demo data, never against your own `~/.claude`. The probe uses a neutral profile name.

## Commits and branches

- Branch from `main`; name branches after the change (`fix/reset-countdown`, `docs/install-steps`).
- Commit subjects say what changed in the imperative or as a short noun phrase; the body explains why and lists the
  evidence (tests added, gates run). See `git log` for the house style.
- Keep history readable; the maintainer may squash on merge.

## Review

- Every pull request needs the maintainer's review. Expect questions about privacy and failure behaviour first.
- Reviews aim to respond within a week; ping the pull request if you have heard nothing.
- Contributions are credited in the commit history. There is no Contributor License Agreement. By submitting a
  contribution you agree that it is licensed under the project's [MIT License](LICENSE).

## Code of Conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
