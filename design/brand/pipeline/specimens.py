"""Type specimens rendered by CoreText (render.swift) from the built font files, registered at process scope exactly
as the app registers its fonts. The renderer exits non-zero if any text run resolves to a font other than the one
named, so each PNG is proof that the file installs and renders on macOS."""
import json
import subprocess
from pathlib import Path

from type_system import APP, FAMILIES, WEB

HERE = Path(__file__).resolve().parent
BRAND = HERE.parent
FONTS = BRAND / "fonts"
OUT = BRAND / "specimens"
BIN = HERE / ".build" / "render"

INK, SURF, LINE = "#060907", "#0D1410", "#2C4034"
TEXT, TEXT2, ACCENT, AMBER, RUST = "#EAF7EE", "#93B9A0", "#4DFF8F", "#FFC04D", "#FF6B5E"
PX, MR, MM, MB = "ClepsoPixel-Regular", "ClepsoMono-Regular", "ClepsoMono-Medium", "ClepsoMono-Bold"


def renderer():
    src = HERE / "render.swift"
    if not BIN.exists() or BIN.stat().st_mtime < src.stat().st_mtime:
        BIN.parent.mkdir(exist_ok=True)
        subprocess.run(["swiftc", "-O", "-o", str(BIN), str(src)], check=True)
    return BIN


class Page:
    def __init__(self, w, h):
        self.w, self.h, self.texts, self.rects = w, h, [], []

    def t(self, font, size, x, y, text, color=TEXT, **kw):
        self.texts.append(dict(font=font, size=size, color=color, x=x, y=y, text=text, **kw))

    def r(self, x, y, w, h, color, radius=0):
        self.rects.append(dict(x=x, y=y, w=w, h=h, color=color, radius=radius))

    def head(self, eyebrow, title, title_font, title_size, sub):
        self.t(MM, 13, 64, 52, eyebrow.upper(), TEXT2, tracking=2.4)
        self.t(title_font, title_size, 64, 84, title)
        self.t(MR, 16, 64, 96 + title_size * 1.25, sub, TEXT2, maxWidth=1100, lineHeight=25)

    def save(self, name):
        OUT.mkdir(exist_ok=True)
        spec = dict(fonts=[str(p) for p in sorted(FONTS.glob("*.otf"))], width=self.w, height=self.h, scale=2,
                    background=INK, rects=self.rects, texts=self.texts)
        path = OUT / f"{name}.json"
        path.write_text(json.dumps(spec, ensure_ascii=False, indent=1))
        res = subprocess.run([str(renderer()), str(path), str(OUT / f"{name}.png")], capture_output=True, text=True)
        if res.returncode:
            raise SystemExit(f"specimen {name} failed: {res.stderr}")
        path.unlink()
        print("  " + res.stdout.strip().replace(str(BRAND) + "/", ""))


def pixel_specimen():
    p = Page(1600, 1560)
    p.head("Clepso brand · Type 01 · Display", "CLEPSO PIXEL", PX, 80,
           "The display face. Capitals 7 pixels tall on a 10-pixel em (one pixel = 100 units), drawn so a number can "
           "never be misread: dotted zero, flagged one, square-shouldered five. Tabular figures; kerning computed so "
           "open shapes tuck in and no two strokes ever touch. Replaces Silkscreen.")
    y = 300
    p.t(MM, 12, 64, y, "CHARACTER SET · 30 PX", TEXT2, tracking=2)
    rows = ["ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", "0123456789  %  +−×÷=±<>≤≥≈",
            ".,:;…!?'\"‘’“”()[]{}/\\|-–—_·•*#@&$€£¢",
            "→←↑↓↗↘  ⌘⌥⇧⏎  ✓■□▲▼▶◀●○  ©®™°§¶",
            "ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØŒÙÚÛÜÝŠŽ", "àáâãäåæçèéêëìíîïñòóôõöøœùúûüýÿšžß¡¿«»"]
    for i, row in enumerate(rows):
        p.t(PX, 30, 64, y + 30 + i * 46, row)
    y = 680
    p.r(64, y, 1472, 1, LINE)
    p.t(MM, 12, 64, y + 24, "SIZES · WHOLE PIXELS AT 10, 20, 30, 40, 60 PX", TEXT2, tracking=2)
    yy = y + 60
    for s in (10, 20, 30, 40, 60):
        p.t(MR, 12, 64, yy + s * 0.35, f"{s}", TEXT2)
        p.t(PX, s, 130, yy, "RESETS 20:01 · 83% USED · 7-DAY 21%")
        yy += s * 1.2 + 18
    y = yy + 20
    p.r(64, y, 1472, 1, LINE)
    p.t(MM, 12, 64, y + 24, "NEVER MISREAD", TEXT2, tracking=2)
    pairs = [("0 O", "dot in the zero"), ("1 I l", "flag and foot · serifs · tail"), ("5 S", "square shoulder · chamfer"),
             ("8 B", "round both sides · flat left"), ("6 G", "open hook · spur"), ("9 g", "hook · descender")]
    for i, (glyphs, note) in enumerate(pairs):
        x = 64 + i * 245
        p.t(PX, 60, x, y + 60, glyphs, ACCENT)
        p.t(MR, 12, x, y + 150, note, TEXT2, maxWidth=220)
    y += 210
    p.r(64, y, 1472, 1, LINE)
    p.t(MM, 12, 64, y + 24, "IN USE", TEXT2, tracking=2)
    p.r(64, y + 56, 520, 190, SURF)
    p.t(PX, 20, 88, y + 80, "5-HOUR", TEXT)
    p.t(PX, 80, 88, y + 116, "83", ACCENT)
    p.t(PX, 40, 88 + 96 + 8, y + 156, "%", TEXT2)
    p.t(MM, 13, 330, y + 96, "Approaching limit", AMBER)
    p.t(MR, 12, 330, y + 120, "Resets 20:01 · in 2h 14m", TEXT2)
    p.t(MR, 12, 330, y + 140, "Reported just now", TEXT2)
    p.r(620, y + 56, 916, 190, SURF)
    p.t(PX, 50, 644, y + 84, "YOUR LIMITS,", TEXT)
    p.t(PX, 50, 644, y + 144, "BEFORE YOU HIT THEM.", ACCENT)
    p.save("clepso-pixel-specimen")


def mono_specimen():
    p = Page(1600, 1610)
    p.head("Clepso brand · Type 02 · Body", "Clepso Mono", MM, 72,
           "The body face. A monospace constructed from the same rounded rectangle as the pixel face's chamfered "
           "corners, drawn at high resolution. Vertical strokes heavier than horizontal for an even colour; Regular, "
           "Medium and Bold are one drawing at three stroke widths. Replaces SF Mono for sentences.")
    y = 300
    for i, (ps, label) in enumerate(((MR, "Regular 400"), (MM, "Medium 500"), (MB, "Bold 700"))):
        p.t(MR, 12, 64, y + i * 64 + 14, label.upper(), TEXT2, tracking=1.5)
        p.t(ps, 40, 240, y + i * 64, "Reported limits available · 83% · 20:01")
    y = 520
    p.r(64, y, 1472, 1, LINE)
    p.t(MM, 12, 64, y + 24, "CHARACTER SET · 26 PX", TEXT2, tracking=2)
    rows = ["ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz", "0123456789 %+−×÷=±<>≤≥≈ .,:;…!?'\"‘’“”()[]{}/\\|-–—_·•*#@&$€£¢",
            "→←↑↓↗↘ ⌘⌥⇧⏎ ✓■□▲▼▶◀●○ ©®™° ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝ", "àáâãäåçèéêëìíîïñòóôõöøùúûüýÿ ŠšŽžČč ß ¡¿«»"]
    for i, row in enumerate(rows):
        p.t(MR, 26, 64, y + 52 + i * 40, row)
    y = 760
    p.r(64, y, 1472, 1, LINE)
    p.t(MM, 12, 64, y + 24, "TEXT SIZES", TEXT2, tracking=2)
    sample = ("Clepso reads the status line Claude Code already sends, on your Mac. It never reads your prompts, files or "
              "transcript, makes no AI calls and costs no tokens. Missing is never zero: a value that has not arrived says so.")
    yy = y + 56
    for s, lh, ps in ((12, 17, MR), (13, 19, MM), (15, 24, MR), (20, 30, MR)):
        p.t(MR, 12, 64, yy + 2, f"{s}/{lh}", TEXT2)
        p.t(ps, s, 160, yy, sample, TEXT, maxWidth=1200, lineHeight=lh)
        yy += lh * (2 if s < 20 else 3) + 26
    y = yy + 10
    p.r(64, y, 1472, 1, LINE)
    p.t(MM, 12, 64, y + 24, "NEVER MISREAD", TEXT2, tracking=2)
    p.t(MR, 48, 64, y + 56, "Il1|  O0o  5S  8B  6G  9g  rn m  {[()]}", ACCENT)
    y += 150
    p.r(64, y, 1472, 1, LINE)
    p.t(MM, 12, 64, y + 24, "BESIDE SF MONO AT THE APP'S SIZES (2×)", TEXT2, tracking=2)
    lines = ["Approaching limit · just now", "Resets 20:01 · in 2h 14m", "Estimate: at this pace, 100% around 18:29"]
    for col, (font, label) in enumerate(((MM, "Clepso Mono Medium 13"), ("system-mono-medium", "SF Mono Medium 13"))):
        x = 64 + col * 740
        p.r(x, y + 50, 720, 150, SURF)
        p.t(MR, 12, x + 20, y + 64, label.upper(), TEXT2, tracking=1.5)
        for i, l in enumerate(lines):
            p.t(font, 13, x + 20, y + 94 + i * 30, l)
    p.save("clepso-mono-specimen")


def type_system_sheet():
    rows = len(APP) + len(WEB)
    p = Page(1600, 360 + rows * 92 + 120)
    p.head("Clepso brand · Type 03 · System", "TYPE SYSTEM", PX, 50,
           "Two faces, one geometry. Clepso Pixel speaks in numbers and labels; Clepso Mono explains. Pixel sizes are "
           "multiples of 5 pt in the app (whole device pixels on Retina) and of 10 px on the web.")
    y = 250

    def section(title, data, app):
        nonlocal y
        p.t(MM, 12, 64, y, title, TEXT2, tracking=2)
        p.t(MM, 12, 1000, y, "FACE · SIZE / LINE · TRACKING", TEXT2, tracking=2)
        y += 30
        for row in data:
            token, face, weight, size, lh, track, case, use = row[:8]
            ps = FAMILIES[face]["ps"][weight]
            p.r(64, y, 1472, 1, LINE)
            p.t(MM, 14, 64, y + 18, token, ACCENT)
            p.t(MR, 12, 64, y + 40, use, TEXT2, maxWidth=230)
            sample = {"pixel": "83% · RESETS 20:01" if size >= 30 else "5-HOUR LIMIT · 83%",
                      "mono": "Resets 20:01 · in 2h 14m"}[face]
            if case == "UPPER":
                sample = sample.upper()
            shown = min(size, 60)
            p.t(ps, shown, 320, y + 14 + max(0, (44 - shown) / 2), sample, TEXT, tracking=track or None)
            spec = f"{FAMILIES[face]['family']} {weight} · {size}/{lh}{' pt' if app else ' px'}"
            if track:
                spec += f" · +{track}"
            if shown != size:
                spec += f" (shown at {shown})"
            p.t(MR, 13, 1000, y + 18, spec, TEXT)
            if app and len(row) > 8:
                p.t(MR, 12, 1000, y + 40, "was " + row[8], TEXT2)
            y += 92
        y += 30

    section("APP TOKENS (TypographyToken)", APP, True)
    section("WEB SCALE", WEB, False)
    p.h = y + 40
    p.save("type-system")


def build_all(brand=BRAND):
    pixel_specimen()
    mono_specimen()
    type_system_sheet()
