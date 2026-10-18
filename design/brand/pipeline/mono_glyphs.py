"""Clepso Mono: the body face, constructed from rounded rectangles on the same logic as the pixel face.

Every glyph sits in a 600-unit cell (UPM 1000). Bowls are rounded rectangles: the pixel face's chamfered corners,
drawn at high resolution. Vertical strokes are heavier than horizontal ones (wv > wh) so the colour stays even; diagonals
sit between. Weight is a parameter, so Regular, Medium and Bold are the same drawing at different stroke widths.
Figures share the pixel face's disambiguation: dotted 0, flagged 1 with a foot, square-shouldered 5.
"""
from geom import bar, diff, ellipse, inter, mirror_x, poly, rect, ring, rotate180, rr, shift, slant, union

ADV = 600
XH, CAP, ASC, DESC, OS = 530, 700, 750, -210, 10
L, R = 86, 514            # lowercase body
CL, CR = 70, 530          # capitals
DL, DR = 92, 508          # figures
MID = 300


class Mono:
    def __init__(self, wv, wh):
        self.W, self.H = wv, wh
        self.D = wv * 0.96                   # diagonal stroke
        self.rl = 150                        # lowercase bowl radius
        self.rc = 168                        # capital bowl radius
        self.rd = 150                        # figure bowl radius
        self.dot = wv * 1.18                 # i, j, punctuation dots
        self.glyphs = {}
        self._build()

    # ---------------------------------------------------------------------------------------------- helpers
    def clipy(self, p, y0, y1):
        return inter(p, rect(-500, y0, 1100, y1))

    def clipx(self, p, x0, x1):
        return inter(p, rect(x0, -1000, x1, 2000))

    def sq(self, cx, y0, size=None, w=None):
        """A dot: a softened square."""
        s = size or self.dot
        w = w or s
        r = s * 0.22
        return rr(cx - w / 2, y0, cx + w / 2, y0 + s, r, r, r, r)

    def arch(self, x0, x1, top, R, w=None, h=None, bottom=0):
        """Two stems joined by a rounded top (n, h, A)."""
        w, h = w or self.W, h or self.H
        return self.clipy(ring(x0, bottom - 900, x1, top, R, w, h, "tl tr"), bottom, top + 1)

    def tilde(self, cy, x0, x1, amp, w=None, h=None):
        """Two half rings, clipped at their shared centre line, so the wave is one continuous stroke."""
        w, h = w or self.W * 0.95, h or self.H
        r = amp / 2
        return union(self.clipy(ring(x0, cy - amp / 2, MID + w / 2, cy + amp / 2, r, w, h), cy, cy + amp),
                     self.clipy(ring(MID - w / 2, cy - amp / 2, x1, cy + amp / 2, r, w, h), cy - amp, cy))

    def bowl(self, x0, y0, x1, y1, R, side=None):
        """A closed bowl; `side` = 'l' or 'r' squares the outer corners on that side (where a stem joins)."""
        corners = {"l": "tr br", "r": "tl bl", None: "tl tr br bl"}[side]
        return ring(x0, y0, x1, y1, R, self.W, self.H, corners, inner="tl tr br bl")

    # ---------------------------------------------------------------------------------------------- build
    def _build(self):
        W, H, D = self.W, self.H, self.D
        g = self.glyphs
        rl, rc, rd = self.rl, self.rc, self.rd
        ym = XH * 0.5

        # lowercase -------------------------------------------------------------------------------------
        g["o"] = ring(L, -OS, R, XH + OS, rl, W, H)
        g["c"] = diff(ring(L + 6, -OS, R, XH + OS, rl, W, H), rect(R - W - 30, XH * 0.31, R + 40, XH * 0.69))
        eb = XH * 0.50
        g["e"] = union(diff(ring(L, -OS, R, XH + OS, rl, W, H), rect(R - W - 30, H + 70, R + 40, eb - H / 2)),
                       rect(L, eb - H / 2, R, eb + H / 2))
        g["n"] = union(rect(L, 0, L + W, XH), self.arch(L, R, XH + OS, rl))
        g["h"] = union(rect(L, 0, L + W, ASC), self.arch(L, R, XH + OS, rl))
        wm = W * 0.80
        rm = 100
        g["m"] = union(rect(L - 10, 0, L - 10 + wm, XH),
                       self.arch(L - 10, MID + wm / 2, XH + OS, rm, w=wm),
                       self.arch(MID - wm / 2, R + 10, XH + OS, rm, w=wm))
        g["u"] = rotate180(g["n"], MID, XH / 2)
        g["r"] = union(rect(L + 40, 0, L + 40 + W, XH),
                       self.clipy(ring(L + 40, -900, R + 6, XH + OS, rl, W, H, "tl tr"), XH - 130, XH + OS + 1),
                       rect(L - 10, 0, L + 40 + W + 150, H))
        # a: double storey; top arch from a flat terminal, bowl joined to the right stem
        ab = XH * 0.58
        g["a"] = union(
            diff(self.clipy(ring(L, -900, R, XH + OS, rl, W, H, "tl tr"), 0, XH + OS + 1),
                 rect(L - 1, -1, L + W + 1, XH + OS - rl * 0.9)),
            ring(L, -OS, R, ab, 120, W, H, "tl bl", inner="tl tr br bl"))
        # s: two bowls sharing the spine
        rs = 118
        sm = XH * 0.53
        upper = diff(ring(L + 12, sm - H / 2, R - 8, XH + OS, rs, W, H),
                     rect(R - 8 - W - 40, sm - H / 2 - 1, R + 1, XH + OS - rs * 0.9))
        lower = diff(ring(L, -OS, R, sm + H / 2, rs, W, H),
                     rect(L - 1, rs * 0.9 - OS, L + W + 40, sm + H / 2 + 1))
        g["s"] = union(upper, lower)
        g["d"] = union(self.bowl(L, 0, R, XH, rl, "r"), rect(R - W, 0, R, ASC))
        g["b"] = union(self.bowl(L, 0, R, XH, rl, "l"), rect(L, 0, L + W, ASC))
        g["p"] = union(self.bowl(L, 0, R, XH, rl, "l"), rect(L, DESC, L + W, XH))
        g["q"] = union(self.bowl(L, 0, R, XH, rl, "r"), rect(R - W, DESC, R, XH))
        g["g"] = union(self.bowl(L, 0, R, XH, rl, "r"), rect(R - W, DESC + 100, R, XH),
                       self.clipy(diff(ring(L + 10, DESC, R, DESC + 400, rl, W, H, "br", inner="br"),
                                       rect(L, DESC + H, R - W, DESC + 401)), DESC, DESC + 160))
        # i j l: centred stems with serifs
        si = MID + 16
        g["ı"] = union(rect(si - W / 2, 0, si + W / 2, XH), rect(140, XH - H, si, XH), rect(130, 0, 470, H))
        g["i"] = union(g["ı"], self.sq(si, XH + 110))
        sj = MID + 70
        g["ȷ"] = union(rect(sj - W / 2, DESC + 120, sj + W / 2, XH), rect(170, XH - H, sj, XH),
                       self.clipy(ring(110, DESC, sj + W / 2, DESC + 400, rl, W, H, "br", inner="br"), DESC, DESC + 160),
                       )
        g["ȷ"] = diff(g["ȷ"], rect(100, DESC + H, sj - W / 2, DESC + 170))
        g["j"] = union(g["ȷ"], self.sq(sj, XH + 110))
        sl = MID - 10
        g["l"] = union(rect(sl - W / 2, 140, sl + W / 2, ASC), rect(130, ASC - H, sl, ASC),
                       self.clipy(ring(sl - W / 2, -OS, 500, 400, rl, W, H, "bl", inner="bl"), -OS, 170),
                       )
        g["l"] = diff(g["l"], rect(sl + W / 2, H, 501, 171))
        st = 220
        g["t"] = union(rect(st, 140, st + W, XH + 170), rect(96, XH - H, 486, XH),
                       diff(self.clipy(ring(st, -OS, 500, 400, rl, W, H, "bl", inner="bl"), -OS, 170),
                            rect(st + W, H, 501, 171)))
        sf = 210
        g["f"] = union(rect(sf, 0, sf + W, ASC - 150),
                       diff(self.clipy(ring(sf, 0, 504, ASC, rl, W, H, "tl", inner="tl"), ASC - 170, ASC + 1),
                            rect(sf + W, ASC - 171, 505, ASC - H)),
                       rect(96, XH - H, 476, XH))
        g["k"] = union(rect(L, 0, L + W, ASC),
                       self.clipx(self.clipy(slant(L + W * 0.5, XH * 0.32, R - 6, XH, D, ext=60), XH * 0.2, XH), L + W / 2, R + 20),
                       self.clipy(slant(L + W + 70, XH * 0.47, R, 0, D, ext=60), 0, XH * 0.47))
        g["v"] = self.clipy(union(slant(L - 4, XH, MID, 0, D, ext=80), slant(R + 4, XH, MID, 0, D, ext=80)), 0, XH)
        dw = D * 0.86
        g["w"] = union(self.clipy(union(slant(L - 26, XH, L + 92, 0, dw, ext=80), slant(R + 26, XH, R - 92, 0, dw, ext=80)), 0, XH),
                       self.clipy(union(slant(MID, XH * 0.74, L + 92, 0, dw, ext=80), slant(MID, XH * 0.74, R - 92, 0, dw, ext=80)), 0, XH * 0.74))
        g["x"] = self.clipy(union(slant(L, XH, R, 0, D, ext=80), slant(R, XH, L, 0, D, ext=80)), 0, XH)
        yx = R - (R - L - 40) * (XH / (XH - DESC))
        g["y"] = union(self.clipy(slant(L - 4, XH, yx + 10, 0, D, ext=80), 0, XH),
                       self.clipy(slant(R + 4, XH, L + 40, DESC, D, ext=80), DESC, XH),
                       )
        g["z"] = union(rect(L + 10, XH - H, R - 6, XH), rect(L, 0, R, H),
                       self.clipx(self.clipy(slant(R - 6 - D * 0.55, XH - H, L + D * 0.55, H, D, ext=40), H / 2, XH - H / 2), L, R))

        # capitals --------------------------------------------------------------------------------------
        cm = CAP * 0.5
        g["O"] = ring(CL, -OS, CR, CAP + OS, rc, W, H)
        g["C"] = diff(ring(CL + 6, -OS, CR, CAP + OS, rc, W, H), rect(CR - W - 30, CAP * 0.30, CR + 40, CAP * 0.70))
        g["G"] = union(diff(ring(CL, -OS, CR, CAP + OS, rc, W, H), rect(CR - W - 30, CAP * 0.47, CR + 40, CAP * 0.70)),
                       rect(MID + 10, CAP * 0.47 - H, CR, CAP * 0.47))
        g["A"] = union(self.arch(CL, CR, CAP, rc), rect(CL, CAP * 0.36, CR, CAP * 0.36 + H))
        g["U"] = rotate180(self.arch(CL, CR, CAP + OS, rc), MID, CAP / 2)
        g["H"] = union(rect(CL, 0, CL + W, CAP), rect(CR - W, 0, CR, CAP), rect(CL, cm - H / 2, CR, cm + H / 2))
        g["I"] = union(rect(MID - W / 2, 0, MID + W / 2, CAP), rect(150, CAP - H, 450, CAP), rect(150, 0, 450, H))
        g["L"] = union(rect(CL + 20, 0, CL + 20 + W, CAP), rect(CL + 20, 0, CR, H))
        g["E"] = union(rect(CL + 10, 0, CL + 10 + W, CAP), rect(CL + 10, CAP - H, CR - 10, CAP),
                       rect(CL + 10, cm - H / 2, CR - 50, cm + H / 2), rect(CL + 10, 0, CR, H))
        g["F"] = union(rect(CL + 10, 0, CL + 10 + W, CAP), rect(CL + 10, CAP - H, CR - 10, CAP),
                       rect(CL + 10, cm - H / 2 - 10, CR - 50, cm + H / 2 - 10))
        g["T"] = union(rect(CL - 10, CAP - H, CR + 10, CAP), rect(MID - W / 2, 0, MID + W / 2, CAP))
        g["D"] = ring(CL, 0, CR, CAP, rc + 20, W, H, "tr br", inner="tl tr br bl")
        rb = 140
        bm = CAP * 0.53
        g["B"] = union(ring(CL, bm - H / 2, CR - 26, CAP, rb, W, H, "tr br", inner="tl tr br bl"),
                       ring(CL, 0, CR, bm + H / 2, rb + 10, W, H, "tr br", inner="tl tr br bl"))
        pb = CAP * 0.40
        g["P"] = union(ring(CL, pb, CR, CAP, rb + 10, W, H, "tr br", inner="tl tr br bl"), rect(CL, 0, CL + W, CAP))
        g["R"] = union(g["P"], self.clipy(slant(MID - 10, pb + H / 2, CR, 0, D, ext=60), 0, pb + H / 2))
        g["J"] = union(rect(CR - 20 - W, 170, CR - 20, CAP), rect(200, CAP - H, CR - 20, CAP),
                       self.clipy(ring(CL, -OS, CR - 20, 600, rc, W, H, "bl br", inner="bl br"), -OS, 230))
        g["K"] = union(rect(CL + 10, 0, CL + 10 + W, CAP),
                       self.clipx(self.clipy(slant(CL + 10 + W * 0.5, CAP * 0.30, CR - 4, CAP, D, ext=60), CAP * 0.2, CAP), CL + 10 + W / 2, CR + 20),
                       self.clipy(slant(CL + 10 + W + 80, CAP * 0.47, CR + 4, 0, D, ext=60), 0, CAP * 0.47))
        wn = W * 0.9
        g["N"] = union(rect(CL + 6, 0, CL + 6 + wn, CAP), rect(CR - 6 - wn, 0, CR - 6, CAP),
                       self.clipy(slant(CL + 6 + wn * 0.5, CAP, CR - 6 - wn * 0.5, 0, D * 0.95, ext=60), 0, CAP))
        g["M"] = union(rect(CL, 0, CL + wn, CAP), rect(CR - wn, 0, CR, CAP),
                       self.clipy(union(slant(CL + wn * 0.4, CAP, MID, CAP * 0.30, D * 0.88, ext=60),
                                        slant(CR - wn * 0.4, CAP, MID, CAP * 0.30, D * 0.88, ext=60)), CAP * 0.30, CAP))
        g["V"] = self.clipy(union(slant(CL - 6, CAP, MID, 0, D, ext=80), slant(CR + 6, CAP, MID, 0, D, ext=80)), 0, CAP)
        g["W"] = union(self.clipy(union(slant(CL - 30, CAP, CL + 92, 0, dw, ext=80), slant(CR + 30, CAP, CR - 92, 0, dw, ext=80)), 0, CAP),
                       self.clipy(union(slant(MID, CAP * 0.66, CL + 92, 0, dw, ext=80), slant(MID, CAP * 0.66, CR - 92, 0, dw, ext=80)), 0, CAP * 0.66))
        g["X"] = self.clipy(union(slant(CL + 4, CAP, CR - 4, 0, D, ext=80), slant(CR - 4, CAP, CL + 4, 0, D, ext=80)), 0, CAP)
        yj = CAP * 0.42
        g["Y"] = union(self.clipy(union(slant(CL - 4, CAP, MID, yj, D, ext=80), slant(CR + 4, CAP, MID, yj, D, ext=80)), yj, CAP),
                       rect(MID - W / 2, 0, MID + W / 2, yj + 10))
        g["Z"] = union(rect(CL + 14, CAP - H, CR - 10, CAP), rect(CL, 0, CR, H),
                       self.clipx(self.clipy(slant(CR - 10 - D * 0.55, CAP - H, CL + D * 0.55, H, D, ext=40), H / 2, CAP - H / 2), CL, CR))
        rsc = 140
        sc = CAP * 0.53
        g["S"] = union(diff(ring(CL + 14, sc - H / 2, CR - 10, CAP + OS, rsc, W, H),
                            rect(CR - 10 - W - 40, sc - H / 2 - 1, CR + 1, CAP + OS - rsc * 0.9)),
                       diff(ring(CL, -OS, CR, sc + H / 2, rsc, W, H),
                            rect(CL - 1, rsc * 0.9 - OS, CL + W + 40, sc + H / 2 + 1)))
        g["Q"] = union(g["O"], self.clipy(bar(MID + 50, CAP * 0.24, CR + 20, -110, D), -110, CAP * 0.3))

        # figures ---------------------------------------------------------------------------------------
        g["0"] = union(ring(DL, -OS, DR, CAP + OS, rd, W, H),
                       rr(MID - W * 0.55, CAP / 2 - W * 0.85, MID + W * 0.55, CAP / 2 + W * 0.85, W * 0.3, W * 0.3, W * 0.3, W * 0.3))
        g["1"] = union(rect(MID + 20 - W / 2, 0, MID + 20 + W / 2, CAP), rect(130, 0, 470, H),
                       bar(150, CAP - 170, MID + 20 - W / 2 + 4, CAP - H / 2 - 4, H * 1.05),
                       rect(MID + 20 - W / 2, CAP - H, MID + 20 + W / 2, CAP))
        two_top = CAP * 0.52
        g["2"] = union(
            diff(self.clipy(ring(DL, -900, DR, CAP + OS, rd, W, H, "tl tr"), two_top, CAP + OS + 1),
                 rect(DL - 1, two_top - 1, DL + W + 1, CAP + OS - rd * 0.9)),
            self.clipx(self.clipy(slant(DR - W * 0.5, two_top + 30, DL + W * 0.5, H, D, ext=40), H * 0.5, two_top + 30), DL, DR),
            rect(DL, 0, DR, H))
        rb3 = 135
        t3 = CAP * 0.54
        g["3"] = union(diff(ring(DL + 16, t3 - H / 2, DR - 14, CAP + OS, rb3, W, H),
                            rect(DL + 15, t3 - H / 2 - 1, DL + 16 + W + 80, CAP + OS - rb3 * 0.9)),
                       diff(ring(DL, -OS, DR, t3 + H / 2, rb3 + 10, W, H),
                            rect(DL - 1, rb3 * 0.9 - OS, DL + W + 60, t3 + H / 2 + 1)))
        f4 = CAP * 0.30
        s4 = DR - 40
        g["4"] = union(rect(s4 - W, 0, s4, CAP), rect(DL, f4 - H / 2, DR, f4 + H / 2),
                       self.clipy(slant(DL + D * 0.5, f4, s4 - W * 0.5, CAP, D, ext=60), f4, CAP))
        t5 = CAP * 0.58
        g["5"] = union(rect(DL, CAP - H, DR - 10, CAP), rect(DL, t5 - H, DL + W, CAP),
                       diff(ring(DL, -OS, DR, t5, rb3 + 10, W, H, "tr br bl", inner="tl tr br bl"),
                            rect(DL - 1, (rb3 + 10) * 0.9 - OS, DL + W + 1, t5 - H)))
        t6 = CAP * 0.58
        g["6"] = union(ring(DL, -OS, DR, t6, rb3 + 10, W, H),
                       diff(self.clipy(ring(DL, -900, DR - 6, CAP + OS, rd, W, H, "tl tr"), t6 / 2, CAP + OS + 1),
                            rect(DR - 6 - W - 1, t6 / 2 - 1, DR + 1, CAP + OS - rd * 0.9)))
        g["9"] = rotate180(g["6"], MID, CAP / 2)
        g["7"] = union(rect(DL, CAP - H, DR, CAP),
                       self.clipx(self.clipy(slant(DR - D * 0.5, CAP - H / 2, DL + 110, 0, D, ext=40), 0, CAP - H / 2), DL, DR))
        g["8"] = union(ring(DL + 18, t3 - H / 2, DR - 18, CAP + OS, rb3, W, H),
                       ring(DL, -OS, DR, t3 + H / 2, rb3 + 10, W, H))

        # punctuation -----------------------------------------------------------------------------------
        d = self.dot
        g["."] = self.sq(MID, 0)
        g[","] = union(self.sq(MID, 0), self.clipy(slant(MID + d / 2 - d * 0.45, d * 0.5, MID - d * 0.55, -170, d * 0.62, ext=0), -170, d * 0.6))
        g[":"] = union(self.sq(MID, 0), self.sq(MID, XH - d))
        g[";"] = union(g[","], self.sq(MID, XH - d))
        g["…"] = union(self.sq(110, 0, d * 0.9), self.sq(MID, 0, d * 0.9), self.sq(490, 0, d * 0.9))
        g["!"] = union(rect(MID - W / 2, 220, MID + W / 2, CAP), self.sq(MID, 0))
        g["?"] = union(
            diff(ring(DL + 20, CAP * 0.40, DR - 10, CAP + OS, rd, W, H, "tl tr br", inner="tl tr br bl"),
                 rect(DL + 19, CAP * 0.40 - 1, DL + W + 21, CAP + OS - rd * 0.9),
                 rect(DL + 19, CAP * 0.40 - 1, MID - W / 2, CAP * 0.40 + H + 1)),
            rect(MID - W / 2, 220, MID + W / 2, CAP * 0.40 + H), self.sq(MID, 0))
        g["'"] = rect(MID - W / 2, CAP - 230, MID + W / 2, CAP + 20)
        g['"'] = union(rect(190 - W / 2, CAP - 230, 190 + W / 2, CAP + 20), rect(410 - W / 2, CAP - 230, 410 + W / 2, CAP + 20))
        q = self.clipy(union(self.sq(MID, 0), slant(MID + d / 2 - d * 0.45, d * 0.5, MID - d * 0.55, -170, d * 0.62)), -170, d * 1.0)
        g["’"] = shift(q, dy=CAP - d + 30)
        g["‘"] = rotate180(g["’"], MID, CAP - 60)
        g["”"] = union(shift(g["’"], dx=-110), shift(g["’"], dx=110))
        g["“"] = union(shift(g["‘"], dx=-110), shift(g["‘"], dx=110))
        g["‚"] = g[","]
        g["„"] = union(shift(g[","], dx=-110), shift(g[","], dx=110))
        g["("] = self.clipx(ring(180, -170, 640, CAP + 160, 220, W, H, "tl bl"), 179, 440)
        g[")"] = mirror_x(g["("])
        g["["] = union(rect(200, -170, 200 + W, CAP + 160), rect(200, CAP + 160 - H, 440, CAP + 160), rect(200, -170, 440, -170 + H))
        g["]"] = mirror_x(g["["])
        cb = CAP / 2 - 20
        g["{"] = union(rect(MID - W / 2, -170, MID + W / 2, CAP + 160), rect(MID - W / 2, CAP + 160 - H, 460, CAP + 160),
                       rect(MID - W / 2, -170, 460, -170 + H), rect(150, cb - H / 2, MID, cb + H / 2))
        g["}"] = mirror_x(g["{"])
        g["/"] = self.clipy(slant(120, -130, 480, CAP + 110, D, ext=20), -130, CAP + 110)
        g["\\"] = mirror_x(g["/"])
        g["|"] = rect(MID - W / 2, DESC, MID + W / 2, ASC + 40)
        hy = 290
        g["-"] = rect(150, hy - H / 2, 450, hy + H / 2)
        g["‐"] = g["-"]
        g["–"] = rect(60, hy - H / 2, 540, hy + H / 2)
        g["—"] = rect(0, hy - H / 2, 600, hy + H / 2)
        g["_"] = rect(40, -150, 560, -150 + H)
        g["·"] = self.sq(MID, hy - d / 2)
        g["•"] = rr(MID - 110, hy - 110, MID + 110, hy + 110, 50, 50, 50, 50)
        ac, al = (MID, CAP - 190), 175
        import math
        spokes = [bar(ac[0] - al * math.cos(math.radians(a)), ac[1] - al * math.sin(math.radians(a)),
                      ac[0] + al * math.cos(math.radians(a)), ac[1] + al * math.sin(math.radians(a)), W * 0.92)
                  for a in (90, 30, 150)]
        g["*"] = union(*spokes)
        g["#"] = union(rect(200 - W / 2, 0, 200 + W / 2, CAP), rect(400 - W / 2, 0, 400 + W / 2, CAP),
                       rect(70, 450 - H / 2, 530, 450 + H / 2), rect(70, 230 - H / 2, 530, 230 + H / 2))
        wa = W * 0.84
        ha = H * 0.84
        g["@"] = union(diff(ring(50, -150, 550, CAP + 10, 170, wa, ha), rect(400, -151, 551, 120)),
                       ring(190, 140, 410, 470, 90, wa, ha, "tl bl", inner="tl tr br bl"),
                       rect(410 - wa, 140, 410, 470), rect(410 - wa, 120 - ha + 30, 550, 120 + 30))
        g["&"] = union(diff(ring(DL + 30, CAP * 0.52, 400, CAP + OS, 110, W, H), rect(330 - 1, CAP * 0.52 - 1, 401, CAP * 0.62)),
                       diff(ring(DL, -OS, 440, CAP * 0.60, 130, W, H), rect(440 - W - 1, CAP * 0.28, 441, CAP * 0.61)),
                       self.clipy(slant(DL + 70, CAP * 0.58, DR + 10, -10, D, ext=40), 0, CAP * 0.62),
                       rect(330, CAP * 0.34 - H / 2 + 20, DR, CAP * 0.34 + H / 2 + 20))
        g["$"] = union(g["S"], rect(MID - W * 0.42, CAP, MID + W * 0.42, CAP + 100), rect(MID - W * 0.42, -110, MID + W * 0.42, 0))
        pr = 70
        g["%"] = union(ring(60, CAP - 250, 260, CAP, pr, W * 0.82, H * 0.82), ring(340, 0, 540, 250, pr, W * 0.82, H * 0.82),
                       self.clipy(slant(120, -10, 480, CAP + 10, D * 0.85, ext=20), -10, CAP + 10))
        g["^"] = union(bar(130, CAP - 260, MID, CAP, D), bar(MID, CAP, 470, CAP - 260, D))
        g["^"] = self.clipy(g["^"], CAP - 280, CAP)
        g["~"] = self.tilde(300, 100, 500, 170)
        g["`"] = self.clipy(bar(210, CAP + 40, 380, CAP - 120, D * 0.95), CAP - 130, CAP + 50)
        g["°"] = ring(200, CAP - 220, 400, CAP + 10, 90, W * 0.82, H * 0.82)

        # maths ---------------------------------------------------------------------------------------
        my = 300
        g["+"] = union(rect(100, my - H / 2, 500, my + H / 2), rect(MID - W / 2, my - 200, MID + W / 2, my + 200))
        g["−"] = rect(100, my - H / 2, 500, my + H / 2)
        g["×"] = union(bar(150, my - 150, 450, my + 150, W * 0.95), bar(150, my + 150, 450, my - 150, W * 0.95))
        g["÷"] = union(g["−"], self.sq(MID, my + 110), self.sq(MID, my - 110 - d))
        g["="] = union(rect(100, my + 70, 500, my + 70 + H), rect(100, my - 70 - H, 500, my - 70))
        g["±"] = union(rect(100, my - H / 2 + 60, 500, my + H / 2 + 60), rect(MID - W / 2, my - 120, MID + W / 2, my + 240),
                       rect(100, 0, 500, H))
        g["<"] = union(bar(470, my + 200, 140, my, D), bar(140, my, 470, my - 200, D))
        g[">"] = mirror_x(g["<"])
        g["≤"] = union(shift(g["<"], dy=70), rect(130, 0, 470, H))
        g["≥"] = mirror_x(g["≤"])
        tilde = g["~"]
        g["≈"] = union(shift(tilde, dy=-130), shift(tilde, dy=40))

        # arrows and keys -----------------------------------------------------------------------------
        ay = 300
        head = union(bar(330, ay + 190, 520, ay, W * 0.96), bar(520, ay, 330, ay - 190, W * 0.96))
        g["→"] = union(rect(60, ay - H / 2, 500, ay + H / 2), head)
        g["←"] = mirror_x(g["→"])
        up = union(rect(MID - W / 2, -10, MID + W / 2, CAP - 30), bar(MID - 200, CAP - 200, MID, CAP, W * 0.96),
                   bar(MID, CAP, MID + 200, CAP - 200, W * 0.96))
        g["↑"] = self.clipy(up, -10, CAP + 20)
        g["↓"] = rotate180(g["↑"], MID, CAP / 2)
        g["↗"] = union(bar(110, 40, 470, 400, W * 0.96), rect(210, 400 - H, 490, 400 + 20), rect(490 - W, 120, 490, 420))
        g["↘"] = union(bar(110, 400, 470, 40, W * 0.96), rect(210, 20, 490, 20 + H), rect(490 - W, 20, 490, 300))
        cw, ch = W * 0.8, H * 0.8
        lo, hi, lr = 210, 390, 110
        loops = [ring(cx - lr, cy - lr, cx + lr, cy + lr, lr, cw, ch) for cx in (lo - lr + cw / 2 + 50, hi + lr - cw / 2 - 50)
                 for cy in (lo - lr + ch / 2 + 50 - 10, hi + lr - ch / 2 - 50 - 10)]
        g["⌘"] = union(ring(lo - cw / 2 + 10, lo - ch / 2, hi + cw / 2 - 10, hi + ch / 2 - 20, 0, cw, ch, ""), *loops)
        g["⌥"] = union(rect(70, CAP * 0.62 - H, 230, CAP * 0.62), rect(340, CAP * 0.62 - H, 530, CAP * 0.62),
                       rect(370, 0, 530, H), self.clipy(slant(195, CAP * 0.62 - H / 2, 405, H / 2, D, ext=20), H / 2, CAP * 0.62 - H / 2))
        arrow = poly((MID, CAP + 10), (540, 330), (420, 330), (420, 30), (180, 30), (180, 330), (60, 330))
        inner = poly((MID, CAP + 10 - 1.4 * W), (540 - 2.2 * W, 330 + 0.6 * H), (420 - W, 330 + 0.6 * H), (420 - W, 30 + H),
                     (180 + W, 30 + H), (180 + W, 330 + 0.6 * H), (60 + 2.2 * W, 330 + 0.6 * H))
        g["⇧"] = diff(arrow, inner)
        g["⏎"] = union(rect(500 - W, 230, 500, CAP - 60), rect(150, 230, 500, 230 + H),
                       bar(300, 400, 120, 230 + H / 2, W * 0.95), bar(120, 230 + H / 2, 300, 60, W * 0.95))
        g["€"] = union(diff(ring(CL + 40, -OS, CR, CAP + OS, rc, W, H), rect(CR - W - 30, CAP * 0.28, CR + 40, CAP * 0.72)),
                       rect(30, 400 - H / 2, 380, 400 + H / 2), rect(30, 280 - H / 2, 380, 280 + H / 2))
        g["£"] = union(rect(DL, 0, DR, H), rect(160, 0, 160 + W, CAP * 0.72),
                       diff(self.clipy(ring(160, 100, DR, CAP + OS, 150, W, H, "tl tr"), CAP * 0.6, CAP + OS + 1),
                            rect(DR - W - 1, CAP * 0.6 - 1, DR + 1, CAP + OS - 140)),
                       rect(DL, 330 - H / 2, 400, 330 + H / 2))
        g["¢"] = union(diff(ring(L + 6, 30, R, XH + 40, rl, W, H), rect(R - W - 30, XH * 0.32 + 30, R + 40, XH * 0.70 + 30)),
                       rect(MID - W * 0.42, -90, MID + W * 0.42, XH + 140))
        wc, hc = W * 0.75, H * 0.75
        circ = ring(20, -40, 580, CAP + 40, 240, wc, hc)
        g["©"] = union(circ, diff(ring(170, 150, 430, 510, 90, wc, hc), rect(430 - wc - 20, 270, 431, 390)))
        g["®"] = union(circ, ring(200, 340, 410, 520, 70, wc, hc, "tr br", inner="tl tr br bl"), rect(200, 140, 200 + wc, 520),
                       self.clipy(slant(300, 340 + hc / 2, 410, 140, wc, ext=30), 140, 340 + hc / 2))
        tm = 0.42
        g["™"] = union(rect(30, CAP - H * 0.8, 250, CAP), rect(140 - W * 0.4, CAP - 260, 140 + W * 0.4, CAP),
                       rect(300, CAP - 260, 300 + W * 0.8, CAP), rect(570 - W * 0.8, CAP - 260, 570, CAP),
                       self.clipy(union(slant(300 + W * 0.3, CAP, 435, CAP - 150, W * 0.75, ext=40),
                                        slant(570 - W * 0.3, CAP, 435, CAP - 150, W * 0.75, ext=40)), CAP - 150, CAP))
        g["✓"] = union(bar(100, 300, 240, 120, W * 1.05), bar(240, 120, 520, 560, W * 1.05))
        g["✓"] = self.clipy(g["✓"], 60, 600)
        g["■"] = rr(110, 60, 490, 440, 30, 30, 30, 30)
        g["□"] = ring(110, 60, 490, 440, 30, W, H)
        g["▲"] = poly((90, 60), (510, 60), (MID, 470))
        g["▼"] = poly((90, 470), (MID, 60), (510, 470))
        g["▶"] = poly((120, 60), (500, 260), (120, 460))
        g["◀"] = poly((480, 60), (480, 460), (100, 260))
        g["●"] = ellipse(MID, 260, 200, 200)
        g["○"] = diff(ellipse(MID, 260, 200, 200), ellipse(MID, 260, 200 - W, 200 - H))
        g["«"] = union(*(shift(union(bar(260, 420, 130, 260, W * 0.9), bar(130, 260, 260, 100, W * 0.9)), dx=dx) for dx in (0, 190)))
        g["»"] = mirror_x(g["«"])
        g["¡"] = rotate180(g["!"], MID, 250)
        g["¿"] = rotate180(g["?"], MID, 250)

        # letters with their own drawings --------------------------------------------------------------
        g["Ø"] = union(g["O"], self.clipy(slant(CL - 20, -60, CR + 20, CAP + 60, W * 0.9), -60, CAP + 60))
        g["ø"] = union(g["o"], self.clipy(slant(L - 20, -50, R + 20, XH + 50, W * 0.9), -50, XH + 50))
        sb = 400
        g["ß"] = union(rect(L, 0, L + W, ASC - 120),
                       ring(L, sb - H / 2, R - 40, ASC, 140, W, H, "tl tr br", inner="tl tr br bl"),
                       diff(ring(L + 150, -OS, R, sb + H / 2, 130, W, H, "tr br bl", inner="tl tr br bl"),
                            rect(L + 149, 130 - OS, L + 150 + W + 1, sb - H / 2)))

        # spaces
        for ch in (" ", " ", " ", " ", " "):
            g[ch] = None


# Marks for accented letters: (drawing for lowercase, drawing for capitals) in a 600 cell, centred on 300.
def marks(m):
    W, H = m.W, m.H
    d = m.dot
    out = {}
    for case, base in (("lc", XH + 100), ("uc", CAP + 70)):
        top = base + 170
        out[("acute", case)] = m.clipy(bar(250, base, 380, top, W * 0.92), base, top)
        out[("grave", case)] = mirror_x(out[("acute", case)])
        out[("circumflex", case)] = m.clipy(union(bar(170, base, MID, top, W * 0.9), bar(MID, top, 430, base, W * 0.9)), base, top)
        out[("caron", case)] = m.clipy(union(bar(170, top, MID, base, W * 0.9), bar(MID, base, 430, top, W * 0.9)), base, top)
        out[("dieresis", case)] = union(m.sq(190, base + 10, d * 0.95), m.sq(410, base + 10, d * 0.95))
        out[("tilde", case)] = m.tilde(base + 75, 140, 460, 150, w=W * 0.9, h=H * 0.9)
        out[("ring", case)] = ring(MID - 95, base - 10, MID + 95, top + 20, 80, W * 0.8, H * 0.8)
    out[("cedilla", "lc")] = union(rect(MID - W / 2, -110, MID + W / 2, 10),
                                   m.clipy(ring(MID - W / 2 - 120, -230, MID + W / 2, -60, 70, W * 0.9, H * 0.9, "tr br", inner="tr br"), -230, -100))
    out[("cedilla", "uc")] = out[("cedilla", "lc")]
    return out
