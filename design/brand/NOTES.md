# Pulse identity: design notes

Working notes behind the brand kit: what was decided, why, and what remains open. The public version of this is the
Brand section of the design-system page (`site/design-system/`).

## 1. The idea

Pulse watches a limit you cannot see and tells you before you hit it. Two things matter: **the limit** (a
container that fills) and **the live signal** (a reading that keeps arriving, or stops). The mark puts one inside
the other: **a heartbeat inside a ring**. The ring is the existing 16 px menu bar ring, so the logo and the status
icon are one object. The beat is the live reading. The same ring can hold other marks (warning, flatline, clock),
so the brand mark doubles as the "available" state of a status family that already exists in the code.

## 2. Explorations (sheets/explorations.png)

All six directions were drawn on the same 16 px grid and judged **at menu bar size first**, the way Susan Kare
judged the 1984 Macintosh icons at 1× before anything else.

| | Direction | Verdict |
|---|---|---|
| A | ECG line (the old favicon) | Generic health-app signifier; no silhouette at 16 px; cannot carry a status |
| B | Ring with a lit core (the 1.11 menu bar icon) | Reads as a radio button or record light |
| C | Pixel P monogram | Empty of meaning; tied to a working name; a pixel P blurs with D and R |
| D | Gauge with needle | Cliché; needle angle illegible at 16 px; implies precision the data does not always have |
| E | Signal bars | Reads as Wi-Fi or audio |
| **F** | **Beat in the ring** | **Chosen** |

Refining F: the trace touching the ring split it into a θ; a two-pixel beat clotted; a square screen became a chart
icon. The final beat floats with a 2 p margin and spans x 3–12, y 3–12: centred on both axes.

## 3. Construction (sheets/construction.png)

- Unit **p** = 1/16 of the symbol. Every edge on whole p. Stroke 1 p everywhere.
- Ring: the app's menu bar ring (`MenuBarIcon.ring`) unchanged, keyline circle r = 8 p.
- Wordmark: PULSE in Pulse Pixel capitals (7 p), tracked 2 p. Horizontal lockup gap 5 p, cap top 4 p below the
  symbol's top. Stacked: 4 p gap; the symbol sits at 9 p from the left (half a p right of true centre, because
  33 − 16 is odd); render at even scales below 64 px.
- Clear space 4 p on every side. Minimums: symbol 16 px (print 6 mm), horizontal lockup 54 × 16 px (print 20 mm).
- Below 64 px, scale only in whole multiples of the grid. Never resample a pixel mark between 16 and 64 px.
- A 12 p small symbol (the app's 12 px glyph grid) exists for the 16 px app icon and the favicon only.

This follows the rigour of the 1975 NASA *Graphics Standards Manual* (construction drawing, clear space, minimum
size and misuse pages for a single mark) rather than the looser "logo usage" pages common today.

## 4. Colour across themes

The identity **does not depend on green**. The mark is always one flat colour: the active theme's `accent` token on
that theme's `background` (Phosphor dark `#4DFF8F` on `#060907`, Phosphor light `#0A7238` on `#F3F1E7`, Ember
`#F4AE55` on `#130D09`, Classic `#1D4FD7` / `#7FA8FF`), or black / white. Shape carries recognition, colour carries
theme. This is the role-based approach of Material Design 3's tokens: name the role, let the theme supply the
value. The design-system page reads themes from `design.json`, so a new theme appears there without page changes.

Phosphor green stays the **signature** colourway (marketing, app icon, website) because recognition needs one
default. The app icon is fixed (macOS has no per-theme app icons beyond its own light/dark/tinted variants; see
INTEGRATION.md).

## 5. Type

**Why replace Silkscreen.** At display sizes Silkscreen's 5-pixel capitals are crude (the merged W in "ALLOWLIST",
the U and S in the site's hero), and the founder already hit legibility problems with pixel figures ("8.5B" read as
"8.SB" in Pixelify Sans, increment 1.8). A monitoring product lives on its numbers.

**Pulse Pixel** (display): 7-pixel capitals, 5-pixel x-height, 2-pixel descenders on a 10-pixel em. Designed
around disambiguation: dotted 0 vs O, flagged 1 with a foot vs serifed I vs tailed l, square-shouldered 5 vs
chamfered S, round 8 vs flat-backed B, 6/G and 9/g by their spurs. Figures, %, +, −, = are tabular (6 px). Kerning
is computed, not hand-listed: a pair tightens by 1 px only when no pixel of one glyph would touch the other
(8-connected), so open shapes (T, L, Y, F, P, r, quotes) tuck in and strokes never merge. 218 characters including
Latin-1 letters, arrows and ⌘ ⌥ ⇧ ⏎.

**Pulse Mono** (body): monospace, 600-unit cell, built from the same rounded rectangle as the pixel face's
chamfered corners, at high resolution. Vertical strokes heavier than horizontal (Regular 90/76) so the texture is
even; diagonals between. Weight is a parameter: Regular, Medium and Bold are one drawing.

**Is the body face good enough?** Assessed honestly against SF Mono at the app's real sizes (13 pt Medium, 12 pt
Regular, 2× display, CoreText; see `specimens/pulse-mono-specimen.png`): it is as legible in the app's sentences,
keeps every disambiguation, and gives the product its own voice. Limits, stated plainly:

- **Unhinted.** Fine on Retina Macs (macOS ignores hinting anyway); on 1× Windows screens it will look soft.
- **Coverage:** ASCII, Latin-1 letters, Š Ž Č, common symbols. No Greek, Cyrillic, full Central European, no
  italics. CoreText and browsers fall back per character, which would show a different face mid-word for names
  outside the set.
- **No optical-size masters, no type-designer review.** Joins and terminals are geometric, not hand-corrected.

Recommendation: use Pulse Mono on the website now, and in the app for labels and short sentences (the tokens in
INTEGRATION.md). Before it becomes the only text face of a shipping product, have a type designer review it
(1–2 weeks) and extend coverage. If that is not possible, the best licensed alternative for this language is
**JetBrains Mono** (SIL OFL 1.1, large Latin/Greek/Cyrillic coverage, hinted, weights 100–800); keep SF Mono as the
in-app fallback either way.

**Pairing rule.** Pixel speaks in numbers and labels (short, uppercase or figures); Mono explains (sentences,
captions, data). Never set a sentence in Pulse Pixel; never set a big figure in Pulse Mono.

**Pixel-snapping rule.** Pulse Pixel's pixel is 1/10 em. Sizes whose tenth is a whole number of device pixels render
without blur: multiples of 5 pt in the app on Retina (15, 20, 25, 30, 35, 40), multiples of 10 px on the web.

## 6. Voice

One voice, tones that adapt (the model of Mailchimp's *Content Style Guide*). The voice is **a precise instrument
that tells the truth**: plain words, numbers with their source and age, never a guess presented as a fact
("Estimate:" always says so), never "100% connected", never zero for missing. Tone shifts by moment: calm when
available, direct when a limit is near, factual (not apologetic) when data is missing.

## 7. References that informed the structure

| Reference | What it informed |
|---|---|
| NASA *Graphics Standards Manual* (Danne & Blackburn, 1975) | construction drawing, clear space, minimum sizes, misuse |
| Susan Kare's Macintosh icons (1984) | drawing on the pixel grid and judging at 1× first |
| IBM Design Language and IBM Plex | an identity that owns its typeface, with a written rationale |
| GitHub's Mona Sans and Hubot Sans | shipping brand fonts as a downloadable part of the guidelines |
| Uber's brand site (brand.uber.com) | web guideline structure: logo, colour, type, iconography, voice, downloads |
| Atlassian's design guidelines | explicit "don't" examples for the logo |
| Mailchimp *Content Style Guide* | voice constant, tone by situation, with examples |
| Apple Human Interface Guidelines (app icons, menu bar extras) | squircle template, icon sizes, template images |
| Material Design 3 colour roles | role-based tokens so the identity survives new themes |

## 8. Open

- **Name.** "Pulse" is a working name and a crowded word in software; no trademark search has been done. The
  symbol does not depend on the name; the wordmark and the font names do (one constant each in `logo.py` and
  `fontmeta.py`).
- **Font licence.** The faces are original (no OFL source). Founder decision, 17 Oct 2026: released under the SIL OFL
  1.1 with Reserved Font Names "Pulse Pixel" and "Pulse Mono"; the logo, name and icons stay reserved (TRADEMARKS.md).
- **Menu bar status family.** The flatline / warning / clock / broken-ring set is a proposal; `MenuBarIcon` in the
  app still draws its own marks.
