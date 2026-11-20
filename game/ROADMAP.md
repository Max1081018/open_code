# Deepdelve Roadmap

Ordered by impact on how the game looks and plays, not by how interesting
the work is.

## Done

| # | Work | Notes |
|---|---|---|
| 1 | World generation | Terrain, caves, ore veins, three biomes |
| 2 | Player physics | Swept tile collision, no tunnelling |
| 3 | Mining and building | Per-tile hardness, reach limits |
| 4 | Items and inventory | Data-driven registry, stacking |
| 5 | Crafting | Recipes, stations, all-or-nothing commits |
| 6 | Enemies and combat | Four types, chase AI, shared damage rules |
| 7 | Bosses | Four bosses, scripted phases |
| 8 | Save/load | Versioned, run-length encoded, defensive |
| 9 | Chunked renderer | One draw call per chunk, streaming |
| 10 | Lighting | Sky-light flood fill, smooth falloff |
| 11 | Procedural tile art | Six variants per material, context edges |
| 12 | Touch controls | Thumb zones tested without a phone |
| 13 | Android pipeline | Scaffolded, **never built** — see ANDROID.md |
| 14 | Animation system | Nine clips, state machine, staggered blinking |
| 15 | Character sprites | Part-based bodies with animated faces |
| 16 | Animated cast in game | Player, enemies, bosses, lit by the world |
| 17 | Scenery | Trees, pines, cacti, bushes, rocks, fungus, crystals |

## Next

| # | Work | Why it matters |
|---|---|---|
| 18 | VFX | Mining debris, hit sparks, damage numbers, screen shake |
| 19 | Audio | Synthesised SFX and ambient beds; asset sites are unreachable |
| 20 | Parallax backdrop | The sky is a large flat area doing no work |
| 21 | Tile detail pass | Grass fringe onto neighbours, ore glint, surface pebbles |
| 22 | Torches and placed light | Caves are unlit; the light system already supports sources |
| 23 | Structures | Ruins, chests, sealed vaults — reasons to explore |
| 24 | NPCs and dialogue | Someone to find and talk to |
| 25 | Equipment and armour | Progression past the three pickaxes |
| 26 | Weather | Rain and snow per biome |
| 27 | On-device performance pass | Nothing has run on real hardware yet |

## Constraints that shape all of this

**Asset sites are unreachable.** Kenney, OpenGameArt, itch.io, CraftPix,
Freesound and Pixabay are all refused by this container's network policy;
only GitHub responds. All art is therefore generated in code. This is also
why audio will be synthesised rather than sampled.

**No GPU.** Rendering is verified by capturing frames headlessly under Xvfb
on llvmpipe. Anything that can live in `core` does, because `core` is
testable and the frontend can only be eyeballed.

**No Android NDK.** `dl.google.com` is blocked, so the APK has never been
built. The pipeline is written and its preflight passes up to that point.
