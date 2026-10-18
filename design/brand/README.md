# Clepso brand kit

Everything here is generated from code in `pipeline/`. Edit the sources, run the build, commit the outputs.

```sh
design/brand/pipeline/build.sh            # everything, then font checks and the OpenType Sanitizer
design/brand/pipeline/build.sh fonts      # or one stage: fonts | logo | sheets | specimens
```

The script creates a virtualenv (`$CLEPSO_BRAND_VENV`, default `design/brand/.venv`, git-ignored) from
`pipeline/requirements.txt`. Builds are deterministic: fonts carry a fixed timestamp, so an unchanged source gives
byte-identical files.

| Needs | Version used | Why |
|---|---|---|
| Python | 3.12 (Homebrew) | |
| fontTools | 4.55.3 | font compilation, OTF/TTF/WOFF2, feature compiler |
| skia-pathops | 0.8.0.post2 | boolean geometry for Clepso Mono (exact Béziers, overlaps removed) |
| uharfbuzz | 0.45.0 | shaping (with kerning) when text is set as outlines in SVG |
| Brotli | 1.1.0 | WOFF2 compression |
| Pillow | 11.1.0 | pixel-exact PNGs, app icon compositing |
| CairoSVG | 2.7.1 (+ cairocffi 1.7.1, Homebrew `cairo`) | SVG sheets to PNG |
| opentype-sanitizer | 9.2.0 | the OTS validator browsers run on web fonts |
| Swift / CoreText | Xcode command line tools | `render.swift`: specimens rendered by the Mac's own text engine |
| iconutil | macOS | `Clepso.icns` from the iconset |

## Outputs

| Folder | Contents |
|---|---|
| `fonts/` | Clepso Pixel Regular; Clepso Mono Regular, Medium, Bold. Each as `.ttf`, `.otf`, `.woff2` |
| `logo/svg/` | `clepso-{symbol,symbol-small,wordmark,horizontal,stacked}-{phosphor,deep,black,white,on-ink,on-paper}.svg` |
| `logo/png/` | the same at whole-pixel scales; file name ends in the pixel width. Plus `clepso-logo-email-244.png`, the account emails' header logo (copied to `site/assets/email/`, see `docs/EMAIL.md`) |
| `app-icon/` | `clepso-app-icon.svg` (layered master), PNG 16–1024, `Clepso.iconset`, `Clepso.icns` |
| `menubar/` | `ClepsoMenuBarTemplate-16.png`, `-16@2x`, `-18`, `-18@2x`; status family `state-*.png` (seven states, two stale variants); `clepso-menubar-matrix.txt`; `MenuBarBeat.swift.txt` |
| `favicon/` | `favicon.svg`, `favicon.ico` (16/32/48), `favicon-{16,32,48}.png`, `apple-touch-icon.png` |
| `sheets/` | logo sheet, construction grid, explorations, app icon, menu bar (SVG + PNG at 2×) |
| `specimens/` | Clepso Pixel, Clepso Mono and type-system specimens, rendered by CoreText |

## Pipeline map

| File | Role |
|---|---|
| `pixel_glyphs.py` | Clepso Pixel drawn as bitmaps, accents composed, kerning computed |
| `pixels.py` | traces pixel sets into clean outlines (shared by font, logo and icons) |
| `build_pixel_font.py` | Clepso Pixel → TTF/OTF/WOFF2 |
| `geom.py`, `mono_glyphs.py` | Clepso Mono constructed from rounded rectangles; weight is a parameter |
| `build_mono_font.py` | Clepso Mono → TTF/OTF/WOFF2 in three weights |
| `fontmeta.py` | names, vertical metrics, OS/2, licence string, reproducible timestamps |
| `logo.py` | symbol matrices, wordmark, lockups, colourways, app icon, menu bar family (+ the app's `MenuBarGlyphs.swift`), favicon |
| `typeset.py` | text set in the Clepso faces as SVG outlines |
| `sheets.py`, `specimens.py`, `render.swift` | presentation sheets and CoreText specimens |
| `type_system.py` | the type scale as data (app tokens and web scale) |
| `check_fonts.py` | required characters, metrics consistency, tabular figures, fixed pitch, contour direction, no reserved names |

See `NOTES.md` for the reasoning behind the identity and `INTEGRATION.md` for wiring the fonts and icons into the app.
