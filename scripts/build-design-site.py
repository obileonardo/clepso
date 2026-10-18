"""Builds the Clepso brand and design-system page (increment 1.3; rebuilt as brand guidelines on brand/identity).

Input: a folder written by `pulse-design-render` (design.json + img/), the brand kit in design/brand (built by
design/brand/pipeline/build.sh), and read-only Swift sources for the themes (Theme/Tokens.swift) and the pixel icon
set (Pixel/PixelGlyphBitmaps.swift). Output: <site>/design-system/ with index.html, design.json, img/ and brand/
(fonts, logo files, icons, sheets and download kits), plus <site>/vercel.json (and <site>/index.html if missing).

Nothing on the page is drawn by hand: logos and icons are inline SVG generated from the same pixel matrices as the
masters, colours and contrast come from the Swift themes, component images from the Swift renderer.
Usage: python3 -I scripts/build-design-site.py <render dir> <site dir> [screens dir]
Standard library only (the Makefile runs it with the system python3).
"""
import html
import json
import re
import shutil
import sys
import zipfile
from pathlib import Path

render, site = Path(sys.argv[1]), Path(sys.argv[2])
screens_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else None
repo = Path(__file__).resolve().parent.parent
brand_src = repo / "design" / "brand"
design = json.loads((render / "design.json").read_text())
brand = json.loads((brand_src / "brand.json").read_text())
out = site / "design-system"
staging = site / ".design-system-staging"
if staging.exists():
    shutil.rmtree(staging)
staging.mkdir(parents=True)
shutil.copytree(render / "img", staging / "img")
if screens_dir:
    shutil.copytree(screens_dir, staging / "img" / "screens")
shutil.copy(render / "design.json", staging / "design.json")
e = html.escape

# ------------------------------------------------------------------------------------------------ brand assets
kit = staging / "brand"
for sub_dir in ("fonts", "logo/svg", "logo/png", "app-icon", "menubar", "favicon", "sheets", "specimens"):
    (kit / sub_dir).mkdir(parents=True, exist_ok=True)
for f in sorted((brand_src / "fonts").iterdir()):
    shutil.copy(f, kit / "fonts" / f.name)
for sub_dir in ("logo/svg", "logo/png", "menubar", "favicon"):
    for f in sorted((brand_src / sub_dir).iterdir()):
        if f.is_file():
            shutil.copy(f, kit / sub_dir / f.name)
for f in sorted((brand_src / "app-icon").glob("clepso-app-icon*")):
    shutil.copy(f, kit / "app-icon" / f.name)
shutil.copy(brand_src / "app-icon" / "Clepso.icns", kit / "app-icon" / "Clepso.icns")
for f in sorted((brand_src / "sheets").glob("*.png")):
    shutil.copy(f, kit / "sheets" / f.name)
for f in sorted((brand_src / "specimens").glob("*.png")):
    shutil.copy(f, kit / "specimens" / f.name)

STAMP = (2026, 10, 17, 12, 0, 0)                      # fixed zip timestamps: reproducible downloads


def make_zip(name, files):
    """files: list of (path on disk, path in archive)."""
    path = kit / name
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for src, arc in files:
            info = zipfile.ZipInfo(arc, STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, Path(src).read_bytes())
    return path


def tree(folder, prefix):
    """Files under folder for a download, without the iconset (Clepso.icns and AppIcon.appiconset carry the same
    images) and without sheet SVGs (they embed their PNGs; the PNGs are included)."""
    return [(p, prefix + "/" + p.relative_to(folder).as_posix()) for p in sorted(folder.rglob("*")) if p.is_file()
            and not p.name.startswith(".") and "Clepso.iconset" not in p.parts
            and not (p.parent.name == "sheets" and p.suffix == ".svg")]


notes = [(brand_src / n, "Clepso-brand/" + n) for n in ("README.md", "NOTES.md", "INTEGRATION.md")]
zips = {
    "fonts": make_zip("clepso-fonts.zip", tree(brand_src / "fonts", "Clepso-fonts")),
    "logo": make_zip("clepso-logo.zip", tree(brand_src / "logo", "Clepso-logo")),
    "appicon": make_zip("clepso-app-icon.zip", tree(brand_src / "app-icon", "Clepso-app-icon") + tree(brand_src / "favicon", "Clepso-app-icon/favicon")),
    "kit": make_zip("clepso-brand-kit.zip", notes + [x for d in ("fonts", "logo", "app-icon", "menubar", "favicon", "sheets", "specimens")
                                                    for x in tree(brand_src / d, "Clepso-brand/" + d)]),
}


def size_of(p):
    n = Path(p).stat().st_size
    return f"{n / 1048576:.1f} MB" if n >= 1048576 else f"{max(1, round(n / 1024))} KB"


# ------------------------------------------------------------------------------------------------ pixel drawing
def runs(rows, dx=0, dy=0):
    """Path data for a pixel matrix: one rectangle per horizontal run, in grid units."""
    d = []
    for y, row in enumerate(rows):
        x = 0
        while x < len(row):
            if row[x] == "#":
                s = x
                while x < len(row) and row[x] == "#":
                    x += 1
                d.append(f"M{s + dx} {y + dy}h{x - s}v1h-{x - s}z")
            else:
                x += 1
    return "".join(d)


def compose(*parts):
    """Overlay matrices: parts are (rows, x, y). Returns (rows, width, height)."""
    w = max(x + len(r[0]) for r, x, y in parts)
    h = max(y + len(r) for r, x, y in parts)
    grid = [["."] * w for _ in range(h)]
    for rows, ox, oy in parts:
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch == "#":
                    grid[oy + y][ox + x] = "#"
    return ["".join(r) for r in grid], w, h


G = brand["grid"]
SYMBOL, SMALL, WORD = brand["symbol"], brand["symbolSmall"], brand["wordmark"]
WW, WH = len(WORD[0]), len(WORD)
LOCKUPS = {
    "symbol": (SYMBOL, 16, 16),
    "wordmark": (WORD, WW, WH),
    "horizontal": compose((SYMBOL, 0, 0), (WORD, 16 + G["lockupGap"], G["wordTop"])),
    "stacked": compose((SYMBOL, (WW - 16) // 2 + 1, 0), (WORD, 0, 16 + G["stackGap"])),
}


def pix(rows, scale, label, cls="pix", style=""):
    w, h = len(rows[0]), len(rows)
    st = f' style="{style}"' if style else ""
    aria = f'role="img" aria-label="{e(label)}"' if label else 'aria-hidden="true"'
    return (f'<svg class="{cls}" viewBox="0 0 {w} {h}" width="{w * scale}" height="{h * scale}" {aria} '
            f'shape-rendering="crispEdges"{st}><path d="{runs(rows)}" fill="currentColor"/></svg>')


def mark(kind, scale, label=None, cls="pix", style=""):
    rows, w, h = LOCKUPS[kind]
    return pix(rows, scale, label or {"symbol": "Clepso symbol", "wordmark": "Clepso wordmark",
                                      "horizontal": "Clepso logo", "stacked": "Clepso logo, stacked"}[kind], cls, style)


# ------------------------------------------------------------------------------------------------ themes (Tokens.swift)
def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def lum(h):
    def ch(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(c) for c in hexrgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


THEME_NAMES = {"mac": "Classic", "phosphor": "Phosphor", "ember": "Ember"}
THEME_NOTES = {"mac": "The system-native theme that preceded Phosphor.",
               "phosphor": "The signature: phosphor green on near-black glass; warm paper in light mode.",
               "ember": "The pixel pack's warm browns and amber, on dark glass."}
TOKENS = ["background", "surfaceElevated", "surfaceMuted", "separator", "textPrimary", "textSecondary", "accent",
          "statusSuccess", "statusAttention", "statusBlocked", "statusStale", "statusUnknown"]
TEXT_TOKENS = ["textPrimary", "textSecondary", "accent", "statusSuccess", "statusAttention", "statusBlocked", "statusStale", "statusUnknown"]
SURFACES = ["background", "surfaceElevated", "surfaceMuted"]


def parse_themes():
    """Every `public static let x = Theme(...)` in Tokens.swift, as appearances. A theme whose light and dark values
    are equal is one appearance. Falls back to design.json's Phosphor palette if the source format changes."""
    src = repo / "Sources" / "DesignSystem" / "Theme" / "Tokens.swift"
    text = src.read_text() if src.exists() else ""
    themes = []
    # Both spellings: `= Theme(` and the 1.15 helper `= pixel("amber", [`.
    starts = [(m.start(), m.group(1)) for m in re.finditer(r"public static let (\w+) = (?:Theme\(|pixel\()", text)]
    # Only the themes a user can choose (Theme.selectable), in that order; retired ones stay out of the guidelines.
    sel = re.search(r"static let selectable: \[Theme\] = \[([^\]]+)\]", text)
    selectable = [k.strip().lstrip(".") for k in sel.group(1).split(",")] if sel else None
    notes = {k: n.strip() for n, k in re.findall(r"/// ([^\n]+)\n    public static let (\w+) = ", text)}
    ends = [m.start() for m in re.finditer(r"\n    (?:public )?static (?:let|func|var) ", text)] + [len(text)]
    for start, key in starts:
        body = text[start:next(x for x in ends if x > start)]
        pairs = {t: (a, b) for t, a, b in re.findall(r"\.(\w+): \(RGB\(0x([0-9A-Fa-f]{6})\), RGB\(0x([0-9A-Fa-f]{6})\)\)", body)}
        singles = {t: (a, a) for t, a in re.findall(r"\.(\w+): RGB\(0x([0-9A-Fa-f]{6})\)", body)}
        pal = pairs or singles
        if not all(t in pal for t in TOKENS) or (selectable and key not in selectable):
            continue
        apps = [("dark", 1), ("light", 0)] if any(a != b for a, b in pal.values()) else [("dark", 1)]
        for appearance, i in apps:
            colours = {t: "#" + pal[t][i].upper() for t in TOKENS}
            light = lum(colours["background"]) > 0.4
            name = THEME_NAMES.get(key, key.capitalize())
            themes.append({"id": f"{key}-{appearance}" if len(apps) > 1 else key, "key": key,
                           "name": name + (f" · {appearance}" if len(apps) > 1 else ""), "light": light,
                           "note": THEME_NOTES.get(key) or notes.get(key, "").split(": ", 1)[-1], "c": colours, "rank": selectable.index(key) if selectable else 0})
    if not any(t["key"] == "phosphor" for t in themes):
        pal = {p["token"]: p["hex"] for p in design["phosphor"]["palette"]}
        themes.insert(0, {"id": "phosphor-dark", "key": "phosphor", "name": "Phosphor · dark", "light": False, "note": "",
                          "c": {t: pal.get(t, "#FF00FF") for t in TOKENS}})
    order = {"phosphor-dark": 0, "phosphor-light": 1}
    themes.sort(key=lambda t: (t.get("rank", 0), t["id"].endswith("-light")))
    for t in themes:
        c = t["c"]
        c["onAccent"] = max((c["background"], c["textPrimary"], "#000000", "#FFFFFF"), key=lambda x: contrast(x, c["accent"]))
        t["checks"] = [(tx, s, contrast(c[tx], c[s])) for tx in TEXT_TOKENS for s in SURFACES]
        t["worst"] = min(t["checks"], key=lambda x: x[2])
    return themes


THEMES = parse_themes()
DEFAULT = THEMES[0]["id"]
failing = [(t["id"], tx, s, round(r, 2)) for t in THEMES for tx, s, r in t["checks"] if r < 4.5]
if failing:
    print("warning: text below 4.5:1 in", failing)


def theme_vars(t):
    c = t["c"]
    return (f'--bg:{c["background"]};--surface:{c["surfaceElevated"]};--muted:{c["surfaceMuted"]};--line:{c["separator"]};'
            f'--text:{c["textPrimary"]};--text2:{c["textSecondary"]};--accent:{c["accent"]};--on-accent:{c["onAccent"]};'
            f'--ok:{c["statusSuccess"]};--warn:{c["statusAttention"]};--bad:{c["statusBlocked"]};--stale:{c["statusStale"]};'
            f'color-scheme:{"light" if t["light"] else "dark"};')


theme_css = "".join(f':root[data-ds-theme="{t["id"]}"]{{{theme_vars(t)}}}' for t in THEMES)
theme_buttons = "".join(
    f'<button type="button" class="tp" data-ds-theme-pick="{t["id"]}" aria-pressed="{"true" if t["id"] == DEFAULT else "false"}">'
    f'<i style="background:{t["c"]["background"]};color:{t["c"]["accent"]}" aria-hidden="true">■</i>{e(t["name"])}</button>'
    for t in THEMES)
theme_meta = json.dumps({t["id"]: t["light"] for t in THEMES})


# ------------------------------------------------------------------------------------------------ icon set (Swift)
def parse_glyphs():
    src = repo / "Sources" / "DesignSystem" / "Pixel" / "PixelGlyphBitmaps.swift"
    text = src.read_text() if src.exists() else ""
    return [(n, json.loads("[" + body + "]")) for n, body in re.findall(r"\.(\w+): \[((?:\"[.#]+\",?\s*)+)\]", text)]


GLYPHS = parse_glyphs()


def human(name):
    return re.sub(r"(?<!^)([A-Z])", r" \1", name).lower()


# ------------------------------------------------------------------------------------------------ copy blocks
def section_head(num, sid, title, lede):
    return (f'<header class="sh"><p class="eyebrow"><b>{num}</b> / {e(title.upper())}</p>'
            f'<h2 id="{sid}">{e(title)}</h2><p class="lede">{lede}</p></header>')


def sub(title, sid=None, note=None):
    i = f' id="{sid}"' if sid else ""
    n = f'<p class="note">{note}</p>' if note else ""
    return f'<div class="subhead"><h3{i}>{e(title)}</h3>{n}</div>'


def img(src, alt, w=None, h=None, cls="", lazy=True, pixelated=False):
    wh = f' width="{w}" height="{h}"' if w and h else ""
    style = ' style="image-rendering:pixelated"' if pixelated else ""
    load = ' loading="lazy"' if lazy else ""
    return f'<img class="{cls}" src="{e(src)}" alt="{e(alt)}"{wh}{load} decoding="async"{style}>'


def plate(src, alt, caption, w, h, link=True):
    pic = img(src, alt, w, h, "plate-img")
    if link:
        pic = f'<a href="{e(src)}" class="plate-link">{pic}</a>'
    return f'<figure class="plate">{pic}<figcaption>{caption}</figcaption></figure>'


def png_size(p):
    data = Path(p).read_bytes()[16:24]
    return int.from_bytes(data[:4], "big"), int.from_bytes(data[4:], "big")


# ------------------------------------------------------------------------------------------------ 01 logo
def logo_section():
    ex = "".join(
        f'<li class="ex{" chosen" if x["chosen"] else ""}"><div class="ex-art">{pix(x["rows"], 6, x["name"])}'
        f'<span class="ex-1x">{pix(x["rows"], 1, x["name"] + " at 16 px", "pix one")}{pix(x["rows"], 2, x["name"] + " at 32 px", "pix one")}</span></div>'
        f'<p class="ex-name"><b>{x["code"]}</b> {e(x["name"])}<span class="{"yes" if x["chosen"] else "no"}">{"Chosen" if x["chosen"] else "Rejected"}</span></p>'
        f'<p class="ex-v">{e(x["verdict"])}</p></li>' for x in brand["explorations"])
    ref = "".join(
        f'<li class="ex{" chosen" if x["chosen"] else ""}"><div class="ex-art">{pix(x["rows"], 5, x["name"])}</div>'
        f'<p class="ex-name"><b>{x["code"]}</b> {e(x["name"])}</p><p class="ex-v">{e(x["note"])}</p></li>' for x in brand["refinements"])
    lockups = (
        f'<div class="lockups">'
        f'<figure class="tile big"><div class="art">{mark("horizontal", 6)}</div><figcaption>Horizontal lockup · primary</figcaption></figure>'
        f'<figure class="tile"><div class="art">{mark("stacked", 5)}</div><figcaption>Stacked lockup</figcaption></figure>'
        f'<figure class="tile"><div class="art">{mark("symbol", 8)}</div><figcaption>Symbol</figcaption></figure>'
        f'<figure class="tile"><div class="art">{mark("wordmark", 5)}</div><figcaption>Wordmark</figcaption></figure></div>')
    ways = [("Phosphor on ink", "#060907", "#4DFF8F", "#93B9A0"), ("Deep green on paper", "#F3F1E7", "#0A7238", "#44564A"),
            ("Black, one colour", "#FFFFFF", "#000000", "#5A5A64"), ("White, reversed", "#000000", "#FFFFFF", "#B0B0BA")]
    waytiles = "".join(f'<figure class="tile fixed" style="background:{bg};color:{fg}"><div class="art">{mark("horizontal", 3)}</div>'
                       f'<figcaption style="color:{cap}">{e(n)}</figcaption></figure>' for n, bg, fg, cap in ways)
    themetiles = "".join(f'<figure class="tile fixed" style="background:{t["c"]["background"]};color:{t["c"]["accent"]}">'
                         f'<div class="art">{mark("stacked", 3)}</div><figcaption style="color:{t["c"]["textSecondary"]}">{e(t["name"])}'
                         f'<br><code style="color:inherit;background:none">{t["c"]["accent"]}</code></figcaption></figure>' for t in THEMES)
    sym = SYMBOL
    misuse = [
        ("Stretch or squash it", f'<svg class="pix" viewBox="0 0 16 16" width="128" height="72" preserveAspectRatio="none" shape-rendering="crispEdges" aria-hidden="true"><path d="{runs(sym)}" fill="currentColor"/></svg>'),
        ("Rotate it", mark("symbol", 5, style="transform:rotate(-16deg)")),
        ("Fill it with a gradient", f'<svg class="pix" viewBox="0 0 16 16" width="80" height="80" shape-rendering="crispEdges" aria-hidden="true"><defs><linearGradient id="mg" x1="0" x2="1"><stop offset="0" stop-color="#FF6B5E"/><stop offset="1" stop-color="#7FA8FF"/></linearGradient></defs><path d="{runs(sym)}" fill="url(#mg)"/></svg>'),
        ("Outline it", f'<svg class="pix" viewBox="-0.5 -0.5 17 17" width="85" height="85" aria-hidden="true"><path d="{runs(sym)}" fill="none" stroke="currentColor" stroke-width="0.12"/></svg>'),
        ("Add glows, shadows or bevels", mark("symbol", 5, style="filter:drop-shadow(0 0 6px currentColor) drop-shadow(3px 4px 0 #000)")),
        ("Resample it off the grid", '<img src="brand/logo/png/clepso-symbol-phosphor-16.png" width="83" height="83" alt="" style="image-rendering:auto;filter:blur(.6px)">'),
        ("Retype the wordmark", '<span class="retype">Clepso</span>'),
        ("Rearrange the lockup", pix(compose((WORD, 0, G["wordTop"]), (SYMBOL, WW + 5, 0))[0], 2, "")),
        ("Set it on low contrast", f'<span class="lowc">{mark("symbol", 5)}</span>'),
    ]
    misuse_html = "".join(f'<li><div class="art" aria-hidden="true">{art}</div><p><span class="x" aria-hidden="true">✕</span>Don’t {e(t[0].lower() + t[1:])}</p></li>' for t, art in misuse)
    states = "".join(f'<li><div class="art">{pix(s["rows"], 4, s["label"])}</div><div class="mb" aria-hidden="true">'
                     f'<span class="mb-l">{pix(s["rows"], 1, "", "pix one")}</span><span class="mb-d">{pix(s["rows"], 1, "", "pix one")}</span></div>'
                     f'<p><b>{e(s["key"])}</b>{e(s["label"])}</p></li>' for s in brand["states"])
    sizes = "".join(f'<li>{img(f"brand/app-icon/clepso-app-icon-{s}.png", f"Clepso app icon, {s} px", min(s, 128), min(s, 128), pixelated=s <= 64)}<span>{s} px{" · shown 128" if s > 128 else ""}</span></li>'
                    for s in (1024, 256, 128, 64, 32, 16))
    cw, ch = png_size(brand_src / "sheets" / "construction.png")
    ew, eh = png_size(brand_src / "sheets" / "explorations.png")
    return f"""
<section class="block" aria-labelledby="logo">
{section_head("01", "logo", "Logo", "A heartbeat inside a ring. The ring is the limit, the same ring that sits in the menu bar; the beat is the live reading. One idea that reads at 16 pixels, in one colour, in any theme.")}
<div class="concept">
  <div class="concept-art">{mark("symbol", 16, "Clepso symbol, enlarged", cls="pix concept-mark")}
    <span class="callout c1" aria-hidden="true"><i></i>Ring · the limit</span><span class="callout c2" aria-hidden="true"><i></i>Beat · the live reading</span></div>
  <div class="concept-copy">
    <p>Clepso watches something you cannot see, a usage limit, and tells you before you hit it. The mark puts the two things that matter one inside the other: <b>the container that fills</b> and <b>the signal that keeps arriving</b>.</p>
    <p>Because the ring is the existing menu bar ring, the logo and the status icon are one object. The beat is the "available" state; the same ring can hold a warning, a flatline or a clock without the brand changing shape.</p>
    <p>It is drawn on a 16-pixel grid with a 1-pixel stroke, the way the original Macintosh icons were drawn: judged at actual size first, large second.</p>
  </div>
</div>
{sub("How it came about", "logo-process", "Six directions on the same grid, judged at menu bar size. The two small renders beside each are actual size (16 px) and 2×.")}
<ol class="explore">{ex}</ol>
{sub("Refining the beat", None, "Four drawings of the chosen idea. The last floats with a 2 p margin and is centred on both axes.")}
<ol class="explore four">{ref}</ol>
{sub("Lockups", "logo-lockups", "The horizontal lockup is primary. Use the stacked lockup where width is scarce, and the symbol alone where the name is already present: the menu bar, the app icon, a favicon.")}
{lockups}
{sub("Construction", "logo-construction", "Unit <b>p</b> is 1/16 of the symbol. Every edge falls on whole p; the stroke is 1 p everywhere. Wordmark capitals are 7 p, tracked 2 p; the horizontal gap is 5 p; clear space is 4 p on every side.")}
{plate("brand/sheets/construction.png", "Construction grid: the symbol on its 16 p grid with keylines, the lockups with clear space, the small symbol and minimum sizes", 'Construction sheet · <a href="brand/sheets/construction.png">full size</a> · <a href="brand/logo/svg/clepso-symbol-phosphor.svg">symbol SVG</a>', cw // 2, ch // 2)}
<div class="rules">
  <div><h4>Clear space</h4><p>4 p on every side: a quarter of the symbol's height. Nothing else enters it, including the edge of the screen or page.</p></div>
  <div><h4>Minimum size</h4><p>Symbol 16 px (1 p = 1 px). Horizontal lockup 54 × 16 px. In print, symbol 6 mm, lockup 20 mm wide.</p></div>
  <div><h4>Scaling</h4><p>Below 64 px, scale only in whole multiples (16, 32, 48, 64 px) so no pixel is resampled. Above 64 px, any size.</p></div>
  <div><h4>Small symbol</h4><p>A 12 p drawing of the same mark, for the 16 px app icon and the favicon only, where 16 p cannot sit 1:1.</p></div>
</div>
{sub("Colour", "logo-colour", "Always one flat colour. On dark grounds the signature is phosphor green; on paper, deep green; anywhere else, black or white.")}
<div class="tiles four">{waytiles}</div>
{sub("Across themes", None, "In the app the mark takes the active theme's accent. The shape never changes, so recognition never depends on green.")}
<div class="tiles themes">{themetiles}</div>
{sub("Misuse", "logo-misuse", "The mark is pixels on a grid, in one colour, with room around it. Each example below breaks one of those.")}
<ul class="misuse">{misuse_html}</ul>
{sub("App icon", "logo-app-icon", "The symbol as a lit dot matrix on a phosphor screen. Every size is drawn on whole device pixels; 16 and 32 px are placed by hand, not scaled.")}
<div class="appicon">
  <div class="appicon-hero">{img("brand/app-icon/clepso-app-icon-512.png", "Clepso app icon", 256, 256)}</div>
  <ul class="appicon-sizes">{sizes}</ul>
</div>
{sub("Menu bar", "logo-menu-bar", "A template image: opaque pixels on transparency, tinted by macOS for light, dark and tinted menu bars. The beat is the brand; the proposed family keeps the ring and changes what is inside.")}
<div class="menubar-demo" aria-hidden="true">
  <div class="mbar light">{pix(SYMBOL, 2, "", "pix")}<span>83%</span></div>
  <div class="mbar dark">{pix(SYMBOL, 2, "", "pix")}<span>83%</span></div>
</div>
<ul class="states">{states}</ul>
<p class="fine">Template images: <a href="brand/menubar/ClepsoMenuBarTemplate-16.png">16 pt</a>, <a href="brand/menubar/ClepsoMenuBarTemplate-16@2x.png">@2x</a>, <a href="brand/menubar/ClepsoMenuBarTemplate-18.png">18 pt</a>, <a href="brand/menubar/ClepsoMenuBarTemplate-18@2x.png">@2x</a>, <a href="brand/menubar/clepso-menubar-matrix.txt">pixel matrix</a>. Favicon: <a href="brand/favicon/favicon.svg">SVG</a>, <a href="brand/favicon/favicon.ico">ICO</a>.</p>
<details class="more"><summary>The exploration sheet</summary>{plate("brand/sheets/explorations.png", "Exploration sheet: six directions and four refinements", '<a href="brand/sheets/explorations.png">Full size</a>', ew // 2, eh // 2)}</details>
</section>"""


# ------------------------------------------------------------------------------------------------ 02 colour
def colour_section():
    sig = [("Phosphor", "#4DFF8F", "The signature. Marks, accents, the live signal."), ("Ink", "#060907", "Near-black glass. The default ground."),
           ("Paper", "#F3F1E7", "The light ground. Warm, never pure white."), ("Deep", "#0A7238", "Phosphor on paper: the accent in light mode."),
           ("Amber", "#FFC04D", "Attention. Approaching a limit."), ("Rust", "#FF6B5E", "Blocked. A limit reached, an error.")]
    sigs = "".join(f'<li><span class="sw" style="background:{h}"></span><b>{n}</b><code>{h}</code><p>{e(d)}</p></li>' for n, h, d in sig)
    cards = []
    for t in THEMES:
        c = t["c"]
        chips = "".join(f'<li><span class="chip" style="background:{c[k]}"></span><code>{k}</code><span class="hex">{c[k]}</span></li>' for k in TOKENS)
        worst = t["worst"]
        passed = sum(1 for _, _, r in t["checks"] if r >= 4.5)
        rows = ""
        for tx in TEXT_TOKENS:
            cells = "".join(f'<td class="num{" low" if r < 4.5 else ""}">{r:.2f}</td>' for x, s, r in t["checks"] if x == tx)
            rows += f'<tr><th scope="row"><code>{tx}</code></th>{cells}</tr>'
        mini = (f'<div class="mini" style="background:{c["surfaceElevated"]};border-color:{c["separator"]}">'
                f'<p class="mini-t" style="color:{c["textPrimary"]}">5-HOUR</p><p class="mini-n" style="color:{c["accent"]}">83<small style="color:{c["textSecondary"]}">%</small></p>'
                f'<p class="mini-bar" style="background:{c["surfaceMuted"]}"><i style="background:{c["statusAttention"]}"></i></p>'
                f'<p class="mini-s" style="color:{c["statusAttention"]}">Approaching limit</p><p class="mini-s" style="color:{c["textSecondary"]}">Resets 20:01 · in 2h 14m</p></div>')
        cards.append(f"""<article class="theme" style="background:{c['background']};color:{c['textPrimary']};border-color:{c['separator']}">
  <div class="theme-head"><h4>{e(t['name'])}</h4><p style="color:{c['textSecondary']}">{e(t['note'])}</p></div>
  <div class="theme-body">{mini}<ul class="chips" style="color:{c['textSecondary']}">{chips}</ul></div>
  <details style="color:{c['textSecondary']}"><summary>Contrast: {passed}/{len(t['checks'])} pass AA · worst {worst[2]:.2f}:1</summary>
  <div class="table-wrap"><table class="ct"><thead><tr><th scope="col">Text on</th>{''.join(f'<th scope="col">{s}</th>' for s in SURFACES)}</tr></thead><tbody>{rows}</tbody></table></div></details>
  <button type="button" class="tp inline" data-ds-theme-pick="{t['id']}" style="color:{c['accent']};border-color:{c['separator']}">Preview the page in {e(t['name'])}</button>
</article>""")
    return f"""
<section class="block" aria-labelledby="colour">
{section_head("02", "colour", "Colour", "Components ask for a role (background, textSecondary, accent); only the theme knows the value. Every theme below is read from the Swift source at build time, and every text role is checked against every surface: 4.5:1 or better.")}
{sub("Signature colours", "colour-signature", "The brand's own palette, independent of any app theme. Phosphor on ink is the default; amber and rust only ever mean attention and blocked.")}
<ul class="sig">{sigs}</ul>
{sub("Themes", "colour-themes", f"{len(THEMES)} appearances from {len({t['key'] for t in THEMES})} themes. Each card shows the same limit row in that theme, its tokens and its contrast matrix. A theme added to <code>Tokens.swift</code> appears here on the next build.")}
<div class="themes-grid">{''.join(cards)}</div>
<div class="rules">
  <div><h4>Never colour alone</h4><p>Every state has a symbol, words and a bar pattern as well as a colour (tested in the app). Recolouring can never merge two meanings.</p></div>
  <div><h4>Accent is for signal</h4><p>Use the accent for the live figure, the mark and links, not for decoration or large fills.</p></div>
  <div><h4>Status colours are reserved</h4><p>Attention and blocked colours appear only when a limit is near or reached.</p></div>
</div>
</section>"""


# ------------------------------------------------------------------------------------------------ 03 type
def type_section():
    T = brand["type"]
    fonts = {f["file"]: f for f in brand["fonts"]}
    px, mono = fonts.get("ClepsoPixel-Regular", {}), fonts.get("ClepsoMono-Regular", {})

    def scale_rows(rows, unit, app):
        out_rows = []
        for r in rows:
            fam = "px" if r["face"] == "pixel" else "mono"
            weight = {"Regular": 400, "Medium": 500, "Bold": 700}[r["weight"]]
            if fam == "px":
                sample = "83% USED" if r["size"] >= 50 else "83% · RESETS 20:01" if r["size"] >= 30 else "5-HOUR LIMIT · 83%"
            else:
                sample = "Resets 20:01 · in 2h 14m"
            if r["case"] == "UPPER":
                sample = sample.upper()
            shown = min(r["size"], 60)
            spec = f'{T["families"][r["face"]]["family"]} {r["weight"]} · {r["size"]}/{r["lineHeight"]} {unit}' + (f' · +{r["tracking"]}' if r["tracking"] else "")
            if shown != r["size"]:
                spec += f" (shown at {shown})"
            was = f'<span class="was">was {e(r["replaces"])}</span>' if app and r.get("replaces") else ""
            lh = r["lineHeight"] if shown == r["size"] else shown
            out_rows.append(f'<tr><th scope="row"><code>{e(r["token"])}</code><span class="use">{e(r["use"])}</span></th>'
                            f'<td class="samp"><span class="tsample {fam}" style="font-size:{shown}px;line-height:{lh}px;'
                            f'font-weight:{weight};letter-spacing:{r["tracking"]}px">{e(sample)}</span></td>'
                            f'<td class="spec">{e(spec)}{was}</td></tr>')
        return "".join(out_rows)

    def dl(stem):
        return " · ".join(f'<a href="brand/fonts/{stem}.{x}" download>{x.upper()}</a>' for x in ("otf", "ttf", "woff2"))

    pw, ph = png_size(brand_src / "specimens" / "clepso-pixel-specimen.png")
    mw, mh = png_size(brand_src / "specimens" / "clepso-mono-specimen.png")
    return f"""
<section class="block" aria-labelledby="type">
{section_head("03", "type", "Typography", "Two faces drawn for Clepso, one geometry. Clepso Pixel speaks in numbers and labels; Clepso Mono explains. Both are built in code from the same grid logic, so the display face and the body face share corners, rhythm and figures.")}
<div class="faces">
  <article class="face">
    <p class="eyebrow">Display</p><p class="face-big px" aria-hidden="true">Aa 0123</p>
    <h4>Clepso Pixel</h4>
    <p>Capitals 7 pixels tall on a 10-pixel em. Drawn so a number is never misread: dotted 0, flagged 1 with a foot, square-shouldered 5. Tabular figures; kerning that tucks open shapes in without ever touching a stroke.</p>
    <dl><dt>Weights</dt><dd>Regular</dd><dt>Characters</dt><dd>{px.get("characters", "")}, incl. Latin-1 letters, arrows, ⌘ ⌥ ⇧</dd><dt>Use</dt><dd>Figures, titles, labels, buttons, the wordmark</dd><dt>Replaces</dt><dd>Silkscreen</dd></dl>
    <p class="fine">{dl("ClepsoPixel-Regular")}</p>
  </article>
  <article class="face">
    <p class="eyebrow">Body</p><p class="face-big mono" aria-hidden="true">Aa 0123</p>
    <h4>Clepso Mono</h4>
    <p>A monospace constructed from the rounded rectangle behind the pixel face's chamfered corners. Vertical strokes heavier than horizontal for an even texture; three weights from one drawing.</p>
    <dl><dt>Weights</dt><dd>Regular · <span style="font-weight:500">Medium</span> · <b>Bold</b></dd><dt>Characters</dt><dd>{mono.get("characters", "")}, ASCII and Latin-1 letters</dd><dt>Use</dt><dd>Sentences, captions, data labels</dd><dt>Replaces</dt><dd>SF Mono for sentences (kept as fallback)</dd></dl>
    <p class="fine">Regular {dl("ClepsoMono-Regular")}<br>Medium {dl("ClepsoMono-Medium")}<br>Bold {dl("ClepsoMono-Bold")}</p>
  </article>
</div>
{sub("Try them", "type-tester")}
<div class="tester">
  <label for="tester-input">Type a sample</label>
  <input id="tester-input" type="text" value="Reported limits available · 83% · resets 20:01" spellcheck="false" autocomplete="off">
  <p class="t-px px" data-tester>Reported limits available · 83% · resets 20:01</p>
  <p class="t-mono mono" data-tester>Reported limits available · 83% · resets 20:01</p>
</div>
{sub("Never misread", "type-legibility", "The figures were drawn around the confusions a monitor cannot afford. The founder's own review found “8.5B” read as “8.SB” in the previous pixel face.")}
<div class="pairs"><p class="px">0O 1Il 5S 8B 6G 9g</p><p class="mono">Il1| 0Oo 5S 8B 6G 9g rn m</p></div>
{sub("Scale · app", "type-scale", "The app's typography tokens. Pixel sizes are multiples of 5 pt, so on a Retina display every pixel of Clepso Pixel lands on whole device pixels.")}
<div class="table-wrap"><table class="scale"><thead><tr><th scope="col">Token</th><th scope="col">Sample</th><th scope="col">Face · size / line</th></tr></thead><tbody>{scale_rows(T["app"], "pt", True)}</tbody></table></div>
{sub("Scale · web", None, "On the web, pixel sizes are multiples of 10 px. Headings drop a step on phones (h1 50 → 30).")}
<div class="table-wrap"><table class="scale"><thead><tr><th scope="col">Token</th><th scope="col">Sample</th><th scope="col">Face · size / line</th></tr></thead><tbody>{scale_rows(T["web"], "px", False)}</tbody></table></div>
<div class="rules">
  <div><h4>Pairing</h4><p>Pixel for numbers and short labels, usually uppercase. Mono for anything that is a sentence. Never a sentence in Clepso Pixel; never a big figure in Clepso Mono.</p></div>
  <div><h4>Pixel snapping</h4><p>Clepso Pixel's pixel is 1/10 em. Use 15, 20, 25, 30, 35, 40 pt in the app and 10, 20, 30, 50, 60, 80 px on the web; anything else blurs.</p></div>
  <div><h4>No faux styles</h4><p>No synthetic bold or italic of the pixel face, no tracking on it (its spacing is in whole pixels already), no outlines or shadows on type.</p></div>
  <div><h4>Fallback</h4><p>Clepso Mono covers ASCII and Latin-1. Keep the system monospace behind it: names outside the set fall back per character.</p></div>
</div>
<div class="plates two">
{plate("brand/specimens/clepso-pixel-specimen.png", "Clepso Pixel specimen rendered by CoreText", 'Clepso Pixel specimen, rendered by CoreText · <a href="brand/specimens/clepso-pixel-specimen.png">full size</a>', pw // 2, ph // 2)}
{plate("brand/specimens/clepso-mono-specimen.png", "Clepso Mono specimen rendered by CoreText, with SF Mono beside it", "Clepso Mono specimen, beside SF Mono at the app’s sizes · <a href='brand/specimens/clepso-mono-specimen.png'>full size</a>", mw // 2, mh // 2)}
</div>
</section>"""


# ------------------------------------------------------------------------------------------------ 04 icons
def icons_section():
    items = "".join(f'<li>{pix(rows, 3, "")}<span>{e(human(n))}</span></li>' for n, rows in GLYPHS)
    return f"""
<section class="block" aria-labelledby="icons">
{section_head("04", "icons", "Iconography", f"{len(GLYPHS)} icons, each drawn on a 12 × 12 pixel grid with a 1-pixel stroke: the mark's rules at a smaller grid. Read from <code>PixelGlyphBitmaps.swift</code> at build time, so this is exactly the set the app draws.")}
<ul class="glyphs">{items}</ul>
<div class="rules">
  <div><h4>Grid</h4><p>12 × 12 p, 1 p stroke, no anti-aliasing. Sizes are multiples of 6 pt (12, 18, 24) so pixels stay whole.</p></div>
  <div><h4>Colour</h4><p>An icon takes the colour of the text beside it. Status colour only when the icon is the status.</p></div>
  <div><h4>Shape carries meaning</h4><p>Within a family no two states share a shape. A new icon is drawn here first, at 1×, before it ships.</p></div>
  <div><h4>Never mix</h4><p>No smooth system symbols beside pixel icons, and no icon redrawn at a finer grid to make it fit.</p></div>
</div>
</section>"""


# ------------------------------------------------------------------------------------------------ 05 components (from the renderer)
COMPONENT_NOTES = {
    "ProviderCard": "One provider: identity, plan, one row per allowance pool, the active session. Compact in the menu bar popover, expanded in provider detail.",
    "QuotaProgress": "One allowance pool. Takes a provenance-carrying value, never a bare number, so missing data cannot render as 0%. Every state has its own symbol, words and bar pattern as well as colour.",
    "ResetCountdown": "Counts down from a verified reset instant. At the reset time it says “Reset expected”, never “Ready”: only a fresh reading can say that.",
    "PlanPill": "The plan label always carries how it is known. The plan never feeds any arithmetic.",
    "ConnectionHealth": "Whether readings are arriving, with the age of the last one. Never “100% connected”.",
    "DataSourceLabel": "Source and freshness, on every value. Freshness is never omitted; stale values say “last seen”.",
}
ORDER = ["ProviderCard", "QuotaProgress", "ResetCountdown", "PlanPill", "ConnectionHealth", "DataSourceLabel"]
PH_NOTES = {
    "PixelLimitRow": "One allowance pool in the pixel style. Same status words, freshness, reset line and VoiceOver sentence as QuotaProgress (tested); the optional pace line always says “Estimate”.",
    "PixelBar": "The segmented bar. Stale values are dithered and missing values draw only an outline, so meaning never rests on colour.",
    "PixelButtonStyle": "Bevelled pixel buttons: a lit top edge and a shaded bottom edge that swap when pressed.",
    "PixelTabs": "Tabs in the pixel-pack manner, used in the Details window and Stats.",
    "PixelStat": "A value over a small pixel caption, for the session strip and Stats.",
    "PixelLineChart": "History drawn as steps snapped to a pixel grid, with dotted 80/95/100 guides, NOW, and the dashed pace projection. VoiceOver reads a sentence instead of the drawing.",
    "PixelHeatmap": "Activity like Claude Code's /stats: one column per week, Monday on top, four levels plus empty.",
    "PixelPanel": "The frame every pixel screen sits in: stepped corners, an outer frame and an inner rule; glass behind it in the app.",
    "Typography": "Rendered with the faces the app bundles today (Silkscreen); Clepso Pixel replaces it when the integration lands.",
}
SCREENS = [("popover-overview", "Menu bar popover"), ("popover-detail", "Provider detail"), ("popover-inspector", "Where this number comes from"),
           ("details-limits", "Details · Limits: history and pace"), ("details-session", "Details · Session"),
           ("details-stats-overview", "Details · Stats overview"), ("details-stats-models", "Details · Stats models"),
           ("onboarding-3-consent", "Onboarding · consent"), ("settings-diagnostics", "Settings · Diagnostics"),
           ("settings-delete-all-sheet", "Delete all, confirmation")]


def pair(light, dark, alt):
    return (f'<img class="v-light" src="{e(light)}" alt="{e(alt)} (light)" loading="lazy">'
            f'<img class="v-dark" src="{e(dark)}" alt="{e(alt)} (dark)" loading="lazy">')


def components_section():
    ph = design["phosphor"]
    ph_order = list(dict.fromkeys(s["component"] for s in ph["specimens"]))
    ph_sections = []
    for component in ph_order:
        cards = "".join(f'<figure class="specimen ph"><img src="{e(s["image"])}" alt="{e(component + ": " + s["caption"])}" loading="lazy" width="{s["width"]}" height="{s["height"]}">'
                        f'<figcaption><span>{e(s["caption"])}</span><code>{e(s["id"])}</code></figcaption></figure>'
                        for s in ph["specimens"] if s["component"] == component)
        ph_sections.append(f'<div class="component"><h4 class="ch" id="ph-{component.lower()}">{component}</h4>'
                           f'<p class="note">{e(PH_NOTES.get(component, ""))}</p><div class="grid">{cards}</div></div>')
    classic = []
    for component in ORDER:
        rows = [s for s in design["specimens"] if s["component"] == component]
        cards = "".join(f'<figure class="specimen">{pair(s["light"], s["dark"], component + ": " + s["caption"])}'
                        f'<figcaption><span>{e(s["caption"])}</span><code>{e(s["id"])}</code></figcaption></figure>' for s in rows)
        classic.append(f'<div class="component"><h4 class="ch">{component}</h4><p class="note">{e(COMPONENT_NOTES[component])}</p><div class="grid">{cards}</div></div>')
    pal = {p["token"]: (p["light"], p["dark"]) for p in design["palette"]}
    style_rows = "".join(
        f'<tr><td><span class="family">{e(r["family"])}</span></td><td><code>{e(r["state"])}</code></td>'
        f'<td class="glyph">{pair(r["glyph"] + "-light.png", r["glyph"] + "-dark.png", r["symbol"])}</td>'
        f'<td>{e(r["label"])}</td><td class="muted">“{e(r["accessibility"])}”</td>'
        f'<td><span class="swatch" style="--l:{pal[r["role"]][0]};--d:{pal[r["role"]][1]}"></span><code>{e(r["role"])}</code></td>'
        f'<td><span class="pattern p-{e(r["pattern"])}"></span>{e(r["pattern"])}</td></tr>' for r in design["styles"])
    screens = ""
    if screens_dir:
        screens = "".join(f'<figure class="specimen ph"><img src="img/screens/{n}.png" alt="{e(c)}" loading="lazy"><figcaption><span>{e(c)}</span></figcaption></figure>'
                          for n, c in SCREENS if (screens_dir / f"{n}.png").exists())

    def tok(key, unit):
        return "".join(f'<li><code>{e(t["token"])}</code><span>{t["points"]:g} {unit}</span></li>' for t in design[key])

    return f"""
<section class="block" aria-labelledby="components">
{section_head("05", "components", "Components", "The SwiftUI components behind the app, rendered from the Swift code by <code>pulse-design-render</code>. Every image here is the real component or the running app, in demo data.")}
<div class="principles">
  <div><b>A number always says where it came from</b><span>Every value shows its source and age. Components take provenance-carrying values; there is no bare-number input.</span></div>
  <div><b>Missing is never zero</b><span>Absent, null, stale and not connected are four states with their own words. None renders as 0%.</span></div>
  <div><b>Never colour alone</b><span>Each state has a symbol, words, a bar pattern and a spoken phrase.</span></div>
  <div><b>Restyle without changing meaning</b><span>Palette, spacing and layout can change. State names, labels and accessibility text are locked and tested.</span></div>
</div>
{sub("Screens", "components-screens", "The running app in demo data, captured from the signed bundle.")}
<div class="grid screens">{screens}</div>
{sub("Phosphor components", "components-phosphor", "The pixel layer. Every shape is drawn in code on a pixel grid, so it stays sharp and scales with text size.")}
{''.join(ph_sections)}
{sub("Status styles", "components-states", "The single lookup from a state to how it looks and reads. Within each family no two states share a shape (tested).")}
<div class="table-wrap"><table class="styles"><thead><tr><th scope="col">Family</th><th scope="col">State</th><th scope="col">Glyph</th><th scope="col">Label</th><th scope="col">VoiceOver</th><th scope="col">Colour role</th><th scope="col">Pattern</th></tr></thead>
<tbody>{style_rows}</tbody></table></div>
{sub("Spacing, radius, stroke", "components-tokens", "Classic theme values; Phosphor squares the corners (radius 2) and opens spacing to 20.")}
<div class="scales"><ul><li class="h">Spacing</li>{tok("spacing", "pt")}</ul><ul><li class="h">Radius</li>{tok("radius", "pt")}</ul><ul><li class="h">Stroke</li>{tok("stroke", "pt")}</ul></div>
<details class="more"><summary>Classic components ({len(design["specimens"])} states)</summary>
<p class="note">The first six components in the system theme that preceded Phosphor. Still in the code; the pixel components reuse their wording and accessibility text. Light or dark follows the theme you preview.</p>
{''.join(classic)}</details>
</section>"""


# ------------------------------------------------------------------------------------------------ 06 voice
def voice_section():
    pairs = [
        ("Reported limits available", "All limits available", "Say only what the data supports. The status line reports two limits; there may be a third."),
        ("Reset expected", "Ready", "At the reset time no fresh reading has arrived yet. Only a reading can say “ready”."),
        ("Estimate: at this pace, 100% around 18:29", "You'll run out at 18:29", "A projection always says it is one."),
        ("Not reported yet", "0%", "Missing is never zero. Name what is absent."),
        ("Last seen 12 min ago", "Stale", "Give the fact that makes it stale, not the jargon."),
        ("Couldn't update settings. Nothing was changed.", "Oops! Something went wrong.", "Say what happened and what it means for the user's files. No apology theatre."),
    ]
    rows = "".join(f'<tr><td class="do">{e(a)}</td><td class="dont">{e(b)}</td><td>{e(c)}</td></tr>' for a, b, c in pairs)
    return f"""
<section class="block" aria-labelledby="voice">
{section_head("06", "voice", "Voice and tone", "One voice: a precise instrument that tells the truth. The tone shifts with the moment; the voice never does.")}
<div class="principles">
  <div><b>Exact</b><span>Numbers carry their source and age. Units always. No rounding that changes a decision.</span></div>
  <div><b>Plain</b><span>Short words, active verbs, sentence case. The product's job is to be glanced at.</span></div>
  <div><b>Honest about uncertainty</b><span>An estimate says so; a missing value says so; a guess is never shown as a fact.</span></div>
  <div><b>Calm</b><span>No alarms for their own sake. Attention when a limit is near, plain facts when it is reached.</span></div>
</div>
{sub("Tone by moment", "voice-tone")}
<div class="tones">
  <div><h4>Available</h4><p class="q">Reported limits available</p><p>Quiet. One line, then out of the way.</p></div>
  <div><h4>Approaching</h4><p class="q warn">Approaching limit · resets 20:01</p><p>Direct. Lead with what will happen and when.</p></div>
  <div><h4>Reached</h4><p class="q bad">Limit reached · resets in 2h 14m</p><p>Factual. What it is, when it ends. No blame, no exclamation marks.</p></div>
  <div><h4>Missing</h4><p class="q stale">Not reported yet</p><p>Neutral. Name the absence; never fill it.</p></div>
</div>
{sub("Write this, not that", "voice-examples", "From the app's own copy decisions.")}
<div class="table-wrap"><table class="voice"><thead><tr><th scope="col">Write</th><th scope="col">Not</th><th scope="col">Why</th></tr></thead><tbody>{rows}</tbody></table></div>
</section>"""


# ------------------------------------------------------------------------------------------------ 07 downloads
def downloads_section():
    kits = [("kit", "Brand kit", "Everything below plus the guideline notes, sheets and specimens."),
            ("logo", "Logo", "Symbol, small symbol, wordmark and lockups: SVG masters in six colourways, PNGs at whole-pixel scales."),
            ("fonts", "Fonts", "Clepso Pixel and Clepso Mono (Regular, Medium, Bold) as OTF, TTF and WOFF2."),
            ("appicon", "App icon", "Layered SVG master, PNG 16–1024, iconset, ICNS, favicon SVG/ICO/PNG, Apple touch icon.")]
    cards = "".join(f'<li><a class="kit" href="brand/{zips[k].name}" download><b>{e(t)}</b><span>{e(d)}</span><em>ZIP · {size_of(zips[k])}</em></a></li>' for k, t, d in kits)
    singles = [("Symbol · SVG", "brand/logo/svg/clepso-symbol-phosphor.svg"), ("Horizontal lockup · SVG", "brand/logo/svg/clepso-horizontal-phosphor.svg"),
               ("Stacked lockup · SVG", "brand/logo/svg/clepso-stacked-phosphor.svg"), ("Lockup on ink · PNG", "brand/logo/png/" + sorted((brand_src / "logo" / "png").glob("clepso-horizontal-on-ink-*.png"), key=lambda q: int(q.stem.rsplit("-", 1)[1]))[-2].name),
               ("App icon 1024 · PNG", "brand/app-icon/clepso-app-icon-1024.png"), ("App icon · ICNS", "brand/app-icon/Clepso.icns"),
               ("Menu bar template @2x · PNG", "brand/menubar/ClepsoMenuBarTemplate-16@2x.png"), ("Favicon · SVG", "brand/favicon/favicon.svg"),
               ("Logo sheet · PNG", "brand/sheets/logo-sheet.png"), ("Construction · PNG", "brand/sheets/construction.png")]
    lis = "".join(f'<li><a href="{p}" download>{e(n)}</a><span>{size_of(staging / p)}</span></li>' for n, p in singles)
    return f"""
<section class="block" aria-labelledby="downloads">
{section_head("07", "downloads", "Downloads", "Every file is generated by <code>design/brand/pipeline/build.sh</code> from source in the repository, so the downloads always match these guidelines.")}
<ul class="kits">{cards}</ul>
<ul class="files">{lis}</ul>
<p class="fine">The Clepso faces are original drawings, proprietary to Clepso and free to use in Clepso products and materials. “Clepso” is a working name.</p>
</section>"""


# ------------------------------------------------------------------------------------------------ page
NAV = [("logo", "01", "Logo"), ("colour", "02", "Colour"), ("type", "03", "Typography"), ("icons", "04", "Iconography"),
       ("components", "05", "Components"), ("voice", "06", "Voice"), ("downloads", "07", "Downloads")]
nav = "".join(f'<li><a href="#{i}"><span>{n}</span>{e(t)}</a></li>' for i, n, t in NAV)
default_vars = theme_vars(next(t for t in THEMES if t["id"] == DEFAULT))
worst_all = min(r for t in THEMES for _, _, r in t["checks"])
facts = [(str(len(THEMES)), "theme appearances"), (str(len(GLYPHS)), "pixel icons"),
         (str(len(design["phosphor"]["specimens"]) + len(design["specimens"])), "component states"),
         (f"{worst_all:.2f}:1", "worst text contrast")]

CSS = """
@font-face{font-family:"Clepso Pixel";src:url("brand/fonts/ClepsoPixel-Regular.woff2") format("woff2");font-display:swap}
@font-face{font-family:"Clepso Mono";src:url("brand/fonts/ClepsoMono-Regular.woff2") format("woff2");font-weight:400;font-display:swap}
@font-face{font-family:"Clepso Mono";src:url("brand/fonts/ClepsoMono-Medium.woff2") format("woff2");font-weight:500;font-display:swap}
@font-face{font-family:"Clepso Mono";src:url("brand/fonts/ClepsoMono-Bold.woff2") format("woff2");font-weight:700;font-display:swap}
:root{%(default)s --px:"Clepso Pixel",ui-monospace,monospace;--mono:"Clepso Mono",ui-monospace,"SF Mono",Menlo,monospace;--head:var(--p-head,76px)}
%(themes)s
*{box-sizing:border-box}
html{scroll-padding-top:calc(var(--head) + 64px);-webkit-text-size-adjust:100%%}
html,body{margin:0;background:var(--bg);color:var(--text)}
body{font:400 15px/24px var(--mono);-webkit-font-smoothing:antialiased;overflow-x:hidden}
.ds a{color:var(--accent);text-underline-offset:3px;text-decoration-thickness:1px}
.ds a:focus-visible,.ds button:focus-visible,.ds input:focus-visible,.ds summary:focus-visible{outline:2px solid var(--accent);outline-offset:3px}
.ds code{font:13px/1.4 var(--mono);color:var(--text2);overflow-wrap:anywhere}
.ds img{max-width:100%%;height:auto}
.ds .px{font-family:var(--px);font-weight:400}
.ds .mono{font-family:var(--mono)}
.ds .pix{display:block;max-width:100%%;height:auto;color:var(--accent)}
.ds .pix.one{display:inline-block}
.ds{display:grid;grid-template-columns:200px minmax(0,1fr);gap:56px;max-width:1280px;margin:0 auto;padding:0 32px}
.ds-side{position:sticky;top:calc(var(--head) + 28px);align-self:start;padding-top:72px}
.ds-side p{margin:0 0 12px;font:500 12px/16px var(--mono);letter-spacing:.14em;text-transform:uppercase;color:var(--text2)}
.ds-side ol{list-style:none;margin:0 0 32px;padding:0;border-left:1px solid var(--line)}
.ds-side li a{display:flex;gap:12px;padding:6px 0 6px 14px;margin-left:-1px;border-left:1px solid transparent;color:var(--text2);text-decoration:none;font-size:14px}
.ds-side li a span{font-size:12px;width:18px}
.ds-side li a:hover,.ds-side li a.on{color:var(--text);border-left-color:var(--accent)}
.tps{display:flex;flex-direction:column;gap:6px}
.tp{display:flex;align-items:center;gap:10px;width:100%%;text-align:left;font:13px/1.2 var(--mono);color:var(--text2);background:transparent;border:1px solid var(--line);padding:8px 10px;cursor:pointer;border-radius:2px;min-height:40px}
.tp i{font-style:normal;font-size:12px;width:22px;height:22px;display:grid;place-items:center;border:1px solid rgba(127,127,127,.45);flex:none}
.tp:hover{color:var(--text);border-color:var(--text2)}
.tp[aria-pressed="true"]{color:var(--text);border-color:var(--accent);box-shadow:inset 3px 0 0 var(--accent)}
.tp.inline{width:auto;display:inline-flex;margin-top:16px}
.ds-main{min-width:0;padding-bottom:40px}
.hero{padding:72px 0 64px;border-bottom:1px solid var(--line)}
.eyebrow{margin:0 0 18px;font:500 12px/16px var(--mono);letter-spacing:.14em;text-transform:uppercase;color:var(--text2)}
.eyebrow b{color:var(--accent);font-weight:500}
.hero .pix{width:432px}
.hero h1{font:400 50px/56px var(--px);margin:44px 0 20px;text-transform:uppercase;letter-spacing:0;max-width:14em}
.hero h1 em{font-style:normal;color:var(--accent)}
.lede{color:var(--text2);font-size:16px;line-height:26px;max-width:66ch;margin:0}
.facts{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:1px;margin:44px 0 0;padding:0;list-style:none;background:var(--line);border:1px solid var(--line)}
.facts li{background:var(--bg);padding:18px 18px 16px}
.facts b{display:block;font:400 30px/36px var(--px);color:var(--text);font-variant-numeric:tabular-nums}
.facts span{font-size:13px;color:var(--text2)}
.hero-themes{margin-top:28px}
.hero-themes p{margin:0 0 10px;font:500 12px/16px var(--mono);letter-spacing:.14em;text-transform:uppercase;color:var(--text2)}
.hero-themes .tps{flex-direction:row;flex-wrap:wrap}
.hero-themes .tp{width:auto}
.block{padding:96px 0 24px;border-bottom:1px solid var(--line)}
.sh{margin-bottom:48px}
.sh h2{font:400 50px/56px var(--px);margin:0 0 18px;text-transform:uppercase}
.subhead{margin:72px 0 22px;max-width:76ch}
.subhead h3{font:400 20px/24px var(--px);text-transform:uppercase;margin:0 0 10px}
.note{color:var(--text2);margin:0}
.fine{color:var(--text2);font-size:13px;line-height:21px}
.ds h4{font:500 15px/22px var(--mono);margin:0 0 8px}
.concept{display:grid;grid-template-columns:auto minmax(0,1fr);gap:56px;align-items:center}
.concept-art{position:relative;padding:24px 200px 24px 24px;border:1px solid var(--line);background:var(--surface)}
.concept-mark{width:256px}
.callout{position:absolute;left:250px;font-size:12px;color:var(--text2);white-space:nowrap;display:flex;align-items:center;gap:8px;letter-spacing:.06em;text-transform:uppercase}
.callout i{display:block;width:32px;height:1px;background:var(--text2)}
.c1{top:34px}.c2{top:148px}
.concept-copy p{margin:0 0 16px;max-width:62ch;color:var(--text2)}
.concept-copy b{color:var(--text);font-weight:500}
.explore{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}
.explore.four{grid-template-columns:repeat(4,minmax(0,1fr))}
.ex{border:1px solid var(--line);background:var(--surface);padding:20px}
.ex.chosen{border-color:var(--accent)}
.ex .pix{color:var(--text2)}
.ex.chosen .pix{color:var(--accent)}
.ex-art{display:flex;align-items:flex-end;justify-content:space-between;gap:12px}
.ex-art>.pix{width:96px}
.explore.four .ex-art>.pix{width:80px}
.ex-1x{display:flex;gap:8px;align-items:flex-end}
.ex .ex-1x .pix{color:var(--text)}
.ex-name{display:flex;gap:10px;align-items:baseline;margin:16px 0 6px;font-weight:500}
.ex-name b{font:400 20px/24px var(--px);color:var(--text2)}
.ex.chosen .ex-name b{color:var(--accent)}
.ex-name span{margin-left:auto;font-size:11px;letter-spacing:.12em;text-transform:uppercase}
.yes{color:var(--accent)}.no{color:var(--bad)}
.ex-v{margin:0;font-size:13px;line-height:20px;color:var(--text2)}
.lockups{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}
.lockups .big{grid-column:1/-1}
.tile{margin:0;border:1px solid var(--line);background:var(--surface);display:flex;flex-direction:column}
.tile .art{flex:1;display:grid;place-items:center;padding:48px 24px;min-height:200px}
.tile.big .art{min-height:280px}
.tile figcaption{padding:12px 16px;border-top:1px solid rgba(127,127,127,.25);font-size:13px;line-height:20px;color:var(--text2)}
.tile.fixed .pix{color:inherit}
.tiles{display:grid;gap:14px}
.tiles.four{grid-template-columns:repeat(4,minmax(0,1fr))}
.tiles.themes{grid-template-columns:repeat(auto-fit,minmax(min(100%%,170px),1fr))}
.tiles .art{min-height:150px;padding:32px 16px}
.plate{margin:0;border:1px solid var(--line);background:#060907}
.plate-link{display:block}
.plate-img{display:block;width:100%%}
.plate figcaption{padding:12px 16px;font-size:13px;color:var(--text2);background:var(--surface);border-top:1px solid var(--line)}
.plates.two{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px;margin-top:40px;align-items:start}
.rules{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%%,210px),1fr));gap:1px;margin-top:28px;background:var(--line);border:1px solid var(--line)}
.rules>div{background:var(--bg);padding:20px}
.rules p{margin:0;font-size:14px;line-height:22px;color:var(--text2)}
.misuse{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}
.misuse li{border:1px solid var(--line);background:var(--surface)}
.misuse .art{height:170px;display:grid;place-items:center;color:var(--accent);overflow:hidden}
.misuse .art .pix{width:auto}
.misuse p{margin:0;padding:12px 16px;border-top:1px solid var(--line);font-size:13px;color:var(--text2)}
.x{color:var(--bad);margin-right:8px;font-weight:700}
.retype{font:700 44px/1 Georgia,"Times New Roman",serif;color:var(--accent);letter-spacing:-.02em}
.lowc{display:grid;place-items:center;width:120px;height:120px;background:color-mix(in srgb,var(--accent) 78%%,var(--bg))}
.lowc .pix{color:color-mix(in srgb,var(--accent) 88%%,#fff)}
.appicon{display:grid;grid-template-columns:auto minmax(0,1fr);gap:48px;align-items:center;border:1px solid var(--line);background:linear-gradient(135deg,#E9E6DA,#C9D8CF);padding:36px}
.appicon-hero img{display:block;width:256px}
.appicon-sizes{list-style:none;margin:0;padding:0;display:flex;flex-wrap:wrap;align-items:flex-end;gap:26px}
.appicon-sizes li{display:flex;flex-direction:column;align-items:center;gap:8px;font-size:12px;color:#38463D}
.appicon-sizes img{display:block}
.menubar-demo{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:14px}
.mbar{display:flex;align-items:center;justify-content:flex-end;gap:10px;height:48px;padding:0 20px;border:1px solid var(--line)}
.mbar .pix{width:32px;color:inherit}
.mbar span{font:400 20px/1 var(--px)}
.mbar.light{background:#ECECEC;color:#141414}.mbar.dark{background:#2A2A2C;color:#F5F5F5}
.states{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:14px}
.states li{border:1px solid var(--line);background:var(--surface);padding:18px}
.states .art .pix{width:64px;color:var(--text)}
.states li:first-child .art .pix{color:var(--accent)}
.mb{display:flex;gap:8px;margin:14px 0 10px}
.mb span{display:grid;place-items:center;width:40px;height:24px}
.mb-l{background:#ECECEC;color:#141414}.mb-d{background:#2A2A2C;color:#F5F5F5}
.mb .pix{color:inherit}
.states p{margin:0;font-size:13px;line-height:19px;color:var(--text2)}
.states p b{display:block;color:var(--text);font-weight:500}
.more{margin-top:28px;border:1px solid var(--line)}
.more>summary{cursor:pointer;padding:12px 16px;font-size:13px;letter-spacing:.06em;color:var(--text2)}
.more[open]>summary{border-bottom:1px solid var(--line)}
.more>.plate{border:0}
.more>.component,.more>.note{padding:0 16px}
.more>.note{padding-top:16px}
.more>.component:last-child{padding-bottom:16px}
.sig{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:14px}
.sig li{border:1px solid var(--line);background:var(--surface);padding-bottom:14px}
.sig .sw{display:block;height:96px;border-bottom:1px solid var(--line)}
.sig b{display:block;padding:12px 14px 0;font-weight:500}
.sig code{display:block;padding:0 14px}
.sig p{margin:6px 14px 0;font-size:12px;line-height:18px;color:var(--text2)}
.themes-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%%,400px),1fr));gap:14px}
.theme{border:1px solid;padding:22px}
.ds .theme h4{font:400 20px/24px var(--px);text-transform:uppercase;margin:0 0 6px}
.theme-head p{margin:0 0 18px;font-size:13px;line-height:20px}
.theme-body{display:grid;grid-template-columns:minmax(0,170px) minmax(0,1fr);gap:18px;align-items:start}
.mini{border:1px solid;padding:14px}
.mini p{margin:0}
.mini-t{font:400 10px/12px var(--px)}
.mini .mini-n{font:400 40px/44px var(--px);margin:8px 0 6px}
.mini-n small{font-size:20px;margin-left:4px}
.mini .mini-bar{height:8px;margin:6px 0 10px}
.mini-bar i{display:block;width:83%%;height:100%%}
.mini-s{font-size:11px;line-height:16px}
.chips{list-style:none;margin:0;padding:0;display:grid;gap:4px}
.chips li{display:grid;grid-template-columns:16px minmax(0,1fr) auto;gap:8px;align-items:center;font-size:12px;line-height:16px}
.chips code{font-size:12px;color:inherit}
.chip{width:16px;height:16px;border:1px solid rgba(127,127,127,.4)}
.hex{font-variant-numeric:tabular-nums}
.theme details{margin-top:16px;font-size:13px}
.theme summary{cursor:pointer}
.theme .table-wrap{border-color:rgba(127,127,127,.35);margin-top:10px}
.ds .ct{font-size:12px}
.ds .ct th,.ds .ct td{padding:6px 8px;border-color:rgba(127,127,127,.3);background:transparent;color:inherit}
.ct td.low{color:var(--bad);font-weight:700}
.faces{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}
.face{border:1px solid var(--line);background:var(--surface);padding:28px}
.face-big{font-size:80px;line-height:96px;margin:0 0 20px;color:var(--accent);white-space:nowrap;overflow:hidden}
.face-big.mono{font-size:72px;font-weight:500}
.ds .face h4{font:400 20px/24px var(--px);text-transform:uppercase}
.face p{color:var(--text2);margin:0 0 16px}
.face dl{display:grid;grid-template-columns:auto minmax(0,1fr);gap:6px 18px;margin:0 0 16px;font-size:13px}
.face dt{color:var(--text2)}.face dd{margin:0}
.tester{border:1px solid var(--line);background:var(--surface);padding:22px}
.tester label{display:block;font:500 12px/16px var(--mono);letter-spacing:.14em;text-transform:uppercase;color:var(--text2);margin-bottom:8px}
.tester input{width:100%%;font:15px/24px var(--mono);color:var(--text);background:var(--bg);border:1px solid var(--line);padding:10px 12px;border-radius:2px}
.t-px{font-size:30px;line-height:40px;margin:22px 0 10px;overflow-wrap:anywhere}
.t-mono{font-size:20px;line-height:30px;margin:0;overflow-wrap:anywhere}
.pairs{border:1px solid var(--line);background:var(--surface);padding:28px}
.pairs p{margin:0;color:var(--accent);overflow-wrap:anywhere}
.pairs .px{font-size:60px;line-height:72px;word-spacing:.2em}
.pairs .mono{font-size:36px;line-height:48px;margin-top:14px}
.table-wrap{overflow-x:auto;border:1px solid var(--line)}
.ds table{border-collapse:collapse;width:100%%;font-size:14px}
.ds th,.ds td{text-align:left;padding:12px 14px;border-bottom:1px solid var(--line);vertical-align:middle}
.ds thead th{font:500 12px/16px var(--mono);letter-spacing:.12em;text-transform:uppercase;color:var(--text2);background:var(--surface)}
.ds tbody th{font-weight:400}
.ds tbody tr:last-child>*{border-bottom:0}
.num{text-align:right;font-variant-numeric:tabular-nums}
.scale th[scope=row]{width:210px}
.scale .use{display:block;font:400 12px/18px var(--mono);color:var(--text2);margin-top:4px}
.scale .spec{width:270px;font-size:13px}
.scale .was{display:block;font-size:12px;color:var(--text2)}
.scale .samp{max-width:0;overflow:hidden}
.tsample{display:block;white-space:nowrap}
.tsample.px{font-family:var(--px)}
.tsample.mono{font-family:var(--mono)}
.glyphs{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:repeat(auto-fill,minmax(112px,1fr));gap:1px;background:var(--line);border:1px solid var(--line)}
.glyphs li{background:var(--surface);display:flex;flex-direction:column;align-items:center;gap:12px;padding:22px 8px 14px}
.glyphs .pix{width:36px;color:var(--text)}
.glyphs span{font-size:12px;line-height:16px;color:var(--text2);text-align:center}
.principles{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%%,210px),1fr));gap:14px}
.principles>div{border:1px solid var(--line);background:var(--surface);padding:20px}
.principles b{display:block;font-weight:500;margin-bottom:8px}
.principles span{font-size:14px;line-height:22px;color:var(--text2)}
.component{margin-top:40px}
.ds .ch{font:400 20px/24px var(--px);text-transform:uppercase;margin:0 0 6px}
.component .note{max-width:76ch;margin-bottom:16px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%%,320px),1fr));gap:14px;align-items:start}
.grid.screens{grid-template-columns:repeat(auto-fill,minmax(min(100%%,300px),1fr))}
.specimen{margin:0;border:1px solid var(--line);background:var(--surface);overflow:hidden}
.specimen.ph{background:#060907}
.specimen img{display:block;width:100%%;height:auto}
.specimen figcaption{display:flex;justify-content:space-between;gap:10px;padding:10px 14px;border-top:1px solid var(--line);font-size:13px;background:var(--surface)}
.specimen figcaption code{flex:none;white-space:nowrap}
:root.ds-light .v-dark,:root:not(.ds-light) .v-light{display:none!important}
td.glyph img{width:30px;height:auto}
.family{font-size:12px;border:1px solid var(--line);padding:1px 8px;color:var(--text2)}
.swatch{display:inline-block;width:14px;height:14px;margin-right:6px;vertical-align:-2px;background:linear-gradient(135deg,var(--l) 50%%,var(--d) 50%%);border:1px solid var(--line)}
.pattern{display:inline-block;width:30px;height:8px;margin-right:8px;vertical-align:1px;border:1px solid var(--text2)}
.p-solid{background:var(--text2)}.p-hatched{background:repeating-linear-gradient(135deg,var(--text2) 0 3px,transparent 3px 6px)}.p-dashed{border-style:dashed}
.muted{color:var(--text2);font-size:13px}
.styles td:nth-child(6),.styles td:nth-child(7){white-space:nowrap}
.styles code{overflow-wrap:normal;white-space:nowrap}
.scales{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}
.scales ul{list-style:none;margin:0;padding:0;border:1px solid var(--line);background:var(--surface)}
.scales li{display:flex;justify-content:space-between;gap:12px;padding:9px 14px;border-bottom:1px solid var(--line);font-size:14px}
.scales li:last-child{border-bottom:0}
.scales li.h{font:500 12px/16px var(--mono);letter-spacing:.12em;text-transform:uppercase;color:var(--text2);padding:12px 14px}
.tones{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}
.tones>div{border:1px solid var(--line);background:var(--surface);padding:20px}
.tones p{margin:0;font-size:14px;line-height:22px;color:var(--text2)}
.tones .q{font-weight:500;color:var(--ok);margin-bottom:10px}
.tones .q.warn{color:var(--warn)}.tones .q.bad{color:var(--bad)}.tones .q.stale{color:var(--stale)}
.voice td{font-size:14px;line-height:22px}
.voice .do{color:var(--text);font-weight:500}
.voice .do::before{content:"✓ ";color:var(--ok)}
.voice .dont{color:var(--text2);text-decoration:line-through;text-decoration-color:var(--bad)}
.kits{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}
.ds .kit{display:flex;flex-direction:column;height:100%%;gap:10px;border:1px solid var(--line);background:var(--surface);padding:22px;color:var(--text);text-decoration:none}
.ds .kit:hover{border-color:var(--accent)}
.kit b{font:400 20px/24px var(--px);text-transform:uppercase}
.kit span{font-size:13px;line-height:20px;color:var(--text2);flex:1}
.kit em{font-style:normal;font-size:12px;letter-spacing:.12em;color:var(--accent)}
.files{list-style:none;margin:28px 0 0;padding:0;columns:2;column-gap:40px}
.files li{display:flex;justify-content:space-between;gap:16px;padding:10px 0;border-bottom:1px solid var(--line);break-inside:avoid;font-size:14px}
.files span{color:var(--text2);font-size:13px;white-space:nowrap}
.ds-foot{grid-column:2;padding:32px 0 96px;color:var(--text2);font-size:13px;line-height:21px}
.ds-foot p{max-width:90ch;margin:0 0 10px}
@media (max-width:1180px){.explore,.explore.four{grid-template-columns:repeat(2,minmax(0,1fr))}
  .sig{grid-template-columns:repeat(3,minmax(0,1fr))}.kits{grid-template-columns:repeat(2,minmax(0,1fr))}.tones{grid-template-columns:repeat(2,minmax(0,1fr))}
  .states{grid-template-columns:repeat(3,minmax(0,1fr))}.tiles.four{grid-template-columns:repeat(2,minmax(0,1fr))}.misuse{grid-template-columns:repeat(2,minmax(0,1fr))}
  .concept{grid-template-columns:1fr;gap:32px}.concept-art{justify-self:start}}
@media (max-width:900px){
  .ds{display:block;padding:0 16px}
  .ds-side{position:sticky;top:var(--head);z-index:20;padding:0;margin:0 -16px;background:var(--bg);border-bottom:1px solid var(--line)}
  .ds-side p,.ds-side .tps{display:none}
  .ds-side ol{display:flex;gap:6px;margin:0;padding:8px 16px;border:0;overflow-x:auto;scrollbar-width:none}
  .ds-side ol::-webkit-scrollbar{display:none}
  .ds-side li a{border:1px solid var(--line);padding:6px 10px;margin:0;white-space:nowrap;font-size:13px}
  .ds-side li a.on{border-color:var(--accent)}
  .ds-side li a span{display:none}
  .faces,.plates.two,.menubar-demo{grid-template-columns:1fr}
  .appicon{grid-template-columns:1fr;padding:24px}
  .scales{grid-template-columns:1fr}
  .files{columns:1}
  .theme-body{grid-template-columns:1fr}
}
@media (max-width:600px){
  .hero{padding:44px 0 44px}
  .hero .pix{width:270px}
  .hero h1,.sh h2{font-size:30px;line-height:36px}
  .facts{grid-template-columns:repeat(2,minmax(0,1fr))}
  .facts b{font-size:20px;line-height:24px}
  .block{padding:72px 0 16px}
  .subhead{margin-top:56px}
  .explore,.explore.four,.lockups,.tiles.four,.misuse,.kits,.tones{grid-template-columns:1fr}
  .sig,.states{grid-template-columns:repeat(2,minmax(0,1fr))}
  .lockups .big .pix{width:270px}
  .concept-art{padding:20px}
  .concept-mark{width:192px}
  .callout{position:static;margin-top:10px}
  .callout i{width:20px}
  .face{padding:22px}
  .face-big{font-size:50px;line-height:60px}.face-big.mono{font-size:44px;line-height:56px}
  .pairs{padding:20px}
  .pairs .px{font-size:30px;line-height:40px}.pairs .mono{font-size:20px;line-height:30px}
  .t-px{font-size:20px;line-height:28px}
  .appicon-hero img{width:192px}
  .scale thead,.voice thead{display:none}
  .scale tr,.voice tr{display:block;padding:14px 16px;border-bottom:1px solid var(--line)}
  .scale tbody tr:last-child,.voice tbody tr:last-child{border-bottom:0}
  .ds .scale th,.ds .scale td,.ds .voice td{display:block;width:auto;padding:0;border:0}
  .scale .samp{max-width:none;margin:10px 0 8px}
  .scale .tsample{white-space:normal;overflow-wrap:anywhere}
  .voice .do{margin-bottom:4px}.voice .dont{margin-bottom:8px}
  .ds-foot{padding-bottom:72px}
}
"""

hero = f"""<section class="hero" aria-labelledby="ds-title">
  <p class="eyebrow"><b>Clepso</b> · Brand and design system · v1.0</p>
  {mark("horizontal", 8, "Clepso")}
  <h1 id="ds-title">The limit, and <em>the live signal.</em></h1>
  <p class="lede">The identity, type, colour, icons, components and voice of Clepso, the menu bar monitor for AI coding-agent limits. Every logo, glyph and colour on this page is generated from the same source the app and the downloads are built from.</p>
  <ul class="facts">{''.join(f'<li><b>{e(a)}</b><span>{e(b)}</span></li>' for a, b in facts)}</ul>
  <div class="hero-themes"><p>Preview the page in a theme</p><div class="tps">{theme_buttons}</div></div>
</section>"""

page = f"""<!doctype html>
<html lang="en" data-ds-theme="{DEFAULT}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Brand and design system · Clepso docs</title>
<meta name="description" content="The Clepso identity and design system: logo and construction, colour across themes, the Clepso Pixel and Clepso Mono typefaces, pixel icons, components, voice and downloads.">
<meta name="theme-color" content="#060907">
<link rel="preload" href="brand/fonts/ClepsoPixel-Regular.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="brand/fonts/ClepsoMono-Regular.woff2" as="font" type="font/woff2" crossorigin>
<script>(function(){{try{{var t=localStorage.getItem("pulse-ds-theme"),m={theme_meta};if(t&&m.hasOwnProperty(t)){{document.documentElement.setAttribute("data-ds-theme",t);if(m[t])document.documentElement.classList.add("ds-light")}}}}catch(e){{}}}})()</script>
<style>{CSS % {"default": default_vars, "themes": theme_css}}</style>
</head>
<body>
<div class="ds">
<aside class="ds-side" aria-label="Design system sections">
  <p>On this page</p>
  <ol>{nav}</ol>
  <p>Theme</p>
  <div class="tps">{theme_buttons}</div>
</aside>
<main id="main" class="ds-main">
{hero}
{logo_section()}
{colour_section()}
{type_section()}
{icons_section()}
{components_section()}
{voice_section()}
{downloads_section()}
</main>
<footer class="ds-foot">
<p>Generated by <code>scripts/build-design-site.py</code> from the brand kit (<code>design/brand</code>), the Swift themes and icon set, and the component renderer <code>pulse-design-render</code> (rendered {e(design["generatedAt"][:10])}). Raw data: <a href="design.json">design.json</a>.</p>
<p>Structure and rigour informed by the NASA Graphics Standards Manual (1975), IBM's design language and Plex, Uber's brand site, GitHub's Mona Sans release, Atlassian's logo guidance, Mailchimp's content style guide, Apple's Human Interface Guidelines and Material Design colour roles. Notes: <code>design/brand/NOTES.md</code>.</p>
</footer>
</div>
<script>
(function () {{
  var root = document.documentElement, meta = {theme_meta}, key = "pulse-ds-theme";
  function apply(id, save) {{
    if (!meta.hasOwnProperty(id)) return;
    root.setAttribute("data-ds-theme", id);
    root.classList.toggle("ds-light", !!meta[id]);
    document.querySelectorAll(".tp:not(.inline)").forEach(function (b) {{
      b.setAttribute("aria-pressed", String(b.getAttribute("data-ds-theme-pick") === id)); }});
    if (save) {{ try {{ localStorage.setItem(key, id); }} catch (e) {{}} }}
  }}
  apply(root.getAttribute("data-ds-theme"), false);
  document.querySelectorAll("[data-ds-theme-pick]").forEach(function (b) {{
    b.addEventListener("click", function () {{ apply(b.getAttribute("data-ds-theme-pick"), true); }}); }});
  var input = document.getElementById("tester-input");
  if (input) input.addEventListener("input", function () {{
    document.querySelectorAll("[data-tester]").forEach(function (p) {{ p.textContent = input.value || " "; }}); }});
  var links = [].slice.call(document.querySelectorAll(".ds-side ol a"));
  var heads = links.map(function (a) {{ return document.getElementById(a.hash.slice(1)); }});
  var ticking = false;
  function spy() {{
    ticking = false;
    var y = window.scrollY + window.innerHeight * 0.3, cur = -1;
    heads.forEach(function (h, i) {{ if (h && h.getBoundingClientRect().top + window.scrollY <= y) cur = i; }});
    links.forEach(function (a, i) {{ a.classList.toggle("on", i === cur); if (i === cur) a.setAttribute("aria-current", "true"); else a.removeAttribute("aria-current"); }});
    var on = links[cur];
    if (on && window.matchMedia("(max-width: 900px)").matches) {{
      var strip = on.closest("ol"), l = on.offsetLeft - 16;
      if (l < strip.scrollLeft || l + on.offsetWidth > strip.scrollLeft + strip.clientWidth) strip.scrollTo({{ left: l, behavior: "auto" }});
    }}
  }}
  window.addEventListener("scroll", function () {{ if (!ticking) {{ ticking = true; requestAnimationFrame(spy); }} }}, {{ passive: true }});
  spy();
}})();
</script>
</body>
</html>
"""
(staging / "index.html").write_text(page)
if out.exists():
    shutil.rmtree(out)
staging.rename(out)

if not (site / "index.html").exists():
    (site / "index.html").write_text("""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Clepso</title><meta http-equiv="refresh" content="0; url=/design-system/">
<style>:root{color-scheme:light dark}body{font:16px -apple-system,system-ui,sans-serif;margin:0;padding:48px 16px;background:Canvas;color:CanvasText}</style>
</head><body><p>Clepso. <a href="/design-system/">Design system</a></p></body></html>
""")
(site / "vercel.json").write_text(json.dumps({"trailingSlash": True}, indent=2) + "\n")
n_files = sum(1 for p in out.rglob("*") if p.is_file())
print(f"wrote {out / 'index.html'} ({len(page) // 1024} KB), {n_files} files, {len(THEMES)} theme appearances, {len(GLYPHS)} icons")
