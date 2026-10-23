#!/bin/sh
# Rebuilds every Clepso brand asset: fonts, logo, app icon, menu bar icon, favicon, sheets and specimens,
# then validates the fonts (scripted checks + the OpenType Sanitizer that browsers use).
# Usage, from anywhere:  design/brand/pipeline/build.sh [fonts|logo|menubar|sheets|specimens ...]
# The virtualenv lives in $CLEPSO_BRAND_VENV (default: design/brand/.venv, git-ignored), pinned by requirements.txt.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
VENV=${CLEPSO_BRAND_VENV:-"$HERE/../.venv"}
PY=${CLEPSO_BRAND_PYTHON:-python3.12}
if [ ! -x "$VENV/bin/python" ]; then
  "$PY" -m venv "$VENV"
fi
# Reconcile existing environments too: changing the security pin must not silently keep an older installed wheel.
REQUIREMENTS_HASH=$(shasum -a 256 "$HERE/requirements.txt" | awk '{print $1}')
STAMP="$VENV/.clepso-requirements.sha256"
INSTALLED_HASH=$(cat "$STAMP" 2>/dev/null || true)
if [ "$INSTALLED_HASH" != "$REQUIREMENTS_HASH" ]; then
  echo "Synchronising pinned brand dependencies"
  "$VENV/bin/python" -m pip install --quiet -r "$HERE/requirements.txt"
  "$VENV/bin/python" -m pip check
  printf '%s\n' "$REQUIREMENTS_HASH" > "$STAMP.next"
  mv "$STAMP.next" "$STAMP"
fi
# cairosvg needs libcairo (Homebrew: brew install cairo); render.swift needs the Xcode command line tools.
export DYLD_FALLBACK_LIBRARY_PATH="${DYLD_FALLBACK_LIBRARY_PATH:-/opt/homebrew/lib:/usr/local/lib}"
"$VENV/bin/python" "$HERE/build.py" "$@"
"$VENV/bin/python" "$HERE/check_fonts.py"
for f in "$HERE"/../fonts/*.ttf "$HERE"/../fonts/*.otf "$HERE"/../fonts/*.woff2; do
  "$VENV/bin/python" -m ots "$f" >/dev/null || { echo "OTS rejected $f"; exit 1; }
done
echo "OTS: all fonts sanitised"
