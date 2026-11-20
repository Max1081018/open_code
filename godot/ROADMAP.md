# Roadmap — Lanternbound

## Done and verified

Verified by headless tests (76) and a gameplay soak bot (`--action=soak`) and by screenshot captures at 2340×1080.

- World: 640×360 tiles, three surface biomes, soil/rock/basalt layers,
  caves and shafts, crystal hollows, contained water and lava pools, brick
  ruins with loot and spawners, the boss vault, the geode, the cottage.
- Rendering: autotiled terrain with 9-slice edges, background walls, ore
  overlays, chunk streaming, coloured tile light map (sky, torches, lava,
  glowshards, lantern), four fogged parallax depth layers, mist, light
  shafts, motes, fireflies, sun, moon and stars, final grade, day/night.
- Player: full animation set, step-up, coyote time, jump buffering,
  digging with tiered tools, chopping, building, melee with auto-aim,
  eating, the lantern and the dark's damage, death and respawn.
- Creatures: twelve kinds across biomes and depths, shades tied to
  darkness, ruin spawners, two bosses with enrage phases and minions.
- Items: 50 items, 26 recipes over four stations, chests.
- UI: HUD, multitouch controls (floating stick, per-finger buttons),
  pack and crafting, chests, pause and settings, title screen, notices,
  pickup feed, boss bar.
- Audio: 13 recorded effects, 4 looped music tracks following location.
- Save/load through the real level; corrupt files refused.
- Graphics (overhaul stage A): Low/Medium/High/Ultra presets plus
  separate lighting, particles, shader effects, background, shadows,
  bloom and weather settings, all saved; terrain relief and detail
  shading; per-material palette; graded colour; soft contact shadows.
- Living world (stage B): animated water (waves, caustics, refraction on
  High+) and flowing lava; wind-swayed ground cover; drifting leaves;
  rain and snow that dim the sky; cave drips that splash; glowing,
  pulsing cave mushrooms and crystals that light their surroundings;
  underwater and lava-heat screen effects.
- Performance budgets tested: light map ~1.5 ms, chunk load ~1.7 ms.

- Story (see `assets/story/dialogue.json`, `scripts/story/`): three voiced
  NPCs (Wren, Old Bram, Mira) on the jointed rig; a main quest chain
  (First Light → Below the Roots → Ward the Dark → The Rusted Warden →
  Into the Hollows) and side quests; the tutorial is Wren talking the
  player through felling, gathering, crafting, placing, mining, upgrading
  and building. Quest tracker, guide arrow, save-compatible quest state.
- Voices: Piper TTS baked offline to Ogg (`tools/bake_voices.py`), a
  distinct voice per character, subtitles revealed with the audio, music
  ducking, a Voices volume slider.
- Characters: a jointed cut-out rig (Kenney Toon parts) for the hero,
  enemies and NPCs: strides matched to ground speed, arm swing, breathing,
  three-quarter head facing travel, expressions; items held in the fist
  with per-swing curves (mine, chop, slash, place), torch, belt lantern,
  shields that block from the front.
- Gathering and building: felled trees topple; placement ghost with
  reasons; timed crafting with station sounds; build effects.
- Weather: rain, snow, thunderstorms with lightning and thunder; ambience
  beds (forest, rain, cave) mixed by location.
- Collision: fitted creature boxes, swing reach in front only, telegraphed
  enemy attacks, a collision debug view.

## Not done yet

- **APK**: the export preset is ready; the build needs Godot's export
  templates and an Android SDK, and has not been run.
- **On-device testing**: nothing has run on a phone. Frame rate, touch
  feel and memory on real hardware are unmeasured.
- **Audio by ear**: no sound device here; clips are checked as data only.
- **Control layout editor**: control size, opacity and left-handed mode
  are configurable; dragging individual buttons is not yet exposed in UI
  (the setting `control_offsets` exists and is honoured).
- **Map screen** and a **minimap**.
- **Armour and accessories**: tools and weapons progress; armour does not
  exist yet.
- **Voices by ear**: lines are checked for length and loudness, not
  listened to; Piper output can mispronounce names.
- **More quests and NPCs**: three NPCs and seven quests so far.
- **Liquids** are static: digging under a pool does not drain it.
- **Furniture** beyond the crafting stations, chests and wardstones.
