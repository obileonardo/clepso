# Security policy

Pulse installs a helper that Claude Code runs on every status-line refresh, edits `~/.claude/settings.json`, listens on
a local socket, and can optionally sync daily counts to a hosted backend. Reports about any of these are very welcome.

## Supported versions

Pulse has not had a public release. Security fixes are made on `main`; once releases exist, only the latest release
will receive fixes.

| Version | Supported |
|---|---|
| `main` | Yes |
| Anything else | No |

## Reporting a vulnerability

**Please do not open a public issue, discussion or pull request for a security problem.**

Report privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**
(GitHub private vulnerability reporting). This is the only reporting channel for now.

<!-- PLACEHOLDER: a project contact alias (not a personal address) may be added here later. -->

Please include:

- What is affected (the helper `pulse-statusline`, the app, the settings installer, the `pulse` CLI, the Sync client,
  the Supabase schema, or the documentation site), and the commit or version.
- Steps to reproduce, and what an attacker needs (another local user? a process running as the same user? a
  malicious web page? network position?).
- The impact you see, and any suggested fix.

Please use synthetic data in reports. Do not include real prompts, transcripts, tokens or other people's data.

## What to expect

These are targets, not guarantees, for a project maintained by one person:

- Acknowledgement within 5 working days.
- An initial assessment within 10 working days.
- A fix or mitigation plan agreed with you before any public disclosure. We aim to publish an advisory, crediting
  you if you wish, once a fix is available.

## Scope

In scope, for example:

- Data leaving the helper that the field allowlist should have blocked (paths, prompts, ids, secrets).
- Ways to make the helper alter, delay beyond its budget, or break the user's own status-line output.
- Ways to corrupt or lose the user's `~/.claude/settings.json`, or to make Pulse write outside its own files.
- Local privilege or trust-boundary problems in the Unix socket (`~/Library/Application Support/Pulse/run/`).
- Injection through the `dev.tokone.pulse://` URL scheme or the sign-in flow.
- A build from source (no `Config/Sync.local.xcconfig`) that signs in or makes any network request.
- Row-level-security bypasses or cross-account access in `backend/supabase`.
- Supply-chain problems in the build (the pinned XcodeGen download, `Package.resolved`).

Out of scope:

- Anything that requires an attacker who already runs code as the same macOS user, *unless* Pulse makes that
  attacker meaningfully more powerful (such a process can already read and edit `~/.claude` directly).
- Values that Claude Code itself reports incorrectly.
- Denial of service against the hosted backend by volume, and findings from automated scanners without a
  demonstrated impact.
- Social engineering of the maintainer.

## Security design notes

How Pulse limits what it can see and do is described in
[`docs/PRIVACY_AND_SECURITY.md`](docs/PRIVACY_AND_SECURITY.md). Known gaps that are planned work rather than
vulnerabilities:

- The local socket accepts any peer running as the same user; it does not yet verify the peer's code signature.
- Builds are not yet Developer ID signed or notarized.
