# Releasing Clepso for macOS

How a signed, notarized Clepso build is made (roadmap increment 4.1). This is the maintainer's runbook; contributors
never need it, and nothing here is required to build from source (`make app` signs ad hoc).

> **State on 18 Oct 2026: no release has been made.** The commands below follow Apple's documented Developer ID flow
> and the project's own build, but the archive, export, notarization and DMG steps have **not been run** for this
> project yet. Mark each step done here the first time it succeeds, with the date.

## 1. What a release is

- A Developer ID signed, hardened-runtime, notarized and stapled `Clepso.app` in a signed, notarized DMG.
- No App Sandbox, no entitlement exceptions: `App/PulseMac/PulseMac.entitlements` is an empty dictionary, and the
  helper (`Contents/Helpers/pulse-statusline`) has no entitlements file.
- No auto-update in alpha: an update check would be network traffic by default. Testers reinstall from the DMG.
- Version: `MARKETING_VERSION` (numeric semver, `0.1.0`) and `CURRENT_PROJECT_VERSION` (`git rev-list --count HEAD`
  on `main`) in `project.yml`. The channel (`alpha`) lives in the git tag and DMG name only: `v0.1.0-alpha.1`.

## 2. Prerequisites (one time)

| Item | State | Notes |
|---|---|---|
| Developer ID Application certificate (DECISIONS A6) | **Present** in the maintainer's login keychain (`security find-identity -v -p codesigning`) | Export the `.p12` once and keep it in the password manager: Apple can't re-issue a lost private key |
| Team ID and bundle prefix (A7) | **Decided** 18 Oct 2026: `com.elvisobi` (app `com.elvisobi.clepso`, helper `com.elvisobi.clepso.statusline`, sign-in scheme `clepso://`) | When the planned code-signature peer check (PRIVACY_AND_SECURITY §3) is built, its designated requirement names `com.elvisobi.clepso.statusline` |
| Notary credentials | Not set up | An App Store Connect API key (Developer role) is preferred over an Apple ID: `xcrun notarytool store-credentials clepso-notary --key <AuthKey.p8> --key-id <id> --issuer <issuer>` stores it in the keychain |
| `Config/Signing.local.xcconfig` | Present on the maintainer's Mac (gitignored) | For a release build set `PULSE_CODE_SIGN_IDENTITY = Developer ID Application` and `PULSE_DEVELOPMENT_TEAM = <TEAMID>` |

## 3. Build, sign, notarize

Run on the maintainer's Mac from a clean checkout of the release tag. Free disk first: an archive plus DerivedData
needs roughly 1.5 GB, an estimate (check `df -h /System/Volumes/Data`).

```sh
git switch --detach v0.1.0-alpha.1
make ci > build/ci.log 2>&1; echo "ci exit $?"      # must print 0; read the summary, never `| tail` the gate
scripts/bootstrap.sh && .tools/xcodegen/bin/xcodegen --quiet

V=0.1.0; B=$(git rev-list --count HEAD)
xcodebuild -project Pulse.xcodeproj -scheme PulseMac -configuration Release \
  -archivePath build/Clepso.xcarchive MARKETING_VERSION=$V CURRENT_PROJECT_VERSION=$B ONLY_ACTIVE_ARCH=NO archive
xcodebuild -exportArchive -archivePath build/Clepso.xcarchive -exportPath build/export \
  -exportOptionsPlist build/ExportOptions.plist     # method developer-id, signingStyle manual, teamID <TEAMID>
```

`build/ExportOptions.plist` (not committed, it names the team):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>teamID</key><string>TEAMID</string>
</dict></plist>
```

Check the signature before spending a notarization on it:

```sh
APP=build/export/Clepso.app
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E 'Authority=Developer ID Application|flags=0x10000\(runtime\)|Timestamp='
codesign -d --entitlements - --xml "$APP" | grep -c 'com.apple.security' # must print 0
codesign -dvv "$APP/Contents/Helpers/pulse-statusline" 2>&1 | grep -E 'Identifier=|flags=0x10000\(runtime\)'
lipo -archs "$APP/Contents/Helpers/pulse-statusline"                    # arm64 x86_64: Claude Code may run under Rosetta
```

Notarize, staple, package:

```sh
ditto -c -k --keepParent "$APP" build/Clepso.zip
xcrun notarytool submit build/Clepso.zip --keychain-profile clepso-notary --wait --output-format json > build/notary-app.json
xcrun stapler staple "$APP" && xcrun stapler validate "$APP"

mkdir -p build/dmg && cp -R "$APP" build/dmg/ && ln -sf /Applications build/dmg/Applications
hdiutil create -volname Clepso -srcfolder build/dmg -ov -format UDZO "build/Clepso-$V-alpha.1.dmg"
codesign --sign "Developer ID Application" --timestamp "build/Clepso-$V-alpha.1.dmg"
xcrun notarytool submit "build/Clepso-$V-alpha.1.dmg" --keychain-profile clepso-notary --wait --output-format json > build/notary-dmg.json
xcrun stapler staple "build/Clepso-$V-alpha.1.dmg"

spctl --assess --type execute -vv "$APP"                                                   # accepted, Notarized Developer ID
spctl --assess --type open --context context:primary-signature -vv "build/Clepso-$V-alpha.1.dmg"
shasum -a 256 "build/Clepso-$V-alpha.1.dmg" > build/SHA256SUMS
```

Any notarization status other than `Accepted`: `xcrun notarytool log <submission id> --keychain-profile clepso-notary`,
fix, rebuild. Never ship a build that was not accepted.

## 4. Release gate

| Gate | Evidence |
|---|---|
| `make ci` exit 0 on the tag | `build/ci.log` summary |
| Signed with Developer ID, hardened runtime, no `com.apple.security.*` entitlements | section 3 checks |
| Notarized and stapled, app and DMG | `notary-*.json`, `stapler validate`, `spctl` output |
| Helper overhead budget | `make perf` on the maintainer's Mac |
| Launches from `/Applications` on a clean user account; login item registers only after consent | founder's run, screenshot |
| No network traffic by default (Sync off unless signed in) | CI "networking only in Sync" check plus a packet capture on the clean account |
| Release notes say what is unverified (Intel Macs, macOS 14 and 15, no auto-update in alpha) | the draft release |

Publish with `gh release create v$V-alpha.1 --draft` (DMG, `SHA256SUMS`, both `notary-*.json`); the founder
publishes the draft.

## 5. Open decisions that change the signed build

- **Bundle prefix (A7).** Decided: `com.elvisobi`. See section 2.
- **Calendar through EventKit.** Add-to-Calendar (2.5) currently writes an `.ics` file that Calendar imports after
  asking the user, which needs no entitlement or permission. Adding events directly with EventKit write-only access
  (NOTIFICATIONS §3.1's first choice on macOS) would need `com.apple.security.personal-information.calendars` under
  the hardened runtime and an `NSCalendarsWriteOnlyAccessUsageDescription` string, which changes the "no
  entitlements" line of the release gate. Recommendation: keep `.ics` for alpha.
- **Sync.** An official build with `Config/Sync.local.xcconfig` set can sign in and upload hourly once the user
  signs in; a build without it never contacts the network. Decide which one the alpha DMG is.
