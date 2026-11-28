# Progress report — the anime fantasy overhaul

Branch `ccr-60ac94c6-dyqxhw`. Godot 4.4.1, GL Compatibility renderer, Android-first.
Main scene: `scenes/main3d.tscn` (the 3D open world). The art direction is in
**ART_BIBLE.md**; every third-party asset and its licence is in **ASSET_CATALOG.md**.

Tests: **142 pass** (`godot/tests/run.sh`; it also fails on any SCRIPT ERROR).

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


## Complete-game pass (DEV_PLAN.md stages)

| Stage | Status | What was done | How it was checked |
|---|---|---|---|
| P1 Audit + tools | done | DEV_PLAN.md; skills search (none extra), Higgsfield (credits used for all front-end art and terrain textures), 3D AI Studio (background removal, free credits now used up), 3D Valley needs re-auth | — |
| P2 Startup | done | Loading screen with real threaded progress → sign-in (guest; local development email accounts with salted iterated hashes, reset code shown on screen; Google/Apple behind a provider interface that refuses when unconfigured) → title → character → island → loading → world. Per-account profile and save | `test_account.gd`, front-end captures |
| P3 Character + islands | done | Character screen (Lyra live 3D on the painted terrace, drag to turn, Kael locked); three starting islands with painted previews; spawn at the chosen land; choice saved on profile and journey | `test_start_islands.gd` |
| P4 Sunscar Sea | done | Large designed desert with crescent dunes, crossing ripples, wide flats, oases, colonnade, Sun Gate; sand shader (Higgsfield 1k seamless sand, ripple normals, crest/slip shading, pinpoint glints); footprints, sinking, slower/uphill-slower walking, slip-face sliding, kicked sand, heat shimmer, clear blue sky and hard sun | desert captures |
| Character fixes | done | SkirtSolver (skirt chains collide with thigh and shin capsules every frame after the pose, gravity drape, no tunnelling); hands on the rig's finger bones, cuffs shortened; camera 3.5 m; floating idle after 1.6 s | live jog/sprint strips, hand close-ups |
| P5 First adventure | done | Arrival flyover with letterbox and chapter title (skippable), Lumi the star-wisp, ten-step teaching chain per island with tips, tracker, rewards, relic, saved progress | `test_adventure.gd` plays the jungle chain through |
| P6 Secrets, combat, presentation, audio, optimisation, QC | largely done (see overnight pass) | — | — |

## Overnight autonomous pass (latest)

| Area | Status | What was done | How it was checked |
|---|---|---|---|
| Washed-out graphics | done | The milky haze was height fog (a 10% veil on everything under 30 m) plus heavy region fog; replaced by thin distance haze with aerial perspective and valley mist. ACES tone mapping, stronger sun, ambient driven each frame from the sky colours (the sky radiance map lit far too weakly in this renderer). Foliage: canopy-shaped normals, crown self-shadow, translucency, per-tree hue; fixed stippled tree shadows. Natural grass colour, meadow variation, texture relief; jungle undergrowth grass; deep-coloured crystals | Before/after captures; shade pixels measured (sky ambient vs colour ambient vs AO on/off) |
| "Ray tracing" | honest | Godot 4.4 has **no ray tracing** on any renderer, and the game uses GL Compatibility for Android reach (SSAO/SSR/SDFGI/volumetric fog exist only in Forward+, which would cost most phones their frame rate). Instead, screen-space effects built on the depth buffer: **ambient occlusion** and **sun shafts**, each a toggle in Settings | Depth shaders compile in every variant (checked in logs); AO/no-AO captures |
| Floating magic weapon | done | `MagicHold`: swords and tools float under her magic, not in her fist. At rest the blade hovers upright beside her right hand (tilted out, bobbing, streaming back at speed, following her body so it never lags). A strike snaps it to the palm's line and follows the clip's swing arc; a cast raises and spins it; Blade Orbit sends it circling. Purple magic, faint at rest, bright in a strike, brightest in a cast, with pulses on sudden moves: palm glow, hilt ring, palm-to-hilt energy strand, wisps and a soft light. Torches and shields stay gripped | `test_magic_hold.gd`; front, side and attack captures |
| Movement feel | done | MotionPose layer: an anime sprint lean (body forward, chin level, arms back) and a falling tuck; violet streams off her hands at full sprint. Idle/walk/jog/sprint blend space, jump start/air/land and idle breaks were already in place and play | Sprint and jump filmstrips |
| Touch controls | done | Jump is the **same size as attack** (radius 60) and sits apart from it in the thumb corner (46 px gap); dash, three arts and the ultimate arc above. Button size, opacity and camera sensitivity now take effect (sensitivity used to be mouse-only and unsaved) | `test_controls.gd`: equal size, no overlaps, all on screen at 16:9 and 20:9 at max size, taps reach each, settings apply |
| Combat maths | done | `DamageCalc`: one documented formula for every blow, both ways (level, weapon, skill multiplier, armour, resistances, crits, Mark, guard, variance; clamped, never NaN, negative or overflowing). The number shown is the health taken. Foes have armour by style, plus resistances and weaknesses | `test_combat.gd` (formula cases, NaN/INF, overflow, one cut per swing per foe) |
| Five arts + ranks | done | Combo, Crescent Wave (heavy), Arcane Comet, **Phase Step** (new: a blink through foes that cuts and Marks them), Violet Starfall (ultimate), and **Blade Orbit** (new: the floating blade circles her, at most one cut per foe every 0.45 s). Unlock levels, cooldowns, ranks 1–3 bought with skill points (one per level), an Arts page with Rank-up buttons, saved; over-spent saves are clamped. New painted icons (Higgsfield) | `test_combat.gd` |
| Thinking foes | done | Line-of-sight sight, hearing, search where she was last seen, return home and rest, skirmishers retreat when badly hurt; state field. **Fixed**: every foe's home post was the world origin | `test_enemies.gd` |
| Island creatures | done | Each island has its own foes beyond the shared ones. Jungle: Vine Stalkers (ambush from the ground) and Root Guardians (shields). Sky: Gale Sprites (fliers, ranged) and Aerie Sentinels (shields, slams). Coast: Crystal Husks (ambush), Tide Callers (ranged) and Coral Knights (shields). A shield turns aside light blows from the front, so strike from behind or with a heavy blow; the number shown is still the health taken. About one foe in twelve is an Elite: golden aura, 2.5x health, 1.3x damage, double loot. On sky isles, foes now spawn on the isle itself (they used to spawn on the land far below) | `test_enemies.gd::test_island_creatures` |
| Island guardians | done | Thornmother (jungle: root lines, ring, summons, charge), Stormwing (sky, flies: volleys, dives, ring, summons), Tidewarden (coast: crystal rain, ring, charge, summons). Each has a runestone arena, an intro banner, phases at 60% and 30% with telegraphs (the ring can be jumped), boss bar, boss music, loot, XP and saved defeat; the tracker points to it after the chapter | `test_enemies.gd`; fight captures |
| Secrets | done | Discovery of named places, eight starlit chests with mote clues, three rune shrines (strike the stones in the order of their marks), starsilver veins, the Colossus of Kings at night; all saved. Starsilver forges the **Astral Edge** | `test_enemies.gd::test_secrets` |
| Relics | done | They were rewards that did nothing in 3D. Now worn in three slots (Wear/Remove in the backpack) with real effects (less harm, speed, air jump, power, luck, stamina, swimming, farther-seen secrets); saved | `test_relics.gd` |
| Audio | done | The open world had **no music**: exploration and boss tracks now play, plus forest/cave ambience on a new Ambient bus. Master and Ambience volume sliders added | Manual code path; not listenable headless |
| Settings | done | Scrolling page: presets Low/Medium/High/**Ultra**; shadows, bloom, ambient occlusion, sun shafts, anti-aliasing (off/FXAA/MSAA 2x/4x), view distance (near → farthest), render scale, frame rate, FPS, shake, sensitivity, button size/opacity, five volumes | `test_controls.gd`, `test_menus3d.gd` |

## Skill, animation and VFX pass (filmed and fixed)

Every art, the dash, jump, sprint, foes' attacks, deaths and guardian moves
were filmed frame by frame (`--art=`, `--move=`, `--full` capture options) and
fixed where they looked wrong:

| Was | Now |
|---|---|
| Rune circles, pillars, slashes burned out to white | Saturated colour with soft halos; only line cores edge to white |
| Arcane Comet crossed the screen in one frame | Forms at the blade tip for 0.3 s, then flies (14 m/s) with a large core and trail |
| Phase Step left a capsule | Violet afterimages baked from her real pose along the blink |
| Blade Orbit: a white laser line from palm to blade | Larger blade, thin violet light trail, no line |
| Starfall lances barely visible; one crossing the lens became a purple slab | Crystal lances (glowing rim and core) fall straight down; each leaves a rune ring; the world dims while they fall; energy effects fade near the camera |
| Thick white torus on area hits | Thin coloured ground shockwave |
| Dodge: a roll ending in a kneeling slide | Upright sprint burst, leaning in, ghosts left behind her |
| Near foes: a knight's sword guard / arms held out | Her easy stance, blade floating ready |
| Sprint feet slid (rate cap) | Rate cap 1.75x matches 8.2 m/s |
| Falling pose crumpled | Tuck ~40% gentler |
| Pink skeletons, red hit tint, sinking corpses, squashed flat corpses | Ashen-violet Risen with glowing eyes (element colour on every skeleton foe), crisp white hit flash, the dead shrink into motes of light |
| Foes the camera passes through walled off the view | They dither away within 2.6 m of the camera (toon and outline passes) |
| **The Stormwing's arena was the Skybound start itself**: every sky journey woke the guardian on top of her (82 damage in the first second) | It waits on its own isle over its own bridge, on the crown's real height; a test checks no start is inside any arena |
| The Crystal Coast arena fell back to a ~40° hillside | The site search scores the whole arena floor and widens its rings; tested level and dry |
| Foe bolts: see-through bubbles, then grey grid-lined balls (the depth AO shading an opaque core) | Drawn as light: glow sprites with a white-hot core |
| Trails behind fast bolts were rows of beads | Ribbon trails (a camera-facing strip through recent positions) |
| Star lances read as frosted-glass panels, and squashed into a white cone on impact | Slim violet crystals of light that drain away where they struck |
| The Stormwing's near-white colour turned everything of it white under bloom | Electric blue |
| Arena runestones were grey boxes | Rough leaning menhirs with a glowing rune cut in each face |
| A flying guardian stayed above the top of the screen all fight | The camera pulls back and tilts to keep the guardian in frame (an offset on the player's own look) |
| One bolt hit tinted the whole screen red-pink | The hurt vignette stays at the screen's rim |
| The Thornmother and Tidewarden were the knight model flooded with one colour (a lime-green mannequin) | Costumed part by part: bark-bronze plate over moss cloth; steel-blue plate over sea teal |
| The Stormwing's dive slid down in its idle pose | It turns to its mark, stoops nose-down with a wind streak and levels out after the strike |
| Armed knights walked with a long blade stuck out ahead like a lance: the knight model's own built-in sword, held as well as the weapon they were given | The built-in sword is hidden when a foe has its own weapon; on the move the weapon is carried low by the leg (grip axis measured in the Walk and Jog clips) and returns to the ready grip to stand or strike |
| Flat translucent root-line bars | Glowing danger lanes that fill as the blow winds up, chevrons, a flash when it lands |
| Plain white damage numbers, torso-sized log drops | Title-font numbers (lilac, gold crits) that pop and drift; small hovering loot with a rarity glint |

### Honest notes
- 2048 px terrain textures, mipmaps and VRAM compression are set in the import files; memory on a real phone is unmeasured.
- The jungle is heavy for the software renderer used in captures; on-device frame rate is unmeasured.
- Google/Apple sign-in need their platform plugins and app credentials; until then those buttons explain that and do nothing.

## Full QA pass (island by island)

Every island was run with the real renderer and its full log read; the
whole suite was read for every engine and script error; an automated
collision audit (`tests/audit_collision.gd`) aimed rays at every
solid-looking thing near each start and guardian arena; each island's
first chapter, every guardian, death and the sky updrafts were played
end to end by new tests.

| Found | Fixed |
|---|---|
| ~80 engine errors on every launch: the animation libraries were stored compressed (Godot 4.4 logs one per clip), and compression made bones snap at page seams (a finger 0.9 rad, the hips 0.5 m in one frame) | Libraries rewritten uncompressed, every key copied exactly and checked against its source (`tools/decompress_anims.gd`) |
| 384 shader-compiler errors per run: samplers passed into functions (terrain, 2D light map) | Macro and taps/mix split |
| Skipping the arrival left its camera sweep running on a freed camera (an error every frame) | The arrival's tween is stopped on skip |
| A foe's bolt called back into its dead caster (script error) | Orphaned bolts fizzle; foe move timers are tied to the foe |
| Truncated save files raised an engine error on load; a profile could be written with no account | Both refused cleanly |
| Arch glass used Godot 3's `specular` (did nothing) | `metallic_specular` |
| **Collision**: guardian runestones, rune-shrine stones, crystal veins, starlit and world chests, crates, benches, flower pots, road lanterns, sky-bridge rails and the trees and crystals on the floating isles could all be walked through | All solid (`Solid` helper; regression `test_solid_props`). Bushes, ferns and flowers stay passable on purpose |
| **Death always woke her in the town square**, 1–2 km from any starting island | She wakes at the nearest safe place she knows (her island's landing, a discovered landmark or the town), its ground streamed in first |
| **A fall from a sky isle stranded her**: a glider drifted out of the updraft within a second and sank back down | Updrafts catch a glider well beyond the visible column and draw her round it; every Skybound column now climbs above its isle in 9–18 s (tested) |
| **Boulders on the Crystal Coast, the beach, the snow and round the sky isles drew as flat glowing white blobs** (traced with the harness: real geometry, not an effect; the rock pack's texture is twice the ground's brightness and full sun clipped it) | Each rock piece toned to weathered grey from its measured brightness; filmed before and after |
| The sky and coast chapters and two of the three guardians had no end-to-end test | `test_island_journeys` (sky and coast chapters, falls on every island, updrafts) and `test_guardian_fights` (every move of every phase, defeat recorded and saved) |

Still printed by the test run, and why: the container has no audio device
or vsync control. ("Parameter material is null" was not harmless noise as
first thought: the real renderer printed it too. Fixed in the mobile pass;
two lines remain, from `test_discovery` freeing the older 2D level at once
with `free()`, a test-only path.)

## Mobile pass (performance, collision, lighting, shaders, APK)

Download: **https://github.com/Max1081018/open_code/releases** (each push
that touches `godot/` builds a signed APK in GitHub Actions,
`.github/workflows/lanternbound-apk.yml`, and publishes it as a release).

| Change | Effect |
|---|---|
| 495 model and terrain textures import VRAM-compressed (ETC2 on Android, checked inside the built APK: 305 `.etc2.ctex`) | 4 to 8 bits a pixel on the GPU instead of 32; the APK stays ~245 MB because lossless WebP was already small on disk |
| Every packed character carries mesh LODs (`tools/lod_characters.gd`) | the 118k-triangle knight and 130k Warden drop detail with screen size |
| Rocks and solid scenery parts get mesh LODs; leaf cards thin out past 22 m in the vertex shader (never in the shadow pass) | canopies stay full up close, far trees cost less |
| Grass clumps: two lighter clumps for the far rings | grass 350k -> 213k triangles in the town view |
| Sun shafts: 12 jittered samples instead of 20 | same streaks, 40% fewer reads on a full-screen pass |
| Phones pick a preset by core count; mesh LOD threshold 2 px on mobile | |
| Enemy hit flash laid over the body only while it shows; a foe hands back its faded material copies before it is freed | an extra transparent pass per foe mesh is gone, and the renderer errors foes caused when freed ("material is null", 107 lines a test run) are gone |
| Collision: the Root Stair gates, the Sun Gate and the Shrine of the First Root were walk-through | solid (`Solid.gate`, `Solid.fountain`); audit on all four starts now reports only bushes, ferns and flowers (passable on purpose) and the floating starstone crystal |
| Lighting: low steep banks (river cuts, coast drops) smeared the grass texture down the face and read as blue streaks in shade | side-projected earthy rock; ambient takes a little more ground bounce so shaded faces are not sky-blue |
| Water shader | drifting caustics on the bed, per-channel absorption (red goes first), fine chop, the real sky gradient reflected and a sun glint that follows the sun |

Town view after the pass: about 1,030 draw calls and 1.85 M primitives by day
(1,078 at night with every lamp lit), down from 1,376 and 2.21 M.

## Measured performance (software renderer, High preset, 1280x720)

| Scene | Draw calls | Triangles | Lights |
|---|---|---|---|
| Greenwood town (before) | 1,660 | 2.39 M | 45 |
| Great Jungle start (before) | 1,646 | 2.69 M | 45 |
| Greenwood town (after the scenery budget) | 1,342 | 2.15 M | 45 |
| Great Jungle start (after the scenery budget) | 1,146 | 2.33 M | 45 |

The scenery budget (`Main3D.budget`) draws each realm, sky-isle, secret and
arena prop only within a distance that suits its size, and small props cast
no shadow.

These are above a comfortable budget for mid-range Android (roughly under 800
draw calls and 1 M triangles). The shadow pass (two splits) roughly doubles
the casters' draw calls, and grass blades and foliage carry most triangles.
Medium and Low presets cut view distance, grass and effects but were **not
measured** here.

## Next exact step

0. **Performance pass first**: bring High under ~800 draw calls and ~1 M
   triangles. Start with shadow casters (exclude grass and small props from
   the shadow pass), MultiMesh-batch the remaining per-prop meshes, and use
   visibility ranges on far foliage. Then measure Medium and Low.
1. On a real Android phone: install the release APK and measure frame rate in the
   jungle and town on Medium and High (AO and sun shafts on and off), and
   check the floating blade and touch layout by hand. Nothing here has run on
   a phone yet.
2. Guardian arenas: build each arena a proper floor (a ruined plaza) rather
   than a runestone ring alone (the Tidewarden's site is now level ground).
3. Animation: a dedicated falling clip and a sprint clip whose natural speed
   matches 8.2 m/s (the shared sprint still slides a little at full speed).

## Known issues

- **Not tested on a phone**: everything was verified headless (140+ tests)
  and with software-rendered captures. Real-device frame rate, memory, touch
  feel and audio are unmeasured.
- The software renderer used for captures is slow in the jungle (several
  minutes per frame); performance numbers from it say nothing about phones.
- Foot sliding was fixed by measurement and stills; it has not been judged in motion
  (video) — the gait rates may need a small visual tune.
- Sprint clip's natural speed (4.9 m/s) is far below sprint speed (8.2): played at the
  1.55× cap it still slides a little at full sprint.
- Fixed this pass (were live bugs): a Skybound start dropped her through the
  isle (spawned inside its crown); every foe's home post was the world origin;
  character meshes rebuilt with custom vertex channels silently failed to
  build; tree shadows were stippled; the arrival HUD could show.
