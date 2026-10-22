"""Build the product landing page and original character artwork from reviewed local sources.

Also called by build-site.py after the documentation build. No private planning documents or credentials
are read here. Re-running this command is idempotent and preserves the documentation landing page.
"""
import json
import re
import shutil
import sys
from pathlib import Path


def build(site, release_tag):
    site = Path(site)
    if not re.fullmatch(r"v\d+\.\d+\.\d+-(?:alpha|beta)\.\d+", release_tag):
        raise ValueError("Expected a reviewed release tag")
    repo = Path(__file__).resolve().parent.parent
    source = repo / "scripts/site"
    old_home = site / "index.html"
    documentation = site / "docs/index.html"
    if "data-public-home" not in old_home.read_text():
        documentation.parent.mkdir(exist_ok=True)
        shutil.copy2(old_home, documentation)
    if not documentation.exists():
        raise ValueError("Build the documentation landing page before the public site")

    release_url = "https://github.com/obileonardo/clepso/releases/tag/" + release_tag
    download_url = ("https://github.com/obileonardo/clepso/releases/download/" + release_tag
                    + "/Clepso-" + release_tag[1:] + ".dmg")
    doc_text = documentation.read_text()
    doc_text = re.sub(r'<a class="dl-btn" href="https://github.com/obileonardo/clepso/releases/tag/v[^\"]+">Download [^<]+</a>',
                      '<a class="dl-btn" href="' + release_url + '">Download ' + release_tag + '</a>', doc_text)
    documentation.write_text(doc_text)
    logo = (repo / "design/brand/favicon/favicon.svg").read_text().strip().replace("<svg ", '<svg aria-hidden="true" ', 1)
    text = (source / "home.html").read_text()
    for key, value in {"LOGO": logo, "DOWNLOAD_URL": download_url, "RELEASE_URL": release_url,
                       "RELEASE_TAG": release_tag, "RELEASE_LABEL": release_tag[1:].replace("-alpha.", " alpha ").replace("-beta.", " beta ")}.items():
        text = text.replace("@" + key + "@", value)
    old_home.write_text(text)
    for name in ["public.css", "home.js"]:
        shutil.copy2(source / name, site / "assets" / name)
    shutil.copytree(source / "characters", site / "characters", dirs_exist_ok=True)
    (site / "characters/notes.html").write_text("""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>About the artwork · Clepso</title>
<link rel="stylesheet" href="style.css"><link rel="icon" href="/favicon.ico"></head><body>
<header><a class="brand" href="/">CLEPSO</a><a href="/characters/">Back to the characters</a></header>
<main style="padding-top:56px;max-width:900px"><h1 style="font-size:48px">About the artwork.</h1>
<p>The literary guild is original Clepso pixel art inspired by the creative-work names Opus, Fable, Sonnet and Haiku.
The owl maestro, fox storyteller, poet and paper crane are our interpretations. They are not official provider mascots.</p>
<p>These characters ship in the Mac Models screen from 0.3.0 alpha 3 onward. The old 12 × 12 drawings remain on this page for comparison.
Edition details identify a model version; Clepso’s usage-based levels remain separate.</p>
<p>The drawings use an integer pixel grid, a consistent foot anchor and a restrained palette. Only the selected
portrait moves. Pause and Reduce Motion controls are available; model data is not needed to explore this page. From 0.4.0 alpha 1, a native flourish marks newly crossed output levels while viewing a model. The website’s button remains a demonstration and does not change usage.</p>
<h2>Sources behind the names</h2><p><a href="https://www.merriam-webster.com/dictionary/opus">Opus</a> ·
<a href="https://www.merriam-webster.com/dictionary/fable">Fable</a> ·
<a href="https://www.poetryfoundation.org/education/glossary/sonnet">Sonnet</a> ·
<a href="https://www.poetryfoundation.org/education/glossary/haiku-or-hokku">Haiku</a></p>
<p class="small">Original procedural drawings: scripts/site/characters/sprites.js in the Clepso source repository.
Typography uses Clepso’s existing fonts and their accompanying open font license.</p></main></body></html>""")

    # Make the new art page discoverable in existing static docs as well as future generated shells.
    for page in sorted(site.rglob("*.html")):
        if page == old_home or "characters" in page.relative_to(site).parts:
            continue
        content = page.read_text()
        if 'class="px-head"' in content and 'href="/characters/"' not in content:
            content = content.replace('<div class="px-pill" role="navigation" aria-label="Main">',
                                      '<div class="px-pill" role="navigation" aria-label="Main"><a href="/characters/">Characters</a>', 1)
            content = content.replace('<p class="px-menu-group">[ Project ]</p>',
                                      '<p class="px-menu-group">[ Project ]</p><a href="/characters/"><span>Art</span><b>Characters</b><i aria-hidden="true">→</i></a>', 1)
            content = content.replace('<a href="/design-system/">Design system</a></li>',
                                      '<a href="/design-system/">Design system</a></li><li><a href="/characters/">Characters</a></li>', 1)
            page.write_text(content)
    index = site / "assets/search.json"
    entries = json.loads(index.read_text())
    for entry in entries:
        if entry.get("u", "").startswith("/#"):
            entry["u"] = "/docs/" + entry["u"][1:]
    for title, url, description in [("Characters", "/characters/", "The literary guild: original pixel model characters and animations."),
                                    ("Documentation", "/docs/", "Explore Clepso’s usage rules, screens, architecture and progress.")]:
        if not any(entry.get("u") == url for entry in entries):
            entries.append({"t": title, "p": "Page", "u": url, "x": description, "top": True})
    index.write_text(json.dumps(entries, ensure_ascii=False, separators=(",", ":")) + "\n")
    changelog = site / "changelog/index.html"
    content = changelog.read_text()
    if release_tag not in content:
        content = content.replace("Current release ·", "Previous release ·", 1)
        card = ('<div class="release"><div><p class="eyebrow">Current release · <b>' + release_tag
                + '</b></p><h2>A little more character.</h2><p>The literary guild now appears in the Mac Models screen, with distinct editions and quiet authored motion.</p>'
                + '<p>Explore the <a href="/characters/">characters</a>. Pause and Reduce Motion controls keep the selected portrait quiet when you need it.</p>'
                + '<p><a href="' + release_url + '">Download and release notes</a></p></div></div>')
        content = content.replace('<div class="release">', card + '<div class="release">', 1)
        changelog.write_text(content)
    print("Public site: product landing, preserved docs, characters and search links built for " + release_tag)


if __name__ == "__main__":
    build(Path(sys.argv[1]), sys.argv[2])
