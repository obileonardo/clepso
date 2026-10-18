#!/bin/sh
# Rebuilds every Clepso brand asset: fonts, logo, app icon, menu bar icon, favicon, sheets and specimens,
# then validates the fonts (scripted checks + the OpenType Sanitizer that browsers use).
# Usage, from anywhere:  design/brand/pipeline/build.sh [fonts|logo|sheets|specimens ...]
# The virtualenv lives in $PULSE_BRAND_VENV (default: design/brand/.venv, git-ignored), pinned by requirements.txt.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
VENV=${PULSE_BRAND_VENV:-"$HERE/../.venv"}
PY=${PULSE_BRAND_PYTHON:-python3.12}
if [ ! -x "$VENV/bin/python" ]; then
  "$PY" -m venv "$VENV"
  "$VENV/bin/pip" install --quiet -r "$HERE/requirements.txt"
fi
# cairosvg needs libcairo (Homebrew: brew install cairo); render.swift needs the Xcode command line tools.
export DYLD_FALLBACK_LIBRARY_PATH="${DYLD_FALLBACK_LIBRARY_PATH:-/opt/homebrew/lib:/usr/local/lib}"
"$VENV/bin/python" "$HERE/build.py" "$@"
"$VENV/bin/python" "$HERE/check_fonts.py"
for f in "$HERE"/../fonts/*.ttf "$HERE"/../fonts/*.otf "$HERE"/../fonts/*.woff2; do
  "$VENV/bin/python" -m ots "$f" >/dev/null || { echo "OTS rejected $f"; exit 1; }
done
echo "OTS: all fonts sanitised"
