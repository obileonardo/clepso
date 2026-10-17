# GitHub settings for `obileonardo/tokone`

What the repository owner must configure by hand. Nothing here was changed by the readiness review; the current
state was read on 17 Oct 2026 with read-only `gh api` calls (listed at the end).

Legend: **Now** = do while the repository is still private. **Before public** = must be done before changing
visibility. **At public** = only available, or only free, once the repository is public. **Later** = after launch.

## Current state (observed)

| Setting | Observed | Target |
|---|---|---|
| Visibility | Private | Public, only after the Stage A blockers and owner questions are resolved |
| Description | "Pulse: local AI capacity monitor for Claude Code (macOS menu bar)" | Keep; mention Codex once public |
| Repository name | `tokone` | Rename to `pulse` deferred until after a trademark check (owner decision) |
| Homepage, topics | None | Add (see below) |
| Default branch | `main`, **not protected** | Protected by a ruleset |
| Branch protection / rulesets | Not available: the API answers "Upgrade to GitHub Pro or make this repository public" | Ruleset on `main` (At public) |
| Collaborators | Owner (admin) and one other account with **write** access | Kept as is: owner's decision (see §5) |
| Deploy keys, webhooks | None | None |
| Actions | Enabled; all actions allowed; SHA pinning not required | Allow only GitHub-owned and selected actions; require SHA pinning |
| Default workflow token | Read-only; workflows cannot approve pull requests | Keep |
| Actions secrets, variables, environments | None | Add a `release` environment only when signed builds exist |
| Dependabot alerts | Disabled | Enabled |
| Dependabot security updates | Disabled | Enabled |
| Secret scanning, push protection | Disabled | Enabled |
| Code scanning | Not enabled | Enabled (At public) |
| Private vulnerability reporting | Not enabled (endpoint returns 404) | Enabled |
| Merge methods | Merge, squash and rebase all allowed; branches not deleted on merge | Squash only; delete head branches |
| Issues / Projects / Wiki / Discussions | On / On / Off / Off | On / Off unless used / Off / Off until there is a community |
| Tags, releases | None | First pre-release tag after Stage C |
| Community profile | 28% (README only) | 100% after the drafted files merge |

## Step by step

### 1. Security (Settings › Code security) — Now where available, otherwise At public

1. **Dependabot alerts**: Enable.
2. **Dependabot security updates**: Enable.
3. **Dependabot version updates**: adopt `docs/open-source/proposed/dependabot.yml` as `.github/dependabot.yml`.
4. **Secret scanning** and **Push protection**: Enable. Free for public repositories; for a private repository it
   needs GitHub Secret Protection. Turn both on no later than the moment the repository becomes public.
5. **Private vulnerability reporting**: Enable (**owner action, required**: `SECURITY.md` names it as the only
   reporting channel). Check, after enabling, that the **Report a vulnerability** button appears on the Security tab.
6. **Code scanning**: once public, enable CodeQL *default setup*. Swift analysis needs a macOS build; if default setup
   cannot build the project, use advanced setup with `swift build` as the build command, or postpone and note it.

### 2. Actions (Settings › Actions › General) — Before public

1. **Actions permissions**: "Allow obileonardo, and select non-obileonardo, actions and reusable workflows";
   allow actions created by GitHub; add others by name only when needed.
2. **Require actions to be pinned to a full-length commit SHA**: Enable (the proposed workflow is written that way).
3. **Fork pull request workflows**: "Require approval for all outside collaborators".
4. **Workflow permissions**: keep "Read repository contents and packages permissions"; keep "Allow GitHub Actions to
   create and approve pull requests" off.
5. Adopt `docs/open-source/proposed/ci.yml` as `.github/workflows/ci.yml` after resolving its `TODO(owner)` items.
   Never use `pull_request_target` for anything that checks out pull-request code.

### 3. Ruleset for `main` (Settings › Rules › Rulesets) — At public

Create a branch ruleset targeting the default branch:

- Restrict deletions; block force pushes.
- Require a pull request before merging; 1 approval once there is a second maintainer (until then, 0 approvals but
  still via pull request, so CI runs); dismiss stale approvals on new commits; require conversation resolution.
- Require status checks to pass: the jobs from the adopted workflow (`Build and test (SwiftPM)`,
  `Quality gates (contributor mode)`); require branches to be up to date.
- Require linear history.
- Bypass list: empty, or the owner only for emergencies.
- Signed commits: optional. Useful if more maintainers join; not required for a single maintainer.

Add a tag ruleset for `v*`: restrict creation, update and deletion to the owner.

### 4. General (Settings › General) — Before public

- Pull requests: allow **squash merging** only; default commit message "Pull request title and description";
  enable **Automatically delete head branches**; enable "Always suggest updating pull request branches".
- Features: keep Issues; turn off Projects unless used; keep Wiki off (docs live in the repository); Discussions off
  until there are users asking questions.
- **Social preview**: upload an image made from a demo screenshot (Settings › General › Social preview).
- **Topics** (About › gear): for example `macos`, `menu-bar-app`, `swift`, `swiftui`, `claude-code`,
  `developer-tools`, `usage-monitor`, `privacy`.
- **Homepage**: the documentation site URL (the owner has approved the site for publication).

### 5. Access — Now

- **Second collaborator: keeps write access (owner's decision, 17 Oct 2026).** A read-only role is not available on a
  repository owned by a personal account; it needs an organization-owned repository (or, for viewing only, a public
  one). Until a ruleset protects `main` (§3, at public), write access includes pushing directly to `main`.
- Confirm two-factor authentication on the owner account.
- Labels for contributors: `good first issue`, `help wanted`, `triage`, `bug`, `enhancement`, `documentation`,
  `privacy` (changes that touch what Pulse reads or sends), `security` (for advisories, not public issues).

### 6. Releases — Later

- First public release: `v0.1.0-alpha` (owner decision), only after Stage C passes; further pre-releases
  `v0.1.0-alpha.N` until there is a signed, notarized build.
- Release notes from the changelog; attach the notarized DMG and its SHA-256; include third-party licence texts
  (GRDB, fonts) in the app bundle or the release download.
- Signed builds run in a separate workflow bound to a `release` environment with the owner as required reviewer.
  The Developer ID certificate and notarization credentials live only in that environment.

## Commands used to read the current state

All read-only (`GET`):

```
gh api repos/obileonardo/tokone
gh api repos/obileonardo/tokone/branches
gh api repos/obileonardo/tokone/branches/main/protection
gh api repos/obileonardo/tokone/rulesets
gh api repos/obileonardo/tokone/vulnerability-alerts
gh api repos/obileonardo/tokone/automated-security-fixes
gh api repos/obileonardo/tokone/private-vulnerability-reporting
gh api repos/obileonardo/tokone/actions/permissions
gh api repos/obileonardo/tokone/actions/permissions/workflow
gh api repos/obileonardo/tokone/actions/secrets
gh api repos/obileonardo/tokone/actions/variables
gh api repos/obileonardo/tokone/environments
gh api repos/obileonardo/tokone/collaborators
gh api repos/obileonardo/tokone/invitations
gh api repos/obileonardo/tokone/hooks
gh api repos/obileonardo/tokone/keys
gh api repos/obileonardo/tokone/tags
gh api repos/obileonardo/tokone/releases
gh api repos/obileonardo/tokone/pages
gh api repos/obileonardo/tokone/community/profile
gh api repos/obileonardo/tokone/secret-scanning/alerts
gh api repos/obileonardo/tokone/code-scanning/alerts
gh api repos/obileonardo/tokone/dependabot/alerts
```
