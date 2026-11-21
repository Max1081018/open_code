# Lanternbound

*Carry the only light there is.*

A 2D mining and exploration adventure for Android, built in **Godot 4.4**.
You dig, build and fight your way down through a procedurally generated
world — meadow, tundra and desert on the surface; soil, rock and the
crystal hollows below; the basalt deep dark at the bottom — carrying a
lantern that is your light, your clock and your lifeline.

## The signature mechanic: light is territory

Your lantern burns **glow**. Underground it drains, and its light shrinks
as it does, so running low is something you *see*. Run dry in the dark and
the dark bites — and **shades** come for you. Shades exist only in darkness:
they spawn where nothing is lit, pass through rock, and burn in strong light.

So light becomes the thing you build:

- **Torches** (wood + coal) make permanent safe pockets: nothing spawns near them.
- **Wardstones** (stone, glowshards, a ruby) refill your lantern, hold back the
  dark and become your respawn point. Planting a line of them is how the
  depths are claimed.
- **Glowshards** grow in the Crystal Hollows: they refill the lantern, craft
  Glow Flasks, and forge the top tier of tools.
- **Lumen Cores**, guarded by the two bosses, raise your lantern a tier —
  brighter, longer-lasting, and the deep dark's extra drain eases. Without
  them the basalt depths are survivable only in short dives.

Every system feeds the next: exploring finds ore and shards; ore makes
tools that can break deeper rock; shards and stone make the light that lets
you stay down there; the bosses at the bottom make the light stronger.

## Playing

**Phone:** the stick floats to wherever your left thumb lands. Jump,
attack and interact sit under the right thumb; tap or hold anywhere in the
world to use what you're holding there (dig, place, eat). Tap a hotbar slot
to hold it; tap a selected food or flask again to use it. The bag button
opens your pack and crafting; pause has settings (graphics quality, volume,
control size and opacity, left-handed layout, camera zoom, shake, FPS).

**Desktop:** A/D move, Space jump, F attack, E interact, hold the mouse
to use, 1–8 hotbar, Tab pack, Esc pause.

Crafting needs stations: by hand (workbench, torches, campfire), at a
**workbench** (wooden tools, planks, chests, brick, the anvil), at an
**anvil** (metal tools, wardstones, glow flasks), and at a **campfire**
(cooking).

## Running it

```sh
godot --path godot                 # play (Godot 4.4.1)
godot/tests/run.sh          # all tests; also fails on any script error
```

### Screenshots without a person at the controls

`scripts/main.gd` has a capture mode used to inspect every screen:

```sh
xvfb-run godot --path godot --rendering-driver opengl3 --resolution 2340x1080 -- \
    --shot=out.png --frames=110 --time=0.4 --touch \
    [--scenario=cave|crystal|deep|ruin|cabin] [--action=dig|walk|jump|attack] \
    [--spawn=slime,zombie] [--boss=warden|gloam] [--panel=inventory|craft|chest|pause] \
    [--menu] [--give=iron_ore,coal]
```

## Android

`export_presets.cfg` holds an Android preset (arm64-v8a + armeabi-v7a,
landscape, immersive, ETC2/ASTC textures, no permissions). Building the APK
needs Godot's 4.4.1 export templates and an Android SDK with a debug
keystore configured in the editor; it has **not** been built yet.

The renderer is GL Compatibility, chosen for the widest range of Android
GPUs. Quality settings scale the light-map update rate (6/12/20 Hz),
particle counts, enemy cap and the post-process grade.

## Layout

```
project.godot, export_presets.cfg
scenes/main.tscn            boot scene
scripts/
  main.gd                   menu, game start, desktop input, capture mode
  level.gd                  builds and wires a running game
  autoload/                 Items (all items + recipes), Settings, Sfx, Game (saves)
  world/                    WorldData (model + generator), World (chunk streaming,
                            tiles, objects), LightMap, Atmosphere, ObjectArt
  actors/                   Player, Enemy (all creatures + bosses), Director
                            (spawning), ItemDrop, CharacterFrames, PlayerInput
  game/inventory.gd         slots, stacking, crafting
  ui/                       HUD, TouchControls, InventoryPanel, PauseMenu,
                            MainMenu, ItemSlot, UITheme
  fx/                       Effects (particles, damage numbers), Glow (bloom)
  shaders/                  sky, light rays, depth fog, final grade
tests/                      headless suites + runner
tools/                      build_assets.py, render_props.gd
assets/                     curated art, audio and fonts — see ASSET_CATALOG.md
```

## Performance

Measured in the test suite on a desktop core (a phone is roughly 3–4×
slower): a light-map update takes ~1.5 ms and runs 6–20 times a second;
a chunk loads in ~1.7 ms and at most three load per frame; world
generation takes under 2 s. Tiles stream in 16×16 chunks around the camera
and are dropped behind it, so only a few thousand of the 230,000 cells are
live at once.
