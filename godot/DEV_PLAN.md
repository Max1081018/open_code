# Lanternbound — development plan (complete-game pass)

Audit taken at commit d79e2d8 (all 125 tests passing). Engine: Godot 4.4.1, GL Compatibility, Jolt physics.

## What exists (and where)

| Area | State | Files |
|---|---|---|
| Boot | Straight into the title screen (`scenes/menu3d.tscn`); no loading screen, no accounts | `scripts/w3d/main_menu3d.gd` |
| World | 5 km procedural island streamed in 64 m chunks; 7 biomes; designed Ashlands; Greenwood town; sky isles; starstones; ambient life; regional weather; navmesh window | `open_world.gd`, `terrain_gen.gd`, `chunk_builder.gd`, `town.gd`, `ashlands.gd`, `sky_islands.gd`, `starstones.gd`, `weather3d.gd`, `nav_field.gd` |
| Player | Quaternius humanoid with outfits; AnimationTree gait + clip slots; combo, heavy, dodge, glide, swim, death, floating idle | `player3d.gd`, `character_kit.gd`, `float_pose.gd` |
| Combat | Moonblade, 3 arts gated by level, 14 foe kinds with styles, telegraphs, Warden boss | `play3d.gd`, `enemy3d.gd`, `arcana.gd`, `progression.gd` |
| Items | Inventory, equipment, crafting stations, shop, chests, starshards | `scripts/autoload/items.gd`, `scripts/game/inventory.gd` |
| Quests | Town quests + 10 regional quests; dialogue JSON; tracker | `quests3d.gd`, `assets/story/dialogue3d.json` |
| UI | HUD, backpack/craft/character/quests/map/settings/shop screens | `hud3d.gd`, `game_menu3d.gd` |
| Save | One file `user://starfall3d.save`, atomic write, version 1 | `save3d.gd` |
| Audio | Sfx autoload, music (title/explore/cave/boss), ambience (forest/cave/rain) | `scripts/autoload/sfx.gd` |
| Tests | 125 headless tests + capture harness | `tests/`, `main3d.gd` capture options |
| Legacy | The earlier 2D game (`scenes/main.tscn`, `scripts/world`, `scripts/ui`, `scripts/story`) — still tested, not reachable from the 3D build | — |

## Gaps found

- No loading screen, login, accounts, character select or starting-location choice.
- One global save; no per-account data.
- No designed starting areas beyond Greenwood; no large designed desert.
- No guided first-hour adventure beyond the town quests.
- Terrain3D, godot_voxel, Effekseer installed but unused.
- Audio buses: only Master/Music/SFX (no Ambient volume).
- Never run on an Android device.

## Tools

- Skills search: no matching extra skills available. Using Godot docs knowledge, the GodoMaster skill when needed.
- Higgsfield CLI: logged in, ~62 credits (used for 2D art: icons, key art, concept refs).
- Asset MCPs: 3D Valley (CC0 library), Soundza (sounds), sfxmint, 3D AI Studio (free plan).
- No phone, no audio device, software OpenGL only.

## Checklist (in order)

- [ ] P2 Startup: loading screen (real threaded progress), login/guest/dev accounts, Google/Apple provider interface (unconfigured → honest error), per-account profile + save
- [ ] P3 Character select (live 3D model, locked second slot) + three starting islands (Great Jungle, Skybound Isle, Crystal Coast) + spawn + starting quest
- [ ] P4 Great Sand Sea: large designed desert, sand shader, footprints, sinking, slow sand walking, kicked sand, sand weather
- [ ] P5 First adventure per island: arrival sequence, contextual tutorial, intro quest chain with relic and reward
- [ ] P6 Exploration secrets, new enemy types, damage numbers, trails, button feedback, audio buses, presets, automated playthrough, QC

See PROGRESS.md for what has been done and how it was checked.
