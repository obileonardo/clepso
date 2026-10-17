#!/bin/bash
# Local quality gate (docs/ROADMAP.md increment 0.5; lanes A and B of docs/RELEASE_AND_CI.md).
# Every check runs even if an earlier one fails; the summary lists each result and the exit status is
# non-zero if any failed. Usage: scripts/ci.sh   (or: make ci)
set -uo pipefail
cd "$(dirname "$0")/.."

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
    [[ "$xcode" == "$EXPECTED_XCODE"* ]] || { echo "expected $EXPECTED_XCODE"; return 1; }
    [[ "$swift" == *"$EXPECTED_SWIFT"* ]] || { echo "expected $EXPECTED_SWIFT"; return 1; }
}

strict_build() { swift build --build-tests -Xswiftc -warnings-as-errors; }

all_tests() { swift test; }            # non-zero exit on any failing test

# The helper Claude Code runs must not be able to reach the network (ADR-002, shim spec §7).
helper_linkage() {
    swift build -c release --product pulse-statusline || return 1
    local bin=".build/release/pulse-statusline"
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

# Source rules from TEST_PLAN.md §1 and RELEASE_AND_CI.md lane B.
no_networking_code() {
    local hits
    # ROADMAP 2.0 (DECISIONS C9): Pulse accounts make HTTPS calls from the Sync module, and only from there.
    hits=$(grep -rnE 'URLSession|NWConnection|NWListener|CFSocketCreate|import Network\b' Sources | grep -v '^Sources/Sync/' || true)
    [ -z "$hits" ] || { echo "$hits"; return 1; }
    hits=$(grep -rln 'import Sync' Sources | grep -vE '^Sources/(PulseApp|Sync)/' || true)
    [ -z "$hits" ] || { echo "Sync imported outside the app: $hits"; return 1; }
    echo "networking APIs only in Sources/Sync/, used only by the app"
}

no_direct_clock() {
    local hits
    hits=$(grep -rn 'Date()' Sources/Domain Sources/ClaudeCodeAdapter Sources/ShimProtocol Sources/UsageEngine Sources/Storage Sources/PulseApp 2>/dev/null \
        | grep -v 'clock-ok' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true)   # comments may mention it
    [ -z "$hits" ] || { echo "inject the clock instead:"; echo "$hits"; return 1; }
    echo "no direct clock reads outside SystemClock"
}

# DESIGN_SYSTEM.md §7: components and app screens take colour, spacing and type from Theme only, so a restyle can't bypass it.
design_tokens_only() {
    local hits
    hits=$(grep -rnE 'Color\((red|\.sRGB|white|hue)|Color\.(red|blue|green|orange|yellow|gray|primary|secondary|black|white)|\.padding\([[:space:]]*[0-9]|Font\.system\(size:|Date\(\)' \
        Sources/DesignSystem/Components Sources/DesignSystem/Pixel Sources/PulseApp 2>/dev/null || true)
    [ -z "$hits" ] || { echo "$hits"; return 1; }
    # 1.13: icons are pixel glyphs (PixelIcon), never the system's smooth symbols.
    hits=$(grep -rnE 'Image\(systemName|systemImage:' Sources/DesignSystem Sources/PulseApp 2>/dev/null || true)
    [ -z "$hits" ] || { echo "use PixelIcon / PixelLabel:"; echo "$hits"; return 1; }
    echo "components use Theme tokens and pixel icons only"
}

# PRIVACY_AND_SECURITY §5: `unsafeReveal` only in Storage and the helper's passthrough; `Redacted` is never Codable.
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
    hits=$(grep -rnIE 'sk-ant-[A-Za-z0-9_-]{3,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----|xox[abp]-[A-Za-z0-9-]{10,}' \
        --exclude-dir=.build --exclude-dir=.git --exclude-dir=.swiftpm . | grep -v 'secret-scan: allow' || true)
    [ -z "$hits" ] || { echo "$hits"; return 1; }
    echo "no secret-shaped strings"
}

# RELEASE_AND_CI lanes C/D, local form: the signed bundle builds, embeds the helper under its identifier,
# carries no sandbox, network or exception entitlements, runs as a menu bar app, and links no networking.
app_bundle() {
    make app >/dev/null || return 1
    local app=build/DerivedData/Build/Products/Debug/Pulse.app
    codesign --verify --deep --strict "$app" || return 1
    local helper="$app/Contents/Helpers/pulse-statusline"
    [ -x "$helper" ] || { echo "helper missing"; return 1; }
    # Capture first, then match: `cmd | grep -q` under pipefail fails when grep closes the pipe early.
    local info
    info=$(codesign -dv "$helper" 2>&1)
    grep -q '^Identifier=dev.tokone.pulse.statusline$' <<<"$info" || { echo "helper identifier wrong"; return 1; }
    for bin in "$app" "$helper"; do
        info=$(codesign -dv "$bin" 2>&1)
        grep -q 'flags=.*runtime' <<<"$info" || { echo "no hardened runtime: $bin"; return 1; }
    done
    local keys
    keys=$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert json -o - - | python3 -c 'import json,sys; print(" ".join(sorted(json.load(sys.stdin))))')
    [ "$keys" = "com.apple.security.get-task-allow" ] || [ -z "$keys" ] || { echo "unexpected entitlements: $keys"; return 1; }
    [ "$(plutil -extract LSUIElement raw "$app/Contents/Info.plist")" = "true" ] || { echo "LSUIElement not set"; return 1; }
    # Since ROADMAP 2.0 the app itself uploads (Sync); the helper Claude Code runs must still never touch the network.
    local net
    net=$(nm -u "$helper" 2>/dev/null | grep -E 'URLSession|NSURLConnection|CFHTTP|CFNetwork|_nw_|getaddrinfo|CFStream' || true)
    [ -z "$net" ] || { echo "networking symbols in the helper:"; echo "$net"; return 1; }
    [ "$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw "$app/Contents/Info.plist")" = "dev.tokone.pulse" ] || { echo "sign-in URL scheme missing"; return 1; }
    echo "bundle signed; helper dev.tokone.pulse.statusline without networking; entitlements: ${keys:-none} (get-task-allow is debug-only); sign-in URL scheme"
}

echo "Tokone local CI · $(date -u +%Y-%m-%dT%H:%M:%SZ) · $(git rev-parse --short HEAD 2>/dev/null || echo 'no commits')"
run "toolchain pinned"              check_toolchain
run "strict build (warnings=errors)" strict_build
run "tests"                         all_tests
run "helper links no networking"    helper_linkage
run "networking only in Sync"       no_networking_code
run "clock injected"                no_direct_clock
run "design tokens only"             design_tokens_only
run "redaction audit"               redaction_audit
run "secret scan"                   secret_scan
run "app bundle"                    app_bundle

echo
echo "Summary"
printf '  %s\n' "${results[@]}"
if [ "$failed" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "CHECKS FAILED"; fi
exit "$failed"
