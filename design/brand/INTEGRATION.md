# Wiring the Clepso identity into the app and site

Written on the brand branch as the edits to make afterwards. **Status, 19 Oct 2026: every step below is applied**:
fonts, typography tokens and the app icon in 1.16 (`3d70caf`), the menu bar state family in item 7 (`7eb3477`), the
site in `261c05b`, the old third-party fonts removed in `020afef`. The file now records where each brand file lives in
the app and on the site, and what to keep in mind when one changes.

## 1. Fonts

Applied (1.16). Bundled in `Sources/DesignSystem/Resources/Fonts/` (a `.copy` resource; every `.ttf` in it is
registered by `PixelFonts.ensureRegistered()` at process scope):

| File | Family | PostScript name | Weight |
|---|---|---|---|
| `design/brand/fonts/ClepsoPixel-Regular.ttf` | Clepso Pixel | `ClepsoPixel-Regular` | 400 |
| `design/brand/fonts/ClepsoMono-Regular.ttf` | Clepso Mono | `ClepsoMono-Regular` | 400 |
| `design/brand/fonts/ClepsoMono-Medium.ttf` | Clepso Mono | `ClepsoMono-Medium` | 500 |
| `design/brand/fonts/ClepsoMono-Bold.ttf` | Clepso Mono | `ClepsoMono-Bold` | 700 |

`PixelFonts.swift` names them by PostScript name (`display = "ClepsoPixel-Regular"`, `body = "ClepsoMono-Regular"`,
`bodyMedium = "ClepsoMono-Medium"`, `bodyBold = "ClepsoMono-Bold"`), used with `.custom(_:size:)`: PostScript names are
unambiguous where family names are not. Silkscreen, Pixelify Sans and VT323 were removed from the app, site, CI and
notices on 18 Oct 2026 (`020afef`).

When a face changes, update the checksum table in `Resources/Fonts/README.md` (`shasum -a 256`). Licence: original
faces under the SIL OFL 1.1 with Reserved Font Names (`ClepsoFonts-OFL.txt`; NOTES.md §8).

## 2. Typography tokens (`Theme.font(_:)`, pixel branch)

Clepso Pixel's pixel is 1/10 em: on Retina, sizes that are multiples of 5 pt land every pixel on whole device pixels.

| Token | Before 1.16 | Now (`Theme/Tokens.swift`, `MenuBarIcon.swift`) | Line height | Notes |
|---|---|---|---|---|
| `.metricHero` | Silkscreen 34 | `.custom("ClepsoPixel-Regular", size: 35, relativeTo: .largeTitle)` | 40 | `.monospacedDigit()` not needed: figures are tabular |
| `.metricMedium` | Silkscreen 22 | `.custom("ClepsoPixel-Regular", size: 20, relativeTo: .title2)` | 24 | |
| `.title` | Silkscreen 15 | `.custom("ClepsoPixel-Regular", size: 15, relativeTo: .headline)` | 20 | uppercase as today |
| `.label` | system mono `.body` medium (13) | `.custom("ClepsoMono-Medium", size: 13, relativeTo: .body)` | 18 | |
| `.supporting` | system mono `.callout` (12) | `.custom("ClepsoMono-Regular", size: 12, relativeTo: .callout)` | 17 | |
| `.micro` | system mono `.callout` semibold (12) | `.custom("ClepsoMono-Medium", size: 12, relativeTo: .callout)` | 16 | tracking +0.4 if uppercase |
| menu bar text | Silkscreen 11 (`MenuBarIcon.pixelImage`) | `NSFont(name: "ClepsoPixel-Regular", size: 10)` | — | 1 font pixel = 1 pt; centred on the 16 pt icon so the baseline is on a whole point; drawn aliased (no antialiasing or font smoothing), hard pixels like the glyph (`382e60c`) |

Line heights are the spacing the specimens were checked at; SwiftUI sets them with `.lineSpacing(lh - size × 1.2)`
only where multi-line text needs it (both faces have a 1.2 em default line). `relativeTo:` keeps Dynamic Type; at
non-default text sizes the pixel face will not be pixel-snapped, which is acceptable.

The system monospaced face stays the fallback: CoreText cascades per character, so anything outside Clepso Mono's
set (Greek, Cyrillic, most of Latin Extended) still renders. Clepso Mono was adopted for `.label`/`.supporting`/`.micro`
without a type-designer review; if one finds problems before release, those three tokens can go back to the system
face and keep Clepso Pixel only (NOTES.md §5).

## 3. Menu bar icon (`MenuBarIcon.swift`)

Applied (item 7). The app draws the kit's status family: `logo.menubar_states()` is the one table, and
`build.sh menubar` writes `menubar/state-*.png` and `Sources/DesignSystem/Theme/MenuBarGlyphs.swift` (the generated
`MenuBarIcon.Shape` and its rows) from it. `PixelMenuBarIconTests` fails if the Swift drifts from the PNGs.

| App state (`OverviewSnapshot.Icon`) | Glyph | Means |
|---|---|---|
| `ok` | `beat` | at least one live reading and nothing outranks it (other cards may be old or not available); also "reporting, no rate limits sent" |
| `approaching` | `approaching` (!) | a limit is nearing capacity |
| `exhausted` | `flatline` | a limit is reached, or the reset of a limit that was reached is awaited: the beat with its spike removed |
| `stale` | `stale` (clock) | no live reading; the last one is old |
| `demo` | `demo` (broken ring) | demo data, not the account |
| `waiting` | `waiting` (…) | installed, no reading yet |
| `notConnected` | `not-connected` (empty ring) | nothing to read: no trace at all |

The stale modifier (`state-approaching-stale.png`, `state-flatline-stale.png`) marks a shape built from old readings:
the ring opens at five o'clock and a 2 × 2 dot sits in the gap. The % text (Clepso Pixel, 10 pt) can follow any glyph;
the app shows it beside the beat and approaching only, from the live readings behind the shape, never beside the
flatline (founder, 19 Oct 2026; UX_SPEC 1.4).
The status item's accessibility value says the state in words (`MenuBarIcon.spokenState`). The beat matrix is in
`menubar/clepso-menubar-matrix.txt`. Template PNGs, if an image asset is ever preferred to code drawing:
`menubar/ClepsoMenuBarTemplate-16.png` / `-16@2x.png` (16 pt) and `-18.png` / `-18@2x.png` (18 pt, 1 pt padding);
mark the asset "Render As: Template Image".

## 4. App icon

Applied (1.16, `3d70caf`). `design/brand/app-icon/AppIcon.appiconset` is copied into
`App/ClepsoMac/Assets.xcassets/`, which the `ClepsoMac` target picks up through its `App/ClepsoMac` sources, and
`project.yml` sets `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. When the icon changes, regenerate the set with the
brand pipeline and copy it over again. `Clepso.icns` is there for anything that needs a single file.
The app is `LSUIElement` (no Dock icon), so the icon shows in Finder, Launchpad, Spotlight, System Settings
(Login Items) and notifications.

macOS 26 (Icon Composer, `.icon`) was not produced here. `clepso-app-icon.svg` is layered for it: `body-layer`
(background), `matrix-off` (unlit pixels), `matrix-glow` and `matrix-on` (the mark).

## 5. Website

Applied (`261c05b`, renamed in `f6597c6`):

- `LOGO` and `/assets/favicon.svg` in `scripts/build-site.py` come from `design/brand/favicon/favicon.svg` (the 12 p
  symbol on an ink tile); every page links `/favicon.ico`, the SVG favicon and `apple-touch-icon.png`.
- `scripts/site/shell.css` declares `@font-face` for `Clepso Pixel` and `Clepso Mono` from
  `/design-system/brand/fonts/*.woff2`, with `--p-pixel: "Clepso Pixel", …` and `--p-mono: "Clepso Mono", ui-monospace, …`.
- Guideline, not a check: Clepso Pixel sizes on the site in multiples of 10 px (`h1` 50, `h2` 30, `h3` 20; the hero
  80, 50 on phones). `shell.css` still sets the pixel face at 14 and 15 px in the search label and header button
  (19 Oct 2026).

The rebuilt design-system page is `site/design-system/index.html` (same path as before; no new nav entry needed).
