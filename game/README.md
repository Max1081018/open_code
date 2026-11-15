# Deepdelve

An original 2D tile-based survival game in Rust. Terraria-shaped — dig,
build, craft, fight — but drawn at roughly 2.5× Terraria's apparent scale so
it stays legible on a phone.

Original work: no Terraria assets, code, or content.

## Running it

```bash
cd game
cargo run -p deepdelve-app --release
```

For Android, see [ANDROID.md](ANDROID.md). **Read its status section first** —
the APK pipeline is scaffolded but has never been built end to end, because
the container this was developed in cannot reach Google's servers.

## Controls

| Input | Action |
|---|---|
| WASD / arrows | Move |
| Space | Jump |
| Left click | Dig, and swing at enemies |
| Right click | Place the held block |
| 1–4 | Switch hotbar slot |
| F1–F4 | Craft the listed recipe |
| B | Summon a boss (consumes a token) |
| F5 / F9 | Save / load |

On touch devices: a stick bottom-left steers, bottom-right jumps, the button
above it places blocks, and tapping anywhere else digs.

## Layout

```
game/
├── core/     engine-agnostic game logic — all of it tested headlessly
├── app/      thin Bevy frontend: rendering, input, camera
└── android/  Gradle project for the APK
```

The split is deliberate and load-bearing. The build container has no GPU, so
anything that lives in `core` can be verified and anything that lives in
`app` can only be eyeballed through screenshots. Game *rules* therefore live
in `core`, and `app` draws what core decides.

That boundary was worth enforcing: twice, logic that had drifted into the
frontend (enemy spawn eligibility, spawn placement) turned out to be wrong in
a way no test could catch until it moved into `core`.

## What's in core

| Module | What it does |
|---|---|
| `noise` | Deterministic value noise, 1-D and 2-D, hand-rolled |
| `world` | Tiles, seeded generation, caves, ore veins |
| `biome` | Tundra / plains / desert bands |
| `physics` | Gravity, walking, jumping, swept tile collision |
| `interact` | Mining with per-tile hardness, placement, reach |
| `item` | Item registry and stacking inventory |
| `craft` | Recipes, stations, all-or-nothing crafting |
| `enemy` | Four enemy types, chase AI, shared damage rules |
| `boss` | Four bosses with scripted phases |
| `spawn` | Depth and time-of-day spawn rules, placement search |
| `daynight` | Day-night cycle and sky brightness |
| `light` | Sky-light flood fill |
| `art` | Procedural tile textures and edge lighting |
| `tilemap` | Chunk compositing |
| `touch` | On-screen control geometry |
| `save` | Versioned, run-length-encoded save files |
| `png` | Dependency-free PNG encoder, for tooling |

`core` has no dependencies at all — not even for noise or PNG encoding — so
every property the game relies on is pinned by tests in this repo.

## Tests

```bash
cd game && cargo test
```

218 tests, all green, no warnings. Written test-first throughout.

## Looking at it without a GPU

```bash
# ASCII cross-section of a generated world
cargo run --example ascii_map -- 7 118 44

# PNG of a world slice at the real in-game scale, with lighting
cargo run --example render_world -- out.png 7 26

# A frame from the actual game, headless
DEEPDELVE_SHOT=shot.png cargo run -p deepdelve-app
```

Useful environment variables: `DEEPDELVE_SHOT` (capture a frame and exit),
`DEEPDELVE_SHOT_FRAME`, `DEEPDELVE_RES=2340x1080`, `DEEPDELVE_START_NIGHT`.

## Known gaps

- **The APK has never been built.** See ANDROID.md.
- **No torches.** Caves are lit only by what reaches them from the sky, so
  deep exploration is dark. Placeable light sources are the obvious next step
  and the light propagation already supports them.
- **Crafting stations are a field kit.** The player is treated as always
  having a furnace and anvil to hand; placeable stations would replace that
  with a proximity check.
- **Enemies and bosses are coloured rectangles.** The tile art is procedural
  and finished; creature sprites are not.
- **Performance is unmeasured on a phone.** The architecture is built around
  it — one draw call per chunk, resident chunks only — but no hardware has
  run it.
