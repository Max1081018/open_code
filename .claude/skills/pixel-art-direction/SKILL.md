---
name: pixel-art-direction
description: The art bible for Deepdelve. Load before generating or changing any sprite, tile, texture or palette, so everything drawn stays one coherent style.
---

# Deepdelve Art Direction

All art in this project is **generated in code**. There are no image files.
This is a deliberate choice: dedicated asset sites are unreachable from the
build environment, and a single generator enforces cohesion that scavenged
asset packs cannot.

Everything below is a constraint, not a suggestion. Breaking one makes the
game look like several games.

## The one rule

**Nothing is a flat rectangle.** Every drawn thing has, at minimum: a base
colour, noise-based variation, and light-aware edge shading. A flat fill is
a bug.

## Scale

| Thing | Size | Why |
|---|---|---|
| Tile source texture | 48×48 px | Room for real detail; 16px is Terraria's and looks like ants on a phone |
| Render scale | integer 2× | Fractional scaling muddies pixel art |
| On-screen tile | 96 px | ~24 tiles across a landscape phone, vs Terraria's 45-60 |
| Character height | 1.8 tiles (~173 px) | ~18% of screen height: readable at arm's length |
| Character source | 44×80 px | Rendered at 2×; enough pixels for a face |

Constants live in `core/src/view.rs`. Never hardcode a size that belongs there.

## Palette

Colours are **ramps**, not single values. Every material defines at least a
shadow, a base and a highlight, and all three come from one hue family.

Never use pure black (`0,0,0`) or pure white (`255,255,255`). Shadows are
dark and *blue-shifted*; highlights are bright and *warm-shifted*. This single
habit is most of what makes art read as hand-made rather than computed.

```
shadow  = base darkened, hue pushed toward blue
base    = the material's identity colour
highlight = base lightened, hue pushed toward yellow/orange
```

Reference ramps (RGB base):

| Material | Base | Notes |
|---|---|---|
| Soil | 134, 96, 62 | Warm brown |
| Rock | 118, 118, 126 | Faintly blue-grey |
| Grass crown | 84, 152, 58 | Ragged lower edge, never a ruled line |
| Sand | 214, 192, 138 | Low contrast, fine grain |
| Snow | 228, 236, 246 | Blue-shifted, never blown-out white |
| Skin | 232, 186, 152 | Warm |
| Cloth | 78, 102, 162 | The player's identity colour |

## Lighting

One light, from the **upper left**, everywhere, always.

Edge shading is a function of a tile's *context*, not its material: a tile
buried in rock must blend seamlessly with its neighbours, while one at a cave
mouth catches light on its exposed faces. This lives in `art::edge_shade` and
takes an `Exposure`. Baking a bevel into a material texture makes the ground
read as a wall of separate bricks — that was tried and reverted.

## Variation

One texture per material makes a wall of stone visibly repeat. Every material
generates `TEXTURE_VARIANTS` (6) variants, chosen per tile by a position hash.
Any new material must do the same.

## Characters

Characters are **built from parts**, not drawn as one blob, so animation can
move the parts independently:

```
head (with face)  ← eyes and mouth live here
torso
arm far / arm near
leg far / leg near
```

Faces are small and expressive. The eye is 2–3 px of dark on a lighter
sclera; the mouth is a 3–5 px line that changes shape with state. At 2× these
read clearly without becoming cartoonish.

Proportions: head is roughly 1/3 of total height. This is a slightly
stylised, readable proportion rather than realistic 1/7.

## Anti-patterns

- Flat fill with no noise → looks computed
- Pure black shadows → looks cheap
- Bevel baked into material → ground looks like brickwork
- One texture per material → visible tiling
- A face drawn at 1 px → unreadable mush at any scale
- Mixing a new hue family in without adding it to this table
