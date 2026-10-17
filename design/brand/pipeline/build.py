"""Builds every Pulse brand asset from source. Usage (from the repo root):

    design/brand/pipeline/build.sh            # creates the pinned venv if needed, then runs this

Outputs (all under design/brand/): fonts/, logo/, app-icon/, menubar/, favicon/, sheets/, specimens/.
Deterministic: running it twice produces the same files (PNG metadata aside).
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BRAND = HERE.parent
sys.path.insert(0, str(HERE))

import build_mono_font  # noqa: E402
import build_pixel_font  # noqa: E402
import logo  # noqa: E402


def step(msg):
    print(f"• {msg}", flush=True)


def main(only=None):
    want = set(only or ["fonts", "logo", "sheets", "specimens"])
    fonts = BRAND / "fonts"
    if "fonts" in want:
        step("Pulse Pixel")
        build_pixel_font.build(fonts)
        step("Pulse Mono (Regular, Medium, Bold)")
        for style, (w, wv, wh) in build_mono_font.WEIGHTS.items():
            build_mono_font.build_weight(style, w, wv, wh, fonts)
    if "logo" in want:
        step("logo masters and rasters")
        logo.write_logo(BRAND / "logo")
        step("menu bar template images")
        logo.write_menubar(BRAND / "menubar")
        step("app icon")
        logo.write_app_icon(BRAND / "app-icon")
        icns = BRAND / "app-icon" / "Pulse.icns"
        if subprocess.run(["iconutil", "-c", "icns", str(BRAND / "app-icon" / "Pulse.iconset"), "-o", str(icns)]).returncode:
            print("  iconutil not available: Pulse.icns not built")
        step("favicon")
        logo.write_favicon(BRAND / "favicon")
    if "sheets" in want:
        import sheets
        step("sheets")
        sheets.build_all(BRAND)
    if "logo" in want or "sheets" in want:
        import export
        step("brand.json (for the design-system page)")
        export.build()
    if "specimens" in want:
        import specimens
        step("type specimens (CoreText)")
        specimens.build_all(BRAND)


if __name__ == "__main__":
    main(sys.argv[1:])
