# ShowdUp design source

Editable brand assets for the redesign. The live, clickable board is
https://claude.ai/artifact/6m1sFupT16ibwzejiuTKac (private to the owner until shared).

## What's here

| Folder | Contents | Open with |
| --- | --- | --- |
| `brand/mark/` | Logo mark in all five states, launcher icon (512 px, full bleed), monochrome themed icon, notification icon, wordmark | Figma, Illustrator, any vector editor |
| `brand/icons/` | 24 icons on a 24 px grid, 2 px round stroke | Figma (drag in), or recolor via `stroke` |
| `brand/companion/` | Dot companion: 6 species × 5 moods | Figma, Illustrator |
| `brand/animals/` | Illustrated animal option: 5 species × 3 moods | Figma, Illustrator |
| `brand/tokens.json` | Colors, type styles, spacing, radii, motion in the W3C design-tokens format | Tokens Studio for Figma (Import → JSON) |
| `brand-board/` | Source of every artboard (`*.dc.html`) and the canvas layout (`canvas.json`) | Re-publish to the board; not a standalone web page |

## Fonts

Both are free under the SIL Open Font License. Install them before opening
`wordmark.svg` or any screen, or text falls back to a system font.

- Big Shoulders Display 800: numbers and one-word shouts — https://fonts.google.com/specimen/Big+Shoulders+Display
- Bricolage Grotesque 500 and 700: everything else — https://fonts.google.com/specimen/Bricolage+Grotesque

## Rules to keep when editing

- Ink `#0E0E0C` background with one accent, mint `#5CF0BE`. No orange or amber anywhere.
- Text on mint is always ink. Stone `#8F8A80` text only on ink or carbon, never on graphite.
- One hero number and one primary action per screen. No emoji, gradients, glass or bordered card grids.
- The mark is one shape with five states. Keep the geometry; change only color.
- Touch targets at least 48 dp.

When a change is approved, update `brand/tokens.json` and tell the app side:
tokens map one-to-one to `lib/design/tokens.dart` once Phase 2 lands.
