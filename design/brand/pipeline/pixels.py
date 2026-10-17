"""Pixel geometry shared by the font, logo and icon builders.

A bitmap is a list of strings, top row first, '#' for an inked pixel. `trace` turns a set of pixels into closed
outlines (no overlaps, shared edges removed, collinear points merged), so a glyph or logo is one clean shape rather
than a heap of squares. Coordinates are y-up, one unit per pixel.
"""


def cells(rows, top=0, left=0):
    """Inked cells of a bitmap as (x, y) with y up; `top` is the y of the first row."""
    out = set()
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch == "#":
                out.add((left + c, top - r))
    return out


def trace(on):
    """Closed contours around a set of unit cells. Outer contours run clockwise (y-up), holes counter-clockwise:
    TrueType's convention. Where two cells touch only at a corner the contours stay separate (right-hand rule)."""
    edges = {}
    for x, y in on:
        corners = [(x, y), (x, y + 1), (x + 1, y + 1), (x + 1, y)]          # clockwise with y up
        for i in range(4):
            a, b = corners[i], corners[(i + 1) % 4]
            if (b, a) in edges:
                del edges[(b, a)]                                           # shared edge: interior, drop both
            else:
                edges[(a, b)] = True
    outgoing = {}
    for a, b in edges:
        outgoing.setdefault(a, []).append(b)
    contours = []
    while outgoing:
        start = next(iter(outgoing))
        loop, cur, prev_dir = [start], start, None
        while True:
            options = outgoing[cur]
            if len(options) == 1 or prev_dir is None:
                nxt = options[0]
            else:
                dx, dy = prev_dir
                ranked = [(dy, -dx), (dx, dy), (-dy, dx)]                    # right turn, straight, left turn
                nxt = next(cur_plus for d in ranked for cur_plus in options
                           if (cur_plus[0] - cur[0], cur_plus[1] - cur[1]) == d)
            options.remove(nxt)
            if not options:
                del outgoing[cur]
            prev_dir = (nxt[0] - cur[0], nxt[1] - cur[1])
            cur = nxt
            if cur == start and (start not in outgoing):
                break
            if cur == start:
                break
            loop.append(cur)
        contours.append(simplify(loop))
    return contours


def simplify(loop):
    """Drop points that sit on a straight run."""
    out = []
    n = len(loop)
    for i in range(n):
        a, b, c = loop[i - 1], loop[i], loop[(i + 1) % n]
        if (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) != 0:
            out.append(b)
    return out


def draw(pen, contours, scale=1, dx=0, dy=0):
    for contour in contours:
        pen.moveTo((contour[0][0] * scale + dx, contour[0][1] * scale + dy))
        for p in contour[1:]:
            pen.lineTo((p[0] * scale + dx, p[1] * scale + dy))
        pen.closePath()


def svg_path(contours, scale=1, dx=0, dy=0, height=None):
    """SVG path data (y-down). `height` is the canvas height in cells, used to flip y."""
    parts = []
    for contour in contours:
        pts = [(p[0] * scale + dx, ((height - p[1]) if height is not None else p[1]) * scale + dy) for p in contour]
        parts.append("M" + " ".join(f"{x:g} {y:g}" for x, y in pts[:1]) +
                     "".join(f"H{x:g}" if y == py else f"V{y:g}" for (px, py), (x, y) in zip(pts, pts[1:])) + "Z")
    return "".join(parts)
