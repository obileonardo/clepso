# Clepso literary-guild characters

Original procedural pixel drawings from the founder-reviewed study, 21 October 2026. This artwork also ships in the
native Mac Models screen from 0.3.0 alpha 3: version-aware portraits, still roster/track markers and authored motion.

`sprites.js` is the source artwork. `node scripts/build-character-art.mjs` freezes its four poses and palette into
`ModelCharacterAtlas.swift`; `--check` is a CI parity gate. Native rendering uses cached pixel runs, physical-pixel
placement, a compact raster for small markers, Pause/Resume and system Reduce Motion. Unknown models keep a robot.

`study.js` provides the public interactive selection, poses, grayscale and reduced-motion comparison. Its level-up
flourish is a website-only demo. No model account, prompts or usage data are read or transmitted. The current-sprite
JSON preserves the original twelve-cell bitmaps solely for the before/after comparison. Fonts reuse the existing
Clepso website fonts and open font license.

Rebuild with `python3 -I scripts/public_site.py site v0.3.0-alpha.3`. The main documentation generator invokes the
same builder, preserving the product page and characters. Private QA images and configuration are never copied.
