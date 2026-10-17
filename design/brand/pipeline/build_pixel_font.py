"""Builds Pulse Pixel (TTF, OTF, WOFF2) from pixel_glyphs.py. Usage: python build_pixel_font.py <out dir>"""
import sys
from pathlib import Path

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.reverseContourPen import ReverseContourPen

import fontmeta
import pixel_glyphs as P
from pixels import cells, draw, trace

PX = 100                     # font units per pixel
UPM = 1000
FAMILY = "Pulse Pixel"
PS = "PulsePixel"


def glyph_name(ch):
    from fontTools.agl import UV2AGL
    cp = ord(ch)
    return UV2AGL.get(cp, f"uni{cp:04X}")


def build(out_dir: Path):
    order = [".notdef"]
    cmap, contours, advances = {}, {}, {}
    contours[".notdef"] = [[(0, 0), (0, 7), (5, 7), (5, 0)], [(1, 1), (4, 1), (4, 6), (1, 6)]]
    advances[".notdef"] = 6
    for ch, adv in P.SPACES.items():
        name = "space" if ch == " " else glyph_name(ch)
        order.append(name); cmap[ord(ch)] = name; contours[name] = []; advances[name] = adv
    for ch in sorted(P.G, key=ord):
        top, rows = P.G[ch]
        name = glyph_name(ch)
        order.append(name); cmap[ord(ch)] = name
        contours[name] = trace(cells(rows, top=top))
        advances[name] = len(rows[0]) + 1

    outputs = {}
    for flavour in ("ttf", "otf"):
        fb = FontBuilder(UPM, isTTF=flavour == "ttf")
        fb.setupGlyphOrder(order)
        fb.setupCharacterMap(cmap)
        metrics = {}
        if flavour == "ttf":
            glyphs = {}
            for name in order:
                pen = TTGlyphPen(None)
                draw(pen, contours[name], scale=PX)
                glyphs[name] = pen.glyph()
            fb.setupGlyf(glyphs)
            for name in order:
                metrics[name] = (advances[name] * PX, glyphs[name].xMin if contours[name] else 0)
        else:
            charstrings = {}
            for name in order:
                pen = T2CharStringPen(advances[name] * PX, None)
                draw(ReverseContourPen(pen), contours[name], scale=PX)     # CFF winds the other way
                charstrings[name] = pen.getCharString()
            fb.setupCFF(PS + "-Regular", {"FullName": FAMILY + " Regular"}, charstrings, {})
            for name in order:
                xs = [p[0] for c in contours[name] for p in c]
                metrics[name] = (advances[name] * PX, min(xs) * PX if xs else 0)
        fb.setupHorizontalMetrics(metrics)
        fontmeta.setup_common(fb, family=FAMILY, ps=PS, style="Regular", weight=400,
                              ascender=1000, descender=-200, line_gap=0, cap=700, x_height=500,
                              description="Pulse Pixel: the pixel display face of the Pulse identity. "
                                          "Drawn on a 7-pixel cap grid; one pixel is 100 units.")
        fea = kerning_fea(set(order))
        addOpenTypeFeaturesFromString(fb.font, fea)
        path = out_dir / f"{PS}-Regular.{flavour}"
        fb.save(str(path))
        outputs[flavour] = path
    fontmeta.woff2(outputs["ttf"], out_dir / f"{PS}-Regular.woff2")
    return outputs


def kerning_fea(names):
    lines = ["languagesystem DFLT dflt;", "languagesystem latn dflt;", "feature kern {"]
    for a, b, px in P.auto_kern():
        lines.append(f"  pos {glyph_name(a)} {glyph_name(b)} {px * PX};")
    lines.append("} kern;")
    return "\n".join(lines)


if __name__ == "__main__":
    out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    for k, v in build(out).items():
        print("wrote", v)
