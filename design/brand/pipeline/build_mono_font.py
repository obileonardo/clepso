"""Builds Pulse Mono Regular, Medium and Bold (TTF, OTF, WOFF2). Usage: python build_mono_font.py <out dir>"""
import sys
from pathlib import Path

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.areaPen import AreaPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.reverseContourPen import ReverseContourPen
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.ttGlyphPen import TTGlyphPen

import fontmeta
import mono_glyphs as M
from build_pixel_font import glyph_name
from geom import union
from pixel_glyphs import ACCENTED

FAMILY = "Pulse Mono"
PS = "PulseMono"
WEIGHTS = {"Regular": (400, 90, 76), "Medium": (500, 110, 92), "Bold": (700, 140, 116)}


def outer_is_clockwise(path):
    """True when the path's largest contour runs clockwise (y-up), the TrueType convention."""
    rec = RecordingPen()
    path.draw(rec)
    contours, cur = [], []
    for op, args in rec.value:
        cur.append((op, args))
        if op in ("closePath", "endPath"):
            contours.append(cur)
            cur = []
    best = 0
    for c in contours:
        ap = AreaPen()
        for op, args in c:
            getattr(ap, op)(*args)
        if abs(ap.value) > abs(best):
            best = ap.value
    return best < 0           # AreaPen: positive = counter-clockwise


def build_weight(style, weight, wv, wh, out_dir):
    m = M.Mono(wv, wh)
    mk = M.marks(m)
    shapes = dict(m.glyphs)
    for ch, (base, accent) in ACCENTED.items():
        if base not in shapes or shapes[base] is None:
            continue
        case = "uc" if base.isupper() else "lc"
        shapes[ch] = union(shapes[base], mk[(accent, case)])
    order = [".notdef"]
    cmap = {}
    from geom import ring as _ring
    notdef = _ring(80, 0, 520, M.CAP, 0, 60, 60, "")
    paths = {".notdef": notdef}
    for ch in sorted(shapes, key=ord):
        name = "space" if ch == " " else glyph_name(ch)
        order.append(name)
        cmap[ord(ch)] = name
        paths[name] = shapes[ch]

    files = {}
    for flavour in ("ttf", "otf"):
        fb = FontBuilder(1000, isTTF=flavour == "ttf")
        fb.setupGlyphOrder(order)
        fb.setupCharacterMap(cmap)
        metrics = {}
        if flavour == "ttf":
            glyphs = {}
            for name in order:
                pen = TTGlyphPen(None)
                p = paths[name]
                if p is not None:
                    reverse = not outer_is_clockwise(p)
                    p.draw(Cu2QuPen(pen, max_err=0.6, reverse_direction=reverse))
                glyphs[name] = pen.glyph()
            fb.setupGlyf(glyphs)
            for name in order:
                g = glyphs[name]
                metrics[name] = (M.ADV, g.xMin if getattr(g, "numberOfContours", 0) else 0)
        else:
            charstrings = {}
            for name in order:
                pen = T2CharStringPen(M.ADV, None)
                p = paths[name]
                if p is not None:
                    target = ReverseContourPen(pen) if outer_is_clockwise(p) else pen   # CFF: counter-clockwise
                    p.draw(target)
                charstrings[name] = pen.getCharString()
            fb.setupCFF(f"{PS}-{style}", {"FullName": f"{FAMILY} {style}", "isFixedPitch": True}, charstrings, {})
            for name in order:
                b = paths[name].bounds if paths[name] is not None else None
                metrics[name] = (M.ADV, int(round(b[0])) if b else 0)
        fb.setupHorizontalMetrics(metrics)
        fontmeta.setup_common(fb, family=FAMILY, ps=PS, style=style, weight=weight,
                              ascender=950, descender=-250, line_gap=0, cap=M.CAP, x_height=M.XH, mono=True,
                              description="Pulse Mono: the body face of the Pulse identity, a monospace "
                                          "constructed from rounded rectangles.")
        addOpenTypeFeaturesFromString(fb.font, "languagesystem DFLT dflt;\nlanguagesystem latn dflt;\n")
        if flavour == "ttf":
            fb.font["head"].flags |= 1 << 3
        path = out_dir / f"{PS}-{style}.{flavour}"
        fb.save(str(path))
        files[flavour] = path
    fontmeta.woff2(files["ttf"], out_dir / f"{PS}-{style}.woff2")
    return files


if __name__ == "__main__":
    out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    only = sys.argv[2:] or list(WEIGHTS)
    for style in only:
        w, wv, wh = WEIGHTS[style]
        for v in build_weight(style, w, wv, wh, out).values():
            print("wrote", v)
