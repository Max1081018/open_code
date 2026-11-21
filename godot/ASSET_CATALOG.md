# Asset catalogue — Lanternbound

Every asset, its source, and its licence. Derived files are reproducible:
`tools/build_assets.py` builds `assets/` from the Kenney mirror, and
`tools/render_props.gd` renders the 3D props.

## Art — Kenney (CC0 1.0)

All art is by [Kenney](https://kenney.nl), released into the public domain
under Creative Commons Zero (`assets/KENNEY-LICENSE.txt`). Fetched from the
GitHub mirror [shorepine/kenney](https://github.com/shorepine/kenney), since
kenney.nl itself is unreachable from the build environment. One vendor was
chosen deliberately so every asset shares one outline weight, palette logic
and shading style.

| Pack | Used for | Notes |
|---|---|---|
| New Platformer Pack | terrain, liquids, torches, ladders, doors, gems, hearts, enemy creatures, parallax backdrops | 128 px "Double" tiles; terrain atlas derived (see below) |
| Toon Characters | the player (Male adventurer), zombies, robots, the guide | full pose sets: walk ×8, run ×3, jump, fall, attack ×3, hurt, death, interact, climb |
| Voxel Pack + Voxel Expansion | tool and weapon icons in five metal tiers, ore lumps, food | the ore lumps double as in-rock ore overlays |
| Background Elements Remastered | trees for every biome, bushes, cacti, clouds, sun, moon | |
| UI Pack – Adventure | panels, buttons, checkboxes, banners | |
| Mobile Controls (Style A) | joystick pad and nub, action buttons, icons | |
| Foliage Pack | ground cover: three grasses (`foliagePack_018–020`) and three flowers (`foliagePack_001–003`) in `scenery/foliage/` | swayed by `shaders/sway.gdshader` |
| Particle Pack, Light Masks | flames, sparks, dust, smoke, slashes, motes, glow halos | |
| Survival Kit, Graveyard Kit (3D) | chest, workbench, anvil, grindstone, campfire, barrel, bottle, wood, lanterns, obelisk (wardstone), altar, signpost | rendered to sprites by `tools/render_props.gd` |

### Derived in `build_assets.py`

- **Held equipment** (`equipment/torch_held.png`, `shield_wood.png`,
  `shield_iron.png`): original art drawn by `tools/draw_equipment.py` in the
  Kenney flat style (the Kenney torch is a wall sconce; its only shields
  are 70 px). Released with the project under CC0.
- **Rig data** (`scripts/actors/rig_data.gd`): fist positions per pose
  frame and grip points per item icon, measured from the art by
  `tools/build_rig.py`.
- **Leaf** (`fx/leaf.png`): drawn procedurally in `build_foliage()`; no
  outside source.

- **Terrain atlas** (`tiles/terrain.png`): 9 materials × 16 neighbour masks.
  Two materials are derived: *soil* (grass soil with the grass cap recoloured
  to an outlined soil lip) and *basalt* (the rock stratum re-tinted for the
  deep). Rock also has Kenney's orange dirt crust recoloured to rock, so cave
  floors don't grow soil.
- **Ore overlays** (`tiles/overlay.png`): the Voxel ore icons composited as
  lumps with contact shadows, two patterns per ore; plus three crack stages.
- **Parallax layers** (`scenery/parallax/`): Kenney backdrops with their baked
  sky flood-filled to transparency, so far hills, near hills and a live
  time-of-day sky can stack.
- **Block icons** (`blocks/`): the fully outlined lone-block piece of each material.

## Audio — Soundza (Soundza Standard License)

From [Soundza](https://soundza.com): free for commercial and personal use, no
attribution required; files may not be redistributed on their own or in a
sample pack. Full list with links in `assets/audio/*/SOUNDZA-LICENSE.txt`.

- **Effects** (mono 16-bit 22 kHz, trimmed, level-matched, ≤14 ms onset):
  dig, break, hit, hurt, jump, land, step, pickup, craft, roar, click, chest,
  swing. **The swing whoosh is AI-generated** per Soundza's own label.
- **Music** (Ogg Vorbis, looped): *Grasslands* (outdoors), *Malchak Crystal
  Cave 2* (underground), *Epic Boss Battle* (boss fights), *Sand Castles*
  (title). 88 MB of source WAV encoded to 4.5 MB.

## Fonts — SIL Open Font License 1.1

- **Lilita One** (titles, numbers) and **Fredoka** (body), from
  [google/fonts](https://github.com/google/fonts). Licence texts in
  `assets/fonts/`.

## Tried and not used

- **Generated images** (3D AI Studio): good foliage, but its CDN is blocked
  here and only a 6 kB lossy preview arrives — fatal for crisp art.
- **Kenney Platformer Pack Medieval**: an older flat style that clashed with
  the rest.
- **SpriteCook, Figma**: their servers failed to connect from this environment.


## Voices — Piper (MIT)

Every spoken line is synthesised offline by `tools/bake_voices.py` with
[Piper](https://github.com/rhasspy/piper) (MIT) and shipped as Ogg Vorbis
in `assets/voice/`; no model is in the game. Voices, from
[rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices), each
under the licence on its model card:

| Character | Voice |
|---|---|
| Wren | en_US-amy-medium |
| Old Bram | en_GB-alan-medium |
| Mira | en_GB-jenny_dioco-medium |
| Tobin | en_GB-northern_english_male-medium (dataset: OpenSLR 83, CC BY-SA 4.0) |

NPC bodies: Kenney Toon Characters (CC0) — Female adventurer (Wren),
Female person (Mira), Male person (Bram; recoloured for Tobin by a script:
ginger hair, leather apron, dark trousers), Parts HD on the cut-out rig.

## Ambience and new effects — Soundza

From [Soundza](https://soundza.com) under the Soundza Standard License
(free for commercial use; listed in `assets/audio/sfx/SOUNDZA-LICENSE.txt`):
tree fall, wood chop, close and distant thunder; ambience loops for rain
through trees, a forest bird chorus and cave drips. Loops are cut to 40 s
with an equal-power crossfade by `tools/make_loop.py`.

## 3D characters, buildings and nature — Quaternius (CC0)

By Quaternius (quaternius.com), CC0 1.0 (`assets/models/quaternius/LICENSE-Quaternius.txt`).

| Pack | Used for |
|---|---|
| Universal Base Characters | Every person and every risen dead: one 65-bone body (male/female) with face, eyes and skin |
| Modular Character Outfits – Fantasy | Ranger and peasant outfits, hoods, pauldrons, hair and beards, mixed per character in `scripts/actors/character_kit.gd` |
| Universal Animation Library 1 and 2 | The 44 clips the cast plays (`assets/models/quaternius/anim/humanoid_anims.res`, built by `tools/build_anim_library.gd`) |
| Stylized Nature MegaKit | Rendered to sprites (`assets/rendered/nature/`): trees, pines, dead and twisted trees, bushes, ferns, flowers, rocks — in the playfield and the parallax backdrops |
| Medieval Village MegaKit | Rendered (`tools/render_cottage.gd`, `assets/rendered/village/`): the cottage's timber-framed wall and gable roof, the ruins' brick arcades |

Outfit colour variants (dusk ranger, steel, rust, lavender, rags, ash skin) are recolours of the
pack textures by `tools/character_palettes.py`. Source glTFs not shipped (nature, village) go in
`assets/models/nature_src` / `village_src`, which are git-ignored.

## Terrain materials — ambientCG (CC0)

By ambientCG (ambientcg.com), CC0 1.0: Ground048 (soil), Rock058 (rock, basalt, crystal), Bricks089,
Ground054 (sand), Snow010A, Grass004 (grass cap), Planks012. Built into `assets/tiles/terrain.png`
by `tools/build_terrain_atlas.py`, which downloads them itself.

## Weapons and dungeon props — KayKit (CC0)

By Kay Lousberg (www.kaylousberg.com), CC0 1.0. Licences kept beside the files
(`assets/models/kaykit/LICENSE-KayKit-*.txt`, `assets/models/LICENSE-KayKit-Dungeon.txt`).

| Pack | Used for |
|---|---|
| KayKit Adventurers 1.0 | Swords, axes, shields, staff held in the characters' hands |
| KayKit Dungeon Remastered 1.0 | Rendered to sprites: gilded relic chest, braziers, candles, banner, trophy and other vault props |

(The KayKit character models were the cast before the Quaternius one; they are no longer shipped.)
