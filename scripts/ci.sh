#!/bin/bash
# Local quality gate. Every check runs even if an earlier one fails; the summary lists each result and the exit
# status is non-zero if any failed.
#
#   scripts/ci.sh                 (make ci)              strict: the maintainer's and official builds
#   scripts/ci.sh --contributor   (make ci-contributor)  for contributors and hosted CI without the maintainer's setup
#
# Strict mode pins the exact toolchain and requires the app to be signed with a real identity, with hardened runtime,
# and with an accounts project configured (Config/*.local.xcconfig). Contributor mode accepts any Swift 6 toolchain,
# an ad-hoc signature and no accounts project; every other check is identical.
set -uo pipefail
cd "$(dirname "$0")/.."

MODE=strict
for arg in "$@"; do
    case "$arg" in
        --contributor) MODE=contributor ;;
        *) echo "usage: scripts/ci.sh [--contributor]"; exit 2 ;;
    esac
done

EXPECTED_XCODE="Xcode 27.1"
EXPECTED_SWIFT="Swift version 6.4"
LOG_DIR=".build/ci-logs"
mkdir -p "$LOG_DIR"

results=()
failed=0

# run <name> <command...>: runs a check, keeps its output in $LOG_DIR, records PASS/FAIL with timing.
run() {
    local name="$1"; shift
    local log="$LOG_DIR/$(echo "$name" | tr ' /' '__').log"
    local start=$SECONDS
    printf '▶ %-34s' "$name"
    if "$@" >"$log" 2>&1; then
        results+=("PASS  $name ($((SECONDS - start))s)")
        printf 'PASS (%ss)\n' "$((SECONDS - start))"
    else
        results+=("FAIL  $name ($((SECONDS - start))s)  log: $log")
        printf 'FAIL (%ss)  log: %s\n' "$((SECONDS - start))" "$log"
        tail -15 "$log" | sed 's/^/      /'
        failed=1
    fi
}

# Output is captured before matching: `grep -q` exits early, which would break a pipe under pipefail.
check_toolchain() {
    local xcode swift
    xcode=$(xcodebuild -version) || return 1
    swift=$(swift --version 2>&1) || return 1
    echo "$xcode"; echo "$swift"
    if [ "$MODE" = contributor ]; then
        [[ "$swift" == *"Swift version 6."* ]] || { echo "a Swift 6 toolchain is required"; return 1; }
        echo "contributor mode: any Swift 6 toolchain (strict mode pins $EXPECTED_XCODE, $EXPECTED_SWIFT)"
        return 0
    fi
    [[ "$xcode" == "$EXPECTED_XCODE"* ]] || { echo "expected $EXPECTED_XCODE"; return 1; }
    [[ "$swift" == *"$EXPECTED_SWIFT"* ]] || { echo "expected $EXPECTED_SWIFT"; return 1; }
}

# -warnings-as-errors does not turn every diagnostic into an error (Swift 6 concurrency warnings got through), so the
# gate also fails on any "warning:" line the compiler prints.
strict_build() {
    local out; out=$(swift build --build-tests -Xswiftc -warnings-as-errors 2>&1); local status=$?
    printf '%s\n' "$out" | tail -5
    [ $status -eq 0 ] || return $status
    if printf '%s\n' "$out" | grep -q "warning:"; then
        printf '%s\n' "$out" | grep "warning:" | sort -u | head -20; echo "compiler warnings are errors"; return 1
    fi
}

all_tests() { swift test; }            # non-zero exit on any failing test

# The helper Claude Code runs must not be able to reach the network.
helper_linkage() {
    swift build -c release --product clepso-statusline || return 1
    local bin=".build/release/clepso-statusline"
    echo "linked libraries:"; otool -L "$bin" | tail -n +2
    local unexpected
    unexpected=$(otool -L "$bin" | tail -n +2 | awk '{print $1}' | grep -v -E \
        '^/System/Library/Frameworks/(Foundation|CryptoKit)\.framework/|^/usr/lib/(libobjc\.A|libSystem\.B)\.dylib$|^/usr/lib/swift/libswift[A-Za-z]+\.dylib$')
    [ -z "$unexpected" ] || { echo "unexpected libraries:"; echo "$unexpected"; return 1; }
    local net
    net=$(nm -u "$bin" | grep -E 'URLSession|NSURLConnection|CFHTTP|CFNetwork|_nw_|getaddrinfo|CFStream')
    [ -z "$net" ] || { echo "networking symbols:"; echo "$net"; return 1; }
    echo "no networking libraries or symbols"
}

# Release builds compile none of the debug-only code (`#if DEBUG`: probe flags, debug launch arguments, demo forcing,
# the helper's CLEPSO_SHIM_NOW_MS and CLEPSO_SHIM_RELAXED_BUDGET). The debug build must contain the names (else the list
# in scripts/debug-only-names.regex is stale); no release object may. scripts/release.sh checks the shipped binaries too.
release_has_no_debug_code() {
    local pattern; pattern=$(cat scripts/debug-only-names.regex) || return 1
    swift build -c release --target ClepsoApp || return 1
    swift build -c release --product clepso-statusline || return 1
    local debug_names
    debug_names=$(strings -a .build/debug/ClepsoApp.o .build/debug/clepso-statusline 2>/dev/null | grep -oE "$pattern" | sort -u || true)
    [ "$(wc -l <<<"$debug_names")" -ge 10 ] || { echo "debug build shows too few debug-only names, list stale? $debug_names"; return 1; }
    local file hits found=0
    for file in .build/release/*.o .build/release/clepso-statusline; do
        hits=$(strings -a "$file" | grep -oE "$pattern" | sort -u || true)
        [ -z "$hits" ] || { echo "$file: $hits"; found=1; }
    done
    [ $found -eq 0 ] || { echo "debug-only names in a release build"; return 1; }
    echo "$(wc -l <<<"$debug_names" | tr -d ' ') debug-only names in the debug build, none in the release build"
}

# Optional Clepso accounts make HTTPS calls from the Sync module, and only from there.
no_networking_code() {
    local hits
    hits=$(grep -rnE 'URLSession|NWConnection|NWListener|CFSocketCreate|import Network\b' Sources | grep -v '^Sources/Sync/' || true)
    [ -z "$hits" ] || { echo "$hits"; return 1; }
    hits=$(grep -rln 'import Sync' Sources | grep -vE '^Sources/(ClepsoApp|Sync)/' || true)
    [ -z "$hits" ] || { echo "Sync imported outside the app: $hits"; return 1; }
    echo "networking APIs only in Sources/Sync/, used only by the app"
}

no_direct_clock() {
    local hits
    hits=$(grep -rn 'Date()' Sources/Domain Sources/ClaudeCodeAdapter Sources/ShimProtocol Sources/UsageEngine Sources/Storage Sources/ClepsoApp 2>/dev/null \
        | grep -v 'clock-ok' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true)   # comments may mention it
    [ -z "$hits" ] || { echo "inject the clock instead:"; echo "$hits"; return 1; }
    echo "no direct clock reads outside SystemClock"
}

# Components and app screens take colour, spacing and type from Theme only, so a restyle can't bypass it.
design_tokens_only() {
    local hits
    hits=$(grep -rnE 'Color\((red|\.sRGB|white|hue)|Color\.(red|blue|green|orange|yellow|gray|primary|secondary|black|white)|\.padding\([[:space:]]*[0-9]|Font\.system\(size:|Date\(\)' \
        Sources/DesignSystem/Components Sources/DesignSystem/Pixel Sources/ClepsoApp 2>/dev/null || true)
    [ -z "$hits" ] || { echo "$hits"; return 1; }
    # Icons are pixel glyphs (PixelIcon), never the system's smooth symbols.
    hits=$(grep -rnE 'Image\(systemName|systemImage:' Sources/DesignSystem Sources/ClepsoApp 2>/dev/null || true)
    [ -z "$hits" ] || { echo "use PixelIcon / PixelLabel:"; echo "$hits"; return 1; }
    echo "components use Theme tokens and pixel icons only"
}

# Item 9: every animation goes through a motion token (`Theme.motion`), which honours Reduce Motion, and views read
# Reduce Motion from `\.reduceMotion` (set once per window by `ReduceMotionRoot`). Animation curves live only in
# Tokens.swift; an explicit `.animation(nil…)` is allowed (it turns animation off).
motion_tokens_only() {
    local scope=(Sources/DesignSystem Sources/ClepsoApp) hits
    hits=$(grep -rnE 'withAnimation[[:space:]]*\(|\.animation[[:space:]]*\(|Transaction\(animation:|\.animation[[:space:]]*=' "${scope[@]}" \
        | grep -v '^Sources/DesignSystem/Theme/Tokens.swift:' | grep -v 'motion(' | grep -vE '\.animation\(nil|TimelineView\(' \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true)
    [ -z "$hits" ] || { echo "animate through theme.motion(<MotionToken>, reduceMotion:):"; echo "$hits"; return 1; }
    # Frame-by-frame motion (a TimelineView) pauses under Reduce Motion: its schedule names reduceMotion.
    hits=$(grep -rn 'TimelineView(' "${scope[@]}" | grep -v 'reduceMotion' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true)
    [ -z "$hits" ] || { echo "pause TimelineView under Reduce Motion (.animation(minimumInterval:paused: reduceMotion)):"; echo "$hits"; return 1; }
    hits=$(grep -rnE '\.(spring|interpolatingSpring|interactiveSpring|easeInOut|easeIn|easeOut|linear|bouncy|snappy|smooth)\(|\.repeatForever|\.(bouncy|snappy|smooth|spring|easeInOut|easeIn|easeOut|linear)[,)]' \
        "${scope[@]}" | grep -v '^Sources/DesignSystem/Theme/Tokens.swift:' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true)
    [ -z "$hits" ] || { echo "animation curves belong in MotionToken (Tokens.swift):"; echo "$hits"; return 1; }
    hits=$(grep -rn 'accessibilityReduceMotion' "${scope[@]}" | grep -v '^Sources/DesignSystem/Theme/Tokens.swift:' || true)
    [ -z "$hits" ] || { echo "read \\.reduceMotion (set by ReduceMotionRoot), not the system value:"; echo "$hits"; return 1; }
    echo "animations: $(grep -rnE 'withAnimation[[:space:]]*\(|\.animation[[:space:]]*\(' "${scope[@]}" | grep -v 'TimelineView(' | grep -vc '^Sources/DesignSystem/Theme/Tokens.swift:' || true) call sites, all through motion tokens"
}

# Item 9: everything works from the keyboard with a visible focus indicator. Self-drawn buttons use
# PixelPlainButtonStyle (pixel focus ring), never `.plain`; a view that turns the system focus effect off draws the
# pixel ring itself; a tap gesture sits on a view that also takes focus and answers keys; and information shown on hover
# is also reachable by keyboard (`chartKeyboard`) unless the hover is decorative (marked `hover-ok`).
keyboard_reachable() {
    local scope=(Sources/DesignSystem Sources/ClepsoApp) hits file
    hits=$(grep -rn 'buttonStyle(\.plain)\|buttonStyle(PlainButtonStyle())' "${scope[@]}" || true)
    [ -z "$hits" ] || { echo "use PixelPlainButtonStyle (it draws the focus ring):"; echo "$hits"; return 1; }
    for file in $(grep -rl 'focusEffectDisabled' "${scope[@]}"); do
        grep -qE 'pixelFocusRing|focusRing' "$file" || { echo "$file turns the focus effect off without drawing a ring"; return 1; }
    done
    for file in $(grep -rl '\.onTapGesture' "${scope[@]}"); do
        grep -q '\.focusable(' "$file" && grep -qE 'onKeyPress|onMoveCommand' "$file" \
            || { echo "$file: a tap gesture with no keyboard path (make it a Button, or focusable with key handling)"; return 1; }
    done
    hits=$(grep -rnE '\.onContinuousHover|\.onHover' "${scope[@]}" | grep -v 'hover-ok' | while IFS=: read -r f rest; do
        grep -q 'chartKeyboard(' "$f" || echo "$f:$rest"; done)
    [ -z "$hits" ] || { echo "hover shows something the keyboard can't reach (chartKeyboard, or mark decorative hover-ok):"; echo "$hits"; return 1; }
    echo "no .plain buttons; focus effect replaced by the pixel ring where off; taps and hover readouts reachable by keyboard"
}

# Logging and redaction (PRIVACY_AND_SECURITY §5): `unsafeReveal` only in Storage and the helper's passthrough;
# `Redacted` is never Codable.
redaction_audit() {
    local hits
    hits=$(grep -rn 'unsafeReveal(' Sources | grep -v '^Sources/Domain/Redacted.swift' \
        | grep -vE '^Sources/(Storage|StatusLineShim)/' || true)
    [ -z "$hits" ] || { echo "unsafeReveal outside Storage/StatusLineShim:"; echo "$hits"; return 1; }
    hits=$(grep -rnE 'extension Redacted[^{]*(Codable|Encodable|Decodable)|struct Redacted[^{]*(Codable|Encodable|Decodable)' Sources || true)
    [ -z "$hits" ] || { echo "Redacted must not be Codable:"; echo "$hits"; return 1; }
    echo "unsafeReveal call sites: $(grep -rn 'unsafeReveal(' Sources | grep -vc '^Sources/Domain/Redacted.swift' || true); Redacted not Codable"
}

secret_scan() {
    local hits
    hits=$(grep -rnIE 'sk-ant-[A-Za-z0-9_-]{3,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----|xox[abp]-[A-Za-z0-9-]{10,}|sb_secret_[A-Za-z0-9_-]{8,}' \
        --exclude-dir=.build --exclude-dir=.git --exclude-dir=.swiftpm . | grep -v 'secret-scan: allow' || true)
    [ -z "$hits" ] || { echo "$hits"; return 1; }
    echo "no secret-shaped strings"
}

# Builds from source must never reach the maintainer's accounts project: no Supabase project or publishable key may be
# committed. Official builds get them from the uncommitted Config/Sync.local.xcconfig. (Tests use example.supabase.co.)
no_committed_sync_project() {
    local hits
    hits=$(git ls-files -z | xargs -0 grep -nIE '[a-z0-9]{20}\.supabase\.co|sb_publishable_[A-Za-z0-9_-]{20,}' 2>/dev/null || true)
    [ -z "$hits" ] || { echo "accounts project committed:"; echo "$hits" | cut -d: -f1,2; return 1; }
    hits=$(git ls-files 'Config/*.local.xcconfig')
    [ -z "$hits" ] || { echo "local configuration committed: $hits"; return 1; }
    echo "no accounts project in tracked files; Config/*.local.xcconfig untracked"
}

# Account emails (backend/supabase/templates) are generated: up to date, wired into config.toml, well-formed, no
# comments (Supabase strips them), no scripts or web fonts, and under Gmail's clipping size. The logo they link is in
# site/ and matches the brand pipeline's output.
email_templates() {
    python3 -I scripts/build-email.py --check || return 1
    cmp design/brand/logo/png/clepso-logo-email-244.png site/assets/email/clepso-logo-email-244.png || return 1
    echo "email templates current; logo deployed with the site"
}

# The app bundle builds, is signed, embeds the helper under its identifier, carries no sandbox, network or exception
# entitlements, runs as a menu bar app, ships third-party licences, and its helper links no networking.
# Strict mode also requires a real signing identity, hardened runtime and a configured accounts project.
app_bundle() {
    make app >/dev/null || return 1
    local app=build/DerivedData/Build/Products/Debug/Clepso.app
    codesign --verify --deep --strict "$app" || return 1
    local helper="$app/Contents/Helpers/clepso-statusline"
    [ -x "$helper" ] || { echo "helper missing"; return 1; }
    local helpers; helpers=$(ls "$app/Contents/Helpers")
    [ "$helpers" = "clepso-statusline" ] || { echo "unexpected files in Contents/Helpers: $helpers"; return 1; }
    # Capture first, then match: `cmd | grep -q` under pipefail fails when grep closes the pipe early.
    local info
    info=$(codesign -dv "$helper" 2>&1)
    grep -q '^Identifier=com.elvisobi.clepso.statusline$' <<<"$info" || { echo "helper identifier wrong"; return 1; }
    for bin in "$app" "$helper"; do
        info=$(codesign -dv "$bin" 2>&1)
        if grep -q 'Signature=adhoc' <<<"$info"; then
            # Xcode does not apply hardened runtime to ad-hoc signatures; only contributor builds may be ad hoc.
            [ "$MODE" = contributor ] || { echo "ad-hoc signature in strict mode (add Config/Signing.local.xcconfig): $bin"; return 1; }
        else
            grep -q 'flags=.*runtime' <<<"$info" || { echo "no hardened runtime: $bin"; return 1; }
        fi
    done
    local keys
    keys=$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert json -o - - | python3 -c 'import json,sys; print(" ".join(sorted(json.load(sys.stdin))))')
    [ "$keys" = "com.apple.security.get-task-allow" ] || [ -z "$keys" ] || { echo "unexpected entitlements: $keys"; return 1; }
    [ "$(plutil -extract LSUIElement raw "$app/Contents/Info.plist")" = "true" ] || { echo "LSUIElement not set"; return 1; }
    # The app may upload (optional Sync); the helper Claude Code runs must never touch the network.
    local net
    net=$(nm -u "$helper" 2>/dev/null | grep -E 'URLSession|NSURLConnection|CFHTTP|CFNetwork|_nw_|getaddrinfo|CFStream' || true)
    [ -z "$net" ] || { echo "networking symbols in the helper:"; echo "$net"; return 1; }
    [ "$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw "$app/Contents/Info.plist")" = "clepso" ] || { echo "sign-in URL scheme missing"; return 1; }
    local ack="$app/Contents/Resources/Acknowledgements.txt"
    grep -q 'Gwendal Rou' "$ack" 2>/dev/null && grep -q 'Permission is hereby granted' "$ack" || { echo "third-party licences missing: $ack"; return 1; }
    for font in ClepsoFonts; do
        [ -f "$app/Contents/Resources/Clepso_DesignSystem.bundle/Contents/Resources/Fonts/$font-OFL.txt" ] || { echo "$font licence missing"; return 1; }
    done
    local sync
    sync=$(plutil -extract ClepsoSyncHost raw "$app/Contents/Info.plist" 2>/dev/null || true)
    if [ "$MODE" = strict ]; then
        [ -n "$sync" ] || { echo "no accounts project in strict mode (add Config/Sync.local.xcconfig)"; return 1; }
    fi
    echo "bundle signed ($MODE); helper com.elvisobi.clepso.statusline without networking; entitlements: ${keys:-none} (get-task-allow is debug-only);" \
         "sign-in URL scheme; licences shipped; accounts project: $([ -n "$sync" ] && echo configured || echo none, Sync off)"
}

echo "Clepso local CI ($MODE) · $(date -u +%Y-%m-%dT%H:%M:%SZ) · $(git rev-parse --short HEAD 2>/dev/null || echo 'no commits')"
run "toolchain pinned"              check_toolchain
run "strict build (warnings=errors)" strict_build
run "tests"                         all_tests
run "helper links no networking"    helper_linkage
run "release build has no debug code" release_has_no_debug_code
run "networking only in Sync"       no_networking_code
run "clock injected"                no_direct_clock
run "design tokens only"             design_tokens_only
run "motion through tokens"         motion_tokens_only
run "keyboard reachable"            keyboard_reachable
run "redaction audit"               redaction_audit
run "secret scan"                   secret_scan
run "no committed accounts project" no_committed_sync_project
run "email templates"               email_templates
run "app bundle"                    app_bundle

echo
echo "Summary"
printf '  %s\n' "${results[@]}"
if [ "$failed" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "CHECKS FAILED"; fi
exit "$failed"
