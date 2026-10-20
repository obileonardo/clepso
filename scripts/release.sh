#!/bin/bash
# Builds, signs, verifies and notarises a Clepso release: docs/RELEASE.md §3 as one repeatable script.
#
#   scripts/release.sh v0.1.0-alpha.1                  (make release TAG=v0.1.0-alpha.1)
#   scripts/release.sh v0.1.0-alpha.1 --allow-dirty    a trial run from uncommitted work (never publish its output)
#   scripts/release.sh v0.1.0-alpha.1 --with-accounts  keep the accounts project from Config/Sync.local.xcconfig
#
# Steps: Release archive → Developer ID export (hardened runtime, secure timestamp) → checks on every signed binary
# (signature, Developer ID authority, team, timestamp, no entitlements, helper identifier and requirement, architectures,
# version, shipped licences, no debug-only code) → a signed DMG, checked mounted → notarise the app → staple → the final
# DMG from the stapled app → notarise and staple the DMG → Gatekeeper assessment → SHA256SUMS.
#
# Without the `clepso-notary` keychain profile it stops right before notarising, with everything before it built and
# checked (exit 3), and prints the one command that sets the profile up. It never tags, pushes or publishes.
#
# Output: build/release/<tag>/ (gitignored): release.log, logs/, Clepso.xcarchive, export/Clepso.app,
# Clepso-<version>-<channel>-UNNOTARIZED.dmg (before notarising), Clepso-<version>-<channel>.dmg, notary-*.json,
# SHA256SUMS, publish-commands.txt.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE=clepso-notary
APP_ID=com.elvisobi.clepso
HELPER_ID=com.elvisobi.clepso.statusline
MIN_FREE_GB=8
# Debug-only names (probe flags, debug launch arguments, the helper's test clock and budget): none may reach a release
# binary. One list for this script and make ci's "release build has no debug code" gate.
DEBUG_ONLY=$(cat scripts/debug-only-names.regex)

usage() { echo "usage: scripts/release.sh v<major>.<minor>.<patch>[-alpha.N|-beta.N] [--allow-dirty] [--with-accounts]" >&2; exit 2; }
fail() { echo "RELEASE FAILED: $*" >&2; exit 1; }
step() { echo; echo "== $*"; }
ok() { echo "   ok  $*"; }

TAG="" ALLOW_DIRTY=0 WITH_ACCOUNTS=0
for arg in "$@"; do
    case "$arg" in
        --allow-dirty) ALLOW_DIRTY=1 ;;
        --with-accounts) WITH_ACCOUNTS=1 ;;
        v*) [ -z "$TAG" ] || usage; TAG="$arg" ;;
        *) usage ;;
    esac
done
[[ "$TAG" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)(-(alpha|beta)\.[0-9]+)?$ ]] || usage
VERSION="${BASH_REMATCH[1]}"
NAME="Clepso-${TAG#v}"                                     # Clepso-0.1.0-alpha.1
OUT="build/release/$TAG"
mkdir -p "$OUT"
rm -rf "${OUT:?}"/*                                         # only this release's own output folder
mkdir -p "$OUT/logs"
exec > >(tee "$OUT/release.log") 2>&1

# ---------------------------------------------------------------------------------------------------------------------
step "Preflight"
MARKETING=$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -1)
[ "$MARKETING" = "$VERSION" ] || fail "tag $TAG is version $VERSION but project.yml MARKETING_VERSION is $MARKETING"
BUILD=$(git rev-list --count HEAD)
COMMIT=$(git rev-parse HEAD)
DIRTY=$(git status --porcelain --untracked-files=no)
if [ -n "$DIRTY" ]; then
    [ "$ALLOW_DIRTY" = 1 ] || fail "uncommitted changes; release from a clean checkout of the tag (or --allow-dirty for a trial)"
    echo "   WARNING: trial build from uncommitted changes: never publish this output"
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    [ "$(git rev-parse "$TAG^{commit}")" = "$COMMIT" ] || fail "tag $TAG exists but is not HEAD ($COMMIT)"
    ok "tag $TAG is HEAD"
else
    echo "   note: tag $TAG does not exist yet; it must point at $COMMIT when published"
fi
ok "version $VERSION, build $BUILD (git rev-list --count HEAD), commit ${COMMIT:0:12}"

free_kb=$(df -k /System/Volumes/Data | awk 'NR==2 {print $4}')
[ "$free_kb" -ge $((MIN_FREE_GB * 1024 * 1024)) ] || fail "under ${MIN_FREE_GB} GB free on /System/Volumes/Data"
ok "$((free_kb / 1024 / 1024)) GB free"

TEAM="${CLEPSO_TEAM_ID:-$(sed -n 's/^ *CLEPSO_DEVELOPMENT_TEAM *= *\([A-Z0-9]*\).*/\1/p' Config/Signing.local.xcconfig 2>/dev/null | tail -1)}"
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || fail "no team id: set CLEPSO_DEVELOPMENT_TEAM in Config/Signing.local.xcconfig or CLEPSO_TEAM_ID"
identities=$(security find-identity -v -p codesigning)
IDENTITY=$(sed -n "s/.*\"\(Developer ID Application: .* ($TEAM)\)\"/\1/p" <<<"$identities" | head -1)
[ -n "$IDENTITY" ] || fail "no valid 'Developer ID Application' identity for team $TEAM in the keychain"
ok "signing identity: $IDENTITY"

NOTARY_READY=0
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >"$OUT/logs/notary-profile.log" 2>&1; then
    NOTARY_READY=1; ok "notary profile $NOTARY_PROFILE works"
else
    echo "   note: notary profile '$NOTARY_PROFILE' not usable ($(head -1 "$OUT/logs/notary-profile.log")): will stop before notarising"
fi

if [ "$WITH_ACCOUNTS" = 1 ]; then
    SYNC_ARGS=()
    echo "   accounts project: from Config/Sync.local.xcconfig (--with-accounts)"
else
    SYNC_ARGS=(CLEPSO_SYNC_HOST= CLEPSO_SYNC_PUBLISHABLE_KEY=)   # no accounts project: Sync off, no network at all
    echo "   accounts project: none (Sync off); pass --with-accounts to include it"
fi

# ---------------------------------------------------------------------------------------------------------------------
step "Archive (Release) and export with Developer ID"
scripts/bootstrap.sh >/dev/null
.tools/xcodegen/bin/xcodegen --quiet
ARCHIVE="$OUT/Clepso.xcarchive"
xcodebuild -project Clepso.xcodeproj -scheme ClepsoMac -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath build/release/DerivedData -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" ONLY_ACTIVE_ARCH=NO \
    CLEPSO_CODE_SIGN_IDENTITY="Developer ID Application" CLEPSO_DEVELOPMENT_TEAM="$TEAM" ${SYNC_ARGS[@]+"${SYNC_ARGS[@]}"} \
    archive >"$OUT/logs/archive.log" 2>&1 || { tail -30 "$OUT/logs/archive.log"; fail "archive (log: $OUT/logs/archive.log)"; }
ok "archive: $ARCHIVE"

cat >"$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>teamID</key><string>$TEAM</string>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" -exportOptionsPlist "$OUT/ExportOptions.plist" \
    >"$OUT/logs/export.log" 2>&1 || { tail -30 "$OUT/logs/export.log"; fail "export (log: $OUT/logs/export.log)"; }
APP="$OUT/export/Clepso.app"
[ -d "$APP" ] || fail "export produced no Clepso.app"
ok "exported: $APP"

# ---------------------------------------------------------------------------------------------------------------------
# verify_app <app> <pre|post>: every check that does not need Apple's notary service; `post` also requires the stapled
# ticket and Gatekeeper's "Notarized Developer ID".
verify_app() {
    local app="$1" phase="$2" out bin
    out=$(codesign --verify --deep --strict --verbose=2 "$app" 2>&1) || { echo "$out"; fail "codesign --verify --deep --strict"; }
    echo "$out" | sed 's/^/   /'
    ok "codesign --verify --deep --strict"

    local machos=()
    while IFS= read -r -d '' bin; do
        [[ "$(file -b "$bin")" == *Mach-O* ]] && machos+=("$bin")
    done < <(find "$app" -type f -print0)
    local expected=("$app/Contents/MacOS/Clepso" "$app/Contents/Helpers/clepso-statusline")
    [ "$(printf '%s\n' "${machos[@]}" | sort)" = "$(printf '%s\n' "${expected[@]}" | sort)" ] \
        || fail "unexpected executables in the bundle: ${machos[*]}"
    ok "executables: Contents/MacOS/Clepso, Contents/Helpers/clepso-statusline (nothing else)"

    for bin in "${machos[@]}"; do
        local rel="${bin#"$app"/}" info keys found
        info=$(codesign -dvv "$bin" 2>&1)
        grep -q "^Authority=Developer ID Application: .* ($TEAM)$" <<<"$info" || fail "$rel: not signed with Developer ID ($TEAM)"
        grep -q "^TeamIdentifier=$TEAM$" <<<"$info" || fail "$rel: team identifier"
        grep -q '^CodeDirectory .*flags=0x10000(runtime)' <<<"$info" || fail "$rel: no hardened runtime"
        grep -q '^Timestamp=' <<<"$info" || fail "$rel: no secure timestamp"
        # Entitlements: none. The one exception is the helper's com.apple.application-identifier = <team>.<helper id>,
        # which Xcode adds to every command-line tool signed with a team (ENTITLEMENTS_REQUIRED=NO, an empty entitlements file and no team were tried, 19 Oct 2026); it grants nothing.
        keys=$(codesign -d --entitlements - --xml "$bin" 2>/dev/null | { plutil -convert json -o - - 2>/dev/null || echo '{}'; } \
            | python3 -I -c 'import json,sys; e=json.load(sys.stdin); print(" ".join(f"{k}={v}" for k, v in sorted(e.items())))')
        if [ "$rel" = Contents/Helpers/clepso-statusline ]; then
            [ "$keys" = "com.apple.application-identifier=$TEAM.$HELPER_ID" ] || fail "$rel: unexpected entitlements: ${keys:-none}"
        else
            [ -z "$keys" ] || fail "$rel: entitlements present: $keys (the app carries none, not even get-task-allow)"
        fi
        # Captured first: `strings | grep -q` under pipefail can miss a match when grep closes the pipe early.
        found=$(strings -a "$bin" | grep -E "$DEBUG_ONLY" || true)
        [ -z "$found" ] || { sort -u <<<"$found" | head -20; fail "$rel: debug-only names in a release binary"; }
        grep -E '^(Identifier|Authority=Developer|TeamIdentifier|Timestamp|CodeDirectory)' <<<"$info" | sed "s|^|   $rel: |"
        ok "$rel: Developer ID, hardened runtime, secure timestamp, entitlements: ${keys:-none}, no debug-only names"
    done

    local helper="$app/Contents/Helpers/clepso-statusline" app_archs helper_archs
    grep -q "^Identifier=$HELPER_ID$" <<<"$(codesign -dv "$helper" 2>&1)" || fail "helper identifier is not $HELPER_ID"
    codesign --verify -R="anchor apple generic and identifier \"$HELPER_ID\" and certificate leaf[subject.OU] = \"$TEAM\"" "$helper" \
        || fail "helper does not satisfy the peer-check requirement"
    ok "helper satisfies: anchor apple generic and identifier \"$HELPER_ID\" and certificate leaf[subject.OU] = \"$TEAM\""
    app_archs=$(lipo -archs "$app/Contents/MacOS/Clepso"); helper_archs=$(lipo -archs "$helper")
    echo "   lipo -archs Clepso: $app_archs · clepso-statusline: $helper_archs"
    [ "$app_archs" = arm64 ] || fail "app should be arm64 only in alpha (DECISIONS C4), is: $app_archs"
    [[ " $helper_archs " == *" arm64 "* && " $helper_archs " == *" x86_64 "* ]] || fail "helper must be universal (C4), is: $helper_archs"
    ok "architectures: app arm64 (C4), helper universal"

    local plist="$app/Contents/Info.plist" sync
    [ "$(plutil -extract CFBundleIdentifier raw "$plist")" = "$APP_ID" ] || fail "bundle identifier"
    [ "$(plutil -extract CFBundleShortVersionString raw "$plist")" = "$VERSION" ] || fail "CFBundleShortVersionString"
    [ "$(plutil -extract CFBundleVersion raw "$plist")" = "$BUILD" ] || fail "CFBundleVersion"
    [ "$(plutil -extract LSUIElement raw "$plist")" = true ] || fail "LSUIElement"
    sync=$(plutil -extract ClepsoSyncHost raw "$plist" 2>/dev/null || true)
    if [ "$WITH_ACCOUNTS" = 1 ]; then [ -n "$sync" ] || fail "--with-accounts but no accounts project in Info.plist"
    else [ -z "$sync" ] || fail "accounts project present without --with-accounts"; fi
    ok "Info.plist: $APP_ID $VERSION ($BUILD), menu bar app, accounts project: $([ -n "$sync" ] && echo configured || echo none)"

    local res="$app/Contents/Resources"
    cmp -s LICENSE "$res/LICENSE" || fail "Contents/Resources/LICENSE missing or not the repository's LICENSE"
    grep -q 'Gwendal Rou' "$res/Acknowledgements.txt" && grep -q 'Permission is hereby granted' "$res/Acknowledgements.txt" \
        || fail "Acknowledgements.txt missing GRDB's licence"
    [ -f "$res/Clepso_DesignSystem.bundle/Contents/Resources/Fonts/ClepsoFonts-OFL.txt" ] || fail "font licence missing"
    ok "licences shipped: LICENSE, Acknowledgements.txt (GRDB), ClepsoFonts-OFL.txt"

    out=$(spctl -a -vvv -t exec "$app" 2>&1 || true)
    echo "$out" | sed 's/^/   spctl: /'
    if [ "$phase" = post ]; then
        grep -q 'accepted' <<<"$out" && grep -q 'source=Notarized Developer ID' <<<"$out" || fail "Gatekeeper does not accept the app"
        xcrun stapler validate "$app" >/dev/null || fail "no stapled ticket on the app"
        ok "Gatekeeper: accepted, Notarized Developer ID; ticket stapled"
    else
        grep -q 'source=Unnotarized Developer ID' <<<"$out" || fail "Gatekeeper should see an unnotarised Developer ID app here"
        ok "Gatekeeper: Developer ID recognised; rejected only because it is not notarised yet (expected before notarising)"
    fi
}

# make_dmg <app> <dmg>: the app and an Applications link, compressed, signed with a timestamp, and checked mounted.
make_dmg() {
    local app="$1" dmg="$2" stage="$OUT/dmg-staging" mnt out
    local stage_kb image_mb
    rm -rf "$stage" "$dmg"; mkdir -p "$stage"
    ditto "$app" "$stage/Clepso.app"
    ln -s /Applications "$stage/Applications"
    # Automatic sizing produced an unreadable UDZO image for the 0.2 payload on macOS 27. Explicit 64 MiB
    # increments verify correctly; reserve at least 16 MiB beyond the staged files for HFS+/partition metadata.
    stage_kb=$(du -sk "$stage" | awk '{print $1}')
    image_mb=$(( (stage_kb + 16384 + 65535) / 65536 * 64 ))
    hdiutil create -volname Clepso -srcfolder "$stage" -fs HFS+ -format UDZO -size "${image_mb}m" -ov "$dmg" >"$OUT/logs/hdiutil.log" 2>&1 \
        || { cat "$OUT/logs/hdiutil.log"; fail "hdiutil create"; }
    rm -rf "$stage"
    hdiutil verify "$dmg" >"$OUT/logs/hdiutil-verify-unsigned.log" 2>&1 \
        || { cat "$OUT/logs/hdiutil-verify-unsigned.log"; fail "unsigned DMG integrity"; }
    ok "unsigned DMG integrity (${image_mb} MiB logical size)"
    codesign --sign "$IDENTITY" --timestamp "$dmg" || fail "signing the DMG"
    out=$(codesign --verify --strict --verbose=2 "$dmg" 2>&1) || { echo "$out"; fail "DMG signature"; }
    echo "$out" | sed 's/^/   /'
    out=$(codesign -dvv "$dmg" 2>&1)
    grep -E '^(Authority=Developer|TeamIdentifier|Timestamp)' <<<"$out" | sed 's/^/   dmg: /' || true
    grep -q '^Timestamp=' <<<"$out" || fail "DMG has no secure timestamp"
    hdiutil verify "$dmg" >"$OUT/logs/hdiutil-verify.log" 2>&1 || { cat "$OUT/logs/hdiutil-verify.log"; fail "hdiutil verify"; }
    # DiskArbitration can deny a mount point beneath an external output volume. Use an internal temporary
    # directory, independent of where the checked image and archive are stored.
    mnt=$(mktemp -d /private/tmp/clepso-dmg-mount.XXXXXX)
    hdiutil attach "$dmg" -readonly -nobrowse -noautoopen -mountpoint "$mnt" >"$OUT/logs/hdiutil-attach.log" 2>&1 \
        || { cat "$OUT/logs/hdiutil-attach.log"; rmdir "$mnt" 2>/dev/null || true; fail "mounting the DMG"; }
    local status=0 listing
    listing=$(ls "$mnt" | tr '\n' ' ')
    [ "$listing" = "Applications Clepso.app " ] || { echo "   DMG holds: $listing"; status=1; }
    [ "$(readlink "$mnt/Applications")" = /Applications ] || status=1
    codesign --verify --deep --strict "$mnt/Clepso.app" || status=1
    [ "$(codesign -dvvv "$mnt/Clepso.app" 2>&1 | grep '^CDHash=')" = "$(codesign -dvvv "$app" 2>&1 | grep '^CDHash=')" ] || status=1
    hdiutil detach "$mnt" -quiet || hdiutil detach "$mnt" -force -quiet || true
    rmdir "$mnt" 2>/dev/null || true
    [ $status -eq 0 ] || fail "DMG contents differ from the checked app"
    ok "DMG $(basename "$dmg"): signed, verified, mounts with Clepso.app (same CDHash) and the Applications link"
}

# notarize <file> <json>: submits and waits; anything but Accepted prints Apple's log and fails.
notarize() {
    local file="$1" json="$2" status id
    xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m --output-format json >"$json" \
        || { cat "$json"; fail "notarytool submit $(basename "$file")"; }
    status=$(plutil -extract status raw "$json"); id=$(plutil -extract id raw "$json")
    echo "   notary submission $id: $status"
    if [ "$status" != Accepted ]; then
        xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" "$OUT/logs/notary-$id.json" || true
        cat "$OUT/logs/notary-$id.json" 2>/dev/null || true
        fail "notarisation of $(basename "$file") was $status, not Accepted"
    fi
}

# ---------------------------------------------------------------------------------------------------------------------
step "Verify the exported app"
verify_app "$APP" pre

step "Signed DMG (before notarisation)"
PRE_DMG="$OUT/$NAME-UNNOTARIZED.dmg"
make_dmg "$APP" "$PRE_DMG"
echo "   $(du -h "$PRE_DMG" | cut -f1)  $(shasum -a 256 "$PRE_DMG")"

cat >"$OUT/publish-commands.txt" <<EOF
# Prepared by scripts/release.sh; nothing here has been run. Publishing is public: the founder decides.
# Only after the notarised DMG and SHA256SUMS exist in this folder, from a clean checkout of $COMMIT.
git tag -a $TAG $COMMIT -m "Clepso $VERSION ${TAG#v$VERSION-}"
git push origin $TAG
gh release create $TAG --repo obileonardo/clepso --verify-tag --prerelease --draft \\
  --title "Clepso $VERSION ${TAG#v$VERSION-}" --notes-file docs/release-notes/$TAG.md \\
  "$OUT/$NAME.dmg" "$OUT/SHA256SUMS"
EOF

if [ "$NOTARY_READY" != 1 ]; then
    cat <<EOF

== STOPPED BEFORE NOTARISATION
Everything up to notarisation is built and verified in $OUT
($(basename "$PRE_DMG") is signed but NOT notarised: never publish it).

The keychain profile '$NOTARY_PROFILE' is missing. Set it up once (it asks for an app-specific password made at
https://account.apple.com › Sign-In and Security › App-Specific Passwords, and keeps it in the login keychain):

    xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <your Apple ID email> --team-id $TEAM

Check it with:  xcrun notarytool history --keychain-profile $NOTARY_PROFILE
Then run this script again: scripts/release.sh $TAG$([ "$WITH_ACCOUNTS" = 1 ] && echo " --with-accounts")
EOF
    exit 3
fi

# ---------------------------------------------------------------------------------------------------------------------
step "Notarise the app, staple"
rm -f "$PRE_DMG"
ditto -c -k --keepParent "$APP" "$OUT/Clepso.zip"
notarize "$OUT/Clepso.zip" "$OUT/notary-app.json"
rm -f "$OUT/Clepso.zip"
xcrun stapler staple "$APP" >/dev/null || fail "stapling the app"
verify_app "$APP" post

step "Final DMG from the stapled app; notarise, staple"
DMG="$OUT/$NAME.dmg"
make_dmg "$APP" "$DMG"
notarize "$DMG" "$OUT/notary-dmg.json"
xcrun stapler staple "$DMG" >/dev/null || fail "stapling the DMG"
xcrun stapler validate "$DMG" || fail "stapler validate (DMG)"
out=$(spctl --assess --type open --context context:primary-signature -vv "$DMG" 2>&1 || true)
echo "$out" | sed 's/^/   spctl: /'
grep -q 'accepted' <<<"$out" && grep -q 'source=Notarized Developer ID' <<<"$out" || fail "Gatekeeper does not accept the DMG"
ok "DMG: notarised, stapled, accepted by Gatekeeper"

step "Checksums"
(cd "$OUT" && shasum -a 256 "$NAME.dmg" > SHA256SUMS && shasum -a 256 -c SHA256SUMS)
cat "$OUT/SHA256SUMS"
echo
echo "RELEASE READY: $DMG ($(du -h "$DMG" | cut -f1)). Publishing commands (not run): $OUT/publish-commands.txt"
