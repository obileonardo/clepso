"""The Pulse logo: symbol, wordmark and lockups, drawn on one pixel grid.

Unit: p = one grid pixel = 1/16 of the symbol's height. Every element sits on whole p, and every raster
render uses a whole number of device pixels per p, so the mark is never resampled.
"""
from pathlib import Path

from PIL import Image, ImageDraw

import pixel_glyphs
from pixels import cells, svg_path, trace

# The symbol: a heartbeat inside the ring (16 × 16). The beat spans x 3–12, y 3–12: centred on both axes.
SYMBOL = [
    ".....######.....",
    "...##......##...",
    "..#..........#..",
    ".#....#.......#.",
    ".#...#.#......#.",
    "#....#.#.......#",
    "#....#.#.......#",
    "#....#.#.......#",
    "#..###.#..###..#",
    "#......#.#.....#",
    "#......#.#.....#",
    ".#.....#.#....#.",
    ".#......#.....#.",
    "..#..........#..",
    "...##......##...",
    ".....######.....",
]

# The small symbol (12 × 12) for 16 px app icons and favicons, where the 16 grid cannot fit 1:1.
# Same idea, same rhythm: ring of the app's 12 px glyph set, beat spanning x 2–9, y 3–8 (centred).
SYMBOL_SMALL = [
    "....####....",
    "..##....##..",
    ".#........#.",
    ".#...#....#.",
    "#...#.#....#",
    "#...#.#....#",
    "#.###.#.##.#",
    "#.....#.#..#",
    ".#.....#..#.",
    ".#........#.",
    "..##....##..",
    "....####....",
]

RING = [r.replace("#", "#") for r in SYMBOL]
RING_ONLY = [
    ".....######.....", "...##......##...", "..#..........#..", ".#............#.", ".#............#.",
    "#..............#", "#..............#", "#..............#", "#..............#", "#..............#",
    "#..............#", ".#............#.", ".#............#.", "..#..........#..", "...##......##...", ".....######.....",
]

TRACKING = 2           # p between wordmark letters
LOCKUP_GAP = 5         # p between symbol and wordmark (horizontal)
STACK_GAP = 4          # p between symbol and wordmark (stacked)
WORD_TOP = 4           # wordmark cap top, in p from the symbol's top (centre 7.5 of 16)
CLEAR = 4              # clear space on every side, p (a quarter of the symbol)

COLOURS = {
    "phosphor": "#4DFF8F",     # on dark: the signature
    "deep": "#0A7238",         # on paper (Phosphor light)
    "black": "#000000",
    "white": "#FFFFFF",
}
INK = "#060907"
PAPER = "#F3F1E7"


def symbol_cells(rows=SYMBOL, x=0, y=0):
    """Cells with y down (row index), offset by (x, y)."""
    return {(x + c, y + r) for r, row in enumerate(rows) for c, ch in enumerate(row) if ch == "#"}


def wordmark_rows():
    letters = [pixel_glyphs.G[ch][1] for ch in "PULSE"]
    h = len(letters[0])
    rows = [""] * h
    for i, glyph in enumerate(letters):
        for r in range(h):
            rows[r] += glyph[r] + ("." * TRACKING if i < len(letters) - 1 else "")
    return rows


WORDMARK = wordmark_rows()
WORD_W, WORD_H = len(WORDMARK[0]), len(WORDMARK)


def layout(kind):
    """(cells y-down, width, height) for 'symbol', 'symbol-small', 'wordmark', 'horizontal', 'stacked'."""
    if kind == "symbol":
        return symbol_cells(), 16, 16
    if kind == "symbol-small":
        return symbol_cells(SYMBOL_SMALL), 12, 12
    if kind == "wordmark":
        return symbol_cells(WORDMARK), WORD_W, WORD_H
    if kind == "horizontal":
        on = symbol_cells() | symbol_cells(WORDMARK, x=16 + LOCKUP_GAP, y=WORD_TOP)
        return on, 16 + LOCKUP_GAP + WORD_W, 16
    if kind == "stacked":
        # The wordmark is 33 p wide and the symbol 16 p: the symbol sits half a p right of centre's grid line,
        # so both stay on whole p (see NOTES.md). Rendered at even pixel scales only below 64 px.
        sx = (WORD_W - 16) // 2 + 1
        on = symbol_cells(x=sx) | symbol_cells(WORDMARK, y=16 + STACK_GAP)
        return on, WORD_W, 16 + STACK_GAP + WORD_H
    raise KeyError(kind)


def svg(kind, colour, scale=1, pad=0, background=None):
    on, w, h = layout(kind)
    flipped = {(x, h - 1 - y) for x, y in on}                 # trace works y-up
    d = svg_path(trace(flipped), scale=scale, dx=pad * scale, dy=pad * scale, height=h)
    W, H = (w + 2 * pad) * scale, (h + 2 * pad) * scale
    bg = f'<rect width="{W}" height="{H}" fill="{background}"/>' if background else ""
    title = {"symbol": "Pulse symbol", "symbol-small": "Pulse symbol, small", "wordmark": "Pulse wordmark",
             "horizontal": "Pulse logo, horizontal", "stacked": "Pulse logo, stacked"}[kind]
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
            f'shape-rendering="crispEdges" role="img" aria-label="{title}"><title>{title}</title>{bg}'
            f'<path d="{d}" fill="{colour}" fill-rule="nonzero"/></svg>\n')


def png(kind, colour, scale, pad=0, background=None):
    """Pixel-exact raster: each p is scale × scale device pixels, no resampling."""
    on, w, h = layout(kind)
    W, H = (w + 2 * pad) * scale, (h + 2 * pad) * scale
    bg = background or (0, 0, 0, 0)
    img = Image.new("RGBA", (W, H), bg)
    d = ImageDraw.Draw(img)
    for x, y in on:
        x0, y0 = (x + pad) * scale, (y + pad) * scale
        d.rectangle([x0, y0, x0 + scale - 1, y0 + scale - 1], fill=colour)
    return img


def hex_rgba(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def write_logo(out: Path):
    svg_dir, png_dir = out / "svg", out / "png"
    svg_dir.mkdir(parents=True, exist_ok=True)
    png_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for kind in ("symbol", "symbol-small", "wordmark", "horizontal", "stacked"):
        for cname, colour in COLOURS.items():
            p = svg_dir / f"pulse-{kind}-{cname}.svg"
            p.write_text(svg(kind, colour))
            written.append(p)
        # Reversed on the brand's dark and light grounds, with clear space included.
        (svg_dir / f"pulse-{kind}-on-ink.svg").write_text(svg(kind, COLOURS["phosphor"], pad=CLEAR, background=INK))
        (svg_dir / f"pulse-{kind}-on-paper.svg").write_text(svg(kind, COLOURS["deep"], pad=CLEAR, background=PAPER))
    # Rasters at whole-pixel scales.
    for kind, scales in (("symbol", (1, 2, 4, 8, 16, 32, 64)), ("symbol-small", (1, 2, 4)),
                         ("wordmark", (2, 4, 8, 16)), ("horizontal", (2, 4, 8, 16)), ("stacked", (2, 4, 8, 16))):
        for s in scales:
            on, w, h = layout(kind)
            for cname in ("phosphor", "black", "white"):
                png(kind, hex_rgba(COLOURS[cname]), s).save(png_dir / f"pulse-{kind}-{cname}-{w * s}.png")
            png(kind, hex_rgba(COLOURS["phosphor"]), s, pad=CLEAR, background=hex_rgba(INK)).save(
                png_dir / f"pulse-{kind}-on-ink-{(w + 2 * CLEAR) * s}.png")
            png(kind, hex_rgba(COLOURS["deep"]), s, pad=CLEAR, background=hex_rgba(PAPER)).save(
                png_dir / f"pulse-{kind}-on-paper-{(w + 2 * CLEAR) * s}.png")
    return written


# --------------------------------------------------------------------------------------------- menu bar
# The status family proposed for MenuBarIcon (shape carries meaning; the system tints the template).
def menubar_states():
    beat = symbol_cells()
    ring = symbol_cells(RING_ONLY)
    inner = beat - ring
    bang = {(x, y) for x in (7, 8) for y in range(4, 10)} | {(7, 11), (8, 11)}
    flat = {(x, 8) for x in range(3, 13)}
    clock = {(7, y) for y in range(4, 9)} | {(x, 8) for x in range(8, 11)}
    dashed = {(x, y) for x, y in ring if (x + y) % 4 >= 2}
    return {
        "beat": ("Available (the brand mark)", ring | inner),
        "approaching": ("Approaching a limit", ring | bang),
        "flatline": ("Limit reached: the beat flatlines", ring | flat),
        "stale": ("Stale: last reading is old", ring | clock),
        "demo": ("Demo data: broken ring", dashed | inner),
    }


def write_menubar(out: Path):
    out.mkdir(parents=True, exist_ok=True)
    black = (0, 0, 0, 255)
    on = symbol_cells()
    for size, pad in ((16, 0), (18, 1)):
        for scale in (1, 2):
            img = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
            d = ImageDraw.Draw(img)
            for x, y in on:
                x0, y0 = (x + pad) * scale, (y + pad) * scale
                d.rectangle([x0, y0, x0 + scale - 1, y0 + scale - 1], fill=black)
            suffix = "" if scale == 1 else "@2x"
            img.save(out / f"PulseMenuBarTemplate-{size}{suffix}.png")
    for name, (_, cells_) in menubar_states().items():
        for scale in (1, 2):
            img = Image.new("RGBA", (16 * scale, 16 * scale), (0, 0, 0, 0))
            d = ImageDraw.Draw(img)
            for x, y in cells_:
                d.rectangle([x * scale, y * scale, x * scale + scale - 1, y * scale + scale - 1], fill=black)
            img.save(out / f"state-{name}{'' if scale == 1 else '@2x'}.png")
    rows = "\n".join(SYMBOL)
    coords = sorted((x, y) for x, y in on if (x, y) not in symbol_cells(RING_ONLY))
    (out / "pulse-menubar-matrix.txt").write_text(
        "Pulse menu bar symbol, 16 x 16, row 0 at the top, '#' = opaque black (template image).\n"
        "The ring is identical to MenuBarIcon.ring; the beat replaces the 2 x 2 'lit core' of the .ring state.\n\n"
        f"{rows}\n\nBeat pixels (x, y), y down, for MenuBarIcon.mark(.ring):\n{coords}\n")
    swift_pairs = ", ".join(f"({x}, {y})" for x, y in coords)
    (out / "MenuBarBeat.swift.txt").write_text(
        "// Drop-in for Sources/DesignSystem/Theme/MenuBarIcon.swift, `mark(_:)` (not applied: DesignSystem is being\n"
        "// changed by another engineer). Replaces the 2 x 2 lit core of `.ring` with the Pulse beat.\n"
        f"case .ring: return [{swift_pairs}]\n")


# --------------------------------------------------------------------------------------------- app icon
def superellipse(cx, cy, a, n=5.0, steps=90):
    """macOS-style continuous-corner square of half-size a: straight sides and superellipse corners spanning
    1.528 × the nominal 22.5 % radius (the 'squircle' of the Big Sur icon template)."""
    import math
    E = min(a, 1.528 * 0.225 * 2 * a)
    pts = []
    corners = [(cx + a - E, cy + a - E, 0), (cx - a + E, cy + a - E, 1), (cx - a + E, cy - a + E, 2), (cx + a - E, cy - a + E, 3)]
    for ox, oy, q in corners:
        for i in range(steps + 1):
            t = (q + i / steps) * math.pi / 2
            c, s_ = math.cos(t), math.sin(t)
            pts.append((ox + E * math.copysign(abs(c) ** (2 / n), c), oy + E * math.copysign(abs(s_) ** (2 / n), s_)))
    return pts


ICON = {
    "canvas": 1024, "body": 824, "grid": 576, "pitch": 36, "dot": 30, "dot_radius": 5,
    "top": "#13231B", "bottom": "#040705", "lit": "#4DFF8F", "unlit_alpha": 0.075,
}


def _inside_screen(x, y):
    """Cells of the 16 grid inside the ring (the round screen)."""
    import math
    return math.hypot(x + 0.5 - 8, y + 0.5 - 8) < 7.2


def app_icon_svg():
    c = ICON
    cv, body = c["canvas"], c["body"]
    off = (cv - body) / 2
    pts = superellipse(cv / 2, cv / 2, body / 2)
    shape = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + "Z"
    g0 = (cv - c["grid"]) / 2
    lit = symbol_cells()
    rects_lit, rects_dim = [], []
    for y in range(16):
        for x in range(16):
            px, py = g0 + x * c["pitch"] + (c["pitch"] - c["dot"]) / 2, g0 + y * c["pitch"] + (c["pitch"] - c["dot"]) / 2
            r = f'<rect x="{px:g}" y="{py:g}" width="{c["dot"]}" height="{c["dot"]}" rx="{c["dot_radius"]}"/>'
            if (x, y) in lit:
                rects_lit.append(r)
            elif _inside_screen(x, y):
                rects_dim.append(r)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {cv} {cv}" width="{cv}" height="{cv}">
<title>Pulse app icon</title>
<defs>
  <linearGradient id="body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{c['top']}"/><stop offset="1" stop-color="{c['bottom']}"/></linearGradient>
  <radialGradient id="screen" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{c['lit']}" stop-opacity="0.16"/><stop offset="1" stop-color="{c['lit']}" stop-opacity="0"/></radialGradient>
  <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/><stop offset="0.25" stop-color="#FFFFFF" stop-opacity="0.04"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0.02"/></linearGradient>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="14"/><feOffset dy="10"/><feComponentTransfer><feFuncA type="linear" slope="0.45"/></feComponentTransfer></filter>
  <filter id="glow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="16"/></filter>
  <clipPath id="clip"><path d="{shape}"/></clipPath>
</defs>
<g id="shadow-layer"><path d="{shape}" fill="#000" filter="url(#shadow)"/></g>
<g id="body-layer" clip-path="url(#clip)">
  <rect width="{cv}" height="{cv}" fill="url(#body)"/>
  <circle cx="{cv / 2}" cy="{cv / 2}" r="{c['grid'] * 0.47}" fill="url(#screen)"/>
  <g id="matrix-off" fill="{c['lit']}" fill-opacity="{c['unlit_alpha']}">{''.join(rects_dim)}</g>
  <g id="matrix-glow" fill="{c['lit']}" opacity="0.75" filter="url(#glow)">{''.join(rects_lit)}</g>
  <g id="matrix-on" fill="{c['lit']}">{''.join(rects_lit)}</g>
</g>
<path d="{shape}" fill="none" stroke="url(#rim)" stroke-width="3"/>
</svg>
"""


def app_icon_png(size):
    """Raster from the same geometry. ≥ 64 px: 4× supersampled master with glow, downsampled. 32 and 16 px are
    drawn on the pixel grid by hand rules (16 grid at 1 px, 12 grid at 1 px), because downsampling would blur."""
    from PIL import ImageFilter
    if size in (16, 32):
        return _app_icon_small(size)
    c = ICON
    N = 4096
    k = 4

    def S(v):
        return v * k

    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    pts = [(S(x), S(y)) for x, y in superellipse(512, 512, c["body"] / 2)]
    # shadow
    sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon([(x, y + S(10)) for x, y in pts], fill=(0, 0, 0, 115))
    sh = sh.filter(ImageFilter.GaussianBlur(S(14)))
    img.alpha_composite(sh)
    # body gradient clipped to the squircle
    top, bot = hex_rgba(c["top"]), hex_rgba(c["bottom"])
    grad = Image.new("RGBA", (1, N))
    for y in range(N):
        t = y / (N - 1)
        grad.putpixel((0, y), tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,))
    grad = grad.resize((N, N))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    body = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    body.paste(grad, (0, 0), mask)
    # screen glow
    lit = hex_rgba(c["lit"])
    glow_c = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    r = S(c["grid"] * 0.47)
    ImageDraw.Draw(glow_c).ellipse([N / 2 - r * 0.6, N / 2 - r * 0.6, N / 2 + r * 0.6, N / 2 + r * 0.6], fill=lit[:3] + (40,))
    glow_c = glow_c.filter(ImageFilter.GaussianBlur(S(70)))
    body.alpha_composite(glow_c)
    # matrix: drawn on whole device pixels for the target size, so dots stay crisp at every size
    pitch = max(2, round(c["pitch"] * size / 1024))
    dotpx = pitch if size <= 64 else max(2, round(pitch * c["dot"] / c["pitch"]))
    inset = (pitch - dotpx) // 2
    g0 = (size - 16 * pitch) // 2
    rad = max(0, round(dotpx * c["dot_radius"] / c["dot"]))
    on = symbol_cells()
    dim = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    bright = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    dd, bd = ImageDraw.Draw(dim), ImageDraw.Draw(bright)
    f = N // size
    for y in range(16):
        for x in range(16):
            px, py = (g0 + x * pitch + inset) * f, (g0 + y * pitch + inset) * f
            box = [px, py, px + dotpx * f - 1, py + dotpx * f - 1]
            if (x, y) in on:
                bd.rounded_rectangle(box, radius=rad * f, fill=lit)
            elif _inside_screen(x, y):
                dd.rounded_rectangle(box, radius=rad * f, fill=lit[:3] + (int(255 * c["unlit_alpha"]),))
    body.alpha_composite(dim)
    glow = bright.filter(ImageFilter.GaussianBlur(S(16)))
    glow.putalpha(glow.getchannel("A").point(lambda a: int(a * 0.75)))
    body.alpha_composite(glow)
    body.alpha_composite(bright)
    # rim light along the top edge
    rim = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(rim).polygon(pts, outline=(255, 255, 255, 72), width=S(3))
    fade = Image.new("L", (1, N))
    for y in range(N):
        fade.putpixel((0, y), int(255 * max(0.1, 1 - y / (N * 0.35))))
    rim.putalpha(Image.composite(rim.getchannel("A"), Image.new("L", (N, N), 0), fade.resize((N, N))))
    body.alpha_composite(rim)
    img.alpha_composite(body)
    return img.resize((size, size), Image.LANCZOS)


def _app_icon_small(size):
    c = ICON
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ss = 8
    big = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    m = 1 if size == 16 else 3
    radius = (3 if size == 16 else 6) * ss
    ImageDraw.Draw(big).rounded_rectangle([m * ss, m * ss, (size - m) * ss - 1, (size - m) * ss - 1], radius=radius,
                                          fill=hex_rgba("#0B140F"))
    img.alpha_composite(big.resize((size, size), Image.LANCZOS))
    d = ImageDraw.Draw(img)
    rows, off = (SYMBOL_SMALL, 2) if size == 16 else (SYMBOL, 8)
    for x, y in symbol_cells(rows):
        d.point((x + off, y + off), fill=hex_rgba(c["lit"]))
    return img


def write_app_icon(out: Path):
    out.mkdir(parents=True, exist_ok=True)
    (out / "pulse-app-icon.svg").write_text(app_icon_svg())
    iconset = out / "Pulse.iconset"
    iconset.mkdir(exist_ok=True)
    cache = {}
    for s in (16, 32, 64, 128, 256, 512, 1024):
        cache[s] = app_icon_png(s)
        cache[s].save(out / f"pulse-app-icon-{s}.png")
    appiconset = out / "AppIcon.appiconset"
    appiconset.mkdir(exist_ok=True)
    images = []
    for pt in (16, 32, 128, 256, 512):
        cache[pt].save(iconset / f"icon_{pt}x{pt}.png")
        cache[pt * 2].save(iconset / f"icon_{pt}x{pt}@2x.png")
        for scale, px in ((1, pt), (2, pt * 2)):
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            cache[px].save(appiconset / name)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
    import json
    (appiconset / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    return cache


def write_favicon(out: Path):
    out.mkdir(parents=True, exist_ok=True)
    d = svg_path(trace({(x, 11 - y) for x, y in symbol_cells(SYMBOL_SMALL)}), dx=2, dy=2, height=12)
    (out / "favicon.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" shape-rendering="crispEdges">'
        f'<rect width="16" height="16" rx="3" fill="{INK}"/><path d="{d}" fill="{COLOURS["phosphor"]}"/></svg>\n')
    imgs = {}
    for s in (16, 32, 48):
        k = s // 16
        img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        big = Image.new("RGBA", (s * 8, s * 8), (0, 0, 0, 0))
        ImageDraw.Draw(big).rounded_rectangle([0, 0, s * 8 - 1, s * 8 - 1], radius=3 * k * 8, fill=hex_rgba(INK))
        img.alpha_composite(big.resize((s, s), Image.LANCZOS))
        dr = ImageDraw.Draw(img)
        for x, y in symbol_cells(SYMBOL_SMALL):
            dr.rectangle([(x + 2) * k, (y + 2) * k, (x + 3) * k - 1, (y + 3) * k - 1], fill=hex_rgba(COLOURS["phosphor"]))
        imgs[s] = img
        img.save(out / f"favicon-{s}.png")
    # Base image is the largest so Pillow keeps every size; append_images supplies the exact pixel drawings.
    imgs[48].save(out / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)], append_images=[imgs[16], imgs[32]])
    # Apple touch icon: full bleed (iOS applies its own mask).
    touch = app_icon_png(1024).crop((100, 100, 924, 924)).resize((180, 180), Image.LANCZOS)
    bg = Image.new("RGBA", (180, 180), hex_rgba("#0A120D"))
    bg.alpha_composite(touch)
    bg.convert("RGB").save(out / "apple-touch-icon.png")
