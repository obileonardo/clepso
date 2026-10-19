#!/usr/bin/env python3
"""Draw the README's menu bar state strip from the brand kit's template PNGs.

    python3 scripts/readme-menubar-strip.py

Reads the seven design/brand/menubar/state-*@2x.png states (black pixels on transparency, generated with the app's
glyphs) and writes docs/readme/menubar-states-{light,dark}.png: the same pixels, scaled by whole numbers with no
smoothing, labelled in Clepso Mono, on a transparent ground. Needs Pillow. Run it again after the menu bar family
changes in design/brand/pipeline/logo.py.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "design/brand/menubar"
OUT = ROOT / "docs/readme"
FONT = ROOT / "design/brand/fonts/ClepsoMono-Regular.ttf"

STATES = ["beat", "approaching", "flatline", "stale", "demo", "waiting", "not-connected"]
SCALE = 3                 # 32 px @2x source -> 96 px, every source pixel a 3 x 3 block
CELL_W, PAD_TOP, GAP, LABEL_H = 240, 8, 22, 36
INKS = {"light": (6, 9, 7, 255), "dark": (234, 247, 238, 255)}       # Ink and Phosphor-dark textPrimary
LABEL = {"light": (82, 99, 88, 255), "dark": (147, 185, 160, 255)}


def tinted(path: Path, ink) -> Image.Image:
    src = Image.open(path).convert("RGBA")
    alpha = src.getchannel("A")
    out = Image.new("RGBA", src.size, ink)
    out.putalpha(alpha)
    return out.resize((src.width * SCALE, src.height * SCALE), Image.NEAREST)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype(str(FONT), 26)
    for mode, ink in INKS.items():
        icon_h = 32 * SCALE
        strip = Image.new("RGBA", (CELL_W * len(STATES), PAD_TOP + icon_h + GAP + LABEL_H), (0, 0, 0, 0))
        draw = ImageDraw.Draw(strip)
        for i, name in enumerate(STATES):
            icon = tinted(SRC / f"state-{name}@2x.png", ink)
            x = i * CELL_W + (CELL_W - icon.width) // 2
            strip.alpha_composite(icon, (x, PAD_TOP))
            w = draw.textlength(name, font=font)
            draw.text((i * CELL_W + (CELL_W - w) / 2, PAD_TOP + icon_h + GAP), name, font=font, fill=LABEL[mode])
        strip.save(OUT / f"menubar-states-{mode}.png", optimize=True)


if __name__ == "__main__":
    main()
