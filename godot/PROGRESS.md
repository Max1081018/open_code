# Progress report — Lanternbound

Last updated at commit after `10ba25e` on branch `ccr-60ac94c6-dyqxhw`.
Engine: Godot 4.4.1, GL Compatibility renderer, Android-first.

## Working and verified (tests: 76 pass; soak bot: 3 runs, 4.6 min of play, no script errors)

| Area | State | How verified |
|---|---|---|
| Characters | Jointed cut-out rig (Kenney Toon parts) for hero, NPCs, zombies, robots, bosses; strides matched to speed, arm swing, breathing, three-quarter head, expressions, death topple | Filmstrips at fixed 60 fps |
| Item holding | Fist-anchored grips measured from art, item in front of arm and under the fingers, behind the head on overhead wind-ups; mine / chop / slash / place curves; torch with flame; belt lantern; shields | Filmstrips, 8 equipment tests |
| Story | 3 voiced NPCs (Wren, Bram, Mira); 5 main + 2 side quests; tutorial taught through play; tracker; guide arrow; save-compatible | 7 quest tests incl. full tutorial play-through, captures |
| Voices | Piper TTS baked offline to Ogg (30 lines), one voice per NPC, subtitles timed to audio, music ducking, Voices volume | Every line checked for real length and loudness; not listened to |
| Gathering | Trees topple and scatter wood; material-specific mining sounds; impact-timed effects | Captures |
| Building | Placement ghost with reasons; one validity check for ghost and build; can't build into bodies | Placement test (incl. straddling) |
| Crafting | Timed jobs with station sounds and work animation; progress fill | 4 crafting tests, capture |
| World | 2.5D foliage shader per species, bevelled terrain, light-directed relief, foreground layer, coloured light scatter, water/lava shaders, weather incl. thunderstorms, ambience beds | Captures |
| Combat | Fitted creature boxes, front-only sword reach, telegraphed enemy attacks, shield block | 4 collision tests |
| Death | Death screen with Rise countdown | Capture |

## Tutorial verified end to end by a bot

`--action=tutorial` plays First Light through the real game with real
inputs, reading only the quest tracker. It now finishes all eight steps in
about 1,600 frames. Getting there found and fixed six real problems:

1. The tutorial spent all its wood on the bench and never said the axe
   needs eight more (now asks for 18; the tracker names what is missing).
2. Rock lay under many tiles of soil near the start (new worlds get a
   surface outcrop; tested on five seeds).
3. Creatures harried the player during the tutorial (the surface is safe
   until First Light is done).
4. The jump (2.2 tiles) could not clear the 3-tile ledges common in the
   terrain (now about 3.2 tiles).
5. Away from the bench, nothing pointed the way back (the guide arrow now
   points to the station a crafting step needs).
6. A block could be built into the player's own body (soak bot).

## Not verified / not done

- **No real device** has run the game; no APK has been built (future deliverable).
- **Audio is unheard**: there is no sound device here. Clips are checked by
  length/loudness only. Piper may mispronounce names.
- Robot keeps a front-facing head (its three-quarter cut lost the face).
- Running vs walking as separate gaits, pick-up animation:
  not done (the brief asks for them).
- Inventory: drag and drop, rarity, sort and richer details are done; equipment slots (shield/lantern) are not:
  the best shield carried is used automatically.
- More NPCs/quests, map/minimap, armour, liquids flowing: not done.

## Exact next tasks

1. (done: dodge roll) Running gait above walking speed; pick-up gesture.
2. Equipment slots for shield and lantern (drag and drop, rarity, sort done).
3. (done: pooled bursts, enemy death finish) Material chips per tile type.
4. A second region of story content (Bram's mine as a built location,
   more voiced lines; re-run `python3 tools/bake_voices.py`).
5. Performance pass on the foliage shader and light scatter at Low/Medium.

## How to check things

- Tests: `godot --headless --path godot -s res://tests/run_tests.gd`
- Soak: `xvfb-run -a godot --path godot --rendering-driver opengl3 --fixed-fps 60 -- --shot=out.png --touch --frames=6000 --action=soak --seed=7`, then grep the log for `SCRIPT ERROR`.
- Captures: see `--action`, `--scenario`, `--hold`, `--strip`, `--story`, `--hover`, `--debug` in `scripts/main.gd`.
