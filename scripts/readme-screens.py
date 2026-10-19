#!/usr/bin/env python3
"""Lay out the README's screenshot grid and the repository's social preview from design/screens.

    python3 scripts/readme-screens.py

GitHub shows images side by side only as well as their sizes match, so every image in one grid row here has the same
pixel dimensions:

- The Dashboard window shots the README shows are used as they are; this script only checks that each is 3000 x 2532.
- docs/readme/panel-*.png: the menu bar panel shots (1160 wide, 940 to 1254 tall) centred, unscaled and uncropped, on
  one 1320 x 1416 card in the site's Phosphor surface colour, so panels of different heights line up.
- docs/readme/social-preview.png: 1280 x 640, for the repository's social preview (Settings > General).

Nothing is stretched or cropped: panels keep every pixel, and only the social preview's panel is resized (halved).
Needs Pillow. Run it again after the screenshots in design/screens are refreshed.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SCREENS = ROOT / "design/screens"
OUT = ROOT / "docs/readme"
FONTS = ROOT / "design/brand/fonts"

SURFACE = (13, 20, 16, 255)        # --p-surface #0D1410 (site/assets/site.css)
LINE = (44, 64, 52, 255)           # --p-line #2C4034
INK = (6, 9, 7, 255)               # Ink #060907
TEXT = (234, 247, 238, 255)        # Phosphor dark textPrimary #EAF7EE
MUTED = (147, 185, 160, 255)       # Phosphor dark label colour, as in scripts/readme-menubar-strip.py

DASHBOARD = ["details-home", "details-home-light", "details-limits", "details-session",
             "details-stats-arena", "details-stats-arena-light"]
PANELS = ["popover-detail", "popover-inspector"]                # the overview is the README hero, at full size
PANEL_CANVAS = (1320, 1416)        # the tallest panel (1254) plus 81 px above and below; 80 px either side
CARD_RADIUS = 36


def save(image: Image.Image, name: str) -> None:
    path = OUT / f"{name}.png"
    image.save(path, optimize=True)
    print(f"{path.relative_to(ROOT)}  {image.width} x {image.height}  {path.stat().st_size // 1024} KB")


def check_dashboard() -> None:
    for name in DASHBOARD:
        size = Image.open(SCREENS / f"{name}.png").size
        assert size == (3000, 2532), f"{name}: {size}; every Dashboard shot in the README grid must be 3000 x 2532"


def card(size, radius=CARD_RADIUS) -> Image.Image:
    tile = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=SURFACE,
                                           outline=LINE, width=2)
    return tile


def panel_tiles() -> None:
    for name in PANELS:
        src = Image.open(SCREENS / f"{name}.png").convert("RGBA")
        assert src.width <= PANEL_CANVAS[0] and src.height <= PANEL_CANVAS[1] - 2 * CARD_RADIUS, f"{name}: {src.size}"
        tile = card(PANEL_CANVAS)
        tile.alpha_composite(src, ((PANEL_CANVAS[0] - src.width) // 2, (PANEL_CANVAS[1] - src.height) // 2))
        save(tile, name.replace("popover-", "panel-"))


def social_preview() -> None:
    w, h = 1280, 640
    img = Image.new("RGBA", (w, h), INK)
    logo = Image.open(ROOT / "design/brand/logo/png/clepso-horizontal-phosphor-488.png").convert("RGBA")
    img.alpha_composite(logo, (80, 176))
    draw = ImageDraw.Draw(img)
    bold = ImageFont.truetype(str(FONTS / "ClepsoMono-Bold.ttf"), 34)
    regular = ImageFont.truetype(str(FONTS / "ClepsoMono-Regular.ttf"), 22)
    draw.text((80, 344), "Your coding-agent limits,", font=bold, fill=TEXT)
    draw.text((80, 388), "before you hit them.", font=bold, fill=TEXT)
    draw.text((80, 452), "Claude Code and Codex usage limits", font=regular, fill=MUTED)
    draw.text((80, 482), "in the macOS menu bar. Local-first.", font=regular, fill=MUTED)
    panel = Image.open(SCREENS / "popover-overview.png").convert("RGBA")
    panel = panel.resize((panel.width // 2, panel.height // 2), Image.LANCZOS)    # 580 x 470
    img.alpha_composite(panel, (w - panel.width - 64, (h - panel.height) // 2))
    save(img.convert("RGB"), "social-preview")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    check_dashboard()
    panel_tiles()
    social_preview()


if __name__ == "__main__":
    main()
