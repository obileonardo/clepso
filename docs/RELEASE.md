# Releasing Clepso for macOS

How a signed, notarised Clepso build is made (roadmap increment 4.1). This is the maintainer's runbook; contributors
never need it, and nothing here is required to build from source (`make app` signs ad hoc).

> **State on 19 Oct 2026.** `scripts/release.sh` (`make release TAG=…`) runs the whole flow below. A trial run on
> branch `release/v0.1.0-alpha` built, signed, checked and packaged `v0.1.0-alpha.1` up to notarisation, which waits for
> the notary profile (section 2). Notarisation, stapling and publishing have **not been run** yet. Mark each step
> done here the first time it succeeds, with the date.

## 1. What a release is

- A Developer ID signed, hardened-runtime, notarised and stapled `Clepso.app` in a signed, notarised, stapled DMG,
  plus `SHA256SUMS`.
- No App Sandbox, no entitlement exceptions: `App/ClepsoMac/ClepsoMac.entitlements` is an empty dictionary and the
  app's signature carries no entitlements at all (no `get-task-allow` in Release). The helper
  (`Contents/Helpers/clepso-statusline`) has no entitlements file; its signature carries only
  `com.apple.application-identifier = <team>.com.elvisobi.clepso.statusline`, which Xcode adds to every command-line tool
  signed with a team (`ENTITLEMENTS_REQUIRED=NO`, an empty entitlements file and an empty team were tried on 19 Oct
  2026: none removes it, and a tool without a team can't be signed). It grants nothing; the helper runs natively and
  under Rosetta with it.
- Architectures (DECISIONS C4): the app is arm64 only in alpha; the helper is universal (`arm64 x86_64`) because
  Claude Code may run it under Rosetta. Set per target in `project.yml`.
- No accounts in alpha unless the founder decides otherwise (RELEASE_ROADMAP §5: Supabase's built-in email only reaches
  the project team, so nobody else could sign in). `scripts/release.sh` builds without the accounts project by default,
  so the build never touches the network; `--with-accounts` keeps `Config/Sync.local.xcconfig`.
- No auto-update in alpha (C3; opt-in update checks come at beta, v0.5). Testers reinstall from the DMG.
- Release features (`Sources/ClepsoApp/System/ReleaseFeatures.swift`): release builds use `ReleaseFeatures.shipping`.
  For v0.1 that hides the player Card and Goals (revealed in v0.2); their data keeps collecting. Debug builds show
  everything; `-ClepsoReleaseFeatures shipping` shows what a release shows. Switch them on for v0.2 by changing
  `shipping`.
- Version: `MARKETING_VERSION` (numeric semver, `0.1.0`) in `project.yml`; `CURRENT_PROJECT_VERSION` is
  `git rev-list --count HEAD` at the tagged commit, set by the script. The channel lives only in the tag and the DMG
  name: tags `v0.1.0-alpha.1`, `v0.1.0-alpha.2`, … (founder decision, 19 Oct 2026). The app shows its version under
  the name in the Dashboard's sidebar.

## 2. Prerequisites (one time)

| Item | State | Notes |
|---|---|---|
| Developer ID Application certificate (DECISIONS A6) | **Present** in the maintainer's login keychain (`security find-identity -v -p codesigning`) | Export the `.p12` once and keep it in the password manager: Apple can't re-issue a lost private key |
| Team ID and bundle prefix (A7) | **Decided** 18 Oct 2026: `com.elvisobi` (app `com.elvisobi.clepso`, helper `com.elvisobi.clepso.statusline`, sign-in scheme `clepso://`) | The script checks the helper against `anchor apple generic and identifier "com.elvisobi.clepso.statusline" and certificate leaf[subject.OU] = "<TEAMID>"` |
| Notary credentials | **Not set up** (19 Oct 2026) | See below |
| `Config/Signing.local.xcconfig` | Present on the maintainer's Mac (gitignored) | The script reads the team from `CLEPSO_DEVELOPMENT_TEAM` (or `CLEPSO_TEAM_ID` in the environment) and signs with "Developer ID Application" whatever identity the file names for daily builds |

**Notary profile.** Once, on the release Mac, store credentials under the profile name the script uses,
`clepso-notary`. With an Apple ID and an app-specific password (made at account.apple.com › Sign-In and Security ›
App-Specific Passwords; the command prompts for it, so it stays out of shell history):

```sh
xcrun notarytool store-credentials clepso-notary --apple-id <Apple ID email> --team-id DD8UY75RZT
xcrun notarytool history --keychain-profile clepso-notary     # check: lists past submissions (none yet), no error
```

An App Store Connect API key (Developer role) works too and is what a CI release workflow would use:
`xcrun notarytool store-credentials clepso-notary --key <AuthKey.p8> --key-id <id> --issuer <issuer>`.

## 3. Build, sign, notarise: `scripts/release.sh`

Run on the maintainer's Mac from a clean checkout of the release commit, with roughly 8 GB free
(`df -h /System/Volumes/Data`; the script refuses below 8 GB).

```sh
git switch --detach <release commit on main>
make ci > build/ci.log 2>&1; echo "ci exit $?"   # must print 0; read the summary, never `| tail` the gate
make release TAG=v0.1.0-alpha.1                 # = scripts/release.sh v0.1.0-alpha.1
```

Output goes to `build/release/<tag>/` (gitignored), with `release.log` and every tool's log in `logs/`. The script:

1. **Preflight.** The tag's version equals `MARKETING_VERSION`; a clean tree (`--allow-dirty` for trials only; never
   publish a dirty build); if the tag exists it must be HEAD; 8 GB free; a valid Developer ID Application identity for
   the team; whether the `clepso-notary` profile works (checked first, so a missing one is reported early).
2. **Archive** (Release, `generic/platform=macOS`, `ONLY_ACTIVE_ARCH=NO`, version and build number set) and
   **export** with `method developer-id`, manual signing: Xcode re-signs inside-out with the hardened runtime and a
   secure timestamp.
3. **Checks on the exported app** (any failure stops the script):
   - `codesign --verify --deep --strict --verbose=2`;
   - the bundle holds exactly two executables, `Contents/MacOS/Clepso` and `Contents/Helpers/clepso-statusline`;
   - each: `Authority=Developer ID Application: … (<team>)`, `TeamIdentifier`, `flags=0x10000(runtime)`, a
     `Timestamp=` line, entitlements as in section 1, and none of the debug-only names in
     `scripts/debug-only-names.regex` (probe flags, `-Clepso…` launch arguments, `CLEPSO_SHIM_NOW_MS`,
     `CLEPSO_SHIM_RELAXED_BUDGET`) in `strings -a`;
   - the helper's identifier and its peer-check requirement (`codesign --verify -R=…`);
   - `lipo -archs`: app `arm64`, helper `arm64` and `x86_64`;
   - `Info.plist`: bundle id, version, build, `LSUIElement`, and the accounts project present only with
     `--with-accounts`;
   - licences: `Contents/Resources/LICENSE` (byte-identical to the repository's), `Acknowledgements.txt` (GRDB),
     `ClepsoFonts-OFL.txt`;
   - `spctl -a -vvv -t exec`: before notarisation it must say `source=Unnotarized Developer ID`; after, `accepted` and
     `source=Notarized Developer ID`, and `stapler validate` must pass.
4. **A signed DMG** (`Clepso-<version>-<channel>-UNNOTARIZED.dmg`): the app and an `Applications` link, HFS+, UDZO,
   signed with the Developer ID and a timestamp, `codesign --verify --strict`, `hdiutil verify`, then mounted read-only
   to check its contents and that the app inside has the same CDHash as the checked one.
5. **Without the notary profile it stops here** (exit 3) and prints the command from section 2. Everything above is
   built and checked; the `-UNNOTARIZED` DMG must never be published.
6. **Notarise the app** (`ditto` zip, `notarytool submit --keychain-profile clepso-notary --wait`, JSON in
   `notary-app.json`), staple it, and run the checks again as `post`.
7. **The final DMG** from the stapled app (`Clepso-<version>-<channel>.dmg`), notarised (`notary-dmg.json`), stapled,
   `stapler validate`, and `spctl --assess --type open --context context:primary-signature -vv` must say `accepted`,
   `source=Notarized Developer ID`.
8. **`SHA256SUMS`** for the DMG, and `publish-commands.txt` with the tag and `gh release` commands (section 5), not run.

Any notarisation status other than `Accepted` prints `xcrun notarytool log <id>` and fails. Never ship a build that
was not accepted.

`make ci` also has a **"release build has no debug code"** gate: it builds `ClepsoApp` and the helper in release and
fails if any release object contains a name from `scripts/debug-only-names.regex` (and if the debug build shows fewer
than ten of them, which would mean the list has gone stale).

## 4. Release gate

| Gate | Evidence |
|---|---|
| `make ci` exit 0 on the release commit | `build/ci.log` summary |
| Signed with Developer ID, hardened runtime, secure timestamp, entitlements as in section 1, no debug-only code | `release.log`, section 3 step 3 |
| Notarised and stapled, app and DMG | `notary-*.json`, `stapler validate`, `spctl` lines in `release.log` |
| Helper overhead budget | `make perf` on the maintainer's Mac |
| Launches from `/Applications` on a clean user account; login item registers only after consent | founder's run, screenshot |
| No network traffic (no accounts project in the alpha build) | CI "networking only in Sync" check, `Info.plist` check, plus a packet capture on the clean account |
| Release notes say what is unverified (Intel Macs, macOS 14 and 15, no auto-update in alpha) | `docs/release-notes/<tag>.md` |

## 5. Publishing (the founder's decision)

Publishing is public and only the owner may create `v*` tags (tag ruleset, `docs/open-source/GITHUB_SETTINGS.md` §3).
After the gate passes, from the same clean checkout (the script writes these, filled in, to
`build/release/<tag>/publish-commands.txt`):

```sh
git tag -a v0.1.0-alpha.1 <release commit> -m "Clepso 0.1.0 alpha.1"
git push origin v0.1.0-alpha.1
gh release create v0.1.0-alpha.1 --repo obileonardo/clepso --verify-tag --prerelease --draft \
  --title "Clepso 0.1.0 alpha.1" --notes-file docs/release-notes/v0.1.0-alpha.1.md \
  build/release/v0.1.0-alpha.1/Clepso-0.1.0-alpha.1.dmg build/release/v0.1.0-alpha.1/SHA256SUMS
```

The draft is checked on GitHub (assets, notes, pre-release flag), then the founder publishes it.

## 6. Open decisions that change the signed build

- **Accounts in the alpha.** Default: none (section 1). Building with `--with-accounts` puts the accounts project in
  the app; the release notes' "No network in this build" line then has to change.
- **Calendar through EventKit.** Add-to-Calendar (2.5) currently writes an `.ics` file that Calendar imports after
  asking the user, which needs no entitlement or permission. Adding events directly with EventKit write-only access
  would need `com.apple.security.personal-information.calendars` under the hardened runtime and an
  `NSCalendarsWriteOnlyAccessUsageDescription` string, which changes the entitlement check above. Recommendation: keep
  `.ics`.
