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
