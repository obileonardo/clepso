# Third-party notices

> **Draft.** Prepared during the open-source readiness review. It lists every third-party component found in this
> repository and in what Pulse ships; the maintainer should confirm it before the first public release.

Pulse's own source code is intended to be released under the MIT License (not yet granted; see the README's Licence
section). The components below are **not** covered by that licence; each keeps its own.

## Shipped in Pulse.app

### GRDB.swift 7.11.1

- Use: SQLite toolkit for the local database (`Sources/Storage`). Linked into the app.
- Source: https://github.com/groue/GRDB.swift, revision `b83108d10f42680d78f23fe4d4d80fc88dab3212` (pinned in `Package.resolved`).
- Licence: MIT. Copyright (C) 2015-2025 Gwendal Roué. Full text: the `LICENSE` file in that repository at the
  pinned revision.
- Note: GRDB links the SQLite library that ships with macOS (`GRDBSQLite` system-library target). Its
  `SQLiteCustom/src` git submodule is fetched by Swift Package Manager but not compiled into Pulse.

The MIT License requires the copyright notice and permission notice to be included in copies of the software. A
binary distribution of Pulse should therefore include GRDB's licence text (for example in an "Acknowledgements"
file inside the app bundle or the release download).

### Fonts (SIL Open Font License 1.1)

Bundled in `Sources/DesignSystem/Resources/Fonts/` and copied into the app. Fetched from
https://github.com/google/fonts at commit `47d54ca1ebb14fd864695f1d39dc734f39017c33`; SHA-256 checksums are in
`Sources/DesignSystem/Resources/Fonts/README.md`. Each font's full licence sits beside it.

| Font | Files | Copyright | Licence file |
|---|---|---|---|
| Silkscreen | `Silkscreen-Regular.ttf`, `Silkscreen-Bold.ttf` | Copyright 2001 The Silkscreen Project Authors (https://github.com/googlefonts/silkscreen) | `Silkscreen-OFL.txt` |
| Pixelify Sans | `PixelifySans-Variable.ttf` | Copyright 2021 The Pixelify Sans Project Authors (https://github.com/eifetx/Pixelify-Sans) | `PixelifySans-OFL.txt` |
| VT323 | `VT323-Regular.ttf` | Copyright 2011, The VT323 Project Authors | `VT323-OFL.txt` |

The OFL allows bundling the fonts with software, including commercial software. The fonts may not be sold on their
own, and their licence must accompany them. The OFL does not change the licence of Pulse's code.

## Used by the documentation website only (`site/`, `scripts/site/`)

### three.js r160

- Use: the 3D footer scene on the documentation site (`scripts/site/village.js`). Not part of the app.
- Files: `scripts/site/vendor/three.module.min.js` and its copy `site/assets/vendor/three.module.min.js`
  (identical, SHA-256 `3e690ac7d180b0aadf0891bea39eec643e29e2d3e75c99b18689518665f69ba6`).
- Source: npm `three@0.160.0`; integrity recorded in `scripts/site/vendor/README.txt`.
- Licence: MIT. Copyright © 2010-2023 three.js authors. Full text: `scripts/site/vendor/three-LICENSE.txt` and
  `site/assets/vendor/three-LICENSE.txt`.

### Silkscreen (site copy)

`site/assets/fonts/Silkscreen-Regular.ttf` and `Silkscreen-Bold.ttf` are byte-identical copies of the app's fonts,
shipped with `site/assets/fonts/Silkscreen-OFL.txt`.

## Development tools (not distributed)

| Tool | Version | Licence | How it is obtained |
|---|---|---|---|
| XcodeGen | 2.46.0 | MIT | `scripts/bootstrap.sh` downloads the release zip from GitHub and checks its SHA-256 before use |
| Supabase CLI and local stack | Not pinned in this repository | Apache-2.0 (CLI); components vary | Installed by the developer, only for `make backend-test` |

## Third-party data and text

- `Sources/SubscriptionCatalog/Resources/plan-catalog.v1.json` describes subscription plans of Anthropic, OpenAI,
  Google and xAI. Each entry records its source URL and the date it was checked, and some entries quote short
  passages from those vendors' public help pages (`sourceQuote`). Those passages remain the vendors' text; they are
  quoted for reference and attribution.
- Test fixtures under `Sources/TestFixtures/Resources/claude-code/` reproduce the *structure* of Claude Code's
  status-line JSON with synthetic or scrubbed values.

## Trademarks

Claude and Claude Code are trademarks of Anthropic, PBC. Codex and ChatGPT are trademarks of OpenAI. Gemini is a
trademark of Google LLC. Grok is a trademark of xAI. Cursor, GitHub Copilot, Windsurf and other product names are
trademarks of their respective owners. They are used only to identify the tools Pulse works with or describes; Pulse
is not affiliated with or endorsed by them. The app shows sign-in providers as pixel monograms rather than their
logos, and the readiness review found no third-party logo image files in this repository.
