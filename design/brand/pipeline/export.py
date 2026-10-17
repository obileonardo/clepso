"""Writes design/brand/brand.json: everything the design-system page needs to draw the identity itself (pixel
matrices as rows of '#'), so scripts/build-design-site.py stays standard-library only."""
import json
from pathlib import Path

from fontTools.ttLib import TTFont

import logo
import sheets
from type_system import APP, FAMILIES, WEB

BRAND = Path(__file__).resolve().parent.parent


def rows(cells_, w=16, h=16):
    return ["".join("#" if (x, y) in cells_ else "." for x in range(w)) for y in range(h)]


def font_facts():
    out = []
    for path in sorted((BRAND / "fonts").glob("*.ttf")):
        f = TTFont(str(path))
        name = f["name"]
        out.append({"file": path.stem, "family": name.getDebugName(1), "style": name.getDebugName(2),
                    "postscript": name.getDebugName(6), "weight": f["OS/2"].usWeightClass,
                    "characters": len([c for c in f.getBestCmap() if c > 32]), "version": name.getDebugName(5)})
    return out


def build(out=BRAND / "brand.json"):
    data = {
        "grid": {"unit": "p", "symbol": 16, "small": 12, "tracking": logo.TRACKING, "lockupGap": logo.LOCKUP_GAP,
                 "stackGap": logo.STACK_GAP, "wordTop": logo.WORD_TOP, "clear": logo.CLEAR},
        "symbol": logo.SYMBOL,
        "symbolSmall": logo.SYMBOL_SMALL,
        "ring": logo.RING_ONLY,
        "wordmark": logo.WORDMARK,
        "colours": logo.COLOURS,
        "explorations": [{"code": c, "name": n, "rows": rows(on), "verdict": v, "chosen": c == "F"}
                         for c, n, on, v in sheets.exploration_marks()],
        "refinements": [{"code": c, "name": n, "rows": rows(on), "note": v, "chosen": c == "F4"}
                        for c, n, on, v in sheets.refinement_marks()],
        "states": [{"key": k, "label": label, "rows": rows(on)} for k, (label, on) in logo.menubar_states().items()],
        "type": {"families": FAMILIES,
                 "app": [dict(zip(("token", "face", "weight", "size", "lineHeight", "tracking", "case", "use", "replaces"), r)) for r in APP],
                 "web": [dict(zip(("token", "face", "weight", "size", "lineHeight", "tracking", "case", "use"), r)) for r in WEB]},
        "fonts": font_facts(),
    }
    out.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n")
    return out
