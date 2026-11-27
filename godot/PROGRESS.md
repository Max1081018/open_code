# Progress report — the anime fantasy overhaul

Branch `ccr-60ac94c6-dyqxhw`. Godot 4.4.1, GL Compatibility renderer, Android-first.
Main scene: `scenes/main3d.tscn` (the 3D open world). The art direction is in
**ART_BIBLE.md**; every third-party asset and its licence is in **ASSET_CATALOG.md**.

Tests: **125 pass** (`godot/tests/run.sh`; it also fails on any SCRIPT ERROR).

## Stages (from the overhaul brief)

| Stage | Status | What was done | How it was checked |
|---|---|---|---|
| S0 Audit | done | Project, tools, skills and MCP servers surveyed; checkpoint commit | — |
| S1 Art bible | done | `ART_BIBLE.md`: palette, region table, architecture rules (no half-timber), materials, lighting, VFX, UI, asset quality gate, screenshot audit | — |
| S2 World visuals | done | Broad, soft grass clumps with meadow/bare patches and per-biome roots; region trees, rocks and landmark formations from CC-BY packs (sakura, pines, rocks, sandstone, volcanic) split per piece by `tools/split_nature.gd`; colliders on trees, rocks and formations | Captures of every region |
| S3 Greenwood | done | Rebuilt as an elegant fantasy town from a procedural kit (`ArchKit`): plastered houses with cut-stone bases, glazed cobalt/teal/violet roofs, arched windows that glow at night, balconies, towers, a mage tower, a gate, a star fountain with a floating crystal; old timber houses removed | Street, aerial, night and east captures; ~1,335 draw calls in town |
| S4 Regions | done (first pass) | **The Ashlands**: four volcano cones with craters, lava pools, smoke columns and embers; lava flows down the slopes (terrain shader); the region's lakes are crusted lava with glowing seams; lava burns and throws the heroine to shore. **Every region**: its own sky and air (fog + sky tint), hued ground tint blended over ~30 m at borders, region flora (Gloomwood dense blue-green pines, Sunscar sandstone stacks, Frostpeaks pines and pale rock, Blight twisted trees and void-veined rock). Trees dither out near the camera and in front of the heroine | Captures: Ashlands wide/ground/night, lava burn, Gloomwood ground+aerial, Blight aerial, Sunscar, Frostpeaks, Greenwood regression |
| S5 Characters & animation | done (first pass) | The heroine runs on an **AnimationTree**: a gait blend space (idle → walk → jog → sprint) placed along her speed so starts and stops blend, played at the rate that keeps planted feet still (clip ground speeds measured by `tools/measure_gait.gd`; the old code over-sped the walk 1.5×); two crossfading clip slots for every other move. **Death** (she could not die before): Death01, controls lock, screen fades, she wakes at the town gate getting up (LayToIdle) with full health and 3 s of mercy. Heavy blows knock her back (Hit_Knockback), light ones alternate head/chest reactions; long drops end in a crouching hard landing; she banks into turns at speed | Side-on walk/run/stop filmstrips (`--side`), death→respawn filmstrip (`--action=die`), `tests/test_player3d.gd` |
| S6 Tools/weapons/items | done | Fantasy pickaxe, axe, hammer, caged torch, rod, heater and round shields (CC BY, credited), re-rendered icons with tier tints; the heroine's own **Violet Moonblade** (fights and gathers: no starting axe/pickaxe); wings removed from the model and the key art | Item lineup, icon sheet, chop/mine filmstrips |
| Progression + arts | done | `Progression`: XP from foes, trees, rock, quests; levels raise HP/stamina/damage and open the Moonblade's arts: Lv 2 Crescent Wave, Lv 3 Arcane Comet (E), Lv 5 Violet Starfall (Q); padlocks with the level on sealed buttons; violet XP line; level-up banner; saved. VFX library `Arcana` (rune circles, arcane pillar, flashes, sparks, homing orb, star lances); magic sounds from Soundza | `test_progression.gd`, comet/starfall filmstrips day and night |
| S7 Combat polish | done | Combos, charged heavy, telegraphs, stagger, hit sparks both ways; ten zone foes with fighting styles (ranged casters keep distance and strafe, chargers crouch then lunge, slammers ring the ground), element lights, health bars | `test_telegraph.gd`, fight captures |
| Engine plugins | installed | Jolt Physics on (`physics/3d/physics_engine`); Recast (Godot's NavigationServer3D) drives foes through `NavField`: a 112 m navmesh window baked on a worker thread around the heroine (height field + carved trees/rocks, no water), re-baked every 28 m, ~80-120 ms off-thread; foes path around obstacles and spread apart. Terrain3D, godot_voxel and Effekseer GDExtensions are installed and load (classes verified) but **no content uses them yet** | `test_navfield.gd` |
| World size + map design | done | Island grown from 3 km to 5 km across; climate and mountain noise lowered so each region is one large coherent zone (Greenwood 5.7 km², Frostpeaks 3.5, Gloomwood 2.4, Sunscar 1.5, Blight 1.1, Ashlands 1.0); the Ashlands moved to the NE corner with five volcanoes. Terrain still streams in 64 m chunks, so the runtime cost per frame is unchanged; the horizon mesh uses 32 m cells | Biome map render |
| Weather | done | `Weather3D`: each region draws spells from its own table: Greenwood clear/showers/thunderstorms (lightning + thunder), Gloomwood mist and drizzle, Frostpeaks snow and blizzards, Sunscar sandstorms, Ashlands ashfall with embers, Blight rising violet motes and void storms. Fog, fog tint, sun and cloud cover follow it; rain loop; particle counts scale with quality | `test_weather.gd` |
| Quest lines | done | Ten regional quests after the Night Hunt: for each region, wake its Starstone, then defeat its foes (Mira: Gloomwood, Aldous: Frostpeaks and Ashlands, Tobin: Sunscar, Wren: the Blight), with dialogue and rewards; the tracker points at the stone | `test_region_quests.gd` |
| Floating idle | done | After ~4.5 s still she rises and reclines on the air (FloatPose skeleton modifier + 35° tilt, one knee drawn up, slow breathing drift) over a turning violet rune circle with a dusk underlay, motes and light; any input brings her down | Side-on captures, day |
| S8 Systems | pending | — | — |
| S9 UI | done (in-game screens) | HUD: held-item slot + backpack button, sealed skills. Screens in one style (header, emblem, chips, violet panels, gold selection): Backpack (categories, rarity slots, details, Equip/Use/Discard, Sort), Crafting (new: requirements have/need, stepper, Craft, forge rule), Character (level/XP, attributes, Arts page), Pause tiles, Quests, Map (region names), Settings; centred on wide phones | `test_menus3d.gd`; captures of every screen at 1920x1080 and 2340x1080 |
| S10-12 Lighting, sourcing, mobile | pending | — | — |
| S13-14 Tests, QC, report | pending | — | — |

## Next exact step

Stage 7 combat polish (charged heavy attack, enemy telegraphs and stagger), then
S10-12: quality presets (FPS cap, resolution scale) and a draw-call budget pass.

## Known issues

- Foot sliding was fixed by measurement and stills; it has not been judged in motion
  (video) — the gait rates may need a small visual tune.
- Sprint clip's natural speed (4.9 m/s) is far below sprint speed (8.2): played at the
  1.55× cap it still slides a little at full sprint.

- Dense forests: the low-poly pine boughs are large; the camera can sit among them
  (they thin out, but the view is busy).
- The ground plain at the lava lakes' shores is flat; it could use more relief.
- Smoke columns are particle billboards; from inside a column they would fill the view
  (distance fade keeps it readable at the tested angles).

## Not verified

- **No phone has run this build.** Everything was checked in the Linux runtime with
  software OpenGL under Xvfb (captures, headless tests). Frame rate, memory and thermal
  behaviour on Android are unmeasured.
- **Audio is unheard** (no sound device in the container).
- Touch controls are drawn and wired but not exercised with real touches.

## How to check things

- Tests: `cd godot && tests/run.sh [filter]`. After adding a `class_name`, run
  `godot --headless --path . --import` once.
- Captures: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3
  --resolution 1920x1080 --fixed-fps 60 res://scenes/main3d.tscn -- --shot=OUT.png --frames=50`
  plus `--at=x,z --yaw= --pitch= --dist= --time=0..1`, `--cam=x,y,z --look=x,y,z` (free camera),
  `--action=walk|run|sprint|jump|attack|fight|skills|glide|talk`, `--menu=bag|map|book|person|gear`,
  `--strip=N --every=K` (filmstrip), `--stats` (draw calls).
- Region heartlands are the Starstones (`Starstones.heartlands`); Greenwood is at (0,0), the Ashlands centre at (1250,-1300).
- `--weather=rain|thunderstorm|mist|snow|blizzard|sandstorm|ashfall|voidmotes|clear` pins the weather; `--float` makes her float at once.
