"""Names, vertical metrics and tables shared by both Clepso faces.

Vertical metrics follow the 'webfont strategy' used by Google Fonts: hhea = typo = win, USE_TYPO_METRICS set, so
macOS, Windows and browsers lay lines out identically. Names avoid every Reserved Font Name of the OFL faces the app
bundled before (Silkscreen, Pixelify Sans, VT323): these faces are drawn from scratch, not derived.
"""
from fontTools.misc.timeTools import timestampFromString
from fontTools.ttLib import TTFont

VERSION = "1.000"
RELEASED = "Sat Oct 17 12:00:00 2026"
VENDOR = "PULS"
# Founder decision (17 Oct 2026): the faces are open (SIL OFL 1.1) with their names reserved; the Clepso logo, name and app
# icon are not covered (see TRADEMARKS.md).
COPYRIGHT = 'Copyright 2026 The Clepso Project Authors, with Reserved Font Names "Clepso Pixel" and "Clepso Mono"'
DESIGNER = "Clepso brand team"
LICENSE = ("This Font Software is licensed under the SIL Open Font License, Version 1.1. This license is available with a "
           "FAQ at: https://openfontlicense.org")
LICENSE_URL = "https://openfontlicense.org"


def setup_common(fb, *, family, ps, style, weight, ascender, descender, line_gap, cap, x_height, description,
                 mono=False, italic=False):
    full = f"{family} {style}"
    fb.setupNameTable({
        "copyright": COPYRIGHT,
        "familyName": family,
        "styleName": style,
        "uniqueFontIdentifier": f"{VERSION};{VENDOR};{ps}-{style}",
        "fullName": full,
        "version": f"Version {VERSION}",
        "psName": f"{ps}-{style}",
        "manufacturer": "Clepso",
        "designer": DESIGNER,
        "description": description,
        "licenseDescription": LICENSE,
        "licenseInfoURL": LICENSE_URL,
    })
    fb.setupHorizontalHeader(ascent=ascender, descent=descender, lineGap=line_gap)
    fs_selection = (1 << 7)                                    # USE_TYPO_METRICS
    if style == "Regular":
        fs_selection |= 1 << 6
    if style == "Bold":
        fs_selection |= 1 << 5
    fb.setupOS2(
        version=4, achVendID=VENDOR, usWeightClass=weight, usWidthClass=5, fsType=0, fsSelection=fs_selection,
        sTypoAscender=ascender, sTypoDescender=descender, sTypoLineGap=line_gap,
        usWinAscent=ascender, usWinDescent=-descender, sxHeight=x_height, sCapHeight=cap,
        ulCodePageRange1=1,                                    # Latin 1
        panose=panose(mono, weight))
    fb.setupPost(isFixedPitch=1 if mono else 0, underlinePosition=-150, underlineThickness=80 if not mono else 70)
    fb.font["head"].fontRevision = float(VERSION)
    # Reproducible builds: fixed timestamps (the release date of this version), never "now".
    fb.font["head"].created = fb.font["head"].modified = timestampFromString(RELEASED)
    fb.font.recalcTimestamp = False
    fb.font["head"].macStyle = (1 if style == "Bold" else 0)
    fb.font["OS/2"].recalcUnicodeRanges(fb.font)


def panose(mono, weight):
    from fontTools.ttLib.tables.O_S_2f_2 import Panose
    p = Panose()
    p.bFamilyType = 2
    p.bSerifStyle = 11 if not mono else 11
    p.bWeight = {400: 5, 500: 6, 700: 8}.get(weight, 5)
    p.bProportion = 9 if mono else 3
    for f in ("bContrast", "bStrokeVariation", "bArmStyle", "bLetterForm", "bMidline", "bXHeight"):
        setattr(p, f, 0)
    return p


def woff2(src, dst):
    font = TTFont(str(src), recalcTimestamp=False)
    font.flavor = "woff2"
    font.save(str(dst))
