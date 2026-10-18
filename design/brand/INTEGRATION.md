# Wiring the Clepso identity into the app and site

Nothing under `Sources/`, `scripts/build-site.py` or `scripts/site/` was changed on this branch (other work is in
flight there). These are the edits to make afterwards.

## 1. Fonts

Copy into `Sources/DesignSystem/Resources/Fonts/` (the folder is already a `.copy` resource and every `.ttf` in it
is registered by `PixelFonts.ensureRegistered()` at process scope):

| File | Family | PostScript name | Weight |
|---|---|---|---|
| `design/brand/fonts/ClepsoPixel-Regular.ttf` | Clepso Pixel | `ClepsoPixel-Regular` | 400 |
| `design/brand/fonts/ClepsoMono-Regular.ttf` | Clepso Mono | `ClepsoMono-Regular` | 400 |
| `design/brand/fonts/ClepsoMono-Medium.ttf` | Clepso Mono | `ClepsoMono-Medium` | 500 |
| `design/brand/fonts/ClepsoMono-Bold.ttf` | Clepso Mono | `ClepsoMono-Bold` | 700 |

Then in `PixelFonts.swift`: `display = "ClepsoPixel-Regular"` and add `body = "ClepsoMono-Regular"`,
`bodyMedium = "ClepsoMono-Medium"`, `bodyBold = "ClepsoMono-Bold"`. Use PostScript names with `.custom(_:size:)`:
they are unambiguous where family names are not. Silkscreen, Pixelify Sans and VT323 (and their OFL texts and README
rows) can be removed once nothing references them; if Pixelify Sans and VT323 are unused today, they can go now.

Add the new files to the checksum table in `Resources/Fonts/README.md` (`shasum -a 256`). Licence line: original
faces under the SIL OFL 1.1 with Reserved Font Names (`ClepsoFonts-OFL.txt`; NOTES.md §8).

## 2. Typography tokens (`Theme.font(_:)`, pixel branch)

Clepso Pixel's pixel is 1/10 em: on Retina, sizes that are multiples of 5 pt land every pixel on whole device pixels.

| Token | Now | Change to | Line height | Notes |
|---|---|---|---|---|
| `.metricHero` | Silkscreen 34 | `.custom("ClepsoPixel-Regular", size: 35, relativeTo: .largeTitle)` | 40 | `.monospacedDigit()` not needed: figures are tabular |
| `.metricMedium` | Silkscreen 22 | `.custom("ClepsoPixel-Regular", size: 20, relativeTo: .title2)` | 24 | |
| `.title` | Silkscreen 15 | `.custom("ClepsoPixel-Regular", size: 15, relativeTo: .headline)` | 20 | uppercase as today |
| `.label` | system mono `.body` medium (13) | `.custom("ClepsoMono-Medium", size: 13, relativeTo: .body)` | 18 | |
| `.supporting` | system mono `.callout` (12) | `.custom("ClepsoMono-Regular", size: 12, relativeTo: .callout)` | 17 | |
| `.micro` | system mono `.callout` semibold (12) | `.custom("ClepsoMono-Medium", size: 12, relativeTo: .callout)` | 16 | tracking +0.4 if uppercase |
| menu bar text | Silkscreen 11 (`MenuBarIcon.pixelImage`) | `NSFont(name: "ClepsoPixel-Regular", size: 10)` | — | 1 font pixel = 1 pt; vertically centre on the 16 pt icon |

Line heights are the spacing the specimens were checked at; SwiftUI sets them with `.lineSpacing(lh - size × 1.2)`
only where multi-line text needs it (both faces have a 1.2 em default line). `relativeTo:` keeps Dynamic Type; at
non-default text sizes the pixel face will not be pixel-snapped, which is acceptable.

Keep the system monospaced face as the fallback: CoreText cascades per character, so anything outside Clepso Mono's
set (Greek, Cyrillic, most of Latin Extended) still renders. If a type-designer review of Clepso Mono is not possible
before release, keep `.label`/`.supporting`/`.micro` on the system face and adopt only Clepso Pixel (NOTES.md §5).

## 3. Menu bar icon (`MenuBarIcon.swift`)

The ring is unchanged; the brand mark replaces the 2 × 2 "lit core" of the `.ring` state:

```swift
case .ring: return [(3, 8), (4, 8), (5, 4), (5, 5), (5, 6), (5, 7), (5, 8), (6, 3), (7, 4), (7, 5), (7, 6), (7, 7),
                    (7, 8), (7, 9), (7, 10), (7, 11), (8, 12), (9, 9), (9, 10), (9, 11), (10, 8), (11, 8), (12, 8)]
```

(also in `menubar/MenuBarBeat.swift.txt`; full matrix in `menubar/clepso-menubar-matrix.txt`). Template PNGs, if an
image asset is preferred to code drawing: `menubar/ClepsoMenuBarTemplate-16.png` / `-16@2x.png` (16 pt) and
`-18.png` / `-18@2x.png` (18 pt, 1 pt padding); mark the asset "Render As: Template Image".

Proposed, not required: `.bar` (exhausted) becomes a 1 p flatline across x 3–12 on row 8, the beat with its spike
removed (`menubar/state-flatline.png`). The five states stay distinct by shape.

## 4. App icon

There is no app icon today (`project.yml` has no asset catalog). Copy `design/brand/app-icon/AppIcon.appiconset` into
`App/PulseMac/Assets.xcassets/` (with the catalog's own `Contents.json`: `{"info":{"author":"xcode","version":1}}`),
add the catalog to the `PulseMac` target's sources in `project.yml`, and set
`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. `Clepso.icns` is there for anything that needs a single file.
The app is `LSUIElement` (no Dock icon), so the icon shows in Finder, Launchpad, Spotlight, System Settings
(Login Items) and notifications.

macOS 26 (Icon Composer, `.icon`) was not produced here. `clepso-app-icon.svg` is layered for it: `body-layer`
(background), `matrix-off` (unlit pixels), `matrix-glow` and `matrix-on` (the mark).

## 5. Website

`scripts/build-site.py` writes `/assets/favicon.svg` and the header logo (`LOGO`), and `scripts/site/shell.css` loads
Silkscreen as `--p-pixel`. To finish the switch:

- `LOGO` and `favicon.svg`: use `design/brand/favicon/favicon.svg` (the 12 p symbol on an ink tile) and add
  `<link rel="icon" href="/favicon.ico" sizes="any">` + `apple-touch-icon.png`.
- `shell.css`: `@font-face` for `Clepso Pixel` and `Clepso Mono` from `/design-system/brand/fonts/*.woff2` (already
  published by this branch), then `--p-pixel: "Clepso Pixel", …` and `--p-mono: "Clepso Mono", ui-monospace, …`.
- Pixel sizes on the site: multiples of 10 px (`h1` 50, `h2` 30, `h3` 20; the hero 80, 50 on phones).

The rebuilt design-system page is `site/design-system/index.html` (same path as before; no new nav entry needed).
