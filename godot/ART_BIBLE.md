# Lanternbound — Realms of the Starfall: art bible

The game is a stylised anime fantasy open-world action RPG. Reference points are modern anime
open-world games (bright skies, cel-shaded characters, magical architecture, cinematic light)
with an original identity: the **Starfall** — fallen star-light that crystallised across the
land and lifted pieces of it into the sky. Nothing is copied from another game: no characters,
logos, UI assets or music.

Every asset, shader and screen is judged against this page. If it does not fit, it is changed
or replaced, even if it already "works".

## 1. Mood
Wonder first. Clear blue skies and golden sunsets, white-and-gold spires, floating isles with
waterfalls, glowing flowers, ancient star ruins. Danger is violet and black (the Void), never
brown and muddy. **Nothing reads as Viking, rustic, medieval-timber or "survival camp".**

## 2. Master palette
| Role | Colours |
|---|---|
| Sky | cerulean #2961DB → pale horizon #B8D6FA; sunsets gold-pink-violet |
| Starlight (magic, UI accents) | gold #F5D68F, pale starlight #F2EEFF, cyan glow #6FD9FF |
| Void (enemies, corruption) | violet #7A4CFF, black-purple #1A1030, crimson accents |
| Foliage | fresh greens, never olive; flowers lilac, white, sky blue, buttercup |
| Stone (architecture) | warm white #EDE6DA, sandstone #D9C3A0, slate trim #5A6478 |
| Roofs | cobalt #2F57A8, teal #2E8C8A, violet slate #5B4E8C; gold ridges and finials |
| UI panels | deep indigo glass #171A38 at 82–90 %, gold 1–2 px edges, radius 14–18 px |

## 3. Regions (each has a silhouette, a colour, an air and a reason to go)
| Region | Silhouette & landmarks | Ground & plants | Air (fog/light tint) | Motes |
|---|---|---|---|---|
| **Greenwood / Starfall Haven** | white-stone town on a plateau, magic tower, plaza fountain, banners; floating isle overhead | bright meadow grass with wildflower patches, round broadleaf trees | clear, warm | butterflies, birds |
| **The Gloomwood** | tall dark pines, mossy ruins, glowing mushrooms | deep teal grass, ferns | teal haze, dimmer sun | cyan glimmers |
| **The Blight** | twisted trees, violet crystal spikes, Void scars | violet grass, ash patches | violet fog | violet spores |
| **The Sunscar** | mesas, wind-carved arches, sun-bleached ruins | sand and dry tufts, no meadow grass | warm, bright, light haze | drifting dust |
| **The Ashlands** | volcanic cones and craters, basalt spires, lava rivers in channels | ash-grey ground, dark basalt, ember plants | orange-brown haze | rising embers, smoke |
| **The Frostpeaks** | snow ridges, ice crystals, a frozen shrine | snow, blue ice, sparse pines | cold blue-white | snowfall |
| **Sky isles** | lobed rims, banded cliffs, vines, waterfalls; the Starspire's light pillar | grass crowns, crystals | cloud puffs at their waists | — |

Borders blend (grass, fog and motes all fade across a region edge). No black voids, no abrupt
cut-offs, no isles without updrafts or clouds to explain them.

## 4. Characters
Anime proportions and faces, readable silhouettes (twin tails, capes, ribbons, horns), layered
fantasy clothing — never fur, rough leather or plain tunics. Heights: heroine 1.56 m, youths
1.6–1.72 m, adults 1.7–1.8 m, bosses 2 m+. Each character has its own idle, walk and speed
(`CharacterKit.HERO_STYLE`). Shading: two-tone toon light, cool tinted shade (never black),
thin rim light, ink outline 1–2 px at 1080p, skin lit nearly flat; pale hair gets lilac shade
and a glossy ring so it never clips to white.

Main heroine: silver-lavender twin tails, small horns, bat wings and tail, oversized black
jacket with lilac ribbons, plaid skirt. A male lead will follow.

## 5. Architecture — "Starfall Haven" style
- **Materials:** warm white stone walls with sandstone quoins; slate-blue or teal roofs with
  gold ridge caps and finials; arched windows with blue glass that glows at night; dark wood
  only as trim (balconies, doors), never as log walls or half-timbering.
- **Shapes:** tall, slender, vertical; round towers with conical roofs; arches and colonnades;
  a landmark visible from every street (the magic tower, the plaza fountain).
- **Details:** banners in indigo and gold with the four-point star, lanterns on posts, flower
  boxes, fountains, stairs and small bridges, crystal ornaments.
- **Forbidden:** half-timbered Tudor houses, log cabins, thatch, wooden palisades, rustic
  workbenches as town decoration.

## 6. Equipment and items
Swords are elegant, with crystal and gold fittings; catalysts and staves glow. Gathering tools
are magical: a **starcutter blade** (trees, plants), a **crystal resonator** (ore and crystal
nodes); they are summoned to the hand in a burst of starlight and vanish after use. Resources
are crystals, star-ore, luminous plants and void cores. Crafting stations are altars and arcane
workbenches with floating runes. Every item has a real model and an icon rendered from it.

## 7. Materials and textures
Stylised, not photoreal: hand-painted or softly textured albedo, gentle normal detail, no
noisy high-frequency photo grit. Texel density consistent between neighbours. Phone budgets:
characters ≤ 1024 px colour, props ≤ 512 px, ground layers 1024 px tiling with a second
macro scale to hide repeats.

## 8. Lighting and atmosphere
Bright key sun with soft shadows (not harsh black), sky-tinted ambient, ACES tone map, mild
bloom on emissive magic only, height fog plus a region tint, drifting cloud shadows on the
land, aerial perspective so far hills turn blue. Nights are moonlit blue and readable, with
warm lanterns and glowing windows. No blown-out whites, no oversaturated greens.

## 9. VFX
Light and starry: additive glows, soft round sparks, crescent sword trails (cyan light,
gold heavy), star rings on skills, dust tinted to the ground underfoot. Restrained shake.
Enemy telegraphs in Void violet/red.

## 10. UI
Cinzel / Cinzel Decorative for titles and menus, Fredoka for numbers, Cormorant Italic for
flavour lines. Gold diamond markers, indigo glass panels, round icon buttons with thin gold
rims, rarity-coloured item cards with stars. Touch targets ≥ 96 px at 1080p. Every button
does something.

## 11. Asset quality gate (every import)
1. Licence allows use (CC0 / CC BY with credit in `ASSET_CATALOG.md`); never named characters
   from other franchises, never non-commercial or share-alike for shipped art.
2. Fits sections 4–7 (no medieval timber, no Viking).
3. Correct real-world scale, seated on the ground, facing +Z, collision where it blocks.
4. Merged to few draw calls (`MeshMerge`), textures capped for phones, distance culled.
5. Seen in a capture from the game before it is committed.

## 12. Screenshot audit (capture harness; re-check after every pass)
1 main menu · 2 Greenwood · 3 player character · 4 Ashlands · 5 other regions · 6 combat ·
7 inventory · 8 character screen · 9 crafting · 10 dialogue. Current status in `PROGRESS.md`.
