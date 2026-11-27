# Progress report — the anime fantasy overhaul

Branch `ccr-60ac94c6-dyqxhw`. Godot 4.4.1, GL Compatibility renderer, Android-first.
Main scene: `scenes/main3d.tscn` (the 3D open world). The art direction is in
**ART_BIBLE.md**; every third-party asset and its licence is in **ASSET_CATALOG.md**.

Tests: **117 pass** (`godot/tests/run.sh`; it also fails on any SCRIPT ERROR).

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
| S7 Combat polish | pending | — | — |
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
- Region centres (seed 1337): Greenwood (0,0), Gloomwood (-864,432), Frostpeaks (-336,0),
  Sunscar (-960,-288), Ashlands (820,-860), Blight (240,-48).
