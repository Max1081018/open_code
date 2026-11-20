# Roadmap — Lanternbound

## Done and verified

Verified by headless tests (44) and by screenshot captures at 2340×1080.

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
- Performance budgets tested: light map ~1.5 ms, chunk load ~1.7 ms.

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
- **NPCs**: the guide's art is imported but she is not in the world.
- **Weather**: rain and snow particles.
- **Liquids** are static: digging under a pool does not drain it.
- **Furniture** beyond the crafting stations, chests and wardstones.
