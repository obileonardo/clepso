# Third-party notices and brand assets

Pulse's source code is licensed under the MIT License (see [`LICENSE`](LICENSE)). The components below keep their own
licences. Inside the app, `Pulse.app/Contents/Resources/Acknowledgements.txt` carries GRDB's licence and points to the
font licences bundled beside the fonts.

## Shipped in Pulse.app

### GRDB.swift 7.11.1

- Use: SQLite toolkit for the local database (`Sources/Storage`), linked into the app.
- Source: https://github.com/groue/GRDB.swift, revision `b83108d10f42680d78f23fe4d4d80fc88dab3212` (pinned in
  `Package.resolved`).
- Licence: MIT. Copyright (C) 2015-2025 Gwendal Roué. The full text is reproduced in
  `App/PulseMac/Acknowledgements.txt`, which ships in the app.
- GRDB links the SQLite library that ships with macOS. Its `SQLiteCustom/src` git submodule is fetched by Swift
  Package Manager but not compiled into Pulse.

### Fonts under the SIL Open Font License 1.1

Bundled in `Sources/DesignSystem/Resources/Fonts/` (and so in the app), fetched from https://github.com/google/fonts at
commit `47d54ca1ebb14fd864695f1d39dc734f39017c33`; SHA-256 checksums are in that folder's `README.md`, and each font's
full licence sits beside it and ships with it.

| Font | Copyright | Licence file |
|---|---|---|
| Silkscreen | Copyright 2001 The Silkscreen Project Authors (https://github.com/googlefonts/silkscreen) | `Silkscreen-OFL.txt` |
| Pixelify Sans | Copyright 2021 The Pixelify Sans Project Authors (https://github.com/eifetx/Pixelify-Sans) | `PixelifySans-OFL.txt` |
| VT323 | Copyright 2011, The VT323 Project Authors | `VT323-OFL.txt` |

Since Pulse's own typefaces arrived, these three are still bundled but no longer used by the interface. The OFL allows
bundling with software; the fonts may not be sold on their own, and their licence must travel with them.

## Used by the documentation website only (`site/`, `scripts/site/`)

### three.js r160

- Use: the 3D footer scene on the documentation site (`scripts/site/village.js`); not part of the app.
- Files: `scripts/site/vendor/three.module.min.js` and the identical copy `site/assets/vendor/three.module.min.js`
  (SHA-256 `3e690ac7d180b0aadf0891bea39eec643e29e2d3e75c99b18689518665f69ba6`), from npm `three@0.160.0`.
- Licence: MIT. Copyright © 2010-2023 three.js authors. Full text beside each copy (`three-LICENSE.txt`).

### Silkscreen (site copy)

`site/assets/fonts/Silkscreen-*.ttf` are byte-identical copies of the app's fonts, shipped with `Silkscreen-OFL.txt`.

## Development tools (not distributed)

| Tool | Version | Licence | How it is obtained |
|---|---|---|---|
| XcodeGen | 2.46.0 | MIT | `scripts/bootstrap.sh` downloads the release zip and checks its SHA-256 |
| Supabase CLI and local stack | Not pinned here | Apache-2.0 (CLI); components vary | Installed by the developer, only for `make backend-test` |

## Pulse brand assets

The Pulse name, the Pulse mark and logo, the app icon and the menu bar mark (`design/brand/`,
`App/PulseMac/Assets.xcassets/`), and the **Pulse Pixel** and **Pulse Mono** typefaces (`design/brand/fonts/`,
`Sources/DesignSystem/Resources/Fonts/PulsePixel-*` and `PulseMono-*`, and copies under `site/design-system/brand/`)
are original works made for this project.

> **Open owner decision.** The two typefaces embed this licence text in their metadata: "Proprietary brand font of
> Pulse (working name). Free to use in Pulse products and materials; licence for third parties to be decided by the
> founder." That conflicts with distributing them under the repository's MIT licence. Before the repository is
> public, the owner should either license the typeface files openly (for example under the SIL Open Font License or
> MIT, and update the embedded text) or state here that they are excluded from the MIT grant and on what terms they may
> be redistributed with the code. The same choice applies to the logo and app icon, which projects often keep as
> trademarks even when the code is open.

"Pulse" is a working name; no trademark search has been done.

## Third-party data and text

- `Sources/SubscriptionCatalog/Resources/plan-catalog.v1.json` describes subscription plans of Anthropic, OpenAI,
  Google and xAI. Each entry records its source URL and the date it was checked; some entries quote short passages
  from those vendors' public help pages (`sourceQuote`). Those passages remain the vendors' text, quoted for reference
  with attribution.
- Test fixtures under `Sources/TestFixtures/Resources/claude-code/` reproduce the structure of Claude Code's
  status-line JSON with synthetic or scrubbed values.

## Trademarks

Claude and Claude Code are trademarks of Anthropic, PBC. Codex and ChatGPT are trademarks of OpenAI. Gemini is a
trademark of Google LLC. Grok is a trademark of xAI. Cursor, GitHub Copilot, Windsurf and other product names are
trademarks of their respective owners. They are used only to identify the tools Pulse works with or describes; Pulse
is not affiliated with or endorsed by them. The app shows sign-in providers as pixel monograms rather than their
logos, and no third-party logo image files were found in this repository.
