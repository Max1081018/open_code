# Progress report — the anime fantasy overhaul

Branch `ccr-60ac94c6-dyqxhw`. Godot 4.4.1, GL Compatibility renderer, Android-first.
Main scene: `scenes/main3d.tscn` (the 3D open world). The art direction is in
**ART_BIBLE.md**; every third-party asset and its licence is in **ASSET_CATALOG.md**.

Tests: **111 pass** (`godot/tests/run.sh`; it also fails on any SCRIPT ERROR).

## Stages (from the overhaul brief)

| Stage | Status | What was done | How it was checked |
|---|---|---|---|
| S0 Audit | done | Project, tools, skills and MCP servers surveyed; checkpoint commit | — |
| S1 Art bible | done | `ART_BIBLE.md`: palette, region table, architecture rules (no half-timber), materials, lighting, VFX, UI, asset quality gate, screenshot audit | — |
| S2 World visuals | done | Broad, soft grass clumps with meadow/bare patches and per-biome roots; region trees, rocks and landmark formations from CC-BY packs (sakura, pines, rocks, sandstone, volcanic) split per piece by `tools/split_nature.gd`; colliders on trees, rocks and formations | Captures of every region |
| S3 Greenwood | done | Rebuilt as an elegant fantasy town from a procedural kit (`ArchKit`): plastered houses with cut-stone bases, glazed cobalt/teal/violet roofs, arched windows that glow at night, balconies, towers, a mage tower, a gate, a star fountain with a floating crystal; old timber houses removed | Street, aerial, night and east captures; ~1,335 draw calls in town |
| S4 Regions | done (first pass) | **The Ashlands**: four volcano cones with craters, lava pools, smoke columns and embers; lava flows down the slopes (terrain shader); the region's lakes are crusted lava with glowing seams; lava burns and throws the heroine to shore. **Every region**: its own sky and air (fog + sky tint), hued ground tint blended over ~30 m at borders, region flora (Gloomwood dense blue-green pines, Sunscar sandstone stacks, Frostpeaks pines and pale rock, Blight twisted trees and void-veined rock). Trees dither out near the camera and in front of the heroine | Captures: Ashlands wide/ground/night, lava burn, Gloomwood ground+aerial, Blight aerial, Sunscar, Frostpeaks, Greenwood regression |
| S5 Characters & animation | next | — | — |
| S6 Tools/weapons/items | pending | — | — |
| S7 Combat polish | pending | — | — |
| S8 Systems | pending | — | — |
| S9 UI | pending | — | — |
| S10-12 Lighting, sourcing, mobile | pending | — | — |
| S13-14 Tests, QC, report | pending | — | — |

## Next exact step

Stage 5: audit the heroine's locomotion (start/stop, turning, fall/land, hit, death,
foot sliding) with `--action=walk|run|sprint|jump` filmstrips, then build the
AnimationTree state machine and fix what the strips show.

## Known issues

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
