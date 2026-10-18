"""Presentation sheets: logo, construction grid, explorations, app icon, menu bar. SVG with every word set in the
Clepso faces as outlines (typeset.py), rendered to PNG at 2× with cairosvg. Sources: sheets/*.svg, renders:
sheets/*.png."""
import base64
import io
import math
from pathlib import Path

import cairosvg
from PIL import Image

import logo
HORIZ_W = logo.layout("horizontal")[1]
STACK_W, STACK_H = logo.layout("stacked")[1:]
from logo import SYMBOL, SYMBOL_SMALL, RING_ONLY, symbol_cells
from pixels import svg_path, trace
from typeset import svg_text, width

BRAND = Path(__file__).resolve().parent.parent
PIX = BRAND / "fonts" / "ClepsoPixel-Regular.ttf"
MONO = BRAND / "fonts" / "ClepsoMono-Regular.ttf"
MONO_M = BRAND / "fonts" / "ClepsoMono-Medium.ttf"

INK, SURF, MUTED, LINE = "#060907", "#0D1410", "#16211A", "#2C4034"
TEXT, TEXT2, ACCENT, AMBER, RUST, PAPER = "#EAF7EE", "#93B9A0", "#4DFF8F", "#FFC04D", "#FF6B5E", "#F3F1E7"

THEMES = [  # name, background, accent, text  (values from Sources/DesignSystem/Theme/Tokens.swift)
    ("Phosphor · dark", "#060907", "#4DFF8F", "#EAF7EE"),
    ("Phosphor · light", "#F3F1E7", "#0A7238", "#0F1A13"),
    ("Ember", "#130D09", "#F4AE55", "#F7E7D0"),
    ("Classic · light", "#F2F2F7", "#1D4FD7", "#1C1C1E"),
    ("Classic · dark", "#1C1C1E", "#7FA8FF", "#F5F5F7"),
]


def T(text, size, x, y, fill=TEXT, font=MONO, **kw):
    return svg_text(font, text, size, x, y, fill, **kw)


def P(text, size, x, y, fill=TEXT, **kw):
    """Pixel face: size a multiple of 10 keeps every pixel on whole units."""
    return svg_text(PIX, text, size, x, y, fill, **kw)


def para(text, size, x, y, w, fill=TEXT2, font=MONO, lh=1.5):
    words, line, out, yy = text.split(), "", [], y
    for word in words:
        trial = (line + " " + word).strip()
        if width(font, trial, size) > w and line:
            out.append(T(line, size, x, yy, fill, font))
            yy += size * lh
            line = word
        else:
            line = trial
    if line:
        out.append(T(line, size, x, yy, fill, font))
        yy += size * lh
    return "".join(out), yy


def cells_path(on, p, x, y, fill, h=None):
    """Pixel cells (y down) as one traced path at p units per cell, top-left at (x, y)."""
    if not on:
        return ""
    H = h or (max(c[1] for c in on) + 1)
    flipped = {(cx, H - 1 - cy) for cx, cy in on}
    return f'<path d="{svg_path(trace(flipped), scale=p, dx=x, dy=y, height=H)}" fill="{fill}"/>'


def kind_path(kind, p, x, y, fill):
    on, w, h = logo.layout(kind)
    return cells_path(on, p, x, y, fill, h)


def png_href(img):
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def image(path_or_img, x, y, w, h, pixelated=False):
    img = path_or_img if isinstance(path_or_img, Image.Image) else Image.open(path_or_img)
    style = ' style="image-rendering:pixelated"' if pixelated else ""
    return f'<image x="{x}" y="{y}" width="{w}" height="{h}" href="{png_href(img)}"{style}/>'


def header(W, eyebrow, title, sub):
    out = [f'<rect width="{W}" height="100%" fill="{INK}"/>',
           T(eyebrow.upper(), 13, 64, 70, TEXT2, tracking=2.6),
           P(title, 40, 64, 128, TEXT)]
    s, _ = para(sub, 16, 64, 168, W - 128, TEXT2)
    out.append(s)
    return "".join(out)


def save(name, W, H, body):
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">'
           f'<rect width="{W}" height="{H}" fill="{INK}"/>{body}</svg>')
    out = BRAND / "sheets"
    out.mkdir(exist_ok=True)
    (out / f"{name}.svg").write_text(svg)
    cairosvg.svg2png(bytestring=svg.encode(), write_to=str(out / f"{name}.png"), output_width=W * 2, output_height=H * 2)


def panel(x, y, w, h, fill=SURF, stroke=LINE):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="{stroke}" stroke-width="1"/>'


# --------------------------------------------------------------------------------------------- logo sheet
def logo_sheet():
    W, H = 1600, 1270
    o = [header(W, "Clepso brand · 01 Logo", "THE MARK", "A heartbeat inside a ring: the ring is the limit, the beat is the "
         "live reading. Symbol, wordmark and two lockups, drawn on one 16-unit pixel grid and shown here at whole-pixel scales.")]
    y0 = 236
    o.append(panel(64, y0, 1472, 430, INK))
    # symbol, horizontal, stacked
    o.append(kind_path("symbol", 14, 140, y0 + 103, ACCENT))
    o.append(kind_path("horizontal", 10, 470, y0 + 135, ACCENT))
    o.append(kind_path("stacked", 8, 1150, y0 + 107, ACCENT))
    for label, x in (("SYMBOL", 140), ("HORIZONTAL LOCKUP", 470), ("STACKED LOCKUP", 1150)):
        o.append(T(label, 12, x, y0 + 392, TEXT2, tracking=2))
    # colourways
    y1 = y0 + 470
    o.append(T("COLOURWAYS", 12, 64, y1, TEXT2, tracking=2))
    ways = [("Phosphor on ink", INK, ACCENT, TEXT2), ("Deep green on paper", PAPER, "#0A7238", "#44564A"),
            ("Black, one colour", "#FFFFFF", "#000000", "#5A5A64"), ("White, reversed", "#000000", "#FFFFFF", "#B0B0BA")]
    cw = (1472 - 3 * 16) / 4
    for i, (name, bg, fg, cap) in enumerate(ways):
        x = 64 + i * (cw + 16)
        o.append(f'<rect x="{x}" y="{y1 + 16}" width="{cw}" height="230" fill="{bg}" stroke="{LINE}"/>')
        o.append(kind_path("horizontal", 5, x + (cw - HORIZ_W * 5) / 2, y1 + 16 + 75, fg))
        o.append(T(name, 13, x + 20, y1 + 16 + 205, cap))
    # themes
    y2 = y1 + 290
    o.append(T("ACROSS THEMES · THE MARK TAKES THE ACCENT; THE SHAPE NEVER CHANGES", 12, 64, y2, TEXT2, tracking=2))
    tw = (1472 - 4 * 16) / 5
    for i, (name, bg, acc, txt) in enumerate(THEMES):
        x = 64 + i * (tw + 16)
        o.append(f'<rect x="{x}" y="{y2 + 16}" width="{tw}" height="200" fill="{bg}" stroke="{LINE}"/>')
        o.append(kind_path("stacked", 3, x + (tw - logo.WORD_W * 3) / 2, y2 + 16 + 40, acc))
        o.append(T(name, 13, x + 16, y2 + 16 + 150, txt))
        o.append(T(acc, 12, x + 16, y2 + 16 + 174, txt, opacity=0.7))
    save("logo-sheet", W, H, "".join(o))


# --------------------------------------------------------------------------------------------- construction
def construction_sheet():
    W, H = 1600, 1730
    o = [header(W, "Clepso brand · 02 Construction", "CONSTRUCTION GRID",
                "Unit p = 1/16 of the symbol. Every edge falls on whole p; the ring approximates a circle of radius 8 p "
                "with the stepped profile of the app's 16 px menu bar ring; the beat spans 10 × 10 p and is centred on both axes.")]
    p, gx, gy = 40, 104, 290
    o.append(panel(64, 250, 720, 760, INK))
    # grid
    lines = []
    for i in range(17):
        lines.append(f'<line x1="{gx + i * p}" y1="{gy}" x2="{gx + i * p}" y2="{gy + 16 * p}"/>')
        lines.append(f'<line x1="{gx}" y1="{gy + i * p}" x2="{gx + 16 * p}" y2="{gy + i * p}"/>')
    o.append(f'<g stroke="{LINE}" stroke-width="1">{"".join(lines)}</g>')
    # beat baseline band
    o.append(f'<rect x="{gx}" y="{gy + 8 * p}" width="{16 * p}" height="{p}" fill="{AMBER}" fill-opacity="0.07"/>')
    o.append(cells_path(symbol_cells(), p, gx, gy, ACCENT, 16))
    # keylines
    cx, cy = gx + 8 * p, gy + 8 * p
    o.append(f'<circle cx="{cx}" cy="{cy}" r="{8 * p}" fill="none" stroke="{AMBER}" stroke-width="1.5" stroke-dasharray="6 6"/>')
    o.append(f'<circle cx="{cx}" cy="{cy}" r="{7 * p}" fill="none" stroke="{AMBER}" stroke-width="1" stroke-dasharray="2 6"/>')
    o.append(f'<line x1="{cx}" y1="{gy - 14}" x2="{cx}" y2="{gy + 16 * p + 14}" stroke="{RUST}" stroke-width="1.2"/>')
    o.append(f'<line x1="{gx - 14}" y1="{cy}" x2="{gx + 16 * p + 14}" y2="{cy}" stroke="{RUST}" stroke-width="1.2"/>')
    o.append(f'<rect x="{gx + 3 * p}" y="{gy + 3 * p}" width="{10 * p}" height="{10 * p}" fill="none" stroke="{TEXT}" '
             f'stroke-width="1.2" stroke-dasharray="10 5"/>')
    # dimensions
    o.append(dim_h(gx, gx + 16 * p, gy + 16 * p + 34, "16 p"))
    o.append(dim_v(gx + 16 * p + 30, gy, gy + 16 * p, "16 p"))
    o.append(T("beat 10 × 10 p", 12, gx + 3 * p + 6, gy + 3 * p - 8, TEXT))
    # legend
    leg = [(AMBER, "dash", "Keyline: circle r = 8 p (outer) and 7 p (inner)"), (RUST, "line", "Optical centre: x = 8 p, y = 8 p"),
           (TEXT, "dash", "Beat box: x 3–13 p, y 3–13 p"), (AMBER, "band", "Beat baseline: row 8"),
           (ACCENT, "fill", "Stroke: 1 p everywhere")]
    for i, (c, kind, label) in enumerate(leg):
        ly = 1050 + i * 28
        if kind == "fill":
            o.append(f'<rect x="64" y="{ly - 11}" width="12" height="12" fill="{c}"/>')
        elif kind == "band":
            o.append(f'<rect x="62" y="{ly - 11}" width="18" height="12" fill="{c}" fill-opacity="0.25"/>')
        else:
            o.append(f'<line x1="62" y1="{ly - 5}" x2="80" y2="{ly - 5}" stroke="{c}" stroke-width="2"'
                     f'{" stroke-dasharray=\"4 3\"" if kind == "dash" else ""}/>')
        o.append(T(label, 14, 92, ly, TEXT2))

    # lockup with clear space
    lx, ly0, q = 840, 250, 9
    o.append(panel(lx, ly0, 696, 440, INK))
    o.append(T("HORIZONTAL LOCKUP · CLEAR SPACE", 12, lx + 24, ly0 + 34, TEXT2, tracking=2))
    ox, oy = lx + (696 - (HORIZ_W + 8) * q) / 2, ly0 + 92
    o.append(f'<rect x="{ox}" y="{oy}" width="{(HORIZ_W + 8) * q}" height="{(16 + 8) * q}" fill="{AMBER}" fill-opacity="0.08" '
             f'stroke="{AMBER}" stroke-dasharray="5 4"/>')
    o.append(f'<rect x="{ox + 4 * q}" y="{oy + 4 * q}" width="{HORIZ_W * q}" height="{16 * q}" fill="{INK}"/>')
    o.append(kind_path("horizontal", q, ox + 4 * q, oy + 4 * q, ACCENT))
    o.append(dim_h(ox, ox + 4 * q, oy + (16 + 8) * q + 22, "4 p", small=True))
    o.append(dim_h(ox + 20 * q, ox + 25 * q, oy + (16 + 8) * q + 22, "5 p", small=True))
    o.append(dim_v(ox + (HORIZ_W + 8) * q + 16, oy + 8 * q, oy + 15 * q, "7 p", small=True))
    o.append(T("tracking 2 p", 12, ox + 32 * q, oy + 3 * q - 6, TEXT2))
    s, _ = para("Clear space is 4 p on every side (a quarter of the symbol). The wordmark's cap height is 7 p and sits "
                "4 p below the symbol's top, its centre half a p above the symbol's, which reads as level.", 13, lx + 24, ly0 + 372, 648)
    o.append(s)
    # stacked
    sy0 = ly0 + 460
    o.append(panel(lx, sy0, 696, 300, INK))
    o.append(T("STACKED LOCKUP", 12, lx + 24, sy0 + 34, TEXT2, tracking=2))
    q2 = 6
    sx = lx + 60
    o.append(f'<rect x="{sx}" y="{sy0 + 56}" width="{(logo.WORD_W + 8) * q2}" height="{(STACK_H + 8) * q2}" fill="{AMBER}" fill-opacity="0.08" '
             f'stroke="{AMBER}" stroke-dasharray="5 4"/>')
    o.append(f'<rect x="{sx + 4 * q2}" y="{sy0 + 56 + 4 * q2}" width="{logo.WORD_W * q2}" height="{STACK_H * q2}" fill="{INK}"/>')
    o.append(kind_path("stacked", q2, sx + 4 * q2, sy0 + 56 + 4 * q2, ACCENT))
    sx_p = (logo.WORD_W - 16) // 2 + (logo.WORD_W - 16) % 2
    centred = "exactly centred" if (logo.WORD_W - 16) % 2 == 0 else "on the grid, half a p right of true centre"
    s, _ = para(f"Symbol over wordmark, 4 p apart. The wordmark is {logo.WORD_W} p wide, the symbol 16 p, so the symbol's "
                f"left edge sits at {sx_p} p: {centred}. Below 64 px wide, render it at even scales only.",
                13, lx + 360, sy0 + 80, 300)
    o.append(s)

    # small symbol
    ky = sy0 + 320
    o.append(panel(lx, ky, 696, 300, INK))
    o.append(T("SMALL SYMBOL · 12 p GRID", 12, lx + 24, ky + 34, TEXT2, tracking=2))
    q3 = 16
    kx = lx + 40
    grid = []
    for i in range(13):
        grid.append(f'<line x1="{kx + i * q3}" y1="{ky + 60}" x2="{kx + i * q3}" y2="{ky + 60 + 12 * q3}"/>')
        grid.append(f'<line x1="{kx}" y1="{ky + 60 + i * q3}" x2="{kx + 12 * q3}" y2="{ky + 60 + i * q3}"/>')
    o.append(f'<g stroke="{LINE}" stroke-width="1">{"".join(grid)}</g>')
    o.append(cells_path(symbol_cells(SYMBOL_SMALL), q3, kx, ky + 60, ACCENT, 12))
    s, _ = para("The same drawing on the app's 12 p glyph grid, for places where 16 p cannot sit 1:1: the 16 px app icon "
                "and the favicon. Ring of the app's 12 px circle glyph; beat x 2–10 p, y 3–9 p, centred. Use it only "
                "below 24 px.", 13, lx + 280, ky + 76, 390)
    o.append(s)

    # minimum sizes
    my = 1370
    o.append(panel(64, my, 1472, 330, INK))
    o.append(T("MINIMUM SIZES · SHOWN AT ACTUAL SIZE (1 p = 1 px, 2 px)", 12, 88, my + 34, TEXT2, tracking=2))
    items = [("symbol", 1, "Symbol 16 px", "menu bar, favicon"), ("symbol", 2, "Symbol 32 px", "@2x"),
             ("horizontal", 1, f"Lockup {HORIZ_W} × 16 px", "smallest digital"), ("horizontal", 2, f"Lockup {HORIZ_W * 2} × 32 px", "@2x"),
             ("stacked", 2, f"Stacked {STACK_W * 2} × {STACK_H * 2} px", "smallest stacked")]
    x = 88
    for kind, sc, name, note in items:
        on, w, h = logo.layout(kind)
        o.append(kind_path(kind, sc, x, my + 90, ACCENT))
        o.append(T(name, 13, x, my + 190, TEXT))
        o.append(T(note, 12, x, my + 212, TEXT2))
        x += max(w * sc, 150) + 70
    s, _ = para("Scale in whole multiples of the grid below 64 px (16, 32, 48, 64 px…); above that, any size. In print, the "
                "symbol is never smaller than 6 mm and the horizontal lockup never narrower than 20 mm.", 13, 88, my + 262, 1400)
    o.append(s)
    save("construction", W, H, "".join(o))


def dim_h(x0, x1, y, label, small=False):
    t = 6
    return (f'<g stroke="{TEXT2}" stroke-width="1"><line x1="{x0}" y1="{y}" x2="{x1}" y2="{y}"/>'
            f'<line x1="{x0}" y1="{y - t}" x2="{x0}" y2="{y + t}"/><line x1="{x1}" y1="{y - t}" x2="{x1}" y2="{y + t}"/></g>'
            + T(label, 12 if small else 13, (x0 + x1) / 2, y + 20, TEXT2, anchor="middle"))


def dim_v(x, y0, y1, label, small=False):
    t = 6
    return (f'<g stroke="{TEXT2}" stroke-width="1"><line x1="{x}" y1="{y0}" x2="{x}" y2="{y1}"/>'
            f'<line x1="{x - t}" y1="{y0}" x2="{x + t}" y2="{y0}"/><line x1="{x - t}" y1="{y1}" x2="{x + t}" y2="{y1}"/></g>'
            + T(label, 12 if small else 13, x + 10, (y0 + y1) / 2 + 4, TEXT2))


# --------------------------------------------------------------------------------------------- explorations
def bresenham(x0, y0, x1, y1):
    pts, dx, dy = [], abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        pts.append((x0, y0))
        if x0 == x1 and y0 == y1:
            return pts
        e2 = 2 * err
        if e2 >= dy:
            err += dy; x0 += sx
        if e2 <= dx:
            err += dx; y0 += sy


def polyline(*pts):
    out = set()
    for a, b in zip(pts, pts[1:]):
        out |= set(bresenham(*a, *b))
    return out


def exploration_marks():
    ring = symbol_cells(RING_ONLY)
    ecg = polyline((1, 9), (5, 9), (7, 3), (9, 13), (11, 6), (12, 9), (14, 9))
    core = ring | {(7, 7), (8, 7), (7, 8), (8, 8)}
    mono = symbol_cells(["................", "..##########....", "..###########...", "..##.......###..", "..##........##..",
                         "..##........##..", "..##.......###..", "..###########...", "..##########....", "..##............",
                         "..##............", "..##............", "..##............", "..##............", "................",
                         "................"])
    gauge = {(x, y) for x, y in ring if not (y >= 11 and 4 <= x <= 11)} | polyline((8, 8), (12, 4)) | {(7, 8), (8, 9), (7, 9)}
    bars = {(x, y) for x0, h in ((2, 6), (5, 11), (8, 14), (11, 8)) for x in (x0, x0 + 1) for y in range(15 - h, 15)}
    return [
        ("A", "ECG line", ecg, "The favicon's heartbeat, alone. Says 'health app'; every fitness tracker owns it. "
                               "Without a container it has no silhouette at 16 px and cannot carry a status."),
        ("B", "Lit core", core, "The 1.11 menu bar ring with a 2 × 2 core. Clean, but reads as a radio button or "
                                "a record light: a control, not a product."),
        ("C", "P monogram", mono, "Ownable as a letter, empty as an idea, and tied to a working name that may change. "
                                  "A pixel P also blurs into 'D' and 'R' at 16 px."),
        ("D", "Gauge", gauge, "Speedometer cliché. The needle's angle is illegible at 16 px, and it promises a precise "
                              "reading the app often cannot give (stale and missing are first-class states)."),
        ("E", "Signal bars", bars, "Reads as Wi-Fi, audio level or cell signal. Strong silhouette, wrong meaning."),
        ("F", "Beat in the ring", symbol_cells(), "Chosen. The ring is the limit (and the existing menu bar ring); the "
                                                  "beat is the live reading. One idea, legible at 16 px, and it can "
                                                  "flatline, warn or go stale without changing shape."),
    ]


def refinement_marks():
    def m(rows):
        return symbol_cells(rows)
    touching = m([".....######.....", "...##......##...", "..#..........#..", ".#....#.......#.", ".#...#.#......#.",
                  "#....#.#.......#", "#....#.#.......#", "#....#.#.......#", "######.#..######", "#......#.#.....#",
                  "#......#.#.....#", ".#.....#.#....#.", ".#......#.....#.", "..#..........#..", "...##......##...",
                  ".....######....."])
    bold = m([".....######.....", "...##......##...", "..#..........#..", ".#....##......#.", ".#....##......#.",
              "#....#..#......#", "#....#..#......#", "#....#..#..#...#", "######..#.#.####", "#.......#.#....#",
              "#........#.....#", ".#.......#....#.", ".#............#.", "..#..........#..", "...##......##...",
              ".....######....."])
    square = m([".##############.", "#..............#", "#..............#", "#......#.......#", "#.....#.#......#",
                "#.....#.#......#", "#.....#.#......#", "#.....#.#......#", "#######.#..#####", "#.......#.#....#",
                "#.......#.#....#", "#.......#.#....#", "#........#.....#", "#..............#", "#..............#",
                ".##############."])
    return [
        ("F1", "Trace edge to edge", touching, "The line splits the ring into halves: reads as a theta or a null sign."),
        ("F2", "Heavy beat", bold, "Two-pixel peak clots at 16 px and fights the 1 p ring."),
        ("F3", "Square screen", square, "An oscilloscope, but also a generic chart icon; loses the menu bar ring."),
        ("F4", "Floating trace", symbol_cells(), "Chosen: the beat floats with a 2 p margin, centred on both axes."),
    ]


def menubar_strip(on, scale=1, light=True):
    """A 16 px mark on a sliver of menu bar, at actual size × scale."""
    bg = (236, 236, 236, 255) if light else (40, 40, 42, 255)
    fg = (20, 20, 20, 255) if light else (245, 245, 245, 255)
    img = Image.new("RGBA", (40 * scale, 24 * scale), bg)
    for x, y in on:
        for i in range(scale):
            for j in range(scale):
                img.putpixel(((12 + x) * scale + i, (4 + y) * scale + j), fg)
    return img


def explorations_sheet():
    W, H = 1600, 1180
    o = [header(W, "Clepso brand · 03 Process", "HOW THE MARK CAME ABOUT",
                "Six directions were drawn on the same 16 px grid and judged at actual menu bar size first, large second. "
                "The brief: one idea a person gets in a glance, legible at 16 px in one colour, able to show status.")]
    cw, gap = (1472 - 5 * 16) / 6, 16
    y0 = 240
    for i, (code, name, on, verdict) in enumerate(exploration_marks()):
        x = 64 + i * (cw + gap)
        chosen = code == "F"
        o.append(panel(x, y0, cw, 560, INK, ACCENT if chosen else LINE))
        o.append(cells_path(on, 9, x + (cw - 144) / 2, y0 + 30, ACCENT if chosen else TEXT, 16))
        strip = menubar_strip(on, 2)
        o.append(image(strip, x + (cw - 80) / 2, y0 + 200, 80, 48, pixelated=True))
        o.append(T("actual size @2x", 11, x + cw / 2, y0 + 268, TEXT2, anchor="middle"))
        o.append(P(code, 20, x + 16, y0 + 316, ACCENT if chosen else TEXT2))
        o.append(T(name, 15, x + 48, y0 + 314, TEXT, MONO_M))
        s, _ = para(verdict, 12.5, x + 16, y0 + 348, cw - 32, TEXT if chosen else TEXT2, lh=1.45)
        o.append(s)
        if not chosen:
            o.append(T("REJECTED", 11, x + cw - 16, y0 + 540, RUST, anchor="end", tracking=1.5))
        else:
            o.append(T("CHOSEN", 11, x + cw - 16, y0 + 540, ACCENT, anchor="end", tracking=1.5))
    y1 = y0 + 610
    o.append(T("REFINING F · FOUR DRAWINGS OF THE BEAT", 12, 64, y1, TEXT2, tracking=2))
    rw = (1472 - 3 * 16) / 4
    for i, (code, name, on, note) in enumerate(refinement_marks()):
        x = 64 + i * (rw + 16)
        chosen = code == "F4"
        o.append(panel(x, y1 + 18, rw, 330, INK, ACCENT if chosen else LINE))
        o.append(cells_path(on, 10, x + 24, y1 + 48, ACCENT if chosen else TEXT, 16))
        o.append(image(menubar_strip(on, 2, light=False), x + 214, y1 + 48, 80, 48, pixelated=True))
        o.append(image(menubar_strip(on, 1), x + 214, y1 + 112, 40, 24, pixelated=True))
        o.append(T(f"{code}  {name}", 14, x + 24, y1 + 248, TEXT, MONO_M))
        s, _ = para(note, 12.5, x + 24, y1 + 274, rw - 48, TEXT if chosen else TEXT2)
        o.append(s)
    save("explorations", W, H, "".join(o))


# --------------------------------------------------------------------------------------------- app icon
def app_icon_sheet():
    W, H = 1600, 970
    o = [header(W, "Clepso brand · 04 App icon", "APP ICON",
                "The symbol as a lit dot matrix on a phosphor screen: unlit pixels inside the ring, the beat glowing. "
                "Every size is drawn on whole device pixels; 16 and 32 px use hand-placed pixels, not a scaled master.")]
    ic = BRAND / "app-icon"
    for bgfill, y0, label in (("url(#desk)", 240, "ON A LIGHT DESKTOP"), (INK, 600, "ON A DARK DESKTOP")):
        o.append(f'<rect x="64" y="{y0}" width="1472" height="330" fill="{bgfill}" stroke="{LINE}"/>')
        o.append(T(label, 12, 88, y0 + 30, "#44564A" if y0 == 240 else TEXT2, tracking=2))
        x = 96
        for s, shown in ((1024, 256), (512, 160), (256, 128), (128, 128), (64, 64), (32, 32), (16, 16)):
            yy = y0 + 50 + (256 - shown) / 2
            o.append(image(ic / f"clepso-app-icon-{s}.png", x, yy, shown, shown, pixelated=s <= 64))
            o.append(T(f"{s} px" if s == shown else f"{s} px (shown {shown})", 12, x, y0 + 320,
                       "#44564A" if y0 == 240 else TEXT2))
            x += shown + 60
    defs = '<defs><linearGradient id="desk" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#E9E6DA"/><stop offset="1" stop-color="#C9D8CF"/></linearGradient></defs>'
    save("app-icon-sheet", W, H, defs + "".join(o))


# --------------------------------------------------------------------------------------------- menu bar
def menubar_sheet():
    W, H = 1600, 1060
    o = [header(W, "Clepso brand · 05 Menu bar", "MENU BAR",
                "A template image: black pixels on transparency, tinted by macOS for light, dark and tinted menu bars. "
                "Shape carries the meaning. Shown at 2× with the percentage set in Clepso Pixel at 10 pt (1 pixel = 1 pt).")]
    on = symbol_cells()
    for i, (light, label) in enumerate(((True, "LIGHT MENU BAR"), (False, "DARK MENU BAR"))):
        y0 = 250 + i * 150
        bg, fg = ("#ECECEC", "#141414") if light else ("#2A2A2C", "#F5F5F5")
        o.append(f'<rect x="64" y="{y0}" width="1472" height="96" fill="{bg}" stroke="{LINE}"/>')
        o.append(T(label, 12, 64, y0 - 12, TEXT2, tracking=2))
        # 2x: 1 p = 2 px; menu bar 24 pt tall → 48 px; icon 16 pt → 32 px
        bx = 900
        o.append(cells_path(on, 4, bx, y0 + 16, fg, 16))
        o.append(P("83%", 40, bx + 64 + 16, y0 + 16 + 4 * 11.5, fg))
        o.append(T("Wi-Fi    Sat 17 Oct  20:01", 22, 1536 - 32, y0 + 58, fg, opacity=0.55, anchor="end"))
    y1 = 580
    o.append(T("STATUS FAMILY · PROPOSED FOR MenuBarIcon (SAME RING, THE MARK INSIDE CHANGES)", 12, 64, y1, TEXT2, tracking=2))
    sw = (1472 - 4 * 16) / 5
    for i, (key, (label, cells_)) in enumerate(logo.menubar_states().items()):
        x = 64 + i * (sw + 16)
        o.append(panel(x, y1 + 18, sw, 420, INK, ACCENT if key == "beat" else LINE))
        o.append(cells_path(cells_, 10, x + (sw - 160) / 2, y1 + 50, ACCENT if key == "beat" else TEXT, 16))
        o.append(image(menubar_strip(cells_, 2), x + (sw - 80) / 2, y1 + 240, 80, 48, pixelated=True))
        o.append(image(menubar_strip(cells_, 2, light=False), x + (sw - 80) / 2, y1 + 296, 80, 48, pixelated=True))
        o.append(T(key, 15, x + 20, y1 + 384, TEXT, MONO_M))
        o.append(T(label, 12, x + 20, y1 + 406, TEXT2))
    save("menubar-sheet", W, H, "".join(o))


def build_all(brand=BRAND):
    logo_sheet()
    construction_sheet()
    explorations_sheet()
    app_icon_sheet()
    menubar_sheet()
