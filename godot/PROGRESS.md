# Progress report — Lanternbound

Last updated on branch `ccr-60ac94c6-dyqxhw`, after the session that started from `eeb5b35`
(see `git log eeb5b35..HEAD`).
Engine: Godot 4.4.1, GL Compatibility renderer, Android-first.

## Working and verified (tests: 95 pass; cave soak 4,000 frames and 3 tutorial bot runs, no script errors)

| Area | State | How verified |
|---|---|---|
| Characters | Jointed cut-out rig (Kenney Toon parts) for hero, NPCs, zombies, robots, bosses. Arms have elbows and two-bone IK. The hands are placed on the item, not the item in the hand | IK test (hand lands on target), filmstrips |
| Locomotion | Relaxed idle: breathing, weight shift, head drift, fidgets (look round, stretch). Distinct walk and run (stride, lean, arm swing, bounce scale with speed). Card turn (body narrows and flips), with the held item and shield narrowing too. Footsteps fire from the stride, so no sliding | Filmstrips: walk, run, turn |
| Item holding | Grips measured from each icon. Picks and axes swung two-handed (far hand on the handle, shoulders turn into the blow). Hammers, swords and torches one-handed. Shield in the far hand, brought in front to block. Lantern hangs on the belt as a pendulum | Filmstrips of pickaxe, axe, sword, hammer, torch, shield, block, planks, workbench, belt lantern. 3 equipment tests |
| Trees | Chopping stages: a notch that deepens, a lean away from the axe, a shudder, and a creak past half. Bark, leaf and splinter bursts on every blow. On the last blow the crown bursts into leaves and the trunk splits into wood chunks that tumble, bounce and settle into collectable wood | Filmstrips |
| Mining / combat feel | Debris per material (rock chips, crystal shards, earth). Hit-stop on sword hits (longer on criticals). Enemies squash on impact | Capture; time-scale recovery checked |
| Building | Placement ghost with reasons. Materials sound different going down (timber knock, stone thud). Hammers (wood, iron) take down placed objects and planks/brick tiles in one blow and refund them | Hammer test, placement test |
| Pickups | Drops glint at rest (in rarity colour when rare), shrink as they fly in, sparkle on collection, and climb in pitch through a haul | Pickup test |
| Audio | Surface footsteps (grass, stone, wood, snow). Anvil ring while forging. Creature snarl before attacks, grunts when hurt, body fall on death. Tree fall, thunder. A test checks every `Sfx.play` name has a file | Lengths/loudness only (no sound device) |
| Story | 4 voiced NPCs (Wren, Bram, Mira, and Tobin the travelling smith, a recoloured Bram). 5 main and 3 side quests. Tobin's "Tools of the Trade" teaches the hammer (craft one, knock down 3 built things, build 10, get his iron hammer). Old saves get quests added since | 11 quest tests incl. the tutorial and Tobin's quest played with real hammer blows |
| Tutorial | Plays through to the end by bot (`--action=tutorial`), 3 of 3 runs, about 2,200 frames. Fixed this session: the guide arrow vanished during "Mine stone" from 7 of 31 meadow positions; a pooled particle emitter freed with a felled tree errored | Bot runs, 2 regression tests |
| Enemies | 11 regular kinds + 2 bosses. New: the spitter (rooted in caves, gapes as a tell, lobs acid on an arc only with line of sight; shield or roll to answer it) and ladybugs in the meadow | Spit test (hits, shield, line of sight), cave soak |
| Caves | Stalactite clusters hang from rock, basalt and soil ceilings (cleared when the ceiling is dug), pebbles and mushrooms on floors | Captures |
| Map | Corner minimap: explored cells (fog of war, saved with the world), NPC dots, quest-target mark | Map test (reveal, save, old saves), capture |
| World, crafting, death, weather | As before: 2.5D foliage, light scatter, water/lava, thunderstorms, timed crafting with station sounds, death screen | Captures, tests |

## Not verified / not done

- **No real device** has run the game, and no APK has been built.
- **Audio is unheard**: there is no sound device here. Clips are checked by length and loudness only. Piper may mispronounce names.
- Robot keeps a front-facing head (accepted: it is a machine; no side view in the art).
- The belt lantern does not narrow during the card turn (it is small).
- Equipment slots for shield and lantern: the best shield carried is used automatically.
- A full-screen map (the minimap only), armour and flowing liquids: not done.

## Exact next tasks

1. Underground lighting: colour grading per depth (caves are dressed now).
2. A second region of story content (Bram's mine as a built location, more voiced lines).
   Re-run `python3 tools/bake_voices.py` after editing `assets/story/dialogue.json`.
3. Equipment slots for shield and lantern.
4. Enemy variety: a cave bat (spitter done).
5. Performance pass on the foliage shader and light scatter at Low/Medium.

## How to check things

- Tests: `godot --headless --path godot -s res://tests/run_tests.gd [-- name_filter]`
- New `class_name` scripts need `godot --headless --path godot --import` once.
- Soak: `xvfb-run -a godot --path godot --rendering-driver opengl3 --fixed-fps 60 -- --shot=out.png --touch --frames=6000 --action=soak --seed=7`, then grep the log for `SCRIPT ERROR`.
- Captures: `--x=s-30` stands the player 30 columns left of spawn; see also `--action`, `--scenario`, `--hold`, `--strip` (with `--every=N` frame spacing), `--story`, `--hover`, `--debug` in `scripts/main.gd`.
- Rig layout after adding a character: `python3 tools/build_rig.py` (about 2.5 minutes).
