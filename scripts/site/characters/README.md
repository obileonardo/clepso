# Clepso character-art preview

Original procedural pixel drawings from the founder-reviewed “literary guild” study, 21 October 2026.
The public website integrates this preview; the native app retains its existing characters until a separate,
version-aware compact-art implementation is completed and verified.

`sprites.js` contains the integer-grid artwork. `study.js` provides selection, authored poses, pause,
grayscale and reduced-motion previews. No model account, prompts or usage data are read or transmitted.
The current-sprite JSON reproduces existing Clepso bitmaps only for the before/after comparison.
Fonts reuse the website’s existing Clepso fonts and accompanying open font license.

Rebuild the public pages with `python3 -I scripts/public_site.py site v0.3.0-alpha.2`.
The main documentation generator invokes the same builder at the end, so the landing page and character
preview are retained on future documentation builds. Private QA images and local configuration are not copied.
