"""Builds the Clepso documentation website around the design-system page.

Pages: Overview, Progress, Metrics, Architecture, Privacy, Screens, Changelog, the Design system (built by
build-design-site.py, which runs first; this script adds the site's header, menu and search to it) and the web
dashboard at /app (scripts/site/app.js; its accounts project goes into the uncommitted site/app/config.js).
Content comes from the repository: ROADMAP.md tables for progress, ARCHITECTURE.md's data-flow diagram, git history, the gate list in
scripts/ci.sh, the app screenshots in design/screens, Swift source excerpts beside the interactive rules, and the metric
rules below, which mirror the Swift code they describe (each names its source file).

Styles and behaviour live in scripts/site/.

Curated for a public URL: no decision log, security internals, backend or compliance
plans, results logs or commit bodies.

Usage: python3 -I scripts/build-site.py <site dir> <docs dir> <screens dir>
"""
import html
import json
import os
import re
import runpy
import shutil
import subprocess
import sys
import textwrap
from datetime import date
from pathlib import Path

site, docs, screens = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
repo = Path(__file__).resolve().parent.parent
assets_src = repo / "scripts" / "site"
e = html.escape


def git(*args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=True).stdout.strip()


COMMIT, COMMIT_DATE = git("log", "-1", "--pretty=%h"), git("log", "-1", "--pretty=%ad", "--date=short")
# The latest public build; bump with each release (docs/RELEASE.md).
RELEASE_TAG = "v0.4.0-alpha.2"
RELEASE_URL = f"https://github.com/obileonardo/clepso/releases/tag/{RELEASE_TAG}"

NAV = [("", "Overview"), ("progress/", "Progress"), ("metrics/", "Metrics"), ("architecture/", "Architecture"), ("changelog/", "Changelog")]
MENU = [("Docs", [("", "Overview"), ("metrics/", "Metrics"), ("architecture/", "Architecture"), ("privacy/", "Privacy")]),
        ("Project", [("progress/", "Progress"), ("changelog/", "Changelog"), ("screens/", "Screens"), ("design-system/", "Design system"),
                     ("characters/", "Characters"), ("app/", "Web dashboard")])]
DOC_PAGES = [("metrics/", "Metrics"), ("architecture/", "Architecture"), ("privacy/", "Privacy")]
MENU[0][1].append(("integrations/", "Widgets, MCP & updates"))

# ------------------------------------------------------------------------------------------------------------ shell

# The Clepso mark (design/brand): the 12 p symbol on an ink tile, the same drawing as the favicon.
LOGO = (repo / "design/brand/favicon/favicon.svg").read_text().strip().replace("<svg ", '<svg aria-hidden="true" ', 1)


def header(current, label="docs"):
    here = ' aria-current="page"'
    pill = "".join(f'<a href="/{p}"{here if p == current else ""}>{e(n)}</a>' for p, n in NAV)
    return (f'<a class="px-skip" href="#main">Skip to content</a>'
            f'<header class="px-head"><a class="px-brand" href="/" aria-label="Clepso docs, home">{LOGO}CLEPSO<small>{e(label)}</small></a>'
            f'<div class="px-pill" role="navigation" aria-label="Main">{pill}</div>'
            '<div class="px-actions"><button class="px-btn" type="button" data-search-open aria-label="Search the docs (⌘K)">'
            '<span class="px-label">Search</span><kbd>⌘K</kbd></button>'
            '<button class="px-btn" type="button" data-menu-open aria-expanded="false" aria-controls="px-menu">'
            '<span class="px-burger" aria-hidden="true"><i></i><i></i><i></i></span><span class="px-label">Menu</span></button></div></header>'
            + menu(current) + search_dialog())


def menu(current):
    rows, n = [], 0
    for group, items in MENU:
        rows.append(f'<p class="px-menu-group">[ {e(group)} ]</p>')
        for path, name in items:
            n += 1
            cur = ' aria-current="page"' if path == current else ""
            rows.append(f'<a href="/{path}"{cur}><span>{n:02d}</span><b>{e(name)}</b><i aria-hidden="true">→</i></a>')
    return (f'<div class="px-menu" id="px-menu" role="dialog" aria-modal="true" aria-label="Site menu" hidden>'
            f'<div class="px-menu-art"><canvas data-dither data-w="150" data-h="190" aria-hidden="true"></canvas>'
            f'<p>Clepso · build {e(COMMIT)}</p></div>'
            f'<div class="px-menu-list">{"".join(rows)}</div>'
            f'<button class="px-btn px-close" type="button" data-menu-close>Close <kbd>esc</kbd></button></div>')


def search_dialog():
    return ('<div class="px-search" id="px-search" role="dialog" aria-modal="true" aria-label="Search the docs" hidden>'
            '<div class="px-search-box"><label><span aria-hidden="true">&gt;</span>'
            '<input type="search" placeholder="Search limits, levels, pace, privacy…" autocomplete="off" spellcheck="false" '
            'role="combobox" aria-expanded="true" aria-controls="px-results" aria-label="Search"></label>'
            '<ul id="px-results" role="listbox" aria-label="Results"></ul>'
            '<p class="px-search-hint">↑ ↓ to move · ↵ to open · esc to close</p></div></div>')


# The footer village (founder request, 17 Oct 2026). Statuses must match docs/ROADMAP.md: Claude Code and Codex (3.4) are
# read today; Gemini and Grok are in 3.2 (manual snapshots) and 3.3 (spikes); the rest were requested, not planned.
VILLAGE = [
    ("claude-code", "Claude Code", "#FF8A5B", "today", "Read today: both limits, the session, Claude Code's statistics and agents per task."),
    ("codex", "Codex", "#8FD3FF", "today", "Read today, if you turn it on: the 5-hour and weekly limits and plan, from Codex's own session files (3.4)."),
    ("gemini-cli", "Gemini CLI", "#A58CFF", "planned", "On the roadmap (3.5): a reader for what Gemini CLI records on your Mac, like Codex's."),
    ("grok", "Grok", "#D9D4C4", "planned", "On the roadmap (3.6): a reader once a Grok coding agent keeps local records; manual entries meanwhile."),
    ("cursor", "Cursor", "#FFC04D", "planned", "On the roadmap (3.7–3.9): study what it keeps on your Mac, then a reader like Codex\'s."),
    ("copilot", "GitHub Copilot", "#5EE6FF", "planned", "On the roadmap (3.7–3.9): study what it keeps on your Mac, then a reader like Codex\'s."),
    ("windsurf", "Windsurf", "#3DD6B0", "planned", "On the roadmap (3.7–3.9): study what it keeps on your Mac, then a reader like Codex\'s."),
]
VILLAGE_STATUS = {"today": "Today", "planned": "Roadmap", "requested": "Requested"}


def village():
    data = json.dumps([{"id": i, "name": n, "color": int(c[1:], 16), "status": s, "note": t} for i, n, c, s, t in VILLAGE]).replace("</", "<\\/")
    buttons = "".join(f'<button type="button" data-agent="{i}" aria-pressed="false"><i style="background:{c}"></i>{e(n)}'
                      f'<small class="s-{s}">{VILLAGE_STATUS[s]}</small></button>' for i, n, c, s, _ in VILLAGE)
    return (f'<section class="village" aria-labelledby="village-title"><div class="wrap village-head">'
            f'<div><p class="eyebrow" id="village-title">The village · <b>agents Clepso reads, and the ones moving in</b></p>'
            f'<p class="village-sub">Tokens from agents Clepso can read join the tower\'s glow; the others fall back until it learns to read them. '
            f'Product names belong to their owners; Clepso is independent.</p></div>'
            f'<div class="village-roster" role="group" aria-label="Agents in the village">{buttons}</div></div>'
            f'<div class="village-stage"><canvas aria-hidden="true"></canvas><span class="village-label" hidden></span>'
            f'<div class="village-card" role="status" aria-live="polite" hidden></div>'
            f'<p class="village-hint">Drag to look around · select an agent</p>'
            f'<p class="village-fallback">The village needs WebGL. The agents are listed above.</p></div>'
            f'<script type="application/json" id="village-data">{data}</script></section>')


def footer():
    cols = "".join(f'<div><p>{e(group)}</p><ul>' + "".join(f'<li><a href="/{p}">{e(n)}</a></li>' for p, n in items) + "</ul></div>"
                   for group, items in MENU)
    return (f'<div class="stripes" aria-hidden="true"></div><footer class="foot"><div class="wrap">'
            f'<div class="foot-cols"><div><p>Clepso</p><ul><li>A macOS menu bar monitor for coding-agent limits: Claude Code and Codex.</li>'
            f'<li>Clepso is a working name.</li></ul></div>{cols}'
            f'<div><p>Build</p><ul><li>Commit <code>{e(COMMIT)}</code></li><li>{e(COMMIT_DATE)}</li><li>{len(GATES)} gates per commit</li></ul></div></div>'
            f'<div class="foot-word" aria-hidden="true"><small>CLEPSO.wordmark</small><b>CLEPSO</b><i></i><i></i><i></i><i></i></div></div>'
            f'{village()}'
            f'<div class="wrap foot-base"><span>Generated by <code>scripts/build-site.py</code> from the repository.</span>'
            f'<a href="#main">Back to top ↑</a></div></footer>')


SEARCH = []


def page(path, title, description, body, kind="wide"):
    out = site / path / "index.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(title)} · Clepso docs</title><meta name="description" content="{e(description)}">
<meta name="theme-color" content="#060907"><link rel="stylesheet" href="/assets/site.css"><link rel="icon" href="/favicon.ico" sizes="any"><link rel="icon" href="/assets/favicon.svg" type="image/svg+xml"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<script>document.documentElement.classList.add("js")</script>
</head><body class="k-{kind}">{header(path)}<main id="main">{body}</main>{footer()}
<script src="/assets/site.js" defer></script>
</body></html>
""")
    index(path, title, description, body)


def strip(fragment):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", fragment))).strip()


def index(path, title, description, body):
    """Search entries: the page, then every h2 with an id and the text under it."""
    SEARCH.append({"t": title, "p": "Page", "u": f"/{path}", "x": description, "top": True})
    parts = re.split(r'(<h2 id="[^"]+"[^>]*>.*?</h2>)', body, flags=re.S)
    for i in range(1, len(parts), 2):
        anchor = re.search(r'id="([^"]+)"', parts[i]).group(1)
        SEARCH.append({"t": strip(parts[i]), "p": title, "u": f"/{path}#{anchor}", "x": strip(parts[i + 1])[:240]})


def inline(text):
    """Escape, then the little Markdown the roadmap tables use: code, bold, links shown as their text."""
    text = e(text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)


def plain(text):
    return re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text).replace("`", "").replace("**", "")


def compact(n):
    for size, suffix in ((1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")):
        if n >= size:
            v = n / size
            return (f"{v:.0f}" if v == int(v) else f"{v:.1f}") + suffix
    return str(int(n))


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def excerpt(rel, start, end, keep_end=True):
    """A verbatim slice of a Swift file, from the line containing `start` to the line containing `end`.
    Fails the build if either marker is gone, so a page can never show code that no longer exists."""
    lines = (repo / rel).read_text().splitlines()
    a = next(i for i, l in enumerate(lines) if start in l)
    b = next(i for i in range(a, len(lines)) if end in lines[i])
    return textwrap.dedent("\n".join(lines[a:b + (1 if keep_end else 0)]))


def sources(*files):
    items = "".join(f"<li><code>{e(f)}</code></li>" for f in files)
    return f'<details class="sources" open><summary>Relevant source files</summary><ul>{items}</ul></details>'


def docs_page(path, title, description, lede, body):
    """Three columns (Mintlify): page tree, the article, and On this page with a reading ruler."""
    heads = re.findall(r'<h2 id="([^"]+)"[^>]*>(.*?)</h2>', body, re.S)
    tree = []
    for p, n in DOC_PAGES:
        cur = p == path
        sub = "".join(f'<li><a href="#{a}">{strip(t)}</a></li>' for a, t in heads) if cur else ""
        tree.append(f'<li><a href="/{p}"{" aria-current=page" if cur else ""}>{e(n)}</a>{f"<ul>{sub}</ul>" if sub else ""}</li>')
    project = "".join(f'<li><a href="/{p}">{e(n)}</a></li>' for p, n in MENU[1][1])
    toc = "".join(f'<li><a href="#{a}">{strip(t)}</a></li>' for a, t in heads)
    mobile = "".join(f'<li><a href="#{a}">{i:02d} {strip(t)}</a></li>' for i, (a, t) in enumerate(heads, 1))
    page(path, title, description, f"""
<div class="docs">
<aside class="tree" aria-label="Documentation pages"><p>[ Docs ]</p><ul>{"".join(tree)}</ul><p>[ Project ]</p><ul>{project}</ul></aside>
<article class="article">
<header class="doc-head"><p class="eyebrow">Docs / <b>{e(title)}</b></p><h1>{e(title)}</h1><p class="lede">{lede}</p>
<div class="doc-tools"><button class="tool" type="button" data-copy-page>Copy page</button><button class="tool" type="button" data-copy-link>Copy link</button>
<button class="tool" type="button" data-search-open>Search ⌘K</button></div></header>
<details class="mobile-tree"><summary>On this page</summary><ul>{mobile}</ul></details>
{body}
</article>
<aside class="toc" aria-label="On this page"><p>On this page</p><div class="toc-list"><span class="ruler" aria-hidden="true"><i></i></span><ol>{toc}</ol></div><p class="toc-pct" aria-hidden="true"></p></aside>
</div>""", kind="docs")


GATES = re.findall(r'^run "([^"]+)"', (repo / "scripts" / "ci.sh").read_text(), re.M)
GATE_NOTES = {
    "toolchain pinned": "The expected Swift version.",
    "strict build (warnings=errors)": "Warnings are errors; Swift 6 strict concurrency.",
    "tests": "The full suite (Swift Testing).",
    "helper links no networking": "The helper binary links no networking frameworks.",
    "networking only in Sync": "Networking APIs appear only in the Sync module, and only the app imports it.",
    "clock injected": "Logic reads time through an injected clock, so tests control it.",
    "design tokens only": "Views use theme tokens and pixel glyphs, never literal colours, sizes or system symbols.",
    "redaction audit": "Logs and exports contain no fields outside the allowlist.",
    "secret scan": "No credentials in the repository.",
    "app bundle": "Signature, embedded helper, entitlements, URL scheme.",
}
TESTS = sum(p.read_text().count("@Test") for p in (repo / "Tests").rglob("*.swift"))

# ------------------------------------------------------------------------------------------------- roadmap progress

STATUS = {"✓": ("done", "Done"), "✔": ("done", "Done"), "▶": ("next", "In progress"), "○": ("todo", "Not started"),
          "⏸": ("wait", "Waiting")}
PLANNED = ("todo", "Planned")


def roadmap_sections():
    """(title, header, rows) for every table in ROADMAP §3, status column included where present."""
    text = (docs / "ROADMAP.md").read_text()
    body = text[text.index("## 3. Increments in detail"):text.index("## 4.")]
    sections, title, table = [], None, None
    for line in body.splitlines():
        if line.startswith("### "):
            title, table = line[4:].strip(), None
        elif line.startswith("|") and title:
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if table is None:
                table = (title, cells, [])
                sections.append(table)
            elif not set("".join(cells)) <= set("-: "):
                table[2].append(cells)
        else:
            table = None
    return sections


def status_of(cell):
    return next((v for k, v in STATUS.items() if k in cell), None)


def badge(status):
    return f'<span class="badge s-{status[0]}">{e(status[1])}</span>'


def meter(n, of, cells=24):
    lit = round(cells * n / of) if of else 0
    return '<div class="meter" aria-hidden="true">' + "".join(f'<i class="{"on" if i < lit else ""}"></i>' for i in range(cells)) + "</div>"


def short(title):
    head = re.sub(r"\s*\(.*\)$", "", title)
    if head.startswith("M2 to M4"):
        return "M2–M4", head
    return head.split(":")[0].split(" ")[0], head


def inc_num(cell):
    """The increment id in a row's first cell, as written ("2.1", "2.1q", "1.18"), without Markdown or spaces.
    Compared as a whole string, so "2.1q" is its own increment (not 2.1) and "1.18" is never "1.8"."""
    return plain(cell).strip()


sections = roadmap_sections()
# An increment with a row in a table that has a Status column is tracked there; the same number in a table without
# one (the sequenced M2 to M4 plan) is its earlier, planned description, so that copy is dropped.
TRACKED = {inc_num(r[0]) for _, header_, rows in sections if "Status" in header_ for r in rows if r}
MILESTONES = []      # [{"key", "name", "rows": [inc]}]
INCS = []            # every increment in build order
for title, header_, rows in sections:
    key, name = short(title)
    col = {h: i for i, h in enumerate(header_)}
    ms = {"key": key, "name": name, "title": title, "header": header_, "rows": []}
    for r in rows:
        if "Status" not in col and inc_num(r[0]) in TRACKED:
            continue
        get = lambda h: r[col[h]] if h in col and col[h] < len(r) else ""
        inc = {"num": inc_num(r[0]), "title": get("Increment"), "how": get("How it is built") or get("Build approach in one line"),
               "proof": get("Proof it works"), "status": status_of(get("Status")) if "Status" in col else PLANNED,
               "ms": key, "row": r}
        inc["status"] = inc["status"] or PLANNED
        ms["rows"].append(inc)
        INCS.append(inc)
    if ms["rows"]:                       # a plan table whose every row is now tracked elsewhere disappears
        MILESTONES.append(ms)

done = sum(1 for i in INCS if i["status"][0] == "done")
total = len(INCS)
in_progress = [i for i in INCS if i["status"][0] == "next"]
waiting = [i for i in INCS if i["status"][0] == "wait"]
now_index = INCS.index(in_progress[0]) if in_progress else done


def inc_id(inc):
    return "inc-" + slug(inc["num"])


def check_unique(ids, where):
    """Fail the build when an increment would show twice: two rows for one id, or two ids that share an anchor."""
    seen = {}
    for i in ids:
        seen[i] = seen.get(i, 0) + 1
    twice = sorted(i for i, n in seen.items() if n > 1)
    if twice:
        sys.exit(f"build-site: increment shown more than once on {where}: {', '.join(twice)} "
                 "(ROADMAP §3 has more than one row with a Status for it; keep one).")


check_unique([inc_id(i) for i in INCS], "the Progress page")


def status_board(compact_rows=False):
    """One bar per increment, a row per milestone (Stripe Status)."""
    rows = []
    for ms in MILESTONES:
        n_done = sum(1 for i in ms["rows"] if i["status"][0] == "done")
        bars = "".join(f'<a class="{i["status"][0] if i["status"] != PLANNED else "todo"}" href="/progress/#{inc_id(i)}" '
                       f'title="{e(i["num"])} · {e(plain(i["title"]))} · {e(i["status"][1])}" aria-label="{e(i["num"])} {e(plain(i["title"]))}: {e(i["status"][1])}"></a>'
                       for i in ms["rows"])
        label = f'{n_done} of {len(ms["rows"])} done' if n_done or ms["rows"][0]["status"] != PLANNED else "Sequenced"
        rows.append(f'<div class="status-row"><span>{e(ms["name"])}</span><div class="bars">{bars}</div><em>{label}</em></div>')
    pct = round(100 * done / total)
    return (f'<div class="status rv"><div class="status-top"><b>{done} of {total} increments done · {pct}%</b><div class="legend">'
            '<span><i class="c-green"></i>Done</span><span><i class="c-amber"></i>In progress</span>'
            '<span><i style="box-shadow:inset 0 0 0 2px var(--p-amber)"></i>Waiting</span><span><i style="background:var(--p-muted);box-shadow:inset 0 0 0 1px var(--p-line)"></i>Not started</span></div></div>'
            + "".join(rows) + "</div>")


def timeline(select=None):
    """Dot timeline across every increment in build order (Grok, SpaceXAI, V7)."""
    select = select if select is not None else now_index
    parts, last = [], None
    for k, inc in enumerate(INCS):
        if inc["ms"] != last:
            parts.append(f'<span class="tl-mark" aria-hidden="true"><span>{e(inc["ms"])}</span></span>')
            last = inc["ms"]
        s = inc["status"]
        cls = "todo" if s == PLANNED else s[0]
        parts.append(f'<button class="tl-dot {cls}" type="button" aria-pressed="{"true" if k == select else "false"}" '
                     f'aria-label="{e(inc["num"])} {e(plain(inc["title"]))}, {e(s[1])}" data-n="{e(inc["num"])}" data-t="{e(plain(inc["title"]))}" '
                     f'data-p="{e(plain(inc["how"]))}" data-s="{cls}" data-sl="{e(s[1])}"><i></i></button>')
    first = INCS[select]
    return (f'<div class="tl rv"><div class="tl-track"><div class="tl-line">{"".join(parts)}</div></div>'
            f'<div class="tl-card" aria-live="polite"><b>{e(first["num"])}</b><div><h3>{e(plain(first["title"]))}</h3><p>{e(plain(first["how"]))}</p></div></div>'
            '<div class="tl-nav"><button class="tool" type="button" data-tl="-1">← Previous</button><button class="tool" type="button" data-tl="1">Next →</button>'
            '<span class="counts" style="align-self:center;margin-left:8px">Arrow keys move along the line.</span></div></div>')


# ---------------------------------------------------------------------------------------------------------- progress

lanes = []
start = 0
for ms in MILESTONES:
    n = len(ms["rows"])
    n_done = sum(1 for i in ms["rows"] if i["status"][0] == "done")
    row = len(lanes) + 1
    lanes.append(f'<div class="lane-name" style="grid-row:{row};grid-column:1" title="{e(ms["name"])}">{e(ms["name"])}</div>'
                 f'<div class="lane-bar" style="grid-row:{row};grid-column:{start + 2} / span {n}"><i style="width:{100 * n_done / n:.1f}%"></i>'
                 f'<span>{n_done}/{n}</span></div>')
    start += n
now_left = f"calc(170px + (100% - 170px) * {(now_index + 0.5) / total:.4f})"
lanes_html = (f'<div class="lanes rv"><div class="lanes-grid" style="--n:{total}">{"".join(lanes)}'
              f'<div class="now" style="left:{now_left}" aria-hidden="true"><span>NOW</span></div></div></div>')

tabs, panels = [], []
for k, (key, label, test) in enumerate([("done", "Done", lambda s: s[0] == "done"), ("now", "In progress", lambda s: s[0] in ("next", "wait")),
                                        ("next", "Next", lambda s: s[0] == "todo")]):
    cards = []
    for ms in MILESTONES:
        items = [i for i in ms["rows"] if test(i["status"])]
        if not items:
            continue
        lis = "".join(f'<li><b>{e(i["num"])}</b><span>{e(plain(i["title"]))}</span></li>' for i in items)
        cards.append(f'<article class="phase"><header><b>{e(ms["name"])}</b><em>{len(items)} of {len(ms["rows"])}</em></header><ul>{lis}</ul></article>')
    count = sum(1 for i in INCS if test(i["status"]))
    tabs.append(f'<button role="tab" id="tab-{key}" aria-controls="panel-{key}" aria-selected="{"true" if key == "now" else "false"}" type="button">{label} · {count}</button>')
    panels.append(f'<div class="phases" role="tabpanel" id="panel-{key}" aria-labelledby="tab-{key}"{"" if key == "now" else " hidden"}>{"".join(cards)}</div>')

details = []
for ms in MILESTONES:
    header_ = ms["header"]
    keep = [i for i, h in enumerate(header_) if h != "Founder input"]
    has_status = "Status" in header_
    n_done = sum(1 for i in ms["rows"] if i["status"][0] == "done")
    head = "".join(f'<th scope="col">{e(header_[i])}</th>' for i in keep)
    if not has_status:
        head = head.replace("</th>", '</th><th scope="col">Status</th>', 1)
    body_rows = []
    for inc in ms["rows"]:
        r = inc["row"]
        cells = []
        for i in keep:
            cells.append(f"<td>{badge(inc['status'])}</td>" if header_[i] == "Status" else f"<td>{inline(r[i]) if i < len(r) else ''}</td>")
        if not has_status:
            cells.insert(1, f"<td>{badge(PLANNED)}</td>")
        body_rows.append(f'<tr id="{inc_id(inc)}">' + "".join(cells) + "</tr>")
    is_open = any(i["status"][0] in ("next", "wait") for i in ms["rows"])
    summary = f"{n_done} of {len(ms['rows'])} done" if has_status else "Sequenced; detail is written when the milestone before it closes"
    details.append(f'<details class="milestone"{" open" if is_open else ""}><summary><div><h3>{e(ms["name"])}</h3><span class="counts">{summary}</span></div>'
                   f'{meter(n_done, len(ms["rows"])) if has_status else "<span></span>"}</summary>'
                   f'<div class="table-wrap"><table><thead><tr>{head}</tr></thead><tbody>{"".join(body_rows)}</tbody></table></div></details>')

roadmap_text = (docs / "ROADMAP.md").read_text()
roadmap_map = re.search(r"## 2\. The map\s+```text\n(.*?)```", roadmap_text, re.S)

page("progress/", "Progress", "Every increment of Clepso with its status, how it is built and how it is proven.", f"""
<div class="wrap">
<section class="section" style="padding-top:40px"><p class="eyebrow">Project / <b>Progress</b></p>
<h1>Progress <span class="code-voice">// {done}/{total}</span></h1>
<p class="lede">Every increment, in build order, straight from the project roadmap. Each one names how it is built and the evidence
that proves it works; an increment is done only when that proof exists.</p></section>
<h2 id="board">Every increment</h2>{status_board()}
<h2 id="lanes">Milestones</h2><p class="muted">Each lane spans its increments in build order; the fill is the share done.</p>{lanes_html}
<h2 id="path">Path of progress</h2>{timeline()}
<h2 id="phases">By status</h2><div class="tabs" role="tablist" aria-label="Increments by status">{"".join(tabs)}</div>{"".join(panels)}
<h2 id="detail">In detail</h2><p class="muted">Open a milestone for how each increment is built and the proof it works.</p>{"".join(details)}
<h2 id="map">The map</h2><div class="map"><pre>{e(roadmap_map.group(1)) if roadmap_map else ""}</pre></div>
</div>""")
# The same rule on the written page: each increment's row anchor exists once.
check_unique(re.findall(r'<tr id="(inc-[^"]+)"', (site / "progress" / "index.html").read_text()), "progress/index.html")

# ----------------------------------------------------------------------------------------------------------- metrics

# Mirrors ModelLevel.targets in Sources/ClepsoApp/Views/Details/ModelsSection.swift (a test there pins the same list).
TARGETS = [d * m for d in (10 ** k for k in range(3, 16)) for m in (1, 2, 5)]


def level_of(output):
    reached = sum(1 for t in TARGETS if t <= output)
    return reached + 1, (TARGETS[reached - 1] if reached else 0), TARGETS[reached]


ladder_rows = []
for lv in range(1, 26):
    need = 0 if lv == 1 else TARGETS[lv - 2]
    nxt = TARGETS[lv - 1]
    example = ' class="here"' if lv == 14 else ""
    ladder_rows.append(f"<tr{example}><td>LV {lv}</td><td class=\"num\">{compact(need) if need else '0'}</td>"
                       f"<td class=\"num\">{compact(nxt)}</td><td class=\"num\">{compact(nxt - need)}</td></tr>")

ex_out = 18_200_000
ex_lv, ex_floor, ex_next = level_of(ex_out)
ex_pct = round(100 * (ex_out - ex_floor) / (ex_next - ex_floor))

LEVEL_SRC = "Sources/ClepsoApp/Views/Details/ModelsSection.swift"
LIMIT_SRC = "Sources/UsageEngine/PoolReducer.swift"
PACE_SRC = "Sources/UsageEngine/Pace.swift"
level_code = excerpt(LEVEL_SRC, "static let targets: [Int64]", "self.next = reached")
limit_code = excerpt(LIMIT_SRC, "static func classify(", "return .available")
pace_code = excerpt(PACE_SRC, "guard slope > flatSlope", "return .reachesLimit(at: hit)")


def play(kind, title, demo, code, src):
    return (f'<div class="play" data-play="{kind}"><div class="play-demo"><b>{e(title)}</b>{demo}</div>'
            f'<pre class="play-code" data-nocopy><code>// {e(src)}\n{e(code)}</code></pre></div>')


LIMIT_DEMO = ('<label><span>Used <output>40%</output></span><input type="range" min="0" max="100" value="40" aria-label="Percent of the limit used"></label>'
              '<div class="pmeter" aria-hidden="true"></div><p class="play-out ok" aria-live="polite">Available</p><p class="play-note"></p>')
LEVEL_DEMO = ('<label><span>All-time output tokens</span><input type="number" min="0" step="1000" value="18200000" inputmode="numeric" aria-label="Output tokens"></label>'
              '<div class="mini-btns"><button class="tool" type="button" data-set="850">850</button><button class="tool" type="button" data-set="1200000">1.2M</button>'
              '<button class="tool" type="button" data-set="18200000">18.2M</button><button class="tool" type="button" data-set="740000000">740M</button></div>'
              '<p class="play-out ok" aria-live="polite">LV 14</p><div class="pmeter" aria-hidden="true"></div><p class="play-note"></p>')
PACE_DEMO = ('<label><span>Used now <output></output></span><input type="range" min="0" max="100" value="55" aria-label="Percent used now"></label>'
             '<label><span>Rising by <output></output></span><input type="range" min="0" max="40" step="0.5" value="12" aria-label="Points per hour"></label>'
             '<label><span>Readings span <output></output></span><input type="range" min="0" max="240" step="5" value="60" aria-label="Minutes of readings"></label>'
             '<label><span>Reset in <output></output></span><input type="range" min="0" max="300" step="5" value="150" aria-label="Minutes until the reset, 0 for unknown"></label>'
             '<p class="play-out" aria-live="polite"></p><p class="play-note"></p>')

docs_page("metrics/", "Metrics", "How Clepso defines every number it shows: limits, pace, tokens, levels, specialty, calendars and charts.",
          "How every number in Clepso is defined, where it comes from, and what it does not mean. These rules are the code's rules: "
          "each section names the files that implement it, and the three playgrounds run the same rules beside the code.", f"""
<h2 id="sources">Where the numbers come from</h2>
<div class="table-wrap"><table><thead><tr><th>Source</th><th>What it gives</th><th>How fresh</th><th>Kept by Clepso</th></tr></thead><tbody>
<tr><td>Claude Code status line</td><td>5-hour and 7-day usage with reset times, current model, context window, session cost estimate, durations, lines changed, prompt-cache counts</td><td>Every status refresh while Claude Code runs</td><td>Yes, on this Mac only, after an allowlist removes everything else (paths, prompts, ids)</td></tr>
<tr><td>Codex session files (<code>~/.codex/sessions</code>, optional)</td><td>5-hour and weekly used % with reset times, plan type, model: only <code>token_count</code> events for Codex's own allowance, from the last 256 KB of the three most recently written files in the last 8 days' folders, and Codex's version from each file's first 4 KB. For Stats, tokens per day and model, from <code>token_count</code> and <code>turn_context</code> lines only</td><td>Each time Clepso checks, about every 30 seconds while on</td><td>Yes, the limits only, on this Mac. Prompts and replies in the same files are skipped without being parsed</td></tr>
<tr><td>Claude Code statistics file (<code>~/.claude/stats-cache.json</code>, the data behind <code>/stats</code>)</td><td>Messages and sessions per day, tokens per model per day, tokens by kind per model (all time), sessions by hour</td><td>Up to yesterday: Claude Code folds each day in afterwards</td><td>No. Read when you open Stats, only if you turn it on; never stored or exported</td></tr>
</tbody></table></div>

<h2 id="tokens">What the tokens are</h2>
<p>A token is a small piece of text, roughly three or four characters, that models read and write. Claude Code counts four kinds.</p>
<div class="table-wrap"><table><thead><tr><th>Kind</th><th>What it is</th><th>Typical share</th><th>Counts for level</th></tr></thead><tbody>
<tr><td class="kind">Output</td><td>Text the model wrote: replies, code, tool calls. The model's own work.</td><td>Well under 1%</td><td class="yes">Yes</td></tr>
<tr><td class="kind">Input</td><td>New text sent to the model that was not already cached: your message, tool results, files it read.</td><td>Under 1%</td><td class="no">No</td></tr>
<tr><td class="kind">Cache read</td><td>Earlier conversation the model re-reads from the prompt cache on every turn. Grows with the length of a conversation, not with the work done.</td><td>Most tokens, often 95% or more</td><td class="no">No</td></tr>
<tr><td class="kind">Cache write</td><td>Conversation stored in the prompt cache so later turns can re-read it cheaply.</td><td>A few percent</td><td class="no">No</td></tr>
</tbody></table></div>
<p class="muted">Totals (“15.8B tokens”, “79% of all”) add all four kinds, as <code>/stats</code> does. Levels use output only.</p>

<h2 id="levels">Levels</h2>
<p class="formula">Level = 1 + the number of targets the model's all-time output has reached.<br>
Targets: 1K, 2K, 5K, 10K, 20K, 50K, 100K … (1, 2, 5 in every power of ten).</p>
{play("level", "Try it: output to level", LEVEL_DEMO, level_code, LEVEL_SRC)}
<p>Why output: it is what the model produced. Total tokens are dominated by cache reads, so a long conversation would
level a model up without it doing more. Why fixed 1-2-5 targets: every next target is a round number you can read, and
each level asks for 2 to 2.5 times the output of the one before, so levels keep meaning something at any scale.</p>
<h3>Worked example: why “18.2M of 20M output” is progress to LV 15</h3>
<p>A model has written {compact(ex_out)} output tokens. The highest target reached is {compact(ex_floor)}, the 13th target,
so it is <strong>LV {ex_lv}</strong>. The next target is {compact(ex_next)}, which makes LV {ex_lv + 1}. The level bar in its dossier
runs from {compact(ex_floor)} to {compact(ex_next)}: ({compact(ex_out)} − {compact(ex_floor)}) ÷ ({compact(ex_next)} − {compact(ex_floor)}) = {ex_pct}%,
with {compact(ex_next - ex_out)} to go.</p>
<h3>The ladder</h3>
<div class="table-wrap narrow"><table><thead><tr><th>Level</th><th class="num">Output reached</th><th class="num">Next level at</th><th class="num">Output in this level</th></tr></thead>
<tbody>{"".join(ladder_rows)}</tbody></table></div>
<p class="muted">The ladder continues the same way past LV 25. In the app, “How levels work” under Stats › Models (Arena) draws it as a
pixel track: a cell per level, at least 1 to 20, each target under its cell, every model's character standing on its level and the chosen model's
next level marked NEXT. On 30-day and 7-day ranges, levels still use all-time output, because Claude Code records tokens by kind for all time only.</p>
{sources(LEVEL_SRC)}

<h2 id="rank">Rank and specialty</h2>
<p><strong>Rank</strong>: by level, then by output, then by total tokens. A higher rank never has a lower level.</p>
<p class="formula">Specialty ratio for a kind = (model's tokens of that kind ÷ model's total) ÷ (all models' tokens of that kind ÷ all models' total)</p>
<p>The specialty is the kind with the highest ratio, shown as, for example, “Reading input · 13× the party”: that model's
share of input is 13 times the share across all models. If no kind reaches 1.1×, the model is an <strong>All-rounder</strong>.
Every model mostly reads from cache, so the plain largest kind would say the same thing on every card; the ratio shows how
each one differs.</p>
{sources(LEVEL_SRC + " (ModelSpecialty)")}

<h2 id="agents">Agents per task</h2>
<p>Optional, off until you turn it on in Settings. A <strong>task</strong> is one prompt: from the moment you send
it until Claude stops. Clepso adds four background hooks to Claude Code (prompt submitted, subagent started, subagent stopped,
Claude stopped) and counts the subagents each task starts, nested ones included.</p>
<div class="table-wrap"><table><thead><tr><th>Figure</th><th>Meaning</th></tr></thead><tbody>
<tr><td>Agents</td><td>Subagents started during the task. Each one counts once, matched by a hashed id, even if its events arrive out of order.</td></tr>
<tr><td>Types</td><td>Claude Code's built-in types by name, made readable (Explore (research), Plan, General, Claude Code guide, Status line setup). Your own and plugin agents count as Custom, unless you approve an agent's exact name in Settings › Claude Code: only then does the helper pass that name on. Approved names stay on this Mac; an account upload counts them as Custom.</td></tr>
<tr><td>Finished</td><td>Subagents that reported stopping. Background subagents can finish after the task ends.</td></tr>
<tr><td>Running</td><td>No stop seen yet, and the subagent started under six hours ago. “Running now” lists every such subagent from any task, with the task that started it; after 10 quiet minutes in its session one reads “Last seen”.</td></tr>
<tr><td>Used agents</td><td>Share of the last 30 days' tasks that started at least one subagent.</td></tr>
<tr><td>Agents per task</td><td>All subagents in 30 days ÷ all tasks in 30 days, tasks without subagents included.</td></tr>
</tbody></table></div>
<div class="callout"><p>Claude Code hands every hook the whole event, your prompt included. The helper keeps only the event name,
hashed session and agent ids and the type, and drops the rest before anything leaves it.</p></div>
{sources("Sources/ShimProtocol/HookFrame.swift", "Sources/Storage/Store+Agents.swift")}

<h2 id="limits">Limits and the pace estimate</h2>
<div class="table-wrap"><table><thead><tr><th>State</th><th>When</th></tr></thead><tbody>
<tr><td>Available</td><td>Under 80% used</td></tr><tr><td>Approaching limit</td><td>80% or more</td></tr>
<tr><td>Nearly exhausted</td><td>95% or more</td></tr><tr><td>Limit reached</td><td>100%</td></tr>
<tr><td>Reset expected</td><td>The reset time has passed but no fresh reading has confirmed it. Clepso never says “ready” without one.</td></tr>
<tr><td>Stale</td><td>No reading recently; the last value is shown as “last seen” with its age.</td></tr>
</tbody></table></div>
<p>A state clears only after usage drops 3 points below its threshold, so it does not flicker.</p>
{play("limit", "Try it: drag the usage up and back down", LIMIT_DEMO, limit_code, LIMIT_SRC)}
<p><strong>Pace estimate</strong> (always labelled “Estimate”): a straight line fitted by least squares through recent readings in
the current window: the last 90 minutes for the 5-hour limit, the last 24 hours for the 7-day limit. It needs at least 3
readings over at least 10 minutes. At or below 0.5 points per hour usage counts as flat (“not rising”). It never looks further ahead
than 8 times the history it rests on, so an hour of readings cannot predict two days. If the window resets before the line
reaches 100%, it says roughly how much will be used by the reset.</p>
{play("pace", "Try it: a steady rise through the readings", PACE_DEMO, pace_code, PACE_SRC)}
<p>The Limits chart spans the limit's own window, from reset minus its length to the reset. The hatched span before the first
reading is time Clepso was not yet watching.</p>
{sources(LIMIT_SRC + " (EngineConfig, classify)", PACE_SRC)}

<h2 id="session">Session figures</h2>
<div class="table-wrap"><table><thead><tr><th>Figure</th><th>Meaning</th></tr></thead><tbody>
<tr><td>Context</td><td>Tokens in the model's context window now, out of the window's size. Not a running total for the session.</td></tr>
<tr><td>Cost est.</td><td>Claude Code's estimate at API list price. Not your bill and not your plan's usage.</td></tr>
<tr><td>Cache hits</td><td>Share of prompt tokens served from the cache in this session.</td></tr>
<tr><td>API time · Wall time</td><td>Time spent waiting on the model · time since the session started.</td></tr>
<tr><td>Lines +/−</td><td>Lines added and removed by the session's edits.</td></tr>
<tr><td>By model</td><td>Sessions grouped by their main model over 30 days; background models count under the main one.</td></tr>
</tbody></table></div>

<h2 id="calendar">Activity calendar</h2>
<p>Each square is a day. Its level is set by messages that day, in quarters of your active days, and drawn as pixel density
rather than shade: the quietest quarter lights a few pixels, then a checkerboard, then solid with a few holes, and the busiest
quarter is solid. The pattern says the level without relying on colour. A day with no messages is the plain square; a day before
your first session or after today is an outline marked “no data”. All time shows one calendar year (January to December) with a
year switcher that goes back to 2025; 30 days shows a month calendar, each day's date and message count on the plain square with
its level as a pixel band below them; 7 days shows a column per day.</p>
{sources("Sources/ClepsoApp (StatsCalendar, StatsSummary)")}

<h2 id="charts">Charts</h2>
<p>Tokens per day are stacked by model on a real date axis: days with nothing stay on the axis. Past 120 days the bars become
weeks. Every bar chart is drawn as pixel columns: whole-pixel widths, heights in whole pixels from the baseline, stepped top corners. The scale's top is the first round number at or above the tallest bar whose quarters are also round (for example
8M for a 6.5M peak). Models differ by colour and fill pattern, never colour alone. Point at a bar for its numbers.</p>
""")

# ------------------------------------------------------------------------------------------------------ architecture

arch = (docs / "ARCHITECTURE.md").read_text()
flow = re.search(r"## 6\. Data flow\s+```text\n(.*?)```", arch, re.S)

STEPS = [
    ("Claude Code", "Status line", "Runs your status line command on every refresh and hands it a JSON description of the session."),
    ("Helper", "statusline.sh · clepso-statusline", "Passes the input to your own status line unchanged, keeps only allowlisted fields, sends them on."),
    ("Ingest", "Socket · Ingestor", "Local socket, peer checks and a rate limit; each frame becomes readings with source and freshness."),
    ("Store", "SQLite · UsageEngine", "One transaction per frame: insert the reading, work out each limit's state, keep the history."),
    ("Show", "Menu bar · Dashboard", "Renders snapshots it is handed and never computes a state itself."),
    ("Sync", "Optional, if you sign in", "Uploads daily counts once an hour; the only module allowed to use the network."),
]


def explode():
    plates = "".join(f'<div class="plate{" cloud" if i == len(STEPS) else ""}" style="--z:{i - 3.5}" data-step="{i}"><span>{i:02d} {e(name)}</span></div>'
                     for i, (name, _, _) in enumerate(STEPS, 1))
    steps = "".join(f'<li data-step="{i}" tabindex="0"><b>{i:02d}</b><div><strong>{e(name)} · {e(sub)}</strong><span>{e(note)}</span></div></li>'
                    for i, (name, sub, note) in enumerate(STEPS, 1))
    return (f'<div class="explode rv"><ol class="steps" aria-label="How a reading travels">{steps}</ol>'
            f'<div class="stack" aria-hidden="true">{plates}<span class="giant-word">FLOW</span></div></div>')


PIXEL = {  # 8×8 pixel icons for the principles (Teak's hairline grid)
    "local": ["...##...", "..####..", ".######.", "########", ".#....#.", ".#.##.#.", ".#.##.#.", ".######."],
    "allow": ["########", "########", ".######.", "..####..", "...##...", "...##...", "...##...", "...#...."],
    "absent": ["........", "########", "#......#", "#......#", "########", "........", "#.#.#.#.", "........"],
    "undo": ["..####..", ".#....#.", "#......#", "#...#...", "#...##..", "#...###.", ".#..##..", "..#.#..."],
}


def pixel_icon(name, colour="#4DFF8F"):
    rects = "".join(f'<rect x="{x}" y="{y}" width="1" height="1"/>' for y, row in enumerate(PIXEL[name]) for x, c in enumerate(row) if c == "#")
    return f'<svg viewBox="0 0 8 8" fill="{colour}" aria-hidden="true" shape-rendering="crispEdges">{rects}</svg>'


gate_rows = "".join(f"<tr><td>{e(g[:1].upper() + g[1:])}</td><td>{e(GATE_NOTES.get(g, ''))}</td></tr>" for g in GATES)

docs_page("architecture/", "Architecture", "How Clepso is put together: processes, data flow, modules and quality gates.",
          "A native macOS menu bar app (Swift 6, SwiftUI) that reads what Claude Code already reports about itself, on your Mac. "
          "It works fully without an account; signing in is optional and uploads daily counts only (see <a href=\"/privacy/\">Privacy</a>).", f"""
<h2 id="flow-at-a-glance">A reading's path</h2>
<p>Six layers, bottom to top. Point at a step to light its layer.</p>
{explode()}

<h2 id="processes">Processes</h2>
<div class="table-wrap"><table><thead><tr><th>Process</th><th>Role</th></tr></thead><tbody>
<tr><td><code>Clepso.app</code></td><td>The menu bar app. Listens on a local socket, keeps readings in a local database, works out each limit's state and shows it. If you sign in, it uploads daily counts once an hour.</td></tr>
<tr><td><code>clepso-statusline</code></td><td>A small signed helper inside the app that Claude Code runs on every status refresh. It passes the input to your own status line unchanged, keeps only allowlisted fields and sends them to the app. It links no networking at all.</td></tr>
<tr><td><code>hook.sh</code> (optional)</td><td>Installed only when you turn on agents per task. Claude Code runs it in the background on four events; it runs the helper in hook mode, which sends counts only and always exits silently, so it can never block or change what Claude Code does.</td></tr>
<tr><td><code>statusline.sh</code></td><td>The installed command. Runs the helper if the app is there, otherwise your original status line, so removing the app never breaks Claude Code.</td></tr>
</tbody></table></div>

<h2 id="flow">Data flow on the Mac</h2>
<pre>{e(flow.group(1)) if flow else ""}</pre>

<h2 id="modules">Modules</h2>
<div class="table-wrap"><table><thead><tr><th>Module</th><th>Responsibility</th></tr></thead><tbody>
<tr><td><code>Domain</code></td><td>Values that carry where they came from and how fresh they are, so a missing number can never show as 0%.</td></tr>
<tr><td><code>ShimProtocol</code> · <code>StatusLineShim</code></td><td>The frame format and the allowlist; the helper's logic.</td></tr>
<tr><td><code>ClaudeCodeAdapter</code></td><td>Socket ingest, mapping frames to readings, the settings and hooks installers, the statistics-file reader.</td></tr>
<tr><td><code>UsageEngine</code></td><td>Pure rules: limit states, windows, freshness, the pace estimate.</td></tr>
<tr><td><code>Storage</code></td><td>SQLite (GRDB): one writer, a ledger of readings, migrations with a backup first, retention.</td></tr>
<tr><td><code>Sync</code></td><td>Optional sign-in by email link and the hourly upload of daily counts. The only module that may use the network, and only the app imports it.</td></tr>
<tr><td><code>DesignSystem</code></td><td>Tokens, themes (Phosphor dark and light), pixel glyphs and components, accessibility formatting.</td></tr>
<tr><td><code>ClepsoApp</code></td><td>The app: menu bar panel, Dashboard (Home, Limits, Session, Stats, Goals, Account, Settings), onboarding, diagnostics.</td></tr>
<tr><td><code>SubscriptionCatalog</code></td><td>Plan names, never used to infer usage.</td></tr>
</tbody></table></div>

<h2 id="principles">Principles</h2>
<div class="hair principles">
<div class="principle">{pixel_icon("local")}<h3>Local first</h3><p>Everything works on your Mac without an account. Network code lives only in Sync, used only after you sign in.</p></div>
<div class="principle">{pixel_icon("allow", "#FFC04D")}<h3>Allowlist at the source</h3><p>The helper drops everything not on the allowlist before sending, so the app cannot receive what it must not keep.</p></div>
<div class="principle">{pixel_icon("absent", "#F3F1E7")}<h3>Absent is not zero</h3><p>A limit the source did not report is shown in words with an empty outlined bar, never as 0%.</p></div>
<div class="principle">{pixel_icon("undo", "#FF6B5E")}<h3>Reversible</h3><p>Installing into Claude Code backs up your settings; uninstalling and delete-all restore them byte for byte.</p></div>
</div>

<h2 id="quality">Quality gates</h2>
<p>One command, <code>make ci</code>, runs every gate and must pass before each increment is committed. The list below is read from <code>scripts/ci.sh</code>.</p>
<div class="table-wrap"><table><thead><tr><th>Gate</th><th>What it checks</th></tr></thead><tbody>{gate_rows}</tbody></table></div>
{sources("scripts/ci.sh", "docs/ARCHITECTURE.md")}
""")

# ----------------------------------------------------------------------------------------------------------- privacy

docs_page("privacy/", "Privacy", "What Clepso reads, what it keeps on your Mac, and what it uploads if you sign in.",
          "Clepso works fully on your Mac without an account. If you choose to sign in, it uploads daily counts so you can see your "
          "goals and usage elsewhere. Published by Elvis Obi, Lagos, Nigeria. Updated 22 October 2026.", """
<h2 id="publisher">Publisher and contact</h2>
<p>Clepso is published by <strong>Elvis Obi</strong>, Lagos, Nigeria. For privacy questions, corrections or requests,
email <a href="mailto:contact@elvisobi.com">contact@elvisobi.com</a>. Clepso is independent software and is not affiliated
with the AI providers whose usage it displays.</p>
<h2 id="mac">On your Mac</h2>
<p>Clepso reads Claude Code's status line (limits, model, context, session cost estimate, durations, lines changed), and, only if you turn them
on, Claude Code's statistics file, four background hooks that count subagents per task, and Codex's session files (only the
token count and model lines: limits, plan and tokens per day; prompts and replies in them are skipped unread). A helper drops everything else (prompts, replies,
file paths, project names) before anything reaches the app. Readings stay in a local database for 90 days (sessions and tasks 30).
Delete all removes everything Clepso stored and restores Claude Code's settings.</p>

<h2 id="upload">If you sign in: what is uploaded</h2>
<p>Once an hour, the last 14 days, to a database in Frankfurt (Supabase, EU), readable only with your sign-in:</p>
<div class="table-wrap"><table><thead><tr><th>Data</th><th>Fields</th><th>Only when</th></tr></thead><tbody>
<tr><td>Profile</td><td>Name you typed, plan name you chose</td><td>Always</td></tr>
<tr><td>Daily activity</td><td>Day, messages, sessions, active or not</td><td>Claude Code stats are on</td></tr>
<tr><td>Tokens per model per day</td><td>Day, model name, token count</td><td>Claude Code stats are on</td></tr>
<tr><td>Totals per model</td><td>Model name; input, output, cache read and cache write tokens</td><td>Claude Code stats are on</td></tr>
<tr><td>Limits per day</td><td>Day, the 5-hour limit's peak %, the 7-day limit's % at the end of the day</td><td>Always</td></tr>
<tr><td>Agents per day</td><td>Day, tasks, subagents, subagents by built-in type (custom agents as "custom")</td><td>Counting agents is on</td></tr>
<tr><td>Goals</td><td>Goal kind and target; each day's value and whether it was met</td><td>Always</td></tr>
</tbody></table></div>
<div class="callout"><p><strong>Never uploaded:</strong> prompts, replies, file or folder paths, project or repository names, transcript locations, session or agent
ids, per-session cost, your Claude account details or anything about other apps.</p></div>

<h2 id="account">Your account</h2>
<p>Sign-in is by email link (Apple, Google and GitHub to follow). Your email is held by the sign-in service to send links; it is not stored
with your counts. <strong>Delete account</strong> (Clepso › Account) deletes the account and every row stored with it, at once. Signing out
stops uploads; deleting the account removes what was uploaded. Clepso does not sell personal data or use advertising trackers.</p>

<h2 id="integrations">Optional local integrations</h2>
<p>Desktop widgets and MCP sharing start off. Widgets receive only provider/window names, reported percentages,
observation and reset times, source and state in an app-group container. MCP exposes the same allowlisted fields
to clients you explicitly allow in Settings. Your MCP client may forward readings to its AI service. Revoke a client
in Settings; deleting local data revokes all grants. Local processes running under your Mac account can read this
shared snapshot. Neither integration receives prompts, replies, paths, session identifiers, email addresses or credentials.</p>
<p>When enabled, automatic updates contact the Clepso update feed hosted on Vercel and download releases from GitHub.
Update archives and feeds are signed. Automatic checks and downloads are choices in Settings; no system profile is sent.</p>

<h2 id="gemini">Optional Gemini CLI recording reader</h2>
<p>From 0.4.0 alpha 2, a separate opt-in reader scans the newest Gemini CLI recordings for numeric activity and timestamps.
These files also contain conversations; content is discarded. Numeric activity, hashed deduplication keys and a temporary
file cache stay in memory on this Mac. Paths are used to find files and cache modification times, and are never persisted
or uploaded. Disabling clears the cache. Credentials are not read and provider telemetry is not enabled. These counts
are not included in account uploads, widgets or MCP snapshots. They do not establish your subscription allowance.</p>

<h2 id="services">Service providers</h2>
<p>The public website is hosted on Vercel; downloads are hosted on GitHub. Optional accounts use Supabase for
authentication and storage and Namecheap Private Email for sign-in delivery. These services process the requests
needed to provide those features, including normal connection metadata such as IP addresses. Reading usage locally
does not require a Clepso account. Provider account subscriptions remain with their respective providers.</p>

<h2 id="control">Your controls</h2>
<p>Choose retention in Settings. Export or delete local data there, turn off individual readers and sharing, or delete
your Clepso account from Account. Account deletion removes the server rows belonging to your account; uninstalling
the app by itself does not request server deletion. Contact the publisher if you need help with a privacy request.</p>

<h2 id="security">Security</h2>
<p>Every table is protected by row-level security: a signed-in user can read and write only their own rows, and an anonymous request is
refused. The app holds only the project's publishable key; your session is kept in this Mac's Keychain.</p>
""")

# ----------------------------------------------------------------------------------------------------------- screens

docs_page("integrations/", "Within reach", "Desktop widgets, read-only MCP and signed updates.",
          "Available from 0.4.0 alpha 1. Each connection starts with your choice in Clepso Settings.", """
<h2 id="widgets">Desktop widgets</h2>
<p>In Settings → Integrations, enable Desktop widgets. Add <strong>Clepso limits</strong> from the Mac widget gallery.
The small layout shows two windows; the medium layout shows four. Automatic readings come first. Manual entries,
missing values, old readings and expected resets stay labeled. Click the widget to open Limits.</p>
<p>macOS controls refresh frequency. A widget is a recent snapshot, not a live menu-bar replacement. Turning sharing
off removes its shared snapshot. No account is required.</p>
<h2 id="mcp">Ask an assistant</h2>
<p>In Settings → Integrations, enter a client name, review the disclosure and choose Allow. Copy setup and add the JSON
to that client's documented MCP configuration. Clepso never edits another client's settings automatically.</p>
<div class="table-wrap"><table><thead><tr><th>Tool</th><th>Returns</th></tr></thead><tbody>
<tr><td><code>get_limits</code></td><td>Reported used percentages, reset times, source and freshness</td></tr>
<tr><td><code>get_reader_health</code></td><td>Observation times and whether the app snapshot/readings are current</td></tr>
</tbody></table></div>
<p>Both tools accept an optional provider filter. Missing data stays missing; an expected reset never proves
availability. The server uses local stdio, with no shell, file, credential, settings or database tool.</p>
<p>Your client may forward usage readings to its AI service. Local processes running as your Mac user can read
the shared file. Revoke any client in Settings; running clients lose permission on their next request. Deleting
local data revokes all grants. Demo data is never shared.</p>
<h2 id="gemini">Gemini CLI recorded activity</h2>
<p>From 0.4.0 alpha 2, enable Read recorded token activity in Settings → Gemini CLI. Limits shows tokens from the newest
16 retained local recordings, with input, cache, output, reasoning and tool counters kept separate. Counts and a temporary
file cache stay in memory; conversation content is discarded. Disabling clears the cache. No credentials are read.</p>
<p>This is retained recording activity, not a subscription quota or billing ledger. Deleted history can reduce counts;
partial coverage is labeled. Quota percentage and reset time remain unknown from this source. Gemini web chat is separate.</p>
<h2 id="updates">Updates in the app</h2>
<p>Use Settings → Updates to check manually, enable daily checks, or allow automatic installation. Automatic options
start off. This alpha channel includes preview releases. Sparkle verifies signed feeds and archives before extraction;
official app and DMG releases remain signed and notarized. No system profile is sent.</p>
<p>The first updater-enabled release must be installed using the DMG or Homebrew once. Homebrew remains available:
<code>brew upgrade --cask --greedy obileonardo/clepso/clepso</code>.</p>
<h2 id="privacy">Small, deliberate boundaries</h2>
<p>Widgets and MCP receive only provider/window labels, usage percentages, observation/reset times, source and state.
They never receive prompts, replies, paths, session identifiers, email addresses or credentials.
Read the <a href="/privacy/">privacy notice</a> for account uploads and service providers.</p>
""")

GROUPS = [
    ("Menu bar", {
        "popover-overview": ("Menu bar panel", "Both limits side by side with state, reset and pace estimate; the current session; one Dashboard button."),
        "popover-detail": ("Provider detail", "Plan, both limits and the session in more depth."),
        "popover-inspector": ("Provenance inspector", "Where a number came from and how fresh it is."),
    }),
    ("Dashboard", {
        "details-home": ("Home", "A greeting, the running total, both limits, the latest task, goals at a glance and the last 12 months."),
        "details-home-light": ("Home, light mode", "The same page in Phosphor light: paper, ink and deep green."),
        "details-limits": ("Limits", "Each limit over its own window: scale, threshold bands, NOW, the span before readings, the pace estimate."),
        "details-session": ("Session", "The current session in full, agents per task, recent sessions, and sessions by model."),
        "details-goals": ("Goals", "Active days a week, the 5-hour peak and the week's finish, each with its state in words and its target."),
        "details-account": ("Account", "Profile, plan, sign in by email link (Apple, Google and GitHub being set up), your year and the danger zone."),
        "details-settings": ("Settings", "Settings in the window, as rows with a line of explanation each."),
    }),
    ("Stats", {
        "details-stats-overview": ("Overview, all time", "A January–December activity calendar with a year switcher, tiles, hours and tokens by kind."),
        "details-stats-overview-30": ("Overview, 30 days", "A month calendar with message counts beside tokens per day."),
        "details-stats-overview-7": ("Overview, 7 days", "A column per day: messages, sessions and tokens."),
        "details-stats-models": ("Models, chart", "The roster beside tokens per week stacked by model, drawn as pixel columns on a real date axis."),
        "details-stats-arena": ("Models, arena", "A ranked roster; the chosen model's dossier: its pixel character, tokens by kind, level bar, specialty and activity."),
        "details-stats-arena-light": ("Models, light mode", "The same page in Phosphor light."),
        "details-stats-arena-tall": ("Models, how levels work", "The level track with each model standing on its level, the next one marked, and how to level up."),
        "details-card": ("Card", "The player card: name, first session, plan, milestone stamps, output total, named level; copy, save or share."),
    }),
    ("Setup and safety", {
        "onboarding-3-consent": ("Onboarding consent", "What Clepso reads and keeps, before anything is installed."),
        "settings-diagnostics": ("Diagnostics", "Redacted log, export and delete-all."),
        "settings-delete-all-sheet": ("Delete all", "Removes Clepso's data and restores Claude Code's settings."),
    }),
]
(site / "screens" / "img").mkdir(parents=True, exist_ok=True)
figures, dock, stage_panels, shot_count = [], [], [], 0
for gi, (group, shots) in enumerate(GROUPS):
    buttons = []
    for name, (title, note) in shots.items():
        src = screens / f"{name}.png"
        if not src.exists():
            continue
        shutil.copy(src, site / "screens" / "img" / src.name)
        shot_count += 1
        url = f"img/{src.name}"
        alt = f"{title}: {note}"
        figures.append(f'<figure><a href="{url}"><img src="{url}" alt="{e(alt)}" loading="lazy"></a>'
                       f'<figcaption><strong>{e(group)} › {e(title)}</strong>. {e(note)}</figcaption></figure>')
        buttons.append(f'<button type="button" aria-pressed="false" data-src="{url}" data-alt="{e(alt)}" data-title="{e(group)} › {e(title)}" data-note="{e(note)}">'
                       f'<img src="{url}" alt="" loading="lazy"><span>{e(title)}</span></button>')
    if buttons:
        key = slug(group)
        dock.append(f'<button role="tab" class="px-btn" id="dock-{key}" aria-controls="thumbs-{key}" aria-selected="{"true" if gi == 1 else "false"}" type="button">{e(group)}</button>')
        stage_panels.append(f'<div class="thumbs" role="tabpanel" id="thumbs-{key}" aria-labelledby="dock-{key}"{"" if gi == 1 else " hidden"}>{"".join(buttons)}</div>')

page("screens/", "Screens", "Screenshots of the running Clepso app with demo data.", f"""
<div class="wrap">
<section class="section" style="padding-top:40px"><p class="eyebrow">Project / <b>Screens</b></p>
<h1>Screens <span class="code-voice">// demo data</span></h1>
<p class="lede">The running app, captured by its own debug probe with demo data and a synthetic statistics file. Nothing here is
a real account. Pick a group in the dock, then a screen below; select the large image to open it full size.</p></section>
<div class="halftone rv"><div class="stage">
<div class="dock"><div role="tablist" aria-label="Screen groups">{"".join(dock)}</div></div>
<figure class="stage-main"><a href="#" target="_blank" rel="noopener"><img src="" alt=""></a><figcaption></figcaption></figure>
{"".join(stage_panels)}
</div><div class="shots">{"".join(figures)}</div></div>
</div>""")

# --------------------------------------------------------------------------------------------------------- changelog

log = [line.split("\t", 2) for line in git("log", "--pretty=%ad\t%h\t%s", "--date=short").splitlines()]


def tag_of(subject):
    m = re.match(r"(\d+\.\d+[a-z]?(?:[-–]\w+)?)", subject)
    if m:
        return "increment", m.group(1)
    for prefix, kind, label in (("Site", "site", "Site"), ("Milestone", "milestone", "Milestone"), ("Design", "design", "Design"),
                                ("Level", "design", "Design"), ("Arena", "design", "Design")):
        if subject.startswith(prefix):
            return kind, label
    return "milestone", subject.split(":")[0][:10]


def nice_date(d):
    y, m, dd = map(int, d.split("-"))
    return date(y, m, dd).strftime("%-d %b %Y")


days_html, by_day = [], {}
for d, h, s in log:
    by_day.setdefault(d, []).append((h, s))
for d, entries in by_day.items():
    lis = []
    for h, s in entries:
        kind, label = tag_of(s)
        lis.append(f'<li data-tag="{kind}" data-text="{e(s.lower())} {e(label.lower())} {h}"><span class="tag t-{kind}">{e(label)}</span>'
                   f'<span>{e(s)}</span><code>{e(h)}</code></li>')
    days_html.append(f'<section class="day"><h2 id="d-{d}"><time datetime="{d}">{nice_date(d)}</time></h2><ul class="entries">{"".join(lis)}</ul></section>')

latest_inc = next(((h, s) for d, h, s in log if tag_of(s)[0] == "increment"), None)
kinds = [("", "All"), ("increment", "Increments"), ("site", "Site"), ("design", "Design"), ("milestone", "Milestones and decisions")]
chips = "".join(f'<button class="chip" type="button" data-tag="{k}" aria-pressed="{"true" if not k else "false"}">{e(n)}</button>' for k, n in kinds)
gates_list = "".join(f"<span>{e(g)}</span>" for g in GATES)

page("changelog/", "Changelog", "Every commit to Clepso, newest first.", f"""
<div class="wrap" data-changelog>
<section class="section" style="padding-top:40px"><p class="eyebrow">Project / <b>Changelog</b></p>
<h1>Changelog <span class="code-voice">// {len(log)} commits</span></h1>
<p class="lede">Every commit, newest first. Each one passed all {len(GATES)} quality gates before it was pushed.</p>
<p class="muted">Clepso was called Pulse until 18 Oct 2026. Older commits keep the name they were written with.</p></section>
<div class="release"><div><p class="eyebrow">Current release · <b>{e(RELEASE_TAG)}</b></p><h2>A little more character.</h2>
<p>The literary guild now appears in the Mac Models screen, with distinct editions and quiet authored motion.</p>
<p>Explore the <a href="/characters/">interactive characters</a>; the same artwork ships in the Mac app with Pause and Reduce Motion support.</p>
<p><a href="{RELEASE_URL}">Download and release notes</a></p></div></div>
{f'<div class="release rv"><div><p class="eyebrow">Latest increment · <b>{e(latest_inc[0])}</b></p><h3>{e(latest_inc[1])}</h3><p>Passed every gate:</p></div><div class="gates">{gates_list}</div></div>' if latest_inc else ""}
<div class="filters"><input type="search" placeholder="Search the changelog" aria-label="Search the changelog">{chips}</div>
{"".join(days_html)}
<p class="none" hidden>No commit matches. Clear the search or pick All.</p>
</div>""")
for d, h, s in log:
    SEARCH.append({"t": s, "p": "Changelog", "u": f"/changelog/#d-{d}", "x": f"{h} · {d}"})
for inc in INCS:
    SEARCH.append({"t": f'{inc["num"]} {plain(inc["title"])}', "p": f'Progress · {inc["status"][1]}', "u": f"/progress/#{inc_id(inc)}",
                   "x": plain(inc["how"])[:200]})

# ---------------------------------------------------------------------------------------------------------- overview


def words(text, start=0.0, step=0.06):
    out = []
    for i, w in enumerate(text.split(" ")):
        out.append(f'<span class="w" style="animation-delay:{start + i * step:.2f}s">{w}</span>')
    return " ".join(out)


MARQUEE = [["LIMITS", "green"], ["5-HOUR", "out"], ["PACE", "amber"], ["7-DAY", "cream"], ["LEVELS", "rust"], ["ABSENT ≠ 0", "out"],
           ["GOALS", "green"], ["AGENTS", "amber"]]
MARQUEE2 = [["LOCAL FIRST", "cream"], ["ALLOWLIST", "out"], ["STREAKS", "rust"], ["CALENDAR", "green"], ["DELETE ALL", "out"],
            ["ESTIMATE", "amber"], ["ARENA", "cream"]]


def marquee_row(items):
    blocks = "".join(f'<b class="c-{c}">{e(w)}</b>' for w, c in items)
    return f'<div class="marquee-row">{blocks}<span class="dup" style="display:contents">{blocks}</span></div>'


inc_dots = "".join(f'<i class="{"on" if i["status"][0] == "done" else "next" if i["status"][0] == "next" else "wait" if i["status"][0] == "wait" else ""}" title="{e(i["num"])}"></i>' for i in INCS)
bubbles = "".join('<div><span>' + "".join(f'<i class="{"on" if i["status"][0] == "done" else "next" if i["status"][0] in ("next", "wait") else ""}"></i>' for i in ms["rows"])
                  + f'</span><small>{e(ms["key"])}</small></div>' for ms in MILESTONES)
recent = "".join(f'<li><span class="tag t-{tag_of(s)[0]}">{e(tag_of(s)[1])}</span><span>{e(s)}</span><code>{e(h)}</code></li>' for d, h, s in log[:6])


def wire(kind):
    """Small wireframe drawings for the entry cards (Attio)."""
    body = {
        "metrics": '<rect class="wf" x="20" y="20" width="280" height="100"/><rect class="wf-f" x="40" y="80" width="20" height="30"/><rect class="wf-f" x="70" y="60" width="20" height="50"/>'
                   '<rect class="wf-s" x="100" y="40" width="20" height="70"/><rect class="wf-f" x="130" y="70" width="20" height="40"/>'
                   '<path class="wf-s" d="M180 100 h20 v-10 h20 v-15 h20 v-20 h20 v-25 h20"/><text class="wf-t" x="182" y="40">LV 14</text>',
        "architecture": '<rect class="wf" x="40" y="22" width="120" height="26"/><rect class="wf" x="60" y="56" width="120" height="26"/><rect class="wf-s" x="80" y="90" width="120" height="26"/>'
                        '<path class="wf" d="M200 35 h60 v68 h-60"/><circle class="wf-a" cx="260" cy="70" r="3"/><text class="wf-t" x="88" y="107">STORE</text>',
        "privacy": '<rect class="wf" x="110" y="20" width="100" height="100"/><path class="wf-s" d="M140 70 v-14 a20 20 0 0 1 40 0 v14"/><rect class="wf-f" x="130" y="70" width="60" height="38"/>'
                   '<path class="wf" d="M30 40 h60 M30 60 h50 M30 80 h60 M230 40 h60 M240 60 h50 M230 80 h60"/>',
        "progress": '<path class="wf" d="M20 30 h280 M20 60 h280 M20 90 h280"/><rect class="wf-f" x="20" y="22" width="120" height="16"/><rect class="wf-f" x="140" y="52" width="80" height="16"/>'
                    '<rect class="wf" x="220" y="82" width="70" height="16"/><path class="wf-s" d="M200 14 v110"/><text class="wf-t" x="204" y="20">NOW</text>',
        "screens": '<rect class="wf" x="30" y="24" width="170" height="96"/><rect class="wf-s" x="120" y="44" width="170" height="80"/><circle class="wf-a" cx="132" cy="54" r="3"/>'
                   '<rect class="wf-f" x="132" y="66" width="60" height="8"/><rect class="wf-f" x="132" y="80" width="140" height="30"/>',
        "design": '<rect class="wf-f" x="30" y="30" width="40" height="40"/><rect class="wf-a" x="80" y="30" width="40" height="40"/><rect class="wf" x="130" y="30" width="40" height="40"/>'
                  '<text class="wf-t" x="190" y="50" style="font-size:22px">Aa</text><path class="wf" d="M30 90 h260 M30 104 h200"/>',
    }[kind]
    return f'<svg viewBox="0 0 320 140" aria-hidden="true" preserveAspectRatio="xMidYMid meet">{body}</svg>'


ENTRIES = [("metrics/", "metrics", "Metrics", "Every number defined, with three playgrounds that run the app's rules."),
           ("architecture/", "architecture", "Architecture", "Processes, the path of a reading, modules and quality gates."),
           ("privacy/", "privacy", "Privacy", "What stays on your Mac, and every field uploaded if you sign in."),
           ("progress/", "progress", "Progress", "Each increment, how it is built and how it is proven."),
           ("screens/", "screens", "Screens", "The running app, with demo data."),
           ("design-system/", "design", "Design system", "Tokens, themes and components, rendered from the Swift code.")]
entries = "".join(f'<a class="entry" href="/{p}">{wire(k)}<div><h3>{e(t)}</h3><p>{e(d)}</p></div></a>' for p, k, t, d in ENTRIES)
boot_lines = json.dumps(["CLEPSO DOCUMENTATION SYSTEM", f"BUILD {COMMIT} · {COMMIT_DATE}", f"{done}/{total} INCREMENTS · {len(GATES)} GATES",
                         "READING CLAUDE CODE STATUS LINE … OK"])
hero_shot = "popover-overview" if (screens / "popover-overview.png").exists() else None
home_shot = "details-stats-arena" if (screens / "details-stats-arena.png").exists() else None

page("", "Overview", "Technical documentation and progress for Clepso, a macOS menu bar monitor for Claude Code usage limits.", f"""
<div class="boot" aria-hidden="true" data-lines='{e(boot_lines)}'><div class="boot-screen"><div class="boot-logo">CLEPSO</div>
<div class="boot-lines"></div><div class="boot-bar">{"<i></i>" * 20}</div><div class="boot-skip">Click or press any key to skip</div></div></div>
<section class="hero"><canvas class="hero-canvas" data-dither data-beat data-w="180" data-h="180" aria-hidden="true"></canvas>
<div class="wrap hero-inner"><p class="eyebrow">Clepso docs · build <b>{e(COMMIT)}</b> · {done}/{total} increments done</p>
<h1 class="wordmark" data-text="CLEPSO">CLEPSO</h1>
<p class="headline focus-in-later">{words("Your coding-agent limits,")} <span class="w code-voice" style="animation-delay:.3s">//before</span> {words("you hit them.", .36)}</p>
<p class="lede">A macOS menu bar app that shows how much of your Claude Code and Codex limits you have used, when they reset and how
fast you are going, from what those agents report on your own Mac. These pages document how it is built, what every number means and where the work stands.</p>
<div class="dl-row"><a class="dl-btn" href="{RELEASE_URL}">Download {e(RELEASE_TAG)}</a>
<span class="dl-meta">macOS 14+ · Apple silicon · signed and notarized · free and open source</span></div>
<button class="searchbar" type="button" data-search-open><span>Search the docs: limits, levels, pace…</span><kbd>⌘K</kbd></button>
<div class="chips">Popular: <a href="/metrics/#levels">Levels</a><a href="/metrics/#limits">Pace estimate</a><a href="/metrics/#agents">Agents per task</a>
<a href="/privacy/#upload">What is uploaded</a><a href="/architecture/#flow-at-a-glance">A reading's path</a></div>
<div class="hero-foot"><span>01 · Menu bar monitor for macOS</span><span>Scroll ↓</span></div></div></section>

<div class="marquee" aria-hidden="true">{marquee_row(MARQUEE)}{marquee_row(MARQUEE2)}</div>

<div class="wrap">
<section class="section"><div class="section-head rv"><div><span class="idx">01 / AT A GLANCE</span><h2 id="glance">The build, in numbers</h2></div>
<p>Counted from the roadmap, the git history, the test suite and the CI script each time this site is generated.</p></div>
<div class="bento rv">
<div class="tile big"><span>Increments done</span><div class="dots" style="--cols:13">{inc_dots}</div><b>{done}<span style="font-size:.4em;letter-spacing:0;text-transform:none">/{total}</span></b></div>
<div class="tile ink"><b>{len(log)}</b><span>Commits, each through every gate</span></div>
<div class="tile"><b>{TESTS}</b><span>Swift tests</span></div>
<div class="tile"><b>{len(GATES)}</b><span>Quality gates per commit</span></div>
<div class="tile amber"><b>0</b><span>Prompts, replies or paths ever uploaded</span></div>
<div class="tile full"><span>Increments by milestone</span><div class="bubbles">{bubbles}</div></div>
</div></section>

<section class="section"><div class="section-head rv"><div><span class="idx">02 / STATUS</span><h2 id="status">Every increment</h2></div>
<p>One bar per increment, like a status page: green is done, amber is in progress, outlined is waiting on a go.</p></div>
{status_board()}</section>

<section class="section"><div class="section-head rv"><div><span class="idx">03 / THE APP</span><h2 id="app">What it looks like</h2></div>
<p>The menu bar panel and the arena, from the running app with demo data. <a href="/screens/">All screens →</a></p></div>
<div class="halftone rv" style="display:grid;gap:18px;grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr));align-items:start">
{f'<figure style="margin:0"><img src="/screens/img/{hero_shot}.png" alt="Menu bar panel: both limits with state, reset and pace estimate, and the current session" loading="lazy" style="width:100%;display:block"></figure>' if hero_shot else ""}
{f'<figure style="margin:0"><img src="/screens/img/{home_shot}.png" alt="Stats › Models arena: a ranked roster of models and the chosen model’s dossier with its level and tokens by kind" loading="lazy" style="width:100%;display:block;border:1px solid var(--p-line)"></figure>' if home_shot else ""}
</div></section>

<section class="section"><div class="section-head rv"><div><span class="idx">04 / TRY THE RULES</span><h2 id="try">Drag it past 80%</h2></div>
<p>The same rule the app runs to name a limit's state, next to its Swift source. Level and pace playgrounds are on <a href="/metrics/#levels">Metrics</a>.</p></div>
<div class="rv">{play("limit", "Limit state, with hysteresis", LIMIT_DEMO, limit_code, LIMIT_SRC)}</div></section>

<section class="section"><div class="section-head rv"><div><span class="idx">05 / HOW IT READS</span><h2 id="reads">A reading's path</h2></div>
<p>From Claude Code's status line to the menu bar, all on your Mac. The sixth layer runs only if you sign in.</p></div>
{explode()}</section>

<section class="section"><div class="section-head rv"><div><span class="idx">06 / PATH OF PROGRESS</span><h2 id="path">Step through the build</h2></div>
<p>Every increment in order. The highlighted one is in progress now; pick any dot for what it does.</p></div>
{timeline()}</section>

<section class="section"><div class="section-head rv"><div><span class="idx">07 / READ</span><h2 id="explore">The docs</h2></div>
<p>Or press <kbd style="font:12px var(--p-mono);border:1px solid var(--p-line);padding:1px 6px">⌘K</kbd> anywhere to search.</p></div>
<div class="hair rv">{entries}</div></section>

<section class="section"><div class="section-head rv"><div><span class="idx">08 / RECENT</span><h2 id="recent">Recent changes</h2></div>
<p><a href="/changelog/">Full changelog →</a></p></div>
<ul class="entries rv">{recent}</ul></section>
</div>
""", kind="home")

# ------------------------------------------------------------------------------------------- shared assets and design

assets = site / "assets"
shell_css = (assets_src / "shell.css").read_text()
(assets / "bar.css").write_text(shell_css)
(assets / "site.css").write_text(shell_css + (assets_src / "page.css").read_text())
shutil.copy(assets_src / "site.js", assets / "site.js")
shutil.copy(assets_src / "village.js", assets / "village.js")
(assets / "vendor").mkdir(exist_ok=True)
for name in ("three.module.min.js", "three-LICENSE.txt"):
    shutil.copy(assets_src / "vendor" / name, assets / "vendor" / name)
shutil.copy(repo / "design/brand/favicon/favicon.svg", assets / "favicon.svg")
(assets / "email").mkdir(exist_ok=True)   # account emails link here: keep the name stable (scripts/build-email.py)
shutil.copy(repo / "design/brand/logo/png/clepso-logo-email-244.png", assets / "email" / "clepso-logo-email-244.png")
shutil.copy(repo / "design/email/clepso-protocol-hero-v1.png", assets / "email" / "clepso-protocol-hero-v1.png")
for heading in (repo / "design/email").glob("clepso-heading-*-v1.png"):
    shutil.copy(heading, assets / "email" / heading.name)
shutil.copy(repo / "design/brand/fonts/ClepsoPixel-Regular.woff2", assets / "email" / "ClepsoPixel-Regular.woff2")
for name in ("favicon.ico", "apple-touch-icon.png"):
    shutil.copy(repo / "design/brand/favicon" / name, site / name)

design_page = site / "design-system" / "index.html"
if design_page.exists():
    text = design_page.read_text()
    # A page left by an earlier build may still carry the old bar; take it out before adding the header.
    text = re.sub(r'<link rel="stylesheet" href="/assets/bar.css">.*?</style>', "", text, count=1, flags=re.S)
    text = re.sub(r'<div class="site-bar" role="banner">.*?</ul></div></div></div>', "", text, count=1, flags=re.S)
    if "px-head" not in text:
        # Only the shell's own stylesheet: the design page keeps its light and dark themes; its sticky nav sits under the header.
        text = text.replace("</head>", '<link rel="stylesheet" href="/assets/bar.css"><link rel="icon" href="/favicon.ico" sizes="any"><link rel="icon" href="/assets/favicon.svg" type="image/svg+xml"><link rel="apple-touch-icon" href="/apple-touch-icon.png">'
                            '<style>.px-head{background:var(--p-bg)} body > nav{top:var(--p-head)}</style></head>', 1)
        text = re.sub(r"<body([^>]*)>", lambda m: f"<body{m.group(1)}>{header('design-system/')}", text, count=1)
        text = text.replace("</body>", '<script src="/assets/site.js" defer></script></body>', 1)
        design_page.write_text(text)
    SEARCH.append({"t": "Design system", "p": "Page", "u": "/design-system/", "x": "Tokens, themes and components, rendered from the Swift code.", "top": True})
    for anchor, title in re.findall(r'<h2[^>]*id="([^"]+)"[^>]*>(.*?)</h2>', text, re.S):
        SEARCH.append({"t": strip(title), "p": "Design system", "u": f"/design-system/#{anchor}", "x": ""})

# ----------------------------------------------------------------------------------------------- web dashboard (/app)


def accounts_config():
    """The accounts project the dashboard talks to, or None. From Config/Sync.local.xcconfig (uncommitted, the same file
    official app builds read), or CLEPSO_ACCOUNTS_URL and CLEPSO_ACCOUNTS_KEY for a local stack. The same checks as
    SyncConfig.swift: a plausible host and a publishable key; a secret key is refused outright."""
    url, key = os.environ.get("CLEPSO_ACCOUNTS_URL", "").strip(), os.environ.get("CLEPSO_ACCOUNTS_KEY", "").strip()
    providers = os.environ.get("CLEPSO_ACCOUNTS_PROVIDERS", "")
    if not (url and key):
        values, local = {}, repo / "Config" / "Sync.local.xcconfig"
        if local.exists():
            for line in local.read_text().splitlines():
                line = line.split("//", 1)[0]
                if "=" in line:
                    k, v = line.split("=", 1)
                    values[k.strip()] = v.strip()
        host = values.get("CLEPSO_SYNC_HOST", "")
        key = values.get("CLEPSO_SYNC_PUBLISHABLE_KEY", "")
        providers = providers or values.get("CLEPSO_SYNC_PROVIDERS", "")
        url = f"https://{host}" if re.fullmatch(r"(?=.{4,253}$)[a-z0-9-]+(\.[a-z0-9-]+)+", host) else ""
    url_ok = re.fullmatch(r"https://[a-z0-9-]+(\.[a-z0-9-]+)+|http://(127\.0\.0\.1|localhost):\d{1,5}", url)
    key_ok = 0 < len(key) <= 512 and not re.search(r"\s|\$\(", key) and not key.startswith("sb_secret_")
    enabled = sorted(set(providers.split(",")) & {"apple", "google", "github"})
    return {"url": url, "key": key, "providers": enabled} if url_ok and key_ok else None


# Connections only to this site and a Supabase project (127.0.0.1:54321 is the local stack, for testing).
APP_CSP = ("default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; "
           "connect-src 'self' https://*.supabase.co http://127.0.0.1:54321 http://localhost:54321; "
           "object-src 'none'; base-uri 'none'; form-action 'self'")

app_dir = site / "app"
app_dir.mkdir(parents=True, exist_ok=True)
for name in ("app.js", "app.css"):
    shutil.copy(assets_src / name, assets / name)
accounts = accounts_config()
# Gitignored (the "no committed accounts project" gate); Vercel deploys the local site/ folder, so it still ships.
(app_dir / "config.js").write_text("// Generated by scripts/build-site.py; not committed. null: accounts aren't configured.\n"
                                   f"window.CLEPSO_ACCOUNTS = {json.dumps(accounts)};\n")
(app_dir / "index.html").write_text(f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="{APP_CSP}"><meta name="referrer" content="no-referrer"><meta name="robots" content="noindex">
<title>Web dashboard · Clepso</title><meta name="description" content="Your Clepso goals and usage: the daily counts your Mac uploads when you sign in.">
<meta name="theme-color" content="#060907"><link rel="stylesheet" href="/assets/site.css"><link rel="stylesheet" href="/assets/app.css"><link rel="icon" href="/favicon.ico" sizes="any"><link rel="icon" href="/assets/favicon.svg" type="image/svg+xml"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
</head><body class="k-app">{header("app/", "app")}
<main id="main"><div class="app" id="app" aria-busy="true"><div class="loading" role="status"><i aria-hidden="true"></i>Loading…</div>
<noscript><div class="note warn"><p>The web dashboard needs JavaScript. Clepso on your Mac works without it.</p></div></noscript></div>
<p class="sr" id="app-live" aria-live="polite"></p></main>
<footer class="foot"><div class="wrap foot-base"><span>Clepso web dashboard · build <code>{e(COMMIT)}</code></span>
<span><a href="/privacy/#upload">What is uploaded</a> · <a href="/">Docs</a></span></div></footer>
<script src="/app/config.js" defer></script><script src="/assets/app.js" defer></script><script src="/assets/site.js" defer></script>
</body></html>
""")
SEARCH.append({"t": "Web dashboard", "p": "Page", "u": "/app/", "x": "Sign in to see your goals and usage: the daily counts your Mac uploads.", "top": True})

(assets / "search.json").write_text(json.dumps(SEARCH, ensure_ascii=False, separators=(",", ":")))

(site / "404.html").write_text(f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Not found · Clepso docs</title><link rel="stylesheet" href="/assets/site.css"><link rel="icon" href="/favicon.ico" sizes="any"><link rel="icon" href="/assets/favicon.svg" type="image/svg+xml"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<script>document.documentElement.classList.add("js")</script></head><body>{header("404")}
<main id="main"><div class="wrap lost"><p class="eyebrow">Error 404 · <b>signal lost</b></p><h1 class="wordmark" data-text="404">404</h1>
<p class="lede">That page doesn't exist. <a href="/">Back to the overview</a>, or press ⌘K to search.</p></div></main>{footer()}
<script src="/assets/site.js" defer></script></body></html>
""")
runpy.run_path(str(repo / "scripts/public_site.py"))["build"](site, RELEASE_TAG)
print(f"app: accounts {'configured' if accounts else 'not configured'}")
print(f"site: {len(NAV) + 4} pages, {shot_count} screens, {done}/{total} increments done, {TESTS} tests, {len(GATES)} gates, "
      f"{len(SEARCH)} search entries, commit {COMMIT}")
