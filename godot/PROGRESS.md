# Progress report — Lanternbound

Branch `ccr-60ac94c6-dyqxhw`. Engine: Godot 4.4.1, GL Compatibility renderer, Android-first.
Read **DESIGN.md** first: it sets the game's direction (light as weapon and key, vaults,
relics, the Dark Tide, regions).

## Where things stand (tests: 109 pass via `tests/run.sh`)

### Reference-match pass: downloaded models (latest)

The user supplied reference images (a hooded dark-fantasy hero in a lush painted world) and
asked for real models close to them. Done through the Sketchfab API (token saved on the
environment for api.sketchfab.com; CC-BY models, all credited in ASSET_CATALOG.md):

| Change | What it is | How verified |
|---|---|---|
| **Cast** | Player = hooded assassin (hood, layered leathers, belts, cloak, bow, boots); Wren/Mira, Bram, Tobin, villager = realistic Fuse people; Aldous = bearded knight in blue plate; dead = dark-fantasy skeleton; guards = knight in plate; Warden = the Cursed Knight. `Settings.player_3d = true` | In-game captures, sword-combo filmstrip, boss capture |
| Rig pipeline | `tools/retarget_setup.gd` maps Mixamo / Unreal / Character Creator / Biped rigs onto Godot's humanoid profile (import retargeting); `assets/models/heroes/anim/humanoid.res` = UAL clips retargeted, shared by all; `tools/pack_characters.gd` shrinks for phones (player 66 MB -> 1.4 MB scene + VRAM-compressed textures) | `tools/preview_retarget.gd` sheets, tests |
| **3D items** | Pickaxe, axe, hammer, two swords, torch, fishing rod, two shields from Sketchfab, normalised by `tools/pack_items.gd` (grip at origin, shaft +Y, head +X), tinted by tier; replace the picture cards; enemies of the new cast carry them | `tools/preview_items.gd`, captures, test |
| **Village and landmarks** | Tavern, houses, lantern posts (glowing) behind the play plane near spawn; castles + waterfall rising from the far forest; abbey ruins and bridge in the tundra backdrop (`tools/render_scenery.gd`) | Captures |

Sources (`assets/models/sf_src`, git-ignored) must be re-downloaded to rebuild: the Sketchfab
ids are in ASSET_CATALOG.md. Not yet: the Gloam boss (still the Quaternius figure), a second
woman model for Mira, cave/crystal props from Sketchfab, real-device performance of the
heavier characters (several have 40-60 texture files; consider atlasing).

### Art-direction overhaul (earlier)

Goal (from the brief): a mature, stylized fantasy look: real proportions, layered clothing,
PBR materials, warm golden key light over blue shadows, restrained bloom.

| Change | What it is | How verified |
|---|---|---|
| **Player is the cut-out hero again** (by request) | The hand-drawn boy with the green shirt and brown hair (`CutoutBody`), `Settings.player_3d = false`; NPCs and enemies stay 3D. His collision capsule (68 x 196 px, centred on the torso, feet at the origin) was checked against the drawing with `--debug`: hair top to heel, so no resize was needed. The 3D hooded ranger remains available (`player_3d = true`) | Debug-overlay capture, attack filmstrip, tests (equipment tests now default to the cut-out player) |
| **New cast** | Quaternius Universal Base Characters + Modular Fantasy Outfits + Universal Animation Library 1&2 (CC0), built per character by `CharacterKit` (one shared 65-bone skeleton; outfits/hair reparented onto it; texture variants; 44 clips in one shared library). Player: hooded ranger in dusk-coloured leathers. Wren: lavender peasant wool, hair in buns. Bram: grey buzz-cut and beard, dark work clothes. Mira: ranger coat, long auburn hair. Tobin: ginger beard. Sir Aldous: steel-toned ranger plate, pauldron, long grey hair. Dead: ash skin, rags or rust, glowing eyes; zombies/shades shamble (zombie clips); the Warden is a giant in rusted plate, the Gloam a hooded violet wraith | Cast lineup (`tools/preview_kit.gd`), captures, hand-bone test |
| Hands | Items gripped by a node on `hand_r`/`hand_l` placed across the knuckles (index to pinky) and into the palm, so handles sit in the fist | Test, filmstrips of slash/dig/torch |
| Lighting of characters | Warm key (1.0, 0.86, 0.66), cool blue rim and ambient, per-character SubViewport | Captures |
| Portraits | Re-rendered close on the new faces (`tools/render_portraits.gd`) | Dialogue capture |
| **Terrain** | Atlas rebuilt from ambientCG photo materials (soil, rock, brick, sand, snow, planks, grass cap) with soft edge shading, levelled to the game's light (`tools/build_terrain_atlas.py`, fetches its sources) | Surface + cave captures |
| **Forest** | Playfield trees, bushes, ferns, flowers, rocks are renders of the Stylized Nature MegaKit; the parallax tree lines use the same renders behind fog, so near and far match | Captures |
| **Houses and ruins** | `WorldData.buildings` (saved): the cabin is drawn as a cutaway cottage (timber-framed plaster back wall with windows, tiled gable roof and chimney rendered from the Medieval Village MegaKit); ruins and the Warden's hall get an ivy-hung brick arcade repeated at character scale | Captures (`--x=s-6`, `--scenario=ruin`) |
| Size | KayKit character models removed (11 MB); only KayKit weapons remain | Tests |

Not done yet from the brief (next): talking animation and better panels in dialogue; sealed
vaults/Drowned Halls back-wall art; more building types (a village for the NPCs); water and
foreground layer restyle; global colour grade pass; Android texture budget check on a device.

### Earlier this session (from `6c194f2`)

| Change | What it is | How verified |
|---|---|---|
| **Real 3D characters** | `Body3D`: rigged models (first KayKit, now the Quaternius cast above), each filmed side-on by its own orthographic camera into a SubViewport and shown on a sprite at its feet. Truly side-facing; turns by rotating round through the camera; 19-21 skeletal clips (idle/walk/run/jump/chop/slash/block/dodge/hit/death/cast...), gait speed matched to ground speed; items on the `handslot.r` bone (KayKit 3D weapons, else the item picture on a camera-facing card gripped at its handle). Off-screen bodies stop rendering and animating; enemies render at 1x without MSAA. Setting `characters_3d` falls back to the old cut-out rig | Tests (hand-bone parenting, turn, footsteps), filmstrips of dig/chop/slash/torch/walk |
| Cast | Player = hooded wanderer (Rogue_Hooded), Wren = Mage, Bram = Barbarian, Tobin = Barbarian palette-swapped, Mira = Rogue palette-swapped, **Sir Aldous** = Knight (new). Undead: zombie/robot/shade/Warden/Gloam are KayKit skeletons with bone weapons; ordinary dead claw out of the ground on spawn | Cast preview (`tools/preview_cast.gd`), captures |
| Portraits | Rendered from the models (`tools/render_portraits.gd`) | Dialogue capture |
| **Flare** | Star button / Q: 25 glow; burns the dead, staggers the living, lights braziers within 3.5 tiles, wakes light-runes | Test, capture |
| **Sealed vaults** (6/world) | Brick room behind an unbreakable rune-stone door; antechamber with 3 cold braziers (one on a ledge); lit all = door opens on a gilded relic chest that bursts its loot | Test (layout, opening, chest), capture |
| **Hidden caches** (12/world) | Chest sealed in rock behind a cave wall, marked by a light-rune visible only after a flare (or with the Seer's Eye) | Test |
| **Relics** (8, 3 slots) | Featherbone (air jump), Ember Heart (ignite), Deepsong (ore glints), Moth Lantern (glow regrows), Bulwark (-25% harm), Swiftroot (+18% speed), Seer's Eye (runes, double map reveal), Luckstone (richer loot). Wear/take off in the pack panel; row under the vitals; saved | Test |
| **Dark Tide** | 2nd night, then ~1 in 3: sky turns violet-red, the dead rise around the player (max 5) except within 8 tiles of a lit light; extra glowshards; dawn refills the lantern | Test, capture |
| Sir Aldous's quests | "The Lightwardens' Vaults" (open a vault, wear a relic) then "The Hidden Marks" (find 2 caches); voiced | Quest tests driven by real vault/relic/cache events |
| Tobin trades | Old Coins (vaults, caches) buy torches, food, flasks, ore, wardstones, iron tools, heart crystals | Test |
| Cave near layer | Dark stalactite/stalagmite silhouettes at 1.5x parallax framing caves (2.5D depth) | Captures |
| **Bosses** | Three phases each, every move telegraphed. Warden: rolling shockwave slam (both ways later), shield charge that blocks from the front, blade spin, falling rocks in the last stand. Gloam: swoops, violet bolt volleys, blinks behind you, drains glow out of the light. Each phase calls the dead | Test (phases, shield), captures |
| **Fishing** | Rod (workbench); cast at water, strike within 0.9 s of the bite; fish/pearls/coins; glowfin in deep water cook into glow-restoring skewers; Mira's "Light from the Deep Water" | Test |
| **The Drowned Halls** (2/world) | Flooded brick ruin with an air strip and air pockets under bells, glowshard light, biters (swimming enemy), sunken shrine with the Tidecaller's Scale (9th relic: breathe water, swim fast). Breath meter; drowning | Tests (layout, breath, biters), captures (`--scenario=drowned`, `drowned_deep`) |
| Model size | `tools/slim_glb.py` keeps only used clips: characters 33 MB -> 11 MB | Cast preview, tests |

### Earlier (still true)
Trees chop in stages and break into log chunks; mining debris per material; hit-stop; hammers;
footsteps per surface; minimap with saved fog of war; spitters; cave dressing; 5 main + 5 side
quests; tutorial bot; save/load; weather and thunderstorms; foliage shader; light map.

## Not verified / not done

- **No real device** has run the game; no APK built. 3D characters each render their own
  SubViewport: fine in software rendering here, but **phone performance is unmeasured**.
- **Audio is unheard** (no sound device): checked by length/loudness only.
- Tutorial bot passes with the 3D characters (done at frame 2161, no script errors) after vault and
  cache generation got its own random stream (it had reshuffled the meadow and stranded the bot).
- Regions are still the original five biomes; DESIGN.md's region table is the target.
- No fishing, farming, pets, mounts, armour, enchanting yet.

## Next tasks (in order)

1. Confirm the tutorial bot passes again; fix whatever it finds.
2. (done: three-phase bosses with telegraphed moves, shockwaves, shield charge, spin, volleys,
   blink, falling rocks, glow drain.) Next: give each boss an arena worth the fight.
3. (done: the Drowned Halls.) Next regions from DESIGN.md: Ember Forge (volcanic ruins, fire
   enemies), Frozen Ruins (Rimefrost underground).
4. (done: fishing with bite timing, glowfin, Mira's quest.) Cooking buffs (meals that last).
5. Treasure maps (a chest find that marks an unopened vault on the minimap).
6. Phone build and real-device performance check of Body3D.

## How to check things

- Tests: `godot/tests/run.sh [name_filter]` (wraps `run_tests.gd`; also fails on any SCRIPT ERROR,
  which inside a test would otherwise abort it silently and count as a pass)
- New `class_name` scripts need `godot --headless --path godot --import` once.
- Captures: `xvfb-run -a -s "-screen 0 2340x1080x24" godot --path godot --rendering-driver opengl3 --resolution 2340x1080 --fixed-fps 60 -- --shot=out.png --touch --frames=N`
  plus `--scenario=cave|crystal|deep|ruin|vault|vault_open|...`, `--action=dig|chop|attack|walk|flare|tutorial|soak|...`,
  `--hold=item`, `--wear=relic_a,relic_b`, `--tide`, `--spawn=kinds`, `--boss=warden`, `--x=s-30`, `--strip=N --every=K`.
- Tools: `tools/preview_cast.gd`, `tools/preview_kit.gd`, `tools/preview_body.gd`, `tools/render_portraits.gd`,
  `tools/render_props.gd -- dungeon`, `tools/render_cottage.gd`, `tools/build_terrain_atlas.py`,
  `tools/character_palettes.py`, `tools/build_anim_library.gd`, `tools/slim_glb.py`,
  `tools/draw_relics.py`, `tools/bake_voices.py`.
- Software rendering is slow with several 3D bodies: keep captures short or use 1170x540.
