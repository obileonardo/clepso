"""The Clepso type system as data: used by the specimens, the design-system page and the app integration note.

Pixel rule: Clepso Pixel's pixel is 1/10 em, so a size whose tenth is a whole number of device pixels renders without
blur. On a 2× display that is every multiple of 5 pt (15, 20, 25 …); on 1× and the web at 1×, multiples of 10.
"""

FAMILIES = {
    "pixel": {"family": "Clepso Pixel", "ps": {"Regular": "ClepsoPixel-Regular"},
              "role": "Display: figures, titles, labels, buttons, the wordmark"},
    "mono": {"family": "Clepso Mono", "ps": {"Regular": "ClepsoMono-Regular", "Medium": "ClepsoMono-Medium", "Bold": "ClepsoMono-Bold"},
             "role": "Body: sentences, captions, data labels, code"},
}

# token, face, weight, size pt, line height pt, tracking, case, use, replaces
APP = [
    ("metricHero", "pixel", "Regular", 35, 40, 0, "as set", "The big percentage", "Silkscreen 34"),
    ("metricMedium", "pixel", "Regular", 20, 24, 0, "as set", "Secondary figures", "Silkscreen 22"),
    ("title", "pixel", "Regular", 15, 20, 0, "UPPER", "Card titles, tabs, buttons", "Silkscreen 15"),
    ("label", "mono", "Medium", 13, 18, 0, "as set", "Status words, row labels", "SF Mono Medium 13 (.body)"),
    ("supporting", "mono", "Regular", 12, 17, 0, "as set", "Reset lines, freshness, notes", "SF Mono 12 (.callout)"),
    ("micro", "mono", "Medium", 12, 16, 0.4, "UPPER", "Badges, tiny captions", "SF Mono Semibold 12"),
    ("menuBar", "pixel", "Regular", 10, 12, 0, "as set", "Percentage beside the menu bar icon", "Silkscreen 11"),
]

WEB = [
    ("display", "pixel", "Regular", 80, 80, 0, "UPPER", "Hero wordmark-scale lines (50 on phones)"),
    ("h1", "pixel", "Regular", 50, 56, 0, "UPPER", "Page titles (30 on phones)"),
    ("h2", "pixel", "Regular", 30, 36, 0, "UPPER", "Section titles"),
    ("h3", "pixel", "Regular", 20, 24, 0, "UPPER", "Sub-sections, card titles"),
    ("figure", "pixel", "Regular", 60, 60, 0, "as set", "Stat figures"),
    ("eyebrow", "mono", "Medium", 12, 16, 1.7, "UPPER", "Kickers, table heads, labels"),
    ("body", "mono", "Regular", 15, 24, 0, "as set", "Running text"),
    ("small", "mono", "Regular", 13, 20, 0, "as set", "Captions, notes"),
]
