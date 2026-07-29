# Font Asset Handoff

## Scope and Current Decision

- This document covers the Phaser gameplay runtime and its Maker NanoVG port.
- The Phaser level editor is deliberately excluded from the Maker migration.
- Exact font replication is deferred until redistributable font files are supplied.
- Existing SVG source files remain untouched. In particular, this document does
  not authorize editing SVG text, paths, view boxes, fills, strokes, or transforms.

## Source of Truth

The Phaser project ships no `.ttf`, `.otf`, `.woff`, `.woff2`, or `.eot` files.
Its browser output depends on the first available face in each CSS/Phaser font
stack. Therefore, the supplied files must be accompanied by the intended face
for the original reference environment; a similar-looking replacement is not a
pixel-equivalent substitute.

| Text group | Original stack | Original runtime locations | Current Maker alias | Current Maker file | Intended Maker alias after font handoff |
| --- | --- | --- | --- | --- | --- |
| Display Chinese | `"STKaiti", "KaiTi", "Noto Serif SC", Georgia, serif` | `src/game/PlayScene.ts` `FONT_DISPLAY`: title, stage and rule values, objective, card titles, Newton role, success/failure titles, action labels | `maker-display` | `Fonts/MiSans-Regular.ttf` | `maker-display` -> approved KaiTi/STKaiti face |
| Body Chinese | `"Noto Sans SC", "Microsoft YaHei", Arial, sans-serif` | `src/game/PlayScene.ts` `FONT_BODY`; replay controller/feed modules; CSS root defaults | `maker-body` | `Fonts/MiSans-Regular.ttf` | `maker-body` -> approved original body face |
| Serif English | `Georgia, serif` and `Georgia, 'Times New Roman', serif` | `PlayScene.ts`: `ISAAC NEWTON` and scientific/serif labels; `public/assets/lab-bg.svg`: `F = ma` | none | none | `maker-serif` -> approved Georgia face |
| Sans-serif English, digits, symbols | `Arial, sans-serif` | `PlayScene.ts`: pause icon, counts, level index, rule symbols, percentage, direction effects; replay timeline uses Arial | none | none | `maker-sans` -> approved Arial face |
| Phaser editor only (excluded) | `"STKaiti", "KaiTi", serif` and `"Noto Sans SC", "Microsoft YaHei", sans-serif` | `src/style.css`: editor toolbar and inspector | none | none | No Maker mapping required |

`PlayScene.ts` declarations are at lines 72-73. The corresponding CSS defaults
are in `src/style.css` line 3. The SVG background is a preserved source asset;
its own `Georgia,serif` declaration must not be modified.

## Known Reference Environment

On the current Windows reference machine, `C:\Windows\Fonts\simkai.ttf` is
available and is the observed practical fallback for the display-Chinese stack.
It is a system font, not a project asset. Do not copy it into this project or
submit it to Maker unless the project owner confirms redistribution rights.

The same rule applies to `Microsoft YaHei`, `Georgia`, and `Arial`. Their
presence on a development machine does not grant packaging or publishing rights.

## Current Maker Implementation

`scripts/migration/Renderer.lua` creates only these two NanoVG faces:

```lua
self.fontBody = nvgCreateFont(self.vg, "maker-body", "Fonts/MiSans-Regular.ttf")
self.fontDisplay = nvgCreateFont(self.vg, "maker-display", "Fonts/MiSans-Regular.ttf")
```

The default for `Renderer:Text` and `Renderer:TextBox` is `maker-body`.
Gameplay calls that require display typography pass `maker-display` explicitly.
This is a functional fallback only; it is not the final pixel-reference mapping.

## Files Needed From the Owner

Provide legally redistributable, unmodified font binaries and identify the face
that was used to create the approved Phaser visual reference:

| Required logical face | Suggested Maker destination | Required confirmation |
| --- | --- | --- |
| KaiTi/STKaiti display face | `assets/Fonts/DisplayKaiTi.ttf` | Exact face/version and redistribution permission |
| Original Chinese body face | `assets/Fonts/BodySans.ttf` | Exact face/version and redistribution permission |
| Georgia face | `assets/Fonts/SerifEnglish.ttf` | Exact face/version and redistribution permission |
| Arial face | `assets/Fonts/SansEnglish.ttf` | Exact face/version and redistribution permission |

If a supplied font is a collection such as `.ttc`, provide an extractable,
single-face `.ttf`/`.otf` or identify an engine-supported way to select the
correct face. The current NanoVG API call accepts one resource path per alias.

## Deferred Implementation and Acceptance Checks

After assets are supplied, make the following scoped changes:

1. Register `maker-display`, `maker-body`, `maker-serif`, and `maker-sans` in
   `Renderer:Init` using the supplied resource paths.
2. Map every existing runtime text call to its original group; do not change
   source SVG files or restore the Phaser editor.
3. Build with Maker and ensure every `nvgCreateFont` call returns a valid face.
4. Compare fixed `1880x840` design-space captures for title, card hand, Newton
   panel, replay, and success/failure overlays against the Phaser reference.
5. Re-run `migration/fast_validate_phase1.py`, the Maker runtime log check, and
   desktop/mobile-landscape layout checks after the font swap.

Until this handoff is completed, font fidelity is explicitly excluded from the
pixel-level acceptance claim. Physics, rules, level data, SVG-derived bitmap
assets, input mapping, replay, and responsive design-space behavior remain in
the current migration acceptance scope.
