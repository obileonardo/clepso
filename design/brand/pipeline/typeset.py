"""Text set in the Pulse faces as SVG outlines (HarfBuzz shaping, so kerning applies). Sheets and logo files never
depend on fonts being installed on the machine that opens them."""
from functools import lru_cache

import uharfbuzz as hb
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont


@lru_cache(maxsize=None)
def _load(path):
    blob = hb.Blob.from_file_path(str(path))
    face = hb.Face(blob)
    font = hb.Font(face)
    tt = TTFont(str(path))
    return font, tt, tt.getGlyphSet(), tt["head"].unitsPerEm


def shape(path, text, tracking=0):
    font, tt, gs, upm = _load(path)
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf, {"kern": True, "liga": False})
    order = tt.getGlyphOrder()
    out, x = [], 0
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        out.append((order[info.codepoint], x + pos.x_offset, pos.y_offset))
        x += pos.x_advance + tracking
    return out, x - tracking, upm


def width(path, text, size, tracking=0):
    _, w, upm = shape(path, text, tracking * 1000 / size if size else 0)
    return w * size / upm


def path_d(path, text, size, x, y, tracking=0):
    """SVG path data for `text` with its baseline at (x, y), y-down canvas. `tracking` is in output units."""
    font, tt, gs, upm = _load(path)
    s = size / upm
    glyphs, _, _ = shape(path, text, tracking / s if s else 0)
    pen = SVGPathPen(gs, ntos=lambda v: f"{v:.2f}".rstrip("0").rstrip("."))
    for name, gx, gy in glyphs:
        gs[name].draw(TransformPen(pen, (s, 0, 0, -s, x + gx * s, y - gy * s)))
    return pen.getCommands()


def svg_text(path, text, size, x, y, fill, tracking=0, anchor="start", opacity=None):
    if anchor != "start":
        w = width(path, text, size, tracking)
        x -= w if anchor == "end" else w / 2
    op = f' fill-opacity="{opacity}"' if opacity is not None else ""
    return f'<path d="{path_d(path, text, size, x, y, tracking)}" fill="{fill}"{op}/>'
