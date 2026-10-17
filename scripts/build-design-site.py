"""Builds the design-system page from the renderer's output (increment 1.3).

Input: a folder written by `pulse-design-render` (design.json + img/). Output: <site>/design-system/ with
index.html, design.json and img/, plus <site>/index.html and <site>/vercel.json. Everything on the page
comes from the Swift code: rendered component images, exported tokens and computed contrast ratios.
Usage: python3 -I scripts/build-design-site.py <render dir> <site dir> [screens dir]
The optional screens dir holds screenshots of the running app (demo data) captured by the debug probe.
"""
import html
import json
import shutil
import sys
from pathlib import Path

render, site = Path(sys.argv[1]), Path(sys.argv[2])
screens_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else None
design = json.loads((render / "design.json").read_text())
out = site / "design-system"
if out.exists():
    shutil.rmtree(out)
out.mkdir(parents=True)
shutil.copytree(render / "img", out / "img")
if screens_dir:
    shutil.copytree(screens_dir, out / "img" / "screens")
shutil.copy(render / "design.json", out / "design.json")
e = html.escape

COMPONENT_NOTES = {
    "ProviderCard": "One provider: identity, plan, one row per allowance pool, the active session. Compact in the menu bar popover, expanded in provider detail.",
    "QuotaProgress": "One allowance pool. Takes a provenance-carrying value, never a bare number, so missing data cannot render as 0%. Every state has its own symbol, words and bar pattern as well as colour.",
    "ResetCountdown": "Counts down from a verified reset instant. At the reset time it says “Reset expected”, never “Ready”: only a fresh reading can say that.",
    "PlanPill": "The plan label always carries how it is known. The plan never feeds any arithmetic.",
    "ConnectionHealth": "Whether readings are arriving, with the age of the last one. Never “100% connected”.",
    "DataSourceLabel": "Source and freshness, on every value. Freshness is never omitted; stale values say “last seen”.",
}
ORDER = ["ProviderCard", "QuotaProgress", "ResetCountdown", "PlanPill", "ConnectionHealth", "DataSourceLabel"]


def pair(light, dark, alt, cls=""):
    return (f'<img class="v-light {cls}" src="{e(light)}" alt="{e(alt)} (light)" loading="lazy">'
            f'<img class="v-dark {cls}" src="{e(dark)}" alt="{e(alt)} (dark)" loading="lazy">')


sections = []
for component in ORDER:
    rows = [s for s in design["specimens"] if s["component"] == component]
    cards = "".join(
        f'<figure class="specimen">{pair(s["light"], s["dark"], component + ": " + s["caption"])}'
        f'<figcaption><span>{e(s["caption"])}</span><code>{e(s["id"])}</code></figcaption></figure>' for s in rows)
    sections.append(f'<section class="component" id="{component.lower()}"><h3>{component}</h3>'
                    f'<p class="note">{e(COMPONENT_NOTES[component])}</p><div class="grid">{cards}</div></section>')

style_rows = "".join(
    f'<tr><td><span class="family">{e(r["family"])}</span></td><td><code>{e(r["state"])}</code></td>'
    f'<td class="glyph">{pair(r["glyph"] + "-light.png", r["glyph"] + "-dark.png", r["symbol"])}</td>'
    f'<td>{e(r["label"])}</td><td class="muted">“{e(r["accessibility"])}”</td>'
    f'<td><span class="swatch" style="--l:{next(p["light"] for p in design["palette"] if p["token"] == r["role"])};'
    f'--d:{next(p["dark"] for p in design["palette"] if p["token"] == r["role"])}"></span><code>{e(r["role"])}</code></td>'
    f'<td><span class="pattern p-{e(r["pattern"])}"></span>{e(r["pattern"])}</td></tr>'
    for r in design["styles"])

palette = "".join(
    f'<div class="token"><div class="chips"><span style="background:{p["light"]}"></span><span style="background:{p["dark"]}"></span></div>'
    f'<div><code>{e(p["token"])}</code><div class="muted">{p["light"]} · {p["dark"]}{" · text" if p["isText"] else ""}</div></div></div>'
    for p in design["palette"])

surfaces = ["background", "surfaceElevated", "surfaceMuted"]
contrast_tables = []
worst = min(design["contrast"], key=lambda c: c["ratio"])
for scheme in ("light", "dark"):
    texts = []
    for c in design["contrast"]:
        if c["scheme"] == scheme and c["text"] not in texts:
            texts.append(c["text"])
    body = ""
    for t in texts:
        cells = ""
        for s in surfaces:
            c = next(c for c in design["contrast"] if c["scheme"] == scheme and c["text"] == t and c["surface"] == s)
            flag = " worst" if c is worst else ""
            cells += f'<td class="ratio{flag}">{c["ratio"]:.2f}<span class="{"ok" if c["passesAA"] else "fail"}">{"AA" if c["passesAA"] else "fail"}</span></td>'
        body += f"<tr><td><code>{e(t)}</code></td>{cells}</tr>"
    head = "".join(f"<th>{s}</th>" for s in surfaces)
    contrast_tables.append(f'<div><h4>{scheme.capitalize()}</h4><table class="contrast"><thead><tr><th>Text token</th>{head}</tr></thead><tbody>{body}</tbody></table></div>')

def token_list(key, unit):
    return "".join(f'<li><code>{e(t["token"])}</code><span>{t["points"]:g} {unit}</span></li>' for t in design[key])

typography = "".join(f'<li><code>{e(t["token"])}</code><span>{e(t["style"])}</span></li>' for t in design["typography"])

# Increment 1.7: the Phosphor pixel layer (the app's current look) and screenshots of the running app.
ph = design["phosphor"]
PH_NOTES = {
    "PixelLimitRow": "One allowance pool in the pixel style. Same status words, freshness, reset line and VoiceOver sentence as QuotaProgress (tested); the optional pace line always says “Estimate”.",
    "PixelBar": "The segmented bar. Stale values are dithered and missing values draw only an outline, so meaning never rests on colour.",
    "PixelButtonStyle": "Bevelled pixel buttons: a lit top edge and a shaded bottom edge that swap when pressed.",
    "PixelTabs": "Tabs in the pixel-pack manner, used in the Details window and Stats.",
    "PixelStat": "A value over a small pixel caption, for the session strip and Stats.",
    "PixelLineChart": "History drawn as steps snapped to a pixel grid, with dotted 80/95/100 guides, NOW, and the dashed pace projection. VoiceOver reads a sentence instead of the drawing.",
    "PixelHeatmap": "Activity like Claude Code's /stats: one column per week, Monday on top, four levels plus empty.",
    "PixelPanel": "The frame every pixel screen sits in: stepped corners, an outer frame and an inner rule; glass behind it in the app.",
    "Typography": "Silkscreen for figures and labels (its 5 and S differ clearly), a monospaced system face for sentences so they stay readable.",
}
ph_order = list(dict.fromkeys(s["component"] for s in ph["specimens"]))
ph_sections = []
for component in ph_order:
    cards = "".join(
        f'<figure class="specimen ph"><img src="{e(s["image"])}" alt="{e(component + ": " + s["caption"])}" loading="lazy">'
        f'<figcaption><span>{e(s["caption"])}</span><code>{e(s["id"])}</code></figcaption></figure>'
        for s in ph["specimens"] if s["component"] == component)
    ph_sections.append(f'<section class="component" id="ph-{component.lower()}"><h3>{component}</h3>'
                       f'<p class="note">{e(PH_NOTES.get(component, ""))}</p><div class="grid">{cards}</div></section>')
ph_palette = "".join(
    f'<div class="token"><div class="chips"><span style="background:{p["hex"]}"></span></div>'
    f'<div><code>{e(p["token"])}</code><div class="muted">{p["hex"]}{" · text" if p["isText"] else ""}</div></div></div>'
    for p in ph["palette"])
ph_worst = min(ph["contrast"], key=lambda c: c["ratio"])
ph_rows = ""
for t in dict.fromkeys(c["text"] for c in ph["contrast"]):
    cells = ""
    for s in surfaces:
        c = next(c for c in ph["contrast"] if c["text"] == t and c["surface"] == s)
        cells += (f'<td class="ratio{" worst" if c is ph_worst else ""}">{c["ratio"]:.2f}'
                  f'<span class="{"ok" if c["passesAA"] else "fail"}">{"AA" if c["passesAA"] else "fail"}</span></td>')
    ph_rows += f"<tr><td><code>{e(t)}</code></td>{cells}</tr>"
ph_contrast = (f'<table class="contrast"><thead><tr><th>Text token</th>{"".join(f"<th>{s}</th>" for s in surfaces)}</tr></thead>'
               f'<tbody>{ph_rows}</tbody></table>')
ph_passed = sum(c["passesAA"] for c in ph["contrast"])
ph_fonts = "".join(f'<li><code>{e(f["family"])}</code><span>{e(f["use"])} · {e(f["licence"])}</span></li>' for f in ph["fonts"])
SCREENS = [("popover-overview", "Menu bar popover"), ("popover-detail", "Provider detail"), ("popover-inspector", "Where this number comes from"),
           ("details-limits", "Details · Limits: history and pace"), ("details-session", "Details · Session"),
           ("details-stats-overview", "Details · Stats overview"), ("details-stats-models", "Details · Stats models"),
           ("onboarding-3-consent", "Onboarding · consent"), ("settings-diagnostics", "Settings · Diagnostics"),
           ("settings-delete-all-sheet", "Delete all, confirmation")]
screens = ""
if screens_dir:
    screens = "".join(f'<figure class="specimen ph"><img src="img/screens/{n}.png" alt="{e(c)}" loading="lazy"><figcaption><span>{e(c)}</span></figcaption></figure>'
                      for n, c in SCREENS if (screens_dir / f"{n}.png").exists())
passed = sum(c["passesAA"] for c in design["contrast"])

page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tokone Design System</title>
<meta name="description" content="Tokens, status styles and SwiftUI components of the Tokone AI capacity monitor, rendered from the real code.">
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><circle cx='16' cy='16' r='12' fill='none' stroke='%231D4FD7' stroke-width='4'/></svg>">
<style>
:root {{ --bg:#F2F2F7; --surface:#FFFFFF; --muted:#E5E5EA; --line:#C7C7CC; --text:#1C1C1E; --text2:#5A5A64; --accent:#1D4FD7;
  --ok:#15703B; --bad:#B42318; --attn:#8A4F00; color-scheme: light; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg:#1C1C1E; --surface:#2C2C2E; --muted:#3A3A3C; --line:#48484A;
  --text:#F5F5F7; --text2:#B0B0BA; --accent:#7FA8FF; --ok:#4CD47A; --bad:#FF8A7E; --attn:#F2B544; color-scheme: dark; }} }}
:root[data-theme="dark"] {{ --bg:#1C1C1E; --surface:#2C2C2E; --muted:#3A3A3C; --line:#48484A; --text:#F5F5F7; --text2:#B0B0BA;
  --accent:#7FA8FF; --ok:#4CD47A; --bad:#FF8A7E; --attn:#F2B544; color-scheme: dark; }}
* {{ box-sizing: border-box; }}
html, body {{ margin: 0; background: var(--bg); color: var(--text); }}
body {{ font: 15px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; -webkit-font-smoothing: antialiased; }}
code {{ font: 12.5px/1.4 ui-monospace, "SF Mono", Menlo, monospace; color: var(--text2); }}
a {{ color: var(--accent); }}
.wrap {{ max-width: 1180px; margin: 0 auto; padding: 0 16px; }}
header {{ padding: 56px 0 28px; border-bottom: 1px solid var(--line); }}
.eyebrow {{ font-size: 12px; letter-spacing: .12em; text-transform: uppercase; color: var(--text2); font-weight: 600; }}
h1 {{ font-size: clamp(30px, 5vw, 46px); line-height: 1.08; margin: 10px 0 14px; letter-spacing: -.02em; }}
h2 {{ font-size: 24px; margin: 0 0 6px; letter-spacing: -.01em; }}
h3 {{ font-size: 18px; margin: 0 0 4px; }}
h4 {{ margin: 0 0 10px; font-size: 14px; color: var(--text2); }}
.lede {{ max-width: 760px; color: var(--text2); font-size: 17px; margin: 0; }}
.meta {{ display: flex; flex-wrap: wrap; gap: 8px; margin-top: 22px; }}
.tag {{ border: 1px solid var(--line); background: var(--surface); border-radius: 999px; padding: 4px 11px; font-size: 13px; color: var(--text2); }}
.tag strong {{ color: var(--text); font-weight: 600; }}
.tag.demo {{ border-color: var(--accent); color: var(--accent); font-weight: 600; }}
nav {{ position: sticky; top: 0; z-index: 5; background: color-mix(in srgb, var(--bg) 88%, transparent); backdrop-filter: blur(12px);
  border-bottom: 1px solid var(--line); }}
nav .wrap {{ display: flex; align-items: center; gap: 18px; overflow-x: auto; height: 48px; white-space: nowrap; }}
nav a {{ color: var(--text2); text-decoration: none; font-size: 14px; }}
nav a:hover {{ color: var(--text); }}
nav button {{ margin-left: auto; font: inherit; font-size: 13px; color: var(--text); background: var(--surface); border: 1px solid var(--line);
  border-radius: 999px; padding: 4px 12px; cursor: pointer; }}
section.block {{ padding: 44px 0; border-bottom: 1px solid var(--line); }}
.section-head {{ max-width: 760px; margin-bottom: 22px; }}
.section-head p, .note {{ color: var(--text2); margin: 0; }}
.principles {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 14px; }}
.principle {{ background: var(--surface); border: 1px solid var(--line); border-radius: 12px; padding: 18px; }}
.principle b {{ display: block; margin-bottom: 6px; }}
.principle span {{ color: var(--text2); font-size: 14px; }}
.component {{ margin-top: 34px; }}
.component .note {{ max-width: 760px; margin-bottom: 14px; }}
.grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 340px), 1fr)); gap: 16px; align-items: start; }}
.specimen {{ margin: 0; background: var(--surface); border: 1px solid var(--line); border-radius: 12px; overflow: hidden; }}
.specimen img {{ display: block; width: 100%; height: auto; }}
.specimen.ph {{ background: #060907; }}
.screens {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 300px), 1fr)); gap: 16px; align-items: start; }}
figcaption {{ display: flex; justify-content: space-between; gap: 10px; padding: 10px 14px; border-top: 1px solid var(--line); font-size: 13px; }}
.v-dark {{ display: none !important; }}
:root[data-theme="dark"] .v-light {{ display: none !important; }}
:root[data-theme="dark"] .v-dark {{ display: block !important; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) .v-light {{ display: none !important; }}
  :root:not([data-theme="light"]) .v-dark {{ display: block !important; }} }}
.table-wrap {{ overflow-x: auto; background: var(--surface); border: 1px solid var(--line); border-radius: 12px; }}
table {{ border-collapse: collapse; width: 100%; font-size: 14px; }}
th, td {{ text-align: left; padding: 9px 12px; border-bottom: 1px solid var(--line); vertical-align: middle; }}
th {{ font-size: 12px; text-transform: uppercase; letter-spacing: .06em; color: var(--text2); font-weight: 600; }}
tr:last-child td {{ border-bottom: 0; }}
td.glyph img {{ width: 30px; height: auto; }}
td:nth-child(6), td:nth-child(7) {{ white-space: nowrap; }}
.muted {{ color: var(--text2); font-size: 13px; }}
.family {{ font-size: 12px; border: 1px solid var(--line); border-radius: 999px; padding: 1px 8px; color: var(--text2); }}
.swatch {{ display: inline-block; width: 14px; height: 14px; border-radius: 4px; margin-right: 6px; vertical-align: -2px;
  background: linear-gradient(135deg, var(--l) 50%, var(--d) 50%); border: 1px solid var(--line); }}
.pattern {{ display: inline-block; width: 30px; height: 8px; border-radius: 999px; margin-right: 8px; vertical-align: 1px; border: 1px solid var(--text2); }}
.p-solid {{ background: var(--text2); }}
.p-hatched {{ background: repeating-linear-gradient(135deg, var(--text2) 0 3px, transparent 3px 6px); }}
.p-outline {{ background: transparent; }}
.p-dashed {{ background: transparent; border-style: dashed; }}
.tokens {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 260px), 1fr)); gap: 12px; }}
.token {{ display: flex; gap: 12px; align-items: center; background: var(--surface); border: 1px solid var(--line); border-radius: 12px; padding: 12px; }}
.chips {{ display: flex; flex: none; border-radius: 8px; overflow: hidden; border: 1px solid var(--line); }}
.chips span {{ width: 26px; height: 40px; }}
.contrast-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 480px), 1fr)); gap: 18px; }}
.contrast {{ background: var(--surface); border: 1px solid var(--line); border-radius: 12px; overflow: hidden; }}
td.ratio {{ font-variant-numeric: tabular-nums; }}
td.ratio span {{ margin-left: 8px; font-size: 11px; font-weight: 700; border-radius: 4px; padding: 1px 5px; }}
.ok {{ color: var(--ok); border: 1px solid currentColor; }}
.fail {{ color: var(--bad); border: 1px solid currentColor; }}
td.worst {{ outline: 2px solid var(--attn); outline-offset: -3px; }}
.scales {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 260px), 1fr)); gap: 14px; }}
.scales ul {{ list-style: none; margin: 0; padding: 0; background: var(--surface); border: 1px solid var(--line); border-radius: 12px; }}
.scales li {{ display: flex; justify-content: space-between; gap: 12px; padding: 9px 14px; border-bottom: 1px solid var(--line); font-size: 14px; }}
.scales li:last-child {{ border-bottom: 0; }}
footer {{ padding: 36px 0 60px; color: var(--text2); font-size: 13px; }}
@media (max-width: 640px) {{ header {{ padding-top: 36px; }} figcaption {{ flex-direction: column; }} }}
</style>
</head>
<body>
<header><div class="wrap">
  <div class="eyebrow">Tokone · AI capacity monitor</div>
  <h1>Design system</h1>
  <p class="lede">The tokens, status styles and SwiftUI components behind the menu bar app. The app's current look is <b>Phosphor</b>:
  dark glass, phosphor green and pixel elements (founder decision, 17 Oct 2026). Every image below is the real component or the running app,
  rendered from the Swift code; the classic system theme that preceded it is kept further down.</p>
  <div class="meta">
    <span class="tag demo">All values are demo data</span>
    <span class="tag"><strong>{len(ph["specimens"])}</strong> Phosphor specimens</span>
    <span class="tag"><strong>{ph_passed}/{len(ph["contrast"])}</strong> Phosphor contrast checks pass AA</span>
    <span class="tag"><strong>{len(design["specimens"])}</strong> classic component states</span>
    <span class="tag"><strong>{passed}/{len(design["contrast"])}</strong> text contrast checks pass WCAG AA</span>
    <span class="tag">Worst contrast <strong>{worst["ratio"]:.2f}:1</strong></span>
    <span class="tag">Rendered {e(design["generatedAt"][:10])}</span>
  </div>
</div></header>
<nav><div class="wrap">
  <a href="#screens">Screens</a><a href="#phosphor">Phosphor</a><a href="#principles">Principles</a><a href="#components">Classic components</a><a href="#states">Status styles</a>
  <a href="#color">Colour</a><a href="#contrast">Contrast</a><a href="#scales">Type and spacing</a>
  <button type="button" id="theme" aria-label="Switch light or dark">Light / dark</button>
</div></nav>
<main class="wrap">
<section class="block" id="screens">
  <div class="section-head"><h2>Screens</h2><p>The running app in demo data, captured by the debug probe from the signed bundle: the popover, the Details window, onboarding and Settings.</p></div>
  <div class="screens">{screens}</div>
</section>
<section class="block" id="phosphor">
  <div class="section-head"><h2>Phosphor</h2><p>The pixel layer (increment 1.7). Inspired by the Matrix, the Tesla Roadster's interface, Hearth's glass and a pixel UI pack used only as a style reference; every shape is drawn in code on a pixel grid, so it stays sharp and scales with text size. Dark in both appearances.</p></div>
  {''.join(ph_sections)}
  <section class="component"><h3>Phosphor colour</h3><p class="note">One value per token: the look is dark in both appearances.</p><div class="tokens">{ph_palette}</div></section>
  <section class="component"><h3>Phosphor contrast</h3><p class="note">Every text token on every surface, from the values the app uses; the outlined cell is the worst case ({ph_worst["ratio"]:.2f}:1).</p>{ph_contrast}</section>
  <section class="component"><h3>Fonts</h3><p class="note">Bundled under the SIL Open Font License 1.1, pinned to a Google Fonts commit with checksums (Resources/Fonts/README.md).</p><div class="scales"><ul>{ph_fonts}</ul></div></section>
</section>
<section class="block" id="principles">
  <div class="section-head"><h2>Principles</h2><p>What every component has to guarantee, whatever it looks like.</p></div>
  <div class="principles">
    <div class="principle"><b>A number always says where it came from</b><span>Every value shows its source and how old it is. Components take provenance-carrying values; there is no bare-number input.</span></div>
    <div class="principle"><b>Missing is never zero</b><span>Absent, null, stale and not connected are four different states with their own words. None of them can render as 0%.</span></div>
    <div class="principle"><b>Never colour alone</b><span>Each state has a symbol, words, a bar pattern and a spoken phrase. Greyscale and VoiceOver users get the same meaning.</span></div>
    <div class="principle"><b>Restyle without changing meaning</b><span>Palette, spacing and layouts can change freely. State names, labels and accessibility text are locked and tested.</span></div>
  </div>
</section>
<section class="block" id="components">
  <div class="section-head"><h2>Classic components</h2><p>The first six components (PRD §25.2) in the classic system theme, each in every state the engine can produce. Still in the code; the pixel components reuse their wording and accessibility text.</p></div>
  {''.join(sections)}
</section>
<section class="block" id="states">
  <div class="section-head"><h2>Status styles</h2><p>The single lookup from a state to how it looks and reads. Within each family no two states share a shape, so recolouring can never merge two meanings (tested).</p></div>
  <div class="table-wrap"><table><thead><tr><th>Family</th><th>State</th><th>Glyph</th><th>Label</th><th>VoiceOver</th><th>Colour role</th><th>Pattern</th></tr></thead>
  <tbody>{style_rows}</tbody></table></div>
</section>
<section class="block" id="color">
  <div class="section-head"><h2>Colour tokens</h2><p>Semantic names, never raw colours, in light and dark. Components ask for a role; only the theme knows the hex value.</p></div>
  <div class="tokens">{palette}</div>
</section>
<section class="block" id="contrast">
  <div class="section-head"><h2>Contrast</h2><p>Every text token on every surface, computed with the WCAG 2 formula from the same values the app uses. AA for body text is 4.5:1. The outlined cell is the worst case.</p></div>
  <div class="contrast-grid">{''.join(contrast_tables)}</div>
</section>
<section class="block" id="scales">
  <div class="section-head"><h2>Type and spacing</h2><p>Type tokens map to Dynamic Type styles, so all text scales with the user's setting. Numbers use tabular digits.</p></div>
  <div class="scales">
    <div><h4>Typography</h4><ul>{typography}</ul></div>
    <div><h4>Spacing</h4><ul>{token_list("spacing", "pt")}</ul></div>
    <div><h4>Radius</h4><ul>{token_list("radius", "pt")}</ul></div>
    <div><h4>Stroke</h4><ul>{token_list("stroke", "pt")}</ul></div>
  </div>
</section>
</main>
<footer><div class="wrap">Generated from the Swift package by <code>pulse-design-render</code> and <code>scripts/build-design-site.py</code>.
Raw data: <a href="design.json">design.json</a>. Product name is a placeholder.</div></footer>
<script>
(function () {{
  var root = document.documentElement, key = "tokone-design-theme";
  try {{ var saved = localStorage.getItem(key); if (saved) root.setAttribute("data-theme", saved); }} catch (e) {{}}
  document.getElementById("theme").addEventListener("click", function () {{
    var dark = root.getAttribute("data-theme") ? root.getAttribute("data-theme") === "dark"
                                               : window.matchMedia("(prefers-color-scheme: dark)").matches;
    var next = dark ? "light" : "dark";
    root.setAttribute("data-theme", next);
    try {{ localStorage.setItem(key, next); }} catch (e) {{}}
  }});
}})();
</script>
</body>
</html>
"""
(out / "index.html").write_text(page)

(site / "index.html").write_text("""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tokone</title><meta http-equiv="refresh" content="0; url=/design-system/">
<style>:root{color-scheme:light dark}body{font:16px -apple-system,system-ui,sans-serif;margin:0;padding:48px 16px;background:Canvas;color:CanvasText}</style>
</head><body><p>Tokone. <a href="/design-system/">Design system</a></p></body></html>
""")
(site / "vercel.json").write_text(json.dumps({"trailingSlash": True}, indent=2) + "\n")
print(f"wrote {out / 'index.html'} ({len(page) // 1024} KB), {len(list((out / 'img').iterdir()))} images")
