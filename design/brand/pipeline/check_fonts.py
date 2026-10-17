"""Checks every built font: required characters, names, metrics and outlines. Exit 1 on any failure.
Usage: python check_fonts.py [fonts dir]"""
import sys
from pathlib import Path

from fontTools.pens.areaPen import AreaPen
from fontTools.ttLib import TTFont

REQUIRED = ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
            "%·×−+/:;,.…'\"()[]→←↑↓⌘#@&*!?-–—‘’“” ")
FORBIDDEN_NAMES = ("silkscreen", "pixelify", "vt323")       # Reserved Font Names of the OFL faces bundled before


def check(path):
    errors = []
    f = TTFont(str(path))
    cmap = f.getBestCmap()
    missing = [c for c in REQUIRED if ord(c) not in cmap]
    if missing:
        errors.append(f"missing characters: {''.join(missing)!r}")
    names = " ".join(r.toUnicode() for r in f["name"].names).lower()
    for bad in FORBIDDEN_NAMES:
        if bad in names:
            errors.append(f"name table mentions {bad}")
    os2, hhea, head = f["OS/2"], f["hhea"], f["head"]
    if (os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap) != (hhea.ascent, hhea.descent, hhea.lineGap):
        errors.append("typo and hhea metrics differ")
    if os2.usWinAscent != hhea.ascent or os2.usWinDescent != -hhea.descent:
        errors.append("win and hhea metrics differ")
    if not os2.fsSelection & (1 << 7):
        errors.append("USE_TYPO_METRICS not set")
    gs = f.getGlyphSet()
    if head.yMax > os2.usWinAscent or -head.yMin > os2.usWinDescent:
        errors.append(f"glyphs exceed win metrics (yMax {head.yMax}, yMin {head.yMin})")
    if "Mono" in path.name:
        widths = {f["hmtx"][n][0] for n in f.getGlyphOrder()}
        if widths != {600}:
            errors.append(f"monospace advances vary: {sorted(widths)}")
        if not f["post"].isFixedPitch:
            errors.append("post.isFixedPitch not set")
    else:
        digits = {f["hmtx"][cmap[ord(c)]][0] for c in "0123456789"}
        if len(digits) != 1:
            errors.append(f"figures are not tabular: {digits}")
    # outer contours: clockwise in TrueType, counter-clockwise in CFF
    cff = "CFF " in f
    for name in ("O", "o", "zero", "B"):
        pen = AreaPen(gs)
        gs[name].draw(pen)
        if (pen.value > 0) != cff:
            errors.append(f"{name}: contour direction wrong for {'CFF' if cff else 'TrueType'}")
    return errors, len(cmap)


if __name__ == "__main__":
    folder = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "fonts")
    failed = False
    for p in sorted(folder.glob("*.[to]tf")):
        errs, n = check(p)
        print(f"{'FAIL' if errs else 'ok  '} {p.name}: {n} characters" + "".join(f"\n     - {e}" for e in errs))
        failed |= bool(errs)
    sys.exit(1 if failed else 0)
