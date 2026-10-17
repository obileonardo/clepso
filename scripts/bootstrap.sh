#!/bin/sh
# Pinned developer tools (RELEASE_AND_CI §1): exact release, SHA-256 checked, installed under .tools/.
# No Homebrew or Mint, so every machine generates the project with the same XcodeGen.
set -eu

XCODEGEN_VERSION=2.46.0
XCODEGEN_SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806   # GitHub release digest, 2026-07-16

root=$(cd "$(dirname "$0")/.." && pwd)
tools="$root/.tools"
bin="$tools/xcodegen/bin/xcodegen"

if [ -x "$bin" ] && [ "$("$bin" --version 2>/dev/null)" = "Version: $XCODEGEN_VERSION" ]; then
    echo "xcodegen $XCODEGEN_VERSION already installed"
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/xcodegen.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
actual=$(shasum -a 256 "$work/xcodegen.zip" | cut -d' ' -f1)
if [ "$actual" != "$XCODEGEN_SHA256" ]; then
    echo "xcodegen.zip SHA-256 mismatch: expected $XCODEGEN_SHA256, got $actual" >&2
    exit 1
fi
unzip -q "$work/xcodegen.zip" -d "$work/unpacked"
rm -rf "$tools/xcodegen"
mkdir -p "$tools"
mv "$work/unpacked/xcodegen" "$tools/xcodegen"
"$bin" --version
