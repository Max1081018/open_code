# Lanternbound 3D — migration plan

The 2.5D side-scroller becomes a third/first-person open-world survival adventure.
The 2D game stays in the repository (`scenes/main.tscn`, `scripts/level.gd`, …) until the
3D game covers its systems; the 3D game lives in `scenes/main3d.tscn` and `scripts/w3d/`.

## What carries over

| Kept | Why |
|---|---|
| `Items` autoload, recipes, `Inventory` | Item/recipe data is perspective-free |
| `Settings`, `Sfx`, `Story` (dialogue text, speakers) | Same game, same voice lines and story |
| Downloaded cast (`assets/models/heroes`, shared humanoid clip library) | Already real 3D, retargeted |
| 3D hand-held items (`assets/models/items`) | Already in a common grip frame |
| Asset credits (`ASSET_CATALOG.md`) | Extended with every new model |

Replaced: tile world, side camera, 2D level, cut-out rig, parallax, 2D light map, 2D HUD layout.

## Terrain: Terrain3D evaluated, custom streamed heightmap chosen

[Terrain3D](https://github.com/TokisanGames/Terrain3D) is excellent on desktop (clipmap LOD,
sculpting, foliage instancing), but: it is a C++ GDExtension whose Android build and
GL Compatibility support are marked experimental; its strengths are editor sculpting, which a
procedurally generated world does not use; and this project's automated visual tests run on a
software OpenGL renderer where an extension crash would block every test. A small GDScript
chunked heightmap (meshes built on worker threads, height-field colliders, splat-blended
material, per-chunk instanced foliage, streaming by distance) does what the game needs on every
renderer and stays fully testable. Revisit if hand-sculpted landmarks become the bottleneck.

## Stages (each ends in a commit with captures)

1. 3D player and camera: third-person spring-arm camera (collision, orbit, smoothing), first
   person (head camera, own body's arms and held item), walk/sprint/jump/fall/dodge/swim, stamina.
2. World: streamed terrain chunks (2 km square), biomes by noise (forest, dark forest, snow
   mountains, dry lands, volcanic, corrupted), rivers and lakes, instanced trees/rocks/grass,
   sky, sun, fog, water.
3. Combat: light/heavy combos, block, dodge i-frames, stamina, hit detection by shape sweeps,
   knockback, crits, enemy AI (skeletons, knights), boss (Warden) with phases.
4. Gathering and crafting: chop (trees fall and split into logs), mine (rocks crack, debris,
   ore), pick up, craft at stations, inventory and hotbar UI.
5. Building: grid-snapped foundations, walls, floors, roofs, doors, stairs from village kit parts;
   preview, rotation, validity, support.
6. NPCs and quests: village with the cast, dialogue, quest chain rebuilt for 3D goals.
7. Regions: per-biome props, enemies, resources, weather, lighting, music.
8. Wildlife, dungeons/caves, bosses, landmarks.
9. Main menu, settings, polish; voices (better TTS or none).
10. Performance (LOD, distances, instancing, shadows), Android build, automated capture tests.
