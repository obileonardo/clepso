"""Builds the Pulse documentation website around the design-system page.

Pages: Overview, Progress, Metrics, Architecture, Screens, Changelog and the Design system (built by
build-design-site.py, which runs first; this script adds the site bar to it). Content comes from the repository:
ROADMAP.md tables for progress, ARCHITECTURE.md's data-flow diagram, git history, the app screenshots in
design/screens, and the metric rules below, which mirror the Swift code they describe (each names its source file).

Curated for a public URL (founder decision, 17 Oct 2026): no DECISIONS, security internals, backend or compliance
plans, results logs or commit bodies.

Usage: python3 -I scripts/build-site.py <site dir> <docs dir> <screens dir>
"""
import html
import re
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

site, docs, screens = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
repo = Path(__file__).resolve().parent.parent
e = html.escape


def git(*args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=True).stdout.strip()


COMMIT, COMMIT_DATE = git("log", "-1", "--pretty=%h"), git("log", "-1", "--pretty=%ad", "--date=short")

PAGES = [("", "Overview"), ("progress/", "Progress"), ("metrics/", "Metrics"), ("architecture/", "Architecture"),
         ("screens/", "Screens"), ("privacy/", "Privacy"), ("changelog/", "Changelog"), ("design-system/", "Design system")]

# ---------------------------------------------------------------------------------------------------------- styling

BAR_CSS = """
@font-face { font-family: "Silkscreen"; src: url("/assets/fonts/Silkscreen-Regular.ttf") format("truetype"); font-display: swap; }
@font-face { font-family: "Silkscreen"; font-weight: 700; src: url("/assets/fonts/Silkscreen-Bold.ttf") format("truetype"); font-display: swap; }
:root { --p-bg:#060907; --p-surface:#0D1410; --p-muted:#16211A; --p-line:#2C4034; --p-text:#EAF7EE; --p-text2:#93B9A0; --p-accent:#4DFF8F;
  --p-amber:#FFC04D; --p-red:#FF6B5E; --p-pixel:"Silkscreen", ui-monospace, monospace;
  --p-mono: ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, monospace; color-scheme: dark; }
.site-bar { position: sticky; top: 0; z-index: 50; background: rgba(6,9,7,.92); backdrop-filter: blur(10px);
  border-bottom: 1px solid var(--p-line); font-family: var(--p-mono); }
.site-bar .sb-wrap { display: flex; align-items: center; gap: 20px; min-height: 56px; }
.site-bar .brand { font: 700 15px var(--p-pixel); color: var(--p-accent); text-decoration: none; letter-spacing: .06em; white-space: nowrap; }
.site-bar .brand small { color: var(--p-text2); font-weight: 400; margin-left: 6px; }
.site-bar .sb-links ul { display: flex; gap: 2px; list-style: none; margin: 0; padding: 0; overflow-x: auto; scrollbar-width: none; }
.site-bar .sb-links ul::-webkit-scrollbar { display: none; }
.site-bar li a { display: block; padding: 8px 10px; color: var(--p-text2); text-decoration: none; font-size: 13px; white-space: nowrap;
  text-transform: uppercase; letter-spacing: .05em; border-bottom: 2px solid transparent; }
.site-bar li a:hover { color: var(--p-text); }
.site-bar li a[aria-current="page"] { color: var(--p-text); border-bottom-color: var(--p-accent); }
.site-bar .sb-wrap { max-width: 1120px; margin: 0 auto; padding: 0 16px; }
.site-bar a:focus-visible { outline: 2px solid var(--p-accent); outline-offset: 3px; }
.site-bar ul { box-sizing: border-box; }
"""

PAGE_CSS = """
* { box-sizing: border-box; }
html, body { margin: 0; background: var(--p-bg); color: var(--p-text); }
body { font: 15px/1.6 var(--p-mono); -webkit-font-smoothing: antialiased;
  background-image: repeating-linear-gradient(0deg, rgba(77,255,143,.025) 0 1px, transparent 1px 3px); }
a { color: var(--p-accent); text-underline-offset: 3px; }
a:focus-visible, button:focus-visible { outline: 2px solid var(--p-accent); outline-offset: 3px; }
.wrap { max-width: 1120px; margin: 0 auto; padding: 0 16px; }
main { padding: 40px 0 72px; }
.hero { padding: 24px 0 8px; }
h1, h2, h3 { font-family: var(--p-pixel); font-weight: 400; letter-spacing: .04em; line-height: 1.25; }
h1 { font-size: clamp(28px, 5vw, 44px); margin: 0 0 12px; text-transform: uppercase; }
h2 { font-size: 22px; margin: 56px 0 12px; color: var(--p-accent); text-transform: uppercase; scroll-margin-top: 72px; }
h3 { font-size: 16px; margin: 32px 0 8px; text-transform: uppercase; scroll-margin-top: 72px; }
p { margin: 0 0 14px; max-width: 76ch; }
.lede { color: var(--p-text2); font-size: 16px; max-width: 70ch; }
.muted { color: var(--p-text2); }
code { font-family: var(--p-mono); background: var(--p-muted); padding: 1px 5px; border-radius: 2px; font-size: .92em; overflow-wrap: anywhere; }
td:first-child { white-space: nowrap; }
.log code { overflow-wrap: normal; }
pre { background: var(--p-surface); border: 1px solid var(--p-line); padding: 16px; overflow-x: auto; font-size: 12.5px; line-height: 1.45; }
.panel { background: var(--p-surface); border: 1px solid var(--p-line); padding: 20px; position: relative; }
.panel::before { content: ""; position: absolute; inset: 3px; border: 1px solid rgba(77,255,143,.08); pointer-events: none; }
.grid { display: grid; gap: 16px; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); }
.grid.two { grid-template-columns: repeat(auto-fill, minmax(min(100%, 420px), 1fr)); }
.stat b { display: block; font: 400 30px var(--p-pixel); color: var(--p-text); }
.stat span { font-size: 12px; text-transform: uppercase; letter-spacing: .08em; color: var(--p-text2); }
.card { display: block; text-decoration: none; color: inherit; }
.card:hover { border-color: var(--p-accent); }
.card h3 { margin: 0 0 6px; color: var(--p-accent); }
.card p { margin: 0; color: var(--p-text2); font-size: 14px; }
.table-wrap { overflow-x: auto; border: 1px solid var(--p-line); }
table { border-collapse: collapse; width: 100%; font-size: 13.5px; }
th, td { text-align: left; vertical-align: top; padding: 10px 12px; border-bottom: 1px solid var(--p-line); }
th { font-weight: 600; color: var(--p-text2); text-transform: uppercase; font-size: 11.5px; letter-spacing: .08em; background: var(--p-surface); position: sticky; top: 0; }
tr:last-child td { border-bottom: 0; }
td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
.narrow { max-width: 760px; }
.badge { display: inline-block; font: 400 11px var(--p-pixel); padding: 3px 6px 2px; letter-spacing: .06em; white-space: nowrap; }
.s-done { background: var(--p-accent); color: #06130B; }
.s-next { background: var(--p-amber); color: #1A1200; }
.s-todo { border: 1px solid var(--p-line); color: var(--p-text2); }
.s-wait { border: 1px solid var(--p-amber); color: var(--p-amber); }
.meter { height: 10px; background: var(--p-muted); display: flex; gap: 2px; padding: 2px; margin: 8px 0 4px; }
.meter i { flex: 1; background: rgba(77,255,143,.12); }
.meter i.on { background: var(--p-accent); }
.counts { color: var(--p-text2); font-size: 13px; }
.here td { background: rgba(77,255,143,.07); }
.here td:first-child { box-shadow: inset 3px 0 0 var(--p-accent); }
.kind { font-weight: 700; }
.yes { color: var(--p-accent); } .no { color: var(--p-text2); }
.formula { font-size: 15px; background: var(--p-surface); border-left: 3px solid var(--p-accent); padding: 12px 16px; margin: 0 0 16px; max-width: 76ch; }
.toc { display: flex; flex-wrap: wrap; gap: 8px 16px; padding: 0; list-style: none; margin: 16px 0 0; font-size: 13px; }
.shots { display: grid; gap: 24px; grid-template-columns: repeat(auto-fill, minmax(min(100%, 480px), 1fr)); }
figure { margin: 0; }
figure img { width: 100%; height: auto; display: block; border: 1px solid var(--p-line); background: var(--p-surface); }
figcaption { font-size: 13px; color: var(--p-text2); padding-top: 8px; }
.log { list-style: none; padding: 0; margin: 0; }
.log li { display: grid; grid-template-columns: 96px 76px 1fr; gap: 12px; padding: 12px 0; border-bottom: 1px solid var(--p-line); }
.log time, .log code { color: var(--p-text2); }
footer { border-top: 1px solid var(--p-line); padding: 24px 0 40px; color: var(--p-text2); font-size: 12.5px; }
@media (max-width: 640px) { .site-bar .brand small { display: none; } .log li { grid-template-columns: 1fr; gap: 2px; } main { padding-top: 24px; } }
"""


def bar(current):
    here = ' aria-current="page"'
    items = "".join(f'<li><a href="/{path}"{here if path == current else ""}>{e(name)}</a></li>' for path, name in PAGES)
    return (f'<div class="site-bar" role="banner"><div class="sb-wrap"><a class="brand" href="/">PULSE<small>docs</small></a>'
            f'<div class="sb-links" role="navigation" aria-label="Site"><ul>{items}</ul></div></div></div>')


def page(path, title, description, body):
    out = site / path / "index.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(title)} · Pulse docs</title><meta name="description" content="{e(description)}">
<link rel="stylesheet" href="/assets/site.css"><link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">
</head><body>{bar(path)}<main><div class="wrap">{body}</div></main>
<footer><div class="wrap">Generated from commit <code>{COMMIT}</code> ({COMMIT_DATE}) by <code>scripts/build-site.py</code>. Pulse is a working name.</div></footer>
</body></html>
""")


def inline(text):
    """Escape, then the little Markdown the roadmap tables use: code, bold, links shown as their text."""
    text = e(text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)


def compact(n):
    for size, suffix in ((1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")):
        if n >= size:
            v = n / size
            return (f"{v:.0f}" if v == int(v) else f"{v:.1f}") + suffix
    return str(int(n))


# ------------------------------------------------------------------------------------------------- roadmap progress

STATUS = {"✓": ("done", "Done"), "✔": ("done", "Done"), "▶": ("next", "In progress"), "○": ("todo", "Not started"),
          "⏸": ("wait", "Waiting")}


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
    return f'<span class="badge s-{status[0]}">{e(status[1])}</span>' if status else '<span class="badge s-todo">Planned</span>'


sections = roadmap_sections()
all_rows = [(t, h, r) for t, h, rows in sections for r in rows]
counted = [status_of(r[h.index("Status")]) for t, h, r in all_rows if "Status" in h]
done = sum(1 for s in counted if s and s[0] == "done")
planned_later = sum(len(rows) for t, h, rows in sections if "Status" not in h)
total = len(counted) + planned_later
current = [r for t, h, r in all_rows if "Status" in h and status_of(r[h.index("Status")]) and status_of(r[h.index("Status")])[0] == "next"]
upcoming = [r for t, h, r in all_rows if "Status" in h and status_of(r[h.index("Status")]) and status_of(r[h.index("Status")])[0] == "todo"]


def meter(n, of, cells=24):
    lit = round(cells * n / of) if of else 0
    return '<div class="meter" aria-hidden="true">' + "".join(f'<i class="{"on" if i < lit else ""}"></i>' for i in range(cells)) + "</div>"


progress_html = []
for title, header, rows in sections:
    keep = [i for i, h in enumerate(header) if h != "Founder input"]
    has_status = "Status" in header
    if has_status:
        statuses = [status_of(r[header.index("Status")]) for r in rows]
        n_done = sum(1 for s in statuses if s and s[0] == "done")
        summary = f'{meter(n_done, len(rows))}<p class="counts">{n_done} of {len(rows)} done</p>'
    else:
        summary = '<p class="counts">Sequenced; detail is written when the milestone before it closes.</p>'
    head = "".join(f"<th scope=\"col\">{e(header[i])}</th>" for i in keep)
    body_rows = []
    for r in rows:
        cells = []
        for i in keep:
            if header[i] == "Status":
                cells.append(f"<td>{badge(status_of(r[i]))}</td>")
            else:
                cells.append(f"<td>{inline(r[i]) if i < len(r) else ''}</td>")
        if not has_status:
            cells.insert(1, f"<td>{badge(None)}</td>")
        body_rows.append("<tr>" + "".join(cells) + "</tr>")
    if not has_status:
        head = head.replace("</th>", "</th><th scope=\"col\">Status</th>", 1)
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    progress_html.append(f'<h2 id="{slug}">{e(title)}</h2>{summary}'
                         f'<div class="table-wrap"><table><thead><tr>{head}</tr></thead><tbody>{"".join(body_rows)}</tbody></table></div>')

roadmap_text = (docs / "ROADMAP.md").read_text()
roadmap_map = re.search(r"## 2\. The map\s+```text\n(.*?)```", roadmap_text, re.S)

page("progress/", "Progress", "Every increment of Pulse with its status, how it is built and how it is proven.", f"""
<section class="hero"><h1>Progress</h1>
<p class="lede">Every increment, in build order, straight from the project roadmap. Each one names how it is built and the
evidence that proves it works; an increment is done only when that proof exists.</p>
{meter(done, total)}<p class="counts">{done} of {total} increments done · status key:
{badge(STATUS["✓"])} {badge(STATUS["▶"])} {badge(STATUS["○"])} {badge(STATUS["⏸"])}</p></section>
<h2 id="map">The map</h2><pre>{e(roadmap_map.group(1)) if roadmap_map else ""}</pre>
{"".join(progress_html)}
""")

# ----------------------------------------------------------------------------------------------------------- metrics

# Mirrors ModelLevel.targets in Sources/PulseApp/Views/Details/ModelsSection.swift (a test there pins the same list).
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

page("metrics/", "Metrics", "How Pulse defines every number it shows: limits, pace, tokens, levels, specialty, calendars and charts.", f"""
<section class="hero"><h1>Metrics</h1>
<p class="lede">How every number in Pulse is defined, where it comes from, and what it does not mean. These rules are the
code's rules; each section names the file that implements it.</p>
<ul class="toc"><li><a href="#sources">Sources</a></li><li><a href="#tokens">Tokens</a></li><li><a href="#levels">Levels</a></li>
<li><a href="#rank">Rank and specialty</a></li><li><a href="#agents">Agents per task</a></li><li><a href="#limits">Limits and pace</a></li><li><a href="#session">Session</a></li>
<li><a href="#calendar">Calendar</a></li><li><a href="#charts">Charts</a></li></ul></section>

<h2 id="sources">Where the numbers come from</h2>
<div class="table-wrap"><table><thead><tr><th>Source</th><th>What it gives</th><th>How fresh</th><th>Kept by Pulse</th></tr></thead><tbody>
<tr><td>Claude Code status line</td><td>5-hour and 7-day usage with reset times, current model, context window, session cost estimate, durations, lines changed, prompt-cache counts</td><td>Every status refresh while Claude Code runs</td><td>Yes, on this Mac only, after an allowlist removes everything else (paths, prompts, ids)</td></tr>
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
<p>Why output: it is what the model produced. Total tokens are dominated by cache reads, so a long conversation would
level a model up without it doing more. Why fixed 1-2-5 targets: every next target is a round number you can read, and
each level asks for 2 to 2.5 times the output of the one before, so levels keep meaning something at any scale.</p>
<h3>Worked example: why “18.2M of 20M output” is progress to LV 15</h3>
<p>A model has written {compact(ex_out)} output tokens. The highest target reached is {compact(ex_floor)}, the 13th target,
so it is <strong>LV {ex_lv}</strong>. The next target is {compact(ex_next)}, which makes LV {ex_lv + 1}. The bar on its card
runs from {compact(ex_floor)} to {compact(ex_next)}: ({compact(ex_out)} − {compact(ex_floor)}) ÷ ({compact(ex_next)} − {compact(ex_floor)}) = {ex_pct}%,
with {compact(ex_next - ex_out)} to go.</p>
<h3>The ladder</h3>
<div class="table-wrap narrow"><table><thead><tr><th>Level</th><th class="num">Output reached</th><th class="num">Next level at</th><th class="num">Output in this level</th></tr></thead>
<tbody>{"".join(ladder_rows)}</tbody></table></div>
<p class="muted">The ladder continues the same way past LV 25. Source: <code>ModelLevel</code> in <code>Sources/PulseApp/Views/Details/ModelsSection.swift</code>;
the app shows the same table under “How levels work” in Stats › Models › Arena. On 30-day and 7-day ranges, levels still
use all-time output, because Claude Code records tokens by kind for all time only.</p>

<h2 id="rank">Rank and specialty</h2>
<p><strong>Rank</strong>: by level, then by output, then by total tokens. A higher rank never has a lower level.</p>
<p class="formula">Specialty ratio for a kind = (model's tokens of that kind ÷ model's total) ÷ (all models' tokens of that kind ÷ all models' total)</p>
<p>The specialty is the kind with the highest ratio, shown as, for example, “Reading input · 13× the party”: that model's
share of input is 13 times the share across all models. If no kind reaches 1.1×, the model is an <strong>All-rounder</strong>.
Every model mostly reads from cache, so the plain largest kind would say the same thing on every card; the ratio shows how
each one differs. Source: <code>ModelSpecialty</code>.</p>

<h2 id="agents">Agents per task</h2>
<p>Optional, off until you turn it on in Settings › Providers. A <strong>task</strong> is one prompt: from the moment you send
it until Claude stops. Pulse adds four background hooks to Claude Code (prompt submitted, subagent started, subagent stopped,
Claude stopped) and counts the subagents each task starts, nested ones included.</p>
<div class="table-wrap"><table><thead><tr><th>Figure</th><th>Meaning</th></tr></thead><tbody>
<tr><td>Agents</td><td>Subagents started during the task. Each one counts once, matched by a hashed id, even if its events arrive out of order.</td></tr>
<tr><td>Types</td><td>Claude Code's built-in types by name (Explore, Plan, General, Guide, Status line). Your own and plugin agents count as Custom; their names are never sent.</td></tr>
<tr><td>Finished</td><td>Subagents that reported stopping. Background subagents can finish after the task ends.</td></tr>
<tr><td>Running</td><td>No stop seen yet, and the task started under six hours ago.</td></tr>
<tr><td>Used agents</td><td>Share of the last 30 days' tasks that started at least one subagent.</td></tr>
<tr><td>Agents per task</td><td>All subagents in 30 days ÷ all tasks in 30 days, tasks without subagents included.</td></tr>
</tbody></table></div>
<p class="muted">Claude Code hands every hook the whole event, your prompt included. The helper keeps only the event name,
hashed session and agent ids and the type, and drops the rest before anything leaves it. Source: <code>HookFrame</code>,
<code>Store.record</code>.</p>

<h2 id="limits">Limits and the pace estimate</h2>
<div class="table-wrap"><table><thead><tr><th>State</th><th>When</th></tr></thead><tbody>
<tr><td>Available</td><td>Under 80% used</td></tr><tr><td>Approaching limit</td><td>80% or more</td></tr>
<tr><td>Nearly exhausted</td><td>95% or more</td></tr><tr><td>Limit reached</td><td>100%</td></tr>
<tr><td>Reset expected</td><td>The reset time has passed but no fresh reading has confirmed it. Pulse never says “ready” without one.</td></tr>
<tr><td>Stale</td><td>No reading recently; the last value is shown as “last seen” with its age.</td></tr>
</tbody></table></div>
<p class="muted">A state clears only after usage drops 3 points below its threshold, so it does not flicker. Source: <code>EngineConfig</code> in <code>Sources/UsageEngine/PoolReducer.swift</code>.</p>
<p><strong>Pace estimate</strong> (always labelled “Estimate”): a straight line fitted by least squares through recent readings in
the current window: the last 90 minutes for the 5-hour limit, the last 24 hours for the 7-day limit. It needs at least 3
readings over at least 10 minutes. Below 0.5 points per hour usage counts as flat (“not rising”). It never looks further ahead
than 8 times the history it rests on, so an hour of readings cannot predict two days. If the window resets before the line
reaches 100%, it says roughly how much will be used by the reset. Source: <code>PaceEstimate</code> in <code>Sources/UsageEngine/Pace.swift</code>.</p>
<p>The Limits chart spans the limit's own window, from reset minus its length to the reset. The hatched span before the first
reading is time Pulse was not yet watching.</p>

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
<p>Each square is a day. Shading is by messages that day, in quarters of your active days: the quietest quarter is the
faintest green, the busiest quarter the brightest. A day with no messages is dark; a day before your first session or after
today is an outline marked “no data”. All time shows one calendar year (January to December) with a year switcher;
30 days shows a month calendar; 7 days shows a column per day. Source: <code>StatsCalendar</code> and <code>StatsSummary</code>.</p>

<h2 id="charts">Charts</h2>
<p>Tokens per day are stacked by model on a real date axis: days with nothing stay on the axis. Past 120 days the bars become
weeks. The scale's top is the first round number at or above the tallest bar whose quarters are also round (for example
8M for a 6.5M peak). Models differ by colour and fill pattern, never colour alone. Point at a bar for its numbers.</p>
""")

# ------------------------------------------------------------------------------------------------------ architecture

arch = (docs / "ARCHITECTURE.md").read_text()
flow = re.search(r"## 6\. Data flow\s+```text\n(.*?)```", arch, re.S)

page("architecture/", "Architecture", "How Pulse is put together: processes, data flow, modules and quality gates.", f"""
<section class="hero"><h1>Architecture</h1>
<p class="lede">A native macOS menu bar app (Swift 6, SwiftUI) that reads what Claude Code already reports about itself, on your
Mac, with no account, no server and no network code.</p></section>

<h2 id="processes">Processes</h2>
<div class="table-wrap"><table><thead><tr><th>Process</th><th>Role</th></tr></thead><tbody>
<tr><td><code>Pulse.app</code></td><td>The menu bar app. Listens on a local socket, keeps readings in a local database, works out each limit's state and shows it.</td></tr>
<tr><td><code>pulse-statusline</code></td><td>A small signed helper inside the app that Claude Code runs on every status refresh. It passes the input to your own status line unchanged, keeps only allowlisted fields and sends them to the app.</td></tr>
<tr><td><code>hook.sh</code> (optional)</td><td>Installed only when you turn on agents per task. Claude Code runs it in the background on four events; it runs the helper in hook mode, which sends counts only and always exits silently, so it can never block or change what Claude Code does.</td></tr>
<tr><td><code>statusline.sh</code></td><td>The installed command. Runs the helper if the app is there, otherwise your original status line, so removing the app never breaks Claude Code.</td></tr>
</tbody></table></div>

<h2 id="flow">Data flow</h2>
<pre>{e(flow.group(1)) if flow else ""}</pre>

<h2 id="modules">Modules</h2>
<div class="table-wrap"><table><thead><tr><th>Module</th><th>Responsibility</th></tr></thead><tbody>
<tr><td><code>Domain</code></td><td>Values that carry where they came from and how fresh they are, so a missing number can never show as 0%.</td></tr>
<tr><td><code>ShimProtocol</code> · <code>StatusLineShim</code></td><td>The frame format and the allowlist; the helper's logic.</td></tr>
<tr><td><code>ClaudeCodeAdapter</code></td><td>Socket ingest, mapping frames to readings, the settings installer, the statistics-file reader.</td></tr>
<tr><td><code>UsageEngine</code></td><td>Pure rules: limit states, windows, freshness, the pace estimate.</td></tr>
<tr><td><code>Storage</code></td><td>SQLite (GRDB): one writer, a ledger of readings, migrations with a backup first, retention.</td></tr>
<tr><td><code>DesignSystem</code></td><td>Tokens, themes (Phosphor), pixel components, accessibility formatting.</td></tr>
<tr><td><code>PulseApp</code></td><td>The app: popover, Details window, Stats, settings, onboarding, diagnostics.</td></tr>
<tr><td><code>SubscriptionCatalog</code></td><td>Plan names, never used to infer usage.</td></tr>
</tbody></table></div>

<h2 id="principles">Principles</h2>
<div class="grid two">
<div class="panel"><h3>Local only</h3><p class="muted">No networking code in the app or helper; a CI gate checks the binaries' linked frameworks.</p></div>
<div class="panel"><h3>Allowlist at the source</h3><p class="muted">The helper drops everything not on the allowlist before sending, so the app cannot receive what it must not keep.</p></div>
<div class="panel"><h3>Absent is not zero</h3><p class="muted">A limit the source did not report is shown in words with an empty outlined bar, never as 0%.</p></div>
<div class="panel"><h3>Reversible</h3><p class="muted">Installing into Claude Code backs up your settings; uninstalling and delete-all restore them byte for byte.</p></div>
</div>

<h2 id="quality">Quality gates</h2>
<p>One command, <code>make ci</code>, runs every gate and must pass before each increment is committed:</p>
<div class="table-wrap"><table><thead><tr><th>Gate</th><th>What it checks</th></tr></thead><tbody>
<tr><td>Toolchain pinned</td><td>The expected Swift version.</td></tr><tr><td>Strict build</td><td>Warnings are errors; Swift 6 strict concurrency.</td></tr>
<tr><td>Tests</td><td>The full suite (Swift Testing).</td></tr><tr><td>Helper links no networking</td><td>The helper binary links no networking frameworks.</td></tr>
<tr><td>No networking code</td><td>No networking APIs in the sources.</td></tr><tr><td>Clock injected</td><td>Logic reads time through an injected clock, so tests control it.</td></tr>
<tr><td>Design tokens only</td><td>Views use theme tokens, never literal colours or sizes.</td></tr><tr><td>Redaction audit</td><td>Logs and exports contain no fields outside the allowlist.</td></tr>
<tr><td>Secret scan</td><td>No credentials in the repository.</td></tr><tr><td>App bundle</td><td>Signature, embedded helper, entitlements.</td></tr>
</tbody></table></div>
""")

# ----------------------------------------------------------------------------------------------------------- privacy

page("privacy/", "Privacy", "What Pulse reads, what it keeps on your Mac, and what it uploads if you sign in.", """
<section class="hero"><h1>Privacy</h1>
<p class="lede">Pulse works fully on your Mac without an account. If you choose to sign in, it uploads daily counts so you can see your
goals and usage elsewhere. This page lists every field. Draft, 17 October 2026.</p></section>

<h2 id="mac">On your Mac</h2>
<p>Pulse reads Claude Code's status line (limits, model, context, session cost estimate, durations, lines changed), and, only if you turn them
on, Claude Code's statistics file and four background hooks that count subagents per task. A helper drops everything else (prompts, replies,
file paths, project names) before anything reaches the app. Readings stay in a local database for 90 days (sessions and tasks 30).
Delete all removes everything Pulse stored and restores Claude Code's settings.</p>

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
<p><strong>Never uploaded:</strong> prompts, replies, file or folder paths, project or repository names, transcript locations, session or agent
ids, per-session cost, your Claude account details or anything about other apps.</p>

<h2 id="account">Your account</h2>
<p>Sign-in is by email link (Apple, Google and GitHub to follow). Your email is held by the sign-in service to send links; it is not stored
with your counts. <strong>Delete account</strong> (Pulse › Account) deletes the account and every row stored with it, at once. Signing out
stops uploads; deleting the account removes what was uploaded. Nothing is sold or shared, and there is no advertising or tracking.</p>

<h2 id="security">Security</h2>
<p>Every table is protected by row-level security: a signed-in user can read and write only their own rows, and an anonymous request is
refused. The app holds only the project's publishable key; your session is kept in this Mac's Keychain.</p>
""")

# ----------------------------------------------------------------------------------------------------------- screens

CAPTIONS = {
    "details-home": ("Home", "A greeting, the running total, both limits, the latest task, goals at a glance and the last 12 months."),
    "details-card": ("Stats › Card", "The player card: name, first session, plan, milestone stamps, output total, named level; copy, save or share."),
    "details-goals": ("Goals", "Active days a week, the 5-hour peak and the week's finish, each with its state in words and its target."),
    "details-account": ("Account", "Your year, your profile and plan, and where sign-in will go."),
    "details-settings": ("Settings", "Settings in the window, as rows with a line of explanation each."),
    "popover-overview": ("Menu bar popover", "Limits with state, reset and pace estimate; the current session; links to Details and Stats."),
    "popover-detail": ("Provider detail", "Plan, both limits and the session in more depth."),
    "popover-inspector": ("Provenance inspector", "Where a number came from and how fresh it is."),
    "details-limits": ("Details › Limits", "Each limit over its own window: scale, threshold bands, NOW, the span before readings, the pace estimate."),
    "details-session": ("Details › Session", "The current session in full, recent sessions, and sessions by model."),
    "details-stats-overview": ("Stats › Overview, all time", "A January–December activity calendar with a year switcher, tiles, hours and tokens by kind."),
    "details-stats-overview-30": ("Stats › Overview, 30 days", "A month calendar with message counts beside tokens per day."),
    "details-stats-overview-7": ("Stats › Overview, 7 days", "A column per day: messages, sessions and tokens."),
    "details-stats-models": ("Stats › Models, chart", "Tokens per week stacked by model on a real date axis."),
    "details-stats-arena": ("Stats › Models, arena", "A pixel character per model: level from output, specialty, tokens by kind."),
    "details-stats-arena-tall": ("Stats › Models, how levels work", "The level ladder with each model placed on it, and what each kind of token means."),
    "onboarding-3-consent": ("Onboarding consent", "What Pulse reads and keeps, before anything is installed."),
    "settings-diagnostics": ("Settings › Diagnostics", "Redacted log, export and delete-all."),
    "settings-delete-all-sheet": ("Delete all", "Removes Pulse's data and restores Claude Code's settings."),
}
(site / "screens" / "img").mkdir(parents=True, exist_ok=True)
figures = []
for name in CAPTIONS:
    src = screens / f"{name}.png"
    if not src.exists():
        continue
    shutil.copy(src, site / "screens" / "img" / src.name)
    title, note = CAPTIONS[name]
    figures.append(f'<figure><a href="img/{src.name}"><img src="img/{src.name}" alt="{e(title)}: {e(note)}" loading="lazy"></a>'
                   f'<figcaption><strong>{e(title)}</strong>. {e(note)}</figcaption></figure>')

page("screens/", "Screens", "Screenshots of the running Pulse app with demo data.", f"""
<section class="hero"><h1>Screens</h1>
<p class="lede">The running app, captured by its own debug probe with demo data and a synthetic statistics file. Nothing here is
a real account. Select a screen to open it full size.</p></section>
<div class="shots">{"".join(figures)}</div>
""")

# --------------------------------------------------------------------------------------------------------- changelog

log = [line.split("\t", 2) for line in git("log", "--pretty=%ad\t%h\t%s", "--date=short").splitlines()]
items = "".join(f'<li><time datetime="{e(d)}">{e(d)}</time><code>{e(h)}</code><span>{e(s)}</span></li>' for d, h, s in log)
page("changelog/", "Changelog", "Every commit to Pulse, newest first.", f"""
<section class="hero"><h1>Changelog</h1>
<p class="lede">Every commit, newest first. Each one passed all {10} quality gates before it was pushed.</p></section>
<ul class="log">{items}</ul>
""")

# ---------------------------------------------------------------------------------------------------------- overview

now_rows = "".join(f"<tr><td>{inline(r[0])}</td><td>{badge(status_of(r[1]))}</td><td>{inline(r[2])}</td></tr>"
                   for r in (current + upcoming)[:4])
recent = "".join(f'<li><time datetime="{e(d)}">{e(d)}</time><code>{e(h)}</code><span>{e(s)}</span></li>' for d, h, s in log[:5])
hero_shot = "details-stats-arena" if (screens / "details-stats-arena.png").exists() else "popover-overview"
page("", "Overview", "Technical documentation and progress for Pulse, a macOS menu bar monitor for AI usage limits.", f"""
<section class="hero"><h1>Pulse</h1>
<p class="lede">A macOS menu bar app that shows how much of your Claude Code limits you have used, when they reset and how
fast you are going, from what Claude Code reports on your own Mac. These pages document how it is built, what every number
means and where the work stands.</p></section>
<div class="grid" style="margin-top:28px">
<div class="panel stat"><b>{done}/{total}</b><span>Increments done</span>{meter(done, total)}</div>
<div class="panel stat"><b>{len(log)}</b><span>Commits</span></div>
<div class="panel stat"><b>10</b><span>Quality gates per commit</span></div>
<div class="panel stat"><b>0</b><span>Network calls</span></div>
</div>
<h2 id="now">Now and next</h2>
<div class="table-wrap"><table><thead><tr><th>#</th><th>Status</th><th>Increment</th></tr></thead><tbody>{now_rows}</tbody></table></div>
<p style="margin-top:12px"><a href="/progress/">All increments →</a></p>
<h2 id="explore">Explore</h2>
<div class="grid">
<a class="panel card" href="/metrics/"><h3>Metrics</h3><p>Every number defined: tokens, levels, rank, limits, pace, calendars.</p></a>
<a class="panel card" href="/progress/"><h3>Progress</h3><p>Each increment, how it is built and how it is proven.</p></a>
<a class="panel card" href="/architecture/"><h3>Architecture</h3><p>Processes, data flow, modules and quality gates.</p></a>
<a class="panel card" href="/screens/"><h3>Screens</h3><p>The running app, with demo data.</p></a>
<a class="panel card" href="/design-system/"><h3>Design system</h3><p>Tokens, themes and components, rendered from the Swift code.</p></a>
<a class="panel card" href="/changelog/"><h3>Changelog</h3><p>Every commit, newest first.</p></a>
</div>
<h2 id="look">A look</h2>
<figure><img src="/screens/img/{hero_shot}.png" alt="Stats › Models arena: a pixel character per model with level and tokens by kind" loading="lazy">
<figcaption>Stats › Models › Arena, with demo data. <a href="/screens/">More screens →</a></figcaption></figure>
<h2 id="recent">Recent changes</h2><ul class="log">{recent}</ul>
""")

# ------------------------------------------------------------------------------------------- shared assets and design

assets = site / "assets"
(assets / "fonts").mkdir(parents=True, exist_ok=True)
(assets / "bar.css").write_text(BAR_CSS)
(assets / "site.css").write_text(BAR_CSS + PAGE_CSS)
fonts = repo / "Sources/DesignSystem/Resources/Fonts"
for name in ("Silkscreen-Regular.ttf", "Silkscreen-Bold.ttf", "Silkscreen-OFL.txt"):
    shutil.copy(fonts / name, assets / "fonts" / name)
(assets / "favicon.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><rect width="16" height="16" fill="#060907"/>'
                                    '<path d="M2 9h3l2-5 2 9 2-6 1 2h2" fill="none" stroke="#4DFF8F" stroke-width="1.6" stroke-linejoin="miter"/></svg>')

design_page = site / "design-system" / "index.html"
if design_page.exists():
    text = design_page.read_text()
    if "site-bar" not in text:
        # Only the bar's own stylesheet: the design page keeps its light and dark themes; its sticky nav sits under the bar.
        text = text.replace("</head>", '<link rel="stylesheet" href="/assets/bar.css"><link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">'
                            '<style>.site-bar ~ nav{top:57px}</style></head>', 1)
        text = re.sub(r"<body([^>]*)>", lambda m: f"<body{m.group(1)}>{bar('design-system/')}", text, count=1)
        design_page.write_text(text)

(site / "404.html").write_text(f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Not found · Pulse docs</title><link rel="stylesheet" href="/assets/site.css"></head><body>{bar("")}
<main><div class="wrap"><h1>Not found</h1><p class="lede">That page doesn't exist. <a href="/">Back to the overview</a>.</p></div></main></body></html>
""")
print(f"site: {len(PAGES)} pages, {len(figures)} screens, {done}/{total} increments done, commit {COMMIT}")
