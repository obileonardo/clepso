"""Constructive geometry for Pulse Mono: rounded rectangles, rings with separate vertical and horizontal stroke
weights, slanted strokes with flat cuts, and boolean operations (skia-pathops). Curves are exact cubic quarter
ellipses, so outlines stay smooth at any size; overlaps are removed by the final union."""
import math

import pathops

K = 0.5522847498            # cubic approximation of a quarter circle


def _r(c):
    if isinstance(c, tuple):
        return c
    return (c, c)


def rr(x0, y0, x1, y1, tl=0, tr=0, br=0, bl=0):
    """Rectangle with elliptical corner radii (rx, ry) or a number per corner."""
    tl, tr, br, bl = map(_r, (tl, tr, br, bl))
    p = pathops.Path()
    pen = p.getPen()
    pen.moveTo((x0 + bl[0], y0))
    pen.lineTo((x1 - br[0], y0))
    if br[0] and br[1]:
        pen.curveTo((x1 - br[0] + K * br[0], y0), (x1, y0 + br[1] - K * br[1]), (x1, y0 + br[1]))
    pen.lineTo((x1, y1 - tr[1]))
    if tr[0] and tr[1]:
        pen.curveTo((x1, y1 - tr[1] + K * tr[1]), (x1 - tr[0] + K * tr[0], y1), (x1 - tr[0], y1))
    pen.lineTo((x0 + tl[0], y1))
    if tl[0] and tl[1]:
        pen.curveTo((x0 + tl[0] - K * tl[0], y1), (x0, y1 - tl[1] + K * tl[1]), (x0, y1 - tl[1]))
    pen.lineTo((x0, y0 + bl[1]))
    if bl[0] and bl[1]:
        pen.curveTo((x0, y0 + bl[1] - K * bl[1]), (x0 + bl[0] - K * bl[0], y0), (x0 + bl[0], y0))
    pen.closePath()
    return p


def rect(x0, y0, x1, y1):
    return rr(min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))


def poly(*pts):
    p = pathops.Path()
    pen = p.getPen()
    pen.moveTo(pts[0])
    for q in pts[1:]:
        pen.lineTo(q)
    pen.closePath()
    return p


def ring(x0, y0, x1, y1, R, wv, wh, corners="tl tr br bl", inner=None, inner_ratio=0.86):
    """A rounded-rectangle stroke: vertical sides wv thick, horizontal sides wh thick. `corners` are the rounded
    outer corners, `inner` the rounded counter corners (default: the same). Inner radii are a little larger than
    concentric (inner_ratio) so the corners do not clot."""
    cs = corners.split()
    ics = (inner or corners).split()
    rx = min(R, (x1 - x0) / 2)
    ry = min(R, (y1 - y0) / 2)
    outer = {c: ((rx, ry) if c in cs else 0) for c in ("tl", "tr", "br", "bl")}
    irx = max(min(rx - wv * inner_ratio, (x1 - x0 - 2 * wv) / 2), 1)
    iry = max(min(ry - wh * inner_ratio, (y1 - y0 - 2 * wh) / 2), 1)
    inner = {c: ((irx, iry) if c in ics else 0) for c in ("tl", "tr", "br", "bl")}
    return diff(rr(x0, y0, x1, y1, **outer), rr(x0 + wv, y0 + wh, x1 - wv, y1 - wh, **inner))


def slant(x0, y0, x1, y1, w, ext=0):
    """A straight stroke from (x0, y0) to (x1, y1) of perpendicular thickness w, cut horizontally at both ends.
    `ext` lengthens it past both ends (to be clipped later)."""
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy)
    hw = w * length / abs(dy) / 2 if dy else w / 2
    if ext:
        x0, y0 = x0 - dx / length * ext, y0 - dy / length * ext
        x1, y1 = x1 + dx / length * ext, y1 + dy / length * ext
    return poly((x0 - hw, y0), (x0 + hw, y0), (x1 + hw, y1), (x1 - hw, y1))


def bar(x0, y0, x1, y1, w):
    """A stroke of perpendicular thickness w between two points, cut square at its ends."""
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy)
    nx, ny = -dy / length * w / 2, dx / length * w / 2
    return poly((x0 + nx, y0 + ny), (x1 + nx, y1 + ny), (x1 - nx, y1 - ny), (x0 - nx, y0 - ny))


def ellipse(cx, cy, rx, ry):
    return rr(cx - rx, cy - ry, cx + rx, cy + ry, (rx, ry), (rx, ry), (rx, ry), (rx, ry))


def _op(a, b, kind):
    return pathops.op(a, b, kind, fix_winding=True, keep_starting_points=False)


def union(*paths):
    out = pathops.Path()
    for p in paths:
        if p is None:
            continue
        out = _op(out, p, pathops.PathOp.UNION)
    return out


def diff(a, *bs):
    for b in bs:
        a = _op(a, b, pathops.PathOp.DIFFERENCE)
    return a


def inter(a, b):
    return _op(a, b, pathops.PathOp.INTERSECTION)


def shift(p, dx=0, dy=0, sx=1, sy=1):
    from fontTools.pens.transformPen import TransformPen
    out = pathops.Path()
    p.draw(TransformPen(out.getPen(), (sx, 0, 0, sy, dx, dy)))
    return out


def mirror_x(p, axis=300):
    """Mirror left-right about x = axis (the cell centre)."""
    return union(shift(p, dx=2 * axis, sx=-1))


def rotate180(p, cx=300, cy=0):
    return union(shift(p, dx=2 * cx, dy=2 * cy, sx=-1, sy=-1))
